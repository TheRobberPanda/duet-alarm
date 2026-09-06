package com.duet.alarm

import android.content.Context
import android.util.Log

/**
 * The no-Spotify build of [SpotifyRemote].
 *
 * Spotify's App Remote SDK is not published to Maven -- it is an .aar you
 * download from the Spotify developer dashboard after accepting their terms,
 * which is not something this repository can do on your behalf. So the SDK is
 * optional: drop `spotify-app-remote-release.aar` into `app/libs/` and
 * build.gradle.kts swaps this file for the real implementation in
 * `src/spotify/kotlin`. Both expose exactly this API.
 *
 * Until then every Spotify alarm simply rings with its fallback tone, which is
 * the same thing that happens when Spotify is uninstalled, logged out, not
 * Premium, or offline. That is the whole design: see AlarmService.startAudio.
 */
object SpotifyRemote {
    private const val TAG = "DuetSpotify"

    /** No SDK, so nothing to connect to. */
    fun available(ctx: Context): Boolean = false

    fun play(ctx: Context, uri: String, onPlaying: (Boolean) -> Unit) {
        Log.i(TAG, "no Spotify SDK in this build; $uri stays on its fallback tone")
        onPlaying(false)
    }

    fun stop() { /* nothing was ever started */ }
}
