package com.duet.alarm

import android.content.Context
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

/**
 * Device-protected (device-encrypted) storage.
 *
 * Alarm state MUST live here, not in the default credential-encrypted store.
 * A phone that reboots at 03:00 — an overnight OS update, a crash — sits at the
 * lock screen until someone unlocks it, and credential-encrypted preferences do
 * not exist until then. Reading them from a boot receiver throws:
 *
 *   IllegalStateException: SharedPreferences in credential encrypted storage
 *   are not available until after user (id 0) is unlocked
 *
 * which is precisely what happened on the first real reboot test. For an alarm
 * clock the alarm has to survive to the lock screen, so device-protected
 * storage is the correct home for it, not a workaround.
 */
internal fun Context.deviceProtected(): Context =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
        createDeviceProtectedStorageContext() else this

/**
 * The device's own record of what should ring. Deliberately dumb and synchronous:
 * it is read from a BroadcastReceiver at boot, where nothing fancy is available.
 *
 * This is the ONLY source of truth the native side consults. Flutter pushes
 * definitions in; the native side never calls back into Dart to decide whether
 * to ring. See docs/02-architecture.md.
 */
data class AlarmDef(
    val id: String,
    val fireAtUtc: Long,
    val label: String,
    val soundRef: String,
    /** Minutes a snooze lasts. Carried here because the ringing screen has no
     *  Flutter engine to ask -- it must decide entirely from local state. */
    val snoozeMinutes: Int = 9,
    /** 0 disables snoozing outright. */
    val maxSnoozes: Int = 3,
    /** How many snoozes have already been used in THIS ring session. */
    val snoozeCount: Int = 0,
    /**
     * The wall clock this instant was derived from, and the repeat mask.
     *
     * fireAtUtc alone is not enough: "07:00" means seven o'clock wherever you
     * are, so the instant has to be recomputed when the device changes
     * timezone. -1 means "unknown" (a snooze, or an alarm armed before this
     * field existed), in which case the instant is left alone.
     */
    val wallHour: Int = -1,
    val wallMinute: Int = -1,
    val repeatDays: Int = 0,
    /** 'local' follows the device; 'absolute' is a fixed moment and never moves. */
    val tzMode: String = "local"
) {
    val canRezone: Boolean
        get() = wallHour in 0..23 && wallMinute in 0..59 &&
            tzMode == "local" && !id.startsWith(SNOOZE_PREFIX)

    val snoozesLeft: Int get() = (maxSnoozes - snoozeCount).coerceAtLeast(0)
    val canSnooze: Boolean get() = snoozesLeft > 0

    /** The user-facing alarm this belongs to, stripping any snooze wrapper. */
    val baseId: String get() = id.removePrefix(SNOOZE_PREFIX)

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("fireAtUtc", fireAtUtc)
        put("label", label)
        put("soundRef", soundRef)
        put("snoozeMinutes", snoozeMinutes)
        put("maxSnoozes", maxSnoozes)
        put("snoozeCount", snoozeCount)
        put("wallHour", wallHour)
        put("wallMinute", wallMinute)
        put("repeatDays", repeatDays)
        put("tzMode", tzMode)
    }

    companion object {
        const val SNOOZE_PREFIX = "snooze:"

        fun fromJson(o: JSONObject) = AlarmDef(
            id = o.getString("id"),
            fireAtUtc = o.getLong("fireAtUtc"),
            label = o.optString("label", ""),
            soundRef = o.optString("soundRef", "default"),
            snoozeMinutes = o.optInt("snoozeMinutes", 9),
            maxSnoozes = o.optInt("maxSnoozes", 3),
            snoozeCount = o.optInt("snoozeCount", 0),
            wallHour = o.optInt("wallHour", -1),
            wallMinute = o.optInt("wallMinute", -1),
            repeatDays = o.optInt("repeatDays", 0),
            tzMode = o.optString("tzMode", "local")
        )
    }
}

object AlarmStore {
    private const val PREFS = "duet_alarm_store"
    private const val KEY_ARMED = "armed"

    private fun prefs(ctx: Context) =
        ctx.deviceProtected().getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun all(ctx: Context): List<AlarmDef> {
        val raw = prefs(ctx).getString(KEY_ARMED, "[]") ?: "[]"
        val arr = JSONArray(raw)
        return (0 until arr.length()).map { AlarmDef.fromJson(arr.getJSONObject(it)) }
    }

    fun find(ctx: Context, id: String): AlarmDef? = all(ctx).firstOrNull { it.id == id }

    fun put(ctx: Context, def: AlarmDef) {
        val next = all(ctx).filter { it.id != def.id } + def
        write(ctx, next)
    }

    fun remove(ctx: Context, id: String) {
        write(ctx, all(ctx).filter { it.id != id })
    }

    /**
     * Removes alarms whose time has passed, and RETURNS them rather than
     * discarding them silently.
     *
     * An alarm can be overdue here for only one reason: we were not running
     * when it was due — the phone was off, or the OEM delayed our boot
     * broadcast. On the first reboot test MIUI delivered BOOT_COMPLETED three
     * and a half minutes late, by which point the alarm was already overdue and
     * an earlier version of this method deleted it without a word.
     *
     * A missed alarm is the worst thing this app can do to someone, so it is
     * recorded and shown. See docs/04-alarm-engine.md.
     */
    fun prune(ctx: Context, now: Long = System.currentTimeMillis()): List<AlarmDef> {
        val (overdue, live) = all(ctx).partition { it.fireAtUtc <= now }
        if (overdue.isNotEmpty()) write(ctx, live)
        return overdue
    }

    private fun write(ctx: Context, defs: List<AlarmDef>) {
        val arr = JSONArray()
        defs.sortedBy { it.fireAtUtc }.forEach { arr.put(it.toJson()) }
        prefs(ctx).edit().putString(KEY_ARMED, arr.toString()).commit()
    }
}


/**
 * Alarms that were due while the app was not running.
 *
 * This is the single most valuable diagnostic in the project: it is the only
 * way a user (or the developer) ever learns that an alarm silently did not
 * ring. Everything else looks fine after the fact.
 */
object MissedLog {
    private const val PREFS = "duet_missed_log"

    fun record(ctx: Context, defs: List<AlarmDef>, reason: String) {
        if (defs.isEmpty()) return
        val p = ctx.deviceProtected().getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val existing = p.getString("log", "") ?: ""
        val lines = defs.joinToString("\n") {
            "${it.id} due ${it.fireAtUtc} (${it.label}) — $reason"
        }
        p.edit().putString("log", "$lines\n$existing".take(4000)).commit()
    }

    fun read(ctx: Context): String =
        ctx.deviceProtected().getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString("log", "") ?: ""

    fun clear(ctx: Context) {
        ctx.deviceProtected().getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().remove("log").commit()
    }
}
