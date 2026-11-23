import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/shop_repository.dart';
import '../design/format.dart';
import '../design/tokens.dart';
import '../state.dart';
import 'care_widgets.dart';
import 'shop_screen.dart';

/// The bag: lines, how to receive the order, and the totals. The server prices the order again and Stripe adds tax.
class BagScreen extends ConsumerStatefulWidget {
  const BagScreen({super.key});

  @override
  ConsumerState<BagScreen> createState() => _BagScreenState();
}

class _BagScreenState extends ConsumerState<BagScreen> {
  String _fulfilment = 'collect';
  String? _clinicId;
  bool _busy = false;

  Future<void> _checkout(List<BagLine> lines) async {
    final clinicId =
        _clinicId ?? ref.read(clinicsProvider).value?.firstOrNull?.id;
    if (clinicId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final link = await ref
          .read(shopRepositoryProvider)
          .checkout(lines, fulfilment: _fulfilment, clinicId: clinicId);
      late final AppLifecycleListener listener;
      listener = AppLifecycleListener(
        onResume: () {
          listener.dispose();
          Future.delayed(
            const Duration(seconds: 2),
            () => ref.invalidate(shopOrdersProvider),
          );
        },
      );
      if (await launchUrl(link, mode: LaunchMode.inAppBrowserView)) {
        ref.read(bagProvider.notifier).clear();
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Once you have paid, your order appears in Profile, Orders.',
            ),
          ),
        );
      } else {
        listener.dispose();
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not open the payment page.')),
        );
      }
    } on ShopError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bag = ref.watch(bagProvider);
    final lines = bag.values.toList();
    final clinics = ref.watch(clinicsProvider).value ?? const [];
    final subtotal = lines.fold(0, (n, l) => n + l.cents);
    final delivery = _fulfilment == 'ship' ? deliveryCents(subtotal) : 0;
    final refills = lines.where((l) => l.refill).toList();
    return Scaffold(
      backgroundColor: Palette.mist,
      appBar: AppBar(
        title: const Text('Your bag'),
        backgroundColor: Palette.mist,
        foregroundColor: Palette.deepSea,
      ),
      body: lines.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: EmptyNote(
                icon: Icons.shopping_bag_outlined,
                title: 'Your bag is empty',
                body: 'Add something from the shop.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
              children: [
                for (final l in lines) _BagRow(line: l),
                const SizedBox(height: 18),
                const Text(
                  'How would you like it?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Palette.deepSea,
                  ),
                ),
                const SizedBox(height: 10),
                _Option(
                  key: const Key('fulfil-collect'),
                  selected: _fulfilment == 'collect',
                  icon: Icons.storefront_rounded,
                  title: 'Collect at your clinic',
                  trailing: 'Free',
                  onTap: () => setState(() => _fulfilment = 'collect'),
                  child: _fulfilment != 'collect' || clinics.isEmpty
                      ? null
                      : Wrap(
                          spacing: 8,
                          children: [
                            for (final c in clinics)
                              ChoiceChip(
                                label: Text(c.name),
                                selected:
                                    (_clinicId ?? clinics.first.id) == c.id,
                                onSelected: (_) =>
                                    setState(() => _clinicId = c.id),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 8),
                _Option(
                  key: const Key('fulfil-ship'),
                  selected: _fulfilment == 'ship',
                  icon: Icons.local_shipping_rounded,
                  title: 'Deliver to me',
                  trailing: subtotal >= 5000 ? 'Free' : dollars(799),
                  detail: '3 to 5 days, US addresses. Free from \$50.',
                  onTap: () => setState(() => _fulfilment = 'ship'),
                ),
                const SizedBox(height: 20),
                Panel(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _Total('Subtotal', dollars(subtotal)),
                      _Total(
                        _fulfilment == 'ship' ? 'Delivery' : 'Collection',
                        delivery == 0 ? 'Free' : dollars(delivery),
                      ),
                      const _Total('Sales tax', 'At checkout'),
                      const Divider(height: 22),
                      _Total(
                        'Total before tax',
                        dollars(subtotal + delivery),
                        strong: true,
                      ),
                    ],
                  ),
                ),
                if (refills.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Refills: ${refills.map((l) => '${l.product.name} every ${l.product.refillMonths} months').join('; ')}. '
                    'Charged to the same card each time until you cancel.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: Palette.muted,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                const Row(
                  children: [
                    Icon(Icons.lock_rounded, size: 15, color: Palette.muted),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'You pay on Stripe\'s secure page; we never see your card.',
                        style: TextStyle(fontSize: 12.5, color: Palette.muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
      bottomSheet: lines.isEmpty
          ? null
          : Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                12 + MediaQuery.paddingOf(context).bottom,
              ),
              child: FilledButton(
                key: const Key('checkout'),
                onPressed: _busy ? null : () => _checkout(lines),
                style: FilledButton.styleFrom(
                  backgroundColor: Palette.teal,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Checkout',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
    );
  }
}

class _BagRow extends ConsumerWidget {
  const _BagRow({required this.line});
  final BagLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bag = ref.read(bagProvider.notifier);
    final p = line.product;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        key: Key('bag-${p.id}'),
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: ShopImage(p.imageKey, radius: 14),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Palette.deepSea,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    line.refill ? 'Every ${p.refillMonths} months' : 'One time',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Palette.muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dollars(line.cents),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Palette.deepSea,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: line.quantity == 1 ? 'Remove' : 'Fewer',
              onPressed: () => bag.setQuantity(p.id, line.quantity - 1),
              icon: Icon(
                line.quantity == 1
                    ? Icons.delete_outline_rounded
                    : Icons.remove_rounded,
              ),
            ),
            Text(
              '${line.quantity}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            IconButton(
              tooltip: 'More',
              onPressed: line.quantity >= 10
                  ? null
                  : () => bag.setQuantity(p.id, line.quantity + 1),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.selected,
    required this.icon,
    required this.title,
    required this.trailing,
    required this.onTap,
    this.detail,
    this.child,
  });
  final bool selected;
  final IconData icon;
  final String title, trailing;
  final String? detail;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? Palette.enamel : Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Palette.teal : Palette.line,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: selected ? Palette.teal : Palette.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Palette.deepSea,
                    ),
                  ),
                ),
                Text(
                  trailing,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Palette.deepSea,
                  ),
                ),
              ],
            ),
            if (detail != null)
              Padding(
                padding: const EdgeInsets.only(left: 36, top: 2),
                child: Text(
                  detail!,
                  style: const TextStyle(fontSize: 12.5, color: Palette.muted),
                ),
              ),
            if (child != null)
              Padding(
                padding: const EdgeInsets.only(left: 36, top: 10),
                child: child,
              ),
          ],
        ),
      ),
    ),
  );
}

