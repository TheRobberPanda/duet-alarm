package com.duet.alarm

import android.app.*
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.*
import android.util.Log

/**
 * Holds the ringing alarm alive: wake lock, audio on the ALARM stream, vibration,
 * and a full-screen-intent notification that launches RingingActivity.
 *
 * Audio goes out with USAGE_ALARM, which is what makes it play through Do Not
 * Disturb and ignore the media volume slider.
 */
class AlarmService : Service() {

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var currentId: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val id = intent?.getStringExtra(AlarmReceiver.EXTRA_ALARM_ID)
        if (id == null) { stopSelf(); return START_NOT_STICKY }

        if (intent.action == ACTION_STOP) {
            stopRinging()
            return START_NOT_STICKY
        }

        currentId = id
        val def = AlarmStore.find(this, id)
        val label = def?.label?.takeIf { it.isNotBlank() } ?: "Alarm"

        // Must happen within a few seconds of the service starting or the system
        // kills us for not posting a foreground notification.
        startForeground(NOTIF_ID, buildNotification(id, label))

        acquireWakeLock()
        startAudio()
        startVibration()
        RingLog.record(this, id, System.currentTimeMillis())

        // One-shot alarms are spent once they fire.
        AlarmStore.remove(this, id)

        return START_STICKY
    }

    private fun buildNotification(id: String, label: String): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Alarms", NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Ringing alarms"
                // The service plays the audio itself, so the notification is silent.
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                // Best-effort: only takes effect if the app has notification policy
                // access. Audio on USAGE_ALARM already cuts through DND.
                setBypassDnd(true)
            }
            nm.createNotificationChannel(channel)
        }

        val fullScreen = PendingIntent.getActivity(
            this, 1,
            Intent(this, RingingActivity::class.java).apply {
                putExtra(AlarmReceiver.EXTRA_ALARM_ID, id)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL_ID) else
            @Suppress("DEPRECATION") Notification.Builder(this)

        return builder
            .setContentTitle(label)
            .setContentText("Alarm ringing")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setCategory(Notification.CATEGORY_ALARM)
            .setOngoing(true)
            .setAutoCancel(false)
            // The heads-up path when the screen is on; the launch path when locked.
            .setFullScreenIntent(fullScreen, true)
            .setContentIntent(fullScreen)
            .build()
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK, "duet:alarm"
        ).apply { acquire(WAKE_TIMEOUT_MS) }
    }

    private fun startAudio() {
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        try {
            player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@AlarmService, uri)
                isLooping = true
                prepare()
                start()
            }
            // Make sure the alarm stream is actually audible.
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val max = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            if (am.getStreamVolume(AudioManager.STREAM_ALARM) < max / 3) {
                am.setStreamVolume(AudioManager.STREAM_ALARM, max / 2, 0)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "audio failed", t)
        }
    }

    private fun startVibration() {
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION") getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        val pattern = longArrayOf(0, 600, 600)
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0), attrs)
    }

    private fun stopRinging() {
        try { player?.stop() } catch (_: Throwable) {}
        player?.release(); player = null
        vibrator?.cancel(); vibrator = null
        wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        stopRinging()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "DuetService"
        private const val CHANNEL_ID = "duet_alarms"
        private const val NOTIF_ID = 4001
        private const val WAKE_TIMEOUT_MS = 10 * 60 * 1000L
        const val ACTION_STOP = "com.duet.alarm.STOP"

        fun stop(ctx: Context, id: String) {
            ctx.startService(Intent(ctx, AlarmService::class.java).apply {
                action = ACTION_STOP
                putExtra(AlarmReceiver.EXTRA_ALARM_ID, id)
            })
        }
    }
}

/**
 * Records every alarm that actually rang. Milestone 0's most important output:
 * comparing this against what was armed is how a silently-missed alarm becomes a
 * visible, fixable one instead of a one-star review.
 */
object RingLog {
    private const val PREFS = "duet_ring_log"
    fun record(ctx: Context, id: String, at: Long) {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val existing = p.getString("log", "") ?: ""
        p.edit().putString("log", "$id@$at\n$existing".take(4000)).commit()
    }
    fun read(ctx: Context): String =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("log", "") ?: ""
}
