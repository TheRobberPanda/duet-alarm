import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// The plum clock. Opens over the editor when you tap the hero time: a
/// circular dial in two phases -- hours (1-12 with AM/PM pills) then minutes
/// (60 ticks, labelled every five). Tap a number or drag around the ring;
/// the centre always shows the time being built. Pops a 24h `(hour, minute)`
/// record when Done fires, or when a minute is picked.
Future<(int, int)?> showDuetClockPicker(
  BuildContext context, {
  required int hour,
  required int minute,
}) {
  return showModalBottomSheet<(int, int)>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _ClockSheet(initialHour: hour, initialMinute: minute),
  );
}

class _ClockSheet extends StatefulWidget {
  const _ClockSheet({required this.initialHour, required this.initialMinute});

  final int initialHour;
  final int initialMinute;

  @override
  State<_ClockSheet> createState() => _ClockSheetState();
}

class _ClockSheetState extends State<_ClockSheet> {
  late int _hour24;
  late int _minute;
  late bool _am;
  bool _minutePhase = false;

  @override
  void initState() {
    super.initState();
    _hour24 = widget.initialHour;
    _minute = widget.initialMinute;
    _am = widget.initialHour < 12;
  }

  int get _hour12 {
    final h = _hour24 % 12;
    return h == 0 ? 12 : h;
  }

  void _setHour12(int h12) {
    final base = h12 % 12; // 12 -> 0
    _hour24 = _am ? base : base + 12;
  }

  void _pickAngle(Offset localPosition, Size size) {
    final dx = localPosition.dx - size.width / 2;
    final dy = localPosition.dy - size.height / 2;
    // 0 degrees at 12 o'clock, clockwise.
    final deg = (math.atan2(dx, -dy) * 180 / math.pi + 360) % 360;
    if (_minutePhase) {
      final m = (deg / 6).round() % 60;
      if (m != _minute) setState(() => _minute = m);
    } else {
      final h = ((deg / 30).round() % 12);
      final h12 = h == 0 ? 12 : h;
      if (h12 != _hour12) setState(() => _setHour12(h12));
    }
  }

  void _commit() {
    Navigator.of(context).pop((_hour24, _minute));
  }

  @override
  Widget build(BuildContext context) => SkinBuilder(
        builder: (context, skins) => Padding(
          padding: const EdgeInsets.all(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0, 0.45, 1],
                colors: [
                  skins.pal.surfaceEdge,
                  skins.pal.surfaceTop,
                  skins.pal.surfaceBottom,
                ],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: skins.accent.withValues(alpha: 0.22)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SectionLabel('Set the time'),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel',
                            style: TextStyle(color: DuetColors.dim)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // The time being built, always centre stage.
                  Text(
                    '${_hour24.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}',
                    style: DuetText.time(46, tracking: 1),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: 288,
                    height: 288,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) => _pickAngle(d.localPosition, const Size(288, 288)),
                      onPanStart: (d) => _pickAngle(d.localPosition, const Size(288, 288)),
                      onPanUpdate: (d) => _pickAngle(d.localPosition, const Size(288, 288)),
                      child: AnimatedBuilder(
                        animation: skins,
                        builder: (context, _) => CustomPaint(
                          painter: _ClockDialPainter(
                            minutePhase: _minutePhase,
                            hour12: _hour12,
                            minute: _minute,
                            accent: skins.accent,
                            line: skins.pal.line,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // AM/PM live on the sheet, not the dial: a 24h clock's two
                  // rings are a puzzle; two pills are a choice.
                  if (!_minutePhase)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _amPm('AM', _am, () => setState(() {
                              _am = true;
                              _setHour12(_hour12);
                            })),
                        const SizedBox(width: 10),
                        _amPm('PM', !_am, () => setState(() {
                              _am = false;
                              _setHour12(_hour12);
                            })),
                      ],
                    )
                  else
                    Text(
                      'Drag the ring for exact minutes',
                      style: const TextStyle(fontSize: 12.5, color: DuetColors.dim),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: DuetButton(
                      _minutePhase ? 'Done' : 'Set minutes',
                      filled: true,
                      onTap: _minutePhase ? _commit : () => setState(() => _minutePhase = true),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _amPm(String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
          decoration: BoxDecoration(
            gradient: on ? SkinColors.instance.wash : null,
            color: on ? null : SkinColors.instance.pal.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: on
                    ? Colors.transparent
                    : SkinColors.instance.pal.line),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: on ? DuetColors.amberInk : DuetColors.dim)),
        ),
      );
}

class _ClockDialPainter extends CustomPainter {
  _ClockDialPainter({
    required this.minutePhase,
    required this.hour12,
    required this.minute,
    required this.accent,
    required this.line,
  });

  final bool minutePhase;
  final int hour12;
  final int minute;
  final Color accent;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 14;

    // Track.
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = line);

    // 12 at the top, 00 at the top -- both rings start at 12 o'clock and
    // step clockwise.
    final count = minutePhase ? 60 : 12;
    for (var i = 0; i < count; i++) {
      final angle = (i * (360 / count) - 90) * math.pi / 180;
      final pos = Offset(c.dx + r * math.cos(angle), c.dy + r * math.sin(angle));

      final label = minutePhase
          ? (i % 5 == 0 ? i.toString().padLeft(2, '0') : null)
          : '${i == 0 ? 12 : i}';
      if (label == null) {
        // Minor minute tick.
        canvas.drawCircle(
            pos,
            1.4,
            Paint()
              ..color = line
              ..style = PaintingStyle.stroke);
        continue;
      }

      final selected = minutePhase ? i == _minuteOf : i == _hourIndexOf;
      if (selected) {
        canvas.drawCircle(pos, 17, Paint()..color = accent);
      }

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: minutePhase ? 11.5 : 15,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? DuetColors.amberInk : DuetColors.muted,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  int get _minuteOf => minute;
  int get _hourIndexOf => hour12 % 12;

  @override
  bool shouldRepaint(_ClockDialPainter old) =>
      old.minutePhase != minutePhase ||
      old.hour12 != hour12 ||
      old.minute != minute ||
      old.accent != accent ||
      old.line != line;
}
