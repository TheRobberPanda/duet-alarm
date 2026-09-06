import 'dart:math' as math;

import 'alarm_engine.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  static const bgHigh = Color(0xFF221823);

  // Cards are no longer flat fills -- they are lit from the top-left like the
  // design canvas's 160deg two-stop gradients, with [edge] catching light along
  // the top rim so a raised surface reads as raised without a heavy shadow.
  static const surface = Color(0xFF251A22);
  static const surfaceTop = Color(0xFF31222C);
  static const surfaceEdge = Color(0xFF3B2935);
  static const surfaceBottom = Color(0xFF201620);
  static const surfaceRaised = Color(0xFF33232D);
  static const line = Color(0xFF402C38);
  static const edge = Color(0x24F9EBF3);

  static const text = Color(0xFFF9EBF3);
  static const muted = Color(0xFFCBA8BE);
  static const dim = Color(0xFF937284);
  static const faint = Color(0xFF5F4555);

  static const amber = Color(0xFFF0A8C8);
  static const amberInk = Color(0xFF3D1526);
  static const teal = Color(0xFFC9AEE8);
  static const danger = Color(0xFFE87DA0);

  // Semantic, not decorative: diagnostics needs an unambiguous "this is fine"
  // that is not the skin accent (using pink for "no battery problem" read as
  // decoration). A muted sage that sits quietly in the plum field.
  static const success = Color(0xFFA9C9B8);

  // NOTE: the app's accent gradient is NOT here. It lives on SkinColors as a
  // live getter, because it depends on which skin each of you picked -- see
  // SkinColors.wash. These constants are only the fallbacks it defaults to.
}

/// The type ramp. Time is the hero element everywhere it appears: large,
/// generously tracked, tabular figures so a ticking countdown never jitters.
/// UI text is Hanken Grotesk (bundled as 'Duet UI'); [serif] is the one
/// celebratory voice and is capped at one appearance per screen.
class DuetText {
  static TextStyle time(double size,
          {double tracking = 1.0,
          FontWeight weight = FontWeight.w800,
          Color color = DuetColors.text}) =>
      TextStyle(
        fontFamily: 'Duet Display',
        fontSize: size,
        height: 1.02,
        letterSpacing: tracking,
        fontWeight: weight,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static const serif =
      TextStyle(fontFamily: 'Duet Serif', fontSize: 36, height: 1.08, color: DuetColors.text);

  static const serifItalic = TextStyle(
      fontFamily: 'Duet Serif',
      fontSize: 36,
      height: 1.08,
      fontStyle: FontStyle.italic,
      color: DuetColors.text);
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [skins.pal.bgDeep, skins.pal.bg],
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
        builder: (context, skins) => builder(context, SkinColors.instance),
      );
}

/// Pushes the current theme's world down to the native ringing screen -- its
/// background and (when paired) the partner's display name for the farewell
/// message. Call wherever skins are pushed: pair resolution and theme picks.
/// One helper, so the two callers can never drift.
Future<void> pushCosmetics({String? partnerName}) =>
    AlarmEngine.setCosmetics(
      partnerName: partnerName,
      bgColor: SkinColors.instance.pal.bgDeep.toARGB32(),
    );

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
      // Hanken Grotesk, bundled as 'Duet UI' (pubspec fonts). Previously this
      // was the device's own sans -- free and native, but it meant MiSans,
      // Roboto and One UI Sans each rendered Duet as a different app, and none
      // of them had the humanist warmth the design canvases specify. The trade
      // (a few hundred KB of TTFs) buys the identity the product deserves.
      fontFamily: 'Duet UI',
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
            // Lit-from-top-left gradient body with a lighter rim on the first
            // stop -- the canvas's card treatment. An explicit [color] opts out
            // (danger cards etc. stay solid). Colors follow your theme.
            gradient: color != null
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: const [0, 0.45, 1],
                    colors: [
                      skins.pal.surfaceEdge,
                      skins.pal.surfaceTop,
                      skins.pal.surfaceBottom,
                    ],
                  ),
            color: color?.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border ?? skins.accent.withValues(alpha: 0.16)),
            boxShadow: [
              BoxShadow(
                color: skins.accent.withValues(alpha: 0.07),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      );
}

