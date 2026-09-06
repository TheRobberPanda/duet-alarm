package com.duet.alarm

import android.content.Context
import android.util.Log
import org.json.JSONArray
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

    /**
     * The one read this object does. Polled from the ringing screen (Milestone
     * 4's live awareness strip) to show what the partner did, if anything --
     * `null` covers every reason there is nothing to show yet: no partner row
     * (their phone has not started ringing), no credentials, or a failed
     * request. The caller cannot and should not tell those apart; the strip
     * just stays hidden.
     *
     * [callback] runs on the same background thread as the request, same as
     * every other entry point here -- the caller hops back to the main thread
     * itself.
     */
    fun fetchPartnerState(
        ctx: Context, alarmId: String, firedAtUtc: Long, pairId: String?, callback: (String?) -> Unit
    ) {
        if (pairId == null) return callback(null)
        val token = AuthStore.accessToken(ctx)
        val uid = AuthStore.userId(ctx)
        if (token == null || uid == null) return callback(null)

        Thread {
            val state = try {
                val session = sessionId(alarmId, firedAtUtc)
                val url = "$URL_BASE/ring_participants" +
                    "?session_id=eq.$session&user_id=neq.$uid&select=state&limit=1"
                val body = get(token, url)
                val arr = JSONArray(body)
                if (arr.length() == 0) null else arr.getJSONObject(0).optString("state", null)
            } catch (t: Throwable) {
                Log.w(TAG, "fetch partner state failed (non-fatal)", t)
                null
            }
            callback(state)
        }.start()
    }

    /**
     * MY OWN participant row -- the other half of "dismiss for both", and the
     * reason that feature did not work over the cloud path at all.
     *
     * `act_on_partner` sets the TARGET's row to dismissed. Their phone,
     * however, only ever polled [fetchPartnerState] (`user_id=neq.$uid`), so
     * nothing on it ever read the row that had just been changed on its
     * behalf: the RPC succeeded, the database was correct, and the alarm kept
     * ringing. Only the LAN datagram actually stopped anything, which meant
     * the feature worked at home on the same wifi and silently did nothing
     * anywhere else.
     *
     * Same shape and same silence as [fetchPartnerState]: null means "no row,
     * no credentials, or the request failed", and the caller does nothing.
     */
    fun fetchMyState(
        ctx: Context, alarmId: String, firedAtUtc: Long, pairId: String?, callback: (String?) -> Unit
    ) {
        if (pairId == null) return callback(null)
        val token = AuthStore.accessToken(ctx)
        val uid = AuthStore.userId(ctx)
        if (token == null || uid == null) return callback(null)

        Thread {
            val state = try {
                val session = sessionId(alarmId, firedAtUtc)
                val url = "$URL_BASE/ring_participants" +
                    "?session_id=eq.$session&user_id=eq.$uid&select=state&limit=1"
                val arr = JSONArray(get(token, url))
                if (arr.length() == 0) null else arr.getJSONObject(0).optString("state", null)
            } catch (t: Throwable) {
                Log.w(TAG, "fetch my state failed (non-fatal)", t)
                null
            }
            callback(state)
        }.start()
    }

    /**
     * "For both of us" (docs/01, ADR-006's deliberate secondary action): acts on
     * the PARTNER's participant row via the `act_on_partner` RPC, which is the
     * only path that can -- it checks their `allow_partner_dismiss` preference
     * server-side, which a direct client write to their row cannot be trusted
     * to respect. No-ops harmlessly if their ring session has not started yet
     * (nothing to update) or they have that preference off (the RPC rejects
     * it); either way [callback] just reports whether it thinks it worked.
     */
    fun actOnPartner(
        ctx: Context, alarmId: String, firedAtUtc: Long, pairId: String?, action: String,
        callback: (Boolean) -> Unit
    ) {
        if (pairId == null) return callback(false)
        val token = AuthStore.accessToken(ctx)
        val uid = AuthStore.userId(ctx)
        if (token == null || uid == null) return callback(false)

        Thread {
            val ok = try {
                val partnerId = fetchPartnerId(token, pairId, uid)
                if (partnerId == null) {
                    false
                } else {
                    val session = sessionId(alarmId, firedAtUtc)
                    val body =
                        """{"p_session":"$session","p_target":"$partnerId","p_action":"$action"}"""
                    postForSuccess(token, "$URL_BASE/rpc/act_on_partner", body)
                }
            } catch (t: Throwable) {
                Log.w(TAG, "act on partner failed (non-fatal)", t)
                false
            }
            callback(ok)
        }.start()
    }

    private fun fetchPartnerId(token: String, pairId: String, myUid: String): String? {
        val url = "$URL_BASE/pair_members?pair_id=eq.$pairId&user_id=neq.$myUid&select=user_id&limit=1"
        val arr = JSONArray(get(token, url))
        return if (arr.length() == 0) null else arr.getJSONObject(0).optString("user_id", null)
    }

    /** Deterministic, so both phones ringing the same shared alarm agree on the
     *  session id without either having to create it first. */
    fun sessionIdFor(alarmId: String, firedAtUtc: Long): String = sessionId(alarmId, firedAtUtc)

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

    /**
     * Shared with AlarmPull.kt, which needs the same authenticated GET and has
     * no more business duplicating the header dance than it does the base URL.
     * Returns "[]" rather than throwing on an HTTP error, so a caller with no
     * UI has one thing to handle instead of two.
     */
    fun getJson(token: String, url: String): String = get(token, url)

    private fun get(token: String, url: String): String {
        val conn = URL(url).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "GET"
            conn.setRequestProperty("apikey", ANON_KEY)
            conn.setRequestProperty("Authorization", "Bearer $token")
            conn.connectTimeout = 5000
            conn.readTimeout = 5000
            val code = conn.responseCode
            if (code >= 400) {
                Log.w(TAG, "GET $url -> $code: ${conn.errorStream?.bufferedReader()?.readText()}")
                return "[]"
            }
            return conn.inputStream.bufferedReader().readText()
        } finally {
            conn.disconnect()
        }
    }

    private fun postForSuccess(token: String, url: String, body: String): Boolean {
        val conn = URL(url).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.setRequestProperty("apikey", ANON_KEY)
            conn.setRequestProperty("Authorization", "Bearer $token")
            conn.setRequestProperty("Content-Type", "application/json")
            conn.connectTimeout = 5000
            conn.readTimeout = 5000
            conn.outputStream.use { it.write(body.toByteArray()) }
            val code = conn.responseCode
            if (code >= 400) {
                Log.w(TAG, "POST $url -> $code: ${conn.errorStream?.bufferedReader()?.readText()}")
                return false
            }
            return true
        } finally {
            conn.disconnect()
        }
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
