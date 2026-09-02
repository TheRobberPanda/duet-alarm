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

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: DuetColors.amber,
            onPrimary: DuetColors.amberInk,
            surface: DuetColors.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() { _hour = picked.hour; _minute = picked.minute; });
    }
  }

  Future<void> _pickSound() async {
    final chosen = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => SoundPickerScreen(selected: _soundRef)),
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
            child: const Text('Save',
                style: TextStyle(
                    color: DuetColors.amber, fontWeight: FontWeight.w600, fontSize: 16)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
        children: [
          Center(
            child: InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Text(
                  '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      fontSize: 74,
                      fontWeight: FontWeight.w200,
                      letterSpacing: 2,
                      color: DuetColors.text),
                ),
              ),
            ),
          ),
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
          _tappableRow(
            icon: Icons.graphic_eq,
            title: 'You will hear',
            value: _soundTitle,
            onTap: _pickSound,
          ),
          const SizedBox(height: 8),
          Opacity(
            opacity: 0.45,
            child: _tappableRow(
              icon: Icons.person_outline,
              title: 'They will hear',
              value: 'Once you pair',
              onTap: null,
            ),
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
            const SizedBox(height: 30),
            TextButton(
              onPressed: _delete,
              child: const Text('Delete this alarm',
                  style: TextStyle(color: DuetColors.danger, fontSize: 15)),
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
          child: Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? DuetColors.amber : DuetColors.surface,
              shape: BoxShape.circle,
              border: on ? null : Border.all(color: DuetColors.line),
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

  Widget _tappableRow({
    required IconData icon,
    required String title,
    required String value,
    VoidCallback? onTap,
  }) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: DuetCard(
            child: Row(children: [
              Icon(icon, size: 19, color: DuetColors.dim),
              const SizedBox(width: 13),
              Expanded(
                  child: Text(title,
                      style: const TextStyle(color: DuetColors.text, fontSize: 15))),
              Text(value,
                  style: const TextStyle(color: DuetColors.muted, fontSize: 14.5)),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, size: 18, color: DuetColors.faint),
              ],
            ]),
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
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? const Color(0xFF342B25) : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(t.label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                          color: on ? DuetColors.text : DuetColors.dim)),
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
              color: onTap == null ? DuetColors.faint : DuetColors.amber),
        ),
      );
}