class DuetButton extends StatefulWidget {
  const DuetButton(this.label, {super.key, this.onTap, this.filled = false, this.busy = false, this.icon});

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool busy;

  /// Optional leading glyph -- the filled pill is the app's primary CTA and a
  /// small icon gives it a face ("+ new alarm").
  final IconData? icon;

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
    final label = Text(widget.label,
        style: TextStyle(
            fontSize: widget.filled ? 16.5 : 15.5,
            fontWeight: widget.filled ? FontWeight.w600 : FontWeight.w500));
    final child = widget.busy
        ? const SizedBox(
            height: 20, width: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: DuetColors.amberInk))
        : widget.icon == null
            ? label
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon,
                      size: 17,
                      color: widget.filled ? DuetColors.amberInk : SkinColors.instance.accent),
                  const SizedBox(width: 8),
                  label,
                ],
              );

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
  const DuetSkin(this.id, this.label, this.color, this.icon, this.palette);

  final String id;
  final String label;
  final Color color;
  final IconData icon;

  /// The world the theme paints: backgrounds, surfaces and hairlines. Picking
  /// a theme re-skins the whole app, not just the accents -- ADR-016.
  final SkinPalette palette;

  /// The theme's mascot -- the same glyph that rides your ring badges, shown
  /// large and faint behind the home dial.
  IconData get mascot => icon;
}

/// A theme's own backgrounds. All dark, all tuned so [DuetColors.text] stays
/// readable on every one -- a theme that traded legibility for personality
/// would be a theme nobody can use at 06:00.
class SkinPalette {
  const SkinPalette({
    required this.bgDeep,
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceTop,
    required this.surfaceEdge,
    required this.surfaceBottom,
    required this.line,
  });

  final Color bgDeep;
  final Color bg;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceTop;
  final Color surfaceEdge;
  final Color surfaceBottom;
  final Color line;
}

const skinPalettes = <String, SkinPalette>{
  // Classic: the original plum, unchanged -- the fallback everything else
  // diverges from.
  'teal': SkinPalette(
    bgDeep: DuetColors.bgDeep,
    bg: DuetColors.bg,
    surface: DuetColors.surface,
    surfaceRaised: DuetColors.surfaceRaised,
    surfaceTop: DuetColors.surfaceTop,
    surfaceEdge: DuetColors.surfaceEdge,
    surfaceBottom: DuetColors.surfaceBottom,
    line: DuetColors.line,
  ),
  // Blue: midnight navy -- the same night sky, a colder latitude.
  'blue': SkinPalette(
    bgDeep: Color(0xFF0C1018),
    bg: Color(0xFF101623),
    surface: Color(0xFF18212F),
    surfaceRaised: Color(0xFF223045),
    surfaceTop: Color(0xFF232E40),
    surfaceEdge: Color(0xFF2B3A50),
    surfaceBottom: Color(0xFF131A27),
    line: Color(0xFF2E3C52),
  ),
  // Fish: a deep teal lagoon -- dim light through water.
  'fish': SkinPalette(
    bgDeep: Color(0xFF0A1416),
    bg: Color(0xFF0E1A1D),
    surface: Color(0xFF142427),
    surfaceRaised: Color(0xFF1E3338),
    surfaceTop: Color(0xFF1D3236),
    surfaceEdge: Color(0xFF253C41),
    surfaceBottom: Color(0xFF101D20),
    line: Color(0xFF2A444C),
  ),
  // Horse: warm desert brown -- sundown on sand, the warmest of the four.
  'horse': SkinPalette(
    bgDeep: Color(0xFF171009),
    bg: Color(0xFF1D1610),
    surface: Color(0xFF271D14),
    surfaceRaised: Color(0xFF33271B),
    surfaceTop: Color(0xFF33271B),
    surfaceEdge: Color(0xFF3E2F20),
    surfaceBottom: Color(0xFF1F1710),
    line: Color(0xFF423424),
  ),
};

