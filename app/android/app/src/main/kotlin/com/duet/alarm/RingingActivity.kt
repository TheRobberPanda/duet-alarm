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
import android.view.WindowInsets
import android.view.WindowInsetsController
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

private val DEFAULT_MINE = Color.parseColor("#C9AEE8")
private val DEFAULT_THEM = Color.parseColor("#F0A8C8")

/**
 * Deliberately NOT a Flutter screen.
 *
 * Cold-starting the Flutter engine from a locked screen at 06:00 adds latency and
 * a class of failure that cannot be debugged from bed -- on the one screen that
 * absolutely must work. This is plain Android views with no dependencies, so it
 * keeps working even if the Flutter side is broken entirely, and it can run
 * before first unlock (directBootAware) after an overnight reboot.
 * See docs/12-roadblocks.md section 3.2.
 *
 * ## The two phases
 *
 * RINGING is the alarm: sound, vibration, Snooze, Dismiss, and the held
 * "for both of us".
 *
 * WATCHING is what happens after YOU dismiss and your partner has not. The
 * screen stays, in silence -- the same view they are looking at, minus the
 * noise -- with a "Good morning" coming out of your half of the ring. When
 * they finally stop theirs, their half lights up, their own bubble appears,
 * and only then does this go away. That waiting is the product: an alarm clock
 * for two people is about the moment you both got up, and ending the screen
 * the instant you personally hit Dismiss throws that away.
 *
 * Then it opens the app, not the lock screen, so the morning ends on the wake
 * receipt rather than on a wallpaper.
 */
class RingingActivity : Activity() {

    private enum class Phase { RINGING, WATCHING }

    private var alarmId: String? = null
    private var snoozeMinutes = 9
    private var maxSnoozes = 3
    private var snoozeCount = 0
    private var soundRef = "default"
    private var label = "Alarm"
    private var pairId: String? = null

    private var phase = Phase.RINGING

    private var awarenessWrap: View? = null
    private lateinit var awarenessText: TextView

    // Last state the poll or LAN relay reported for your partner -- the
    // farewell message is derived from it, so an uncertain state says nothing
    // rather than a wrong name.
    private var lastPartnerState: String? = null

    private lateinit var rootLayout: LinearLayout
    private lateinit var screen: FrameLayout
    private lateinit var ring: PairRingView
    private lateinit var myBubble: TextView
    private lateinit var partnerBubble: TextView
    private lateinit var controls: LinearLayout
    private lateinit var hint: TextView
    private var holdBoth: HoldButton? = null
    private var partnerAvatar: View? = null

    private val farewellHandler = Handler(Looper.getMainLooper())
    private val pollHandler = Handler(Looper.getMainLooper())

    private val snoozesLeft get() = (maxSnoozes - snoozeCount).coerceAtLeast(0)

    private val mineColor by lazy { AuthStore.skinMine(this, DEFAULT_MINE) }
    private val themColor by lazy { AuthStore.skinPartner(this, DEFAULT_THEM) }
    private val partnerName by lazy { AuthStore.partnerName(this) }

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

