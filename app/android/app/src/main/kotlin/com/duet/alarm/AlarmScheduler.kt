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

    /**
     * Nullable ON PURPOSE: with FLAG_NO_CREATE the platform returns null when
     * no matching PendingIntent exists -- which is the normal state when
     * dismissing an alarm that has already fired, because AlarmManager drops
     * the entry once it fires. Declaring this non-null made Kotlin throw an
     * NPE exactly there, crashing the app on every Dismiss (the caller's
     * `?.let` never even ran). Callers that CREATE (arm) can never see null;
     * callers that only LOOK UP (disarm) must handle it.
     */
    private fun pendingIntent(ctx: Context, id: String, flags: Int): PendingIntent? {
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
        // With UPDATE_CURRENT this always creates; null would mean the system
        // refused (security policy), which must be loud, never swallowed --
        // an alarm armed silently is worse than one that fails loudly.
        val fire = pendingIntent(
            ctx, def.id,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        ) ?: error("AlarmManager refused the fire PendingIntent for ${def.id}")

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
        // Anything already overdue was missed while we were not running. Record
        // it loudly rather than dropping it -- an alarm that silently did not
        // ring is the failure this whole project exists to avoid.
        val missed = AlarmStore.prune(ctx)
        if (missed.isNotEmpty()) {
            MissedLog.record(ctx, missed, "not running when due")
            missed.forEach { Log.w(TAG, "MISSED ${it.id} due ${it.fireAtUtc} (${it.label})") }
        }

        val defs = AlarmStore.all(ctx)
        defs.forEach { arm(ctx, it) }
        Log.i(TAG, "reconciled ${defs.size} alarm(s), ${missed.size} missed")
    }

    /**
     * Recomputes every wall-clock alarm for the device's CURRENT timezone.
     *
     * Called on TIMEZONE_CHANGED and TIME_SET. Without this, an alarm set for
     * 07:00 in Oslo keeps its original instant and rings at 06:00 in Lisbon --
     * and nothing corrects it until the app next runs, which for a traveller
     * may well be after it has already gone off at the wrong time.
     *
     * Dart's reconcile remains authoritative and will overwrite this on the next
     * run; this only has to keep things right in the meantime.
     */
    fun rezone(ctx: Context) {
        val now = System.currentTimeMillis()
        var moved = 0

        for (def in AlarmStore.all(ctx)) {
            if (!def.canRezone) continue

            val recomputed = NextFire.next(
                hour = def.wallHour,
                minute = def.wallMinute,
                repeatDays = def.repeatDays,
                after = now
            ) ?: continue

            if (recomputed == def.fireAtUtc) continue

            // The armed id encodes the old instant, so the old one must be
            // cancelled explicitly rather than overwritten.
            disarm(ctx, def.id)
            val newId = def.id.substringBefore('#') + "#" + recomputed
            arm(ctx, def.copy(id = newId, fireAtUtc = recomputed))
            moved++
        }

        if (moved > 0) {
            Log.i(TAG, "rezoned $moved alarm(s) to ${java.util.TimeZone.getDefault().id}")
        }
    }

    fun canScheduleExact(ctx: Context): Boolean {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) am.canScheduleExactAlarms() else true
    }
}