// final, not const: each entry indexes the palette map, which is not a const
// expression. Cheap regardless -- built once, read-only afterwards.
final duetSkins = [
  DuetSkin('teal', 'Classic', DuetColors.teal, Icons.favorite_rounded, skinPalettes['teal']!),
  DuetSkin('blue', 'Blue', Color(0xFF6FA8DC), Icons.water_drop_rounded, skinPalettes['blue']!),
  DuetSkin('fish', 'Fish', Color(0xFF4FBFB0), Icons.set_meal_rounded, skinPalettes['fish']!),
  DuetSkin('horse', 'Horse', Color(0xFFC99A6B), Icons.pets_rounded, skinPalettes['horse']!),
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
  // 1800ms, not faster: these glyphs animate for as long as their screen is
  // alive, and a per-second heartbeat reads as alive while a per-half-second
  // one reads as busy. Slow is the house style.
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
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

  /// The world your theme paints: every background, surface and hairline in
  /// the app reads from here, so picking a theme re-dresses the whole app
  /// (ADR-016). Partner skins colour their half of the ring; backgrounds are
  /// always YOURS.
  SkinPalette get pal => mineSkin.palette;

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
    this.mineOn = true,
    this.strokeWidth = 2.5,
    this.animate = true,
    this.fill = false,
    this.partnerExists,
  });

  final double size;

  /// Whether the partner's half is drawn at all: they exist AND have this
  /// alarm switched on their end (Alarm.partnerEnabled).
  final bool hasPartner;

  /// Whether a partner exists at all. Defaults to [hasPartner]; pass it
  /// separately where the caller knows both facts -- a paired partner who has
  /// THIS alarm off draws a *dashed* arc ("they're in, just not for this one")
  /// rather than bare track, which is the canvas's "not yet" state. No partner
  /// at all draws nothing.
  final bool? partnerExists;

  /// Whether YOUR half is drawn -- i.e. you have it switched on. A ring with
  /// neither half lit is just the dim track, which is exactly what an alarm
  /// nobody has enabled should look like.
  final bool mineOn;

  final double strokeWidth;
  final bool animate;

  /// Paint the inside of the ring as two vertical transparent halves, split
  /// down the 12-to-6 axis: right half yours, left half theirs -- the same
  /// split the arcs use, so the fill and the ring tell one story. Each side
  /// only fills if that person has the alarm on; a dashed partner ("not
  /// yet") leaves their half empty.
  final bool fill;

  @override
  State<PairRing> createState() => _PairRingState();
}

