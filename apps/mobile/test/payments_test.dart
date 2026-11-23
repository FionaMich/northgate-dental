import 'package:dental/data/care_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'appointments_test.dart' show elena, visitIn;
import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

Appointment priced(int days, String id) {
  final a = visitIn(days, id);
  return Appointment(
    id: a.id,
    startsAt: a.startsAt,
    endsAt: a.endsAt,
    service: a.service,
    location: a.location,
    status: a.status,
    priceCents: 11000,
  );
}

void main() {
  testWidgets('a booked visit shows its price and a Pay now button', (
    tester,
  ) async {
    final care = FakeCareRepository({
      'p-elena': CareSummary(upcoming: [priced(3, 'a-1')]),
    });
    await pumpApp(tester, FakeAccountRepository(patients: [elena]), care: care);
    await signIn(tester);
    await tapKey(tester, 'tab-appointments');
    expect(find.textContaining('\$110.00', findRichText: true), findsOneWidget);
    expect(find.byKey(const Key('pay-visit-a-1')), findsOneWidget);
  });

  testWidgets('a paid visit shows Paid instead of a button', (tester) async {
    final care = FakeCareRepository({
      'p-elena': CareSummary(
        upcoming: [priced(3, 'a-1')],
        payments: [
          Payment(
            id: 'pay-1',
            appointmentId: 'a-1',
            amountCents: 11000,
            status: 'paid',
            service: 'Adult cleaning',
            location: 'Back Bay',
            visitAt: DateTime.now(),
            paidAt: DateTime.now(),
          ),
        ],
      ),
    });
    await pumpApp(tester, FakeAccountRepository(patients: [elena]), care: care);
    await signIn(tester);
    await tapKey(tester, 'tab-appointments');
    expect(find.byKey(const Key('pay-visit-a-1')), findsNothing);
    expect(find.text('Paid'), findsOneWidget);
  });

  testWidgets('Profile opens Payments with what is due and the receipts', (
    tester,
  ) async {
    final care = FakeCareRepository({
      'p-elena': CareSummary(
        upcoming: [priced(3, 'a-1')],
        payments: [
          Payment(
            id: 'pay-0',
            appointmentId: 'old',
            amountCents: 9500,
            status: 'paid',
            service: 'Exam',
            location: 'Quincy',
            visitAt: DateTime(2026, 10, 1),
            paidAt: DateTime(2026, 10, 1),
          ),
        ],
      ),
    });
    await pumpApp(tester, FakeAccountRepository(patients: [elena]), care: care);
    await signIn(tester);
    await tapKey(tester, 'tab-profile');
    await tapKey(tester, 'open-payments');
    expect(find.byKey(const Key('due-a-1')), findsOneWidget);
    expect(find.byKey(const Key('receipt-pay-0')), findsOneWidget);
    expect(find.text('\$95.00'), findsOneWidget);
  });
}
