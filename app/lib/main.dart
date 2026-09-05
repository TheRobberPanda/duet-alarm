import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'alarm_engine.dart';
import 'alarm_repository.dart';
import 'alarm_sync.dart';
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

    // A firing alarm needs the token to report a ring session with no Flutter
    // engine running (RingSync.kt), so it has to be pushed down natively
    // rather than fetched on demand. Every auth change is a chance to refresh
    // it -- including the token refresh Supabase does quietly on its own,
    // which is exactly the moment a stale native copy would otherwise go
    // uncorrected.
    final client = Supabase.instance.client;
    AlarmEngine.setAuthToken(
      client.auth.currentSession?.accessToken,
      client.auth.currentUser?.id,
    );
    client.auth.onAuthStateChange.listen((state) {
      AlarmEngine.setAuthToken(
        state.session?.accessToken,
        state.session?.user.id,
      );
    });
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
        // Painted once behind every screen, Navigator route changes included --
        // ThemeData.scaffoldBackgroundColor is transparent precisely so this
        // shows through instead of every screen needing its own backdrop.
        builder: (context, child) => GirlyBackdrop(child: child ?? const SizedBox()),
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
        // A cross-fade rather than a hard swap: signing in and getting pulled
        // into pairing should feel like one continuous motion, not a jump cut.
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: session == null
              ? const SignInScreen(key: ValueKey('signin'))
              : const PairGate(key: ValueKey('pair')),
        );
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
  bool _skippedPairing = false;

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
      // Hand the alarm repository a sync source as a side effect of resolving
      // the pair -- not inside build(), where side effects do not belong.
      _pair = _repo.currentPair().then((pair) async {
        AlarmRepository.instance
          ..sync = AlarmSync(Supabase.instance.client)
          ..pairId = pair?.pairId;
        // Every PairRing in the app reads its two colors from here -- see
        // theme.dart's SkinColors. myProfile() is a second round trip, but
        // this only runs on sign-in/pairing changes, not on every rebuild.
        final me = await _repo.myProfile();
        SkinColors.instance.setSkins(mine: me?.accent, partner: pair?.partner?.accent);
        // The ringing screen is plain Android views with no Flutter engine, so
        // it cannot read SkinColors -- the two colors have to be pushed to it.
        await AlarmEngine.setSkinColors(
          SkinColors.instance.mine.toARGB32(),
          SkinColors.instance.partner.toARGB32(),
        );
        // And the native side gets what the LAN fast path needs to sign and
        // authorise datagrams while the app itself is not running.
        await AlarmEngine.setPairContext(
          pairId: pair?.pairId,
          lanSecret: pair?.lanSecret,
          allowPartnerDismiss: me?.allowPartnerDismiss ?? true,
        );
        return pair;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PairState?>(
      future: _pair,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator(color: SkinColors.instance.accent)),
          );
        }
        final pair = snap.data;
        final paired = pair != null && pair.isComplete;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: !paired && !_skippedPairing
              ? PairScreen(
                  key: const ValueKey('invite'),
                  onPaired: _reload,
                  onSkip: () => setState(() => _skippedPairing = true),
                )
              : HomeScreen(
                  key: const ValueKey('home'),
                  partnerName: paired ? pair.partner!.shortName : null,
                  partnerTimezone: paired ? pair.partner!.timezone : null,
                  onInvite: paired
                      ? null
                      : () => setState(() => _skippedPairing = false),
                ),
        );
      },
    );
  }
}
