package com.duet.alarm

import android.content.Context
import android.util.Log
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.UUID

/**
 * Reports "I am ringing" / "I snoozed" / "I dismissed" to Postgres, so a paired
 * partner's phone can eventually show what the other person did (docs/01).
 *
 * This is the one place the native side talks to the network, and it is
 * deliberately peripheral: nothing about actually ringing waits on it, nothing
 * here can fail loudly, and a solo alarm (pairId null) never calls it at all --
 * there is no partner to tell. See AuthStore.kt for why the token can go stale,
 * and why that is an acceptable, silent degradation rather than a bug.
 *
 * Values below mirror lib/supabase_config.dart -- that file is the source of
 * truth; this is a stopgap duplicate for code with no Flutter engine to ask,
 * the same tradeoff NextFire.kt makes for scheduling math.
 */
object RingSync {
    private const val TAG = "DuetRingSync"
    private const val URL_BASE = "https://htxxjvmikxgagtuuoxkm.supabase.co/rest/v1"
    private const val ANON_KEY = "sb_publishable_c-KyDimcLEDDkG8cTqfaEQ_XoxeADVR"

    fun startRinging(ctx: Context, alarmId: String, firedAtUtc: Long, pairId: String?) {
        if (pairId == null) return
        withCreds(ctx) { token, uid ->
            val session = sessionId(alarmId, firedAtUtc)
            post(
                token, "$URL_BASE/ring_sessions?on_conflict=id",
                """{"id":"$session","alarm_id":"$alarmId","pair_id":"$pairId","fired_at":"${iso(firedAtUtc)}"}"""
            )
            post(
                token, "$URL_BASE/ring_participants?on_conflict=session_id,user_id",
                """{"session_id":"$session","user_id":"$uid","state":"ringing"}"""
            )
        }
    }

    fun updateState(
        ctx: Context, alarmId: String, firedAtUtc: Long, pairId: String?, state: String
    ) {
        if (pairId == null) return
        withCreds(ctx) { token, uid ->
            val session = sessionId(alarmId, firedAtUtc)
            patch(
                token,
                "$URL_BASE/ring_participants?session_id=eq.$session&user_id=eq.$uid",
                """{"state":"$state","updated_at":"${iso(System.currentTimeMillis())}"}"""
            )
        }
    }

    /** Deterministic, so both phones ringing the same shared alarm agree on the
     *  session id without either having to create it first. */
    private fun sessionId(alarmId: String, firedAtUtc: Long): String =
        UUID.nameUUIDFromBytes("$alarmId:$firedAtUtc".toByteArray()).toString()

    private fun iso(epochMillis: Long): String = Instant.ofEpochMilli(epochMillis).toString()

    private fun withCreds(ctx: Context, block: (token: String, uid: String) -> Unit) {
        val token = AuthStore.accessToken(ctx) ?: return
        val uid = AuthStore.userId(ctx) ?: return
        Thread {
            try {
                block(token, uid)
            } catch (t: Throwable) {
                // Never lets a network hiccup touch the ring path itself.
                Log.w(TAG, "ring sync failed (non-fatal)", t)
            }
        }.start()
    }

    private fun post(token: String, url: String, body: String) =
        request(token, url, "POST", body, "Prefer" to "resolution=merge-duplicates,return=minimal")

    private fun patch(token: String, url: String, body: String) =
        request(token, url, "PATCH", body, "Prefer" to "return=minimal")

    private fun request(
        token: String, url: String, method: String, body: String, prefer: Pair<String, String>
    ) {
        val conn = URL(url).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = method
            conn.doOutput = true
            conn.setRequestProperty("apikey", ANON_KEY)
            conn.setRequestProperty("Authorization", "Bearer $token")
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty(prefer.first, prefer.second)
            conn.connectTimeout = 5000
            conn.readTimeout = 5000
            conn.outputStream.use { it.write(body.toByteArray()) }
            val code = conn.responseCode
            if (code >= 400) {
                Log.w(TAG, "$method $url -> $code: ${conn.errorStream?.bufferedReader()?.readText()}")
            }
        } finally {
            conn.disconnect()
        }
    }
}
