import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'alarm_engine.dart';
import 'pair_repository.dart';
import 'theme.dart';

/// Turns whatever Spotify put on the clipboard into a `spotify:` sound ref.
///
/// Accepts the share link (`https://open.spotify.com/track/ID?si=...`), the
/// URI (`spotify:track:ID`), and the country-prefixed link Spotify sometimes
/// produces (`.../intl-es/track/ID`). Returns null for anything else, so the
/// field can say so instead of storing a ref that will never play.
///
/// Deliberately a pure function with no network: identifying a track needs no
/// account, which is the entire reason Duet asks for a pasted link instead of
/// running an OAuth flow.
String? spotifyRefFromInput(String raw) {
  final input = raw.trim();
  if (input.isEmpty) return null;

  final uri = RegExp(r'^spotify:(track|playlist|album|episode|show):([A-Za-z0-9]+)')
      .firstMatch(input);
  if (uri != null) return 'spotify:${uri.group(1)}:${uri.group(2)}';

  final link = RegExp(
    r'open\.spotify\.com/(?:intl-[a-z]{2}/)?(track|playlist|album|episode|show)/([A-Za-z0-9]+)',
  ).firstMatch(input);
  if (link != null) return 'spotify:${link.group(1)}:${link.group(2)}';

  return null;
}

/// 'Spotify track' / 'Spotify playlist' -- what a stored ref should be called
/// in a list of tones.
String spotifyRefTitle(String ref) {
  final kind = ref.split(':').length > 1 ? ref.split(':')[1] : 'track';
  return 'Spotify ${kind == 'show' ? 'podcast' : kind}';
}

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

  final _spotifyInput = TextEditingController();
  String? _spotifyError;

  bool get _spotifyChosen => _selected.startsWith('spotify:');

  @override
  void initState() {
    super.initState();
    _selected = widget.selected;
    _load();
  }

  @override
  void dispose() {
    _spotifyInput.dispose();
    AlarmEngine.stopPreview();
    super.dispose();
  }

  Future<void> _pasteSpotify() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    _spotifyInput.text = data?.text?.trim() ?? '';
    _applySpotify();
  }

  void _applySpotify() {
    final ref = spotifyRefFromInput(_spotifyInput.text);
    setState(() {
      if (ref == null) {
        _spotifyError = _spotifyInput.text.trim().isEmpty
            ? null
            : "That does not look like a Spotify link.";
      } else {
        _spotifyError = null;
        _selected = ref;
        _playing = null;
      }
    });
    if (ref != null) AlarmEngine.stopPreview();
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
                _spotifyCard(),
                const SizedBox(height: 14),
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
                          Text('Wake ${PairRepository.lastKnownPartner?.them ?? 'them'} up as you',
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

  /// Wake up to a song -- with the tone underneath it, always.
  ///
  /// No sign-in: pasting a link identifies a track without an account, so the
  /// only thing Duet ever needs is the URI. The copy is blunt about the
  /// fallback because the failure modes are real and invisible (no Premium, no
  /// signal, signed out on the phone) and someone choosing this should know
  /// what they will actually hear on a bad morning.
  Widget _spotifyCard() {
    final accent = SkinColors.instance.accent;
    return DuetCard(
      border: _spotifyChosen ? accent.withValues(alpha: 0.5) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.14),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: const Icon(Icons.library_music_outlined,
                  size: 18, color: DuetColors.muted),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Text('Wake up to a song',
                  style: TextStyle(
                      color: DuetColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
            ),
            if (_spotifyChosen)
              Icon(Icons.favorite_rounded, size: 17, color: accent),
          ]),
          const SizedBox(height: 10),
          const Text(
            'Paste a Spotify link. The alarm tone still starts first and only '
            'goes quiet once Spotify is actually playing, so a morning with no '
            'signal, no Premium or Spotify signed out still wakes you.',
            style: TextStyle(fontSize: 12.5, color: DuetColors.dim, height: 1.45),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _spotifyInput,
                onChanged: (_) => _applySpotify(),
                style: const TextStyle(fontSize: 14, color: DuetColors.text),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'open.spotify.com/track/...',
                  hintStyle: const TextStyle(fontSize: 13.5, color: DuetColors.dim),
                  errorText: _spotifyError,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Paste',
              onPressed: _pasteSpotify,
              icon: Icon(Icons.content_paste_rounded, size: 20, color: accent),
            ),
          ]),
          if (_spotifyChosen) ...[
            const SizedBox(height: 8),
            Text('Chosen: ${spotifyRefTitle(_selected)}',
                style: TextStyle(fontSize: 12.5, color: accent)),
          ],
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
              color: chosen ? SkinColors.instance.pal.surfaceRaised : SkinColors.instance.pal.surface,
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
