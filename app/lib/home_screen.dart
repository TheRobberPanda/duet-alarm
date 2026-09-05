import 'dart:async';

import 'package:flutter/material.dart';

import 'alarm.dart';
import 'alarm_editor_screen.dart';
import 'alarm_repository.dart';
import 'diagnostics_screen.dart';
import 'main.dart' show kBackendEnabled;
import 'pair_repository.dart';
import 'settings_screen.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.partnerName, this.onInvite});

  /// Null while solo -- either not signed in, or not yet paired.
  final String? partnerName;

  /// Non-null only when there is no partner yet: takes them back to pairing.
  final VoidCallback? onInvite;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _repo = AlarmRepository.instance;
  Timer? _tick;
  bool _loading = true;

  // The rotating tip banner -- a game-loading-screen-style line that cycles on
  // its own timer, independent of the 30s clock tick above.
  Timer? _tipTicker;
  int _tipIndex = 0;
  int? _myDismissed;
  int? _partnerDismissed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _tipTicker = Timer.periodic(const Duration(seconds: 14), (_) {
      if (mounted) setState(() => _tipIndex++);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _tipTicker?.cancel();
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
    // Pulls remote changes and pushes local ones when signed in; a plain
    // reconcile when not. Either way the OS ends up holding the right alarms.
    await _repo.refresh();
    if (mounted) setState(() => _loading = false);

    // Only meaningful once paired -- a solo user has no one to compare with.
    if (kBackendEnabled && widget.partnerName != null) {
      final counts = await PairRepository.instance().myDismissCounts();
      if (mounted) {
        setState(() {
          _myDismissed = counts['mine'];
          _partnerDismissed = counts['partner'];
        });
      }
    }
  }

  /// Flavor lines plus, once both dismiss counts are in, a live standing --
  /// deliberately phrased like a loading-screen tip rather than a scoreboard.
  List<String> _tips() {
    final tips = <String>[
      'Tip: hold Dismiss to end the alarm for both of you at once.',
      'Tip: pick a theme in Settings -- it repaints your half of the ring '
          'everywhere it shows up.',
    ];
    final mine = _myDismissed, theirs = _partnerDismissed;
    if (mine != null && theirs != null) {
      final partner = widget.partnerName ?? 'They';
      final line = mine == theirs
          ? "You're tied with $partner: $mine dismissals each."
          : mine > theirs
              ? "You're ahead of $partner: $mine dismissals to their $theirs."
              : "$partner is ahead: $theirs dismissals to your $mine.";
      tips.insert(0, line);
    }
    return tips;
  }

  Future<void> _edit([Alarm? existing]) async {
    final saved = await Navigator.of(context).push<bool>(
      DuetPageRoute(builder: (_) => AlarmEditorScreen(alarm: existing)),
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

    // Wrapped so a skin picked over in Settings repaints this screen the
    // moment you come back, rather than whenever the next 30s tick lands.
    return SkinBuilder(
      builder: (context, skins) => Scaffold(
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Duet',
                            style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w500,
                                color: DuetColors.text)),
                        SizedBox(width: 8),
                        HeartAccent(size: 16),
                      ],
                    ),
                  ),
                  if (kBackendEnabled)
                    IconButton(
                      icon: const Icon(Icons.settings_outlined,
                          color: DuetColors.dim, size: 22),
                      tooltip: 'Settings',
                      onPressed: () => Navigator.of(context).push(
                        DuetPageRoute(
                          builder: (_) => SettingsScreen(
                            onSignedOut: () => Navigator.of(context)
                                .popUntil((route) => route.isFirst),
                          ),
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.health_and_safety_outlined,
                        color: DuetColors.dim, size: 22),
                    tooltip: 'Alarm health',
                    onPressed: () => Navigator.of(context).push(
                      DuetPageRoute(builder: (_) => const DiagnosticsScreen()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Only shown when sync was attempted AND failed. Silence here
              // would let someone believe an edit reached their partner when it
              // did not -- the alarms still ring locally, but they are not
              // shared until this clears.
              if (widget.onInvite != null) ...[
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: widget.onInvite,
                    child: DuetCard(
                      child: Row(children: [
                        const PairRing(size: 40, hasPartner: false, strokeWidth: 2.5),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'Alarms ring on your phone only until someone joins '
                            'you. Tap to invite them.',
                            style: TextStyle(
                                fontSize: 13.5,
                                color: DuetColors.muted,
                                height: 1.4),
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            size: 18, color: DuetColors.faint),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (widget.partnerName != null) ...[
                DuetCard(
                  child: Row(children: [
                    const PairRing(size: 40, strokeWidth: 2.5),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text('You and ${widget.partnerName}',
                          style: const TextStyle(
                              fontSize: 15, color: DuetColors.text)),
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
                Builder(builder: (context) {
                  final tips = _tips();
                  final tip = tips[_tipIndex % tips.length];
                  return DuetCard(
                    child: Row(children: [
                      const Icon(Icons.auto_awesome, size: 15, color: DuetColors.amber),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 320),
                          child: Text(
                            tip,
                            key: ValueKey(tip),
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontStyle: FontStyle.italic,
                                color: DuetColors.muted,
                                height: 1.35),
                          ),
                        ),
                      ),
                    ]),
                  );
                }),
                const SizedBox(height: 12),
              ],

              if (_repo.sync != null && !_repo.lastSyncOk) ...[
                DuetCard(
                  border: DuetColors.amber.withValues(alpha: 0.5),
                  child: Row(children: [
                    const Icon(Icons.cloud_off_outlined,
                        color: DuetColors.amber, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Not synced. Your alarms still ring on this phone, but '
                        'changes have not reached your partner yet.',
                        style: TextStyle(
                            color: DuetColors.text, fontSize: 13.5, height: 1.4),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
              ],

              if (next != null)
                FadeSlideIn(
                  key: ValueKey('next-${next.alarm.id}'),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => _edit(next.alarm),
                      child: _nextCard(next.alarm, next.at),
                    ),
                  ),
                ),
              if (next == null && alarms.isNotEmpty) ...[
                const DuetCard(
                  child: Text('Every alarm is switched off.',
                      style: TextStyle(color: DuetColors.dim, fontSize: 14.5)),
                ),
              ],

              if (alarms.isEmpty)
                _emptyState()
              else if (alarms.length > 1) ...[
                const SizedBox(height: 26),
                SectionLabel('All alarms (${alarms.length})'),
                const SizedBox(height: 10),
                ...alarms.asMap().entries.map((e) => FadeSlideIn(
                      key: ValueKey(e.value.id),
                      delay: Duration(milliseconds: 45 * e.key),
                      child: _alarmRow(e.value),
                    )),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          decoration: BoxDecoration(
            gradient: SkinColors.instance.wash,
            borderRadius: const BorderRadius.all(Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: SkinColors.instance.accent.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () => _edit(),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, color: DuetColors.amberInk, size: 18),
                  SizedBox(width: 9),
                  Text('New alarm',
                      style: TextStyle(
                          color: DuetColors.amberInk,
                          fontWeight: FontWeight.w600,
                          fontSize: 15.5)),
                ],
              ),
            ),
          ),
        ),
      ),
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
                PairRing(
                  size: 84,
                  mineOn: alarm.enabled,
                  hasPartner: alarm.partnerEnabled &&
                      alarm.ringTarget != RingTarget.owner,
                ),
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
        // Roughly optical centre of the remaining space, allowing for the FAB.
        padding: EdgeInsets.only(
            top: MediaQuery.of(context).size.height * 0.20, bottom: 40),
        child: Column(children: [
          const PairRing(size: 88, hasPartner: false),
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
                  mineOn: alarm.enabled,
                  hasPartner: alarm.partnerEnabled &&
                      alarm.ringTarget != RingTarget.owner,
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
                  activeTrackColor: SkinColors.instance.accent,
                  inactiveThumbColor: const Color(0xFF5A4C44),
                  inactiveTrackColor: const Color(0xFF2E2621),
                  trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                  thumbIcon: WidgetStateProperty.resolveWith((states) =>
                      states.contains(WidgetState.selected)
                          ? Icon(SkinColors.instance.mineSkin.icon,
                              size: 14, color: SkinColors.instance.accent)
                          : null),
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
