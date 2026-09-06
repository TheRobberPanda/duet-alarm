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
    private const val KEY_SKIN_MINE = "skin_mine"
    private const val KEY_SKIN_PARTNER = "skin_partner"
    private const val KEY_PARTNER_NAME = "partner_name"
    private const val KEY_BG_COLOR = "bg_color"

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

    /**
     * The two ring colors, as ARGB ints, so the ringing screen can wear the
     * skins you picked. Pushed from Dart because that is where the choice
     * lives (theme.dart's SkinColors); 0 means "never set", and the ringing
     * screen keeps its built-in defaults.
     */
    fun setSkinColors(ctx: Context, mine: Int, partner: Int) {
        prefs(ctx).edit()
            .putInt(KEY_SKIN_MINE, mine)
            .putInt(KEY_SKIN_PARTNER, partner)
            .apply()
    }

    fun skinMine(ctx: Context, fallback: Int): Int =
        prefs(ctx).getInt(KEY_SKIN_MINE, 0).takeIf { it != 0 } ?: fallback

    fun skinPartner(ctx: Context, fallback: Int): Int =
        prefs(ctx).getInt(KEY_SKIN_PARTNER, 0).takeIf { it != 0 } ?: fallback

    /**
     * The cosmetic cosmetics: your partner's display name (for the farewell
     * message when a ring ends) and your theme's background color, so the
     * ringing screen dresses in the same world the app does. Both pushed from
     * Dart; 0 / null mean "never set" and the built-in defaults hold.
     */
    fun setCosmetics(ctx: Context, partnerName: String?, bgColor: Int) {
        prefs(ctx).edit()
            .putString(KEY_PARTNER_NAME, partnerName)
            .putInt(KEY_BG_COLOR, bgColor)
            .apply()
    }

    fun partnerName(ctx: Context): String? =
        prefs(ctx).getString(KEY_PARTNER_NAME, null)?.takeIf { it.isNotBlank() }

    fun bgColor(ctx: Context, fallback: Int): Int =
        prefs(ctx).getInt(KEY_BG_COLOR, 0).takeIf { it != 0 } ?: fallback

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
