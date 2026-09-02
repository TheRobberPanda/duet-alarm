package com.duet.alarm

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.graphics.Color
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
 * keeps working even if the Flutter side is broken entirely.
 * See docs/12-roadblocks.md section 3.2.
 */
class RingingActivity : Activity() {

    private var alarmId: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockScreen()

        alarmId = intent.getStringExtra(AlarmReceiver.EXTRA_ALARM_ID)
        val label = intent.getStringExtra("label") ?: "Alarm"

        setContentView(buildUi(label))
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

    private fun buildUi(label: String): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(Color.parseColor("#141110"))
            setPadding(dp(24), dp(48), dp(24), dp(32))
        }

        root.addView(TextView(this).apply {
            text = label.uppercase()
            setTextColor(Color.parseColor("#A08C7C"))
            textSize = 13f
            letterSpacing = 0.22f
            gravity = Gravity.CENTER
        })

        val clock = TextView(this).apply {
            text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
            setTextColor(Color.parseColor("#FBF5EF"))
            textSize = 82f
            typeface = Typeface.create("sans-serif-thin", Typeface.NORMAL)
            letterSpacing = 0.04f
            gravity = Gravity.CENTER
        }
        root.addView(clock, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
            topMargin = dp(16)
        })

        root.addView(TextView(this).apply {
            text = SimpleDateFormat("EEEE, d MMMM", Locale.getDefault()).format(Date())
            setTextColor(Color.parseColor("#8A7C72"))
            textSize = 15f
            gravity = Gravity.CENTER
        })

        // Spacer pushes the controls to the bottom of the screen.
        root.addView(View(this), LinearLayout.LayoutParams(MATCH_PARENT, 0).apply { weight = 1f })

        // Primary row: these stop YOUR phone only. In Milestone 0 there is no
        // partner yet, but the hierarchy is built in from the start so the
        // "for both" actions are never the easy mis-tap. See docs/01-product-spec.md.
        val primary = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }

        primary.addView(
            actionButton("Snooze", "#241D18", "#F5EDE6", outlined = true) { snooze() },
            LinearLayout.LayoutParams(0, dp(72)).apply { weight = 1f; rightMargin = dp(6) }
        )
        primary.addView(
            actionButton("Dismiss", "#E9A35B", "#1B120A", outlined = false) { dismiss() },
            LinearLayout.LayoutParams(0, dp(72)).apply { weight = 1f; leftMargin = dp(6) }
        )
        root.addView(primary, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        root.addView(TextView(this).apply {
            text = "Stops your phone only"
            setTextColor(Color.parseColor("#6E625B"))
            textSize = 13f
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, 0)
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

    private fun snooze() {
        val id = alarmId ?: return finishRinging()
        AlarmService.stop(this, id)
        // Milestone 0 keeps this simple: a fresh one-shot 9 minutes out.
        val next = System.currentTimeMillis() + 9 * 60 * 1000L
        AlarmScheduler.arm(
            this,
            AlarmDef(id = "$id-snooze", fireAtUtc = next, label = "Snoozed", soundRef = "default")
        )
        finishRinging()
    }

    private fun dismiss() {
        alarmId?.let { AlarmService.stop(this, it) }
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
