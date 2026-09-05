import 'dart:math' as math;

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

  /// The two accents as one diagonal wash -- gradient buttons, the sparkle
  /// backdrop, anything that wants to say "girly" in one brushstroke rather
  /// than a flat fill.
  // NOTE: the app's accent gradient is NOT here. It lives on SkinColors as a
  // live getter, because it depends on which skin each of you picked -- see
  // SkinColors.wash. These constants are only the fallbacks it defaults to.
}

/// Paints behind every screen (see main.dart's [MaterialApp.builder]): a soft
/// diagonal wash from the plum background up towards the two accents, plus a
/// handful of blurred bokeh circles standing in for sparkle. Static, not
/// animated -- this sits behind everything else including the ringing screen's
/// eventual Flutter surfaces, and motion back there would upstage the actual
/// alarm.
class GirlyBackdrop extends StatelessWidget {
  const GirlyBackdrop({super.key, required this.child});

  final Widget child;

  // Corners only, small and faint -- a hint of color peeking in rather than a
  // wash sitting over the content. The first pass used huge blurred spreads
  // that muddied every card; this is deliberately closer to "barely there".
  // Positions and sizes are fixed; the colors come from whichever skins are
  // active, so the glow in the corners is literally the two of you.
  static const _bokeh = [
    (Alignment(-1.15, -1.1), 130.0, false),
    (Alignment(1.2, -1.15), 150.0, true),
    (Alignment(1.15, 1.2), 140.0, false),
  ];

  // A few tiny fixed sparkle points -- actual twinkle rather than another
  // blurred circle. Diamond, not a dot, so it reads as a spark at this size.
  static const _sparkles = [
    (Alignment(-0.72, -0.55), 7.0),
    (Alignment(0.8, -0.2), 5.0),
    (Alignment(-0.5, 0.62), 6.0),
    (Alignment(0.65, 0.78), 5.0),
    (Alignment(0.15, -0.78), 4.0),
  ];

  @override
  Widget build(BuildContext context) => SkinBuilder(
        builder: (context, skins) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [DuetColors.bgDeep, DuetColors.bg],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (final (align, size, isPartner) in _bokeh)
              Align(
                alignment: align,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        (isPartner ? skins.partner : skins.mine).withValues(alpha: 0.16),
                        (isPartner ? skins.partner : skins.mine).withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            for (final (align, size) in _sparkles)
              Align(
                alignment: align,
                child: Transform.rotate(
                  angle: 0.785398, // 45deg -- a square read as a diamond
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: DuetColors.text.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            child,
          ],
        ),
        ),
      );
}

/// Rebuilds its subtree whenever either side's skin changes. The way anything
/// that paints in the live accent stays in step, without every widget growing
/// its own listener -- see [SkinColors].
class SkinBuilder extends StatelessWidget {
  const SkinBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, SkinColors skins) builder;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: SkinColors.instance,
        builder: (context, _) => builder(context, SkinColors.instance),
      );
}

