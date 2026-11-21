import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';
import '../state.dart';
import 'aligner_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'records_screen.dart';

enum ShellTab { home, records, profile }

class ShellTabNotifier extends Notifier<ShellTab> {
  @override
  ShellTab build() {
    ref.watch(signedInProvider); // back to Home after a new sign-in
    return ShellTab.home;
  }

  void go(ShellTab tab) => state = tab;
}

final shellTabProvider = NotifierProvider<ShellTabNotifier, ShellTab>(ShellTabNotifier.new);

/// Signed-in, linked app: three tabs and a floating navigation bar.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _tabs = [
    (ShellTab.home, Icons.home_rounded, 'Home'),
    (ShellTab.records, Icons.receipt_long_rounded, 'Records'),
    (ShellTab.profile, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the phone's visit reminders in step with the booked visits on screen.
    ref.listen(careSummaryProvider, (_, next) {
      final upcoming = next.value?.upcoming;
      if (upcoming != null) {
        ref.read(alignerRemindersProvider).visitsBooked([for (final a in upcoming) a.startsAt]).catchError((_) {});
      }
    });
    final tab = ref.watch(shellTabProvider);
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: tab.index, children: const [HomeScreen(), RecordsScreen(), ProfileScreen()]),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: Palette.deepSea.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(color: Palette.deepSea.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 14), spreadRadius: -12),
            ],
          ),
          child: Row(
            children: [
              for (final (t, icon, label) in _tabs)
                Expanded(
                  child: Semantics(
                    selected: t == tab,
                    button: true,
                    label: label,
                    child: InkWell(
                      key: Key('tab-${t.name}'),
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => ref.read(shellTabProvider.notifier).go(t),
                      child: ExcludeSemantics(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(
                                color: t == tab ? Palette.shine.withValues(alpha: 0.18) : Colors.transparent,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Icon(icon, size: 24, color: t == tab ? Palette.shine : const Color(0xFFA9C9C2)),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: t == tab ? FontWeight.w700 : FontWeight.w500,
                                color: t == tab ? Colors.white : const Color(0xFFA9C9C2),
                              ),
                            ),
                          ],
                        ),
                      ),
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
