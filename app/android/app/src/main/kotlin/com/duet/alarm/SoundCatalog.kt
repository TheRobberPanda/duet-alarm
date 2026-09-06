package com.duet.alarm

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.util.Log

/**
 * The sounds an alarm can use.
 *
 * Everything here comes from the phone itself. Shipping no audio files at all
 * means there is no sound-licensing audit to get wrong (docs/12 section 3.7),
 * every device offers tones its owner already recognises as alarms, and the APK
 * stays small. Custom recordings arrive with Duet Full (docs/05) and will be
 * user-generated, which is a different licensing question entirely.
 */
object SoundCatalog {
    private const val TAG = "DuetSounds"
    private var preview: MediaPlayer? = null

    /** A Spotify track or playlist, e.g. `spotify:track:4cOdK2wGLETKBW3PvgPWqT`. */
    const val SPOTIFY_PREFIX = "spotify:"

    /**
     * `default` resolves to the system alarm tone, falling back to the ringtone.
     *
     * A `spotify:` ref resolves here TOO, and deliberately: this returns the
     * sound that will actually come out of the phone, and for a Spotify alarm
     * that is the fallback tone until Spotify is confirmed to be playing (see
     * AlarmService.startAudio). Resolving it to null instead would mean a
     * silent morning every time Spotify was uninstalled, logged out, no longer
     * Premium, or simply offline.
     */
    fun resolve(ctx: Context, soundRef: String): Uri? = when {
        soundRef.startsWith("device:") ->
            runCatching { Uri.parse(soundRef.removePrefix("device:")) }.getOrNull()
                ?: defaultAlarm()
        else -> defaultAlarm()
    }

    private fun defaultAlarm(): Uri? =
        RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)

    /**
     * Alarm tones first, then notification tones as a fallback: some devices
     * ship almost no dedicated alarm sounds, and an empty picker looks broken.
     */
    fun list(ctx: Context): List<Map<String, String>> {
        val out = mutableListOf<Map<String, String>>()
        out.add(mapOf("ref" to "default", "title" to "Default alarm", "kind" to "default"))

        fun collect(type: Int, kind: String) {
            try {
                val rm = RingtoneManager(ctx).apply { setType(type) }
                val cursor = rm.cursor
                while (cursor.moveToNext()) {
                    val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
                    val uri = rm.getRingtoneUri(cursor.position)?.toString() ?: continue
                    out.add(mapOf("ref" to "device:$uri", "title" to title, "kind" to kind))
                }
            } catch (t: Throwable) {
                Log.w(TAG, "could not read $kind tones", t)
            }
        }

        collect(RingtoneManager.TYPE_ALARM, "alarm")
        if (out.size <= 1) collect(RingtoneManager.TYPE_NOTIFICATION, "notification")
        return out
    }

    /**
     * Previews on the ALARM stream, exactly as the real thing will sound --
     * previewing on the media stream would let someone pick a tone that turns
     * out to be inaudible at 06:00.
     */
    fun preview(ctx: Context, soundRef: String) {
        stopPreview()
        val uri = resolve(ctx, soundRef) ?: return
        try {
            preview = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(ctx, uri)
                isLooping = false
                setOnCompletionListener { stopPreview() }
                prepare()
                start()
            }
        } catch (t: Throwable) {
            Log.w(TAG, "preview failed for $soundRef", t)
        }
    }

    fun stopPreview() {
        try { preview?.stop() } catch (_: Throwable) {}
        preview?.release()
        preview = null
    }
}