/// A small, quiet decoration -- never the point of a layout, just a wink that
/// this is Duet. Kept to one glyph size so a row of them never competes with
/// real content for attention. Follows your skin unless given a color.
class HeartAccent extends StatelessWidget {
  const HeartAccent({super.key, this.size = 14, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SkinBuilder(
        builder: (context, skins) => Icon(
          skins.mineSkin.icon,
          size: size,
          color: (color ?? skins.accent).withValues(alpha: 0.85),
        ),
      );
}

ThemeData duetTheme() => ThemeData(
      brightness: Brightness.dark,
      // The gradient lives in GirlyBackdrop, painted once behind the whole app
      // by MaterialApp.builder -- an opaque scaffold color here would hide it
      // on every screen.
      scaffoldBackgroundColor: Colors.transparent,
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
  Widget build(BuildContext context) => SkinBuilder(
        builder: (context, skins) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: (color ?? DuetColors.surface).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border ?? skins.accent.withValues(alpha: 0.16)),
            boxShadow: [
              BoxShadow(
                color: skins.accent.withValues(alpha: 0.06),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
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
  Widget build(BuildContext context) => SkinBuilder(builder: (context, _) => _build());

  Widget _build() {
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
          ? Opacity(
              // FilledButton dims itself when disabled; a bespoke gradient
              // pill has to do that by hand.
              opacity: widget.onTap == null && !widget.busy ? 0.5 : 1,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(15),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: SkinColors.instance.wash,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: SkinColors.instance.accent.withValues(alpha: 0.25),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(15),
                    onTap: widget.busy ? null : widget.onTap,
                    child: Center(
                      child: IconTheme.merge(
                        data: const IconThemeData(color: DuetColors.amberInk),
                        child: DefaultTextStyle.merge(
                          style: const TextStyle(color: DuetColors.amberInk),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
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

/// A selectable look for one side of the pair. Stored as `profiles.accent`
/// (already existed in the schema, unused until now) -- picking one only ever
/// changes what color YOUR half of the ring paints, everywhere it appears,
/// including on your partner's phone once their app re-reads your profile.
class DuetSkin {
  const DuetSkin(this.id, this.label, this.color, this.icon);

  final String id;
  final String label;
  final Color color;
  final IconData icon;
}

const duetSkins = [
  DuetSkin('teal', 'Classic', DuetColors.teal, Icons.favorite_rounded),
  DuetSkin('blue', 'Blue', Color(0xFF6FA8DC), Icons.water_drop_rounded),
  DuetSkin('fish', 'Fish', Color(0xFF4FBFB0), Icons.set_meal_rounded),
  DuetSkin('horse', 'Horse', Color(0xFFC99A6B), Icons.pets_rounded),
];

DuetSkin skinFor(String? id) =>
    duetSkins.firstWhere((s) => s.id == id, orElse: () => duetSkins.first);

/// A skin's icon, animated with a small motion of its own -- a heartbeat for
/// Classic, a drip for Blue, a swim wag for Fish, a trot bounce for Horse.
/// Deliberately tiny and continuous rather than triggered: this plays in a
/// theme-picker swatch, not the ringing screen, so it can run forever without
/// competing for attention anywhere that matters.
class AnimatedSkinIcon extends StatefulWidget {
  const AnimatedSkinIcon({super.key, required this.skin, this.size = 22, this.color});

  final DuetSkin skin;
  final double size;
  final Color? color;

  @override
  State<AnimatedSkinIcon> createState() => _AnimatedSkinIconState();
}

class _AnimatedSkinIconState extends State<AnimatedSkinIcon>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(widget.skin.icon, size: widget.size, color: widget.color);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        switch (widget.skin.id) {
          case 'teal': // heartbeat
            final beat = (t < 0.2 ? (t / 0.2) : (t < 0.4 ? 1 - (t - 0.2) / 0.2 : 0));
            return Transform.scale(scale: 1 + beat * 0.22, child: child);
          case 'blue': // drip -- a small vertical bob
            return Transform.translate(
              offset: Offset(0, math.sin(t * 2 * math.pi) * 2.5),
              child: child,
            );
          case 'fish': // swim wag -- side-to-side rotation
            return Transform.rotate(
              angle: math.sin(t * 2 * math.pi) * 0.24,
              child: child,
            );
          case 'horse': // trot -- a quick vertical bounce
            final bounce = (math.sin(t * 2 * math.pi * 2)).abs();
            return Transform.translate(offset: Offset(0, -bounce * 3), child: child);
          default:
            return child!;
        }
      },
      child: icon,
    );
  }
}

/// The two ring colors currently in effect, one per person. A tiny global
/// notifier rather than a constructor param on every [PairRing] -- the ring
/// appears in ~15 places across the app, and a skin choice has to reach every
/// one of them the moment it changes, not just the screen that changed it.
/// Whoever resolves the pair (today: [PairGate] in main.dart) is responsible
/// for calling [setSkins] once profiles are loaded; unset defaults to the
/// original pink/lavender pairing so a solo or backend-less run looks exactly
/// as it always did.
class SkinColors extends ChangeNotifier {
  SkinColors._();
  static final instance = SkinColors._();

  // "mine" paints the right half (the "you" arc, historically teal); "partner"
  // paints the left half (the "them" arc, historically amber/pink). Matching
  // _PairRingPainter's existing convention below, not swapping it.
  //
  // mineSkin always resolves to a real skin (Classic by default). partnerSkin
  // is null whenever there is nothing distinct to show -- unset, or sitting on
  // the same never-picked db default as mine -- in which case the ring falls
  // back to the classic partner color with no animated badge, exactly as it
  // always looked before skins existed.
  DuetSkin mineSkin = duetSkins.first;
  DuetSkin? partnerSkin;

  Color get mine => mineSkin.color;
  Color get partner => partnerSkin?.color ?? DuetColors.amber;

  /// The app's primary accent -- buttons, glows, toggles, the lot. Your own
  /// skin, so picking one re-skins the whole app rather than just your half of
  /// the ring.
  Color get accent => mine;

  /// The two of you as one gradient: your color running into theirs. Used for
  /// every filled surface (buttons, the FAB, selected pills), so the pair is
  /// literally what the app is painted in. Unpaired, `partner` falls back to
  /// the classic pink and this reads much as it always did.
  LinearGradient get wash => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [mine, partner],
      );

  /// Either argument left null means "leave that side as it is" -- NOT
  /// "reset to default". The settings screen relies on this to update only
  /// its own side without clobbering whatever the partner's was last read as.
  void setSkins({String? mine, String? partner}) {
    final newMineSkin = mine != null ? skinFor(mine) : mineSkin;
    var newPartnerSkin = partner != null ? skinFor(partner) : partnerSkin;
    if (newPartnerSkin != null && newPartnerSkin.color == newMineSkin.color) {
      newPartnerSkin = null;
    }
    if (newMineSkin == mineSkin && newPartnerSkin == partnerSkin) return;
    mineSkin = newMineSkin;
    partnerSkin = newPartnerSkin;
    notifyListeners();
  }
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

  /// Below this the ring itself is too small for a badge to read as anything
  /// but a smudge -- most list-row uses (26-34px) skip it; the bigger
  /// sign-in/home/next-alarm rings (52px+) are where a skin actually shows.
  static const _badgeMinRingSize = 48.0;

  @override
  Widget build(BuildContext context) {
    // Rebuilds whenever a skin changes anywhere in the app, on top of this
    // ring's own breathing pulse -- Listenable.merge so one AnimatedBuilder
    // covers both without a second listener.
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, SkinColors.instance]),
      builder: (context, child) {
        final skins = SkinColors.instance;
        final r = (widget.size - widget.strokeWidth) / 2;
        final badge = (widget.size * 0.34).clamp(16.0, 26.0);

        final ring = SizedBox(
          // CustomPaint only honours `size` when it is otherwise unconstrained
          // -- inside a stretching Column it would expand to the full width
          // and the ring would swallow the screen. The SizedBox pins it either
          // way.
          width: widget.size,
          height: widget.size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _PairRingPainter(
                  hasPartner: widget.hasPartner,
                  strokeWidth: widget.strokeWidth,
                  mine: skins.mine,
                  partner: skins.partner,
                ),
              ),
              if (widget.size >= _badgeMinRingSize) ...[
                _skinBadge(skins.mineSkin, badge, left: widget.size / 2 + r - badge / 2),
                if (widget.hasPartner && skins.partnerSkin != null)
                  _skinBadge(skins.partnerSkin!, badge,
                      left: widget.size / 2 - r - badge / 2),
              ],
            ],
          ),
        );
        if (!widget.animate) return ring;
        return Transform.scale(scale: 1 + _controller.value * 0.035, child: ring);
      },
    );
  }

  Widget _skinBadge(DuetSkin skin, double badge, {required double left}) => Positioned(
        left: left,
        top: widget.size / 2 - badge / 2,
        child: Container(
          width: badge,
          height: badge,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: DuetColors.bgDeep,
            border: Border.all(color: skin.color, width: 1.4),
          ),
          child: Center(
            child: AnimatedSkinIcon(skin: skin, size: badge * 0.56, color: skin.color),
          ),
        ),
      );
}

class _PairRingPainter extends CustomPainter {
  _PairRingPainter({
    required this.hasPartner,
    required this.strokeWidth,
    required this.mine,
    required this.partner,
  });

  final bool hasPartner;
  final double strokeWidth;
  final Color mine;
  final Color partner;

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
    canvas.drawArc(rect, -1.5708, 3.1416, false, arc(mine));
    if (hasPartner) {
      canvas.drawArc(rect, 1.5708, 3.1416, false, arc(partner));
    }
  }

  @override
  bool shouldRepaint(_PairRingPainter old) =>
      old.hasPartner != hasPartner ||
      old.strokeWidth != strokeWidth ||
      old.mine != mine ||
      old.partner != partner;
}
