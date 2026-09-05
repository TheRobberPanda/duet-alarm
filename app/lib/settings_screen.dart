import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'alarm_engine.dart';
import 'pair_repository.dart';
import 'theme.dart';

/// Account and pairing preferences.
///
/// Docs/08 flagged this as missing: `allow_partner_dismiss` and the profile
/// have had a working backend and RPCs since Milestone 2, but no screen to
/// reach them from inside the standalone app. Deliberately thin, same as
/// [PairRepository] itself -- every toggle here just calls the repository and
/// trusts the database's rules, never re-implements them.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.onSignedOut});

  /// Pops the whole authenticated stack back to sign-in. Passed in rather than
  /// assumed, because what "signed out" means depends on what's above this
  /// screen (docs/06's AuthGate/PairGate rebuild on the auth stream either way,
  /// but a screen should not reach up through the tree to make that happen).
  final VoidCallback onSignedOut;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _repo = PairRepository.instance();
  final _nameInput = TextEditingController();

  Profile? _profile;
  PairState? _pair;
  bool _loading = true;
  bool _savingName = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameInput.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await _repo.myProfile();
    final pair = await _repo.currentPair();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _pair = pair;
      _nameInput.text = profile?.displayName ?? '';
      _loading = false;
    });
  }

  Future<void> _saveName() async {
    final name = _nameInput.text.trim();
    if (_profile == null || name == _profile!.displayName) return;
    setState(() => _savingName = true);
    try {
      await _repo.updateDisplayName(name);
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
    await _load();
  }

  Future<void> _setAllowPartnerDismiss(bool allow) async {
    // Optimistic, then reconciled from the server -- the toggle is the whole
    // point of this screen and must never look like it did nothing.
    setState(() => _profile = _profile == null
        ? null
        : Profile(
            id: _profile!.id,
            displayName: _profile!.displayName,
            timezone: _profile!.timezone,
            allowPartnerDismiss: allow,
            accent: _profile!.accent,
          ));
    await _repo.setAllowPartnerDismiss(allow);
    await _load();
  }

  Future<void> _setAccent(String skinId) async {
    // Instant locally -- SkinColors is what every PairRing actually reads,
    // and this screen shouldn't feel like it's waiting on the network to
    // show you your own choice.
    SkinColors.instance.setSkins(mine: skinId, partner: null);
    // Keep the native ringing screen in step with the choice just made.
    AlarmEngine.setSkinColors(
      SkinColors.instance.mine.toARGB32(),
      SkinColors.instance.partner.toARGB32(),
    );
    setState(() => _profile = _profile == null
        ? null
        : Profile(
            id: _profile!.id,
            displayName: _profile!.displayName,
            timezone: _profile!.timezone,
            allowPartnerDismiss: _profile!.allowPartnerDismiss,
            accent: skinId,
          ));
    await _repo.updateAccent(skinId);
    await _load();
  }

  Future<void> _leavePair() async {
    final ok = await _confirm(
      title: 'Leave this pair?',
      body: 'Your alarms stay on this phone, but they stop being shared. '
          '${_pair?.partner?.shortName ?? 'Your partner'} keeps theirs too -- '
          'nothing on their phone changes.',
      confirmLabel: 'Leave pair',
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _repo.leavePair();
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await _repo.signOut();
    widget.onSignedOut();
  }

  Future<void> _deleteAccount() async {
    final ok = await _confirm(
      title: 'Delete your account?',
      body: 'This dissolves your pair first, then permanently deletes your '
          'account and every alarm tied to it. This cannot be undone.',
      confirmLabel: 'Delete account',
      danger: true,
    );
    if (ok != true) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _repo.deleteAccount();
      widget.onSignedOut();
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    bool danger = false,
  }) =>
      showDuetDialog<bool>(
        context: context,
        title: title,
        body: body,
        actions: [
          DuetDialogAction('Cancel', onPressed: () => Navigator.of(context).pop(false)),
          DuetDialogAction(
            confirmLabel,
            destructive: danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 92, height: 26, radius: 8),
                SizedBox(height: 22),
                Skeleton(height: 72, radius: 20),
                SizedBox(height: 16),
                Skeleton(height: 72, radius: 20),
                SizedBox(height: 28),
                Skeleton(width: 110, height: 26, radius: 8),
                SizedBox(height: 16),
                Skeleton(height: 120, radius: 20),
              ],
            ),
          ),
        ),
      );
    }

    final email = _repo.currentUser?.email ?? '';
    final allowPartnerDismiss = _profile?.allowPartnerDismiss ?? true;
    final paired = _pair != null && _pair!.isComplete;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Settings', style: TextStyle(color: DuetColors.text)),
        iconTheme: const IconThemeData(color: DuetColors.text),
      ),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _busy,
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                children: [
                  const SectionLabel('Your name'),
              const SizedBox(height: 10),
              DuetCard(
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _nameInput,
                      style: const TextStyle(color: DuetColors.text, fontSize: 16),
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'What should they see you as?',
                        hintStyle: TextStyle(color: DuetColors.faint),
                      ),
                      onSubmitted: (_) => _saveName(),
                    ),
                  ),
                  if (_savingName)
                    SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: SkinColors.instance.accent),
                    )
                  else
                    IconButton(
                      icon: Icon(Icons.check, color: SkinColors.instance.accent, size: 20),
                      onPressed: _saveName,
                      tooltip: 'Save',
                    ),
                ]),
              ),
              const SizedBox(height: 6),
              Text(email,
                  style: const TextStyle(fontSize: 12.5, color: DuetColors.faint)),

              const SizedBox(height: 28),
              const SectionLabel('Partner'),
              const SizedBox(height: 10),
              DuetCard(
                child: Row(children: [
                  PairRing(size: 40, strokeWidth: 2.5, hasPartner: paired),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      paired
                          ? 'Paired with ${_pair!.partner!.shortName}'
                          : 'Not paired yet',
                      style: const TextStyle(fontSize: 14.5, color: DuetColors.text),
                    ),
                  ),
                  if (paired)
                    TextButton(
                      onPressed: _leavePair,
                      child: const Text('Leave',
                          style: TextStyle(color: DuetColors.danger, fontSize: 13.5)),
                    ),
                ]),
              ),

              if (paired) ...[
                const SizedBox(height: 10),
                DuetCard(
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Let them dismiss for me',
                              style: TextStyle(fontSize: 14.5, color: DuetColors.text)),
                          const SizedBox(height: 4),
                          Text(
                            allowPartnerDismiss
                                ? '${_pair!.partner!.shortName} can snooze or dismiss '
                                    'your alarm from their phone.'
                                : 'Only you can stop your alarm, even when '
                                    '${_pair!.partner!.shortName} is already up.',
                            style: const TextStyle(
                                fontSize: 12.5, color: DuetColors.dim, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    DuetSwitch(
                      value: allowPartnerDismiss,
                      onChanged: _setAllowPartnerDismiss,
                    ),
                  ]),
                ),
              ],

              const SizedBox(height: 28),
              const SectionLabel('Your theme'),
              const SizedBox(height: 10),
              DuetCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: duetSkins.map((skin) {
                    final on = (_profile?.accent ?? 'teal') == skin.id;
                    return GestureDetector(
                      onTap: () => _setAccent(skin.id),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: on
                                  ? Border.all(color: skin.color, width: 1.6)
                                  : null,
                              boxShadow: on
                                  ? [BoxShadow(color: skin.color.withValues(alpha: 0.35), blurRadius: 16)]
                                  : null,
                            ),
                            child: _SkinPreview(skin: skin, selected: on),
                          ),
                          const SizedBox(height: 6),
                          Text(skin.label,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                                  color: on ? DuetColors.text : DuetColors.dim)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your half of the ring, everywhere it shows up -- theirs too, '
                'once they pick one.',
                style: TextStyle(fontSize: 12, color: DuetColors.faint, height: 1.4),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                DuetCard(
                  border: DuetColors.danger,
                  child: Text(_error!,
                      style: const TextStyle(color: DuetColors.danger, fontSize: 13.5)),
                ),
              ],

              const SizedBox(height: 36),
              Center(
                child: TextButton(
                  onPressed: _signOut,
                  child: const Text('Sign out',
                      style: TextStyle(color: DuetColors.dim, fontSize: 14.5)),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : _deleteAccount,
                  child: Text(
                    _busy ? 'Working…' : 'Delete account',
                    style: const TextStyle(color: DuetColors.danger, fontSize: 13.5),
                  ),
                ),
              ),
                ],
              ),
              if (_busy)
                // Busy veil: taps are absorbed by the [AbsorbPointer] above,
                // and the veil makes that visible instead of the screen
                // silently eating touches.
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: 1,
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      color: DuetColors.bgDeep.withValues(alpha: 0.45),
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(color: DuetColors.amber),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A miniature two-tone ring painted with THIS skin as your half and the
/// classic partner pink as theirs -- so picking a theme previews what your
/// half of the ring will look like everywhere, instead of showing an abstract
/// colour dot. The skin's own glyph rides inside when selected.
class _SkinPreview extends StatelessWidget {
  const _SkinPreview({required this.skin, required this.selected});

  final DuetSkin skin;
  final bool selected;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(48, 48),
              painter: _SkinPreviewPainter(
                mine: skin.color,
                partner: DuetColors.amber,
              ),
            ),
            AnimatedSkinIcon(
              skin: skin,
              size: 18,
              color: selected
                  ? skin.color
                  : DuetColors.text.withValues(alpha: 0.55),
            ),
          ],
        ),
      );
}

class _SkinPreviewPainter extends CustomPainter {
  _SkinPreviewPainter({required this.mine, required this.partner});

  final Color mine;
  final Color partner;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: c, radius: size.width / 2 - 2);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = DuetColors.line;
    canvas.drawCircle(c, rect.width / 2, track);

    final minePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = mine;
    canvas.drawArc(rect, -1.5708, 3.1416, false, minePaint);

    final partnerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = partner.withValues(alpha: 0.55);
    canvas.drawArc(rect, 1.5708, 3.1416, false, partnerPaint);
  }

  @override
  bool shouldRepaint(_SkinPreviewPainter old) => old.mine != mine || old.partner != partner;
}