class _Total extends StatelessWidget {
  const _Total(this.label, this.value, {this.strong = false});
  final String label, value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: strong ? 16 : 14,
      fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
      color: Palette.deepSea,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// Paid orders and refills, with where each one is.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  static String _status(ShopOrder o) => switch (o.status) {
    'paid' =>
      o.fulfilment == 'collect'
          ? 'Being prepared at ${o.clinic}'
          : 'Being packed',
    'ready' => 'Ready to collect at ${o.clinic}',
    'collected' => 'Collected',
    'shipped' => 'On its way',
    _ => o.status,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(shopOrdersProvider);
    return Scaffold(
      backgroundColor: Palette.mist,
      appBar: AppBar(
        title: const Text('Orders'),
        backgroundColor: Palette.mist,
        foregroundColor: Palette.deepSea,
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(shopOrdersProvider.future),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ...orders.when(
              loading: () => const [LoadingPanels()],
              error: (_, _) => [
                const Text('Could not load your orders. Pull to try again.'),
              ],
              data: (list) => list.isEmpty
                  ? const [
                      EmptyNote(
                        icon: Icons.shopping_bag_outlined,
                        title: 'No orders yet',
                        body: 'What you buy in the shop appears here.',
                      ),
                    ]
                  : [
                      for (final o in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Panel(
                            key: Key('order-${o.id}'),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    ShopPill(
                                      o.isRefill
                                          ? 'Refill'
                                          : dayMonthYear(o.createdAt),
                                      icon: o.isRefill
                                          ? Icons.autorenew_rounded
                                          : Icons.receipt_long_rounded,
                                    ),
                                    const Spacer(),
                                    if (o.totalCents != null)
                                      Text(
                                        dollars(o.totalCents!),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Palette.deepSea,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                for (final line in o.lines)
                                  Text(
                                    line,
                                    style: const TextStyle(
                                      color: Palette.deepSea,
                                      height: 1.5,
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Text(
                                  _status(o),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Palette.teal,
                                  ),
                                ),
                              ],
                            ),
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
