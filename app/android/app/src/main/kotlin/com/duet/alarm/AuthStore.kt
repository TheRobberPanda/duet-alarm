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
    private const val KEY_PAIR = "pair_id"
    private const val KEY_LAN_SECRET = "lan_secret"
    private const val KEY_ALLOW_PARTNER_DISMISS = "allow_partner_dismiss"

    private fun prefs(ctx: Context) =
        ctx.deviceProtected().getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun set(ctx: Context, accessToken: String?, userId: String?) {
        prefs(ctx).edit()
            .putString(KEY_TOKEN, accessToken)
            .putString(KEY_USER, userId)
            .apply()
    }

    /**
     * The pair context LanSync needs to sign, route and authorise datagrams.
     * Pushed down separately from the token because it changes on a different
     * schedule -- pairing and preference changes, not auth refreshes.
     */
    fun setPairContext(
        ctx: Context,
        pairId: String?,
        lanSecret: String?,
        allowPartnerDismiss: Boolean,
    ) {
        prefs(ctx).edit()
            .putString(KEY_PAIR, pairId)
            .putString(KEY_LAN_SECRET, lanSecret)
            .putBoolean(KEY_ALLOW_PARTNER_DISMISS, allowPartnerDismiss)
            .apply()
    }

    fun accessToken(ctx: Context): String? = prefs(ctx).getString(KEY_TOKEN, null)
    fun userId(ctx: Context): String? = prefs(ctx).getString(KEY_USER, null)
    fun pairId(ctx: Context): String? = prefs(ctx).getString(KEY_PAIR, null)
    fun lanSecret(ctx: Context): String? = prefs(ctx).getString(KEY_LAN_SECRET, null)

    /** Defaults to true, matching the column default -- but a phone that has
     *  never synced should not be MORE permissive than one that has, so the
     *  LAN path also requires a pair context to exist before it acts at all. */
    fun allowPartnerDismiss(ctx: Context): Boolean =
        prefs(ctx).getBoolean(KEY_ALLOW_PARTNER_DISMISS, true)
}
