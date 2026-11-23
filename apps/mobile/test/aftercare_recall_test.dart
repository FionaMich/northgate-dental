import 'package:dental/data/account_repository.dart';
import 'package:dental/data/aftercare.dart';
import 'package:dental/data/care_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

const elena = LinkedPatient(id: 'p-elena', name: 'Elena Marsh', isSelf: true);

Visit visitOn(DateTime at, String kind, List<String> done) => Visit(
  id: 'v-$kind',
  at: at,
  kind: kind,
  location: 'Back Bay',
  procedures: [
    for (final s in done) Procedure(service: s, status: 'completed'),
  ],
);

void main() {
  test('the most involved treatment picks the sheet, and groups tick off as time passes', () {
    final v = visitOn(DateTime(2026, 11, 20, 10), 'treatment', [
      'Adult cleaning',
      'Simple extraction',
    ]);
    expect(aftercareFor(v)!.title, 'After your extraction');
    final d = aftercareDone(v.at, DateTime(2026, 11, 21, 12));
    expect((d.rightNow, d.today, d.thisWeek), (true, true, false));
  });

  test('no sheet for a visit with nothing done, and none of them gives medicine doses', () {
    expect(
      aftercareFor(visitOn(DateTime(2026, 11, 20), 'exam', const [])),
      isNull,
    );
    for (final s in [
      'Simple extraction',
      'Implant placement',
      'Root canal, molar',
      'Composite filling',
      'Whitening',
      'Adult cleaning',
    ]) {
      final sheet = aftercareFor(
        visitOn(DateTime(2026, 11, 20), 'treatment', [s]),
      )!;
      final text = [
        ...sheet.rightNow,
        ...sheet.today,
        ...sheet.thisWeek,
      ].join(' ');
      expect(
        text,
        isNot(
          matches(
            RegExp(
              r'\d+\s*mg|ibuprofen|paracetamol|acetaminophen',
              caseSensitive: false,
            ),
          ),
        ),
        reason: s,
      );
    }
  });

  testWidgets(
    'Home shows aftercare after a recent extraction, opening the full sheet',
    (tester) async {
      final now = DateTime.now();
      final care = FakeCareRepository({
        'p-elena': CareSummary(
          visits: [
            visitOn(now.subtract(const Duration(hours: 5)), 'treatment', [
              'Simple extraction',
            ]),
          ],
        ),
      });
      await pumpApp(
        tester,
        FakeAccountRepository(patients: [elena]),
        care: care,
      );
      await signIn(tester);
      await tapKey(tester, 'aftercare-card');
      expect(find.text('After your extraction'), findsOneWidget);
      expect(find.textContaining('In an emergency, call 911.'), findsOneWidget);
    },
  );

  testWidgets(
    'Home asks for a check-up when the last one was over six months ago',
    (tester) async {
      final now = DateTime.now();
      final care = FakeCareRepository({
        'p-elena': CareSummary(
          visits: [
            visitOn(
              DateTime(now.year, now.month - 7, now.day),
              'exam',
              const [],
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
      expect(find.text('Time for a check-up'), findsOneWidget);
      await tapKey(tester, 'book-checkup');
      expect(find.text('Book a visit'), findsOneWidget);
    },
  );
}
