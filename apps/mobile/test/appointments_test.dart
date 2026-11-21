import 'package:dental/data/account_repository.dart';
import 'package:dental/data/care_repository.dart';
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
  testWidgets('Visits lists every booked visit, not just the next one', (tester) async {
    final care = FakeCareRepository({
      'p-elena': CareSummary(upcoming: [visitIn(3, 'a-1'), visitIn(20, 'a-2')]),
    });
    await pumpApp(tester, FakeAccountRepository(patients: [elena]), care: care);
    await signIn(tester);
    await tapKey(tester, 'tab-appointments');
    expect(find.byKey(const Key('upcoming-a-1')), findsOneWidget);
    expect(find.byKey(const Key('upcoming-a-2')), findsOneWidget);
  });

  testWidgets('rescheduling books the new time first, then cancels the old visit', (tester) async {
    final care = FakeCareRepository({
      'p-elena': CareSummary(upcoming: [visitIn(3, 'a-1')]),
    });
    await pumpApp(tester, FakeAccountRepository(patients: [elena]), care: care);
    await signIn(tester);
    await tapKey(tester, 'tab-appointments');
    await tapKey(tester, 'reschedule-a-1');
    expect(find.text('Book a visit'), findsOneWidget);
    await tapKey(tester, 'day-0');
    await tapKey(tester, 'slot-0');
    await tapTicking(tester, 'hold');
    await tapTicking(tester, 'confirm-booking');
    await tapKey(tester, 'booking-done');
    expect(care.calls, [
      'hold:back-bay:cleaning',
      'confirm:a-1',
      'cancel:a-1',
    ], reason: 'old visit cancelled only after the new one is confirmed');
    expect(care.heldWith, 'dr-1', reason: 'same dentist as before');
  });
}
