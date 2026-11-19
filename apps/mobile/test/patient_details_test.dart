import 'package:dental/data/account_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

Future<void> fillAddress(WidgetTester tester, {String zip = '02139'}) async {
  await tester.enterText(find.byKey(const Key('line1')), '12 Example Lane');
  await tester.enterText(find.byKey(const Key('city')), 'Cambridge');
  await tester.enterText(find.byKey(const Key('state')), 'ma');
  await tester.enterText(find.byKey(const Key('zip')), zip);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('after linking, the patient chooses a clinic and gives an address, then reaches home', (tester) async {
    final repo = await pumpApp(tester, FakeAccountRepository());
    await signIn(tester);
    await tester.enterText(find.byKey(const Key('code')), 'abcd1234efgh5678');
    await tapKey(tester, 'link');
    expect(find.text('Choose your clinic'), findsOneWidget);
    await tapKey(tester, 'clinic-cambridge');
    await fillAddress(tester);
    await tapKey(tester, 'save-details');
    expect(repo.saved, [
      ('p-elena', const PatientDetails(clinicId: 'cambridge', line1: '12 Example Lane', city: 'Cambridge', state: 'MA', zip: '02139')),
    ]);
    expect(find.text('Hello, Elena'), findsOneWidget);
  });

  testWidgets('an address that is missing or has a bad ZIP code is not saved', (tester) async {
    final repo = await pumpApp(tester, FakeAccountRepository(patients: [elenaNew]));
    await signIn(tester);
    expect(find.text('Choose your clinic'), findsOneWidget);
    await tapKey(tester, 'save-details');
    expect(find.text('Enter your street address.'), findsOneWidget);
    await fillAddress(tester, zip: '2139');
    await tapKey(tester, 'save-details');
    expect(find.text('Enter a 5-digit ZIP code.'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  testWidgets('Profile shows the clinic and address, and editing saves a new clinic', (tester) async {
    final repo = await pumpApp(tester, FakeAccountRepository(patients: [elena]));
    await signIn(tester);
    await tapKey(tester, 'tab-profile');
    expect(find.text('Back Bay'), findsOneWidget);
    expect(find.textContaining('1 Example Street'), findsOneWidget);
    await tapKey(tester, 'edit-details');
    expect(find.text('Clinic and address'), findsOneWidget);
    await tapKey(tester, 'clinic-quincy');
    await tapKey(tester, 'save-details');
    expect(repo.saved.single.$2.clinicId, 'quincy');
    expect(repo.saved.single.$2.line1, '1 Example Street', reason: 'the address already on file is kept');
    expect(find.text('Quincy'), findsOneWidget);
  });
}

const elena = LinkedPatient(id: 'p-elena', name: 'Elena Marsh', isSelf: true);
const elenaNew = LinkedPatient(id: 'p-elena', name: 'Elena Marsh', isSelf: true, detailsConfirmed: false);
