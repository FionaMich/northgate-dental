import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dental/ui.dart';

import '../data/care_repository.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../state.dart';
import 'booking_screen.dart';
import 'care_widgets.dart';
import 'dentist_screen.dart';
import 'home_screen.dart' show confirmCancelVisit;
import 'payments_screen.dart';
import 'shell.dart';

/// Every booked visit, each with Reschedule and Cancel; past visits live in Records.
class AppointmentsScreen extends ConsumerWidget {
  const AppointmentsScreen({super.key});

  void _book(BuildContext context, WidgetRef ref, {Appointment? replacing}) {
    final person = ref.read(currentPatientProvider);
    if (person == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingScreen(
          patient: person,
          clinicId: replacing?.clinicId,
          serviceId: replacing?.serviceId,
          dentistId: replacing?.dentistId,
          replaces: replacing,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final care = ref.watch(careSummaryProvider);
    final upcoming = care.value?.upcoming ?? const <Appointment>[];
    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        PageHero(
          title: 'Visits',
          subtitle: upcoming.isEmpty
              ? 'Nothing booked yet.'
              : 'Your booked visits, soonest first.',
          facts: [
            if (upcoming.isNotEmpty)
              (Icons.event_available_rounded, '${upcoming.length} booked'),
          ],
        ),
        OverHero(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PrimaryButton(
                  key: const Key('visits-book'),
                  label: 'Book a visit',
                  onPressed: () => _book(context, ref),
                ),
                const SizedBox(height: 22),
                ...care.when(
                  loading: () => const [LoadingPanels()],
                  error: (_, _) => [
                    Panel(
                      onTap: () => ref.invalidate(careSummaryProvider),
                      child: const Text(
                        'Could not load your visits. Tap to try again.',
                      ),
                    ),
                  ],
                  data: (c) => [
                    if (c.upcoming.isEmpty)
                      const EmptyNote(
                        icon: Icons.event_available_outlined,
                        title: 'No visits booked',
                        body: 'Book a time at your clinic and it appears here, with a reminder the day before.',
                      ),
                    for (final (i, a) in c.upcoming.indexed)
                      Reveal(
                        order: i,
                        child: _VisitCard(
                          appointment: a,
                          payment: c.paymentFor(a.id),
                          onPay: () => payForVisit(context, ref, a.id),
                          onReschedule: () => _book(context, ref, replacing: a),
                          onCancel: () => confirmCancelVisit(context, ref, a),
                        ),
                      ),
                    const SizedBox(height: 8),
                    GroupRow(
                      key: const Key('visits-past'),
                      icon: Icons.history_rounded,
                      tint: Tint.sky,
                      title: 'Past visits',
                      detail:
                          'What was done, X-rays and summaries are in Records',
                      onTap: () => ref
                          .read(shellTabProvider.notifier)
                          .go(ShellTab.records),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({
    required this.appointment,
    required this.onReschedule,
    required this.onCancel,
    required this.onPay,
    this.payment,
  });
  final Appointment appointment;
  final Payment? payment;
  final VoidCallback onReschedule, onCancel, onPay;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Panel(
        key: Key('upcoming-${a.id}'),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 58,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: buttonGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          weekday(a.startsAt),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFCDEFE7),
                          ),
                        ),
                        Text(
                          '${a.startsAt.day}',
                          style: const TextStyle(
                            fontSize: 24,
                            height: 1.05,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.service,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Palette.deepSea,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        trf('{}, {} to {}', [
                          dayMonth(a.startsAt),
                          clock(a.startsAt),
                          clock(a.endsAt),
                        ]),
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: Palette.muted,
                        ),
                      ),
                      Text(
                        a.location,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: Palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (a.dentist != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  DentistAvatar(
                    name: a.dentist!,
                    asset: a.dentistPhoto == null
                        ? null
                        : 'assets/images/team/${a.dentistPhoto}.jpg',
                    size: 34,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'With ${a.dentist}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Palette.deepSea,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (a.priceCents != null && a.priceCents! > 0) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                decoration: BoxDecoration(
                  color: Palette.mist,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: dollars(
                                payment?.amountCents ?? a.priceCents!,
                              ),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Palette.deepSea,
                              ),
                            ),
                            TextSpan(
                              text: payment?.paid == true
                                  ? '  ${tr('paid')}'
                                  : '  ${tr('to pay')}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (payment?.paid == true)
                      const Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: Palette.teal,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Paid',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Palette.teal,
                            ),
                          ),
                        ],
                      )
                    else
                      FilledButton(
                        key: Key('pay-visit-${a.id}'),
                        onPressed: onPay,
                        style: FilledButton.styleFrom(
                          backgroundColor: Palette.teal,
                          minimumSize: const Size(84, 40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Pay now',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: Key('reschedule-${a.id}'),
                    onPressed: onReschedule,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                    ),
                    child: const Text('Reschedule'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    key: Key('cancel-${a.id}'),
                    onPressed: onCancel,
                    style: dangerOutline.copyWith(
                      minimumSize: const WidgetStatePropertyAll(
                        Size.fromHeight(46),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
