package com.duet.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Snooze and dismiss, in one place.
 *
 * Two surfaces need them: the full-screen [RingingActivity], and the heads-up
 * notification that Android shows instead when the phone is unlocked and in use.
 * Having the logic in one object keeps those two from drifting apart -- a
 * dismiss that only half-works from one of them would be a very bad bug.
 *
 * Everything needed is passed in explicitly, because neither surface can look it
 * up: the service deletes the stored alarm the moment it fires.
 */
object AlarmActions {
    private const val TAG = "DuetActions"

    /** Broadcast so an open ringing screen closes itself when acted on elsewhere. */
    const val ACTION_RING_ENDED = "com.duet.alarm.RING_ENDED"

    fun snooze(
        ctx: Context,
        alarmId: String,
        label: String,
        soundRef: String,
        snoozeMinutes: Int,
        maxSnoozes: Int,
        snoozeCount: Int,
        pairId: String? = null
    ) {
        AlarmService.stop(ctx, alarmId)

        if (snoozeCount >= maxSnoozes) {
            Log.i(TAG, "snooze refused for $alarmId: allowance spent")
            endRing(ctx)
            return
        }

        // A stable key derived from the original alarm, so a second snooze
        // replaces the first rather than stacking another alarm on top.
        val base = alarmId.removePrefix(AlarmDef.SNOOZE_PREFIX)
        AlarmScheduler.arm(
            ctx,
            AlarmDef(
                id = AlarmDef.SNOOZE_PREFIX + base,
                fireAtUtc = System.currentTimeMillis() + snoozeMinutes * 60_000L,
                label = label,
                soundRef = soundRef,
                snoozeMinutes = snoozeMinutes,
                maxSnoozes = maxSnoozes,
                snoozeCount = snoozeCount + 1,
                pairId = pairId
            )
        )
        Log.i(TAG, "snoozed $alarmId for $snoozeMinutes min (${snoozeCount + 1}/$maxSnoozes)")
        reportState(ctx, base, "snoozed", pairId)
        endRing(ctx)
    }

    fun dismiss(ctx: Context, alarmId: String, pairId: String? = null) {
        AlarmService.stop(ctx, alarmId)
        // A dismiss ends the session, so any pending snooze goes with it.
        val base = alarmId.removePrefix(AlarmDef.SNOOZE_PREFIX)
        AlarmScheduler.disarm(ctx, AlarmDef.SNOOZE_PREFIX + base)
        Log.i(TAG, "dismissed $alarmId")
        reportState(ctx, base, "dismissed", pairId)
        endRing(ctx)
    }

    /**
     * "For both of us" -- stops this phone AND asks the partner's to stop.
     *
     * Lives here, next to [dismiss], for the reason at the top of this file:
     * the ringing screen and the notification both offer it now, and a
     * "dismiss for both" that only half-worked from one of them is exactly the
     * bug this object exists to prevent.
     *
     * Both transports at once. The LAN datagram lands in milliseconds when the
     * two phones are on the same wifi; the RPC covers them being anywhere
     * else, and is the only path that can check the partner's
     * `allow_partner_dismiss` preference server-side. Whichever arrives first
     * wins and the second is a harmless no-op.
     *
     * Your own alarm stops either way: dismissing for both while yours kept
     * ringing would be a confusing halfway state.
     */
    fun dismissForBoth(ctx: Context, alarmId: String, pairId: String?) {
        val base = alarmId.removePrefix(AlarmDef.SNOOZE_PREFIX)
        splitFireId(base)?.let { (alarm, firedAt) ->
            LanSync.requestDismissForBoth(ctx, RingSync.sessionIdFor(alarm, firedAt))
            RingSync.actOnPartner(ctx, alarm, firedAt, pairId, "dismiss") { ok ->
                Log.i(TAG, "dismiss-for-both RPC reported ok=$ok")
            }
        }
        dismiss(ctx, alarmId, pairId)
    }

    /** The fired-instant id, not a snooze-wrapped one -- a snooze is part of the
     *  same ring session, not a new one, so it must resolve to the same id.
     *
     *  Reported over both transports: the cloud path is the record, the LAN
     *  path is what makes the partner's screen update in the same breath when
     *  they are on the same wifi. */
    private fun reportState(ctx: Context, baseFireId: String, state: String, pairId: String?) {
        if (pairId == null) return
        val (alarmId, firedAt) = splitFireId(baseFireId) ?: return
        RingSync.updateState(ctx, alarmId, firedAt, pairId, state)
        LanSync.announceState(ctx, RingSync.sessionIdFor(alarmId, firedAt), state)
    }

    private fun endRing(ctx: Context) =
        ctx.sendBroadcast(Intent(ACTION_RING_ENDED).setPackage(ctx.packageName))
}

/**
 * Receives Snooze / Dismiss taps from the notification.
 *
 * This is the path that matters when the phone is already in use: Android
 * suppresses the full-screen intent in that case and shows a heads-up instead,
 * so without these actions the only way to stop the alarm is to tap through to
 * the ringing screen first.
 */
class AlarmActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(AlarmReceiver.EXTRA_ALARM_ID) ?: return

        val pairId = intent.getStringExtra("pairId")
        when (intent.action) {
            ACTION_SNOOZE -> AlarmActions.snooze(
                ctx = context,
                alarmId = id,
                label = intent.getStringExtra("label") ?: "Alarm",
                soundRef = intent.getStringExtra("soundRef") ?: "default",
                snoozeMinutes = intent.getIntExtra("snoozeMinutes", 9),
                maxSnoozes = intent.getIntExtra("maxSnoozes", 3),
                snoozeCount = intent.getIntExtra("snoozeCount", 0),
                pairId = pairId
            )
            ACTION_DISMISS -> AlarmActions.dismiss(context, id, pairId)
            ACTION_DISMISS_BOTH -> AlarmActions.dismissForBoth(context, id, pairId)
        }
    }

    companion object {
        const val ACTION_SNOOZE = "com.duet.alarm.action.SNOOZE"
        const val ACTION_DISMISS = "com.duet.alarm.action.DISMISS"
        const val ACTION_DISMISS_BOTH = "com.duet.alarm.action.DISMISS_BOTH"
    }
}
