package com.shinezeogame.sbackup

import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * L'interface. Elle partage le canal `sbackup/systeme` avec la sauvegarde en arrière-plan
 * (`SystemChannel`) et sait, en plus, demander les autorisations ; elle reçoit l'avancement
 * des sauvegardes par le canal `sbackup/progression` (`ProgressHub`).
 */
class MainActivity : FlutterActivity() {
    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, SystemChannel.NAME).setMethodCallHandler(SystemChannel(applicationContext, this))
        // « Tester la connexion » dans les réglages.
        MethodChannel(messenger, SmbChannel.NAME).setMethodCallHandler(SmbChannel(applicationContext))
        EventChannel(messenger, "sbackup/progression").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) = ProgressHub.attach(events)

            override fun onCancel(arguments: Any?) = ProgressHub.attach(null)
        })
    }

    override fun onDestroy() {
        ProgressHub.attach(null)
        super.onDestroy()
    }

    /**
     * Demande une autorisation. Les fenêtres d'autorisation répondent ici
     * ([onRequestPermissionsResult]) ; les pages de réglages répondent tout de suite, et
     * l'interface relit l'état à son retour au premier plan.
     */
    @SuppressLint("BatteryLife") // l'exemption est le cœur du service rendu : sauvegarder en arrière-plan
    fun request(what: String, result: MethodChannel.Result) {
        val permissions: Array<String>? = when (what) {
            "medias" -> SystemChannel.mediaPermissions()
            "notifications" -> if (Build.VERSION.SDK_INT >= 33) arrayOf(Manifest.permission.POST_NOTIFICATIONS) else null
            "localisation" -> arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
            // Android 11+ : ouvre la page où choisir « Toujours autoriser ».
            "localisationArrierePlan" -> arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
            else -> null
        }
        if (permissions != null) {
            pendingPermission?.success(null)
            pendingPermission = result
            requestPermissions(permissions, PERMISSION_REQUEST)
            return
        }
        val intent = when (what) {
            "batterie" -> Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
            "reglagesLocalisation" -> Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
            else -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
        }
        result.success(null)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST) {
            pendingPermission?.success(null)
            pendingPermission = null
        }
    }

    companion object {
        private const val PERMISSION_REQUEST = 4201
    }
}
