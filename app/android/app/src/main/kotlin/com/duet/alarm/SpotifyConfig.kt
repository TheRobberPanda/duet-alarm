package com.duet.alarm

/**
 * The Spotify app registration.
 *
 * Empty by default, and empty means the feature is simply off -- no crash, no
 * warning at 06:00, alarms ring on their fallback tone exactly as they always
 * have. Fill it in with the Client ID from your own app at
 * developer.spotify.com/dashboard, where you must also register [REDIRECT_URI]
 * and the package name and signing fingerprint of this build.
 *
 * Passed in at build time rather than committed, the same bargain the rest of
 * the project makes about credentials:
 *
 *   flutter build apk --dart-define=DUET_BACKEND=true \
 *     -Pspotify.clientId=xxxxxxxxxxxxxxxx
 *
 * There is nothing secret here -- a Spotify Client ID is public by design,
 * like the Supabase publishable key -- it is kept out of the source only so
 * that a fork does not silently ship someone else's quota.
 */
object SpotifyConfig {
    /** Supplied by build.gradle.kts from -Pspotify.clientId; "" when absent. */
    val clientId: String get() = BuildConfig.SPOTIFY_CLIENT_ID

    /** Must match the redirect URI registered in the Spotify dashboard, and
     *  the intent filter is not needed for App Remote -- only for the OAuth
     *  flow, which Duet does not run: picking a song is done by pasting a
     *  Spotify link, so there is nothing to log in to. */
    const val REDIRECT_URI = "duet://spotify-callback"
}
