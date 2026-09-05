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
          ? Center(child: CircularProgressIndicator(color: SkinColors.instance.accent))
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
                    const Icon(Icons.mic_none, size: 20, color: DuetColors.dim),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Text('Record your own voice',
                          style: TextStyle(color: DuetColors.muted, fontSize: 15)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2F2519),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('LATER',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: SkinColors.instance.accent)),
                    ),
                  ]),
                ),
              ],
            ),
    );
  }

  Widget _row(DeviceSound s) {
    final chosen = s.ref == _selected;
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
                  color: chosen ? SkinColors.instance.accent : Colors.transparent, width: 1.4),
              boxShadow: chosen
                  ? const [BoxShadow(color: Color(0x30F0A8C8), blurRadius: 14)]
                  : null,
            ),
            child: Row(children: [
              Icon(
                _playing == s.ref ? Icons.graphic_eq : Icons.play_arrow,
                size: 18,
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
              if (chosen)
                Icon(Icons.favorite_rounded, size: 17, color: SkinColors.instance.accent),
            ]),
          ),
        ),
      ),
    );
  }
}
