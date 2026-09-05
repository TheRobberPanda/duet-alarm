import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alarm.dart';
import 'alarm_editor_screen.dart';
import 'alarm_repository.dart';
import 'diagnostics_screen.dart';
import 'main.dart' show kBackendEnabled;
import 'pair_repository.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'wake_receipt_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.partnerName, this.partnerTimezone, this.onInvite});

  /// Null while solo -- either not signed in, or not yet paired.
  final String? partnerName;

  /// The partner's IANA zone from their profile ('Europe/Lisbon'). The strip
  /// shows the city so you can picture where they are waking up; computing
  /// their actual local time would need a tz database in the app, which is a
  /// heavy dependency for one label.
  final String? partnerTimezone;

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

      // The wake receipt: shown once per ring, then never again. Marking seen
      // on POP -- if the app dies mid-viewing, showing it again is the lesser
      // wrong versus never showing it.
      try {
        final receipt = await PairRepository.instance().latestWake();
        if (receipt != null && mounted) {
          final prefs = await SharedPreferences.getInstance();
          final seenKey = 'receipt_seen_${receipt.sessionId}';
          if (!prefs.containsKey(seenKey)) {
            await prefs.setBool(seenKey, true);
            if (mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                Navigator.of(context).push(
                  DuetPageRoute(
                    builder: (_) => WakeReceiptScreen(
                      data: receipt,
                      partnerName: widget.partnerName!,
                    ),
                  ),
                );
              });
            }
          }
        }
      } catch (_) {
        // A receipt that fails to load is a missing bonus, not an error the
        // home screen should wear.
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

  /// 'Europe/Lisbon' -> 'Lisbon'; 'UTC' stays 'UTC'. Best effort -- the strip
  /// label is a whisper, not data you set your day by.
  String? get _partnerCity {
    final tz = widget.partnerTimezone;
    if (tz == null || !tz.contains('/')) return null;
    return tz.split('/').last.replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      // A skeleton that mirrors the real layout, so the screen arrives in
      // place instead of a spinner being swapped for content.
      return const Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 24, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Skeleton(width: 88, height: 30, radius: 9),
                  Spacer(),
                  Skeleton(width: 42, height: 42, radius: 21),
                  SizedBox(width: 10),
                  Skeleton(width: 42, height: 42, radius: 21),
                ]),
                SizedBox(height: 44),
                Center(child: Skeleton(width: 268, height: 268, radius: 134)),
                SizedBox(height: 30),
                Center(child: Skeleton(width: 120, height: 18, radius: 9)),
              ],
            ),
          ),
        ),
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
          color: SkinColors.instance.accent,
          backgroundColor: DuetColors.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Duet',
                            style: TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                                color: DuetColors.text)),
                        SizedBox(width: 8),
                        HeartAccent(size: 15),
                      ],
                    ),
                  ),
                  if (kBackendEnabled) _headerButton(Icons.settings_outlined, 'Settings', () {
                    Navigator.of(context).push(
                      DuetPageRoute(
                        builder: (_) => SettingsScreen(
                          onSignedOut: () => Navigator.of(context)
                              .popUntil((route) => route.isFirst),
                        ),
                      ),
                    );
                  }),
                  _headerButton(Icons.health_and_safety_outlined, 'Alarm health', () {
                    Navigator.of(context).push(
                      DuetPageRoute(builder: (_) => const DiagnosticsScreen()),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 14),

              // The partner awareness strip -- the canvas's standing header:
              // the two of you overlapped, their city, and whether the line
              // to them is healthy. Solo screens simply do not get one.
              if (widget.partnerName != null) ...[
                _partnerStrip(),
                const SizedBox(height: 16),
              ],

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

              if (_repo.sync != null && !_repo.lastSyncOk) ...[
                DuetCard(
                  border: DuetColors.danger.withValues(alpha: 0.45),
                  color: DuetColors.surface,
                  child: Row(children: [
                    const Icon(Icons.cloud_off_outlined,
                        color: DuetColors.danger, size: 20),
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

              if (next != null) ...[
                FadeSlideIn(
                  key: ValueKey('next-${next.alarm.id}'),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => _edit(next.alarm),
                      child: _dial(next.alarm, next.at),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (next == null && alarms.isNotEmpty) ...[
                DuetCard(
                  child: Text(
                    // Two different situations, and saying the wrong one is a
                    // lie about whether anything will ring: every switch off,
                    // versus switches on but nothing left to fire (a one-shot
                    // whose day has passed).
                    alarms.any((a) => a.enabled)
                        ? 'Nothing coming up. The alarms that are on have already passed.'
                        : 'Every alarm is switched off.',
                    style: const TextStyle(color: DuetColors.dim, fontSize: 14.5, height: 1.4),
                  ),
                ),
                const SizedBox(height: 14),
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

              if (widget.partnerName != null) ...[
                const SizedBox(height: 18),
                Builder(builder: (context) {
                  final tips = _tips();
                  final tip = tips[_tipIndex % tips.length];
                  return DuetCard(
                    child: Row(children: [
                      Icon(Icons.auto_awesome, size: 15, color: SkinColors.instance.accent),
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
              ],

            ],
          ),
        ),
      ),
      // The canvas's full-width bottom CTA, not a FAB -- adding an alarm is
      // the one primary action on this screen and deserves a whole row.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(18, 8, 18, 14),
        child: DuetButton('New alarm', icon: Icons.add_rounded, filled: true, onTap: () => _edit()),
      ),
      ),
    );
  }

  /// Glass circular header action -- the stock IconButton was the last
  /// platform-styled thing on this screen.
  Widget _headerButton(IconData icon, String tooltip, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: IconButton(
          icon: Icon(icon, color: DuetColors.muted, size: 21),
          tooltip: tooltip,
          onPressed: onTap,
          style: IconButton.styleFrom(
            backgroundColor: DuetColors.surface.withValues(alpha: 0.6),
            side: BorderSide(color: DuetColors.line.withValues(alpha: 0.6)),
          ),
        ),
      );

  /// The standing "the two of you" header from the canvas: overlapping skin
  /// avatars, their city, and a live sync dot. Kept to one quiet glass row --
  /// it frames the dial below rather than competing with it.
  Widget _partnerStrip() => SkinBuilder(
        builder: (context, skins) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: DuetColors.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: DuetColors.line.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 54,
                height: 36,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      child: AvatarBadge(
                          icon: (skins.partnerSkin ?? skins.mineSkin).icon,
                          color: skins.partner,
                          size: 36),
                    ),
                    Positioned(
                      right: 0,
                      child: AvatarBadge(icon: skins.mineSkin.icon, size: 36),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('You and ${widget.partnerName}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500, color: DuetColors.text)),
                    Text(
                      _partnerCity == null
                          ? 'Alarms ring on both phones'
                          : 'Alarms ring on both phones · $_partnerCity',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: DuetColors.dim),
                    ),
                  ],
                ),
              ),
              if (kBackendEnabled && _repo.sync != null)
                DuetPill(
                  _repo.lastSyncOk ? 'Synced' : 'Offline',
                  dot: true,
                  color: _repo.lastSyncOk ? DuetColors.success : DuetColors.danger,
                ),
            ],
          ),
        ),
      );

  /// THE DIAL -- the screen's hero and the app's signature.
  ///
  /// The ring was already the one element carrying real information (two
  /// halves, each lit only if that person has this alarm on) and it was sitting
  /// in the corner of a card as decoration. Here it is the object itself, with
  /// the time set inside it like a clock face, because that is what this
  /// product is: a dial the two of you share. Everything below it is
  /// deliberately quieter so this reads first.
  Widget _dial(Alarm alarm, DateTime at) {
    final subtitle = alarm.label.isEmpty
        ? alarm.scheduleLabel
        : '${alarm.label} · ${alarm.scheduleLabel}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          HaloGlow(
            size: 430,
            child: SizedBox(
              width: 268,
              height: 268,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PairRing(
                    size: 268,
                    strokeWidth: 5,
                    mineOn: alarm.enabled,
                    hasPartner: alarm.partnerEnabled &&
                        alarm.ringTarget != RingTarget.owner,
                    // Paired but sitting this one out -> their arc draws
                    // dashed, the canvas's "not yet" state. Owner-only rings
                    // genuinely exclude them, so no arc at all.
                    partnerExists: widget.partnerName != null &&
                        alarm.ringTarget != RingTarget.owner,
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SectionLabel('Next alarm'),
                      const SizedBox(height: 10),
                      // The one place the display face appears. Montserrat's
                      // circular counters echo the ring it sits inside.
                      Text(
                        alarm.timeLabel,
                        style: DuetText.time(58, tracking: -1.5),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 168),
                        child: Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, color: DuetColors.muted, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Rings ${_until(at)}',
            style: const TextStyle(
                fontSize: 14, color: DuetColors.dim, letterSpacing: 0.2),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => Padding(
        // Roughly optical centre of the remaining space, allowing for the FAB.
        padding: EdgeInsets.only(
            top: MediaQuery.of(context).size.height * 0.20, bottom: 40),
        child: Column(children: [
          HaloGlow(size: 220, child: PairRing(size: 88, hasPartner: false)),
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
    final on = alarm.enabled;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _edit(alarm),
          child: Opacity(
            opacity: on ? 1 : 0.5,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOut,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                // Switched-on rows catch a little of the pair gradient --
                // lit like the cards but a stop quieter, so the dial above
                // stays the hero.
                gradient: on
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [DuetColors.surfaceTop, DuetColors.surfaceBottom],
                      )
                    : null,
                color: on ? null : DuetColors.surface.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: (on ? SkinColors.instance.accent : DuetColors.line)
                      .withValues(alpha: on ? 0.14 : 0.5),
                ),
              ),
              child: Row(children: [
                PairRing(
                  size: 26,
                  strokeWidth: 2.5,
                  animate: false,
                  mineOn: on,
                  hasPartner: alarm.partnerEnabled &&
                      alarm.ringTarget != RingTarget.owner,
                  partnerExists: widget.partnerName != null &&
                      alarm.ringTarget != RingTarget.owner,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic, children: [
                        // Tabular figures: a list of times ticking between
                        // screens must never jitter.
                        Text(alarm.timeLabel,
                            style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w300,
                                letterSpacing: 0.5,
                                color: DuetColors.text,
                                fontFeatures: const [FontFeature.tabularFigures()])),
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
                        on
                            ? '${alarm.scheduleLabel}${next == null ? '' : ' · ${_until(next)}'}'
                            : 'Off',
                        style: const TextStyle(fontSize: 12.5, color: DuetColors.dim),
                      ),
                    ],
                  ),
                ),
                DuetSwitch(
                  value: on,
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
