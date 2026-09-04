package com.duet.alarm

import android.app.Activity
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.*

/**
 * Deliberately NOT a Flutter screen.
 *
 * Cold-starting the Flutter engine from a locked screen at 06:00 adds latency and
 * a class of failure that cannot be debugged from bed -- on the one screen that
 * absolutely must work. This is plain Android views with no dependencies, so it
 * keeps working even if the Flutter side is broken entirely, and it can run
 * before first unlock (directBootAware) after an overnight reboot.
 * See docs/12-roadblocks.md section 3.2.
 */
class RingingActivity : Activity() {

    private var alarmId: String? = null
    private var snoozeMinutes = 9
    private var maxSnoozes = 3
    private var snoozeCount = 0
    private var soundRef = "default"
    private var label = "Alarm"
    private var pairId: String? = null
    private var awarenessView: TextView? = null
    private val pollHandler = Handler(Looper.getMainLooper())
    private var sensorManager: SensorManager? = null
    private var proximityTriggered = false

    private val snoozesLeft get() = (maxSnoozes - snoozeCount).coerceAtLeast(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockScreen()

        alarmId = intent.getStringExtra(AlarmReceiver.EXTRA_ALARM_ID)
        label = intent.getStringExtra("label")?.takeIf { it.isNotBlank() } ?: "Alarm"
        soundRef = intent.getStringExtra("soundRef") ?: "default"
        snoozeMinutes = intent.getIntExtra("snoozeMinutes", 9)
        maxSnoozes = intent.getIntExtra("maxSnoozes", 3)
        snoozeCount = intent.getIntExtra("snoozeCount", 0)
        pairId = intent.getStringExtra("pairId")

        setContentView(buildUi())

        // If the user acts on the notification instead, this screen must go too.
        ContextCompat.registerReceiver(
            this, ringEnded, IntentFilter(AlarmActions.ACTION_RING_ENDED),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )

        startAwarenessPolling()
        startProximityGesture()
    }

    /**
     * Milestone 4's live awareness strip -- "Sam snoozed", "Sam is ringing too" --
     * polled rather than pushed: this screen has no Flutter engine and no
     * realtime channel, just RingSync's plain REST calls. A few seconds of
     * staleness on a strip that is itself a nice-to-have is a fine trade for not
     * building a socket connection into the one screen that must never hang.
     */
    private fun startAwarenessPolling() {
        val id = alarmId ?: return
        if (pairId == null) return
        val (base, firedAt) = splitFireId(id.removePrefix(AlarmDef.SNOOZE_PREFIX)) ?: return

        val poll = object : Runnable {
            override fun run() {
                RingSync.fetchPartnerState(this@RingingActivity, base, firedAt, pairId) { state ->
                    runOnUiThread { showAwareness(state) }
                }
                pollHandler.postDelayed(this, 4000)
            }
        }
        pollHandler.post(poll)
    }

    private fun showAwareness(state: String?) {
        val view = awarenessView ?: return
        val text = when (state) {
            "ringing" -> "They're ringing too"
            "snoozed" -> "They snoozed"
            "dismissed" -> "They're up"
            else -> null // no row yet, or the request failed -- say nothing rather than guess
        }
        view.text = text ?: ""
        view.visibility = if (text == null) View.GONE else View.VISIBLE
    }

    /**
     * Wave-to-snooze: covering the top of the phone snoozes it without needing
     * to look at or unlock the screen. Only armed when a snooze is actually
     * available -- a wave over a phone with none left would do nothing, which
     * is worse than the gesture not existing at all. [proximityTriggered]
     * fires it once per ring rather than once per "near" reading, since the
     * sensor stays near for as long as a hand or a pocket covers it.
     */
    private fun startProximityGesture() {
        if (snoozesLeft <= 0) return
        val sm = getSystemService(Context.SENSOR_SERVICE) as? SensorManager ?: return
        val sensor = sm.getDefaultSensor(Sensor.TYPE_PROXIMITY) ?: return
        sensorManager = sm
        sm.registerListener(proximityListener, sensor, SensorManager.SENSOR_DELAY_NORMAL)
    }

