package com.duet.alarm

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

/**
 * Everything the OS can do to stop the alarm, in one place.
 *
 * This backs the Permission Health screen, which is not polish -- on a Xiaomi it
 * is the difference between an alarm that rings and one that silently does not.
 */
object PermissionChecks {

    fun status(ctx: Context): Map<String, Any> = mapOf(
        "exactAlarms" to AlarmScheduler.canScheduleExact(ctx),
        "notifications" to notificationsAllowed(ctx),
        "fullScreenIntent" to fullScreenIntentAllowed(ctx),
        "batteryUnrestricted" to ignoringBatteryOptimizations(ctx),
        "manufacturer" to Build.MANUFACTURER,
        "isAggressiveOem" to isAggressiveOem(),
        "lastBootReArm" to (BootLog.last(ctx) ?: ""),
        "ringLog" to RingLog.read(ctx)
    )

    private fun notificationsAllowed(ctx: Context): Boolean {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return nm.areNotificationsEnabled()
    }

    /**
     * Android 14+ restricts full-screen intents. Alarm apps are meant to keep it,
     * but never assume -- if this is false the ringing screen will not launch over
     * the lock screen and we must fall back to a heads-up notification.
     */
    private fun fullScreenIntentAllowed(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return nm.canUseFullScreenIntent()
    }

    private fun ignoringBatteryOptimizations(ctx: Context): Boolean {
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(ctx.packageName)
    }

    private fun isAggressiveOem(): Boolean {
        val m = Build.MANUFACTURER.lowercase()
        return listOf("xiaomi", "redmi", "poco", "huawei", "honor", "oppo",
                      "vivo", "oneplus", "realme", "samsung", "meizu").any { m.contains(it) }
    }

    /** Opens the relevant system screen. Returns false when we have nowhere to send them. */
    fun openSetting(ctx: Context, which: String): Boolean {
        val intent: Intent? = when (which) {
            "exactAlarms" ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                    Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                           Uri.parse("package:${ctx.packageName}"))
                else null

            "notifications" ->
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, ctx.packageName)

            "fullScreenIntent" ->
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
                    Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                           Uri.parse("package:${ctx.packageName}"))
                else null

            "battery" ->
                @Suppress("BatteryLife")
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                       Uri.parse("package:${ctx.packageName}"))

            // MIUI / HyperOS autostart. The component name is undocumented and has
            // changed between versions, so this is best-effort with a fallback to
            // the generic app-details screen.
            "autostart" -> miuiAutostartIntent(ctx)

            "appDetails" ->
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                       Uri.parse("package:${ctx.packageName}"))

            else -> null
        }

        return try {
            intent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            intent?.let { ctx.startActivity(it); true } ?: false
        } catch (t: Throwable) {
            false
        }
    }

    private fun miuiAutostartIntent(ctx: Context): Intent? {
        val candidates = listOf(
            "com.miui.securitycenter" to
                "com.miui.permcenter.autostart.AutoStartManagementActivity",
            "com.miui.securitycenter" to
                "com.miui.permcenter.autostart.AutoStartDetailManagementActivity"
        )
        for ((pkg, cls) in candidates) {
            val i = Intent().setClassName(pkg, cls)
            if (ctx.packageManager.resolveActivity(i, 0) != null) return i
        }
        return Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                      Uri.parse("package:${ctx.packageName}"))
    }
}
