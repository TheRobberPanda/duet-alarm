import 'dart:async';

import 'package:flutter/material.dart';

import 'alarm.dart';
import 'alarm_editor_screen.dart';
import 'alarm_repository.dart';
import 'diagnostics_screen.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _repo = AlarmRepository.instance;
  Timer? _tick;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Every foreground is a chance to correct a disagreement between what we
    // think is armed and what the OS actually holds.
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    await _repo.load();
    await _repo.reconcile();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _edit([Alarm? existing]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AlarmEditorScreen(alarm: existing)),
    );
    if (saved == true) await _load();
  }

  String _until(DateTime target) {
    final left = target.difference(DateTime.now());
    if (left.isNegative) return 'now';
    final d = left.inDays, h = left.inHours % 24, m = left.inMinutes % 60;
    if (d > 0) return 'in ${d}d ${h}h';
    if (h > 0) return 'in ${h}h ${m}m';
    if (m > 0) return 'in ${m}m';
    return 'in under a minute';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: DuetColors.amber)),
      );
    }

    final alarms = _repo.alarms;
    final next = _repo.nextUp();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: DuetColors.amber,
          backgroundColor: DuetColors.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Duet',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w500,
                            color: DuetColors.text)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.favorite_border,
                        color: DuetColors.dim, size: 22),
                    tooltip: 'Alarm health',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              if (next != null) _nextCard(next.alarm, next.at),
              if (next == null && alarms.isNotEmpty) ...[
                const DuetCard(
                  child: Text('Every alarm is switched off.',
                      style: TextStyle(color: DuetColors.dim, fontSize: 14.5)),
                ),
              ],

              if (alarms.isEmpty)
                _emptyState()
              else ...[
                const SizedBox(height: 26),
                SectionLabel('All alarms (${alarms.length})'),
                const SizedBox(height: 10),
                ...alarms.map(_alarmRow),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: DuetColors.amber,
        foregroundColor: DuetColors.amberInk,
        icon: const Icon(Icons.add),
        label: const Text('New alarm',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
      ),
    );
  }

  Widget _nextCard(Alarm alarm, DateTime at) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF251E19), Color(0xFF1C1613)],
          ),
          border: Border.all(color: DuetColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('Next alarm'),
                      const SizedBox(height: 8),
                      Text(alarm.timeLabel,
                          style: const TextStyle(
                              fontSize: 52,
                              height: 1.05,
                              fontWeight: FontWeight.w200,
                              letterSpacing: 1,
                              color: DuetColors.text)),
                      const SizedBox(height: 4),
                      Text(
                        alarm.label.isEmpty
                            ? alarm.scheduleLabel
                            : '${alarm.label} · ${alarm.scheduleLabel}',
                        style: const TextStyle(fontSize: 14.5, color: DuetColors.muted),
                      ),
                    ],
                  ),
                ),
                PairRing(size: 52, hasPartner: alarm.ringTarget != RingTarget.owner),
              ],
            ),
            const SizedBox(height: 16),
            Container(height: 1, color: const Color(0xFF2B231E)),
            const SizedBox(height: 13),
            Row(children: [
              const Icon(Icons.schedule, size: 15, color: DuetColors.dim),
              const SizedBox(width: 7),
              Text('Rings ${_until(at)}',
                  style: const TextStyle(fontSize: 13.5, color: DuetColors.muted)),
            ]),
          ],
        ),
      );

  Widget _emptyState() => Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(children: [
          const PairRing(size: 64, hasPartner: false),
          const SizedBox(height: 22),
          const Text('No alarms yet.',
              style: TextStyle(fontSize: 20, color: DuetColors.text)),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 30),
            child: Text(
              'Add one, then lock the phone and let it ring. '
              'That is the only way to trust it.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, color: DuetColors.dim, height: 1.5),
            ),
          ),
        ]),
      );

  Widget _alarmRow(Alarm alarm) {
    final next = alarm.nextFireAfter(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _edit(alarm),
          child: Opacity(
            opacity: alarm.enabled ? 1 : 0.5,
            child: DuetCard(
              child: Row(children: [
                PairRing(
                  size: 26,
                  strokeWidth: 2,
                  hasPartner: alarm.enabled && alarm.ringTarget != RingTarget.owner,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic, children: [
                        Text(alarm.timeLabel,
                            style: const TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w300,
                                letterSpacing: 0.5,
                                color: DuetColors.text)),
                        if (alarm.label.isNotEmpty) ...[
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(alarm.label,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 15, color: DuetColors.muted)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 3),
                      Text(
                        alarm.enabled
                            ? '${alarm.scheduleLabel}${next == null ? '' : ' · ${_until(next)}'}'
                            : 'Off',
                        style: const TextStyle(fontSize: 12.5, color: DuetColors.dim),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: alarm.enabled,
                  activeThumbColor: DuetColors.amberInk,
                  activeTrackColor: DuetColors.amber,
                  inactiveThumbColor: const Color(0xFF5A4C44),
                  inactiveTrackColor: const Color(0xFF2E2621),
                  trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                  onChanged: (v) async {
                    await _repo.setEnabled(alarm.id, v);
                    if (mounted) setState(() {});
                  },
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
