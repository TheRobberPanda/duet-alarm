package com.duet.alarm

import android.content.Context
import android.util.Log
import org.json.JSONArray
import java.util.Calendar
import java.util.TimeZone

/**
 * Pulls alarm definitions from Postgres and arms them, with no Flutter engine.
 *
 * ## Why this has to exist
 *
 * Until this file, the ONLY thing that learned about an alarm your partner
 * created was `AlarmRepository.refresh()` in Dart, and that runs on app launch
 * and on foreground-resume. Nothing else. So the sequence that actually
 * happened in testing was:
 *
 *   13:23  she creates a daily 13:36 alarm; it reaches Postgres
 *   13:34  she edits it; Postgres updated
 *   13:36  his phone does not ring -- his app had not been foregrounded since
 *          before 13:23, so his AlarmManager was never told
 *
 * His store held 13:36 on the 7th and the 8th (the 48h window, armed on some
 * earlier run) but nothing for that day. An alarm that only arrives if you
 * happen to open the app is not an alarm clock.
 *
 * ## Why this does not violate ADR-001
 *
 * ADR-001 says the network must never be what makes a phone ring. It still
 * isn't: this only DELIVERS THE SCHEDULE AHEAD OF TIME, exactly as the Dart
 * sync does, and then hands it to AlarmManager, which is what rings. A phone
 * that never sees the network again keeps ringing everything it already holds.
 *
 * ## Why it is safe to run alongside Dart's reconcile
 *
 * It only ever ARMS, and never disarms. The armed id is
 * `<alarm-uuid>#<fire-epoch-millis>`, computed the same way on both sides, so
 * an alarm this pulls and one Dart arms collapse into the same PendingIntent
 * rather than double-ringing. If this arms something Dart would not have, the
 * next reconcile removes it. The failure mode is therefore "an extra alarm is
 * briefly armed", never "an alarm is silently cancelled" -- the right way round
 * for this project.
 *
 * Mirrors AlarmSync.sync and AlarmRepository.reconcile in Dart. Those remain
 * authoritative; keep this a faithful copy rather than letting it grow its own
 * opinions, the same bargain NextFire.kt and RingSync.kt already make.
 */
object AlarmPull {
    private const val TAG = "DuetAlarmPull"
    private const val URL_BASE = "https://htxxjvmikxgagtuuoxkm.supabase.co/rest/v1"

    /** Matches AlarmRepository.window. */
    private const val WINDOW_MS = 48L * 60L * 60L * 1000L
    private const val WAKE_LATER_MINUTES = 15

    /**
     * Fetches and arms, on a background thread. Silent about everything: called
     * from a receiver with no UI, where the only honest response to a failure
     * is to leave the alarms already armed exactly as they are.
     */
    fun pull(ctx: Context, onDone: (() -> Unit)? = null) {
        val appCtx = ctx.applicationContext
        val uid = AuthStore.userId(appCtx)
        if (uid == null || AuthStore.accessToken(appCtx) == null) {
            Log.i(TAG, "no credentials; nothing to pull")
            onDone?.invoke()
            return
        }

        Thread {
            try {
                // Refreshed on this thread if needed: overnight the stored
                // token is always expired, and an expired token here means a
                // missed alarm rather than a missing nicety.
                val token = AuthStore.freshAccessToken(appCtx)
                if (token == null) {
                    Log.i(TAG, "no usable token; nothing to pull")
                    onDone?.invoke()
                    return@Thread
                }
                armAll(appCtx, fetchAlarms(token), fetchMyPrefs(token, uid), uid)
            } catch (t: Throwable) {
                // Never loud. A pull that fails leaves the device holding
                // whatever it already had, which is the safe state.
                Log.w(TAG, "pull failed (non-fatal)", t)
            }
            onDone?.invoke()
        }.start()
    }

    /**
     * RLS already scopes `alarms` to rows this account may see, so there is no
     * pair filter here -- the same reason AlarmSync.sync selects unfiltered.
     */
    private fun fetchAlarms(token: String): JSONArray =
        JSONArray(RingSync.getJson(token, "$URL_BASE/alarms?select=*&deleted_at=is.null"))

    /**
     * This listener's own row per alarm: `enabled` is per-listener (migration
     * 0010), so switching an alarm off on her phone must not silence his.
     * Falls back to the pre-0010 shape rather than failing the whole pull,
     * matching AlarmSync._fetchListenerPrefs.
     */
    private fun fetchMyPrefs(token: String, uid: String): Map<String, Pair<String, Boolean?>> {
        val rows = try {
            JSONArray(
                RingSync.getJson(
                    token,
                    "$URL_BASE/alarm_sounds?select=alarm_id,sound_ref,enabled&listener_id=eq.$uid"
                )
            )
        } catch (t: Throwable) {
            JSONArray(
                RingSync.getJson(
                    token,
                    "$URL_BASE/alarm_sounds?select=alarm_id,sound_ref&listener_id=eq.$uid"
                )
            )
        }

        val out = HashMap<String, Pair<String, Boolean?>>()
        for (i in 0 until rows.length()) {
            val o = rows.getJSONObject(i)
            val sound = if (o.isNull("sound_ref")) "default" else o.optString("sound_ref", "default")
            // Absent (pre-0010) stays null so the shared column stands in,
            // rather than asserting `true` over a genuinely switched-off alarm.
            val enabled = if (o.has("enabled") && !o.isNull("enabled")) o.optBoolean("enabled") else null
            out[o.getString("alarm_id")] = sound to enabled
        }
        return out
    }

