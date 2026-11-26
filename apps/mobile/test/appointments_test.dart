import 'package:dental/data/account_repository.dart';
import 'package:dental/data/care_repository.dart';
import 'package:dental/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'booking_test.dart' show tapTicking;
import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

const elena = LinkedPatient(id: 'p-elena', name: 'Elena Marsh', isSelf: true);

Appointment visitIn(int days, String id) {
  final at = DateTime.now().add(Duration(days: days));
  return Appointment(
    id: id,
    startsAt: DateTime(at.year, at.month, at.day, 10),
    endsAt: DateTime(at.year, at.month, at.day, 11),
    service: 'Adult cleaning',
    location: 'Back Bay',
    status: 'booked',
    clinicId: 'back-bay',
    serviceId: 'cleaning',
    dentistId: 'dr-1',
    dentist: 'Priya Raman, RDH',
  );
}

void main() {
  testWidgets('Visits lists every booked visit, not just the next one', (
    tester,
  ) async {
    final care = FakeCareRepository({
      'p-elena': CareSummary(upcoming: [visitIn(3, 'a-1'), visitIn(20, 'a-2')]),
    });
    await pumpApp(tester, FakeAccountRepository(patients: [elena]), care: care);
    await signIn(tester);
    await tapKey(tester, 'tab-appointments');
    expect(find.byKey(const Key('upcoming-a-1')), findsOneWidget);
    expect(find.byKey(const Key('upcoming-a-2')), findsOneWidget);
  });

  testWidgets(
    'rescheduling moves the visit in one step: the new time is booked and the old visit cancelled together',
    (tester) async {
      final care = FakeCareRepository({
        'p-elena': CareSummary(upcoming: [visitIn(3, 'a-1')]),
      });
      await pumpApp(
        tester,
        FakeAccountRepository(patients: [elena]),
        care: care,
      );
      await signIn(tester);
      await tapKey(tester, 'tab-appointments');
      await tapKey(tester, 'reschedule-a-1');
      expect(find.text('Book a visit'), findsOneWidget);
      await tapKey(tester, 'day-0');
      await tapKey(tester, 'slot-0');
      await tapTicking(tester, 'hold');
      await tapTicking(tester, 'confirm-booking');
      await tapKey(tester, 'booking-done');
      expect(
        care.calls,
        ['hold:back-bay:cleaning', 'reschedule:a-1 replaces a-1'],
        reason: 'one database step, so the patient gets one "your visit has moved" email and never two visits',
      );
      expect(care.heldWith, 'dr-1', reason: 'same dentist as before');
    },
  );

  testWidgets(
    'a booked video consultation has a Join button that opens that visit\'s room; a cleaning has none',
    (tester) async {
      final soon = DateTime.now().add(const Duration(hours: 2));
      final video = Appointment(
        id: 'v-1',
        startsAt: soon,
        endsAt: soon.add(const Duration(minutes: 20)),
        service: 'Video consultation',
        location: 'Quincy',
        status: 'booked',
        serviceCode: 'D9995',
      );
      final consult = FakeConsultRepository(available: false);
      final care = FakeCareRepository({
        'p-elena': CareSummary(upcoming: [video, visitIn(3, 'a-1')]),
      });
      await pumpApp(
        tester,
        FakeAccountRepository(patients: [elena]),
        care: care,
        extra: [consultRepositoryProvider.overrideWithValue(consult)],
      );
      await signIn(tester);
      await tapKey(tester, 'tab-appointments');
      expect(find.byKey(const Key('join-video-a-1')), findsNothing);
      await tapKey(tester, 'join-video-v-1');
      expect(consult.asked, ['v-1'], reason: 'the room is the visit\'s own');
      expect(
        find.textContaining('Video consultations are unavailable'),
        findsOneWidget,
      );
      expect(
        video.canJoinAt(soon.add(const Duration(minutes: 30))),
        isFalse,
        reason: 'the room closes when the visit ends',
      );
    },
  );
}
