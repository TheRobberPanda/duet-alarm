import 'package:flutter/material.dart';

import 'pair_repository.dart';
import 'theme.dart';

/// The wake receipt -- post-alarm summary, the canvas's "small, celebratory,
/// quick to dismiss" artboard. Shows once after a morning you were both up
/// for; a 'Good morning' tap sends it away.
///
/// Everything it claims comes from [WakeReceiptData]; when a field is a
/// client-side approximation, the copy below does not overclaim either.
class WakeReceiptScreen extends StatelessWidget {
  const WakeReceiptScreen({
    super.key,
    required this.data,
    required this.partnerName,
  });

  final WakeReceiptData data;
  final String partnerName;

  String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 'Woke 06:14 · one snooze' -- the who and the first-up badge live on the
  /// card itself; this line only adds the facts.
  String _personLine({required int seconds, required int snoozes}) {
    final at = _clock(data.firedAt.add(Duration(seconds: seconds)));
    final snoozeBit = snoozes == 0
        ? 'no snoozes'
        : snoozes == 1
            ? 'one snooze'
            : '$snoozes snoozes';
    return 'Woke $at · $snoozeBit';
  }

  @override
  Widget build(BuildContext context) {
    return SkinBuilder(
      builder: (context, skins) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(),
                HaloGlow(
                  size: 360,
                  child: SizedBox(
                    width: 150,
                    height: 150,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PairRing(size: 150, strokeWidth: 4),
                        // The check INSIDE the ring -- the canvas's
                        // "you both made it" mark.
                        Container(
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: skins.wash,
                            boxShadow: [
                              BoxShadow(
                                color: skins.accent.withValues(alpha: 0.3),
                                blurRadius: 26,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.check_rounded,
                              size: 52, color: DuetColors.amberInk),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                // The one celebratory serif moment in the app. Italic, warm,
                // and then it is gone.
                Text(
                  "You're both up.",
                  style: DuetText.serifItalic.copyWith(
                    fontSize: 42,
                    color: DuetColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Rang ${_clock(data.firedAt)} · both phones answered',
                  style: const TextStyle(fontSize: 14, color: DuetColors.muted),
                ),
                const SizedBox(height: 30),

                _personCard(
                  title: 'You',
                  line: _personLine(seconds: data.mySeconds, snoozes: data.mySnoozes),
                  color: skins.mine,
                  first: data.iWasFirst,
                ),
                const SizedBox(height: 10),
                _personCard(
                  title: partnerName,
                  line: _personLine(
                      seconds: data.partnerSeconds, snoozes: data.partnerSnoozes),
                  color: skins.partner,
                  first: !data.iWasFirst,
                ),
                const SizedBox(height: 10),

                // Shared streak: one dot per morning, two-tone, capped so a
                // long run renders as a row of the recent ones plus a count.
                DuetCard(
                  child: Column(
                    children: [
                      Text(
                        'Together — ${data.streakDays} '
                        'morning${data.streakDays == 1 ? '' : 's'} in a row',
                        style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: DuetColors.text),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Alternating your colour and theirs -- the streak
                          // is literally the two of you.
                          for (var i = 0; i < data.streakDays.clamp(0, 14); i++)
                            Container(
                              width: 9,
                              height: 9,
                              margin: const EdgeInsets.symmetric(horizontal: 2.5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i.isEven ? skins.mine : skins.partner,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(),
                DuetButton('Good morning', icon: Icons.wb_sunny_rounded, filled: true,
                    onTap: () => Navigator.of(context).pop()),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _personCard({
    required String title,
    required String line,
    required Color color,
    required bool first,
  }) =>
      DuetCard(
        border: color.withValues(alpha: 0.3),
        child: Row(
          children: [
            AvatarBadge(
              initial: title.isEmpty ? '' : title.substring(0, 1).toUpperCase(),
              color: color,
              size: 38,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: DuetColors.text)),
                      if (first) ...[
                        const SizedBox(width: 8),
                        const DuetPill('First up', icon: Icons.emoji_events_rounded),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(line,
                      style: const TextStyle(fontSize: 12.5, color: DuetColors.dim)),
                ],
              ),
            ),
          ],
        ),
      );
}
