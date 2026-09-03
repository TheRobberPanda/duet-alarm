package com.duet.alarm

import android.app.*
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
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
        startForeground(NOTIF_ID, buildNotification(id, label, def))

        acquireWakeLock()
        startAudio(def?.soundRef ?: "default")
        startVibration()
        RingLog.record(this, id, System.currentTimeMillis())
        reportRinging(def)

        // A repeating alarm must schedule its own next occurrence HERE, while we
        // have the definition in hand.
        //
        // Dart arms a rolling 48-hour window, but only when the app runs. A
        // Monday-only alarm that fires on Monday would otherwise sit unarmed
        // until the user happened to open the app -- and if they did not, it
        // would simply never ring again. Nothing would report it, either: it was
        // never armed, so it cannot be "missed".
        //
        // The wall clock travels with the definition precisely so this can be
        // computed without a Flutter engine. Dart's reconcile stays
        // authoritative and will correct anything this gets wrong.
        rearmNextOccurrence(def)

        // The instant that just fired is spent either way.
        AlarmStore.remove(this, id)

        return START_STICKY
    }

    /** Only a shared alarm (pairId set) is worth reporting -- see RingSync.kt. */
    private fun reportRinging(def: AlarmDef?) {
        if (def == null) return
        val (alarmId, firedAt) = splitFireId(def.baseId) ?: return
        RingSync.startRinging(this, alarmId, firedAt, def.pairId)
    }

    private fun rearmNextOccurrence(def: AlarmDef?) {
        if (def == null || def.repeatDays == 0) return
        if (def.id.startsWith(AlarmDef.SNOOZE_PREFIX)) return
        if (def.wallHour !in 0..23 || def.wallMinute !in 0..59) return

        val next = NextFire.next(
            hour = def.wallHour,
            minute = def.wallMinute,
            repeatDays = def.repeatDays,
            after = System.currentTimeMillis()
        ) ?: return

        val base = def.id.substringBefore('#')
        AlarmScheduler.arm(this, def.copy(id = "$base#$next", fireAtUtc = next, snoozeCount = 0))
        Log.i(TAG, "re-armed $base for next occurrence at $next")
    }

    private fun buildNotification(id: String, label: String, def: AlarmDef?): Notification {
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
                // The whole definition rides on the intent: the service deletes
                // the stored alarm once it fires (a one-shot is spent), so the
                // ringing screen cannot look it up afterwards.
                putExtra(AlarmReceiver.EXTRA_ALARM_ID, id)
                putExtra("label", label)
                putExtra("soundRef", def?.soundRef ?: "default")
                putExtra("snoozeMinutes", def?.snoozeMinutes ?: 9)
                putExtra("maxSnoozes", def?.maxSnoozes ?: 3)
                putExtra("snoozeCount", def?.snoozeCount ?: 0)
                putExtra("pairId", def?.pairId)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL_ID) else
            @Suppress("DEPRECATION") Notification.Builder(this)

        // Actions matter most when the phone is already in use: Android
        // suppresses the full-screen intent then and shows a heads-up instead,
        // so without these the only way to stop the alarm is to tap through to
        // the ringing screen first.
        fun action(act: String, extra: Int) = PendingIntent.getBroadcast(
            this, extra,
            Intent(this, AlarmActionReceiver::class.java).apply {
                action = act
                setPackage(packageName)
                putExtra(AlarmReceiver.EXTRA_ALARM_ID, id)
                putExtra("label", label)
                putExtra("soundRef", def?.soundRef ?: "default")
                putExtra("snoozeMinutes", def?.snoozeMinutes ?: 9)
                putExtra("maxSnoozes", def?.maxSnoozes ?: 3)
                putExtra("snoozeCount", def?.snoozeCount ?: 0)
                putExtra("pairId", def?.pairId)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val snoozesLeft = (def?.maxSnoozes ?: 3) - (def?.snoozeCount ?: 0)

        builder
            .setContentTitle(label)
            .setContentText("Alarm ringing")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setCategory(Notification.CATEGORY_ALARM)
            .setOngoing(true)
            .setAutoCancel(false)
            // The heads-up path when the screen is on; the launch path when locked.
            .setFullScreenIntent(fullScreen, true)
            .setContentIntent(fullScreen)

        if (snoozesLeft > 0) {
            builder.addAction(
                Notification.Action.Builder(
                    null, "Snooze", action(AlarmActionReceiver.ACTION_SNOOZE, 10)
                ).build()
            )
        }
        builder.addAction(
            Notification.Action.Builder(
                null, "Dismiss", action(AlarmActionReceiver.ACTION_DISMISS, 11)
            ).build()
        )

        return builder.build()
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK, "duet:alarm"
        ).apply { acquire(WAKE_TIMEOUT_MS) }
    }

    private fun startAudio(soundRef: String) {
        val uri = SoundCatalog.resolve(this, soundRef)
        if (uri == null) {
            Log.e(TAG, "no playable sound for '$soundRef' -- alarm will be silent")
            return
        }
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
        val p = ctx.deviceProtected().getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val existing = p.getString("log", "") ?: ""
        p.edit().putString("log", "$id@$at\n$existing".take(4000)).commit()
    }
    fun read(ctx: Context): String =
        ctx.deviceProtected().getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString("log", "") ?: ""
}
