package com.duet.alarm

import android.content.Context

/**
 * The one piece of Supabase auth the native side needs: enough to write a ring
 * session as the signed-in user (RingSync.kt) with no Flutter engine running.
 *
 * Device-protected storage, like AlarmStore -- a phone that reboots overnight
 * has to be able to report a ring before it is ever unlocked.
 *
 * Deliberately just the access token, not the refresh token: this is a
 * best-effort, fire-and-forget feature (nothing about ringing depends on it,
 * per ADR-001), not something worth the complexity of a native refresh flow.
 * Dart pushes a fresh token down on every auth-state change and every app
 * foreground, which is the common case an alarm fires in reach of. A token
 * that goes stale during a long stretch with the app unopened just means that
 * one ring session silently does not get reported -- the alarm itself still
 * rings exactly as scheduled.
 */
object AuthStore {
    private const val PREFS = "duet_auth"
    private const val KEY_TOKEN = "access_token"
    private const val KEY_USER = "user_id"

    private fun prefs(ctx: Context) =
        ctx.deviceProtected().getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun set(ctx: Context, accessToken: String?, userId: String?) {
        prefs(ctx).edit()
            .putString(KEY_TOKEN, accessToken)
            .putString(KEY_USER, userId)
            .apply()
    }

    fun accessToken(ctx: Context): String? = prefs(ctx).getString(KEY_TOKEN, null)
    fun userId(ctx: Context): String? = prefs(ctx).getString(KEY_USER, null)
}
