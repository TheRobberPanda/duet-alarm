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
import android.os.Build
import android.os.Bundle
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
    }

    private val ringEnded = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, i: Intent?) = finishRinging()
    }

    override fun onDestroy() {
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
            setBackgroundColor(Color.parseColor("#141110"))
            setPadding(dp(24), dp(40), dp(24), dp(28))
        }

        // ── The dial: two-tone ring with the time inside ──────────────────────
        // Amber is your partner, teal is you. Even alone, the ring is the app's
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
            setTextColor(Color.parseColor("#A08C7C"))
            textSize = 12f
            letterSpacing = 0.22f
            gravity = Gravity.CENTER
        })
        inner.addView(TextView(this).apply {
            text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
            setTextColor(Color.parseColor("#FBF5EF"))
            textSize = 62f
            typeface = Typeface.create("sans-serif-thin", Typeface.NORMAL)
            letterSpacing = 0.03f
            gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            topMargin = dp(6)
        })
        inner.addView(TextView(this).apply {
            text = SimpleDateFormat("EEEE, d MMMM", Locale.getDefault()).format(Date())
            setTextColor(Color.parseColor("#8A7C72"))
            textSize = 13f
            gravity = Gravity.CENTER
        })
        dial.addView(
            inner,
            FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.CENTER)
        )

        root.addView(View(this), LinearLayout.LayoutParams(MATCH_PARENT, 0).apply { weight = 1f })
        root.addView(dial, LinearLayout.LayoutParams(dp(268), dp(268)))
        root.addView(View(this), LinearLayout.LayoutParams(MATCH_PARENT, 0).apply { weight = 1f })

        // ── Controls ─────────────────────────────────────────────────────────
        // These stop YOUR phone only. The "for both of us" variants belong here
        // too (docs/01), deliberately smaller and behind a long press -- but they
        // are omitted until pairing exists rather than shipped as dead buttons.
        val controls = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }

        if (snoozesLeft > 0) {
            controls.addView(
                actionButton("Snooze", "#241D18", "#F5EDE6", outlined = true) { snooze() },
                LinearLayout.LayoutParams(0, dp(72)).apply { weight = 1f; rightMargin = dp(6) }
            )
        }
        controls.addView(
            actionButton("Dismiss", "#E9A35B", "#1B120A", outlined = false) { dismiss() },
            LinearLayout.LayoutParams(0, dp(72)).apply {
                weight = 1f
                if (snoozesLeft > 0) leftMargin = dp(6)
            }
        )
        root.addView(controls, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        root.addView(TextView(this).apply {
            text = when {
                maxSnoozes == 0 -> "Snooze is off for this alarm"
                snoozesLeft == 0 -> "No snoozes left — time to get up"
                snoozeCount > 0 -> "Snooze $snoozeCount of $maxSnoozes · $snoozeMinutes min"
                else -> "Snooze lasts $snoozeMinutes min"
            }
            setTextColor(Color.parseColor("#6E625B"))
            textSize = 13f
            gravity = Gravity.CENTER
            setPadding(0, dp(14), 0, 0)
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
            if (outlined) setStroke(dp(1), Color.parseColor("#3E332B"))
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
 * needs no asset. Right half teal (you), left half amber (them).
 */
private class PairRingView(context: Context) : View(context) {
    private val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = Color.parseColor("#2A231E")
    }
    private val you = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        color = Color.parseColor("#5FB3AE")
    }
    private val them = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        color = Color.parseColor("#E9A35B")
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
