package com.duet.alarm

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.graphics.ColorUtils

/**
 * The small custom views the ringing screen is built from.
 *
 * They live here rather than in RingingActivity.kt because that file is
 * already the most safety-critical screen in the app and it does not need to
 * also be the longest. Nothing in this file may throw: every one of these is
 * on the path between an alarm going off and someone being able to stop it.
 */

/** A speech-bubble background with a tail pointing down toward one side. */
class BubbleDrawable(
    private val fill: Int,
    private val stroke: Int,
    private val tailOnLeft: Boolean,
    private val radiusPx: Float,
    private val tailPx: Float,
    private val strokePx: Float,
) : Drawable() {

    private val body = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = fill
    }
    private val edge = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = stroke
        strokeWidth = strokePx
    }
    private val path = Path()

    override fun onBoundsChange(bounds: Rect) {
        val b = RectF(
            bounds.left + strokePx, bounds.top + strokePx,
            bounds.right - strokePx, bounds.bottom - tailPx - strokePx
        )
        // The tail sits under the side the speaker is on, so each bubble
        // visibly comes out of that person's half of the ring.
        val tipX = if (tailOnLeft) b.left + b.width() * 0.24f else b.right - b.width() * 0.24f
        path.reset()
        path.addRoundRect(b, radiusPx, radiusPx, Path.Direction.CW)
        path.moveTo(tipX - tailPx * 0.7f, b.bottom - 1f)
        path.lineTo(tipX, b.bottom + tailPx)
        path.lineTo(tipX + tailPx * 0.7f, b.bottom - 1f)
        path.close()
    }

    override fun draw(canvas: Canvas) {
        canvas.drawPath(path, body)
        canvas.drawPath(path, edge)
    }

    override fun setAlpha(alpha: Int) { body.alpha = alpha; edge.alpha = alpha }
    override fun setColorFilter(cf: ColorFilter?) { body.colorFilter = cf; edge.colorFilter = cf }
    @Deprecated("Deprecated in Drawable")
    override fun getOpacity() = PixelFormat.TRANSLUCENT
}

/** A circular initial badge -- one person, in their own colour. */
class AvatarView(
    context: Context,
    private val initial: String,
    private val ringColor: Int,
    private val inkColor: Int,
) : View(context) {

    private val disc = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = ColorUtils.setAlphaComponent(ringColor, 235)
    }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = inkColor
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    private val halo = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = ColorUtils.setAlphaComponent(ringColor, 90)
    }

    override fun onDraw(canvas: Canvas) {
        val r = minOf(width, height) / 2f
        val cx = width / 2f
        val cy = height / 2f
        halo.strokeWidth = r * 0.10f
        canvas.drawCircle(cx, cy, r - halo.strokeWidth / 2f, halo)
        canvas.drawCircle(cx, cy, r * 0.84f, disc)
        text.textSize = r * 0.95f
        // Optical centring: baseline, not bounding box.
        val fm = text.fontMetrics
        canvas.drawText(initial, cx, cy - (fm.ascent + fm.descent) / 2f, text)
    }
}

/**
 * A button that only fires when it is HELD.
 *
 * "Dismiss for both" is a deliberate secondary action (ADR-006): it stops
 * someone else's alarm, and it must be impossible to do with a stray thumb at
 * 06:00. It used to be a long-press on Dismiss, which is undiscoverable -- the
 * only clue was a line of hint text. This is the same safeguard made visible:
 * a real button that fills up while you hold it and does nothing if you let go
 * early.
 */
