import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pair_repository.dart';
import 'theme.dart';

/// Email one-time code. No passwords: nothing to store, reset or leak, and one
/// fewer field between a new user and the invite flow — which is the app's whole
/// growth engine (docs/11).
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _repo = PairRepository.instance();
  final _email = TextEditingController();
  final _code = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() { _busy = true; _error = null; });
    try {
      await action();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() => _run(() async {
        await _repo.sendOtp(_email.text);
        if (mounted) setState(() => _codeSent = true);
      });

  Future<void> _verify() => _run(() async {
        await _repo.verifyOtp(_email.text, _code.text);
        // The auth state listener in main.dart takes it from here.
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Center(child: PairRing(size: 72)),
              const SizedBox(height: 28),
              const Text('An alarm you share.',
                  style: TextStyle(fontSize: 30, height: 1.1, color: DuetColors.text)),
              const SizedBox(height: 10),
              const Text(
                'Both phones ring. Either of you can turn it off.',
                style: TextStyle(fontSize: 15.5, color: DuetColors.muted, height: 1.45),
              ),
              const SizedBox(height: 34),

              if (!_codeSent) ...[
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  style: const TextStyle(color: DuetColors.text, fontSize: 16),
                  decoration: _fieldDecoration('you@example.com', 'Email'),
                ),
                const SizedBox(height: 12),
                DuetButton('Send me a code', filled: true, busy: _busy, onTap: _send),
              ] else ...[
                Text('Code sent to ${_email.text.trim()}',
                    style: const TextStyle(color: DuetColors.muted, fontSize: 14.5)),
                const SizedBox(height: 12),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                      color: DuetColors.text, fontSize: 28, letterSpacing: 8),
                  textAlign: TextAlign.center,
                  decoration: _fieldDecoration('123456', 'Six-digit code')
                      .copyWith(counterText: ''),
                ),
                const SizedBox(height: 12),
                DuetButton('Sign in', filled: true, busy: _busy, onTap: _verify),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _codeSent = false),
                  child: const Text('Use a different email',
                      style: TextStyle(color: DuetColors.dim)),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 14),
                DuetCard(
                  border: DuetColors.danger,
                  child: Text(_error!,
                      style: const TextStyle(color: DuetColors.danger, fontSize: 13.5)),
                ),
              ],

              const Spacer(),
              const Text(
                'We only use your email to sign you in.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: DuetColors.faint),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint, String label) => InputDecoration(
        hintText: hint,
        labelText: label,
        hintStyle: const TextStyle(color: DuetColors.faint),
        labelStyle: const TextStyle(color: DuetColors.dim),
        filled: true,
        fillColor: DuetColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: DuetColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: DuetColors.amber),
        ),
      );
}