class _PairRingState extends State<PairRing> with TickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);

  // Drives the wave on the interior fill's seam. Only runs when a fill is
  // actually on screen -- list rows and badges never pay for it. Two
  // tickers, hence TickerProviderStateMixin (plural): the single-ticker
  // variant asserts and throws a red box at runtime.
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void initState() {
    super.initState();
    if (widget.fill && widget.animate) _wave.repeat();
  }

  @override
  void didUpdateWidget(PairRing old) {
    super.didUpdateWidget(old);
    final wanted = widget.fill && widget.animate;
    if (wanted && !_wave.isAnimating) {
      _wave.repeat();
    } else if (!wanted && _wave.isAnimating) {
      _wave.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _wave.dispose();
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
      animation: Listenable.merge([_controller, SkinColors.instance, _wave]),
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
                  partnerExists: widget.partnerExists ?? widget.hasPartner,
                  mineOn: widget.mineOn,
                  strokeWidth: widget.strokeWidth,
                  fill: widget.fill,
                  wavePhase: _wave.value * math.pi * 2,
                  line: skins.pal.line,
                  mine: skins.mine,
                  partner: skins.partner,
                ),
              ),
              if (widget.size >= _badgeMinRingSize) ...[
                if (widget.mineOn)
                  _skinBadge(skins.mineSkin, badge, left: widget.size / 2 + r - badge / 2),
                if (widget.hasPartner && skins.partnerSkin != null)
                  _skinBadge(skins.partnerSkin!, badge,
                      left: widget.size / 2 - r - badge / 2),
              ],
            ],
          ),
        );
        if (!widget.animate) return ring;
        // Scale AND opacity: the canvas's ringBreathe keyframe pulses both, and
        // the opacity component is what makes it read as breathing rather than
        // as a widget being resized under your eye.
        return Opacity(
          opacity: 0.82 + 0.18 * _controller.value,
          child: Transform.scale(scale: 1 + _controller.value * 0.035, child: ring),
        );
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
    required this.partnerExists,
    required this.mineOn,
    required this.strokeWidth,
    required this.fill,
    required this.wavePhase,
    required this.line,
    required this.mine,
    required this.partner,
  });

  final bool hasPartner;

  /// A partner exists but hasn't switched this alarm on -- their arc draws
  /// dashed instead of absent.
  final bool partnerExists;
  final bool mineOn;
  final double strokeWidth;

  /// Interior fill up to the halfway line (see [PairRing.fill]).
  final bool fill;

  /// Drives the travelling wave on the fill's seam. Static when the ring
  /// does not animate.
  final double wavePhase;
  final Color line;
  final Color mine;
  final Color partner;

  /// The canvas's `stroke-dasharray: 3 7` "not yet" arc: short dashes walking
  /// the circumference, sized in pixels and converted to radians per radius so
  /// the dash rhythm is identical at ring sizes 26 and 230.
  void dashedArc(Canvas canvas, Rect rect, double start, double sweep, Paint paint) {
    final r = rect.width / 2;
    final dash = 3.0 / r;
    final gap = 7.0 / r;
    var a = 0.0;
    while (a < sweep) {
      final len = math.min(dash, sweep - a);
      canvas.drawArc(rect, start + a, len, false, paint);
      a += dash + gap;
    }
  }

  /// One half-disc of the interior: the arc from [start] sweeping [sweep],
  /// closed back through the centre.
  void halfFill(Canvas canvas, Rect rect, double start, double sweep, Color colour) {
    final path = Path()
      ..moveTo(rect.center.dx, rect.center.dy)
      ..arcTo(rect, start, sweep, false)
      ..close();
    canvas.drawPath(path, Paint()..color = colour);
  }

  /// The seam between the two fills: a vertical wave through the centre,
  /// damped to nothing at the top and bottom so it always meets the ring
  /// exactly. [phase] animates it; both halves sample the same points, so
  /// they join with no gap ever.
  List<Offset> seamPoints(Offset c, double r, double phase) {
    return List<Offset>.generate(13, (i) {
      final u = i / 12;
      final amp = r * 0.055 * math.sin(u * math.pi);
      final x = c.dx + amp * math.sin(phase + u * math.pi * 4);
      return Offset(x, c.dy - r + u * 2 * r);
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.width - strokeWidth) / 2;
    final c = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: c, radius: r);

    // Interior fills go first, behind everything: two vertical half-discs
    // split at the 12-to-6 line -- right yours, left theirs -- with the seam
    // between them a slow travelling wave when both are up. Alone, just your
    // half fills; a dashed partner leaves their half empty.
    if (fill) {
      if (mineOn && hasPartner) {
        final seam = seamPoints(c, r, wavePhase);

        // Both halves start at 12 o'clock and sweep to 6 -- [dir] +1 down
        // the right side (you), -1 down the left (them) -- then follow the
        // shared seam back up. Identical seam points, so they join cleanly.
        Path halfWithSeam(double dir) {
          final path = Path()
            ..moveTo(c.dx, c.dy - r)
            ..arcTo(rect, -math.pi / 2, dir * math.pi, false);
          for (var i = seam.length - 1; i >= 0; i--) {
            path.lineTo(seam[i].dx, seam[i].dy);
          }
          return path..close();
        }

        canvas.drawPath(
            halfWithSeam(1), Paint()..color = mine.withValues(alpha: 0.14));
        canvas.drawPath(
            halfWithSeam(-1), Paint()..color = partner.withValues(alpha: 0.14));

        final seamPath = Path()..moveTo(seam.first.dx, seam.first.dy);
        for (final p in seam) {
          seamPath.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(
          seamPath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = DuetColors.text.withValues(alpha: 0.12),
        );
      } else if (mineOn) {
        halfFill(canvas, rect, -math.pi / 2, math.pi, mine.withValues(alpha: 0.14));
      } else if (hasPartner) {
        halfFill(canvas, rect, math.pi / 2, math.pi, partner.withValues(alpha: 0.14));
      }
    }

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = line;
    canvas.drawCircle(c, r, track);

    Paint arc(Color colour) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = colour;

    // Right half = you, left half = them -- each drawn only if that person
    // has the alarm switched on, so the ring reads at a glance as "we are
    // both up for this" / "only one of us is". A dashed partner arc means
    // "paired, but sitting this one out" (docs canvas: the "not yet" state).
    if (mineOn) canvas.drawArc(rect, -1.5708, 3.1416, false, arc(mine));
    if (hasPartner) {
      canvas.drawArc(rect, 1.5708, 3.1416, false, arc(partner));
    } else if (partnerExists) {
      dashedArc(canvas, rect, 1.5708, 3.1416, arc(partner.withValues(alpha: 0.45)));
    }
  }

  @override
  bool shouldRepaint(_PairRingPainter old) =>
      old.hasPartner != hasPartner ||
      old.partnerExists != partnerExists ||
      old.mineOn != mineOn ||
      old.strokeWidth != strokeWidth ||
      old.fill != fill ||
      old.wavePhase != wavePhase ||
      old.line != line ||
      old.mine != mine ||
      old.partner != partner;
}

