package com.duet.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Alarms do not survive a reboot on their own -- the OS forgets every scheduled
 * alarm. Without this receiver (and, on Xiaomi, without Autostart enabled) an
 * alarm set before a restart simply never rings.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.i(TAG, "re-arming after ${intent.action}")
        AlarmScheduler.reconcile(context)
        BootLog.record(context, intent.action ?: "unknown")
    }

    companion object { private const val TAG = "DuetBoot" }
}

/** Tiny breadcrumb trail so the app can show that re-arming actually happened. */
object BootLog {
    private const val PREFS = "duet_boot_log"
    fun record(ctx: Context, action: String) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("last", "$action @ ${System.currentTimeMillis()}").commit()
    }
    fun last(ctx: Context): String? =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("last", null)
}
