package com.shinezeogame.sbackup

import android.content.Context
import android.provider.MediaStore
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import java.time.Duration
import java.util.concurrent.TimeUnit

/**
 * Programmation des sauvegardes avec WorkManager, qui survit aux redémarrages et respecte
 * les restrictions d'Android 14/15 :
 *
 *  - un passage **toutes les heures**, seulement sur un réseau non facturé (Wi-Fi), et en
 *    charge si l'utilisateur l'a demandé ;
 *  - un passage **quand une photo ou une vidéo arrive** dans la galerie (déclencheur sur
 *    le contenu de MediaStore, réarmé à la fin de chaque passage) ;
 *  - un passage **tout de suite**, à la demande (bouton « Sauvegarder maintenant »).
 *
 * Le nom du Wi-Fi et le reste des conditions sont vérifiés côté Dart (`BackupJob`).
 */
object BackupScheduler {
    const val INPUT_TRIGGER = "declencheur"
    private const val PERIODIC = "sauvegarde-periodique"
    private const val NEW_MEDIA = "sauvegarde-nouveautes"
    private const val NOW = "sauvegarde-maintenant"
    private const val PREFS = "sbackup-planification"

    fun configure(context: Context, enabled: Boolean, requireCharging: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean("actif", enabled)
            .putBoolean("charge", requireCharging)
            .apply()
        val work = WorkManager.getInstance(context)
        if (!enabled) {
            work.cancelUniqueWork(PERIODIC)
            work.cancelUniqueWork(NEW_MEDIA)
            return
        }
        val periodic = PeriodicWorkRequestBuilder<BackupWorker>(1, TimeUnit.HOURS)
            .setConstraints(baseConstraints(requireCharging).build())
            .setInputData(workDataOf(INPUT_TRIGGER to "scheduled"))
            .build()
        work.enqueueUniquePeriodicWork(PERIODIC, ExistingPeriodicWorkPolicy.UPDATE, periodic)
        watchNewMedia(context, ExistingWorkPolicy.REPLACE)
    }

    /**
     * Arme le déclencheur « nouvelle photo ». Appelé en fin de passage avec
     * APPEND_OR_REPLACE : le nouveau guet attend la fin du passage en cours.
     */
    fun watchNewMedia(context: Context, policy: ExistingWorkPolicy = ExistingWorkPolicy.APPEND_OR_REPLACE) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("actif", false)) return
        val constraints = baseConstraints(prefs.getBoolean("charge", false))
            .addContentUriTrigger(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true)
            .addContentUriTrigger(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, true)
            // Une rafale de photos ne lance qu'un passage, une minute après la dernière.
            .setTriggerContentUpdateDelay(Duration.ofMinutes(1))
            .setTriggerContentMaxDelay(Duration.ofMinutes(10))
            .build()
        val request = OneTimeWorkRequestBuilder<BackupWorker>()
            .setConstraints(constraints)
            .setInputData(workDataOf(INPUT_TRIGGER to "newMedia"))
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(NEW_MEDIA, policy, request)
    }

    /** Passage immédiat, prioritaire si le quota d'Android le permet. */
    fun runNow(context: Context) {
        val request = OneTimeWorkRequestBuilder<BackupWorker>()
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .setInputData(workDataOf(INPUT_TRIGGER to "manual"))
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(NOW, ExistingWorkPolicy.KEEP, request)
    }

    private fun baseConstraints(requireCharging: Boolean) = Constraints.Builder()
        .setRequiredNetworkType(NetworkType.UNMETERED)
        .setRequiresCharging(requireCharging)
}
