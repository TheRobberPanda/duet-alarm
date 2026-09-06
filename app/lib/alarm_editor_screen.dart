import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alarm.dart';
import 'alarm_engine.dart';
import 'alarm_repository.dart';
import 'clock_picker.dart';
import 'next_fire.dart';
import 'sound_picker_screen.dart';
import 'theme.dart';

class AlarmEditorScreen extends StatefulWidget {
  const AlarmEditorScreen({super.key, this.alarm});

  /// Null when creating.
  final Alarm? alarm;

  @override
  State<AlarmEditorScreen> createState() => _AlarmEditorScreenState();
}

class _AlarmEditorScreenState extends State<AlarmEditorScreen> {
  final _repo = AlarmRepository.instance;
  late TextEditingController _label;

  late int _hour;
  late int _minute;
  late int _repeatDays;
  late String _soundRef;
  late int _snoozeMinutes;
  late int _maxSnoozes;
  late RingTarget _target;

  String _soundTitle = 'Default alarm';

  bool get _isNew => widget.alarm == null;

  /// The one-time nudge that the big time is itself a button.
  ///
  /// The steppers are right underneath it and look like the control, so people
  /// nudge 07:00 to 06:30 one minute at a time and never discover the dial.
  /// Shown on a new alarm until the dial has been opened once, then never
  /// again -- a coach mark that keeps appearing after you have learned the
  /// thing is just furniture.
  bool _showTimeHint = false;
  static const _hintSeenKey = 'seen_time_dial_hint';

  @override
  void initState() {
    super.initState();
    final a = widget.alarm;
    final now = DateTime.now();
    _hour = a?.hour ?? (now.hour + 1) % 24;
    _minute = a?.minute ?? 0;
    _repeatDays = a?.repeatDays ?? Repeat.none;
    _soundRef = a?.soundRef ?? 'default';
    _snoozeMinutes = a?.snoozeMinutes ?? 9;
    _maxSnoozes = a?.maxSnoozes ?? 3;
    _target = a?.ringTarget ?? RingTarget.both;
    _label = TextEditingController(text: a?.label ?? '');
    _resolveSoundTitle();
    if (_isNew) _maybeShowTimeHint();
  }

