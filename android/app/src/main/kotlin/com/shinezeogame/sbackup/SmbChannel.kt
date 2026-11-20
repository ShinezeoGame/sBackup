package com.shinezeogame.sbackup

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.hierynomus.msdtyp.AccessMask
import com.hierynomus.mserref.NtStatus
import com.hierynomus.mssmb2.SMB2CreateDisposition
import com.hierynomus.mssmb2.SMB2ShareAccess
import com.hierynomus.mssmb2.SMBApiException
import com.hierynomus.smbj.SMBClient
import com.hierynomus.smbj.SmbConfig
import com.hierynomus.smbj.auth.AuthenticationContext
import com.hierynomus.smbj.common.SMBRuntimeException
import com.hierynomus.smbj.connection.Connection
import com.hierynomus.smbj.session.Session
import com.hierynomus.smbj.share.DiskShare
import com.hierynomus.smbj.share.File
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.EnumSet
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Le NAS en partage Windows (SMB 2/3, bibliothèque smbj), côté Android. Côté Dart :
 * `lib/platform/smb_destination.dart`, qui implémente `Destination`.
 *
 * Chemins reçus : relatifs au dossier de destination, avec « / ». Aucune méthode ne
 * supprime quoi que ce soit ; le renommage refuse d'écraser (`replaceIfExist = false`).
 * Tout se passe sur un fil dédié, une opération à la fois ; les réponses reviennent sur le
 * fil principal.
 */
class SmbChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()

    private var client: SMBClient? = null
    private var connection: Connection? = null
    private var session: Session? = null
    private var share: DiskShare? = null
    private var root = ""

    // Fichiers ouverts en écriture ou en lecture, par numéro.
    private val files = HashMap<Int, File>()
    private var nextHandle = 1

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        worker.execute {
            try {
                val value = handle(call)
                main.post { result.success(value) }
            } catch (e: Throwable) {
                val (code, message) = classify(e)
                main.post { result.error(code, message, null) }
            }
        }
    }

    private fun handle(call: MethodCall): Any? = when (call.method) {
        "ouvrir" -> {
            open(
                host = call.argument<String>("hote")!!,
                shareName = call.argument<String>("partage")!!,
                folder = call.argument<String>("dossier") ?: "",
                user = call.argument<String>("utilisateur") ?: "",
            )
            null
        }
        "fermer" -> {
            close()
            null
        }
        "taille" -> size(path(call))
        "creerDossiers" -> {
            makeDirs(path(call))
            null
        }
        "ouvrirEcriture" -> {
            val target = path(call)
            val append = call.argument<Boolean>("ajout") ?: false
            val disposition = if (append) SMB2CreateDisposition.FILE_OPEN_IF else SMB2CreateDisposition.FILE_OVERWRITE_IF
            val file = disk().openFile(
                target,
                EnumSet.of(AccessMask.GENERIC_WRITE, AccessMask.GENERIC_READ),
                null,
                EnumSet.of(SMB2ShareAccess.FILE_SHARE_READ),
                disposition,
                null,
            )
            register(file)
        }
        "ecrireMorceau" -> {
            val file = files[call.argument<Int>("id")!!] ?: throw IllegalStateException("Fichier fermé")
            val bytes = call.argument<ByteArray>("octets")!!
            val offset = (call.argument<Number>("position")!!).toLong()
            var written = 0L
            while (written < bytes.size) {
                written += file.write(bytes.copyOfRange(written.toInt(), bytes.size), offset + written)
            }
            null
        }
        "ouvrirLecture" -> {
            val file = disk().openFile(
                path(call),
                EnumSet.of(AccessMask.GENERIC_READ),
                null,
                EnumSet.of(SMB2ShareAccess.FILE_SHARE_READ),
                SMB2CreateDisposition.FILE_OPEN,
                null,
            )
            register(file)
        }
        "lireMorceau" -> {
            val file = files[call.argument<Int>("id")!!] ?: throw IllegalStateException("Fichier fermé")
            val offset = (call.argument<Number>("position")!!).toLong()
            val buffer = ByteArray(call.argument<Int>("taille") ?: CHUNK)
            val read = file.read(buffer, offset)
            if (read <= 0) ByteArray(0) else buffer.copyOf(read)
        }
        "fermerFichier" -> {
            files.remove(call.argument<Int>("id")!!)?.close()
            null
        }
        "renommer" -> rename(path(call, "de"), path(call, "vers"))
        "enregistrerMotDePasse" -> {
            SecretStore.save(context, call.argument<String>("motDePasse") ?: "")
            null
        }
        "motDePasseEnregistre" -> SecretStore.load(context).isNotEmpty()
        else -> throw UnsupportedOperationException(call.method)
    }

    private fun open(host: String, shareName: String, folder: String, user: String) {
        close()
        val config = SmbConfig.builder()
            .withTimeout(60, TimeUnit.SECONDS)
            .withSoTimeout(90, TimeUnit.SECONDS)
            .build()
        val newClient = SMBClient(config)
        client = newClient
        val newConnection = newClient.connect(host.trim())
        connection = newConnection
        val password = SecretStore.load(context)
        val newSession = newConnection.authenticate(AuthenticationContext(user.trim(), password.toCharArray(), null))
        session = newSession
        share = newSession.connectShare(shareName.trim().trim('/', '\\')) as? DiskShare
            ?: throw SMBApiException(NtStatus.STATUS_BAD_NETWORK_NAME.value, null, "Pas un dossier partagé", null)
        root = smbPath(folder.trim().trim('/', '\\'))
        if (root.isNotEmpty()) makeDirs("")
    }

    private fun close() {
        files.values.forEach { runCatching { it.close() } }
        files.clear()
        runCatching { share?.close() }
        runCatching { session?.close() }
        runCatching { connection?.close() }
        runCatching { client?.close() }
        share = null
        session = null
        connection = null
        client = null
    }

    private fun size(target: String): Long? {
        val disk = disk()
        if (!disk.fileExists(target)) return null
        return disk.getFileInformation(target).standardInformation.endOfFile
    }

    /** Crée le dossier et ses parents (chemin relatif au dossier de destination). */
    private fun makeDirs(target: String) {
        val disk = disk()
        var current = ""
        for (part in target.split('\\').filter { it.isNotEmpty() }) {
            current = if (current.isEmpty()) part else "$current\\$part"
            if (!disk.folderExists(current)) disk.mkdir(current)
        }
    }

    /** Renomme sans jamais écraser : `false` si la cible existe déjà. */
    private fun rename(from: String, to: String): Boolean {
        val disk = disk()
        if (disk.fileExists(to) || disk.folderExists(to)) return false
        val file = disk.openFile(
            from,
            EnumSet.of(AccessMask.DELETE, AccessMask.GENERIC_READ),
            null,
            EnumSet.noneOf(SMB2ShareAccess::class.java),
            SMB2CreateDisposition.FILE_OPEN,
            null,
        )
        try {
            file.rename(to, false)
            return true
        } catch (e: SMBApiException) {
            if (e.status == NtStatus.STATUS_OBJECT_NAME_COLLISION) return false
            throw e
        } finally {
            file.close()
        }
    }

    private fun register(file: File): Int {
        val id = nextHandle++
        files[id] = file
        return id
    }

    private fun disk(): DiskShare = share ?: throw IllegalStateException("NAS non connecté")

    /** Chemin reçu (« 2026/11/a.jpg ») → chemin SMB complet dans le partage. */
    private fun path(call: MethodCall, key: String = "chemin"): String {
        val relative = smbPath(call.argument<String>(key) ?: "")
        return listOf(root, relative).filter { it.isNotEmpty() }.joinToString("\\")
    }

    private fun smbPath(path: String) = path.replace('/', '\\').split('\\').filter { it.isNotEmpty() }.joinToString("\\")

    companion object {
        const val NAME = "sbackup/smb"
        private const val CHUNK = 1 shl 20

        /** Code d'erreur compris par le Dart (`DestinationFailure`) et détail. */
        fun classify(e: Throwable): Pair<String, String> {
            val cause = generateSequence(e) { it.cause }.toList()
            val api = cause.filterIsInstance<SMBApiException>().firstOrNull()
            if (api != null) {
                val code = when (api.status) {
                    NtStatus.STATUS_LOGON_FAILURE,
                    NtStatus.STATUS_ACCOUNT_DISABLED,
                    NtStatus.STATUS_PASSWORD_EXPIRED,
                    -> "authentification"
                    NtStatus.STATUS_ACCESS_DENIED,
                    NtStatus.STATUS_BAD_NETWORK_NAME,
                    NtStatus.STATUS_OBJECT_PATH_NOT_FOUND,
                    NtStatus.STATUS_OBJECT_NAME_NOT_FOUND,
                    -> "permission"
                    NtStatus.STATUS_DISK_FULL -> "plein"
                    else -> "autre"
                }
                return code to "${api.status} ${api.message ?: ""}".trim()
            }
            val io = cause.firstOrNull { it is IOException }
            return when {
                cause.any { it is UnknownHostException || it is ConnectException || it is NoRouteToHostException } ->
                    "injoignable" to (e.message ?: "")
                cause.any { it is SocketTimeoutException } -> "coupure" to (e.message ?: "")
                io != null || e is SMBRuntimeException -> "coupure" to (e.message ?: "")
                else -> "autre" to (e.message ?: e.javaClass.simpleName)
            }
        }
    }
}
