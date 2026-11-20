package com.shinezeogame.sbackup

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.cancellation.CancellationException

/**
 * Un passage de sauvegarde, lancé par WorkManager (voir `BackupScheduler`). Il démarre un
 * moteur Flutter sans interface qui exécute `sauvegardeArrierePlan` (lib/main.dart) : tout
 * le travail (conditions, envoi, index, historique) est en Dart.
 *
 * Pour un gros transfert, le passage devient un service au premier plan de type
 * « dataSync », avec une notification discrète : Android ne l'interrompt pas au bout de dix
 * minutes. Si Android refuse (application en arrière-plan sans exemption de batterie), le
 * passage continue simplement ; s'il est arrêté, le suivant reprend où il en était.
 */
class BackupWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    private val trigger = params.inputData.getString(BackupScheduler.INPUT_TRIGGER) ?: "scheduled"
    private val progress = MutableStateFlow<Map<String, Any?>?>(null)
    private var foreground = false

    override suspend fun doWork(): Result {
        // Un seul passage à la fois : deux moteurs écriraient le même index.
        if (!running.compareAndSet(false, true)) return Result.success()
        try {
            runDart()
        } finally {
            running.set(false)
            ProgressHub.publish(ProgressHub.idle)
            if (trigger == "newMedia") BackupScheduler.watchNewMedia(applicationContext)
        }
        return Result.success()
    }

    private suspend fun runDart() = coroutineScope {
        val done = CompletableDeferred<Unit>()
        var engine: FlutterEngine? = null
        var channel: MethodChannel? = null
        val notifier = launch { progress.collect { p -> if (p != null) showProgress(p) } }
        try {
            withContext(Dispatchers.Main) {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationComplete(applicationContext, null)
                val created = FlutterEngine(applicationContext)
                engine = created
                val ch = MethodChannel(created.dartExecutor.binaryMessenger, SystemChannel.NAME)
                channel = ch
                currentChannel = ch
                ch.setMethodCallHandler(SystemChannel(applicationContext, null) { call, result ->
                    when (call.method) {
                        "declencheur" -> result.success(trigger)
                        "avancement" -> {
                            @Suppress("UNCHECKED_CAST")
                            val map = call.arguments as? Map<String, Any?> ?: emptyMap()
                            ProgressHub.publish(map)
                            progress.value = map
                            result.success(null)
                        }
                        "termine" -> {
                            done.complete(Unit)
                            result.success(null)
                        }
                        else -> return@SystemChannel false
                    }
                    true
                })
                created.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "sauvegardeArrierePlan"),
                )
            }
            done.await()
        } catch (e: CancellationException) {
            // Android arrête le passage (contraintes perdues, délai dépassé) : on laisse au
            // Dart quelques secondes pour s'arrêter proprement entre deux morceaux.
            withContext(NonCancellable + Dispatchers.Main) {
                channel?.invokeMethod("arreter", null)
                withTimeoutOrNull(5_000) { done.await() }
            }
            throw e
        } finally {
            notifier.cancel()
            withContext(NonCancellable + Dispatchers.Main) {
                currentChannel = null
                engine?.destroy()
            }
        }
    }

    /** Passe au premier plan pour les gros transferts, puis met la notification à jour. */
    private suspend fun showProgress(p: Map<String, Any?>) {
        if (p["phase"] == "idle") return
        val remaining = number(p["octetsTotal"]) - number(p["octetsFaits"])
        if (!foreground && remaining < BIG_TRANSFER && number(p["total"]) < BIG_COUNT) return
        try {
            setForeground(foregroundInfo(p))
            foreground = true
        } catch (e: IllegalStateException) {
            // Refusé par Android (ForegroundServiceStartNotAllowedException) : on continue sans.
        }
        delay(1_000)
    }

    override suspend fun getForegroundInfo(): ForegroundInfo = foregroundInfo(null)

    private fun foregroundInfo(p: Map<String, Any?>?): ForegroundInfo =
        ForegroundInfo(NOTIFICATION_ID, notification(p), ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)

    private fun notification(p: Map<String, Any?>?): Notification {
        val context = applicationContext
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Sauvegarde en cours", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Avancement des gros transferts vers le NAS"
                    setShowBadge(false)
                },
            )
        }
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Sauvegarde des photos")
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            // Arrêt propre du passage (annuler le travail WorkManager supprimerait aussi le
            // passage périodique).
            .addAction(0, "Arrêter", StopReceiver.pendingIntent(context))
        if (p == null) {
            builder.setContentText("Préparation…").setProgress(0, 0, true)
        } else {
            val total = number(p["octetsTotal"])
            val done = number(p["octetsFaits"])
            val files = "${number(p["faits"])} sur ${number(p["total"])}"
            builder.setContentText("$files · ${bytes(done)} sur ${bytes(total)}")
            if (total > 0) {
                builder.setProgress(1000, (done * 1000 / total).toInt(), false)
            } else {
                builder.setProgress(0, 0, true)
            }
        }
        return builder.build()
    }

    private fun number(value: Any?): Long = (value as? Number)?.toLong() ?: 0L

    private fun bytes(n: Long): String = when {
        n >= 1_000_000_000 -> String.format(java.util.Locale.FRANCE, "%.1f Go", n / 1e9)
        n >= 1_000_000 -> String.format(java.util.Locale.FRANCE, "%.1f Mo", n / 1e6)
        else -> String.format(java.util.Locale.FRANCE, "%d Ko", n / 1000)
    }

    companion object {
        private val running = AtomicBoolean(false)
        private const val CHANNEL_ID = "sauvegarde"
        private const val NOTIFICATION_ID = 4207

        /** Au-delà de 50 Mo ou de 30 fichiers restants, le passage passe au premier plan. */
        private const val BIG_TRANSFER = 50_000_000L
        private const val BIG_COUNT = 30L

        @Volatile
        private var currentChannel: MethodChannel? = null

        /** Bouton « Arrêter » de l'interface : arrêt propre du passage en cours. */
        fun requestStop() {
            currentChannel?.invokeMethod("arreter", null)
        }

        fun isRunning(): Boolean = running.get()
    }
}
