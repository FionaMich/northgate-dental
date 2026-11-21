import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/account_repository.dart';
import '../design/tokens.dart';
import '../state.dart';
import 'care_widgets.dart';
import 'aligner_screen.dart';
import 'clinic_screen.dart';
import 'coverage_screen.dart';
import 'details_screen.dart';

/// The account: who is linked, their clinic and address, privacy, and signing out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(linkedPatientsProvider).value ?? const [];
    final current = ref.watch(currentPatientProvider);
    final self = people.where((p) => p.isSelf).firstOrNull ?? current;
    final initials = (self?.name ?? '').split(' ').where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join();
    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        PageHero(
          title: self?.name ?? 'Profile',
          subtitle: 'Your clinic, insurance and tools.',
          leading: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFC79A), Palette.apricot],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2.5),
              boxShadow: lift(1.2),
            ),
            child: Text(
              initials,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Palette.deepSea),
            ),
          ),
          facts: [if (people.length > 1) (Icons.group_rounded, '${people.length} people')],
        ),
        OverHero(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (self != null) ...[
                  RowGroup(
                    title: 'Your care',
                    rows: [_DetailsRow(patient: self)],
                  ),
                  const SizedBox(height: 22),
                  CoveragePanel(patient: self),
                  const SizedBox(height: 22),
                ],
                RowGroup(
                  title: 'People on this account',
                  rows: [
                    for (final p in people)
                      GroupRow(
                        icon: p.isSelf ? Icons.person_rounded : Icons.child_care_rounded,
                        tint: p.isSelf ? Tint.teal : Tint.violet,
                        title: p.name,
                        detail: p.isSelf ? 'You' : 'You manage their care',
                      ),
                  ],
                ),
                if (self != null) ...[
                  const SizedBox(height: 22),
                  RowGroup(
                    title: 'Tools',
                    rows: [
                      GroupRow(
                        key: const Key('open-aligner'),
                        icon: Icons.timer_outlined,
                        tint: Tint.violet,
                        title: 'Aligner timer',
                        detail: 'Track wear against 22 hours a day',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AlignerScreen(patient: self))),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                const RowGroup(
                  title: 'Privacy',
                  rows: [
                    GroupRow(
                      icon: Icons.lock_outline_rounded,
                      tint: Tint.sky,
                      title: 'Your data stays protected',
                      detail: 'Your sign-in is kept in the phone\'s secure storage and removed when you sign out.',
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  key: const Key('sign-out'),
                  onPressed: () => _confirmSignOut(context, ref),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: Colors.white,
                    foregroundColor: Palette.error,
                    side: const BorderSide(color: Color(0xFFF1C9C5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    textStyle: const TextStyle(fontFamily: uiFont, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The preferred clinic and home address on file, with Edit.
class _DetailsRow extends ConsumerWidget {
  const _DetailsRow({required this.patient});
  final LinkedPatient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(patientDetailsProvider(patient.id)).value;
    final clinics = ref.watch(clinicsProvider).value ?? const [];
    final clinic = clinics.where((c) => c.id == details?.clinicId).firstOrNull;
    final address = details == null || details.line1.isEmpty
        ? 'No address yet'
        : [details.line1, details.line2, details.city, '${details.state} ${details.zip}'].where((s) => s.trim().isNotEmpty).join(', ');
    void edit() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailsScreen(patient: patient, editing: true)));
    return GroupRow(
      icon: Icons.location_on_rounded,
      tint: Tint.teal,
      title: clinic?.name ?? 'Choose a clinic',
      detail: address,
      onTap: clinic == null ? edit : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClinicScreen(clinic: clinic))),
      trailing: TextButton(key: const Key('edit-details'), onPressed: edit, child: const Text('Edit')),
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
