import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pair_repository.dart';
import 'theme.dart';

/// Pair setup.
///
/// This screen IS the growth engine: every user must recruit a second person or
/// the app does nothing (docs/11). Friction here costs more than friction
/// anywhere else, so the code is large, copyable, shareable, and the "enter
/// theirs" path is one tap away.
class PairScreen extends StatefulWidget {
  const PairScreen({super.key, required this.onPaired});

  final VoidCallback onPaired;

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final _repo = PairRepository.instance();
  final _codeInput = TextEditingController();

  String? _myCode;
  bool _busy = false;
  bool _entering = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCode();
  }

  @override
  void dispose() {
    _codeInput.dispose();
    super.dispose();
  }

  Future<void> _loadCode() async {
    setState(() { _busy = true; _error = null; });
    try {
      final code = await _repo.createInvite();
      if (mounted) setState(() => _myCode = code);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _redeem() async {
    setState(() { _busy = true; _error = null; });
    try {
      await _repo.redeemInvite(_codeInput.text.toUpperCase());
      if (mounted) widget.onPaired();
    } on PostgrestException catch (e) {
      // The database produced this message ("code already used", "code has
      // expired", "that is your own code"). It is already plain language and
      // authoritative, so show it rather than inventing a client-side one.
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () => _repo.signOut(),
            child: const Text('Sign out', style: TextStyle(color: DuetColors.dim)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Invite your person.',
                  style: TextStyle(fontSize: 30, height: 1.1, color: DuetColors.text)),
              const SizedBox(height: 10),
              const Text(
                'Send them this code. Once they enter it, your alarms are shared.',
                style: TextStyle(fontSize: 15.5, color: DuetColors.muted, height: 1.45),
              ),
              const SizedBox(height: 28),

              if (!_entering) ..._inviteSide() else ..._redeemSide(),

              if (_error != null) ...[
                const SizedBox(height: 16),
                DuetCard(
                  border: DuetColors.danger,
                  child: Text(_error!,
                      style: const TextStyle(color: DuetColors.danger, fontSize: 13.5)),
                ),
              ],

              const SizedBox(height: 26),
              Center(
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() { _entering = !_entering; _error = null; }),
                  child: Text(
                    _entering ? 'Show my code instead' : 'Enter their code instead',
                    style: const TextStyle(color: DuetColors.amber, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _inviteSide() {
    final code = _myCode;
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: DuetColors.surface,
          border: Border.all(color: DuetColors.line),
        ),
        child: Column(
          children: [
            const SectionLabel('Your invite code'),
            const SizedBox(height: 18),
            if (code == null)
              const SizedBox(
                height: 60,
                child: Center(
                    child: CircularProgressIndicator(color: DuetColors.amber)),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final ch in code.split(''))
                    Container(
                      width: 44,
                      height: 58,
                      margin: const EdgeInsets.symmetric(horizontal: 3.5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: DuetColors.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: DuetColors.line),
                      ),
                      child: Text(ch,
                          style: const TextStyle(
                              fontSize: 26,
                              color: DuetColors.text,
                              fontFeatures: [FontFeature.tabularFigures()])),
                    ),
                ],
              ),
            const SizedBox(height: 14),
            const Text('Expires in 24 hours',
                style: TextStyle(fontSize: 13, color: DuetColors.dim)),
            const SizedBox(height: 18),
            DuetButton(
              'Copy code',
              filled: true,
              onTap: code == null
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied')),
                      );
                    },
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      DuetCard(
        child: Row(
          children: [
            const PairRing(size: 34, hasPartner: false, strokeWidth: 2),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Waiting for them to join. This screen updates once they do.',
                style: TextStyle(fontSize: 13.5, color: DuetColors.muted, height: 1.4),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: _busy ? null : widget.onPaired,
        child: const Text('I think they joined — check now',
            style: TextStyle(color: DuetColors.dim, fontSize: 14)),
      ),
    ];
  }

  List<Widget> _redeemSide() => [
        TextField(
          controller: _codeInput,
          autofocus: true,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
            TextInputFormatter.withFunction((_, n) =>
                n.copyWith(text: n.text.toUpperCase())),
          ],
          style: const TextStyle(
              fontSize: 30, letterSpacing: 10, color: DuetColors.text),
          decoration: InputDecoration(
            counterText: '',
            hintText: 'ABC123',
            hintStyle: const TextStyle(color: DuetColors.faint, letterSpacing: 10),
            filled: true,
            fillColor: DuetColors.surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 20),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: DuetColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: DuetColors.amber),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DuetButton('Join them', filled: true, busy: _busy, onTap: _redeem),
      ];
}
