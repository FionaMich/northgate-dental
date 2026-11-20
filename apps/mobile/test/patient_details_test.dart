import 'package:dental/data/account_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

Future<void> fillAddress(WidgetTester tester, {String line1 = '1 City Hall Sq', String zip = '02201'}) async {
  await tester.enterText(find.byKey(const Key('line1')), line1);
  await tester.enterText(find.byKey(const Key('city')), 'Boston');
  await tester.enterText(find.byKey(const Key('state')), 'ma');
  await tester.enterText(find.byKey(const Key('zip')), zip);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('after linking, the patient chooses a clinic and gives an address, then reaches home', (tester) async {
    final repo = await pumpApp(tester, FakeAccountRepository());
    await signIn(tester);
    await tester.enterText(find.byKey(const Key('dob')), '04121988');
    await tapKey(tester, 'link');
    expect(find.text('Choose your clinic'), findsOneWidget);
    await tapKey(tester, 'clinic-cambridge');
    await fillAddress(tester);
    await tapKey(tester, 'save-details');
    expect(repo.saved, isEmpty, reason: 'nothing is saved until the patient confirms the checked address');
    expect(find.text('Is this your address?'), findsOneWidget);
    await tapKey(tester, 'address-match-0');
    expect(repo.saved, [
      ('p-elena', const PatientDetails(clinicId: 'cambridge', line1: '1 City Hall Ave', city: 'Boston', state: 'MA', zip: '02108')),
    ], reason: 'the official form of the address is saved');
    expect(find.text('Hello, Elena'), findsOneWidget);
  });

  testWidgets('an address that does not exist is refused', (tester) async {
    final repo = await pumpApp(tester, FakeAccountRepository(patients: [elenaNew]));
    await signIn(tester);
    await fillAddress(tester, line1: '12 Example Lane');
    await tapKey(tester, 'save-details');
    expect(find.textContaining('could not find that address'), findsOneWidget);
    expect(repo.saved, isEmpty);
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
    await tester.enterText(find.byKey(const Key('zip')), '02201');
    await tester.pumpAndSettle();
    expect(find.text('Enter a 5-digit ZIP code.'), findsNothing, reason: 'errors clear as soon as the field is fixed');
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
    expect(repo.saved.single.$2.line1, '1 Example Street', reason: 'the address already on file is kept, without a new check');
    expect(find.text('Quincy'), findsOneWidget);
  });
}

const elena = LinkedPatient(id: 'p-elena', name: 'Elena Marsh', isSelf: true);
const elenaNew = LinkedPatient(id: 'p-elena', name: 'Elena Marsh', isSelf: true, detailsConfirmed: false);
