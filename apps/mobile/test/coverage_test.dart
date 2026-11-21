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
  await tapKey(tester, 'plan-picker');
  await tapKey(tester, 'plan-Harborline Dental PPO');
  await tester.enterText(find.byKey(const Key('member-id')), 'SYN123456');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a patient picks a plan, adds the member ID, saves without photos, and sees it waiting for review', (tester) async {
    final care = await openCoverage(tester);
    await fillCard(tester);
    await tapKey(tester, 'save-coverage');
    expect(care.calls, ['coverage:p-elena:plan-ppo:Harborline Dental PPO:SYN123456:front=0:back=0']);
    expect(find.text('Harborline Dental PPO'), findsOneWidget);
    expect(find.text('Checking your card'), findsOneWidget);
  });

  testWidgets('searching the list, and adding photos of both sides', (tester) async {
    final care = await openCoverage(tester);
    await tapKey(tester, 'plan-picker');
    await tester.enterText(find.byKey(const Key('plan-search')), 'mass');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan-Harborline Dental PPO')), findsNothing);
    await tapKey(tester, 'plan-MassHealth Dental');
    await tester.enterText(find.byKey(const Key('member-id')), 'SYN123456');
    await tapKey(tester, 'photo-front');
    await tapKey(tester, 'photo-camera');
    await tapKey(tester, 'photo-back');
    await tapKey(tester, 'photo-camera');
    await tapKey(tester, 'save-coverage');
    expect(care.calls, ['coverage:p-elena:plan-masshealth:MassHealth Dental:SYN123456:front=3:back=3']);
  });

  testWidgets('a plan that is not listed can be typed in', (tester) async {
    final care = await openCoverage(tester);
    await tapKey(tester, 'plan-picker');
    await tapKey(tester, 'plan-other');
    await tester.enterText(find.byKey(const Key('payer')), 'Small Employer Dental Trust');
    await tester.enterText(find.byKey(const Key('member-id')), 'SYN987');
    await tester.pumpAndSettle();
    await tapKey(tester, 'save-coverage');
    expect(care.calls, ['coverage:p-elena:none:Small Employer Dental Trust:SYN987:front=0:back=0']);
  });

  testWidgets('a card with no plan or no member ID is not saved', (tester) async {
    final care = await openCoverage(tester);
    await tapKey(tester, 'save-coverage');
    expect(find.text('Choose your insurance plan.'), findsOneWidget);
    expect(find.text('Enter the member ID from the card.'), findsOneWidget);
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
    expect(find.textContaining('could not save your card'), findsOneWidget);
    expect(find.byKey(const Key('save-coverage')), findsOneWidget);
  });
}
