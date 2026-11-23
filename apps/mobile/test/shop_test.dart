import 'package:dental/data/shop_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'appointments_test.dart' show elena;
import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

void main() {
  testWidgets('a patient adds a brush and refill heads, chooses delivery and checks out', (tester) async {
    final shop = FakeShopRepository();
    await pumpApp(tester, FakeAccountRepository(patients: [elena]), shop: shop);
    await signIn(tester);
    await tapKey(tester, 'tab-shop');
    expect(find.text('Sonic electric toothbrush'), findsOneWidget);

    await tapKey(tester, 'product-brush');
    await tapKey(tester, 'add-to-bag');
    await tapKey(tester, 'product-heads');
    expect(find.byKey(const Key('choose-refill')), findsOneWidget, reason: 'refills are offered where they make sense');
    await tapKey(tester, 'add-to-bag');

    await tapKey(tester, 'open-bag');
    expect(find.text('\$93.00'), findsWidgets);
    await tapKey(tester, 'fulfil-ship');
    expect(find.text('Free'), findsWidgets, reason: 'delivery is free from \$50');
    await tester.tap(find.byKey(const Key('checkout')));
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException(); // the browser plugin is not available in tests
    expect(shop.placed.single, startsWith('ship:'));
    expect(shop.placed.single, endsWith('brushx1,headsx1r'), reason: 'quantities and refill choice go to the server, never prices');
  });

  testWidgets('a prescription-strength product cannot be added without the dentist\'s approval', (tester) async {
    await pumpApp(tester, FakeAccountRepository(patients: [elena]), shop: FakeShopRepository());
    await signIn(tester);
    await tapKey(tester, 'tab-shop');
    await tester.scrollUntilVisible(find.byKey(const Key('product-fluoride')), 200, scrollable: find.byType(Scrollable).first);
    await tapKey(tester, 'product-fluoride');
    expect(find.text('Ask your dentist'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('add-to-bag'))).onPressed, isNull);
  });

  testWidgets('the category row scrolls sideways and its chips filter the shop', (tester) async {
    tester.view.physicalSize = const Size(720, 1560);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const items = [
      ShopProduct(id: 'b', name: 'Brush', category: 'brush', summary: 's', description: 'd', priceCents: 100, imageKey: 'x'),
      ShopProduct(id: 'f', name: 'Floss', category: 'clean_between', summary: 's', description: 'd', priceCents: 100, imageKey: 'x'),
      ShopProduct(id: 'p', name: 'Paste', category: 'paste_and_rinse', summary: 's', description: 'd', priceCents: 100, imageKey: 'x'),
      ShopProduct(id: 'a', name: 'Chewies', category: 'aligners', summary: 's', description: 'd', priceCents: 100, imageKey: 'x'),
      ShopProduct(id: 'k', name: 'Kids kit', category: 'kids', summary: 's', description: 'd', priceCents: 100, imageKey: 'x'),
      ShopProduct(id: 'w', name: 'Whitening kit', category: 'whitening', summary: 's', description: 'd', priceCents: 100, imageKey: 'x'),
    ];
    await pumpApp(tester, FakeAccountRepository(patients: [elena]), shop: FakeShopRepository(items: items));
    await signIn(tester);
    await tapKey(tester, 'tab-shop');
    final whitening = find.byKey(const Key('category-whitening'));
    expect(whitening, findsNothing, reason: 'the last chips start off-screen, beyond the right edge');
    await tester.scrollUntilVisible(whitening, 120,
        scrollable: find.descendant(of: find.byKey(const Key('shop-categories')), matching: find.byType(Scrollable)));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(whitening).dx, lessThan(360), reason: 'swiping the row brings it into view');
    await tester.tap(whitening);
    await tester.pumpAndSettle();
    expect(find.text('Whitening kit'), findsOneWidget);
    expect(find.text('Brush'), findsNothing, reason: 'the chip filters the products');
  });
}
