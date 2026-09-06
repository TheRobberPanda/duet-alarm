package com.duet.alarm

import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Exchanges a refresh token for a new access token, with no Flutter engine.
 *
 * Supabase access tokens last an hour. The native puller (AlarmPull.kt) runs
 * every ten minutes whether or not the app has been opened, which means that
 * for all but the first hour after someone last used the app -- including the
 * whole night -- the stored access token is expired. Without this, every one
 * of those pulls would 401 in silence and a partner's new alarm would never
 * arrive.
 *
 * The refresh endpoint takes only the publishable key and the refresh token,
 * both of which are already on the device. No service_role, no secret.
 */
object SupabaseAuth {
    private const val TAG = "DuetAuth"
    private const val URL_TOKEN =
        "https://htxxjvmikxgagtuuoxkm.supabase.co/auth/v1/token?grant_type=refresh_token"
    private const val ANON_KEY = "sb_publishable_c-KyDimcLEDDkG8cTqfaEQ_XoxeADVR"

    /**
     * Returns (accessToken, refreshToken) or null.
     *
     * Supabase rotates refresh tokens, so the new one MUST be stored -- reusing
     * a spent refresh token fails, and the device would be locked out of
     * refreshing until someone opened the app again.
     *
     * Blocking; call off the main thread.
     */
    fun refresh(refreshToken: String): Pair<String, String?>? {
        val conn = URL(URL_TOKEN).openConnection() as HttpURLConnection
        return try {
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.setRequestProperty("apikey", ANON_KEY)
            conn.setRequestProperty("Content-Type", "application/json")
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            conn.outputStream.use {
                it.write("""{"refresh_token":"$refreshToken"}""".toByteArray())
            }
            if (conn.responseCode >= 400) {
                Log.w(TAG, "refresh -> ${conn.responseCode}")
                return null
            }
            val o = JSONObject(conn.inputStream.bufferedReader().readText())
            val access = o.optString("access_token", "")
            if (access.isEmpty()) null
            else access to o.optString("refresh_token", null)
        } catch (t: Throwable) {
            Log.w(TAG, "refresh failed (non-fatal)", t)
            null
        } finally {
            conn.disconnect()
        }
    }
}
