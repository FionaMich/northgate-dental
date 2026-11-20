import 'package:dental/data/account_repository.dart';
import 'package:dental/data/wear_log.dart';
import 'package:dental/features/aligner_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

const elena = LinkedPatient(id: 'p-elena', name: 'Elena Marsh', isSelf: true);

void main() {
  group('daily wear total', () {
    final today = DateTime(2026, 11, 20);
    test('counts finished and running sessions up to now', () {
      final log = WearLog([
        (today.add(const Duration(hours: 1)), today.add(const Duration(hours: 7))),
        (today.add(const Duration(hours: 8)), null),
      ]);
      expect(log.wornOn(today, now: today.add(const Duration(hours: 10, minutes: 30))), const Duration(hours: 8, minutes: 30));
      expect(log.wearing, isTrue);
    });

    test('a session across midnight counts only its part of each day', () {
      final log = WearLog([(today.subtract(const Duration(hours: 1)), today.add(const Duration(hours: 2)))]);
      expect(log.wornOn(today, now: today.add(const Duration(hours: 12))), const Duration(hours: 2));
      expect(log.wornOn(today.subtract(const Duration(days: 1)), now: today), const Duration(hours: 1));
    });

    test('survives a round trip through storage', () {
      final log = WearLog([(today, today.add(const Duration(hours: 3))), (today.add(const Duration(hours: 4)), null)]);
      expect(WearLog.decode(log.encode()).wornOn(today, now: today.add(const Duration(hours: 5))), const Duration(hours: 4));
    });
  });

  testWidgets('a patient puts aligners in, takes them out later, and sees today against 22 hours', (tester) async {
    var now = DateTime(2026, 11, 20, 8);
    final store = MemoryWearStore();
    final reminders = FakeAlignerReminders();
    await pumpApp(
      tester,
      FakeAccountRepository(patients: [elena]),
      wear: store,
      reminders: reminders,
      extra: [clockProvider.overrideWithValue(() => now)],
    );
    await signIn(tester);
    await tapKey(tester, 'tab-profile');
    await tapKey(tester, 'open-aligner');
    expect(find.text('0h 0m'), findsOneWidget);
    await tapKey(tester, 'wear-toggle');
    expect(find.text('Aligners in'), findsOneWidget);
    now = DateTime(2026, 11, 20, 10, 30);
    await tapKey(tester, 'wear-toggle');
    expect(find.text('2h 30m'), findsOneWidget);
    expect(find.text('of 22h today'), findsOneWidget);
    expect(store.values.keys, ['aligner:p-elena'], reason: 'kept on the phone, per person');
    expect(reminders.calls.where((c) => c != 'clear'), [
      'in',
      'out:10:30',
    ], reason: 'putting them in cancels reminders; taking them out schedules them');
  });

  testWidgets('signing out removes the wear log and its reminders from the phone', (tester) async {
    final store = MemoryWearStore()..values['aligner:p-elena'] = '[]';
    final reminders = FakeAlignerReminders();
    final repo = await pumpApp(
      tester,
      FakeAccountRepository(patients: [elena]),
      wear: store,
      reminders: reminders,
    );
    await signIn(tester);
    await repo.signOut();
    await tester.pumpAndSettle();
    expect(store.values, isEmpty);
    expect(reminders.calls, contains('clear'), reason: 'pending reminders are removed too');
  });
}
