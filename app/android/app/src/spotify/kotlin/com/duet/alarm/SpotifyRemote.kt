package com.duet.alarm

import android.content.Context
import android.util.Log
import com.spotify.android.appremote.api.ConnectionParams
import com.spotify.android.appremote.api.Connector
import com.spotify.android.appremote.api.SpotifyAppRemote

/**
 * Plays an alarm through the Spotify app, WITHOUT ever being the reason an
 * alarm makes noise.
 *
 * Compiled only when `app/libs/spotify-app-remote-release.aar` is present; see
 * the stub in `src/nospotify/kotlin` for why the SDK is optional and for the
 * contract both versions share.
 *
 * ## The rule this file obeys
 *
 * ADR-001 says the network may never be what makes a phone ring. Spotify is
 * worse than the network: it needs the Spotify app installed, a logged-in
 * account, an active Premium subscription AND connectivity, any of which can
 * be gone at 06:00 without warning. So this is never the alarm -- it is an
 * upgrade applied to an alarm that is already ringing. AlarmService starts the
 * fallback tone first and only silences it once [play] reports that Spotify is
 * genuinely producing sound. Every failure path here calls back `false` and
 * the tone simply carries on, which is why none of them are loud.
 */
object SpotifyRemote {
    private const val TAG = "DuetSpotify"

    /** How long Spotify gets to actually start playing before we give up on it
     *  and leave the fallback tone alone. Short on purpose: a bedside alarm
     *  cannot spend ten seconds deciding how loud to be. */
    private const val CONNECT_TIMEOUT_MS = 4000L

    private var remote: SpotifyAppRemote? = null

    fun available(ctx: Context): Boolean =
        SpotifyConfig.clientId.isNotEmpty() &&
            SpotifyAppRemote.isSpotifyInstalled(ctx)

    fun play(ctx: Context, uri: String, onPlaying: (Boolean) -> Unit) {
        if (!available(ctx)) return onPlaying(false)

        // Answered at most once: a timeout that fires after a late success (or
        // the reverse) would either silence a silent phone or leave two sounds
        // playing over each other.
        val answered = java.util.concurrent.atomic.AtomicBoolean(false)
        fun answer(playing: Boolean) {
            if (answered.compareAndSet(false, true)) onPlaying(playing)
        }

        android.os.Handler(android.os.Looper.getMainLooper())
            .postDelayed({
                if (!answered.get()) {
                    Log.w(TAG, "Spotify did not start in time; keeping the fallback tone")
                    answer(false)
                }
            }, CONNECT_TIMEOUT_MS)

        val params = ConnectionParams.Builder(SpotifyConfig.clientId)
            .setRedirectUri(SpotifyConfig.REDIRECT_URI)
            .showAuthView(false) // never put a login wall in front of a ringing alarm
            .build()

        SpotifyAppRemote.connect(ctx, params, object : Connector.ConnectionListener {
            override fun onConnected(connected: SpotifyAppRemote) {
                remote = connected
                connected.playerApi.play(uri)
                // Trust the player state, not the play() call: a non-Premium
                // account accepts the request and then plays nothing, which is
                // exactly the silent morning this whole design exists to avoid.
                connected.playerApi.subscribeToPlayerState()
                    .setEventCallback { state ->
                        if (!state.isPaused && state.track != null) answer(true)
                    }
                    .setErrorCallback {
                        Log.w(TAG, "player state unavailable", it)
                        answer(false)
                    }
            }

            override fun onFailure(error: Throwable) {
                Log.w(TAG, "Spotify connect failed; keeping the fallback tone", error)
                answer(false)
            }
        })
    }

    fun stop() {
        val r = remote ?: return
        remote = null
        runCatching { r.playerApi.pause() }
        runCatching { SpotifyAppRemote.disconnect(r) }
    }
}
