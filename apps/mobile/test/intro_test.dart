import 'package:dental/app.dart';
import 'package:dental/features/aligner_screen.dart';
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
        wearStoreProvider.overrideWithValue(MemoryWearStore()),
        alignerRemindersProvider.overrideWithValue(FakeAlignerReminders()),
      ],
      child: const NorthgateApp(),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('the intro shows the brand, then stays for a minute, then hands over to sign-in', (tester) async {
    await pumpWithIntro(tester);
    expect(find.text('Healthy smiles across Boston'), findsOneWidget);
    await tester.pump(const Duration(seconds: 59));
    expect(find.text('Healthy smiles across Boston'), findsOneWidget, reason: 'still showing just before the minute');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sign-in')), findsOneWidget);
  });

  testWidgets('a tap continues to the next screen straight away', (tester) async {
    await pumpWithIntro(tester);
    await tester.tap(find.byType(IntroScreen));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sign-in')), findsOneWidget);
  });
}
