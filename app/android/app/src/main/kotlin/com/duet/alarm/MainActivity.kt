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
                            soundRef = call.argument<String>("soundRef") ?: "default",
                            snoozeMinutes = call.argument<Number>("snoozeMinutes")?.toInt() ?: 9,
                            maxSnoozes = call.argument<Number>("maxSnoozes")?.toInt() ?: 3,
                            wallHour = call.argument<Number>("wallHour")?.toInt() ?: -1,
                            wallMinute = call.argument<Number>("wallMinute")?.toInt() ?: -1,
                            repeatDays = call.argument<Number>("repeatDays")?.toInt() ?: 0,
                            tzMode = call.argument<String>("tzMode") ?: "local",
                            pairId = call.argument<String>("pairId")
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
                                "soundRef" to it.soundRef,
                                "snoozeMinutes" to it.snoozeMinutes,
                                "maxSnoozes" to it.maxSnoozes,
                                "snoozeCount" to it.snoozeCount
                            )
                        }
                    )

                    "reconcile" -> { AlarmScheduler.reconcile(this); result.success(null) }

                    "health" -> result.success(PermissionChecks.status(this))

                    "listSounds" -> result.success(SoundCatalog.list(this))

                    "previewSound" -> {
                        SoundCatalog.preview(this, call.argument<String>("soundRef") ?: "default")
                        result.success(null)
                    }

                    "stopPreview" -> { SoundCatalog.stopPreview(); result.success(null) }

                    "openSetting" -> result.success(
                        PermissionChecks.openSetting(this, call.argument<String>("which")!!)
                    )

                    // Lets a firing alarm report a ring session for the partner to see
                    // (RingSync.kt) without a Flutter engine running. Cleared (both
                    // null) on sign-out so a stale token never outlives the session.
                    "setAuthToken" -> {
                        AuthStore.set(
                            this,
                            call.argument<String>("accessToken"),
                            call.argument<String>("userId")
                        )
                        result.success(null)
                    }

                    // So the ringing screen -- plain Android views, no Flutter
                    // engine -- can wear the same skins as the rest of the app.
                    "setSkinColors" -> {
                        AuthStore.setSkinColors(
                            this,
                            call.argument<Number>("mine")?.toInt() ?: 0,
                            call.argument<Number>("partner")?.toInt() ?: 0
                        )
                        result.success(null)
                    }

                    // The pair context LanSync signs and authorises with. Nulls
                    // clear it, which is what leaving a pair or signing out does.
                    "setPairContext" -> {
                        AuthStore.setPairContext(
                            this,
                            call.argument<String>("pairId"),
                            call.argument<String>("lanSecret"),
                            call.argument<Boolean>("allowPartnerDismiss") ?: true
                        )
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    companion object { private const val CHANNEL = "com.duet.alarm/engine" }
}
