package com.duet.alarm

import android.content.Context

/**
 * The one piece of Supabase auth the native side needs: enough to write a ring
 * session as the signed-in user (RingSync.kt) with no Flutter engine running.
 *
 * Device-protected storage, like AlarmStore -- a phone that reboots overnight
 * has to be able to report a ring before it is ever unlocked.
 *
 * This used to hold only the access token, on the reasoning that native
 * networking was cosmetic -- a stale token just meant one ring session went
 * unreported, and the alarm rang regardless (ADR-001).
 *
 * AlarmPull.kt changed that bargain. The native side is now how a partner's
 * newly created alarm reaches this phone while the app is closed, and a
 * Supabase access token lasts one hour. Overnight -- the exact stretch that
 * matters -- the token is always expired, so a pull with no way to refresh
 * would 401 in silence and the alarm would not ring. That is a missed alarm,
 * not a missing nicety, so the refresh token lives here too and
 * [refreshedAccessToken] mints a new one.
 *
 * ADR-001 still holds: none of this is what makes a phone ring. It is how the
 * schedule gets delivered in advance, and a phone with no network keeps
 * ringing everything it already holds.
 */
object AuthStore {
    private const val PREFS = "duet_auth"
    private const val KEY_TOKEN = "access_token"
    private const val KEY_REFRESH = "refresh_token"
    private const val KEY_USER = "user_id"
    private const val KEY_PAIR = "pair_id"
    private const val KEY_LAN_SECRET = "lan_secret"
    private const val KEY_ALLOW_PARTNER_DISMISS = "allow_partner_dismiss"
    private const val KEY_SKIN_MINE = "skin_mine"
    private const val KEY_SKIN_PARTNER = "skin_partner"
    private const val KEY_PARTNER_NAME = "partner_name"
    private const val KEY_MY_NAME = "my_name"
    private const val KEY_BG_COLOR = "bg_color"

    private fun prefs(ctx: Context) =
        ctx.deviceProtected().getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun set(ctx: Context, accessToken: String?, userId: String?, refreshToken: String? = null) {
        prefs(ctx).edit()
            .putString(KEY_TOKEN, accessToken)
            .putString(KEY_USER, userId)
            .putString(KEY_REFRESH, refreshToken)
            // commit, not apply: a sign-out that is still in flight when the
            // process dies would leave a live token on disk.
            .commit()
    }

    fun refreshToken(ctx: Context): String? = prefs(ctx).getString(KEY_REFRESH, null)

    /** Stores the pair Supabase handed back from a refresh, so the next wake
     *  starts from the new one rather than refreshing every single time. */
    fun updateTokens(ctx: Context, accessToken: String, refreshToken: String?) {
        prefs(ctx).edit()
            .putString(KEY_TOKEN, accessToken)
            .apply { if (refreshToken != null) putString(KEY_REFRESH, refreshToken) }
            .commit()
    }

    /**
     * An access token good for at least another minute, refreshing it first if
     * not. Returns null when there is nothing to work with -- signed out, or a
     * refresh that failed -- which every caller treats as "do nothing".
     *
     * Blocking, and must be called off the main thread.
     */
    fun freshAccessToken(ctx: Context): String? {
        val current = accessToken(ctx) ?: return null
        if (!expiresWithin(current, seconds = 60)) return current

        val refresh = refreshToken(ctx) ?: return current
        val minted = SupabaseAuth.refresh(refresh) ?: return current
        updateTokens(ctx, minted.first, minted.second)
        return minted.first
    }

    /**
     * Reads `exp` out of the JWT payload without verifying the signature --
     * which is correct here: we are not authenticating anything, only asking
     * "is it worth sending this?". A token we cannot parse is treated as
     * expired, so the refresh path runs rather than a doomed request.
     */
    private fun expiresWithin(jwt: String, seconds: Long): Boolean = try {
        val payload = jwt.split(".").getOrNull(1) ?: throw IllegalArgumentException("no payload")
        val json = String(
            android.util.Base64.decode(payload, android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING)
        )
        val exp = org.json.JSONObject(json).getLong("exp")
        exp * 1000L - System.currentTimeMillis() < seconds * 1000L
    } catch (t: Throwable) {
        true
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
    fun setCosmetics(ctx: Context, partnerName: String?, myName: String?, bgColor: Int) {
        prefs(ctx).edit()
            .putString(KEY_PARTNER_NAME, partnerName)
            .putString(KEY_MY_NAME, myName)
            .putInt(KEY_BG_COLOR, bgColor)
            .apply()
    }

    fun partnerName(ctx: Context): String? =
        prefs(ctx).getString(KEY_PARTNER_NAME, null)?.takeIf { it.isNotBlank() }

    fun myName(ctx: Context): String? =
        prefs(ctx).getString(KEY_MY_NAME, null)?.takeIf { it.isNotBlank() }

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
