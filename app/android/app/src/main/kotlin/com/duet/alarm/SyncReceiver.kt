package com.duet.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * The heartbeat that keeps a partner's alarms arriving while the app is closed.
 *
 * Wakes every [INTERVAL_MS], asks AlarmPull to fetch and arm, then schedules
 * its own next tick. Self-rescheduling rather than setInexactRepeating because
 * Doze collapses inexact repeats into the idle maintenance window, which can be
 * over an hour apart -- and an hour is longer than the gap this exists to close.
 *
 * `setExactAndAllowWhileIdle` is the right API here and not an abuse of it: the
 * platform rate-limits it to roughly once every nine minutes per app while
 * dozing, which is the cadence we want anyway. It costs one small HTTPS request
 * per tick. That is a real battery and data cost, accepted knowingly, because
 * the alternative is the failure this file exists for -- a phone that stays
 * silent because it never heard about the alarm.
 *
 * This is NOT what makes anything ring (ADR-001). It only delivers schedules to
 * AlarmManager earlier than the next time someone opens the app.
 */
class SyncReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        // Held across the async pull: onReceive's own window closes as soon as
        // it returns, and the fetch outlives it.
        val pending = goAsync()
        // Rescheduled BEFORE the pull, so a pull that fails cannot end the
        // heartbeat -- a phone that stops resyncing stops learning about its
        // partner's alarms, and would never recover on its own.
        schedule(context)
        Log.i(TAG, "resync tick")
        AlarmPull.pull(context) { pending.finish() }
    }

    companion object {
        private const val TAG = "DuetSyncReceiver"
        private const val ACTION = "com.duet.alarm.RESYNC"

        /**
         * Ten minutes. Chosen against the real failure: an alarm created a
         * quarter of an hour before it fires must still reach the other phone.
         */
        private const val INTERVAL_MS = 10L * 60L * 1000L

        private fun pendingIntent(ctx: Context): PendingIntent = PendingIntent.getBroadcast(
            ctx, 0,
            Intent(ctx, SyncReceiver::class.java).setAction(ACTION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        /**
         * Hourly instead of every ten minutes when there is nobody signed in.
         * A signed-out phone has nothing to fetch, and waking it up 144 times a
         * day to find that out is a battery cost with no upside. Signing in
         * pushes credentials down and MainActivity reschedules, so the fast
         * cadence comes back immediately.
         */
        private const val IDLE_INTERVAL_MS = 60L * 60L * 1000L

        /** Idempotent: replaces any tick already pending. */
        fun schedule(ctx: Context) {
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val interval =
                if (AuthStore.accessToken(ctx) == null) IDLE_INTERVAL_MS else INTERVAL_MS
            val at = System.currentTimeMillis() + interval
            try {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pendingIntent(ctx))
            } catch (t: Throwable) {
                // A device that refuses exact alarms still gets the loose one;
                // late resyncs beat none.
                Log.w(TAG, "exact resync refused, falling back to inexact", t)
                am.set(AlarmManager.RTC_WAKEUP, at, pendingIntent(ctx))
            }
        }

        fun cancel(ctx: Context) {
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            am.cancel(pendingIntent(ctx))
        }
    }
}
