class ShizukuStatus {
  const ShizukuStatus({
    this.supported = true,
    this.running = false,
    this.granted = false,
    this.uid,
    this.version,
  });
  final bool supported;
  final bool running;
  final bool granted;
  final int? uid;
  final int? version;
  factory ShizukuStatus.fromMap(Map<Object?, Object?> value) => ShizukuStatus(
    supported: value['supported'] == true,
    running: value['running'] == true,
    granted: value['granted'] == true,
    uid: (value['uid'] as num?)?.toInt(),
    version: (value['version'] as num?)?.toInt(),
  );
}

class Device {
  const Device({
    required this.id,
    required this.name,
    required this.address,
    required this.local,
  });
  final String id;
  final String name;
  final String address;
  final bool local;
  factory Device.fromMap(Map<Object?, Object?> value) => Device(
    id: value['id']! as String,
    name: value['name']! as String,
    address: value['address']! as String,
    local: value['kind'] == 'local',
  );
}

class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.apkPath,
    required this.enabled,
    required this.system,
  });
  final String packageName;
  final String apkPath;
  final bool enabled;
  final bool system;
  factory InstalledApp.fromMap(Map<Object?, Object?> value) => InstalledApp(
    packageName: value['packageName']! as String,
    apkPath: value['apkPath']! as String,
    enabled: value['enabled'] == true,
    system: value['system'] == true,
  );
}

class RemoteFile {
  const RemoteFile({
    required this.name,
    required this.mode,
    required this.size,
    required this.modified,
  });
  final String name;
  final int mode;
  final int size;
  final int modified;
  bool get directory => (mode & 0xf000) == 0x4000;
  bool get symbolicLink => (mode & 0xf000) == 0xa000;
  factory RemoteFile.fromMap(Map<Object?, Object?> value) => RemoteFile(
    name: value['name']! as String,
    mode: (value['mode']! as num).toInt(),
    size: (value['size']! as num).toInt(),
    modified: (value['modified']! as num).toInt(),
  );
}

class MirrorInfo {
  const MirrorInfo({
    required this.textureId,
    required this.width,
    required this.height,
  });
  final int textureId;
  final int width;
  final int height;
  factory MirrorInfo.fromMap(Map<Object?, Object?> value) => MirrorInfo(
    textureId: (value['textureId']! as num).toInt(),
    width: (value['width']! as num).toInt(),
    height: (value['height']! as num).toInt(),
  );
  MirrorInfo resize(int width, int height) =>
      MirrorInfo(textureId: textureId, width: width, height: height);
}

String joinRemotePath(String directory, String name) {
  if (name.isEmpty ||
      name == '.' ||
      name == '..' ||
      name.contains('/') ||
      name.contains('\u0000')) {
    throw const FormatException('Invalid file name');
  }
  return '${directory == '/' ? '' : directory.replaceFirst(RegExp(r'/+$'), '')}/$name';
}

String parentRemotePath(String path) {
  final parts = path.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.length <= 1) return '/';
  return '/${parts.take(parts.length - 1).join('/')}';
}

String formatBytes(int size) {
  if (size < 1024) return '$size B';
  if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KiB';
  if (size < 1024 * 1024 * 1024)
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MiB';
  return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB';
}
