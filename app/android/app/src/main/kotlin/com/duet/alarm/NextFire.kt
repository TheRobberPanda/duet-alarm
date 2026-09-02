package com.duet.alarm

import java.util.Calendar
import java.util.TimeZone

/**
 * Recomputes fire instants from wall-clock time, in whatever timezone the device
 * is in RIGHT NOW.
 *
 * Why this exists at all, given lib/next_fire.dart already does it:
 *
 * The store holds absolute instants, because that is what AlarmManager wants.
 * But "07:00" means seven o'clock wherever you are, not a fixed moment. Fly from
 * Oslo to Lisbon and the stored instant is an hour wrong — and nothing corrects
 * it until the app next runs, which for a traveller could be after the alarm has
 * already gone off at the wrong time.
 *
 * Android tells us about the change through TIMEZONE_CHANGED, but that arrives
 * as a broadcast with no Flutter engine attached, so the recomputation has to be
 * possible here.
 *
 * **Dart remains authoritative.** This is a stopgap that keeps alarms roughly
 * right until the next full reconcile, which will overwrite whatever this
 * produced. Keep it simple; do not grow it into a second scheduler.
 */
object NextFire {

    /**
     * The next time [hour]:[minute] comes round after [after], in the device's
     * current default timezone.
     *
     * [repeatDays] is the same bitmask Dart uses: Mon = 1 shl 0 … Sun = 1 shl 6.
     * Zero means "the next occurrence, today or tomorrow".
     */
    fun next(
        hour: Int,
        minute: Int,
        repeatDays: Int,
        after: Long = System.currentTimeMillis(),
        zone: TimeZone = TimeZone.getDefault()
    ): Long? {
        // Eight days covers a full week plus today's slot having already passed.
        for (i in 0..7) {
            val c = Calendar.getInstance(zone).apply {
                timeInMillis = after
                add(Calendar.DAY_OF_YEAR, i)
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }

            if (repeatDays != 0 && !matches(repeatDays, c)) continue
            if (c.timeInMillis <= after) continue
            return c.timeInMillis
        }
        return null
    }

    /** Calendar weekdays are SUNDAY=1..SATURDAY=7; the mask is Monday-first. */
    private fun matches(mask: Int, c: Calendar): Boolean {
        val bit = when (c.get(Calendar.DAY_OF_WEEK)) {
            Calendar.MONDAY -> 1 shl 0
            Calendar.TUESDAY -> 1 shl 1
            Calendar.WEDNESDAY -> 1 shl 2
            Calendar.THURSDAY -> 1 shl 3
            Calendar.FRIDAY -> 1 shl 4
            Calendar.SATURDAY -> 1 shl 5
            else -> 1 shl 6
        }
        return mask and bit != 0
    }
}
