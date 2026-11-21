import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_repository.dart' show clinicLabel;
import 'care_repository.dart' show linkBase;

/// A product in the clinic's shop. Prices are shown here but always re-read by the server when an order is made.
class ShopProduct {
  const ShopProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.summary,
    required this.description,
    required this.priceCents,
    required this.imageKey,
    this.tags = const [],
    this.refillMonths,
    this.rule = 'none',
    this.approved = false,
  });
  final String id, name, category, summary, description, imageKey, rule;
  final int priceCents;
  final List<String> tags;

  /// Every how many months it can be delivered as a refill; null when it is not sold as one.
  final int? refillMonths;

  /// For prescription-strength products: whether a dentist has approved it for this patient.
  final bool approved;

  bool get needsApproval => rule == 'prescription' && !approved;
  bool get needsRecentExam => rule == 'whitening';
}

/// What the patient sees in the shop's category chips, in this order.
const shopCategories = {
  'brush': 'Brushes',
  'clean_between': 'Between teeth',
  'paste_and_rinse': 'Toothpaste and rinse',
  'aligners': 'Aligners',
  'kids': 'Kids',
  'whitening': 'Whitening',
  'prescription': 'From your dentist',
};

class BagLine {
  const BagLine({required this.product, this.quantity = 1, this.refill = false});
  final ShopProduct product;
  final int quantity;
  final bool refill;
  int get cents => product.priceCents * quantity;
  BagLine copyWith({int? quantity, bool? refill}) =>
      BagLine(product: product, quantity: quantity ?? this.quantity, refill: refill ?? this.refill);
}

class ShopOrder {
  const ShopOrder({
    required this.id,
    required this.status,
    required this.fulfilment,
    required this.clinic,
    required this.createdAt,
    required this.lines,
    this.totalCents,
    this.isRefill = false,
  });
  final String id, status, fulfilment, clinic;
  final DateTime createdAt;
  final List<String> lines;
  final int? totalCents;
  final bool isRefill;
}

class ShopError implements Exception {
  const ShopError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Flat delivery: $7.99, free from $50 (the server applies the same rule).
int deliveryCents(int subtotalCents) => subtotalCents >= 5000 ? 0 : 799;

abstract class ShopRepository {
  Future<List<ShopProduct>> products();

  /// Places the order (the server prices and checks every line) and returns a single-use link to Stripe Checkout.
  Future<Uri> checkout(List<BagLine> lines, {required String fulfilment, required String clinicId});
  Future<List<ShopOrder>> orders();
}

class SupabaseShopRepository implements ShopRepository {
  SupabaseShopRepository(this._db);
  final SupabaseClient _db;

  @override
  Future<List<ShopProduct>> products() async {
    final results = await Future.wait([
      _db
          .from('shop_products')
          .select('id, name, category, summary, description, tags, price_cents, refill_interval_months, rule, image_key')
          .eq('active', true)
          .order('sort'),
      _db.from('shop_approvals').select('product_id, expires_on'),
    ]);
    final today = DateTime.now();
    final approved = {
      for (final a in results[1])
        if (DateTime.parse(a['expires_on'] as String).isAfter(today)) a['product_id'] as String,
    };
    return [
      for (final r in results[0])
        ShopProduct(
          id: r['id'] as String,
          name: r['name'] as String,
          category: r['category'] as String,
          summary: r['summary'] as String,
          description: r['description'] as String,
          tags: [for (final t in r['tags'] as List) t as String],
          priceCents: r['price_cents'] as int,
          refillMonths: r['refill_interval_months'] as int?,
          rule: r['rule'] as String,
          imageKey: r['image_key'] as String,
          approved: approved.contains(r['id']),
        ),
    ];
  }

  @override
  Future<Uri> checkout(List<BagLine> lines, {required String fulfilment, required String clinicId}) async {
    try {
      final orderId = await _db.rpc('create_shop_order', params: {
        'items': [for (final l in lines) {'product_id': l.product.id, 'quantity': l.quantity, 'refill': l.refill}],
        'fulfilment': fulfilment,
        'location': clinicId,
      }) as String;
      final token = await _db.rpc('shop_order_pay_link', params: {'order_id': orderId}) as String;
      return Uri.parse('$linkBase/shop?t=$token');
    } on PostgrestException catch (e) {
      // The server's own words for a refused rule (approval, exam, stock) are written for patients.
      throw ShopError(e.code == '42501' || e.code == '22023' ? e.message : 'We could not place the order. Please try again.');
    }
  }

  @override
  Future<List<ShopOrder>> orders() async {
    final rows = await _db
        .from('shop_orders')
        .select('id, status, fulfilment, total_cents, created_at, parent_order_id, locations(name), '
            'shop_order_items(quantity, shop_products(name))')
        .neq('status', 'expired')
        .neq('status', 'pending')
        .order('created_at', ascending: false);
    return [
      for (final r in rows)
        ShopOrder(
          id: r['id'] as String,
          status: r['status'] as String,
          fulfilment: r['fulfilment'] as String,
          clinic: clinicLabel((r['locations'] as Map?)?['name'] as String? ?? 'Northgate Dental'),
          createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
          totalCents: r['total_cents'] as int?,
          isRefill: r['parent_order_id'] != null,
          lines: [
            for (final i in r['shop_order_items'] as List)
              '${i['quantity']} × ${(i['shop_products'] as Map?)?['name'] ?? 'Item'}',
          ],
        ),
    ];
  }
}
