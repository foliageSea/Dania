package com.foliage.dania.toolbox

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.cert.Certificate
import java.security.cert.CertificateFactory
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Date
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class AdbIdentity(context: Context) {
    private val file = File(context.noBackupFilesDir, "adb-identity.enc")
    private val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private val alias = "dania.adb.identity"
    private var loaded: Pair<PrivateKey, Certificate>? = null

    @Synchronized fun get(): Pair<PrivateKey, Certificate> {
        loaded?.let { return it }
        val result = if (file.exists()) {
            val encrypted = file.readBytes()
            require(encrypted.size in 29..16384) { "Invalid ADB identity" }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, encryptionKey(), GCMParameterSpec(128, encrypted.copyOfRange(0, 12)))
            val data = cipher.doFinal(encrypted.copyOfRange(12, encrypted.size))
            DataInputStream(ByteArrayInputStream(data)).use { input ->
                val key = KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(
                    Protocols.readExactly(input, input.readInt())))
                val cert = CertificateFactory.getInstance("X.509").generateCertificate(ByteArrayInputStream(
                    Protocols.readExactly(input, input.readInt())))
                key to cert
            }
        } else generate()
        loaded = result
        return result
    }

    private fun encryptionKey(): SecretKey {
        if (!store.containsAlias(alias)) {
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
                init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256).build())
                generateKey()
            }
        }
        return store.getKey(alias, null) as SecretKey
    }

    private fun generate(): Pair<PrivateKey, Certificate> {
        val pair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        val now = System.currentTimeMillis()
        val name = X500Name("CN=Dania")
        val cert = JcaX509CertificateConverter().getCertificate(JcaX509v3CertificateBuilder(name,
            BigInteger(128, SecureRandom()), Date(now - 86400000), Date(now + 315360000000L), name, pair.public)
            .build(JcaContentSignerBuilder("SHA256withRSA").build(pair.private)))
        val bytes = ByteArrayOutputStream()
        DataOutputStream(bytes).use { output ->
            output.writeInt(pair.private.encoded.size)
            output.write(pair.private.encoded)
            output.writeInt(cert.encoded.size)
            output.write(cert.encoded)
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, encryptionKey())
        val temporary = File(file.parentFile, "adb-identity.pending")
        temporary.writeBytes(cipher.iv + cipher.doFinal(bytes.toByteArray()))
        check(temporary.renameTo(file)) { "Could not store ADB identity" }
        return pair.private to cert
    }

    @Synchronized fun reset() {
        loaded = null
        if (file.exists()) check(file.delete())
        if (store.containsAlias(alias)) store.deleteEntry(alias)
    }
}