// ---------------------------------------------------------------------------
// The component library below is the app's shared visual vocabulary. Screens
// reach for these instead of hand-rolling look-alikes -- the drift bug (two
// screens shipping different hard-coded switch colours) is exactly what this
// prevents.
// ---------------------------------------------------------------------------

/// A radial glow of the two of you standing behind a hero element -- the dial
/// on home, the check on the wake receipt. The canvas paints one halo per
/// hero; ours is two softly offset discs (yours top-right, theirs bottom-left)
/// so the light itself is a pair. Purely paint; [IgnorePointer] so it never
/// blocks the thing it illuminates.
class HaloGlow extends StatelessWidget {
  const HaloGlow({super.key, required this.child, this.size = 420, this.opacity = 1.0});

  final Widget child;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) => SkinBuilder(
        builder: (context, skins) => Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: IgnorePointer(
                child: CustomPaint(
                  size: Size(size, size),
                  painter: _HaloPainter(mine: skins.mine, partner: skins.partner, opacity: opacity),
                ),
              ),
            ),
            child,
          ],
        ),
      );
}

class _HaloPainter extends CustomPainter {
  _HaloPainter({required this.mine, required this.partner, required this.opacity});

  final Color mine;
  final Color partner;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    void glow(Color col, Offset offset, double strength) {
      final paint = Paint()
        ..shader = RadialGradient(colors: [
          col.withValues(alpha: 0.13 * strength * opacity),
          col.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c + offset, radius: r));
      canvas.drawCircle(c + offset, r, paint);
    }

    glow(mine, const Offset(0.22, -0.18), 1);
    glow(partner, const Offset(-0.24, 0.20), 0.8);
  }

  @override
  bool shouldRepaint(_HaloPainter old) =>
      old.mine != mine || old.partner != partner || old.opacity != opacity;
}

/// A small status pill: "SYNCED", "UP FIRST", "9 MIN LATER". Glass fill in the
/// pill's colour, tiny dot or icon, uppercase label. Never more than one or
/// two per screen or they stop being signals.
class DuetPill extends StatelessWidget {
  const DuetPill(this.text, {super.key, this.color, this.icon, this.dot = false});

  final String text;
  final Color? color;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) => SkinBuilder(
        builder: (context, skins) {
          final col = color ?? skins.accent;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: col.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: col.withValues(alpha: 0.28)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dot) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: col),
                  ),
                  const SizedBox(width: 6),
                ] else if (icon != null) ...[
                  Icon(icon, size: 12, color: col),
                  const SizedBox(width: 5),
                ],
                Text(
                  text.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0.9,
                    fontWeight: FontWeight.w600,
                    color: col,
                  ),
                ),
              ],
            ),
          );
        },
      );
}

