import 'package:dental/app.dart';
import 'package:dental/features/aligner_screen.dart';
import 'package:dental/data/account_repository.dart';
import 'package:dental/features/intro_screen.dart';
import 'package:dental/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

Future<FakeAccountRepository> pumpApp(
  WidgetTester tester,
  FakeAccountRepository repo, {
  FakeCareRepository? care,
  MemoryWearStore? wear,
  FakeAlignerReminders? reminders,
  List<dynamic> extra = const [],
}) async {
  // Tests run with the phone's reduce-motion setting on, as some patients will; the floating art then stays still.
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(repo),
        careRepositoryProvider.overrideWithValue(care ?? FakeCareRepository()),
        introDurationProvider.overrideWithValue(Duration.zero),
        wearStoreProvider.overrideWithValue(wear ?? MemoryWearStore()),
        alignerRemindersProvider.overrideWithValue(reminders ?? FakeAlignerReminders()),
        ...extra,
      ],
      child: const NorthgateApp(),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// Scrolls the control into view first, as a person would, then taps it.
Future<void> tapKey(WidgetTester tester, String key) async {
  // Lists build lazily, so a control far down may not exist until the list scrolls towards it.
  if (find.byKey(Key(key)).evaluate().isEmpty) {
    await tester.scrollUntilVisible(find.byKey(Key(key)), 200, scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> signIn(WidgetTester tester, {String password = 'right'}) async {
  await tester.enterText(find.byKey(const Key('email')), 'patient@northgate.synthetic');
  await tester.enterText(find.byKey(const Key('password')), password);
  await tester.ensureVisible(find.byKey(const Key('sign-in')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('sign-in')));
  await tester.pumpAndSettle();
  // Second factor: the 6-digit code from the email (the fake always sends 123456).
  if (find.byKey(const Key('code-input')).evaluate().isNotEmpty) {
    await tester.enterText(find.byKey(const Key('code-input')), '123456');
    await tester.pumpAndSettle();
  }
}

void main() {
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

  testWidgets('an unlinked patient confirms their date of birth, with no front-desk code, then sees their name', (tester) async {
    await pumpApp(tester, FakeAccountRepository());
    await signIn(tester);
    expect(find.text('Find your record'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('dob')), '04121988');
    expect(find.text('04/12/1988'), findsOneWidget, reason: 'the slashes are added while typing');
    await tapKey(tester, 'link');
    expect(find.textContaining('Elena'), findsWidgets);
  });

  testWidgets('a wrong date of birth is refused, and five misses lock the route', (tester) async {
    final repo = await pumpApp(tester, FakeAccountRepository());
    await signIn(tester);
    await tester.enterText(find.byKey(const Key('dob')), '01011990');
    await tapKey(tester, 'link');
    expect(find.textContaining('could not find a record'), findsOneWidget);
    repo.birthDateMisses = 5;
    await tester.enterText(find.byKey(const Key('dob')), '04121988');
    await tapKey(tester, 'link');
    expect(find.textContaining('Too many tries'), findsOneWidget);
    expect(repo.patients, isEmpty);
  });

  testWidgets('a new patient registers, with no front-desk code, and is asked for a clinic', (tester) async {
    final repo = await pumpApp(tester, FakeAccountRepository());
    await signIn(tester);
    expect(find.byKey(const Key('code')), findsNothing, reason: 'the front-desk code is gone');
    await tapKey(tester, 'patient-kind');
    await tester.tap(find.text('I am new'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('given-name')), 'Jordan');
    await tester.enterText(find.byKey(const Key('family-name')), 'Lee');
    await tester.enterText(find.byKey(const Key('dob')), '05011990');
    await tapKey(tester, 'sex-male');
    await tapKey(tester, 'link');
    expect(repo.registered, ['Jordan Lee 1990-5-1 male']);
    expect(find.text('Choose your clinic'), findsOneWidget);
  });

  testWidgets('an under-18 cannot register in the app', (tester) async {
    final repo = await pumpApp(tester, FakeAccountRepository());
    await signIn(tester);
    await tester.tap(find.text('I am new'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('given-name')), 'Young');
    await tester.enterText(find.byKey(const Key('family-name')), 'Person');
    final teen = DateTime.now().subtract(const Duration(days: 365 * 15));
    await tester.enterText(
      find.byKey(const Key('dob')),
      '${teen.month.toString().padLeft(2, '0')}${teen.day.toString().padLeft(2, '0')}${teen.year}',
    );
    await tapKey(tester, 'sex-female');
    await tapKey(tester, 'link');
    expect(find.textContaining('registered by a parent or guardian'), findsOneWidget);
    expect(repo.registered, isEmpty);
  });

  testWidgets('a parent switches between themselves and a child (E40)', (tester) async {
    await pumpApp(
      tester,
      FakeAccountRepository(
        patients: const [
          LinkedPatient(id: 'p-ana', name: 'Ana Reyes', isSelf: true),
          LinkedPatient(id: 'p-sofia', name: 'Sofia Reyes', isSelf: false),
        ],
      ),
    );
    await signIn(tester);
    expect(find.text('Hello, Ana'), findsOneWidget);
    await tapKey(tester, 'person-p-sofia');
    expect(find.text('Hello, Sofia'), findsOneWidget);
  });

  testWidgets('signing out returns to the sign-in screen (E39)', (tester) async {
    final repo = await pumpApp(
      tester,
      FakeAccountRepository(
        patients: const [LinkedPatient(id: 'p-elena', name: 'Elena Marsh', isSelf: true)],
      ),
    );
    await signIn(tester);
    await tapKey(tester, 'tab-profile');
    await tapKey(tester, 'sign-out');
    await tapKey(tester, 'confirm-sign-out');
    expect(repo.signOutCalls, 1);
    expect(find.byKey(const Key('sign-in')), findsOneWidget);
    expect(find.textContaining('signed out'), findsOneWidget);
  });
}
