package com.shinezeogame.sbackup

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

/**
 * Canal `sbackup/systeme`, côté Android (côté Dart : `lib/platform/android_platform.dart`).
 * Le même code sert l'interface (`MainActivity`, qui sait demander des autorisations) et
 * la sauvegarde en arrière-plan (`BackupWorker`, qui ajoute ses propres méthodes par
 * [extra] ; [activity] y est absente).
 */
class SystemChannel(
    private val context: Context,
    private val activity: MainActivity?,
    private val extra: ((MethodCall, MethodChannel.Result) -> Boolean)? = null,
) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (extra?.invoke(call, result) == true) return
        when (call.method) {
            "dossierDonnees" -> result.success(context.filesDir.path)
            "autorisations" -> result.success(permissions(context))
            "demander" -> {
                val what = call.arguments as? String ?: ""
                if (activity == null) result.success(null) else activity.request(what, result)
            }
            "etatAppareil" -> result.success(deviceState())
            // Lire la galerie peut prendre un moment : hors du fil principal.
            "albums" -> background(result) { MediaQueries.albums(context) }
            "medias" -> {
                val ids = (call.arguments as? List<*>)?.map { it.toString() } ?: emptyList()
                background(result) { MediaQueries.media(context, ids) }
            }
            "planifier" -> {
                BackupScheduler.configure(
                    context,
                    enabled = call.argument<Boolean>("actif") ?: false,
                    requireCharging = call.argument<Boolean>("charge") ?: false,
                )
                result.success(null)
            }
            "sauvegarderMaintenant" -> {
                BackupScheduler.runNow(context)
                result.success(null)
            }
            "arreter" -> {
                BackupWorker.requestStop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        thread {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: SecurityException) {
                main.post { result.error("autorisation", "Accès aux photos et vidéos refusé", null) }
            } catch (e: Exception) {
                main.post { result.error("galerie", e.message, null) }
            }
        }
    }

    /** Wi-Fi, nom du Wi-Fi et charge. */
    private fun deviceState(): Map<String, Any?> {
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val caps = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
        val onWifi = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        // Le nom du Wi-Fi n'est donné qu'avec l'autorisation de localisation, localisation
        // activée ; sinon Android répond « <unknown ssid> ».
        @Suppress("DEPRECATION")
        val ssid = if (onWifi) {
            context.applicationContext.getSystemService(WifiManager::class.java).connectionInfo?.ssid
        } else {
            null
        }
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val plugged = (battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
        return mapOf(
            "wifi" to onWifi,
            "ssid" to ssid,
            "ssidLisible" to granted(context, Manifest.permission.ACCESS_FINE_LOCATION),
            "enCharge" to plugged,
        )
    }

    companion object {
        const val NAME = "sbackup/systeme"

        fun granted(context: Context, permission: String) =
            ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

        /** Autorisations demandées pour l'accès aux photos et vidéos, selon la version d'Android. */
        fun mediaPermissions(): Array<String> = when {
            Build.VERSION.SDK_INT >= 34 -> arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
                Manifest.permission.ACCESS_MEDIA_LOCATION,
            )
            Build.VERSION.SDK_INT >= 33 -> arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.ACCESS_MEDIA_LOCATION,
            )
            else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.ACCESS_MEDIA_LOCATION)
        }

        fun permissions(context: Context): Map<String, Any?> {
            val all = if (Build.VERSION.SDK_INT >= 33) {
                granted(context, Manifest.permission.READ_MEDIA_IMAGES) &&
                    granted(context, Manifest.permission.READ_MEDIA_VIDEO)
            } else {
                granted(context, Manifest.permission.READ_EXTERNAL_STORAGE)
            }
            val partial = Build.VERSION.SDK_INT >= 34 &&
                granted(context, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
            val power = context.getSystemService(PowerManager::class.java)
            val location = context.getSystemService(LocationManager::class.java)
            return mapOf(
                "medias" to if (all) "all" else if (partial) "partial" else "none",
                "notifications" to (Build.VERSION.SDK_INT < 33 ||
                    granted(context, Manifest.permission.POST_NOTIFICATIONS)),
                "localisation" to granted(context, Manifest.permission.ACCESS_FINE_LOCATION),
                "localisationArrierePlan" to granted(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                "localisationActive" to location.isLocationEnabled,
                "batterieLibre" to power.isIgnoringBatteryOptimizations(context.packageName),
            )
        }
    }
}
