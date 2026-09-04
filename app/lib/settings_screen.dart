import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: DuetColors.surfaceRaised,
          title: Text(title, style: const TextStyle(color: DuetColors.text)),
          content: Text(body,
              style: const TextStyle(color: DuetColors.muted, height: 1.4)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: DuetColors.dim)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel,
                  style: TextStyle(color: danger ? DuetColors.danger : DuetColors.amber)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: DuetColors.amber)),
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
          child: ListView(
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
                    const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: DuetColors.amber),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.check, color: DuetColors.amber, size: 20),
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
                  PairRing(size: 30, strokeWidth: 2, hasPartner: paired),
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
                    Switch(
                      value: allowPartnerDismiss,
                      activeThumbColor: DuetColors.amberInk,
                      activeTrackColor: DuetColors.amber,
                      inactiveThumbColor: const Color(0xFF5A4C50),
                      inactiveTrackColor: const Color(0xFF2E2129),
                      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                      thumbIcon: WidgetStateProperty.resolveWith((states) =>
                          states.contains(WidgetState.selected)
                              ? const Icon(Icons.favorite_rounded,
                                  size: 14, color: DuetColors.amber)
                              : null),
                      onChanged: _setAllowPartnerDismiss,
                    ),
                  ]),
                ),
              ],

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
        ),
      ),
    );
  }
}
