import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/care_repository.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../state.dart';
import 'care_widgets.dart';

/// Opens Stripe Checkout for one of the patient's visits in an in-app browser tab. The amount comes from the clinic's
/// price list on the server; the app only asks for a link. When the patient comes back, the visits and payments
/// refresh, so the receipt shows as soon as Stripe has told us.
Future<void> payForVisit(
  BuildContext context,
  WidgetRef ref,
  String appointmentId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final link = await ref.read(careRepositoryProvider).payLink(appointmentId);
    late final AppLifecycleListener listener;
    listener = AppLifecycleListener(
      onResume: () {
        listener.dispose();
        Future.delayed(
          const Duration(seconds: 2),
          () => ref.invalidate(careSummaryProvider),
        );
      },
    );
    if (!await launchUrl(link, mode: LaunchMode.inAppBrowserView)) {
      listener.dispose();
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the payment page.')),
      );
    }
  } on PaymentError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    ref.invalidate(careSummaryProvider);
  }
}

/// Balances to pay (visits booked or open payments) and receipts for what is paid.
class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final care = ref.watch(careSummaryProvider);
    return Scaffold(
      backgroundColor: Palette.mist,
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(careSummaryProvider.future),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 80),
          children: [
            PageHero(
              title: 'Payments',
              subtitle:
                  'Pay for a visit securely by card, and keep your receipts.',
              leading: const BackButton(color: Colors.white),
              facts: [
                if (care.value case final c?) ...[
                  if (_due(c).isNotEmpty)
                    (Icons.receipt_long_rounded, '${_due(c).length} to pay'),
                  if (c.payments.any((p) => p.paid))
                    (
                      Icons.check_circle_rounded,
                      '${c.payments.where((p) => p.paid).length} paid',
                    ),
                ],
              ],
            ),
            OverHero(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: care.when(
                  loading: () => const LoadingPanels(),
                  error: (_, _) => Panel(
                    onTap: () => ref.invalidate(careSummaryProvider),
                    child: const Text(
                      'Could not load your payments. Tap to try again.',
                    ),
                  ),
                  data: (c) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_due(c).isEmpty && c.payments.isEmpty)
                        const EmptyNote(
                          icon: Icons.receipt_long_outlined,
                          title: 'Nothing to pay',
                          body: 'When you book a visit you can pay for it here, before or after you come in.',
                        ),
                      if (_due(c).isNotEmpty) const SectionTitle('To pay'),
                      for (final (i, d) in _due(c).indexed)
                        Reveal(
                          order: i,
                          child: _DueCard(item: d),
                        ),
                      if (c.payments.any((p) => p.paid)) ...[
                        const SizedBox(height: 8),
                        const SectionTitle('Receipts'),
                        for (final p in c.payments.where((p) => p.paid))
                          _ReceiptRow(payment: p),
                      ],
                      const SizedBox(height: 18),
                      const Row(
                        children: [
                          Icon(
                            Icons.lock_rounded,
                            size: 16,
                            color: Palette.muted,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Card details are entered on Stripe\'s secure page and never reach Northgate Dental.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Palette.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Something the patient can pay now: an open payment, or a booked visit with a price and no payment yet.
typedef _Due = ({
  String appointmentId,
  String service,
  String location,
  DateTime at,
  int amountCents,
});

List<_Due> _due(CareSummary c) => [
  for (final p in c.payments.where((p) => !p.paid))
    (
      appointmentId: p.appointmentId,
      service: p.service,
      location: p.location,
      at: p.visitAt,
      amountCents: p.amountCents,
    ),
  for (final a in c.upcoming.where(
    (a) =>
        a.priceCents != null && a.priceCents! > 0 && c.paymentFor(a.id) == null,
  ))
    (
      appointmentId: a.id,
      service: a.service,
      location: a.location,
      at: a.startsAt,
      amountCents: a.priceCents!,
    ),
];

class _DueCard extends ConsumerStatefulWidget {
  const _DueCard({required this.item});
  final _Due item;

  @override
  ConsumerState<_DueCard> createState() => _DueCardState();
}

class _DueCardState extends ConsumerState<_DueCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.item;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        key: Key('due-${d.appointmentId}'),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.service,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Palette.deepSea,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${dayMonth(d.at)}, ${clock(d.at)} · ${d.location}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Palette.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    dollars(d.amountCents),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Palette.deepSea,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              key: Key('pay-${d.appointmentId}'),
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      await payForVisit(context, ref, d.appointmentId);
                      if (mounted) setState(() => _busy = false);
                    },
              style: FilledButton.styleFrom(
                backgroundColor: Palette.teal,
                minimumSize: const Size(96, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Pay',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.payment});
  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        key: Key('receipt-${p.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const TintIcon(Icons.check_rounded, Tint.teal, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.service,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Palette.deepSea,
                    ),
                  ),
                  Text(
                    'Paid ${p.paidAt == null ? '' : dayMonthYear(p.paidAt!)} · ${p.location}',
                    style: const TextStyle(fontSize: 13, color: Palette.muted),
                  ),
                ],
              ),
            ),
            Text(
              dollars(p.amountCents),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Palette.deepSea,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
