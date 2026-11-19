import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'design/tokens.dart';
import 'features/shell.dart';
import 'features/intro_screen.dart';
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
    builder: (context, child) => SyntheticFrame(child: _introDone ? child! : IntroScreen(onDone: () => setState(() => _introDone = true))),
  );
}

/// Light status bar icons over the app's dark tops. The synthetic label lives in quiet copy on sign-up and profile, not a strip (decision 2026-11-19).
class SyntheticFrame extends StatelessWidget {
  const SyntheticFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(value: SystemUiOverlayStyle.light, child: child);
}

/// Sends the person to sign-in, linking or home, depending on where they are.
class Gate extends ConsumerWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const loading = Scaffold(body: Center(child: CircularProgressIndicator()));
    final signedIn = ref.watch(signedInProvider).value;
    if (signedIn == null) return loading;
    if (!signedIn) return const SignInScreen();
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
          data: (people) => people.isEmpty ? const LinkCodeScreen() : const AppShell(),
        );
  }
}
