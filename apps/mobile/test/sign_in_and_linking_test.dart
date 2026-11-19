import 'package:dental/app.dart';
import 'package:dental/data/account_repository.dart';
import 'package:dental/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

Future<FakeAccountRepository> pumpApp(WidgetTester tester, FakeAccountRepository repo) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [accountRepositoryProvider.overrideWithValue(repo)],
    child: const NorthgateApp(),
  ));
  await tester.pumpAndSettle();
  return repo;
}

Future<void> signIn(WidgetTester tester, {String password = 'right'}) async {
  await tester.enterText(find.byKey(const Key('email')), 'patient@northgate.synthetic');
  await tester.enterText(find.byKey(const Key('password')), password);
  await tester.tap(find.byKey(const Key('sign-in')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every screen says the data is synthetic', (tester) async {
    await pumpApp(tester, FakeAccountRepository());
    expect(find.textContaining('Synthetic data'), findsOneWidget);
  });

  testWidgets('a wrong password shows a plain message', (tester) async {
    await pumpApp(tester, FakeAccountRepository());
    await signIn(tester, password: 'wrong');
    expect(find.text('That email and password do not match.'), findsOneWidget);
  });

  testWidgets('a staff account is refused in the patient app', (tester) async {
    await pumpApp(tester, FakeAccountRepository(role: 'receptionist'));
    await signIn(tester);
    expect(find.textContaining('Staff accounts'), findsOneWidget);
    expect(find.byKey(const Key('sign-in')), findsOneWidget);
  });

  testWidgets('an unlinked patient is asked for the front desk code, then sees their name', (tester) async {
    await pumpApp(tester, FakeAccountRepository());
    await signIn(tester);
    expect(find.text('Link your record'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('code')), 'abcd1234efgh5678');
    await tester.tap(find.byKey(const Key('link')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Elena'), findsWidgets);
  });

  testWidgets('a wrong code is refused with advice', (tester) async {
    await pumpApp(tester, FakeAccountRepository());
    await signIn(tester);
    await tester.enterText(find.byKey(const Key('code')), 'NOPE');
    await tester.tap(find.byKey(const Key('link')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ask the front desk'), findsOneWidget);
  });

  testWidgets('a parent switches between themselves and a child (E40)', (tester) async {
    await pumpApp(tester, FakeAccountRepository(patients: const [
      LinkedPatient(id: 'p-ana', name: 'Ana Reyes', isSelf: true),
      LinkedPatient(id: 'p-sofia', name: 'Sofia Reyes', isSelf: false),
    ]));
    await signIn(tester);
    expect(find.text('Hello, Ana'), findsOneWidget);
    await tester.tap(find.byKey(const Key('person-p-sofia')));
    await tester.pumpAndSettle();
    expect(find.text('Hello, Sofia'), findsOneWidget);
  });

  testWidgets('signing out returns to the sign-in screen (E39)', (tester) async {
    final repo = await pumpApp(tester, FakeAccountRepository(patients: const [LinkedPatient(id: 'p-elena', name: 'Elena Marsh', isSelf: true)]));
    await signIn(tester);
    await tester.tap(find.byKey(const Key('sign-out')));
    await tester.pumpAndSettle();
    expect(repo.signOutCalls, 1);
    expect(find.byKey(const Key('sign-in')), findsOneWidget);
  });
}
