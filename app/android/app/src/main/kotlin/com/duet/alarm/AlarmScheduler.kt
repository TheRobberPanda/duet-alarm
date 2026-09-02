package com.duet.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Hands alarms to the OS. Nothing here is clever, and that is the point --
 * every extra moving part between us and AlarmManager is a way for 06:40 to
 * silently not happen.
 */
object AlarmScheduler {
    private const val TAG = "DuetScheduler"

    private fun pendingIntent(ctx: Context, id: String, flags: Int): PendingIntent {
        val intent = Intent(ctx, AlarmReceiver::class.java).apply {
            action = AlarmReceiver.ACTION_FIRE
            putExtra(AlarmReceiver.EXTRA_ALARM_ID, id)
            // The data URI makes the PendingIntent unique per alarm id. Without it
            // every alarm shares one PendingIntent and they overwrite each other.
            data = android.net.Uri.parse("duet://alarm/$id")
        }
        return PendingIntent.getBroadcast(ctx, 0, intent, flags)
    }

    fun arm(ctx: Context, def: AlarmDef) {
        AlarmStore.put(ctx, def)

        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val fire = pendingIntent(
            ctx, def.id,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Tapping the status-bar alarm icon should bring the user to our app.
        val showIntent = PendingIntent.getActivity(
            ctx, 0,
            Intent(ctx, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // setAlarmClock -- not setExactAndAllowWhileIdle. This is the API meant for
        // user-facing alarm clocks: exempt from Doze, shows the next-alarm icon,
        // highest scheduling priority available. See docs/04-alarm-engine.md.
        am.setAlarmClock(AlarmManager.AlarmClockInfo(def.fireAtUtc, showIntent), fire)
        Log.i(TAG, "armed ${def.id} for ${def.fireAtUtc} (${def.label})")
    }

    fun disarm(ctx: Context, id: String) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // NO_CREATE returns null if nothing was scheduled -- then there is nothing to cancel.
        pendingIntent(ctx, id, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
            ?.let { am.cancel(it); it.cancel() }
        AlarmStore.remove(ctx, id)
        Log.i(TAG, "disarmed $id")
    }

    /**
     * Re-arms everything in the store. Safe to call repeatedly -- arming the same
     * alarm twice is a no-op at the OS level because the PendingIntent matches.
     *
     * Called on boot, on package replace, on timezone change, and on app start.
     */
    fun reconcile(ctx: Context) {
        AlarmStore.prune(ctx)
        val defs = AlarmStore.all(ctx)
        defs.forEach { arm(ctx, it) }
        Log.i(TAG, "reconciled ${defs.size} alarm(s)")
    }

    fun canScheduleExact(ctx: Context): Boolean {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) am.canScheduleExactAlarms() else true
    }
}