  Future<void> _maybeShowTimeHint() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || prefs.getBool(_hintSeenKey) == true) return;
    setState(() => _showTimeHint = true);
  }

  Future<void> _retireTimeHint() async {
    if (_showTimeHint && mounted) setState(() => _showTimeHint = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hintSeenKey, true);
  }

  @override
  void dispose() {
    _label.dispose();
    AlarmEngine.stopPreview();
    super.dispose();
  }

  Future<void> _resolveSoundTitle() async {
    if (_soundRef == 'default') {
      setState(() => _soundTitle = 'Default alarm');
      return;
    }
    final sounds = await AlarmEngine.listSounds();
    for (final s in sounds) {
      if (s.ref == _soundRef && mounted) {
        setState(() => _soundTitle = s.title);
        return;
      }
    }
    if (mounted) setState(() => _soundTitle = 'Custom sound');
  }

  // The platform showTimePicker is gone: it opened as a stock modal in the
  // middle of an otherwise bespoke screen. The hero time is edited right
  // where it stands -- chevrons for one-minute nudges, the plum clock dial
  // (below) for seeing the hour laid out.
  void _bumpHour(int delta) => setState(() => _hour = (_hour + delta + 24) % 24);

  void _bumpMinute(int delta) => setState(() => _minute = (_minute + delta + 60) % 60);

  Future<void> _openClock() async {
    // Opening the dial IS learning it -- retire the hint whether or not a time
    // is actually picked.
    await _retireTimeHint();
    if (!mounted) return;
    final picked = await showDuetClockPicker(
      context,
      hour: _hour,
      minute: _minute,
    );
    if (picked == null) return;
    setState(() {
      _hour = picked.$1;
      _minute = picked.$2;
    });
  }

  Future<void> _pickSound() async {
    final chosen = await Navigator.of(context).push<String>(
      DuetPageRoute(builder: (_) => SoundPickerScreen(selected: _soundRef)),
    );
    if (chosen != null) {
      setState(() => _soundRef = chosen);
      await _resolveSoundTitle();
    }
  }

  Future<void> _save() async {
    // A one-shot alarm needs an explicit date, or "07:00" is ambiguous the
    // moment the time has already passed today.
    DateTime? oneShot;
    if (_repeatDays == Repeat.none) {
      final now = DateTime.now();
      var d = DateTime(now.year, now.month, now.day, _hour, _minute);
      if (!d.isAfter(now)) d = d.add(const Duration(days: 1));
      oneShot = DateTime(d.year, d.month, d.day);
    }

    final alarm = Alarm(
      id: widget.alarm?.id ?? AlarmRepository.newId(),
      hour: _hour,
      minute: _minute,
      label: _label.text.trim(),
      enabled: widget.alarm?.enabled ?? true,
      repeatDays: _repeatDays,
      oneShotDate: oneShot,
      soundRef: _soundRef,
      snoozeMinutes: _snoozeMinutes,
      maxSnoozes: _maxSnoozes,
      ringTarget: _target,
    );

    await _repo.save(alarm);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final a = widget.alarm;
    if (a == null) return;
    // The hold button has just locked into its done state (check, "Deleted",
    // sound). Give the eye the beat it needs to register that before the
    // screen vanishes -- deleting faster than you can see it is not snappy,
    // it is unreadable.
    await Future<void>.delayed(const Duration(milliseconds: 750));
    await _repo.delete(a.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _previewLine();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel', style: TextStyle(color: DuetColors.dim)),
        ),
        leadingWidth: 84,
        title: Text(_isNew ? 'New alarm' : 'Edit alarm',
            style: const TextStyle(fontSize: 16, color: DuetColors.text)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _save,
            child: Text('Save',
                style: TextStyle(
                    color: SkinColors.instance.accent, fontWeight: FontWeight.w600, fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
        children: [
          // WHO RINGS, FIRST -- before the time, because whose phone this
          // alarm wakes is the whole point of the app; the time is secondary
          // to the question of who answers it.
          const SectionLabel('Who rings'),
          const SizedBox(height: 6),
          Center(
            child: WhoRingsPicker(
              target: _target,
              onChanged: (t) => setState(() => _target = t),
            ),
          ),
          const SizedBox(height: 22),

          Column(
            children: [
              // The nudge, immediately above the time it points at.
              _timeHint(),
              // The time itself opens the clock dial -- the steppers are for
              // nudging, the dial is for seeing.
              InkWell(
                onTap: _openClock,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                            fontSize: 74,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 2,
                            color: DuetColors.text,
                            fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                      const SizedBox(width: 8),
                      const Padding(
                        padding: EdgeInsets.only(top: 14),
                        child: HeartAccent(size: 18),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              _timeSteppers(),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(preview,
                style: const TextStyle(fontSize: 13.5, color: DuetColors.dim)),
          ),
          const SizedBox(height: 22),

          _dayPills(),
          const SizedBox(height: 18),

          DuetCard(
            child: Row(children: [
              const SizedBox(
                  width: 66,
                  child: Text('Label',
                      style: TextStyle(color: DuetColors.dim, fontSize: 15))),
              Expanded(
                child: TextField(
                  controller: _label,
                  style: const TextStyle(color: DuetColors.text, fontSize: 16),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Gym, flight, wake Sam gently…',
                    hintStyle: TextStyle(color: DuetColors.faint, fontSize: 15),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 18),

          const SectionLabel('Sound'),
          const SizedBox(height: 10),
          // No CrossAxisAlignment.stretch here: a stretched Row needs a
          // bounded height and a ListView's is infinite -- the first build
          // of this threw and took the whole viewport blank with it. The
          // cards are structurally identical, so their natural heights match.
          Row(
            children: [
              Expanded(
                child: _soundCard(
                  title: 'You will hear',
                  value: _soundTitle,
                  active: true,
                  onTap: _pickSound,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _soundCard(title: 'They will hear', value: 'Once you pair'),
              ),
            ],
          ),
          const SizedBox(height: 18),

          const SizedBox(height: 18),

          const SectionLabel('Snooze'),
          const SizedBox(height: 10),
          _snoozeRow(),

          if (!_isNew) ...[
            const SizedBox(height: 34),
            // Deleting a shared alarm reaches the partner's phone too -- that
            // is exactly the class of action the canvases say must be
            // press-and-hold, not a tap you can sleep-fire.
            PressAndHoldButton(
              label: 'Hold to delete',
              icon: Icons.delete_outline_rounded,
              destructive: true,
              onComplete: _delete,
            ),
          ],
        ],
      ),
    );
  }

  /// Shows exactly when it will next go off. Cheap to build, and it removes the
  /// single most common alarm-clock doubt: "did I set that for a.m. or p.m.?"
  String _previewLine() {
    final at = nextFire(
      now: DateTime.now(),
      hour: _hour,
      minute: _minute,
      repeatDays: _repeatDays,
    );
    if (at == null) return 'Will not ring';

    final left = at.difference(DateTime.now());
    final d = left.inDays, h = left.inHours % 24, m = left.inMinutes % 60;
    if (d > 0) return 'Rings in ${d}d ${h}h';
    if (h > 0) return 'Rings in ${h}h ${m}m';
    return 'Rings in ${m + 1}m';
  }

  Widget _dayPills() {
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        final bit = 1 << i;
        final on = _repeatDays & bit != 0;
        return GestureDetector(
          onTap: () => setState(() => _repeatDays ^= bit),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: on ? SkinColors.instance.wash : null,
              color: on ? null : SkinColors.instance.pal.surface,
              shape: BoxShape.circle,
              border: on ? null : Border.all(color: SkinColors.instance.pal.line),
              boxShadow: on
                  ? [BoxShadow(
                      color: SkinColors.instance.accent.withValues(alpha: 0.25),
                      blurRadius: 10)]
                  : null,
            ),
            child: Text(names[i],
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: on ? DuetColors.amberInk : DuetColors.dim)),
          ),
        );
      }),
    );
  }

  /// Chevron pair + value for one segment of the hero time. Wrapping is
  /// handled by the bump functions above.
  /// "Tap the time" with an arrow bending down into it.
  ///
  /// Bobs gently rather than sitting still: a static label next to a very
  /// large number is read as a caption, not as an instruction.
  Widget _timeHint() => AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        child: !_showTimeHint
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: _Bob(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Tap the time to set it on the dial',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: SkinColors.instance.accent,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Transform.rotate(
                        angle: math.pi / 2,
                        child: Icon(Icons.subdirectory_arrow_left_rounded,
                            size: 20, color: SkinColors.instance.accent),
                      ),
                    ],
                  ),
                ),
              ),
      );

  Widget _timeSteppers() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _timeStepper(
            'HOUR',
            _hour.toString().padLeft(2, '0'),
            () => _bumpHour(1),
            () => _bumpHour(-1),
          ),
          const SizedBox(width: 20),
          _timeStepper(
            'MIN',
            _minute.toString().padLeft(2, '0'),
            () => _bumpMinute(1),
            () => _bumpMinute(-1),
          ),
        ],
      );

  Widget _timeStepper(String label, String value, VoidCallback onUp, VoidCallback onDown) =>
      Column(
        children: [
          _chevronButton(Icons.keyboard_arrow_up_rounded, onUp),
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: SkinColors.instance.pal.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: SkinColors.instance.pal.line.withValues(alpha: 0.6)),
            ),
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.8,
                    color: DuetColors.muted,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
          _chevronButton(Icons.keyboard_arrow_down_rounded, onDown),
        ],
      );

  Widget _chevronButton(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: 58,
          height: 30,
          child: Icon(icon, size: 22, color: DuetColors.dim),
        ),
      );

  /// The canvas's side-by-side sound cards. Yours is alive -- a waveform, your
  /// accent, a chevron -- and theirs is the quiet promise of the feature.
  Widget _soundCard({
    required String title,
    required String value,
    bool active = false,
    VoidCallback? onTap,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: DuetCard(
            border: active ? SkinColors.instance.accent.withValues(alpha: 0.3) : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(active ? Icons.graphic_eq : Icons.person_outline,
                      size: 14, color: active ? SkinColors.instance.accent : DuetColors.faint),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(title.toUpperCase(),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w600,
                            color: active ? DuetColors.muted : DuetColors.faint)),
                  ),
                ]),
                const SizedBox(height: 10),
                WaveformBars(count: 6, height: 16, color: active ? null : DuetColors.faint),
                const SizedBox(height: 10),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        color: active ? DuetColors.text : DuetColors.faint)),
              ],
            ),
          ),
        ),
      );

  Widget _snoozeRow() => DuetCard(
        child: Column(children: [
          Row(children: [
            const Expanded(
                child: Text('Snooze length',
                    style: TextStyle(color: DuetColors.text, fontSize: 15))),
            _stepper(
              value: '$_snoozeMinutes min',
              onLess: _snoozeMinutes > 1
                  ? () => setState(() => _snoozeMinutes -= 1)
                  : null,
              onMore: _snoozeMinutes < 30
                  ? () => setState(() => _snoozeMinutes += 1)
                  : null,
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Expanded(
                child: Text('Times allowed',
                    style: TextStyle(color: DuetColors.text, fontSize: 15))),
            _stepper(
              value: _maxSnoozes == 0 ? 'Never' : '$_maxSnoozes×',
              onLess:
                  _maxSnoozes > 0 ? () => setState(() => _maxSnoozes -= 1) : null,
              onMore:
                  _maxSnoozes < 9 ? () => setState(() => _maxSnoozes += 1) : null,
            ),
          ]),
        ]),
      );

  Widget _stepper({
    required String value,
    VoidCallback? onLess,
    VoidCallback? onMore,
  }) =>
      Row(children: [
        _stepButton(Icons.remove, onLess),
        SizedBox(
          width: 66,
          child: Text(value,
              textAlign: TextAlign.center,
              style: const TextStyle(color: DuetColors.muted, fontSize: 14.5)),
        ),
        _stepButton(Icons.add, onMore),
      ]);

  Widget _stepButton(IconData icon, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(icon,
              size: 18,
              color: onTap == null ? DuetColors.faint : SkinColors.instance.accent),
        ),
      );
}

