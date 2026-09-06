package com.duet.alarm

import android.animation.ValueAnimator
import android.app.Activity
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import androidx.core.graphics.ColorUtils
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
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
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.*

// Hand-mirrored from Flutter's DuetColors (theme.dart). The ringing screen
// cannot read Dart state, so these constants shadow it -- when you change the
// palette in theme.dart, change them here too. Names below note the token.
private val BG_DEEP = Color.parseColor("#150F14")      // DuetColors.bgDeep
private val SURFACE = Color.parseColor("#251A22")      // DuetColors.surface
private val LINE = Color.parseColor("#402C38")         // DuetColors.line
private val TEXT = Color.parseColor("#F9EBF3")         // DuetColors.text
private val MUTED = Color.parseColor("#CBA8BE")        // DuetColors.muted
private val DIM = Color.parseColor("#937284")          // DuetColors.dim
private val ON_ACCENT = Color.parseColor("#3D1526")    // DuetColors.amberInk

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
    private var awarenessWrap: View? = null
    private lateinit var awarenessText: TextView

    // Last state the poll or LAN relay reported for your partner -- the
    // farewell message is derived from it, so an uncertain state says nothing
    // rather than a wrong name.
    private var lastPartnerState: String? = null

    private lateinit var rootLayout: LinearLayout
    private val farewellHandler = Handler(Looper.getMainLooper())
    private val pollHandler = Handler(Looper.getMainLooper())

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
        ContextCompat.registerReceiver(
            this, partnerStateOverLan, IntentFilter(LanSync.ACTION_PARTNER_STATE),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )

        startAwarenessPolling()
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
        lastPartnerState = state ?: lastPartnerState
        val wrap = awarenessWrap ?: return
        val text = when (state) {
            "ringing" -> "They're ringing too"
            "snoozed" -> "They snoozed"
            "dismissed" -> "They're up"
            else -> null // no row yet, or the request failed -- say nothing rather than guess
        }
        if (text == null) {
            wrap.visibility = View.GONE
        } else {
            awarenessText.text = text
            wrap.visibility = View.VISIBLE
        }
    }

    /** The one bit of feedback a gesture needs when the screen is about to
     *  close anyway -- there is no time for a visual confirmation to register.
     *  Release-only: debug builds (dev testing on the bench) stay silent.
     *  BuildConfig is not generated in this project (AGP 8 default), so the
     *  app's own FLAG_DEBUGGABLE is the dev-mode signal. */
    private fun vibrateConfirm() {
        if (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0) return
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
        // Both roads at once: the LAN datagram lands in milliseconds if they
        // are on the same wifi, the RPC covers them being anywhere else.
        // Whichever arrives first wins; the second is a harmless no-op.
        LanSync.requestDismissForBoth(this, RingSync.sessionIdFor(alarm, firedAt))
        RingSync.actOnPartner(this, alarm, firedAt, pairId, "dismiss") { }
        dismiss()
    }

    /** A partner state message that came in over the LAN, relayed by
     *  AlarmService -- the same strip the 4s poll drives, just instant. */
    private val partnerStateOverLan = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, i: Intent?) {
            showAwareness(i?.getStringExtra(LanSync.EXTRA_STATE))
        }
    }

    private val ringEnded = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, i: Intent?) = finishRinging()
    }

    override fun onDestroy() {
        pollHandler.removeCallbacksAndMessages(null)
        farewellHandler.removeCallbacksAndMessages(null)
        runCatching { unregisterReceiver(ringEnded) }
        runCatching { unregisterReceiver(partnerStateOverLan) }
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
        rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            // Your theme's background, pushed down from Dart (AuthStore
            // setCosmetics). 06:00 should look like the app you went to bed with.
            setBackgroundColor(AuthStore.bgColor(this@RingingActivity, BG_DEEP))
            setPadding(dp(24), dp(40), dp(24), dp(28))
        }

        // ── The dial: two-tone ring with the time inside ──────────────────────
        // Lavender is you, pink is your partner. Even alone, the ring is the app's
        // signature mark and the thing that says "this is Duet, not a stock
        // alarm" to someone squinting at 06:00.
        val dial = FrameLayout(this)
        dial.addView(
            PairRingView(
                this,
                // Whatever skins the two of you picked, pushed down from Dart
                // (AuthStore.setSkinColors). Falls back to the classic pair.
                mineColor = AuthStore.skinMine(this, Color.parseColor("#C9AEE8")),
                themColor = AuthStore.skinPartner(this, Color.parseColor("#F0A8C8")),
            ),
            FrameLayout.LayoutParams(dp(268), dp(268), Gravity.CENTER)
        )

        val inner = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }
        inner.addView(TextView(this).apply {
            text = label.uppercase()
            setTextColor(DIM)
            textSize = 12f
            letterSpacing = 0.22f
            gravity = Gravity.CENTER
        })
        inner.addView(TextView(this).apply {
            text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
            setTextColor(TEXT)
            textSize = 58f
            // The same display face the Flutter dial uses. It ships inside the
            // APK's flutter_assets even when no engine ever runs, but the path
            // is not something this screen may ever crash over -- any failure
            // falls back to the system's light sans and the alarm still reads.
            typeface = runCatching {
                Typeface.createFromAsset(
                    assets,
                    "flutter_assets/assets/fonts/Montserrat-ExtraBold.ttf"
                )
            }.getOrDefault(Typeface.create("sans-serif-light", Typeface.NORMAL))
            letterSpacing = 0.02f
            gravity = Gravity.CENTER
        }, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            topMargin = dp(6)
        })
        inner.addView(TextView(this).apply {
            text = SimpleDateFormat("EEEE, d MMMM", Locale.getDefault()).format(Date())
            setTextColor(MUTED)
            textSize = 13f
            gravity = Gravity.CENTER
        })
        dial.addView(
            inner,
            FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.CENTER)
        )

        rootLayout.addView(View(this), LinearLayout.LayoutParams(MATCH_PARENT, 0).apply { weight = 1f })
        rootLayout.addView(dial, LinearLayout.LayoutParams(dp(268), dp(268)))

        // Milestone 4's live awareness strip, dressed as the canvas's glassy
        // pill instead of bare text. Empty and GONE until polling finds a
        // partner row to report -- see startAwarenessPolling().
        awarenessText = TextView(this).apply {
            setTextColor(AuthStore.skinPartner(this@RingingActivity, Color.parseColor("#F0A8C8")))
            textSize = 13.5f
            gravity = Gravity.CENTER
        }
        awarenessWrap = LinearLayout(this).apply {
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                cornerRadius = dp(19).toFloat()
                setColor(ColorUtils.setAlphaComponent(SURFACE, 200))
                setStroke(dp(1), LINE)
            }
            setPadding(dp(16), dp(8), dp(16), dp(8))
            addView(awarenessText)
            visibility = View.GONE
        }
        rootLayout.addView(awarenessWrap, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            topMargin = dp(18)
        })

        rootLayout.addView(View(this), LinearLayout.LayoutParams(MATCH_PARENT, 0).apply { weight = 1f })

        // ── Controls ─────────────────────────────────────────────────────────
        // These stop YOUR phone only. The "for both of us" variants belong here
        // too (docs/01) -- reached by a LONG PRESS on Dismiss rather than a
        // second button, so it cannot be hit by accident (ADR-006).
        val controls = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }

        if (snoozesLeft > 0) {
            controls.addView(
                actionButton("Snooze", SURFACE, TEXT, outlined = true) { snooze() },
                LinearLayout.LayoutParams(0, dp(72)).apply { weight = 1f; rightMargin = dp(6) }
            )
        }
        controls.addView(
            actionButton(
                "Dismiss",
                AuthStore.skinMine(this, Color.parseColor("#F0A8C8")),
                ON_ACCENT,
                outlined = false
            ) { dismiss() }
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
        rootLayout.addView(controls, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        rootLayout.addView(TextView(this).apply {
            text = listOfNotNull(
                when {
                    maxSnoozes == 0 -> "Snooze is off for this alarm"
                    snoozesLeft == 0 -> "No snoozes left — time to get up"
                    snoozeCount > 0 -> "Snooze $snoozeCount of $maxSnoozes · $snoozeMinutes min"
                    else -> "Snooze lasts $snoozeMinutes min"
                },
                "hold Dismiss to end it for both".takeIf { pairId != null },
            ).joinToString(" · ")
            setTextColor(DIM)
            textSize = 13f
            gravity = Gravity.CENTER
            setPadding(dp(20), dp(14), dp(20), 0)
        })

        return rootLayout
    }

    private fun actionButton(
        label: String, bg: Int, fg: Int, outlined: Boolean, onClick: () -> Unit
    ) = Button(this).apply {
        text = label
        isAllCaps = false
        textSize = 17f
        letterSpacing = 0.02f
        setTextColor(fg)
        background = GradientDrawable().apply {
            cornerRadius = dp(24).toFloat()
            setColor(bg)
            if (outlined) setStroke(dp(1), LINE)
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
        // Snooze and dismiss both stop the ring, but only a DISMISS earns the
        // farewell: the little "you're up" moment needs to feel earned, and a
        // snooze that celebrated would be lying.
        showFarewell()
    }

    /**
     * The farewell: a beat of celebration between "you stopped the alarm" and
     * the screen going away. A check that pops in, a few hearts floating up,
     * and -- when the partner poll knows something for sure -- who woke
     * first. An uncertain state says nothing rather than a wrong name; a solo
     * ring gets the animation alone.
     */
    private fun showFarewell() {
        val partner = AuthStore.partnerName(this)
        val message = when {
            partner == null -> null // solo: the animation speaks for itself
            lastPartnerState == "dismissed" -> "$partner beat you to it"
            lastPartnerState == null -> null // poll found no row yet: no claim
            else -> "You woke up before $partner" // ringing, snoozed, missed
        }

        val mine = AuthStore.skinMine(this, Color.parseColor("#C9AEE8"))
        val them = AuthStore.skinPartner(this, Color.parseColor("#F0A8C8"))

        val overlay = FrameLayout(this).apply {
            setBackgroundColor(AuthStore.bgColor(this@RingingActivity, BG_DEEP))
            isClickable = true // swallow touches; nothing behind it is reachable now
        }

        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }

        // The check, drawn as a filled circle in your color, popping in.
        val check = TextView(this).apply {
            text = "✓"
            textSize = 44f
            setTextColor(ON_ACCENT)
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                colors = intArrayOf(mine, them)
                orientation = GradientDrawable.Orientation.TL_BR
            }
        }
        val checkSize = dp(96)
        column.addView(check, LinearLayout.LayoutParams(checkSize, checkSize).apply { gravity = Gravity.CENTER_HORIZONTAL })

        if (message != null) {
            column.addView(TextView(this).apply {
                text = message
                setTextColor(TEXT)
                textSize = 17f
                letterSpacing = 0.02f
                gravity = Gravity.CENTER
                setPadding(0, dp(22), 0, 0)
            }, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }

        overlay.addView(column, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.CENTER))

        // Hearts: your color and theirs floating up from random points along
        // the bottom -- the two of you, rising. Cheap Views, one animator.
        for (i in 0 until 7) {
            val heart = TextView(this).apply {
                text = "♥"
                textSize = (14 + (i % 3) * 8).toFloat()
                setTextColor(if (i % 2 == 0) mine else them)
                alpha = 0f
                x = resources.displayMetrics.widthPixels * (0.12f + 0.12f * i)
            }
            overlay.addView(heart, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.BOTTOM))
            val rise = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 1200
                startDelay = (80 * i).toLong()
                interpolator = AccelerateDecelerateInterpolator()
                addUpdateListener {
                    val t = it.animatedValue as Float
                    heart.translationY = -t * dp(300)
                    heart.alpha = if (t < 0.15f) t / 0.15f else 1f - (t - 0.15f) / 0.85f
                }
            }
            rise.start()
        }

        rootLayout.addView(overlay, LinearLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))

        // Check pops in with a little overshoot -- small enough to stay
        // gentle, big enough to feel like a bell being struck.
        check.scaleX = 0f
        check.scaleY = 0f
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 420
            interpolator = android.view.animation.OvershootInterpolator(1.6f)
            addUpdateListener {
                val s = it.animatedValue as Float
                check.scaleX = s
                check.scaleY = s
            }
            start()
        }

        // One beat and a half, then gone. No transition -- same rule as ever.
        farewellHandler.postDelayed({ finishRinging() }, 1500)
    }

    /** Back to rest. If the phone was locked when the alarm rang and STILL is
     *  -- you dismissed from bed without ever unlocking -- the least
     *  surprising thing is for the screen to go back to sleep, not to sit on
     *  the lockscreen glowing. Android has no public "re-lock and sleep" for
     *  a non-admin app, but clearing the keep-screen-on flags before
     *  finishing hands the display back to the system's own screen timeout.
     *  A phone that was unlocked before the ring is left exactly as it was.
     */
    private fun returnToRest() {
        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (km.isKeyguardLocked) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        }
    }

    private fun finishRinging() {
        returnToRest()
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
 *
 * Mirrors the Flutter PairRing's canvas behaviour: a slow scale-plus-opacity
 * breathe (the canvas's ringBreathe keyframe) and a soft radial halo of the
 * two skin colours standing behind the dial. All of it is a couple of Paints
 * and one animator -- nothing here can fail in a way that stops the alarm.
 */
private class PairRingView(
    context: Context,
    mineColor: Int,
    themColor: Int,
) : View(context) {
    private val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = LINE
    }
    private val you = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        color = mineColor
    }
    private val them = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        color = themColor
    }

    private val youHalo = Paint(Paint.ANTI_ALIAS_FLAG)
    private val themHalo = Paint(Paint.ANTI_ALIAS_FLAG)

    // Shaders are rebuilt only when the view changes size -- allocating two
    // RadialGradients per frame was pure waste on a screen that redraws at
    // breathe-rate forever.
    private var shaderWidth = 0

    // 0..1, slow, reversing -- the same 82-100% opacity and ~3.5% scale the
    // Flutter ring breathes between.
    private val breathe = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 3200
        repeatMode = ValueAnimator.REVERSE
        repeatCount = ValueAnimator.INFINITE
        interpolator = AccelerateDecelerateInterpolator()
        addUpdateListener { invalidate() }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        breathe.start()
    }

    override fun onDetachedFromWindow() {
        breathe.cancel()
        super.onDetachedFromWindow()
    }

    private fun haloPaint(paint: Paint, color: Int, cx: Float, cy: Float, radius: Float) {
        if (shaderWidth != width) {
            shaderWidth = width
            val r = width / 2f
            val w = width / 2f
            val h = height / 2f
            youHalo.shader = RadialGradient(
                w + r * 0.22f, h - r * 0.18f, r,
                ColorUtils.setAlphaComponent(you.color, 33),
                ColorUtils.setAlphaComponent(you.color, 0),
                Shader.TileMode.CLAMP
            )
            themHalo.shader = RadialGradient(
                w - r * 0.24f, h + r * 0.20f, r,
                ColorUtils.setAlphaComponent(them.color, 33),
                ColorUtils.setAlphaComponent(them.color, 0),
                Shader.TileMode.CLAMP
            )
        }
    }

    override fun onDraw(canvas: Canvas) {
        val t = if (breathe.isRunning) breathe.animatedValue as Float else 0f
        val stroke = width * 0.011f
        track.strokeWidth = stroke
        you.strokeWidth = stroke * 1.6f
        them.strokeWidth = stroke * 1.6f

        val pad = stroke * 2f
        val rect = RectF(pad, pad, width - pad, height - pad)
        val cx = width / 2f
        val cy = height / 2f

        // The halo: your colour up-right, theirs down-left, barely there --
        // light standing behind the dial, the same trick the Flutter side's
        // HaloGlow does.
        val haloRadius = width / 2f
        haloPaint(youHalo, you.color, cx, cy, haloRadius)
        themHalo.alpha = (115 + 65 * t).toInt()
        youHalo.alpha = (140 + 80 * t).toInt()
        canvas.drawCircle(cx + haloRadius * 0.22f, cy - haloRadius * 0.18f, haloRadius, youHalo)
        canvas.drawCircle(cx - haloRadius * 0.24f, cy + haloRadius * 0.20f, haloRadius, themHalo)

        // Breathe: scale the ring about its centre and let the arcs' opacity
        // ride with the same value.
        val alpha = 0.82f + 0.18f * t
        you.alpha = (alpha * 255).toInt()
        them.alpha = (alpha * 255).toInt()
        val scale = 1f + 0.035f * t
        canvas.save()
        canvas.scale(scale, scale, cx, cy)
        canvas.drawArc(rect, 0f, 360f, false, track)
        canvas.drawArc(rect, -90f, 180f, false, you)
        canvas.drawArc(rect, 90f, 180f, false, them)
        canvas.restore()
    }
}
