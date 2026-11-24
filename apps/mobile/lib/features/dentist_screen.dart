import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dental/ui.dart';

import '../data/care_repository.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../state.dart';
import 'booking_screen.dart';
import 'care_widgets.dart';
import 'clinic_screen.dart';

/// The active team, for booking and the team row on Home.
final dentistsProvider = FutureProvider<List<Dentist>>(retry: (_, _) => null, (
  ref,
) async {
  if (!await ref.watch(sessionVerifiedProvider.future)) return const [];
  return ref.watch(careRepositoryProvider).dentists();
});

/// A round portrait from the app's team photos, or initials when there is no photo.
class DentistAvatar extends StatelessWidget {
  const DentistAvatar({
    super.key,
    required this.name,
    this.asset,
    this.size = 52,
    this.ring = true,
  });
  final String name;
  final String? asset;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .replaceAll('Dr ', '')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0])
        .join();
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ring ? 2.5 : 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ring ? Colors.white : null,
        boxShadow: ring ? lift(0.7) : null,
      ),
      child: ClipOval(
        child: asset == null
            ? Container(
                color: Tint.teal.wash,
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Tint.teal.ink,
                    fontSize: size * 0.32,
                  ),
                ),
              )
            : Image.asset(
                asset!,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
      ),
    );
  }
}

/// One dentist: large portrait over the brand header, what they focus on, where they work, and Book.
class DentistScreen extends ConsumerWidget {
  const DentistScreen({super.key, required this.dentist});
  final Dentist dentist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = dentist;
    final person = ref.watch(currentPatientProvider);
    return Scaffold(
      backgroundColor: Palette.mist,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: heroGradient,
              image: heroPhoto,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      tooltip: tr('Back'),
                      color: Colors.white,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 0, 30),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.name,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    height: 1.15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  d.title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Color(0xFFCDEFE7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (d.photoAsset != null)
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(28),
                            ),
                            child: Image.asset(
                              d.photoAsset!,
                              width: 150,
                              height: 170,
                              fit: BoxFit.cover,
                              excludeFromSemantics: true,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RowGroup(
                  title: 'About',
                  rows: [
                    GroupRow(
                      icon: Icons.auto_awesome_rounded,
                      tint: Tint.violet,
                      title: 'Focus',
                      detail: d.focus,
                    ),
                    GroupRow(
                      key: const Key('dentist-clinic'),
                      icon: Icons.location_on_rounded,
                      tint: Tint.teal,
                      title: 'Works at',
                      detail: d.clinics.values.join(' and '),
                      onTap: () {
                        final clinic =
                            (ref.read(clinicsProvider).value ?? const [])
                                .where((c) => d.clinics.containsKey(c.id))
                                .firstOrNull;
                        if (clinic != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ClinicScreen(clinic: clinic),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Panel(
                  child: Text(
                    d.bio,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.55,
                      color: Palette.deepSea,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                if (person != null)
                  PrimaryButton(
                    key: const Key('book-with-dentist'),
                    label: 'Book with ${d.name.split(',').first}',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BookingScreen(
                          patient: person,
                          dentistId: d.id,
                          clinicId: d.clinics.keys.firstOrNull,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
