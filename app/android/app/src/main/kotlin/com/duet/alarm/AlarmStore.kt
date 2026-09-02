package com.duet.alarm

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

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
    val soundRef: String
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("fireAtUtc", fireAtUtc)
        put("label", label)
        put("soundRef", soundRef)
    }

    companion object {
        fun fromJson(o: JSONObject) = AlarmDef(
            id = o.getString("id"),
            fireAtUtc = o.getLong("fireAtUtc"),
            label = o.optString("label", ""),
            soundRef = o.optString("soundRef", "default")
        )
    }
}

object AlarmStore {
    private const val PREFS = "duet_alarm_store"
    private const val KEY_ARMED = "armed"

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

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

    /** Drops anything already in the past. Called after boot and on reconcile. */
    fun prune(ctx: Context, now: Long = System.currentTimeMillis()) {
        write(ctx, all(ctx).filter { it.fireAtUtc > now })
    }

    private fun write(ctx: Context, defs: List<AlarmDef>) {
        val arr = JSONArray()
        defs.sortedBy { it.fireAtUtc }.forEach { arr.put(it.toJson()) }
        prefs(ctx).edit().putString(KEY_ARMED, arr.toString()).commit()
    }
}
