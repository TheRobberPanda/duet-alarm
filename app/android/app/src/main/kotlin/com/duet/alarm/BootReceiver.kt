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
        // A crash in here means no alarm is ever re-armed, and the user finds
        // out by oversleeping. Nothing in this receiver may be allowed to throw.
        try {
            Log.i(TAG, "re-arming after ${intent.action}")
            AlarmScheduler.reconcile(context)

            // A timezone or clock change moves what "07:00" means, so the stored
            // instants have to be recomputed rather than merely re-armed.
            if (intent.action == Intent.ACTION_TIMEZONE_CHANGED ||
                intent.action == Intent.ACTION_TIME_CHANGED
            ) {
                AlarmScheduler.rezone(context)
            }

            // Re-arming only restores what this phone already knew about. If
            // the partner added an alarm while it was off, only a pull finds
            // it -- and the heartbeat that would have done so died with the
            // reboot, so it has to be started again here.
            SyncReceiver.schedule(context)
            AlarmPull.pull(context)

            BootLog.record(context, intent.action ?: "unknown")
        } catch (t: Throwable) {
            Log.e(TAG, "re-arm FAILED after ${intent.action}", t)
            BootLog.record(context, "FAILED ${intent.action}: ${t.javaClass.simpleName}")
        }
    }

    companion object { private const val TAG = "DuetBoot" }
}

/** Tiny breadcrumb trail so the app can show that re-arming actually happened. */
object BootLog {
    private const val PREFS = "duet_boot_log"
    fun record(ctx: Context, action: String) {
        ctx.deviceProtected().getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("last", "$action @ ${System.currentTimeMillis()}").commit()
    }
    fun last(ctx: Context): String? =
        ctx.deviceProtected().getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString("last", null)
}