/// The one switch. Skin-coloured when on (the app re-skins with your pick),
/// quiet plum when off -- replacing the hard-coded inactive colours that
/// drifted between screens. Used by home and settings so the two can never
/// disagree again.
class DuetSwitch extends StatelessWidget {
  const DuetSwitch({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SkinBuilder(
        builder: (context, skins) => Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: DuetColors.amberInk,
          activeTrackColor: skins.mine,
          inactiveThumbColor: DuetColors.muted,
          inactiveTrackColor: skins.pal.surfaceRaised,
          trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
          // Your skin rides in the thumb of every switch -- the signature
          // follows your hand, not just the ring.
          thumbIcon: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? Icon(skins.mineSkin.icon, size: 14, color: DuetColors.amberInk)
                  : null),
        ),
      );
}

/// An initial-avatar with a colour ring -- yours or theirs. The paired
/// avatars on the canvas overlap; position two of these in a Stack to get
/// that. Unpaired callers pass an empty [initial] for the hollow state.
class AvatarBadge extends StatelessWidget {
  const AvatarBadge(
      {super.key, this.initial = '', this.icon, this.color, this.size = 36, this.ring = true});

  final String initial;

  /// Overrides the initial with a glyph -- the paired strip uses the two skin
  /// icons so the avatars are literally the two of you.
  final IconData? icon;
  final Color? color;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) => SkinBuilder(
        builder: (context, skins) {
          final col = color ?? skins.accent;
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: skins.pal.bgDeep,
              border: Border.all(color: ring ? col : skins.pal.line, width: 1.4),
            ),
            alignment: Alignment.center,
            child: icon != null
                ? Icon(icon, size: size * 0.45, color: col)
                : initial.isEmpty
                    ? Icon(Icons.person_rounded, size: size * 0.45, color: DuetColors.faint)
                    : Text(
                        initial,
                        style: TextStyle(
                          fontSize: size * 0.4,
                          fontWeight: FontWeight.w600,
                          color: col,
                        ),
                      ),
          );
        },
      );
}

/// A quiet loading placeholder. A breathing opacity pulse, not a spinner --
/// spinners say "something went wrong" after three seconds; shimmering shapes
/// say "this screen is arriving" and look like it even while stalled.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 16, this.radius = 12});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SkinBuilder(
        builder: (context, skins) => FadeTransition(
        opacity: Tween(begin: 0.35, end: 0.8).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        ),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: skins.pal.surfaceRaised.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
        ),
      );
}

/// Waveform bars for sound rows -- the canvas gives every sound a little bar
/// chart instead of a generic icon. Static when idle; the bars dance in a
/// slow per-bar phase while that sound is playing. Seven bars, patterned so
/// an idle row still looks like sound rather than noise.
class WaveformBars extends StatefulWidget {
  const WaveformBars({super.key, this.playing = false, this.count = 7, this.height = 18, this.color});

  final bool playing;
  final int count;
  final double height;
  final Color? color;

  @override
  State<WaveformBars> createState() => _WaveformBarsState();
}