/// The graphical who-rings selector: one circle, two halves. Tapping a half
/// toggles that person in or out of the alarm, so "both of us" is simply the
/// state where both halves are lit. The last lit side never goes dark -- an
/// alarm that rings for nobody is not an alarm. On every change the lit
/// fill sweeps in animated, the way the home dial wears it, and the
/// excluded side goes quiet.
class WhoRingsPicker extends StatelessWidget {
  const WhoRingsPicker({super.key, required this.target, required this.onChanged});

  final RingTarget target;
  final ValueChanged<RingTarget> onChanged;

  static const _size = 190.0;

  void _pick(Offset local) {
    final dx = local.dx - _size / 2;
    // Right half toggles you, left half toggles them. Turning off the only
    // lit side is refused: the alarm must keep at least one ringer.
    final RingTarget next;
    if (dx >= 0) {
      next = switch (target) {
        RingTarget.both => RingTarget.partner,
        RingTarget.owner => RingTarget.owner,
        RingTarget.partner => RingTarget.both,
      };
    } else {
      next = switch (target) {
        RingTarget.both => RingTarget.owner,
        RingTarget.owner => RingTarget.both,
        RingTarget.partner => RingTarget.partner,
      };
    }
    if (next != target) onChanged(next);
  }

  @override
  Widget build(BuildContext context) => SkinBuilder(
        builder: (context, skins) => Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _pick(d.localPosition),
              child: TweenAnimationBuilder<double>(
                key: ValueKey(target),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 550),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => SizedBox(
                  width: _size,
                  height: _size,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(_size, _size),
                        painter: _WhoRingsPainter(
                          target: target,
                          progress: t,
                          mine: skins.mine,
                          partner: skins.partner,
                          line: skins.pal.line,
                        ),
                      ),
                      // Whose side is whose: your glyph rides the right
                      // edge, theirs the left, each scaling away when the
                      // selection excludes them.
                      Positioned(
                        left: 2,
                        child: _sideBadge(
                          skins.partnerSkin?.icon ?? Icons.favorite_rounded,
                          skins.partner,
                          included: target != RingTarget.owner,
                          t: t,
                        ),
                      ),
                      Positioned(
                        right: 2,
                        child: _sideBadge(
                          skins.mineSkin.icon,
                          skins.mine,
                          included: target != RingTarget.partner,
                          t: t,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                target.label,
                key: ValueKey(target.label),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: DuetColors.text),
              ),
            ),
          ],
        ),
      );

  Widget _sideBadge(IconData icon, Color color,
          {required bool included, required double t}) =>
      Transform.scale(
        scale: included ? 1 : 0.6 + 0.4 * (1 - t),
        child: Opacity(
          opacity: included ? 1 : 0.25,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DuetColors.bgDeep.withValues(alpha: 0.9),
              border: Border.all(color: color, width: 1.4),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      );
}