class HoldButton(
    context: Context,
    private val label: String,
    private val holdMs: Long,
    private val fillColor: Int,
    private val trackColor: Int,
    private val lineColor: Int,
    private val textColor: Int,
    private val onComplete: () -> Unit,
) : View(context) {

    private var progress = 0f
    private var holding = false
    private var startedAt = 0L

    private val track = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = trackColor }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = fillColor }
    private val edge = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = lineColor
    }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = textColor
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    private val clip = Path()

    private val tick = object : Runnable {
        override fun run() {
            if (!holding) return
            progress = ((System.currentTimeMillis() - startedAt).toFloat() / holdMs).coerceIn(0f, 1f)
            invalidate()
            if (progress >= 1f) {
                holding = false
                onComplete()
            } else {
                postOnAnimation(this)
            }
        }
    }

    init {
        isClickable = true
        // Spoken as one action, not as "button, 0 percent".
        contentDescription = label
    }

    @Suppress("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                holding = true
                startedAt = System.currentTimeMillis()
                postOnAnimation(tick)
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                // Let go early and it simply does not happen. No partial state,
                // no "are you sure" -- the hold IS the confirmation.
                holding = false
                progress = 0f
                invalidate()
            }
        }
        return true
    }

    override fun onDraw(canvas: Canvas) {
        val r = height / 2f
        val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
        canvas.drawRoundRect(rect, r, r, track)

        if (progress > 0f) {
            clip.reset()
            clip.addRoundRect(rect, r, r, Path.Direction.CW)
            canvas.save()
            canvas.clipPath(clip)
            canvas.drawRect(0f, 0f, width * progress, height.toFloat(), fill)
            canvas.restore()
        }

        edge.strokeWidth = height * 0.018f
        canvas.drawRoundRect(
            RectF(
                edge.strokeWidth / 2f, edge.strokeWidth / 2f,
                width - edge.strokeWidth / 2f, height - edge.strokeWidth / 2f
            ),
            r, r, edge
        )

        text.textSize = height * 0.26f
        val fm = text.fontMetrics
        canvas.drawText(label, width / 2f, height / 2f - (fm.ascent + fm.descent) / 2f, text)
    }
}

/** Builds a speech bubble view, hidden until someone actually says something. */
fun speechBubble(
    ctx: Context,
    tailOnLeft: Boolean,
    accent: Int,
    surface: Int,
    textColor: Int,
    density: Float,
): TextView {
    fun dp(v: Float) = (v * density)
    return TextView(ctx).apply {
        setTextColor(textColor)
        textSize = 15f
        gravity = Gravity.CENTER
        background = BubbleDrawable(
            fill = ColorUtils.setAlphaComponent(surface, 245),
            stroke = ColorUtils.setAlphaComponent(accent, 150),
            tailOnLeft = tailOnLeft,
            radiusPx = dp(18f),
            tailPx = dp(9f),
            strokePx = dp(1.4f),
        )
        setPadding(dp(16f).toInt(), dp(10f).toInt(), dp(16f).toInt(), dp(19f).toInt())
        visibility = View.INVISIBLE
    }
}

/** Pops a bubble in from nothing, with a small overshoot. */
fun TextView.speak(message: String, fromLeft: Boolean) {
    text = message
    visibility = View.VISIBLE
    alpha = 0f
    scaleX = 0.7f
    scaleY = 0.7f
    // Grows out of the ring half it belongs to, not out of its own middle.
    pivotX = if (fromLeft) 0f else width.toFloat()
    pivotY = height.toFloat()
    animate()
        .alpha(1f).scaleX(1f).scaleY(1f)
        .setDuration(420)
        .setInterpolator(android.view.animation.OvershootInterpolator(2.2f))
        .start()
}

/** Floating hearts, in the two of your colours. Shared by both celebrations. */
fun floatHearts(host: FrameLayout, mine: Int, them: Int, density: Float, count: Int = 7) {
    val screenWidth = host.resources.displayMetrics.widthPixels
    for (i in 0 until count) {
        val heart = TextView(host.context).apply {
            text = "♥"
            textSize = (14 + (i % 3) * 8).toFloat()
            setTextColor(if (i % 2 == 0) mine else them)
            alpha = 0f
            x = screenWidth * (0.10f + 0.80f * (i.toFloat() / (count - 1).coerceAtLeast(1)))
        }
        host.addView(
            heart,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM
            )
        )
        android.animation.ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 1200
            startDelay = (80 * i).toLong()
            interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            addUpdateListener {
                val t = it.animatedValue as Float
                heart.translationY = -t * 300f * density
                heart.alpha = if (t < 0.15f) t / 0.15f else 1f - (t - 0.15f) / 0.85f
            }
            start()
        }
    }
}
