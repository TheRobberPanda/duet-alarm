package com.duet.alarm

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The one bridge between Flutter and the alarm engine.
 *
 * Keep this surface small (docs/02-architecture.md): every method added here is
 * code that must be written twice and can only be debugged on a device.
 */
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Anything armed before a reboot or an app update gets put back.
        AlarmScheduler.reconcile(this)
        requestNotificationPermission()
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 101)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "arm" -> {
                        val def = AlarmDef(
                            id = call.argument<String>("id")!!,
                            fireAtUtc = call.argument<Number>("fireAtUtc")!!.toLong(),
                            label = call.argument<String>("label") ?: "",
                            soundRef = call.argument<String>("soundRef") ?: "default"
                        )
                        AlarmScheduler.arm(this, def)
                        result.success(null)
                    }

                    "disarm" -> {
                        AlarmScheduler.disarm(this, call.argument<String>("id")!!)
                        result.success(null)
                    }

                    // Reads the device's own record, not a mirror held in Dart --
                    // otherwise the health screen can report alarms that are not
                    // actually scheduled.
                    "armedAlarms" -> result.success(
                        AlarmStore.all(this).map {
                            mapOf(
                                "id" to it.id,
                                "fireAtUtc" to it.fireAtUtc,
                                "label" to it.label,
                                "soundRef" to it.soundRef
                            )
                        }
                    )

                    "reconcile" -> { AlarmScheduler.reconcile(this); result.success(null) }

                    "health" -> result.success(PermissionChecks.status(this))

                    "openSetting" -> result.success(
                        PermissionChecks.openSetting(this, call.argument<String>("which")!!)
                    )

                    else -> result.notImplemented()
                }
            }
    }

    companion object { private const val CHANNEL = "com.duet.alarm/engine" }
}
