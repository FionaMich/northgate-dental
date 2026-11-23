import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/account_repository.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../state.dart';
import 'booking_screen.dart';
import 'care_widgets.dart';
import 'dentist_screen.dart';
import 'visit_screen.dart' show documentOpenerProvider;

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Now, in the clinic's own time zone (so "Open now" is right even when the phone is elsewhere).
DateTime clinicNow(String timeZone) {
  tzdata.initializeTimeZones();
  return tz.TZDateTime.now(tz.getLocation(timeZone));
}

/// Whether the clinic is open at [now] (clinic local time), from its weekly hours.
bool isOpen(Clinic c, DateTime now) {
  final hhmm =
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  return c.hours.any(
    (h) =>
        h.$1 == now.weekday &&
        h.$2.compareTo(hhmm) <= 0 &&
        hhmm.compareTo(h.$3) < 0,
  );
}

String _photoFor(Clinic c) => c.photoKey == null
    ? 'assets/images/intro_clinic.jpg'
    : 'assets/images/clinics/${c.photoKey}.jpg';

/// One clinic: photo, Directions and Call, opening hours with "Open now", services, the team there, and Book.
class ClinicScreen extends ConsumerWidget {
  const ClinicScreen({super.key, required this.clinic, this.now});
  final Clinic clinic;

  /// For tests: the clinic's local time.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = clinic;
    final local = now ?? clinicNow(c.timeZone);
    final open = isOpen(c, local);
    final services =
        ref.watch(bookableServicesProvider(c.id)).value ?? const [];
    final team = [
      for (final d in ref.watch(dentistsProvider).value ?? const [])
        if (d.clinics.containsKey(c.id)) d,
    ];
    final person = ref.watch(currentPatientProvider);
    final opener = ref.read(documentOpenerProvider);
    return Scaffold(
      backgroundColor: Palette.mist,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          SizedBox(
            height: 250,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  _photoFor(c),
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => Image.asset(
                    'assets/images/intro_clinic.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x66072B29),
                        Color(0x00072B29),
                        Color(0xE6072B29),
                      ],
                      stops: [0, 0.4, 1],
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 20, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          color: Colors.white,
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Northgate Dental, ${c.name}',
                                style: const TextStyle(
                                  fontSize: 26,
                                  height: 1.15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                key: const Key('open-badge'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: open
                                      ? const Color(0xFF1FBFA2)
                                      : Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  open ? 'Open now' : 'Closed now',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Action(
                        key: const Key('clinic-directions'),
                        icon: Icons.directions_rounded,
                        label: 'Directions',
                        onTap: () => opener(
                          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(c.address)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (c.phone != null)
                      Expanded(
                        child: _Action(
                          key: const Key('clinic-call'),
                          icon: Icons.call_rounded,
                          label: 'Call',
                          onTap: () => opener('tel:${c.phone}'),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                RowGroup(
                  title: 'Address',
                  rows: [
                    GroupRow(
                      icon: Icons.location_on_rounded,
                      tint: Tint.teal,
                      title: c.address,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                RowGroup(
                  title: 'Opening hours',
                  rows: [
                    for (var day = 1; day <= 7; day++)
                      _HoursRow(
                        day: _weekdays[day - 1],
                        hours: [
                          for (final h in c.hours)
                            if (h.$1 == day) '${h.$2} to ${h.$3}',
                        ],
                        today: day == local.weekday,
                      ),
                  ],
                ),
                if (services.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  RowGroup(
                    title: 'Services here',
                    rows: [
                      for (final sv in services)
                        GroupRow(
                          icon: Icons.medical_services_outlined,
                          tint: Tint.sky,
                          title: sv.name,
                          detail: '${sv.minutes} minutes',
                        ),
                    ],
                  ),
                ],
                if (team.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  RowGroup(
                    title: 'Your team here',
                    rows: [
                      for (final d in team)
                        Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(
                              16,
                              6,
                              12,
                              6,
                            ),
                            leading: DentistAvatar(
                              name: d.name,
                              asset: d.photoAsset,
                              size: 44,
                            ),
                            title: Text(
                              d.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Palette.deepSea,
                              ),
                            ),
                            subtitle: Text(d.title),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFF9DB3AF),
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => DentistScreen(dentist: d),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                if (person != null)
                  PrimaryButton(
                    key: const Key('book-at-clinic'),
                    label: 'Book at ${c.name}',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            BookingScreen(patient: person, clinicId: c.id),
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

class _Action extends StatelessWidget {
  const _Action({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(50),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

class _HoursRow extends StatelessWidget {
  const _HoursRow({
    required this.day,
    required this.hours,
    required this.today,
  });
  final String day;
  final List<String> hours;
  final bool today;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            today ? '$day (today)' : day,
            style: TextStyle(
              fontSize: 15,
              fontWeight: today ? FontWeight.w700 : FontWeight.w500,
              color: Palette.deepSea,
            ),
          ),
        ),
        Text(
          hours.isEmpty ? 'Closed' : hours.join(', '),
          style: TextStyle(
            fontSize: 15,
            fontWeight: today ? FontWeight.w700 : FontWeight.w500,
            color: hours.isEmpty ? Palette.muted : Palette.deepSea,
          ),
        ),
      ],
    ),
  );
}
