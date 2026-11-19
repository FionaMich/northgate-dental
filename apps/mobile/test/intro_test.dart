import 'package:dental/app.dart';
import 'package:dental/features/intro_screen.dart';
import 'package:dental/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

Future<void> pumpWithIntro(WidgetTester tester) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
        careRepositoryProvider.overrideWithValue(FakeCareRepository()),
      ],
      child: const NorthgateApp(),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('the intro shows the brand, then hands over to sign-in after 5 seconds', (tester) async {
    await pumpWithIntro(tester);
    expect(find.text('Healthy smiles across Boston'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sign-in')), findsOneWidget);
  });

  testWidgets('a tap skips the intro straight away', (tester) async {
    await pumpWithIntro(tester);
    await tester.tap(find.byType(IntroScreen));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sign-in')), findsOneWidget);
  });
}