class _WhoRingsPainter extends CustomPainter {
  _WhoRingsPainter({
    required this.target,
    required this.progress,
    required this.mine,
    required this.partner,
    required this.line,
  });

  final RingTarget target;
  final double progress;
  final Color mine;
  final Color partner;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - stroke;
    final rect = Rect.fromCircle(center: c, radius: r);

    // Track.
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = line);

    final sweep = math.pi * progress;
    Paint fill(Color colour) => Paint()..color = colour.withValues(alpha: 0.16 * progress);
    Paint arc(Color colour) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = colour;

    bool mineOn, partnerOn;
    switch (target) {
      case RingTarget.both:
        mineOn = partnerOn = true;
      case RingTarget.owner:
        mineOn = true;
        partnerOn = false;
      case RingTarget.partner:
        mineOn = false;
        partnerOn = true;
    }

    // Fills sweep in as pie wedges from 12 o'clock -- the same gesture the
    // home dial's fill makes, at half a second.
    if (mineOn) {
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(rect, -math.pi / 2, sweep, false)
        ..close();
      canvas.drawPath(path, fill(mine));
      canvas.drawArc(rect, -math.pi / 2, sweep, false, arc(mine));
    }
    if (partnerOn) {
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(rect, -math.pi / 2, -sweep, false)
        ..close();
      canvas.drawPath(path, fill(partner));
      canvas.drawArc(rect, -math.pi / 2, -sweep, false, arc(partner));
    }
  }

  @override
  bool shouldRepaint(_WhoRingsPainter old) =>
      old.target != target ||
      old.progress != progress ||
      old.mine != mine ||
      old.partner != partner ||
      old.line != line;
}

/// A slow vertical bob. Used by the time hint so the arrow reads as pointing
/// at something rather than as decoration sitting above it.
class _Bob extends StatefulWidget {
  const _Bob({required this.child});

  final Widget child;

  @override
  State<_Bob> createState() => _BobState();
}

class _BobState extends State<_Bob> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, Curves.easeInOut.transform(_c.value) * 4 - 2),
          child: child,
        ),
        child: widget.child,
      );
}
