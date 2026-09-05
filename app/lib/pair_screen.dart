import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pair_repository.dart';
import 'qr_scan_screen.dart';
import 'theme.dart';

/// Pair setup.
///
/// This screen IS the growth engine: every user must recruit a second person or
/// the app does nothing (docs/11). Friction here costs more than friction
/// anywhere else, so the code is large, copyable, shareable, and the "enter
/// theirs" path is one tap away.
class PairScreen extends StatefulWidget {
  const PairScreen({super.key, required this.onPaired, this.onSkip});

  final VoidCallback onPaired;

  /// Continue alone. Blocking someone out of the app until their partner joins
  /// is a good way to be uninstalled before the invite is even sent -- the
  /// alarms have to be useful on day one, or there is no reason to keep it.
  final VoidCallback? onSkip;

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final _repo = PairRepository.instance();
  final _codeInput = TextEditingController();

  String? _myCode;
  bool _busy = false;
  bool _entering = false;

  // The invite card shows either the six characters or a QR encoding them --
  // same code, two ways to carry it across a table.
  bool _showQr = false;
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
                  style: TextStyle(
                      fontSize: 30,
                      height: 1.1,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -0.3,
                      color: DuetColors.text)),
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
                    style: TextStyle(color: SkinColors.instance.accent, fontSize: 15),
                  ),
                ),
              ),
              if (widget.onSkip != null)
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : widget.onSkip,
                    child: const Text('Set up my alarms first',
                        style: TextStyle(color: DuetColors.dim, fontSize: 14.5)),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SectionLabel('Your invite code'),
                if (code != null) _codeQrToggle(),
              ],
            ),
            const SizedBox(height: 18),
            if (code == null)
              // Skeleton, not a spinner: the shape of what is arriving.
              Row(
                children: [
                  for (var i = 0; i < 6; i++)
                    Expanded(
                      child: Container(
                        height: 58,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        child: const Skeleton(radius: 12),
                      ),
                    ),
                ],
              )
            else if (_showQr) ..._qrBlock(code) else ..._cells(code),
            const SizedBox(height: 14),
            const Text('Expires in 24 hours',
                style: TextStyle(fontSize: 13, color: DuetColors.dim)),
            const SizedBox(height: 18),
            DuetButton(
              'Copy code',
              icon: Icons.copy_rounded,
              filled: true,
              onTap: code == null
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: code));
                      showDuetSnackBar(context, 'Code copied', icon: Icons.copy_rounded);
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

  /// Six characters, one per cell, entering with a tiny stagger -- the code
  /// assembles itself in front of you. Expanded, not fixed-width: six 44px
  /// cells plus margins overflow a 384dp screen by 12px, and the invite code
  /// is the one screen that must never look broken -- it is the whole growth
  /// engine.
  List<Widget> _cells(String code) => [
        Row(
          children: [
            for (final (i, ch) in code.split('').indexed)
              Expanded(
                child: FadeSlideIn(
                  key: ValueKey('cell-$i-$ch'),
                  delay: Duration(milliseconds: 45 * i),
                  child: Container(
                    height: 58,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: DuetColors.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: DuetColors.line),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(ch,
                          style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w500,
                              color: DuetColors.text,
                              fontFeatures: [FontFeature.tabularFigures()])),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ];

  /// The same code as a QR, on a light island -- cameras need contrast, so
  /// the plum field gets exactly one bright rectangle.
  List<Widget> _qrBlock(String code) => [
        Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: Container(
              key: ValueKey(code),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DuetColors.text,
                borderRadius: BorderRadius.circular(18),
              ),
              child: QrImageView(
                data: code,
                size: 172,
                backgroundColor: DuetColors.text,
                eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square, color: DuetColors.amberInk),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: DuetColors.amberInk),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Center(
          child: Text('Let their camera read this',
              style: TextStyle(fontSize: 13, color: DuetColors.dim)),
        ),
      ];

  Widget _codeQrToggle() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _togglePill('Code', Icons.pin_rounded, !_showQr),
          const SizedBox(width: 6),
          _togglePill('QR', Icons.qr_code_2_rounded, _showQr),
        ],
      );

  Widget _togglePill(String label, IconData icon, bool on) => GestureDetector(
        onTap: () => setState(() => _showQr = label == 'QR'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: on ? SkinColors.instance.wash : null,
            color: on ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 13, color: on ? DuetColors.amberInk : DuetColors.dim),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: on ? DuetColors.amberInk : DuetColors.dim)),
            ],
          ),
        ),
      );

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
          style: TextStyle(
              fontSize: 30,
              letterSpacing: 10,
              fontWeight: FontWeight.w400,
              color: DuetColors.text,
              fontFeatures: const [FontFeature.tabularFigures()]),
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
              borderSide: BorderSide(color: SkinColors.instance.accent),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DuetButton('Join them', filled: true, busy: _busy, onTap: _redeem),
        const SizedBox(height: 10),
        DuetButton(
          'Scan their QR',
          icon: Icons.qr_code_scanner_rounded,
          busy: _busy,
          onTap: _scan,
        ),
      ];

  /// Same table, no typing: read the code off their screen with the camera.
  /// A scanned code goes straight into redemption -- if the camera read a
  /// stale code the redeem error surfaces in plain language.
  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      DuetPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (code == null || !mounted) return;
    _codeInput.text = code.toUpperCase();
    await _redeem();
  }
}
