import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'features/home_screen.dart';
import 'features/link_code_screen.dart';
import 'features/sign_in_screen.dart';
import 'state.dart';

const _teal = Color(0xFF04899A);

class NorthgateApp extends StatefulWidget {
  const NorthgateApp({super.key});

  @override
  State<NorthgateApp> createState() => _NorthgateAppState();
}

class _NorthgateAppState extends State<NorthgateApp> {
  final _router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const Gate())]);

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Northgate Dental',
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: _teal)),
        routerConfig: _router,
        builder: (context, child) => SyntheticFrame(child: child!),
      );
}

/// A strip on every screen: this app only ever holds synthetic data.
class SyntheticFrame extends StatelessWidget {
  const SyntheticFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      Material(
        color: scheme.tertiaryContainer,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Center(
              child: Text('Synthetic data. Not a real practice or patient.',
                  style: TextStyle(fontSize: 12, color: scheme.onTertiaryContainer)),
            ),
          ),
        ),
      ),
      Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: child)),
    ]);
  }
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
    return ref.watch(linkedPatientsProvider).when(
          loading: () => loading,
          error: (_, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => ref.invalidate(linkedPatientsProvider),
                child: const Text('Could not load your record. Tap to try again.'),
              ),
            ),
          ),
          data: (people) => people.isEmpty ? const LinkCodeScreen() : const HomeScreen(),
        );
  }
}