class _WaveformBarsState extends State<WaveformBars> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 950));

  @override
  void initState() {
    super.initState();
    // The controller runs ONLY while this row is actually playing. It used to
    // repeat forever on every row on screen -- a dozen idle rows each
    // repainting at 60fps was the single most wasteful thing in the app.
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(WaveformBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !old.playing) {
      _controller.repeat();
    } else if (!widget.playing && old.playing) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // A fixed silhouette so idle rows are stable frame to frame.
  static const _idle = [0.38, 0.72, 0.5, 0.9, 0.58, 0.34, 0.68, 0.5, 0.78];

  @override
  Widget build(BuildContext context) => SkinBuilder(
        builder: (context, skins) {
          final col = (widget.color ?? skins.accent).withValues(alpha: 0.75);
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              return SizedBox(
                height: widget.height,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (var i = 0; i < widget.count; i++)
                      Container(
                        width: 2.5,
                        height: widget.height *
                            math.max(
                              0.18,
                              widget.playing
                                  ? _idle[i % _idle.length] *
                                      (0.55 + 0.45 * math.sin(t * 2 * math.pi + i * 0.9))
                                  : _idle[i % _idle.length],
                            ),
                        margin: const EdgeInsets.symmetric(horizontal: 1.4),
                        decoration: BoxDecoration(
                          color: col,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      );
}

/// Destructive (or otherwise deliberate) actions are press-and-HOLD, not tap.
/// The canvas puts this on the ringing screen's "for both of us" row -- a
/// Dismiss fired for your partner by a stray tap is the worst thing this app
/// can do, and a hold with a visible progress fill makes that impossible to
/// do in your sleep. Fires [onComplete] once at full progress; releasing
/// early rewinds.
class PressAndHoldButton extends StatefulWidget {
  const PressAndHoldButton({
    super.key,
    required this.label,
    required this.onComplete,
    this.icon = Icons.touch_app_rounded,
    this.destructive = false,
    this.height = 52,
    this.doneLabel,
  });

  final String label;
  final VoidCallback onComplete;
  final IconData icon;
  final bool destructive;
  final double height;

  /// Shown once the hold completes, until the parent removes the button.
  final String? doneLabel;

  @override
  State<PressAndHoldButton> createState() => _PressAndHoldButtonState();
}

class _PressAndHoldButtonState extends State<PressAndHoldButton>
    with SingleTickerProviderStateMixin {
  // Explicit type: the status-listener closure calls widget.onComplete(),
  // which the inferencer would otherwise read as a self-referencing cycle.
  //
  // 2000ms: the whole point of a hold is that it cannot happen by accident
  // or in your sleep -- two full seconds of intent.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Haptics are release-only: dev builds stay silent on the bench
        // (kDebugMode), real phones get the full buzz.
        if (!kDebugMode) HapticFeedback.heavyImpact();
        // The system alert blip: a deletion you can HEAR finished, on the
        // sound stream the phone already owns. No new asset, no new package.
        SystemSound.play(SystemSoundType.alert);
        // Lock in the done state instead of rewinding -- the fill holds at
        // full and the label becomes "Done" until the parent removes this
        // button. Rewinding made the completion blink past unnoticed.
        setState(() => _fired = true);
        widget.onComplete();
      }
    });

  /// Set when the hold completes; freezes the fill at full and swaps the
  /// label, so a slow parent (an editor that pauses a beat before popping)
  /// shows a done state instead of rewinding.
  bool _fired = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    if (_fired) return;
    if (!kDebugMode) HapticFeedback.selectionClick();
    _controller.forward();
  }
  void _stop() {
    // Only rewinds if not already completed -- a completed hold stays done.
    if (!_fired && _controller.status == AnimationStatus.forward) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) => SkinBuilder(
        builder: (context, skins) {
          final tint = widget.destructive ? DuetColors.danger : skins.accent;
          // Pinned size, same discipline as DuetButton: the Stack below wants
          // to expand, and inside an unbounded list context that either
          // collapses to nothing or drags the layout down with it.
          return SizedBox(
            width: double.infinity,
            height: widget.height,
            child: Listener(
            onPointerDown: (_) => _start(),
            onPointerUp: (_) => _stop(),
            onPointerCancel: (_) => _stop(),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                // Once fired, the fill holds at full -- frozen, not rewound.
                final v = _fired ? 1.0 : _controller.value;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: SkinColors.instance.pal.surface.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: tint.withValues(alpha: 0.3 + 0.3 * v)),
                        ),
                      ),
                      // The fill that says "keep holding" -- sweeps left to
                      // right with the press.
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: v,
                        child: ColoredBox(color: tint.withValues(alpha: 0.16)),
                      ),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // The icon tells the truth about the press:
                            // delete while you start, check as the hold
                            // completes.
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: Icon(
                                v > 0.92
                                    ? Icons.check_rounded
                                    : widget.icon,
                                key: ValueKey(v > 0.92),
                                size: 17,
                                color: Color.lerp(DuetColors.muted, tint, v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _fired ? (widget.doneLabel ?? 'Done') : widget.label,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: Color.lerp(DuetColors.muted, tint, v),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            ),
          );
        },
      );
}

