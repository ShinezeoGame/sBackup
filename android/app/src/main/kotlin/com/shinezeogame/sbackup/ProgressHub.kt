package com.shinezeogame.sbackup

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Relais de l'avancement entre la sauvegarde en arrière-plan (`BackupWorker`, son propre
 * moteur Flutter) et l'interface, si elle est ouverte (`MainActivity`, canal
 * `sbackup/progression`). Tout se passe sur le fil principal.
 */
object ProgressHub {
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var last: Map<String, Any?>? = null

    val idle: Map<String, Any?> = mapOf("phase" to "idle")

    /** L'interface s'abonne : elle reçoit tout de suite l'état de la sauvegarde en cours. */
    fun attach(newSink: EventChannel.EventSink?) {
        main.post {
            sink = newSink
            newSink?.success(last ?: idle)
        }
    }

    fun publish(progress: Map<String, Any?>) {
        main.post {
            last = if (progress["phase"] == "idle") null else progress
            sink?.success(progress)
        }
    }
}
