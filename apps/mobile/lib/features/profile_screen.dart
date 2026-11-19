import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../design/art.dart';
import '../design/tokens.dart';
import '../state.dart';
import 'care_widgets.dart';

/// The account: who is linked, privacy, and signing out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(linkedPatientsProvider).value ?? const [];
    final current = ref.watch(currentPatientProvider);
    final self = people.where((p) => p.isSelf).firstOrNull ?? current;
    final initials = (self?.name ?? '').split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join();
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
        children: [
          Text('Profile', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(gradient: heroGradient, borderRadius: BorderRadius.circular(28), boxShadow: lift(1.4)),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Palette.apricot,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
                  ),
                  child: Text(
                    initials,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Palette.deepSea),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        self?.name ?? '',
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      const Text('Patient account', style: TextStyle(fontSize: 14, color: Color(0xFFA9DCD1))),
                    ],
                  ),
                ),
                const ToothMark(height: 34, stroke: Color(0xFF8FE3C8), fill: Colors.transparent),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionTitle('People on this account'),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                for (final p in people)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: IconTile(p.isSelf ? Icons.person_rounded : Icons.child_care_rounded, size: 42),
                    title: Text(
                      p.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.deepSea),
                    ),
                    subtitle: Text(p.isSelf ? 'You' : 'You manage their care', style: const TextStyle(color: Palette.muted)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionTitle('Privacy'),
          const EmptyNote(
            icon: Icons.verified_user_outlined,
            title: 'Your data stays protected',
            body: 'Your sign-in is kept in the phone\'s secure storage and removed when you sign out. This app holds synthetic data only.',
          ),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            key: const Key('sign-out'),
            onPressed: () => _confirmSignOut(context, ref),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              foregroundColor: Palette.error,
              side: const BorderSide(color: Color(0xFFF1C9C5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              textStyle: const TextStyle(fontFamily: uiFont, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
  final yes = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    showDragHandle: true,
    isScrollControlled: true, // size to content and scroll on short screens instead of overflowing
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: IconTile(Icons.logout_rounded, size: 64)),
              const SizedBox(height: 18),
              Text('Sign out of Northgate?', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              const Text(
                'We remove your sign-in from this phone. You will need your email and password to come back.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.5, color: Palette.muted),
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('confirm-sign-out'),
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: Palette.error,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  textStyle: const TextStyle(fontFamily: uiFont, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                child: const Text('Sign out'),
              ),
              const SizedBox(height: 10),
              TextButton(
                key: const Key('cancel-sign-out'),
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: const Text('Stay signed in'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (yes != true) return;
  ref.read(signedOutNoticeProvider.notifier).show();
  await ref.read(accountRepositoryProvider).signOut();
}
