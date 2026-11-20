import 'dart:typed_data';

import 'package:dental/data/account_repository.dart';
import 'package:dental/features/coverage_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

const elena = LinkedPatient(id: 'p-elena', name: 'Elena Marsh', isSelf: true);

Future<FakeCareRepository> openCoverage(WidgetTester tester, {FakeCareRepository? care}) async {
  final repo = care ?? FakeCareRepository();
  await pumpApp(
    tester,
    FakeAccountRepository(patients: [elena]),
    care: repo,
    extra: [
      photoPickerProvider.overrideWithValue((_) async => Uint8List.fromList([0xFF, 0xD8, 0xFF])),
    ],
  );
  await signIn(tester);
  await tapKey(tester, 'tab-profile');
  await tapKey(tester, 'add-coverage');
  return repo;
}

Future<void> fillCard(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('payer')), 'Delta Dental');
  await tester.enterText(find.byKey(const Key('member-id')), 'SYN123456');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a patient photographs both sides, saves, and sees the card waiting for review', (tester) async {
    final care = await openCoverage(tester);
    await fillCard(tester);
    await tapKey(tester, 'photo-front');
    await tapKey(tester, 'photo-camera');
    await tapKey(tester, 'photo-back');
    await tapKey(tester, 'photo-camera');
    await tapKey(tester, 'save-coverage');
    expect(care.calls, ['coverage:p-elena:Delta Dental:SYN123456:front=3:back=3']);
    expect(find.text('Delta Dental'), findsOneWidget);
    expect(find.text('Checking your card'), findsOneWidget);
  });

  testWidgets('missing details or photos are not saved', (tester) async {
    final care = await openCoverage(tester);
    await tapKey(tester, 'save-coverage');
    expect(find.text('Enter the insurance company.'), findsOneWidget);
    expect(find.text('Enter the member ID from the card.'), findsOneWidget);
    await fillCard(tester);
    await tapKey(tester, 'save-coverage');
    expect(find.text('Add a photo of the front and the back of the card.'), findsOneWidget);
    expect(care.calls, isEmpty);
  });

  testWidgets('a failed upload says so and keeps the form', (tester) async {
    await openCoverage(tester, care: FakeCareRepository()..failUpload = true);
    await fillCard(tester);
    for (final side in ['photo-front', 'photo-back']) {
      await tapKey(tester, side);
      await tapKey(tester, 'photo-camera');
    }
    await tapKey(tester, 'save-coverage');
    expect(find.textContaining('could not upload'), findsOneWidget);
    expect(find.byKey(const Key('save-coverage')), findsOneWidget);
  });
}