        // AFTER setContentView, never before: window.insetsController reads
        // through the decor view, which does not exist until there is content,
        // and calling it in onCreate threw an NPE that took the whole alarm
        // screen down with it. Wrapped as well as ordered -- nothing cosmetic
        // on this screen is worth a crash, and a visible status bar is a much
        // smaller problem than an alarm that does not appear.
        runCatching { goFullscreen() }

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
     * Edge to edge, with the system bars hidden.
     *
     * On a tall phone the alarm screen used to be letterboxed between a status
     * bar and a gesture bar, which is both ugly and wrong: this is the one
     * screen that should own the whole display. It also stops the clock in the
     * status bar from sitting a few pixels above a much larger clock, which
     * looked like a bug and occasionally disagreed by a minute.
     *
     * Swiping still reveals the bars transiently, so nothing is trapped.
     */
    private fun goFullscreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            window.decorView.windowInsetsController?.apply {
                hide(WindowInsets.Type.systemBars())
                systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    View.SYSTEM_UI_FLAG_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        }
    }

    /**
     * Milestone 4's live awareness strip -- "Sam snoozed", "Sam is ringing too" --
     * polled rather than pushed: this screen has no Flutter engine and no
     * realtime channel, just RingSync's plain REST calls. A few seconds of
     * staleness on a strip that is itself a nice-to-have is a fine trade for not
     * building a socket connection into the one screen that must never hang.
     *
     * It also polls MY OWN row, which is what makes the partner's "dismiss for
     * both" actually reach this phone when the two are not on the same wifi --
     * see [RingSync.fetchMyState] for how that went unnoticed.
     */
    private fun startAwarenessPolling() {
        val id = alarmId ?: return
        if (pairId == null) return
        val (base, firedAt) = splitFireId(id.removePrefix(AlarmDef.SNOOZE_PREFIX)) ?: return

        val poll = object : Runnable {
            override fun run() {
                RingSync.fetchPartnerState(this@RingingActivity, base, firedAt, pairId) { state ->
                    runOnUiThread { onPartnerState(state) }
                }
                if (phase == Phase.RINGING) {
                    RingSync.fetchMyState(this@RingingActivity, base, firedAt, pairId) { mine ->
                        if (mine == "dismissed") {
                            runOnUiThread { dismissedByPartner() }
                        }
                    }
                }
                pollHandler.postDelayed(this, 4000)
            }
        }
        pollHandler.post(poll)
    }

    /** They pressed "for both of us" on their phone. Same effect as dismissing
     *  here, so the two devices end in the same state, but the screen says who
     *  did it rather than pretending you woke up on your own. */
    private fun dismissedByPartner() {
        if (phase != Phase.RINGING) return
        alarmId?.let { AlarmActions.dismiss(this, it, pairId) }
        enterWatching(greeting = partnerName?.let { "$it got us both up" } ?: "Alarm stopped")
    }

    private fun onPartnerState(state: String?) {
        lastPartnerState = state ?: lastPartnerState
        showAwareness(state)

        // The moment they stop theirs: their half of the ring lights up, they
        // get a bubble of their own, and the morning is over for both of you.
        if (state == "dismissed" && phase == Phase.WATCHING &&
            partnerBubble.visibility != View.VISIBLE
        ) {
            celebratePartnerDismiss()
        }
    }

    private fun showAwareness(state: String?) {
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

    private val partnerStateOverLan = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, i: Intent?) {
            onPartnerState(i?.getStringExtra(LanSync.EXTRA_STATE))
        }
    }

    private val ringEnded = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, i: Intent?) {
            // Only in RINGING. Once we are watching, the ring has already
            // ended -- this broadcast is our own dismiss coming back to us,
            // and obeying it would close the screen we deliberately kept.
            if (phase == Phase.RINGING) finishRinging()
        }
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
    private fun dpf(v: Float) = v * resources.displayMetrics.density

    /**
     * The dial, sized to the phone rather than nailed to 268dp.
     *
     * A fixed size is a bug on both ends: on a small phone the ring crowded
     * the buttons, and on a large one it sat marooned in the middle of a lot
     * of empty space looking like a screenshot from a smaller device. Bounded
     * by height as well as width so a short, wide screen does not push the
     * controls off the bottom.
     */
    private fun dialSize(): Int {
        val dm = resources.displayMetrics
        val byWidth = dm.widthPixels * 0.70f
        val byHeight = dm.heightPixels * 0.34f
        return minOf(byWidth, byHeight).toInt().coerceIn(dp(190), dp(360))
    }

    private fun buildUi(): View {
        val bg = AuthStore.bgColor(this, BG_DEEP)

        rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            // Your theme's background, pushed down from Dart (AuthStore
            // setCosmetics). 06:00 should look like the app you went to bed with.
            setBackgroundColor(bg)
            setPadding(dp(24), dp(40), dp(24), dp(28))
        }

        val dialPx = dialSize()

        // ── The dial: two-tone ring with the time inside ──────────────────────
        // Left half is your partner, right half is you -- the same halves the
        // Flutter PairRing draws, so the two screens agree about which side of
        // the ring each of you is.
        val dial = FrameLayout(this)
        ring = PairRingView(this, mineColor = mineColor, themColor = themColor)
        dial.addView(ring, FrameLayout.LayoutParams(dialPx, dialPx, Gravity.CENTER))

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
            // Scaled with the dial for the same reason the dial is scaled.
            textSize = dialPx / resources.displayMetrics.density * 0.216f
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
        }, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { topMargin = dp(6) })
        inner.addView(TextView(this).apply {
            text = SimpleDateFormat("EEEE, d MMM", Locale.getDefault()).format(Date())
            setTextColor(MUTED)
            textSize = 13f
            gravity = Gravity.CENTER
            // One line, always. Inside a dial there is no room to wrap, and a
            // date that silently loses its second half is worse than a short
            // month name.
            isSingleLine = true
        })
        dial.addView(inner, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.CENTER))

        // ── The two faces, one per half ──────────────────────────────────────
        // Partner on the LEFT, over their arc; you on the right, over yours.
        // Without these the ring is two anonymous colours and you have to
        // remember which one you are.
        val avatarPx = (dialPx * 0.20f).toInt()
        val avatarInset = (dialPx * 0.04f).toInt()

        partnerName?.let { name ->
            partnerAvatar = AvatarView(this, name.take(1).uppercase(), themColor, ON_ACCENT).also {
                dial.addView(
                    it,
                    FrameLayout.LayoutParams(avatarPx, avatarPx, Gravity.START or Gravity.CENTER_VERTICAL)
                        .apply { marginStart = avatarInset }
                )
            }
        }
        val myInitial = AuthStore.myName(this)?.take(1)?.uppercase()
        if (partnerName != null) {
            dial.addView(
                AvatarView(this, myInitial ?: "♥", mineColor, ON_ACCENT),
                FrameLayout.LayoutParams(avatarPx, avatarPx, Gravity.END or Gravity.CENTER_VERTICAL)
                    .apply { marginEnd = avatarInset }
            )
        }

        // ── The bubbles ──────────────────────────────────────────────────────
        // One per half, each with its tail under its own side, so a greeting
        // visibly comes out of that person's arc. Invisible until spoken.
        val density = resources.displayMetrics.density
        partnerBubble = speechBubble(this, tailOnLeft = true, accent = themColor,
            surface = SURFACE, textColor = TEXT, density = density)
        myBubble = speechBubble(this, tailOnLeft = false, accent = mineColor,
            surface = SURFACE, textColor = TEXT, density = density)

        val bubbleRow = FrameLayout(this)
        bubbleRow.addView(
            partnerBubble,
            FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.START or Gravity.BOTTOM)
        )
        bubbleRow.addView(
            myBubble,
            FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.END or Gravity.BOTTOM)
        )

        rootLayout.addView(View(this), LinearLayout.LayoutParams(MATCH_PARENT, 0).apply { weight = 1f })
        rootLayout.addView(
            bubbleRow,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { bottomMargin = dp(6) }
        )
        rootLayout.addView(dial, LinearLayout.LayoutParams(MATCH_PARENT, dialPx))

        // Milestone 4's live awareness strip, dressed as the canvas's glassy
        // pill instead of bare text. Empty and GONE until polling finds a
        // partner row to report -- see startAwarenessPolling().
        awarenessText = TextView(this).apply {
            setTextColor(themColor)
            textSize = 13.5f
            gravity = Gravity.CENTER
        }
        awarenessWrap = LinearLayout(this).apply {
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                cornerRadius = dpf(19f)
                setColor(ColorUtils.setAlphaComponent(SURFACE, 200))
                setStroke(dp(1), LINE)
            }
            setPadding(dp(16), dp(8), dp(16), dp(8))
            addView(awarenessText)
            visibility = View.GONE
        }
        rootLayout.addView(
            awarenessWrap,
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { topMargin = dp(18) }
        )

        rootLayout.addView(View(this), LinearLayout.LayoutParams(MATCH_PARENT, 0).apply { weight = 1f })

        // ── Controls ─────────────────────────────────────────────────────────
        controls = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        buildRingingControls()
        rootLayout.addView(controls, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        hint = TextView(this).apply {
            text = hintText()
            setTextColor(DIM)
            textSize = 13f
            gravity = Gravity.CENTER
            setPadding(dp(20), dp(14), dp(20), 0)
        }
        rootLayout.addView(hint)

        // The whole thing lives inside a FrameLayout so celebrations can be
        // laid over it without disturbing the layout underneath.
        screen = FrameLayout(this).apply {
            setBackgroundColor(bg)
            addView(rootLayout, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }
        return screen
    }

    private fun hintText(): String = when {
        maxSnoozes == 0 -> "Snooze is off for this alarm"
        snoozesLeft == 0 -> "No snoozes left — time to get up"
        snoozeCount > 0 -> "Snooze $snoozeCount of $maxSnoozes · $snoozeMinutes min"
        else -> "Snooze lasts $snoozeMinutes min"
    }

    private fun buildRingingControls() {
        controls.removeAllViews()

        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        if (snoozesLeft > 0) {
            row.addView(
                actionButton("Snooze", SURFACE, TEXT, outlined = true) { snooze() },
                LinearLayout.LayoutParams(0, dp(72)).apply { weight = 1f; rightMargin = dp(6) }
            )
        }
        row.addView(
            actionButton("Dismiss", mineColor, ON_ACCENT, outlined = false) { dismiss() },
            LinearLayout.LayoutParams(0, dp(72)).apply {
                weight = 1f
                if (snoozesLeft > 0) leftMargin = dp(6)
            }
        )
        controls.addView(row, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        // "For both of us" as its own visible button, held rather than tapped.
        // It used to be an invisible long-press on Dismiss, which nobody could
        // find; the hold is still what keeps it from being hit by accident.
        if (pairId != null) {
            holdBoth = HoldButton(
                context = this,
                label = "Hold to dismiss for both",
                holdMs = 1100L,
                fillColor = ColorUtils.setAlphaComponent(themColor, 190),
                trackColor = ColorUtils.setAlphaComponent(SURFACE, 220),
                lineColor = ColorUtils.setAlphaComponent(themColor, 130),
                textColor = TEXT,
            ) { dismissForBoth() }
            controls.addView(
                holdBoth,
                LinearLayout.LayoutParams(MATCH_PARENT, dp(60)).apply { topMargin = dp(10) }
            )
        }
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
            cornerRadius = dpf(24f)
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
        // A snooze is not a morning. No farewell, no bubble, no receipt.
        finishRinging()
    }

    private fun dismiss() {
        alarmId?.let { AlarmActions.dismiss(this, it, pairId) }
        enterWatching(greeting = "Good morning")
    }

    private fun dismissForBoth() {
        val id = alarmId ?: return
        vibrateConfirm()
        AlarmActions.dismissForBoth(this, id, pairId)
        enterWatching(greeting = "Good morning")
    }

    /**
     * You are up; the alarm is silent; the screen stays.
     *
     * Everything noisy has already stopped -- AlarmActions.dismiss killed the
     * service, which owns the audio and the vibration -- so this is only about
     * what is left on screen. It becomes, deliberately, the view your partner
     * still has: the same ring, without the racket. Then it waits for them.
     *
     * Solo rings do not wait for anybody, so they go straight on.
     */
    private fun enterWatching(greeting: String) {
        if (phase == Phase.WATCHING) return
        phase = Phase.WATCHING

        // Your half completes, and says good morning out of your own side.
        ring.markMineDone()
        myBubble.post { myBubble.speak(greeting, fromLeft = false) }
        floatHearts(screen, mineColor, themColor, resources.displayMetrics.density)

        // Let the display time out normally now. Holding the screen awake was
        // for the alarm; the aftermath does not need to burn the battery if
        // the phone goes back on the nightstand.
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val partner = partnerName
        if (partner == null || pairId == null) {
            // Nobody to wait for.
            controls.removeAllViews()
            hint.text = ""
            farewellHandler.postDelayed({ openWakeReceipt() }, 1600)
            return
        }

        // Already up before you got here: no waiting, just both bubbles.
        if (lastPartnerState == "dismissed") {
            showWaitingControls("$partner beat you to it")
            farewellHandler.postDelayed({ celebratePartnerDismiss() }, 500)
            return
        }

        showWaitingControls("Waiting for $partner")
    }

    private fun showWaitingControls(message: String) {
        controls.removeAllViews()
        controls.addView(
            actionButton("Done", SURFACE, TEXT, outlined = true) { openWakeReceipt() },
            LinearLayout.LayoutParams(MATCH_PARENT, dp(60))
        )
        hint.text = message
    }

    /**
     * They stopped theirs. Their half of the ring completes, their bubble
     * answers yours, and after a beat the morning moves to the wake receipt.
     */
    private fun celebratePartnerDismiss() {
        if (partnerBubble.visibility == View.VISIBLE) return
        ring.markThemDone()
        val name = partnerName
        partnerBubble.post {
            partnerBubble.speak("Good morning", fromLeft = true)
        }
        floatHearts(screen, mineColor, themColor, resources.displayMetrics.density, count = 9)
        hint.text = name?.let { "$it is up too" } ?: "You're both up"
        farewellHandler.removeCallbacksAndMessages(null)
        farewellHandler.postDelayed({ openWakeReceipt() }, 2600)
    }

    /**
     * The morning ends in the app, not on the lock screen.
     *
     * The home screen fetches the latest ring session on load and shows the
     * wake receipt for one it has not shown before, so simply opening
     * MainActivity is what puts the receipt in front of you -- there is no
     * extra flag to pass, and a session with nothing to report just lands on
     * the home screen instead of a wallpaper. FLAG_ACTIVITY_NEW_TASK because
     * this activity lives in its own task affinity (see the manifest).
     */
    private fun openWakeReceipt() {
        farewellHandler.removeCallbacksAndMessages(null)
        runCatching {
            startActivity(
                Intent(this, MainActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                )
            )
        }
        finish()
        overridePendingTransition(0, 0)
    }

    /** Back to rest without opening anything -- the snooze path, and the path
     *  taken when the ring was ended somewhere else entirely. If the phone was
     *  locked when the alarm rang and STILL is, the least surprising thing is
     *  for the screen to go back to sleep rather than sit on the lock screen
     *  glowing. Android has no public "re-lock and sleep" for a non-admin app,
     *  but clearing the keep-screen-on flag before finishing hands the display
     *  back to the system's own timeout. */
    private fun returnToRest() {
        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (km.isKeyguardLocked) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(false)
                setTurnScreenOn(false)
            }
        }
    }

    private fun finishRinging() {
        returnToRest()
        finish()
        // No transition -- at 06:00 an animation just looks like a stutter.
        overridePendingTransition(0, 0)
    }

    /** Back must not silently kill the alarm. Once you are up and only
     *  watching, though, it is just a screen -- let it close. */
    @Deprecated("Deprecated in Activity")
    override fun onBackPressed() {
        if (phase == Phase.WATCHING) openWakeReceipt()
    }
}

