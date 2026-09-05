import 'package:flutter/material.dart';

import 'alarm_engine.dart';
import 'theme.dart';

/// Pick from the sounds already on this phone.
///
/// Tapping a row previews it on the ALARM stream — the same stream the real
/// alarm uses — so what you hear here is what you get at 06:00. Previewing on
/// the media stream would let someone choose a tone that turns out to be
/// inaudible.
class SoundPickerScreen extends StatefulWidget {
  const SoundPickerScreen({super.key, required this.selected});

  final String selected;

  @override
  State<SoundPickerScreen> createState() => _SoundPickerScreenState();
}

class _SoundPickerScreenState extends State<SoundPickerScreen> {
  List<DeviceSound> _sounds = [];
  late String _selected;
  String? _playing;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selected = widget.selected;
    _load();
  }

  @override
  void dispose() {
    AlarmEngine.stopPreview();
    super.dispose();
  }

  Future<void> _load() async {
    final sounds = await AlarmEngine.listSounds();
    if (mounted) setState(() { _sounds = sounds; _loading = false; });
  }

  Future<void> _tap(DeviceSound s) async {
    setState(() { _selected = s.ref; _playing = s.ref; });
    await AlarmEngine.previewSound(s.ref);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: DuetColors.muted),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sound', style: TextStyle(fontSize: 17, color: DuetColors.text)),
            SizedBox(width: 7),
            HeartAccent(size: 14),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              AlarmEngine.stopPreview();
              Navigator.of(context).pop(_selected);
            },
            child: Text('Done',
                style: TextStyle(
                    color: SkinColors.instance.accent, fontWeight: FontWeight.w600, fontSize: 16)),
          ),
        ],
      ),
      body: _loading
          ? Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Column(
                children: [
                  for (var i = 0; i < 6; i++) ...[
                    const Skeleton(height: 52, radius: 15),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
              children: [
                const Text(
                  'These are the alarm tones already on your phone. '
                  'Tap one to hear it at alarm volume.',
                  style: TextStyle(fontSize: 13.5, color: DuetColors.dim, height: 1.45),
                ),
                const SizedBox(height: 18),
                ..._sounds.map(_row),
                const SizedBox(height: 26),
                DuetCard(
                  child: Row(children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: SkinColors.instance.accent.withValues(alpha: 0.14),
                        border: Border.all(
                            color: SkinColors.instance.accent.withValues(alpha: 0.35)),
                      ),
                      child: const Icon(Icons.mic_none,
                          size: 18, color: DuetColors.muted),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Record your own voice',
                              style: TextStyle(
                                  color: DuetColors.muted,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(height: 2),
                          Text('Wake them up as you',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: SkinColors.instance.accent.withValues(alpha: 0.8))),
                        ],
                      ),
                    ),
                    DuetPill('Later', icon: Icons.lock_rounded),
                  ]),
                ),
              ],
            ),
    );
  }

  Widget _row(DeviceSound s) {
    final chosen = s.ref == _selected;
    final playing = _playing == s.ref;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () => _tap(s),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: chosen ? DuetColors.surfaceRaised : DuetColors.surface,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                  color: chosen
                      ? SkinColors.instance.accent
                      : Colors.transparent,
                  width: 1.4),
              // Skin-aware: the glow used to be hard-coded to the old pink
              // and ignored whichever skin you had picked.
              boxShadow: chosen
                  ? [
                      BoxShadow(
                        color: SkinColors.instance.accent.withValues(alpha: 0.19),
                        blurRadius: 14,
                      )
                    ]
                  : null,
            ),
            child: Row(children: [
              Icon(
                playing ? Icons.graphic_eq : Icons.play_arrow_rounded,
                size: 20,
                color: chosen ? SkinColors.instance.accent : DuetColors.dim,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  s.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15.5,
                      color: chosen ? DuetColors.text : DuetColors.muted),
                ),
              ),
              // A little equalizer on every row: dancing while its sound
              // plays, a still silhouette otherwise.
              WaveformBars(playing: playing, count: 5, height: 14),
              const SizedBox(width: 10),
              if (chosen)
                Icon(Icons.favorite_rounded,
                    size: 17, color: SkinColors.instance.accent),
            ]),
          ),
        ),
      ),
    );
  }
}
