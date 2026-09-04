import 'package:flutter/material.dart';

/// The palette, re-themed to match the app icon (docs/08): a warm, near-black
/// plum rather than pure black -- the app is looked at by a half-asleep person
/// in a dark room, and #000 with white text is harsh at 06:00.
///
/// [amber] and [teal] keep their names (41 call sites lean on them) but are now
/// the icon's pink and lavender -- the two partner accents. Every shared
/// element shows both, so a glance tells you which half is yours. That is the
/// app's signature, not decoration (ADR-013).
class DuetColors {
  static const bg = Color(0xFF1A1218);
  static const bgDeep = Color(0xFF150F14);
  static const surface = Color(0xFF251A22);
  static const surfaceRaised = Color(0xFF33232D);
  static const line = Color(0xFF402C38);

  static const text = Color(0xFFF9EBF3);
  static const muted = Color(0xFFCBA8BE);
  static const dim = Color(0xFF937284);
  static const faint = Color(0xFF5F4555);

  static const amber = Color(0xFFF0A8C8);
  static const amberInk = Color(0xFF3D1526);
  static const teal = Color(0xFFC9AEE8);
  static const danger = Color(0xFFE87DA0);
}

ThemeData duetTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: DuetColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: DuetColors.amber,
        secondary: DuetColors.teal,
        surface: DuetColors.surface,
        error: DuetColors.danger,
      ),
      // 'sans-serif' resolves to the DEVICE's system font (MiSans on HyperOS,
      // Roboto on Pixel, One UI Sans on Samsung) rather than one we ship. It
      // looks native everywhere and costs nothing, at the price of the app
      // having no typographic identity of its own. Revisit if the brand font
      // from the design canvas (Hanken Grotesk) gets bundled.
      fontFamily: 'sans-serif',
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: DuetColors.surfaceRaised,
        contentTextStyle: TextStyle(color: DuetColors.text),
        behavior: SnackBarBehavior.floating,
      ),
    );

/// Section heading used throughout: small, tracked, quiet.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          letterSpacing: 1.3,
          color: DuetColors.dim,
          fontWeight: FontWeight.w600,
        ),
      );
}

class DuetCard extends StatelessWidget {
  const DuetCard({super.key, required this.child, this.border, this.color});

  final Widget child;
  final Color? border;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color ?? DuetColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: border != null ? Border.all(color: border!) : null,
        ),
        child: child,
      );
}

class DuetButton extends StatefulWidget {
  const DuetButton(this.label, {super.key, this.onTap, this.filled = false, this.busy = false});

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool busy;

  @override
  State<DuetButton> createState() => _DuetButtonState();
}

class _DuetButtonState extends State<DuetButton> {
  // A press-scale, not a ripple replacement: the platform button underneath
  // still owns the real gesture and its own feedback. This is purely tactile
  // -- a Listener rather than a GestureDetector so it never competes for the
  // tap in the gesture arena.
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final child = widget.busy
        ? const SizedBox(
            height: 20, width: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: DuetColors.amberInk))
        : Text(widget.label,
            style: TextStyle(
                fontSize: widget.filled ? 16.5 : 15.5,
                fontWeight: widget.filled ? FontWeight.w600 : FontWeight.w500));

    final button = SizedBox(
      height: 52,
      child: widget.filled
          ? FilledButton(
              onPressed: widget.busy ? null : widget.onTap,
              style: FilledButton.styleFrom(
                backgroundColor: DuetColors.amber,
                foregroundColor: DuetColors.amberInk,
                disabledBackgroundColor: DuetColors.amber,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: child)
          : OutlinedButton(
              onPressed: widget.busy ? null : widget.onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: DuetColors.text,
                side: const BorderSide(color: DuetColors.line),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: child),
    );

    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: button,
      ),
    );
  }
}

/// Fades and lifts a widget into place once, on first mount -- used for list
/// entrances so a screen builds itself in rather than snapping into existence.
/// Give it a stable [key] (the alarm's id) when the surrounding list can
/// reorder, or a reorder will read as a re-entrance.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, 0.08),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _shown ? 1 : 0,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

/// A softer push than the platform default: fade plus a gentle lift, matching
/// the rest of the app's motion rather than Android's flat slide-in.
class DuetPageRoute<T> extends PageRouteBuilder<T> {
  DuetPageRoute({required WidgetBuilder builder})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => builder(context),
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 240),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
                    .animate(curved),
                child: child,
              ),
            );
          },
        );
}

/// The two-tone ring: the app's signature mark. Pink is you, lavender is the
/// partner. A half ring (partner absent) reads as "waiting for someone". A
/// slow breathing pulse keeps it feeling alive without being distracting at
/// 06:00 -- set [animate] false anywhere that needs a perfectly static mark
/// (e.g. inside something else already animating).
class PairRing extends StatefulWidget {
  const PairRing({
    super.key,
    this.size = 56,
    this.hasPartner = true,
    this.strokeWidth = 2.5,
    this.animate = true,
  });

  final double size;
  final bool hasPartner;
  final double strokeWidth;
  final bool animate;

  @override
  State<PairRing> createState() => _PairRingState();
}

class _PairRingState extends State<PairRing> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ring = SizedBox(
      // CustomPaint only honours `size` when it is otherwise unconstrained —
      // inside a stretching Column it would expand to the full width and the
      // ring would swallow the screen. The SizedBox pins it either way.
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _PairRingPainter(hasPartner: widget.hasPartner, strokeWidth: widget.strokeWidth),
      ),
    );
    if (!widget.animate) return ring;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) =>
          Transform.scale(scale: 1 + _controller.value * 0.035, child: child),
      child: ring,
    );
  }
}

class _PairRingPainter extends CustomPainter {
  _PairRingPainter({required this.hasPartner, required this.strokeWidth});

  final bool hasPartner;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.width - strokeWidth) / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: c, radius: r);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = DuetColors.line;
    canvas.drawCircle(c, r, track);

    Paint arc(Color colour) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = colour;

    // Right half = you, left half = them.
    canvas.drawArc(rect, -1.5708, 3.1416, false, arc(DuetColors.teal));
    if (hasPartner) {
      canvas.drawArc(rect, 1.5708, 3.1416, false, arc(DuetColors.amber));
    }
  }

  @override
  bool shouldRepaint(_PairRingPainter old) =>
      old.hasPartner != hasPartner || old.strokeWidth != strokeWidth;
}
