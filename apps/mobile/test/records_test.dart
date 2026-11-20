import 'package:dental/data/account_repository.dart';
import 'package:dental/data/care_repository.dart';
import 'package:dental/features/visit_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

const elena = LinkedPatient(id: 'p-elena', name: 'Elena Marsh', isSelf: true);

final visit = Visit(
  id: 'v-1',
  at: DateTime(2026, 8, 22, 10),
  kind: 'exam',
  location: 'Cambridge',
  dentist: 'Dr Amara Okafor',
  reason: 'Six-monthly check-up',
  procedures: const [
    Procedure(service: 'Comprehensive oral exam', status: 'completed', feeCents: 14000),
    Procedure(service: 'Composite filling, one surface', status: 'planned', tooth: '14', surface: 'O', feeCents: 21000),
  ],
  findings: const [
    Finding(tooth: '14', surface: 'O', condition: 'caries'),
    Finding(tooth: '3', condition: 'filled'),
  ],
);

final docs = [
  PracticeDocument(
    id: 'd-1',
    encounterId: 'v-1',
    kind: 'xray',
    title: 'Bitewing X-rays, 2026-08-22',
    path: 'p-elena/v-1-bitewing.png',
    contentType: 'image/png',
    sharedAt: DateTime(2026, 8, 22),
  ),
  PracticeDocument(
    id: 'd-2',
    encounterId: 'v-1',
    kind: 'visit_summary',
    title: 'Visit summary, 2026-08-22',
    path: 'p-elena/v-1-summary.pdf',
    contentType: 'application/pdf',
    sharedAt: DateTime(2026, 8, 22),
  ),
];

Future<(FakeCareRepository, List<String>)> openRecords(WidgetTester tester) async {
  final opened = <String>[];
  final care = FakeCareRepository({
    'p-elena': CareSummary(visits: [visit], documents: docs),
  });
  await pumpApp(
    tester,
    FakeAccountRepository(patients: [elena]),
    care: care,
    extra: [documentOpenerProvider.overrideWithValue((url) async => opened.add(url))],
  );
  await signIn(tester);
  await tapKey(tester, 'tab-records');
  return (care, opened);
}

void main() {
  testWidgets('a visit opens with the dentist, reason, tooth chart, what was done with fees, and findings', (tester) async {
    await openRecords(tester);
    await tapKey(tester, 'visit-v-1');
    expect(find.text('Dr Amara Okafor'), findsOneWidget);
    expect(find.text('Six-monthly check-up'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Tooth 14: treatment planned, finding')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Tooth 3: finding')), findsOneWidget);
    expect(find.textContaining('tooth 14, top surface'), findsWidgets);
    expect(find.text('\$210.00'), findsOneWidget);
    expect(find.text('Decay'), findsOneWidget);
    expect(find.text('\$350.00'), findsOneWidget, reason: 'the total of the visit');
  });

  testWidgets('documents from the practice are listed and open through a short-lived link', (tester) async {
    final (care, opened) = await openRecords(tester);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Visit summary, 2026-08-22'), findsOneWidget);
    await tapKey(tester, 'doc-d-2');
    expect(care.calls, ['link:p-elena/v-1-summary.pdf']);
    expect(opened, ['https://files.test/p-elena/v-1-summary.pdf?token=short']);
  });

  testWidgets('an X-ray opens in the app viewer', (tester) async {
    final (care, _) = await openRecords(tester);
    await tapKey(tester, 'doc-d-1');
    expect(care.calls, ['link:p-elena/v-1-bitewing.png']);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });
}
