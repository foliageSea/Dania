package com.foliage.dania.toolbox

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.conscrypt.Conscrypt
import org.bouncycastle.jce.provider.BouncyCastleProvider
import org.json.JSONArray
import rikka.shizuku.Shizuku
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.File
import java.io.InputStream
import java.security.Security
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class ToolboxPlugin(private val activity: Activity, private val engine: FlutterEngine) : Closeable {
    private val main = Handler(Looper.getMainLooper())
    private val workers = Executors.newCachedThreadPool()
    private val timer = Executors.newScheduledThreadPool(1)
    private val identity = AdbIdentity(activity)
    private val backends = ConcurrentHashMap<String, AdbBackend>()
    private val devices = ConcurrentHashMap<String, Map<String, Any>>()
    private val operations = ConcurrentHashMap<String, Closeable>()
    private val mirrors = ConcurrentHashMap<String, ScrcpySession>()
    private val cancelled = ConcurrentHashMap.newKeySet<String>()
    private val methods = MethodChannel(engine.dartExecutor.binaryMessenger, "dania/toolbox")
    private val events = EventChannel(engine.dartExecutor.binaryMessenger, "dania/toolbox/events")
    @Volatile private var sink: EventChannel.EventSink? = null
    @Volatile private var service: IPrivilegedService? = null
    @Volatile private var closed = false
    private var pendingExport: Pair<File, MethodChannel.Result>? = null
    private var binding: CompletableFuture<IPrivilegedService>? = null
    private val serviceArgs = Shizuku.UserServiceArgs(ComponentName(activity, PrivilegedService::class.java))
        .processNameSuffix("toolbox").tag("dania-toolbox").version(2).daemon(false).debuggable(false)

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            service = IPrivilegedService.Stub.asInterface(binder)
            service?.let { binding?.complete(it) }
            emit(mapOf("type" to "devices"))
        }
        override fun onServiceDisconnected(name: ComponentName?) {
            service = null
            binding = null
            emit(mapOf("type" to "devices"))
        }
    }
    private val received = Shizuku.OnBinderReceivedListener { emit(mapOf("type" to "shizuku")) }
    private val dead = Shizuku.OnBinderDeadListener {
        service = null
        binding?.completeExceptionally(IllegalStateException("Shizuku disconnected"))
        binding = null
        emit(mapOf("type" to "shizuku"))
        emit(mapOf("type" to "devices"))
    }
    private val permission = Shizuku.OnRequestPermissionResultListener { _, _ -> emit(mapOf("type" to "shizuku")) }

    init {
        Security.insertProviderAt(Conscrypt.newProvider(), 1)
        if (Security.getProvider("BC") == null) Security.addProvider(BouncyCastleProvider())
        Shizuku.addBinderReceivedListenerSticky(received)
        Shizuku.addBinderDeadListener(dead)
        Shizuku.addRequestPermissionResultListener(permission)
        methods.setMethodCallHandler(::handle)
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) { sink = eventSink }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        timer.scheduleWithFixedDelay({
            if (!closed) backends.forEach { (id, backend) ->
                if (!backend.isConnected) {
                    disconnect(id)
                    emit(mapOf("type" to "devices"))
                }
            }
        }, 2, 2, TimeUnit.SECONDS)
        File(activity.cacheDir, "toolbox").listFiles()?.filter {
            it.isFile && it.lastModified() < System.currentTimeMillis() - 86400000
        }?.forEach { it.delete() }
    }

    fun emit(event: Map<String, Any?>) { main.post { if (!closed) sink?.success(event) } }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (closed) { result.error("disconnected", "Toolbox closed", null); return }
        if (call.method == "exportFile") {
            try {
                check(pendingExport == null) { "Another save dialog is open" }
                val file = File(text(call, "localPath")).canonicalFile
                check(file.isFile && file.path.startsWith(File(activity.cacheDir, "toolbox").canonicalPath + "/")) { "Invalid download" }
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("application/octet-stream").putExtra(Intent.EXTRA_TITLE, text(call, "name"))
                pendingExport = file to result
                activity.startActivityForResult(intent, 4812)
            } catch (e: Exception) { pendingExport = null; result.error("save", e.message, null) }
            return
        }
        if (call.method == "mirrorTouch" || call.method == "mirrorKey") {
            try {
                val mirror = mirrors[text(call, "deviceId")] ?: throw IllegalStateException("Mirroring stopped")
                if (call.method == "mirrorKey") mirror.key(number(call, "keyCode"))
                else mirror.touch(number(call, "action"), call.argument<Number>("pointer")?.toLong() ?: 0,
                    number(call, "x"), number(call, "y"), number(call, "width"), number(call, "height"))
                result.success(null)
            } catch (e: Exception) { result.error("control", e.message, null) }
            return
        }
        if (call.method == "authorize") {
            try {
                check(Shizuku.pingBinder()) { "Shizuku is not running" }
                if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) Shizuku.requestPermission(44)
                result.success(null)
            } catch (e: Exception) { result.error("shizuku", e.message, null) }
            return
        }
        if (call.method == "openShizuku") {
            val intent = activity.packageManager.getLaunchIntentForPackage("moe.shizuku.privileged.api")
            if (intent == null) result.error("notInstalled", "Shizuku is not installed", null)
            else { activity.startActivity(intent); result.success(null) }
            return
        }
        if (call.method == "startMirror") {
            val producer = engine.renderer.createSurfaceProducer()
            workers.execute {
                val completed = AtomicBoolean(false)
                var mirror: ScrcpySession? = null
                try {
                    val id = text(call, "deviceId")
                    val mirrorId = text(call, "mirrorId")
                    check(id != "local") { "Mirroring requires a remote ADB device" }
                    stopMirror(id)
                    val session = ScrcpySession(mirrorId, activity, backend(id), producer, main,
                        { event -> emit(event + mapOf("deviceId" to id, "mirrorId" to mirrorId)) })
                    mirror = session
                    mirrors[id] = session
                    val deadline = timer.schedule({
                        if (completed.compareAndSet(false, true)) {
                            main.post { result.error("mirrorTimeout", "Screen control startup timed out", null) }
                            mirrors.remove(id, session)
                            session.timeout()
                        }
                    }, 30, TimeUnit.SECONDS)
                    try {
                        val info = session.start(number(call, "maxSize", 1280), number(call, "bitRate", 4000000))
                        if (completed.compareAndSet(false, true)) main.post { result.success(info) }
                    } finally { deadline.cancel(false) }
                } catch (e: Exception) {
                    val id = call.argument<String>("deviceId")
                    if (completed.compareAndSet(false, true)) main.post { result.error("mirror", e.message, null) }
                    if (mirror != null) {
                        if (id != null) mirrors.remove(id, mirror)
                        mirror.close()
                    } else main.post { producer.release() }
                }
            }
            return
        }
        workers.execute {
            try {
                val value: Any? = when (call.method) {
                    "status" -> status()
                    "devices" -> currentDevices()
                    "connectLocal" -> { local(); emit(mapOf("type" to "devices")); "local" }
                    "pair" -> {
                        val code = text(call, "code")
                        require(code.matches(Regex("[0-9]{6}"))) { "Pairing code must contain 6 digits" }
                        val manager = AdbBackend(identity)
                        check(manager.pair(host(call), port(call, "pairPort"), code)) { "Pairing failed" }
                        null
                    }
                    "connect" -> connect(call)
                    "disconnect" -> { disconnect(text(call, "deviceId")); emit(mapOf("type" to "devices")); null }
                    "info" -> execute(text(call, "deviceId"), "getprop ro.product.model; getprop ro.product.manufacturer; getprop ro.build.version.release; getprop ro.build.version.sdk; id; wm size; dumpsys battery")
                    "command" -> {
                        startCommand(text(call, "deviceId"), text(call, "operationId"), text(call, "command")); null
                    }
                    "cancel" -> {
                        val id = text(call, "operationId")
                        cancelled.add(id)
                        operations.remove(id)?.close()
                        null
                    }
                    "apps" -> listApps(text(call, "deviceId"))
                    "appAction" -> appAction(call)
                    "files" -> listFiles(text(call, "deviceId"), path(call))
                    "fileAction" -> fileAction(call)
                    "upload" -> upload(call)
                    "download" -> download(call)
                    "install" -> install(call)
                    "stopMirror" -> { stopMirror(text(call, "deviceId"), call.argument<String>("mirrorId")); null }
                    "mirrorTouch" -> {
                        mirrors[text(call, "deviceId")]?.touch(number(call, "action"),
                            call.argument<Number>("pointer")?.toLong() ?: 0,
                            number(call, "x"), number(call, "y"), number(call, "width"), number(call, "height")); null
                    }
                    "mirrorKey" -> { mirrors[text(call, "deviceId")]?.key(number(call, "keyCode")); null }
                    "resetIdentity" -> {
                        backends.keys.toList().forEach(::disconnect)
                        identity.reset()
                        emit(mapOf("type" to "devices")); null
                    }
                    else -> throw UnsupportedOperationException(call.method)
                }
                main.post { if (!closed) result.success(value) }
            } catch (error: Exception) {
                main.post { if (!closed) result.error(
                    if (error is SecurityException) "permission" else if (error is IllegalArgumentException) "invalidInput" else "operationFailed",
                    error.message ?: error.javaClass.simpleName, null) }
            }
        }
    }

    private fun status(): Map<String, Any?> {
        val running = Shizuku.pingBinder()
        return mapOf("supported" to true, "running" to running,
            "granted" to (running && runCatching { Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED }.getOrDefault(false)),
            "uid" to if (running) runCatching { Shizuku.getUid() }.getOrNull() else null,
            "version" to if (running) runCatching { Shizuku.getVersion() }.getOrNull() else null)
    }

    private fun currentDevices(): List<Map<String, Any>> {
        val result = devices.values.toMutableList()
        if (service?.asBinder()?.isBinderAlive == true) result.add(mapOf("id" to "local", "name" to android.os.Build.MODEL,
            "address" to "Shizuku", "kind" to "local"))
        return result
    }

    private fun local(): IPrivilegedService {
        service?.takeIf { it.asBinder().isBinderAlive }?.let { return it }
        check(Shizuku.pingBinder()) { "Shizuku is not running" }
        check(Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) { "Shizuku permission is required" }
        val future = CompletableFuture<IPrivilegedService>()
        main.post {
            if (binding == null || binding!!.isCompletedExceptionally) {
                binding = future
                runCatching { Shizuku.bindUserService(serviceArgs, connection) }.onFailure { future.completeExceptionally(it) }
            } else binding!!.whenComplete { value, error ->
                if (error != null) future.completeExceptionally(error) else future.complete(value)
            }
        }
        return future.get(15, TimeUnit.SECONDS)
    }

    private fun connect(call: MethodCall): String {
        val host = host(call)
        val port = port(call, "port")
        val manager = AdbBackend(identity)
        try {
            check(manager.connect(host, port)) { "Connection timed out" }
            val id = UUID.randomUUID().toString()
            val name = runRemote(manager, "getprop ro.product.model").second.trim().ifEmpty { host }
            backends[id] = manager
            devices[id] = mapOf("id" to id, "name" to name, "address" to "$host:$port", "kind" to "adb")
            emit(mapOf("type" to "devices"))
            return id
        } catch (e: Exception) { runCatching { manager.disconnect() }; throw e }
    }

    private fun backend(id: String): AdbBackend = backends[id]?.takeIf { it.isConnected }
        ?: throw IllegalStateException("ADB device disconnected")

    private fun disconnect(id: String) {
        stopMirror(id)
        if (id == "local") {
            main.post { runCatching { Shizuku.unbindUserService(serviceArgs, connection, true) }; service = null; binding = null }
        } else {
            devices.remove(id)
            backends.remove(id)?.let { runCatching { it.disconnect() } }
        }
    }

    private fun collect(input: InputStream): String {
        val bytes = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            check(bytes.size() + count <= 1024 * 1024) { "Command output exceeded 1 MiB" }
            bytes.write(buffer, 0, count)
        }
        return bytes.toString("UTF-8")
    }

    private fun runRemote(manager: AdbBackend, command: String): Pair<Int, String> {
        manager.command(command).use { stream ->
            val deadline = timer.schedule({ stream.close() }, 30, TimeUnit.SECONDS)
            try {
                val bytes = ByteArrayOutputStream()
                val exit = Protocols.readShell(stream.openInputStream()) { _, payload ->
                    check(bytes.size() + payload.size <= 1024 * 1024) { "Command output exceeded 1 MiB" }
                    bytes.write(payload)
                }
                return exit to bytes.toString("UTF-8")
            } finally { deadline.cancel(false) }
        }
    }

    private fun execute(id: String, command: String): String {
        val (exit, output) = if (id == "local") {
            val local = local()
            val task = UUID.randomUUID().toString()
            val descriptor = local.startCommand(task, command)
            val deadline = timer.schedule({ runCatching { local.cancelCommand(task) }; runCatching { descriptor.close() } }, 30, TimeUnit.SECONDS)
            try {
                val text = ParcelFileDescriptor.AutoCloseInputStream(descriptor).use(::collect)
                local.waitForCommand(task) to text
            } finally { deadline.cancel(false); runCatching { local.cancelCommand(task) } }
        } else runRemote(backend(id), command)
        check(exit == 0) { output.trim().take(2000).ifEmpty { "Command failed ($exit)" } }
        return output
    }

    private fun startCommand(device: String, id: String, command: String) {
        require(command.isNotBlank() && command.length <= 32768 && !command.contains('\u0000'))
        check(!operations.containsKey(id)) { "Operation already exists" }
        workers.execute {
            var resource: Closeable? = null
            try {
                val exit: Int
                if (device == "local") {
                    val local = local()
                    val descriptor = local.startCommand(id, command)
                    resource = Closeable { runCatching { local.cancelCommand(id) }; descriptor.close() }
                    register(id, resource)
                    ParcelFileDescriptor.AutoCloseInputStream(descriptor).bufferedReader().use { reader ->
                        val chars = CharArray(4096)
                        while (true) {
                            val count = reader.read(chars)
                            if (count < 0) break
                            emit(mapOf("type" to "command", "id" to id, "text" to String(chars, 0, count)))
                        }
                    }
                    exit = local.waitForCommand(id)
                } else {
                    val stream = backend(device).command(command)
                    resource = stream
                    register(id, stream)
                    exit = Protocols.readShell(stream.openInputStream()) { kind, payload ->
                        emit(mapOf("type" to "command", "id" to id, "bytes" to payload, "stderr" to (kind == 2)))
                    }
                }
                emit(mapOf("type" to "command", "id" to id, "exitCode" to exit, "cancelled" to cancelled.contains(id)))
            } catch (e: Exception) {
                emit(mapOf("type" to "command", "id" to id, "error" to (e.message ?: "Command failed"), "cancelled" to cancelled.contains(id)))
            } finally { operations.remove(id); cancelled.remove(id); runCatching { resource?.close() } }
        }
    }

    private fun register(id: String, resource: Closeable) {
        operations[id] = resource
        if (closed || cancelled.contains(id)) { resource.close(); throw IllegalStateException("Cancelled") }
    }

    private fun listApps(device: String): List<Map<String, Any>> {
        val disabled = execute(device, "pm list packages -d --user 0").lineSequence()
            .filter { it.startsWith("package:") }.map { it.removePrefix("package:").trim() }.toSet()
        val system = execute(device, "pm list packages -s --user 0").lineSequence()
            .filter { it.startsWith("package:") }.map { it.removePrefix("package:").trim() }.toSet()
        return execute(device, "pm list packages -f --user 0").lineSequence().filter { it.startsWith("package:") }.mapNotNull { line ->
            val index = line.lastIndexOf('=')
            if (index < 0) null else {
                val name = line.substring(index + 1).trim()
                mapOf("packageName" to name, "apkPath" to line.substring(8, index), "enabled" to !disabled.contains(name),
                    "system" to system.contains(name))
            }
        }.toList()
    }

    private fun appAction(call: MethodCall): String {
        val name = text(call, "packageName")
        require(name.matches(Regex("[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)*"))) { "Invalid package name" }
        val q = Protocols.quote(name)
        val command = when (text(call, "action")) {
            "details" -> "dumpsys package $q"
            "enable" -> "pm enable --user 0 $q"
            "disable" -> "pm disable-user --user 0 $q"
            "stop" -> "am force-stop --user 0 $q"
            "uninstall" -> "pm uninstall --user 0 $q"
            "grant", "revoke" -> {
                val permission = text(call, "permission")
                require(permission.matches(Regex("[A-Za-z0-9_.]+")))
                "pm ${text(call, "action")} --user 0 $q ${Protocols.quote(permission)}"
            }
            else -> throw IllegalArgumentException("Invalid app action")
        }
        return execute(text(call, "deviceId"), command).also {
            check(!it.trim().startsWith("Failure") && !it.contains("Exception occurred")) { it.take(2000) }
        }
    }

    private fun listFiles(device: String, path: String): List<Map<String, Any>> {
        if (device != "local") return AdbSync(backend(device).openStream("sync:")).use { it.list(path) }
        val array = JSONArray(local().listFiles(path))
        return (0 until array.length()).map { i ->
            val entry = array.getJSONObject(i)
            mapOf("name" to entry.getString("name"), "mode" to entry.getInt("mode"), "size" to entry.getLong("size"),
                "modified" to entry.getLong("modified"))
        }
    }

    private fun fileAction(call: MethodCall): String {
        val path = path(call)
        require(path !in setOf("/", "/sdcard", "/storage", "/storage/emulated", "/storage/emulated/0",
            "/data", "/system", "/vendor", "/product", "/data/local", "/data/local/tmp")) { "Protected directory" }
        val command = when (text(call, "action")) {
            "mkdir" -> "mkdir -- ${Protocols.quote(path)}"
            "rename" -> "mv -n -- ${Protocols.quote(path)} ${Protocols.quote(path(call, "destination"))}"
            "delete" -> "rm -r -- ${Protocols.quote(path)}"
            else -> throw IllegalArgumentException("Invalid file action")
        }
        return execute(text(call, "deviceId"), command)
    }

    private fun progress(id: String): (Long) -> Unit {
        var last = 0L
        return { done ->
            check(!cancelled.contains(id)) { "Cancelled" }
            val now = System.currentTimeMillis()
            if (now - last >= 100) { emit(mapOf("type" to "transfer", "id" to id, "done" to done)); last = now }
        }
    }

    private fun upload(call: MethodCall): Any? {
        val id = text(call, "operationId")
        try {
            push(text(call, "deviceId"), path(call), File(text(call, "localPath")), id)
            return null
        } finally { operations.remove(id); cancelled.remove(id) }
    }

    private fun push(device: String, path: String, file: File, id: String) {
        file.inputStream().use { input ->
            if (device == "local") {
                val descriptor = local().openFile(path, true)
                register(id, descriptor)
                ParcelFileDescriptor.AutoCloseOutputStream(descriptor).use { output ->
                    val buffer = ByteArray(65536)
                    val report = progress(id)
                    var done = 0L
                    while (true) { val n = input.read(buffer); if (n < 0) break; output.write(buffer, 0, n); done += n; report(done) }
                }
            } else {
                AdbSync(backend(device).openStream("sync:")).use { sync ->
                    register(id, sync)
                    sync.push(path, input, progress(id))
                }
            }
        }
    }

    private fun download(call: MethodCall): String {
        val id = text(call, "operationId")
        val device = text(call, "deviceId")
        val path = path(call)
        val directory = File(activity.cacheDir, "toolbox").apply { mkdirs() }
        val filename = File(path).name.replace(Regex("[^\\p{L}\\p{N}._-]"), "_").take(100).ifEmpty { "download" }
        val file = File(directory, "${UUID.randomUUID()}-$filename")
        try {
            file.outputStream().use { output ->
                if (device == "local") {
                    val descriptor = local().openFile(path, false)
                    register(id, descriptor)
                    ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { input ->
                        val buffer = ByteArray(65536)
                        val report = progress(id)
                        var done = 0L
                        while (true) { val n = input.read(buffer); if (n < 0) break; output.write(buffer, 0, n); done += n; report(done) }
                    }
                } else AdbSync(backend(device).openStream("sync:")).use { sync ->
                    register(id, sync)
                    sync.pull(path, output, progress(id))
                }
            }
            return file.absolutePath
        } catch (e: Exception) { file.delete(); throw e }
        finally { operations.remove(id); cancelled.remove(id) }
    }

    private fun install(call: MethodCall): String {
        val device = text(call, "deviceId")
        val id = text(call, "operationId")
        val path = "/data/local/tmp/dania-${UUID.randomUUID()}.apk"
        try {
            push(device, path, File(text(call, "localPath")), id)
            check(!cancelled.contains(id)) { "Cancelled" }
            return execute(device, "pm install -r --user 0 ${Protocols.quote(path)}").also {
                check(it.trim() == "Success") { it.take(2000) }
            }
        } finally {
            operations.remove(id); cancelled.remove(id)
            runCatching { execute(device, "rm -f -- ${Protocols.quote(path)}") }
        }
    }

    fun stopMirrors() { mirrors.keys.toList().forEach { stopMirror(it) } }
    private fun stopMirror(id: String, mirrorId: String? = null) {
        val mirror = mirrors[id] ?: return
        if (mirrorId != null && mirror.mirrorId != mirrorId) return
        if (mirrors.remove(id, mirror)) mirror.close()
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != 4812) return false
        val pending = pendingExport ?: return true
        pendingExport = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { pending.second.success(false); return true }
        workers.execute {
            try {
                val output = activity.contentResolver.openOutputStream(uri) ?: throw IllegalStateException("Cannot save document")
                output.use { destination -> pending.first.inputStream().use { it.copyTo(destination) } }
                main.post { pending.second.success(true) }
            } catch (e: Exception) { main.post { pending.second.error("save", e.message, null) } }
        }
        return true
    }

    override fun close() {
        closed = true
        pendingExport?.second?.error("disconnected", "Toolbox closed", null)
        pendingExport = null
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
        Shizuku.removeBinderReceivedListener(received)
        Shizuku.removeBinderDeadListener(dead)
        Shizuku.removeRequestPermissionResultListener(permission)
        stopMirrors()
        operations.values.forEach { runCatching { it.close() } }
        operations.clear()
        backends.values.forEach { runCatching { it.disconnect() } }
        backends.clear()
        runCatching { if (Shizuku.pingBinder()) Shizuku.unbindUserService(serviceArgs, connection, true) }
        timer.shutdownNow()
        workers.shutdownNow()
    }

    private fun text(call: MethodCall, key: String): String = call.argument<String>(key)
        ?: throw IllegalArgumentException("Missing $key")
    private fun number(call: MethodCall, key: String, default: Int = 0): Int = call.argument<Number>(key)?.toInt() ?: default
    private fun port(call: MethodCall, key: String): Int = number(call, key).also { require(it in 1..65535) { "Invalid port" } }
    private fun host(call: MethodCall): String = text(call, "host").trim().also {
        require(it.isNotEmpty() && it.length <= 253 && !it.any { c -> c.isWhitespace() || c == '/' || c == '\u0000' }) { "Invalid host" }
    }
    private fun path(call: MethodCall, key: String = "path"): String {
        val value = text(call, key)
        require(value.startsWith('/') && !value.contains('\u0000') && value.toByteArray().size <= 4096 && !value.split('/').contains("..")) { "Invalid absolute path" }
        return "/" + value.split('/').filter { it.isNotEmpty() && it != "." }.joinToString("/")
    }
}
