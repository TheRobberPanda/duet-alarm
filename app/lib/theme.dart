import 'package:flutter/material.dart';

/// The palette from the design canvas (design/*.dc.html).
///
/// Warm near-black rather than pure black: the app is looked at by a half-asleep
/// person in a dark room, and #000 with white text is harsh at 06:00.
///
/// [amber] and [teal] are the two partner accents. Every shared element shows
/// both, so a glance tells you which half is yours — that is the app's signature,
/// not decoration (ADR-013).
class DuetColors {
  static const bg = Color(0xFF171310);
  static const bgDeep = Color(0xFF141110);
  static const surface = Color(0xFF1E1815);
  static const surfaceRaised = Color(0xFF2A211B);
  static const line = Color(0xFF352C27);

  static const text = Color(0xFFF5EDE6);
  static const muted = Color(0xFFB2A398);
  static const dim = Color(0xFF7C6E66);
  static const faint = Color(0xFF544942);

  static const amber = Color(0xFFE9A35B);
  static const amberInk = Color(0xFF1B120A);
  static const teal = Color(0xFF5FB3AE);
  static const danger = Color(0xFFC98274);
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

class DuetButton extends StatelessWidget {
  const DuetButton(this.label, {super.key, this.onTap, this.filled = false, this.busy = false});

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            height: 20, width: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: DuetColors.amberInk))
        : Text(label,
            style: TextStyle(
                fontSize: filled ? 16.5 : 15.5,
                fontWeight: filled ? FontWeight.w600 : FontWeight.w500));

    return SizedBox(
      height: 52,
      child: filled
          ? FilledButton(
              onPressed: busy ? null : onTap,
              style: FilledButton.styleFrom(
                backgroundColor: DuetColors.amber,
                foregroundColor: DuetColors.amberInk,
                disabledBackgroundColor: DuetColors.amber,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: child)
          : OutlinedButton(
              onPressed: busy ? null : onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: DuetColors.text,
                side: const BorderSide(color: DuetColors.line),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: child),
    );
  }
}

/// The two-tone ring: the app's signature mark. Amber is the partner, teal is
/// you. A half ring (partner absent) reads as "waiting for someone".
class PairRing extends StatelessWidget {
  const PairRing({super.key, this.size = 56, this.hasPartner = true, this.strokeWidth = 2.5});

  final double size;
  final bool hasPartner;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => SizedBox(
        // CustomPaint only honours `size` when it is otherwise unconstrained —
        // inside a stretching Column it would expand to the full width and the
        // ring would swallow the screen. The SizedBox pins it either way.
        width: size,
        height: size,
        child: CustomPaint(
          size: Size(size, size),
          painter: _PairRingPainter(hasPartner: hasPartner, strokeWidth: strokeWidth),
        ),
      );
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
