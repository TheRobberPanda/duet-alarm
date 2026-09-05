import 'package:flutter/material.dart';

import 'alarm.dart';
import 'alarm_engine.dart';
import 'alarm_repository.dart';
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
  // middle of an otherwise bespoke screen, and the canvases specify the hero
  // time edited right where it stands. Hour and minute each get a chevron
  // pair; both wrap (23 -> 0, 59 -> 0).
  void _bumpHour(int delta) => setState(() => _hour = (_hour + delta + 24) % 24);

  void _bumpMinute(int delta) => setState(() => _minute = (_minute + delta + 60) % 60);

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
          Column(
            children: [
              Row(
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

          const SectionLabel('Who rings'),
          const SizedBox(height: 10),
          _targetSelector(),
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
              color: on ? null : DuetColors.surface,
              shape: BoxShape.circle,
              border: on ? null : Border.all(color: DuetColors.line),
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
              color: DuetColors.surface.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: DuetColors.line.withValues(alpha: 0.6)),
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

  Widget _targetSelector() => Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: DuetColors.surface,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: RingTarget.values.map((t) {
            final on = t == _target;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _target = t),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: on ? SkinColors.instance.wash : null,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(t.label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                          color: on ? DuetColors.amberInk : DuetColors.dim)),
                ),
              ),
            );
          }).toList(),
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
