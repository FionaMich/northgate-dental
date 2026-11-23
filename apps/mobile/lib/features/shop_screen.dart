import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/shop_repository.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../state.dart';
import 'bag_screen.dart';
import 'care_widgets.dart';

/// The product photo on its mint stage; a calm icon if the photo is not bundled yet.
class ShopImage extends StatelessWidget {
  const ShopImage(this.imageKey, {super.key, this.radius = 18});
  final String imageKey;
  final double radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: ColoredBox(
      color: const Color(0xFFDFF1EC),
      child: Image.asset(
        'assets/images/shop/$imageKey.png',
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Center(
          child: Icon(Icons.spa_outlined, size: 40, color: Palette.teal),
        ),
      ),
    ),
  );
}

/// Small rounded label: a benefit ("Sensitive"), a refill cadence, or a rule ("Dentist approval").
class ShopPill extends StatelessWidget {
  const ShopPill(this.label, {super.key, this.icon, this.strong = false});
  final String label;
  final IconData? icon;
  final bool strong;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: strong ? Palette.deepSea : Palette.enamel,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: strong ? Colors.white : Palette.teal),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: strong ? Colors.white : Palette.tealDark,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The shop tab: what our dentists recommend, by category, with the bag one tap away.
class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  String? _category;

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(shopProductsProvider);
    final bag = ref.watch(bagProvider);
    final count = bag.values.fold(0, (n, l) => n + l.quantity);
    final total = bag.values.fold(0, (n, l) => n + l.cents);
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => ref.refresh(shopProductsProvider.future),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 180),
            children: [
              const PageHero(
                title: 'Shop',
                subtitle: 'What our dentists and hygienists recommend, delivered or ready at your next visit.',
                facts: [
                  (Icons.storefront_rounded, 'Collect free'),
                  (Icons.local_shipping_rounded, 'Free delivery from \$50'),
                ],
              ),
              Padding(
                // Below the header, not over its curve: the chips scroll and tap exactly where they are drawn.
                padding: const EdgeInsets.only(top: 18),
                child: products.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: LoadingPanels(),
                  ),
                  error: (_, _) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Panel(
                      onTap: () => ref.invalidate(shopProductsProvider),
                      child: const Text(
                        'Could not load the shop. Tap to try again.',
                      ),
                    ),
                  ),
                  data: (all) {
                    final present = {for (final p in all) p.category};
                    final shown = _category == null
                        ? all
                        : all.where((p) => p.category == _category).toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
                          child: Text(
                            'Shop by need',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Palette.deepSea,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 58, // room for the selected chip's glow
                          // Fades at the right edge, so it is clear there are more categories to swipe to.
                          child: ShaderMask(
                            shaderCallback: (r) => const LinearGradient(
                              colors: [
                                Colors.white,
                                Colors.white,
                                Color(0x00FFFFFF),
                              ],
                              stops: [0, 0.88, 1],
                            ).createShader(r),
                            blendMode: BlendMode.dstIn,
                            child: ListView(
                              key: const Key('shop-categories'),
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              padding: const EdgeInsets.fromLTRB(20, 4, 36, 10),
                              children: [
                                _Chip(
                                  label: 'All',
                                  icon: Icons.apps_rounded,
                                  selected: _category == null,
                                  onTap: () => setState(() => _category = null),
                                ),
                                for (final MapEntry(:key, :value)
                                    in shopCategories.entries)
                                  if (present.contains(key))
                                    _Chip(
                                      key: Key('category-$key'),
                                      label: value,
                                      icon:
                                          _categoryIcons[key] ??
                                          Icons.spa_rounded,
                                      selected: _category == key,
                                      onTap: () =>
                                          setState(() => _category = key),
                                    ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: shown.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 14,
                                  crossAxisSpacing: 14,
                                  // the square photo plus room for a pill, two lines of name and the price, at the
                                  // phone's own text size, so cards never cut off text
                                  mainAxisExtent:
                                      (MediaQuery.sizeOf(context).width - 54) /
                                          2 +
                                      MediaQuery.textScalerOf(context)
                                          .scale(118),
                                ),
                            itemBuilder: (_, i) => Reveal(
                              order: i,
                              child: _ProductCard(product: shown[i]),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (count > 0)
          Positioned(
            left: 20,
            right: 20,
            bottom: 104,
            child: Material(
              color: Palette.teal,
              borderRadius: BorderRadius.circular(20),
              elevation: 8,
              shadowColor: Palette.deepSea.withValues(alpha: 0.4),
              child: InkWell(
                key: const Key('open-bag'),
                borderRadius: BorderRadius.circular(20),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const BagScreen())),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 15,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shopping_bag_rounded,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'View bag · $count ${count == 1 ? 'item' : 'items'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        dollars(total),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

const _categoryIcons = {
  'brush': Icons.brush_rounded,
  'clean_between': Icons.cleaning_services_rounded,
  'paste_and_rinse': Icons.water_drop_rounded,
  'aligners': Icons.mood_rounded,
  'kids': Icons.child_care_rounded,
  'whitening': Icons.auto_awesome_rounded,
  'prescription': Icons.verified_user_rounded,
};

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? Palette.teal : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: selected ? Palette.teal : Palette.line),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: Palette.teal.withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: Palette.deepSea.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? Colors.white : Palette.teal,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : Palette.deepSea,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});
  final ShopProduct product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        key: Key('product-${p.id}'),
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => ProductScreen(product: p))),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Hero(tag: 'shop-${p.id}', child: ShopImage(p.imageKey)),
              ),
              const SizedBox(height: 10),
              if (p.rule == 'prescription')
                const ShopPill(
                  'Dentist approval',
                  icon: Icons.verified_user_outlined,
                  strong: true,
                )
              else if (p.refillMonths != null)
                ShopPill(
                  'Refill every ${p.refillMonths} mo',
                  icon: Icons.autorenew_rounded,
                )
              else if (p.tags.isNotEmpty)
                ShopPill(p.tags.first),
              const SizedBox(height: 6),
              Text(
                p.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: Palette.deepSea,
                ),
              ),
              const Spacer(),
              Text(
                dollars(p.priceCents),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Palette.deepSea,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One product: photo, why we recommend it, one-time or refill, and quantity.
class ProductScreen extends ConsumerStatefulWidget {
  const ProductScreen({super.key, required this.product});
  final ShopProduct product;

  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  int _quantity = 1;
  bool _refill = false;

  @override
  void initState() {
    super.initState();
    _refill =
        widget.product.refillMonths !=
        null; // refills first, like the best oral-care shops
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final locked = p.needsApproval;
    return Scaffold(
      backgroundColor: Palette.mist,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 380,
            backgroundColor: const Color(0xFFDFF1EC),
            foregroundColor: Palette.deepSea,
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'shop-${p.id}',
                child: ShopImage(p.imageKey, radius: 0),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final t in p.tags) ShopPill(t)],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    p.name,
                    style: const TextStyle(
                      fontSize: 24,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: Palette.deepSea,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    dollars(p.priceCents),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Palette.teal,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    p.summary,
                    style: const TextStyle(
                      fontSize: 15.5,
                      height: 1.45,
                      color: Palette.deepSea,
                    ),
                  ),
                  if (locked) ...[
                    const SizedBox(height: 16),
                    const _Note(
                      icon: Icons.verified_user_outlined,
                      title: 'Your dentist approves this first',
                      body: 'This is prescription strength. Ask at your next visit; once your dentist approves it, you can order it here.',
                    ),
                  ],
                  if (p.needsRecentExam) ...[
                    const SizedBox(height: 16),
                    const _Note(
                      icon: Icons.event_available_outlined,
                      title: 'Needs an exam in the last 12 months',
                      body: 'We check whitening is right for your teeth first. Adults only.',
                    ),
                  ],
                  if (p.refillMonths != null && !locked) ...[
                    const SizedBox(height: 22),
                    const Text(
                      'How often',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Palette.deepSea,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Choice(
                      key: const Key('choose-refill'),
                      selected: _refill,
                      title: 'Refill every ${p.refillMonths} months',
                      detail: 'Sent automatically; cancel any time by calling your clinic.',
                      onTap: () => setState(() => _refill = true),
                    ),
                    const SizedBox(height: 8),
                    _Choice(
                      key: const Key('choose-once'),
                      selected: !_refill,
                      title: 'Just this once',
                      onTap: () => setState(() => _refill = false),
                    ),
                  ],
                  const SizedBox(height: 22),
                  const Text(
                    'Why we recommend it',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Palette.deepSea,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    p.description,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.55,
                      color: Palette.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          12 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Row(
          children: [
            _Stepper(
              value: _quantity,
              onChanged: locked ? null : (v) => setState(() => _quantity = v),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('add-to-bag'),
                onPressed: locked
                    ? null
                    : () {
                        ref
                            .read(bagProvider.notifier)
                            .add(
                              p,
                              quantity: _quantity,
                              refill: _refill && p.refillMonths != null,
                            );
                        Navigator.of(context).pop();
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: Palette.teal,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  locked
                      ? 'Ask your dentist'
                      : 'Add to bag · ${dollars(p.priceCents * _quantity)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title, body;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Palette.line),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Palette.teal),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Palette.deepSea,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: Palette.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.selected,
    required this.title,
    this.detail,
    required this.onTap,
  });
  final bool selected;
  final String title;
  final String? detail;
  final VoidCallback onTap;

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
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? Palette.teal : Palette.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Palette.deepSea,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Palette.muted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 54,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Palette.line),
    ),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Fewer',
          onPressed: onChanged == null || value <= 1
              ? null
              : () => onChanged!(value - 1),
          icon: const Icon(Icons.remove_rounded),
        ),
        Text(
          '$value',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Palette.deepSea,
          ),
        ),
        IconButton(
          tooltip: 'More',
          onPressed: onChanged == null || value >= 10
              ? null
              : () => onChanged!(value + 1),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    ),
  );
}
