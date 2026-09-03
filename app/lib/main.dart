import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'home_screen.dart';
import 'pair_repository.dart';
import 'pair_screen.dart';
import 'sign_in_screen.dart';
import 'supabase_config.dart';
import 'theme.dart';

/// Whether to require sign-in and pairing.
///
/// Off for now. The backend is built and its security model is tested
/// (supabase/), but sign-in still needs the Magic Link email template to carry
/// `{{ .Token }}` and needs custom SMTP before it can survive real testers —
/// both noted in supabase/README.md.
///
/// Turning this off costs nothing architecturally: ADR-001 already says alarms
/// are scheduled locally and the network only carries definitions, so the whole
/// product works standalone. Flip it back on with:
///
///   flutter build apk --dart-define=DUET_BACKEND=true
const kBackendEnabled = bool.fromEnvironment('DUET_BACKEND', defaultValue: false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kBackendEnabled) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  }

  runApp(const DuetApp());
}

class DuetApp extends StatelessWidget {
  const DuetApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Duet',
        debugShowCheckedModeBanner: false,
        theme: duetTheme(),
        home: kBackendEnabled ? const AuthGate() : const HomeScreen(),
      );
}

/// Signed out → sign in. Signed in → pairing, or the app.
/// Only reachable when [kBackendEnabled].
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ??
            Supabase.instance.client.auth.currentSession;
        if (session == null) return const SignInScreen();
        return const PairGate();
      },
    );
  }
}

/// A user with no partner cannot use the shared features, so pairing comes
/// before them rather than hiding in settings.
class PairGate extends StatefulWidget {
  const PairGate({super.key});

  @override
  State<PairGate> createState() => _PairGateState();
}

class _PairGateState extends State<PairGate> {
  final _repo = PairRepository.instance();
  Future<PairState?>? _pair;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  // A BLOCK body, not an arrow. `setState(() => _pair = future)` returns the
  // assignment's value -- a Future -- and Flutter rejects a setState callback
  // that returns one, with a full-screen error. The future is stored here and
  // awaited by the FutureBuilder; no async work happens inside setState.
  void _reload() {
    setState(() {
      _pair = _repo.currentPair();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PairState?>(
      future: _pair,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: DuetColors.amber)),
          );
        }
        final pair = snap.data;
        if (pair == null || !pair.isComplete) {
          return PairScreen(onPaired: _reload);
        }
        return const HomeScreen();
      },
    );
  }
}
