import 'package:dental/data/account_repository.dart';
import 'package:dental/data/care_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

const elena = LinkedPatient(id: 'p-elena', name: 'Elena Marsh', isSelf: true);

Future<FakeCareRepository> openBooking(
  WidgetTester tester, {
  FakeCareRepository? care,
}) async {
  final repo = care ?? FakeCareRepository();
  await pumpApp(tester, FakeAccountRepository(patients: [elena]), care: repo);
  await signIn(tester);
  await tapKey(tester, 'book-visit');
  return repo;
}

Future<void> pickFirstTime(WidgetTester tester) async {
  await tapKey(tester, 'service-cleaning');
  await tapKey(tester, 'day-0');
  await tapKey(tester, 'slot-0');
}

/// The hold sheet's countdown ticks every second, so the screen never settles; wait a few frames instead.
Future<void> tapTicking(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets(
    'a patient picks a service, day and time, holds it, confirms, and sees the visit on Home',
    (tester) async {
      final care = await openBooking(tester);
      expect(find.text('Book a visit'), findsOneWidget);
      expect(
        find.text('Back Bay'),
        findsWidgets,
        reason: 'booking starts at the preferred clinic',
      );
      expect(
        find.textContaining('removes plaque and tartar'),
        findsOneWidget,
        reason: 'each service says what happens',
      );
      await pickFirstTime(tester);
      await tapTicking(tester, 'hold');
      expect(care.calls, ['hold:back-bay:cleaning']);
      expect(find.textContaining('Held for you'), findsOneWidget);
      await tapTicking(tester, 'confirm-booking');
      expect(care.calls.last, 'confirm:a-1');
      expect(find.text('You are booked'), findsOneWidget);
      await tapKey(tester, 'booking-done');
      expect(find.text('Next visit'), findsOneWidget);
    },
  );

  testWidgets(
    'a time someone else just took is refused and the patient picks again',
    (tester) async {
      final care = await openBooking(
        tester,
        care: FakeCareRepository()..takeNextHold = true,
      );
      await pickFirstTime(tester);
      await tapKey(tester, 'hold');
      expect(find.text(slotTakenError), findsOneWidget);
      expect(care.calls.where((c) => c.startsWith('confirm')), isEmpty);
    },
  );

  testWidgets(
    'when the 10-minute hold runs out, Confirm switches off and nothing is booked',
    (tester) async {
      final care = await openBooking(tester);
      await pickFirstTime(tester);
      await tapTicking(tester, 'hold');
      for (var i = 0; i < 601; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.textContaining('hold has run out'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('confirm-booking')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(care.calls.where((c) => c.startsWith('confirm')), isEmpty);
    },
  );

  testWidgets(
    'a booked visit can be cancelled from Home after a confirmation',
    (tester) async {
      final care = FakeCareRepository({
        'p-elena': CareSummary(
          upcoming: [
            Appointment(
              id: 'a-9',
              startsAt: DateTime.now().add(const Duration(days: 3)),
              endsAt: DateTime.now().add(const Duration(days: 3, hours: 1)),
              service: 'Adult cleaning',
              location: 'Back Bay',
              status: 'booked',
            ),
          ],
        ),
      });
      await pumpApp(
        tester,
        FakeAccountRepository(patients: [elena]),
        care: care,
      );
      await signIn(tester);
      await tapKey(tester, 'cancel-visit');
      await tapKey(tester, 'keep-visit');
      expect(care.calls, isEmpty);
      await tapKey(tester, 'cancel-visit');
      await tapKey(tester, 'confirm-cancel');
      expect(care.calls, ['cancel:a-9']);
      expect(find.text('No visit booked'), findsOneWidget);
    },
  );

  testWidgets(
    'choosing a dentist shows only their times, and their profile is a tap away',
    (tester) async {
      final care = await openBooking(tester);
      await tapKey(tester, 'service-cleaning');
      expect(find.text('Choose your dentist'), findsOneWidget);
      expect(find.text('Any available dentist'), findsOneWidget);
      await tapKey(tester, 'dentist-dr-2');
      await tapKey(tester, 'day-0');
      expect(find.byKey(const Key('slot-0')), findsOneWidget);
      expect(
        find.byKey(const Key('slot-1')),
        findsNothing,
        reason: 'Dr Brooks has one free time in the test data',
      );
      await tapKey(tester, 'slot-0');
      await tapTicking(tester, 'hold');
      expect(care.calls, ['hold:back-bay:cleaning']);
      expect(care.heldWith, 'dr-2');
    },
  );

  testWidgets(
    'a dentist profile shows who they are and offers booking with them',
    (tester) async {
      await openBooking(tester);
      await tapKey(tester, 'service-cleaning');
      await tester.scrollUntilVisible(
        find.byTooltip('About Dr Hannah Brooks'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byTooltip('About Dr Hannah Brooks'));
      await tester.pumpAndSettle();
      expect(find.text('Hannah looks after the whole family.'), findsOneWidget);
      expect(find.byKey(const Key('book-with-dentist')), findsOneWidget);
    },
  );

  testWidgets('services can be searched and filtered by group', (tester) async {
    await openBooking(tester);
    await tester.enterText(find.byKey(const Key('service-search')), 'exam');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('service-exam')), findsOneWidget);
    expect(find.byKey(const Key('service-cleaning')), findsNothing);
    await tester.enterText(find.byKey(const Key('service-search')), '');
    await tapKey(tester, 'category-Check-ups');
    expect(
      find.byKey(const Key('service-exam')),
      findsOneWidget,
      reason: 'an exam is a check-up',
    );
  });
}