/**
 * The two-tone ring, drawn rather than bundled so it scales to any density and
 * needs no asset. Left half is your partner, right half is you.
 *
 * Mirrors the Flutter PairRing's canvas behaviour: a slow scale-plus-opacity
 * breathe (the canvas's ringBreathe keyframe) and a soft radial halo of the
 * two skin colours standing behind the dial. All of it is a couple of Paints
 * and one animator -- nothing here can fail in a way that stops the alarm.
 *
 * Either half can be marked "done", which brightens it, thickens it and gives
 * it one bloom outward: the visual half of "that person is up".
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
    private val bloom = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }

    private val youHalo = Paint(Paint.ANTI_ALIAS_FLAG)
    private val themHalo = Paint(Paint.ANTI_ALIAS_FLAG)

    private var mineDone = false
    private var themDone = false

    /** 0 when idle, 0..1 while a half is blooming. */
    private var mineBloom = 0f
    private var themBloom = 0f

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

    fun markMineDone() {
        if (mineDone) return
        mineDone = true
        bloomAnimator { mineBloom = it }
    }

    fun markThemDone() {
        if (themDone) return
        themDone = true
        bloomAnimator { themBloom = it }
    }

    private fun bloomAnimator(set: (Float) -> Unit) {
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 900
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { set(it.animatedValue as Float); invalidate() }
            start()
        }
    }

    private fun haloPaint(paint: Paint) {
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
        // A finished half sits a little heavier than a still-ringing one.
        you.strokeWidth = stroke * if (mineDone) 2.2f else 1.6f
        them.strokeWidth = stroke * if (themDone) 2.2f else 1.6f

        val pad = stroke * 3f
        val rect = RectF(pad, pad, width - pad, height - pad)
        val cx = width / 2f
        val cy = height / 2f

        // The halo: your colour up-right, theirs down-left, barely there --
        // light standing behind the dial, the same trick the Flutter side's
        // HaloGlow does.
        val haloRadius = width / 2f
        haloPaint(youHalo)
        themHalo.alpha = (115 + 65 * t).toInt()
        youHalo.alpha = (140 + 80 * t).toInt()
        canvas.drawCircle(cx + haloRadius * 0.22f, cy - haloRadius * 0.18f, haloRadius, youHalo)
        canvas.drawCircle(cx - haloRadius * 0.24f, cy + haloRadius * 0.20f, haloRadius, themHalo)

        // Breathe: scale the ring about its centre and let the arcs' opacity
        // ride with the same value. A finished half stops breathing and simply
        // stays lit -- it is done, and done things do not pulse.
        val alpha = 0.82f + 0.18f * t
        you.alpha = (if (mineDone) 1f else alpha).times(255).toInt()
        them.alpha = (if (themDone) 1f else alpha).times(255).toInt()
        val scale = 1f + 0.035f * t
        canvas.save()
        canvas.scale(scale, scale, cx, cy)
        canvas.drawArc(rect, 0f, 360f, false, track)
        canvas.drawArc(rect, -90f, 180f, false, you)
        canvas.drawArc(rect, 90f, 180f, false, them)
        canvas.restore()

        // The bloom: one expanding, fading echo of the half that just finished.
        drawBloom(canvas, rect, cx, cy, mineBloom, you.color, -90f)
        drawBloom(canvas, rect, cx, cy, themBloom, them.color, 90f)
    }

    private fun drawBloom(
        canvas: Canvas, rect: RectF, cx: Float, cy: Float,
        progress: Float, color: Int, startAngle: Float
    ) {
        if (progress <= 0f || progress >= 1f) return
        bloom.color = color
        bloom.alpha = ((1f - progress) * 190).toInt()
        bloom.strokeWidth = width * 0.011f * (1.6f + 2.4f * progress)
        canvas.save()
        canvas.scale(1f + 0.16f * progress, 1f + 0.16f * progress, cx, cy)
        canvas.drawArc(rect, startAngle, 180f, false, bloom)
        canvas.restore()
    }
}
