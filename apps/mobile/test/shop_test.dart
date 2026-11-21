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
}