/// Every confirmation in the app goes through here -- the stock
/// [AlertDialog] shape (hard corners of the platform, blue-tinted buttons)
/// broke the spell every time it opened. Body is the plum gradient card;
/// actions are [DuetDialogAction]s.
Future<T?> showDuetDialog<T>({
  required BuildContext context,
  required String title,
  String? body,
  Widget? content,
  required List<Widget> actions,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (ctx) => SkinBuilder(
      builder: (context, skins) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0, 0.45, 1],
              colors: [
                SkinColors.instance.pal.surfaceEdge,
                SkinColors.instance.pal.surfaceTop,
                SkinColors.instance.pal.surfaceBottom,
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: skins.accent.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 40,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 18.5, fontWeight: FontWeight.w600)),
              if (body != null) ...[
                const SizedBox(height: 10),
                Text(
                  body,
                  style: const TextStyle(fontSize: 14.5, height: 1.45, color: DuetColors.muted),
                ),
              ],
              if (content != null) ...[const SizedBox(height: 12), content],
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 6,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A dialog action button. Destructive ones go danger-tinted so a "delete" is
/// never dressed as a "maybe".
class DuetDialogAction extends StatelessWidget {
  const DuetDialogAction(this.label, {super.key, this.onPressed, this.destructive = false});

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) => SkinBuilder(
        builder: (context, skins) => TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: destructive ? DuetColors.danger : skins.accent,
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
          ),
          child: Text(label),
        ),
      );
}

/// The one snackbar. Glass plum with the accent (or danger) leading an icon,
/// optionally carrying a single action -- the delete toast lives on this.
void showDuetSnackBar(
  BuildContext context,
  String text, {
  IconData? icon,
  bool error = false,
  String? action,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: action == null
            ? const Duration(seconds: 4)
            : const Duration(seconds: 6), // an action needs reading time
        elevation: 0,
        backgroundColor: Colors.transparent,
        content: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                SkinColors.instance.pal.surfaceTop,
                SkinColors.instance.pal.surfaceBottom,
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: (error ? DuetColors.danger : SkinColors.instance.accent).withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                icon ?? (error ? Icons.error_outline_rounded : Icons.check_circle_rounded),
                size: 18,
                color: error ? DuetColors.danger : SkinColors.instance.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, style: const TextStyle(fontSize: 14, color: DuetColors.text)),
              ),
              if (action != null)
                TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    onAction?.call();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor:
                        error ? DuetColors.danger : SkinColors.instance.accent,
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  child: Text(action),
                ),
            ],
          ),
        ),
      ),
    );
}

/// The theme's mascot standing faintly behind the home dial -- a watermark of
/// the world you picked, lit with the pair gradient so it is literally the
/// two of you. One large glyph, one slow motion per theme (the same mapping
/// as [AnimatedSkinIcon], amplitudes halved: behind the dial it may only
/// breathe, never perform).
class MascotBehindRing extends StatefulWidget {
  const MascotBehindRing({super.key, this.size = 340, this.opacity = 1.0});

  final double size;
  final double opacity;

  @override
  State<MascotBehindRing> createState() => _MascotBehindRingState();
}

class _MascotBehindRingState extends State<MascotBehindRing>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SkinBuilder(
        builder: (context, skins) {
          final skin = skins.mineSkin;
          return IgnorePointer(
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final t = _controller.value;
                  Widget glyph = ShaderMask(
                    shaderCallback: (bounds) => skins.wash.createShader(bounds),
                    blendMode: BlendMode.srcIn,
                    child: Icon(
                      skin.mascot,
                      size: widget.size * 0.62,
                      color: Colors.white,
                    ),
                  );
                  switch (skin.id) {
                    case 'teal': // heartbeat, half strength
                      final beat =
                          (t < 0.25 ? (t / 0.25) : (t < 0.5 ? 1 - (t - 0.25) / 0.25 : 0));
                      glyph = Transform.scale(scale: 1 + beat * 0.05, child: glyph);
                    case 'blue': // slow rise and settle
                      glyph = Transform.translate(
                        offset: Offset(0, math.sin(t * 2 * math.pi) * 5),
                        child: glyph,
                      );
                    case 'fish': // a lazy drift, not a swim
                      glyph = Transform.rotate(
                        angle: math.sin(t * 2 * math.pi) * 0.06,
                        child: glyph,
                      );
                    case 'horse': // a trot at walking pace
                      glyph = Transform.translate(
                        offset: Offset(0, -math.sin(t * 2 * math.pi * 2).abs() * 4),
                        child: glyph,
                      );
                  }
                  return Opacity(opacity: 0.09 * widget.opacity, child: glyph);
                },
              ),
            ),
          );
        },
      );
}