    private val proximityListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            if (proximityTriggered) return
            val near = event.values.isNotEmpty() && event.values[0] < event.sensor.maximumRange
            if (near) {
                proximityTriggered = true
                vibrateConfirm()
                runOnUiThread { snooze() }
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }

    /** The one bit of feedback a gesture needs when the screen is about to
     *  close anyway -- there is no time for a visual confirmation to register. */
    private fun vibrateConfirm() {
        @Suppress("DEPRECATION")
        val v = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        v?.vibrate(VibrationEffect.createOneShot(80, VibrationEffect.DEFAULT_AMPLITUDE))
    }

    /**
     * "For both of us" -- ADR-006's deliberate secondary action, reached by a
     * long press rather than a second button so it cannot be hit by accident.
     * Stops your own alarm too: dismissing for both while yours kept ringing
     * would be a confusing halfway state.
     */
    private fun dismissForBoth() {
        val id = alarmId ?: return
        val base = id.removePrefix(AlarmDef.SNOOZE_PREFIX)
        val (alarm, firedAt) = splitFireId(base) ?: return dismiss()
        vibrateConfirm()
        RingSync.actOnPartner(this, alarm, firedAt, pairId, "dismiss") { }
        dismiss()
    }

    private val ringEnded = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, i: Intent?) = finishRinging()
    }

    override fun onDestroy() {
        pollHandler.removeCallbacksAndMessages(null)
        sensorManager?.unregisterListener(proximityListener)
        runCatching { unregisterReceiver(ringEnded) }
        super.onDestroy()
    }

    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            (getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager)
                .requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun buildUi(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(Color.parseColor("#150F14"))
            setPadding(dp(24), dp(40), dp(24), dp(28))
        }

        // ── The dial: two-tone ring with the time inside ──────────────────────
        // Lavender is you, pink is your partner. Even alone, the ring is the app's
        // signature mark and the thing that says "this is Duet, not a stock
        // alarm" to someone squinting at 06:00.
        val dial = FrameLayout(this)
        dial.addView(
            PairRingView(this),
            FrameLayout.LayoutParams(dp(268), dp(268), Gravity.CENTER)
        )

        val inner = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }
        inner.addView(TextView(this).apply {
            text = label.uppercase()
            setTextColor(Color.parseColor("#A88B9B"))
            textSize = 12f
            letterSpacing = 0.22f
            gravity = Gravity.CENTER
        })
        inner.addView(TextView(this).apply {
            text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
            setTextColor(Color.parseColor("#FBF0F6"))
            textSize = 62f
            typeface = Typeface.create("sans-serif-thin", Typeface.NORMAL)
            letterSpacing = 0.03f
            gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            topMargin = dp(6)
        })
        inner.addView(TextView(this).apply {
            text = SimpleDateFormat("EEEE, d MMMM", Locale.getDefault()).format(Date())
            setTextColor(Color.parseColor("#8F7A88"))
            textSize = 13f
            gravity = Gravity.CENTER
        })
        dial.addView(
            inner,
            FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.CENTER)
        )

        root.addView(View(this), LinearLayout.LayoutParams(MATCH_PARENT, 0).apply { weight = 1f })
        root.addView(dial, LinearLayout.LayoutParams(dp(268), dp(268)))

        // Milestone 4's live awareness strip. Empty and GONE until polling finds
        // a partner row to report -- see startAwarenessPolling().
        awarenessView = TextView(this).apply {
            setTextColor(Color.parseColor("#C9AEE8"))
            textSize = 14f
            gravity = Gravity.CENTER
            visibility = View.GONE
        }
        root.addView(awarenessView, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            topMargin = dp(18)
        })

        root.addView(View(this), LinearLayout.LayoutParams(MATCH_PARENT, 0).apply { weight = 1f })

        // ── Controls ─────────────────────────────────────────────────────────
        // These stop YOUR phone only. The "for both of us" variants belong here
        // too (docs/01) -- reached by a LONG PRESS on Dismiss rather than a
        // second button, so it cannot be hit by accident (ADR-006).
        val controls = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }

        if (snoozesLeft > 0) {
            controls.addView(
                actionButton("Snooze", "#33232D", "#F5EDE6", outlined = true) { snooze() },
                LinearLayout.LayoutParams(0, dp(72)).apply { weight = 1f; rightMargin = dp(6) }
            )
        }
        controls.addView(
            actionButton("Dismiss", "#F0A8C8", "#3D1526", outlined = false) { dismiss() }
                .apply {
                    if (pairId != null) {
                        setOnLongClickListener { dismissForBoth(); true }
                    }
                },
            LinearLayout.LayoutParams(0, dp(72)).apply {
                weight = 1f
                if (snoozesLeft > 0) leftMargin = dp(6)
            }
        )
        root.addView(controls, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        root.addView(TextView(this).apply {
            text = listOfNotNull(
                when {
                    maxSnoozes == 0 -> "Snooze is off for this alarm"
                    snoozesLeft == 0 -> "No snoozes left — time to get up"
                    snoozeCount > 0 -> "Snooze $snoozeCount of $maxSnoozes · $snoozeMinutes min"
                    else -> "Snooze lasts $snoozeMinutes min"
                },
                "wave over the top to snooze".takeIf { snoozesLeft > 0 },
                "hold Dismiss to end it for both".takeIf { pairId != null },
            ).joinToString(" · ")
            setTextColor(Color.parseColor("#776273"))
            textSize = 13f
            gravity = Gravity.CENTER
            setPadding(dp(20), dp(14), dp(20), 0)
        })

        return root
    }

    private fun actionButton(
        label: String, bg: String, fg: String, outlined: Boolean, onClick: () -> Unit
    ) = Button(this).apply {
        text = label
        isAllCaps = false
        textSize = 18f
        setTextColor(Color.parseColor(fg))
        background = GradientDrawable().apply {
            cornerRadius = dp(20).toFloat()
            setColor(Color.parseColor(bg))
            if (outlined) setStroke(dp(1), Color.parseColor("#4A3540"))
        }
        stateListAnimator = null
        setOnClickListener { onClick() }
    }

    // Both actions live in AlarmActions so this screen and the notification
    // cannot drift apart. A dismiss that only half-worked from one of them
    // would be a very bad bug.
    private fun snooze() {
        val id = alarmId ?: return finishRinging()
        AlarmActions.snooze(
            ctx = this,
            alarmId = id,
            label = label,
            soundRef = soundRef,
            snoozeMinutes = snoozeMinutes,
            maxSnoozes = maxSnoozes,
            snoozeCount = snoozeCount,
            pairId = pairId
        )
        finishRinging()
    }

    private fun dismiss() {
        alarmId?.let { AlarmActions.dismiss(this, it, pairId) }
        finishRinging()
    }

    private fun finishRinging() {
        finish()
        // No transition -- at 06:00 an animation just looks like a stutter.
        overridePendingTransition(0, 0)
    }

    /** Back must not silently kill the alarm. */
    override fun onBackPressed() { /* intentionally ignored */ }
}

/**
 * The two-tone ring, drawn rather than bundled so it scales to any density and
 * needs no asset. Right half lavender (you), left half pink (them).
 */
private class PairRingView(context: Context) : View(context) {
    private val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = Color.parseColor("#33232D")
    }
    private val you = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        color = Color.parseColor("#C9AEE8")
    }
    private val them = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        color = Color.parseColor("#F0A8C8")
    }

    override fun onDraw(canvas: Canvas) {
        val stroke = width * 0.011f
        track.strokeWidth = stroke
        you.strokeWidth = stroke * 1.6f
        them.strokeWidth = stroke * 1.6f

        val pad = stroke * 2f
        val rect = RectF(pad, pad, width - pad, height - pad)

        canvas.drawArc(rect, 0f, 360f, false, track)
        canvas.drawArc(rect, -90f, 180f, false, you)
        canvas.drawArc(rect, 90f, 180f, false, them)
    }
}
