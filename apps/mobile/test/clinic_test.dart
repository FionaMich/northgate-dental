import 'package:dental/data/account_repository.dart';
import 'package:dental/features/clinic_screen.dart';
import 'package:dental/features/visit_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

const clinic = Clinic(
  id: 'c',
  name: 'Back Bay',
  address: 'x',
  hours: [(1, '08:00', '18:00'), (5, '08:00', '16:00')],
);

void main() {
  test('open during hours in the clinic\'s own time, closed outside them and on days without hours', () {
    expect(
      isOpen(clinic, DateTime(2026, 11, 23, 10)),
      isTrue,
      reason: 'Monday 10:00',
    );
    expect(
      isOpen(clinic, DateTime(2026, 11, 23, 18)),
      isFalse,
      reason: 'closing time itself is closed',
    );
    expect(
      isOpen(clinic, DateTime(2026, 11, 27, 16, 30)),
      isFalse,
      reason: 'Friday after 16:00',
    );
    expect(
      isOpen(clinic, DateTime(2026, 11, 22, 10)),
      isFalse,
      reason: 'Sunday',
    );
  });

  testWidgets(
    'the clinic page shows hours and the team, and Directions opens maps with the address',
    (tester) async {
      final opened = <String>[];
      await pumpApp(
        tester,
        FakeAccountRepository(
          patients: const [
            LinkedPatient(id: 'p-elena', name: 'Elena Marsh', isSelf: true),
          ],
        ),
        extra: [
          documentOpenerProvider.overrideWithValue(
            (url) async => opened.add(url),
          ),
        ],
      );
      await signIn(tester);
      await tapKey(tester, 'book-visit');
      await tapKey(tester, 'about-clinic');
      expect(find.text('Northgate Dental, Back Bay'), findsOneWidget);
      expect(find.byKey(const Key('open-badge')), findsOneWidget);
      await tapKey(tester, 'clinic-directions');
      expect(
        opened.single,
        startsWith(
          'https://www.google.com/maps/search/?api=1&query=1%20Example%20Street',
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Priya Raman, RDH'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Priya Raman, RDH'), findsOneWidget);
    },
  );
}
