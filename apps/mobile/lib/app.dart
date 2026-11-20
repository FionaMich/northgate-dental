import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'design/tokens.dart';
import 'features/shell.dart';
import 'features/intro_screen.dart';
import 'features/aligner_screen.dart';
import 'features/auth_screens.dart';
import 'features/details_screen.dart';
import 'features/link_code_screen.dart';
import 'features/sign_in_screen.dart';
import 'state.dart';

class NorthgateApp extends StatefulWidget {
  const NorthgateApp({super.key});

  @override
  State<NorthgateApp> createState() => _NorthgateAppState();
}

class _NorthgateAppState extends State<NorthgateApp> {
  bool _introDone = false;
  final _router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => const Gate())],
  );

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Northgate Dental',
    theme: northgateTheme(),
    routerConfig: _router,
    // The intro shows once per cold start, then hands over to the sign-in or home gate.
    builder: (context, child) => LightStatusBar(child: _introDone ? child! : IntroScreen(onDone: () => setState(() => _introDone = true))),
  );
}

/// Light status bar icons over the app's dark tops.
class LightStatusBar extends StatelessWidget {
  const LightStatusBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(value: SystemUiOverlayStyle.light, child: child);
}

/// Sends the person to sign-in, linking, their clinic and address, or home, depending on where they are.
class Gate extends ConsumerWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const loading = Scaffold(body: Center(child: CircularProgressIndicator()));
    // Signing out wipes what this phone keeps for the person (aligner wear logs and their reminders).
    ref.listen(signedInProvider, (_, next) {
      if (next.value == false) {
        ref.read(wearStoreProvider).clearAll();
        ref.read(alignerRemindersProvider).clearAll().catchError((_) {});
      }
    });
    final signedIn = ref.watch(signedInProvider).value;
    if (signedIn == null) return loading;
    if (!signedIn) return const SignInScreen();
    // Second factor: the emailed code, checked by the server, before any patient data.
    final verified = ref.watch(sessionVerifiedProvider);
    if (verified.hasError) {
      return Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => ref.invalidate(sessionVerifiedProvider),
            child: const Text('Could not reach Northgate. Tap to try again.'),
          ),
        ),
      );
    }
    if (!verified.hasValue || verified.isLoading) return loading;
    if (verified.value == false) {
      return CodeScreen(email: ref.read(accountRepositoryProvider).currentEmail ?? '', purpose: CodePurpose.signIn);
    }
    return ref
        .watch(linkedPatientsProvider)
        .when(
          loading: () => loading,
          error: (_, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => ref.invalidate(linkedPatientsProvider),
                child: const Text('Could not load your record. Tap to try again.'),
              ),
            ),
          ),
          data: (people) {
            if (people.isEmpty) return const LinkCodeScreen();
            // Asked once after linking: the account holder's clinic and address.
            final unconfirmed = people.where((p) => p.isSelf && !p.detailsConfirmed).firstOrNull;
            return unconfirmed == null ? const AppShell() : DetailsScreen(patient: unconfirmed);
          },
        );
  }
}
