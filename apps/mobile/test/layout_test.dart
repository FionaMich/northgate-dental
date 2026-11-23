// Layout check: every main screen on a small phone (360 x 780) with larger system text (1.3x), the way many
// patients set their phones. Any overflow ("RenderFlex overflowed") fails the test and names the screen.
import 'package:dental/data/care_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'appointments_test.dart' show elena, visitIn;
import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

final _details = <FlutterErrorDetails>[];

Future<List<String>> visit(WidgetTester tester, Future<void> Function() step, String name) async {
  _details.clear();
  final original = FlutterError.onError;
  FlutterError.onError = (d) => _details.add(d); // keep the full report, which names the widget's file and line
  try {
    await step();
  } finally {
    FlutterError.onError = original;
  }
  return [
    for (final d in _details)
      '$name: ${d.exceptionAsString().split('\n').first} '
          '(${RegExp(r'lib/[a-z_/]+\.dart:\d+').firstMatch(d.toString())?.group(0) ?? 'unknown place'})',
  ];
}

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('no screen overflows on a 360-wide phone at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(720, 1560);
      tester.view.devicePixelRatio = 2.0;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final care = FakeCareRepository({'p-elena': CareSummary(upcoming: [visitIn(3, 'a-1')])});
      await pumpApp(tester, FakeAccountRepository(patients: [elena]), care: care);
      final problems = <String>[];
      problems.addAll(await visit(tester, () => signIn(tester), 'home'));
      for (final tab in ['appointments', 'records', 'shop', 'profile']) {
        problems.addAll(await visit(tester, () => tapKey(tester, 'tab-$tab'), tab));
      }
      problems.addAll(await visit(tester, () => tapKey(tester, 'open-payments'), 'payments'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      problems.addAll(await visit(tester, () => tapKey(tester, 'open-orders'), 'orders'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapKey(tester, 'tab-shop');
      problems.addAll(await visit(tester, () => tapKey(tester, 'product-heads'), 'product'));
      problems.addAll(await visit(tester, () => tapKey(tester, 'add-to-bag'), 'shop after add'));
      problems.addAll(await visit(tester, () => tapKey(tester, 'open-bag'), 'bag'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapKey(tester, 'tab-home');
      problems.addAll(await visit(tester, () => tapKey(tester, 'open-assistant'), 'assistant'));
      expect(problems, isEmpty);
    });
  }
}