    private fun armAll(
        ctx: Context,
        rows: JSONArray,
        prefs: Map<String, Pair<String, Boolean?>>,
        uid: String
    ) {
        val now = System.currentTimeMillis()
        val horizon = now + WINDOW_MS
        val alreadyArmed = AlarmStore.all(ctx).map { it.id }.toHashSet()
        var armed = 0

        for (i in 0 until rows.length()) {
            val o = rows.getJSONObject(i)
            val id = o.getString("id")
            val mine = prefs[id]

            // My switch first, the shared column only as the fallback.
            val enabled = mine?.second ?: o.optBoolean("enabled", true)
            if (!enabled) continue

            // "Just me" / "Just them" -- ring_target is relative to owner_id,
            // so the phone it leaves out arms nothing (Alarm.ringsFor in Dart).
            val ownedByMe = o.optString("owner_id", "") == uid
            when (o.optString("ring_target", "both")) {
                "owner" -> if (!ownedByMe) continue
                "partner" -> if (ownedByMe) continue
            }

            // 'absolute' alarms are a fixed moment and are not wall-clock
            // recomputable; leave those to Dart rather than guess.
            if (o.optString("tz_mode", "local") != "local") continue

            val time = o.optString("local_time", "") // "13:36:00"
            val parts = time.split(":")
            if (parts.size < 2) continue
            var hour = parts[0].toIntOrNull() ?: continue
            var minute = parts[1].toIntOrNull() ?: continue

            var repeatDays = o.optInt("repeat_days", 0)
            var oneShot = if (o.isNull("one_shot_date")) null else o.optString("one_shot_date", null)

            // "Wake them 15 minutes later" (migration 0011): if this phone is
            // the later one, shift the wall time -- and the days, when that
            // crosses midnight -- exactly as Alarm.forListener does in Dart.
            if (!o.isNull("wake_later_id") && o.optString("wake_later_id") == uid) {
                val total = hour * 60 + minute + WAKE_LATER_MINUTES
                val nextDay = total >= 24 * 60
                hour = (total % (24 * 60)) / 60
                minute = (total % (24 * 60)) % 60
                if (nextDay) {
                    if (repeatDays != 0) repeatDays = ((repeatDays shl 1) or (repeatDays shr 6)) and 0x7f
                    oneShot = oneShot?.let {
                        try {
                            java.time.LocalDate.parse(it).plusDays(1).toString()
                        } catch (t: Throwable) { it }
                    }
                }
            }

            val def = AlarmDef(
                id = id,
                fireAtUtc = 0,
                label = if (o.isNull("label")) "" else o.optString("label", ""),
                soundRef = mine?.first ?: "default",
                snoozeMinutes = o.optInt("snooze_minutes", 9),
                maxSnoozes = o.optInt("max_snoozes", 3),
                wallHour = hour,
                wallMinute = minute,
                repeatDays = repeatDays,
                tzMode = "local",
                pairId = if (o.isNull("pair_id")) null else o.optString("pair_id", null)
            )

            for (at in occurrences(hour, minute, repeatDays, oneShot, now, horizon)) {
                val armedId = "$id#$at"
                if (armedId in alreadyArmed) continue
                AlarmScheduler.arm(ctx, def.copy(id = armedId, fireAtUtc = at))
                armed++
            }
        }

        Log.i(TAG, "pulled ${rows.length()} alarm(s) for $uid, newly armed $armed")
    }

    /**
     * Every fire instant between [now] and [horizon] -- the same rolling window
     * Dart arms, so that a phone which never runs the app again still rings for
     * the next two days.
     */
    private fun occurrences(
        hour: Int,
        minute: Int,
        repeatDays: Int,
        oneShotDate: String?,
        now: Long,
        horizon: Long
    ): List<Long> {
        // A dated one-shot fires once, on that date, and never repeats.
        if (repeatDays == 0 && oneShotDate != null) {
            val at = oneShotInstant(oneShotDate, hour, minute) ?: return emptyList()
            return if (at in (now + 1)..horizon) listOf(at) else emptyList()
        }

        val out = ArrayList<Long>()
        var cursor = now
        while (out.size < 16) {
            val at = NextFire.next(hour, minute, repeatDays, cursor) ?: break
            if (at > horizon) break
            out.add(at)
            // A non-repeating alarm has exactly one next occurrence.
            if (repeatDays == 0) break
            cursor = at
        }
        return out
    }

    private fun oneShotInstant(date: String, hour: Int, minute: Int): Long? {
        val p = date.split("-")
        if (p.size < 3) return null
        val y = p[0].toIntOrNull() ?: return null
        val m = p[1].toIntOrNull() ?: return null
        val d = p[2].take(2).toIntOrNull() ?: return null
        return Calendar.getInstance(TimeZone.getDefault()).apply {
            set(y, m - 1, d, hour, minute, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
    }
}
