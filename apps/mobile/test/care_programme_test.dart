import 'package:dental/data/programme_repository.dart';
import 'package:dental/features/checkin_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'appointments_test.dart' show elena;
import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

/// Continuous care (W24 to W28) in the app: consent first, today's check-in, and the clinic's answer in fixed words.
final checkinList = find
    .descendant(
      of: find.byType(CheckinScreen),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  CareProgramme invite(String programme, {String? checkin}) => CareProgramme(
    id: 'enrol-$programme',
    programme: programme,
    status: 'invited',
    endsOn: DateTime(2026, 12, 3),
    todayCheckinId: checkin,
  );

  Future<void> openCheckin(
    WidgetTester tester,
    FakeProgrammeRepository repo,
  ) async {
    await pumpApp(
      tester,
      FakeAccountRepository(patients: [elena]),
      programmes: repo,
    );
    await signIn(tester);
    await tester.ensureVisible(find.byKey(const Key('join-post_procedure')));
    await tester.pumpAndSettle();
    expect(
      find.text('You can leave at any time.'),
      findsOneWidget,
      reason: 'consent is asked, not assumed',
    );
    await tapKey(tester, 'join-post_procedure');
    expect(repo.joined, ['enrol-post_procedure']);
    await tester.ensureVisible(find.byKey(const Key('open-checkin')));
    await tester.pumpAndSettle();
    await tapKey(tester, 'open-checkin');
  }

  testWidgets(
    'a patient joins the recovery programme and a red flag answer shows the emergency text',
    (tester) async {
      final repo = FakeProgrammeRepository(
        programmes: [invite('post_procedure', checkin: 'chk-1')],
      );
      await openCheckin(tester, repo);
      await tester.scrollUntilVisible(
        find.byKey(const Key('checkin-send')),
        300,
        scrollable: checkinList,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('checkin-send')));
      await tester.pumpAndSettle();
      expect(
        repo.answers,
        isEmpty,
        reason: 'nothing is sent before the patient says how they feel',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('checkin-worse')),
        -300,
        scrollable: checkinList,
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'checkin-worse');
      await tapKey(tester, 'checkin-symptom-swelling');
      await tapKey(tester, 'checkin-symptom-fever');
      await tester.scrollUntilVisible(
        find.byKey(const Key('checkin-send')),
        300,
        scrollable: checkinList,
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'checkin-send');
      expect(repo.answers.single['symptoms'], ['swelling', 'fever']);
      expect(find.byKey(const Key('checkin-result-emergency')), findsOneWidget);
      expect(find.textContaining('Call 911'), findsOneWidget);
    },
  );

  testWidgets(
    'pain at the clinic\'s threshold tells the patient the team will call',
    (tester) async {
      final repo = FakeProgrammeRepository(
        programmes: [invite('post_procedure', checkin: 'chk-2')],
      );
      await openCheckin(tester, repo);
      await tester.drag(
        find.byKey(const Key('checkin-pain')),
        const Offset(400, 0),
      );
      await tapKey(tester, 'checkin-same');
      await tester.scrollUntilVisible(
        find.byKey(const Key('checkin-send')),
        300,
        scrollable: checkinList,
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'checkin-send');
      expect(repo.answers.single['pain'] as int, greaterThanOrEqualTo(7));
      expect(find.byKey(const Key('checkin-result-task')), findsOneWidget);
      expect(find.text('Thank you, the team will call you'), findsOneWidget);
    },
  );

  testWidgets('a patient can leave a programme at any time', (tester) async {
    final repo = FakeProgrammeRepository(
      programmes: [
        CareProgramme(
          id: 'enrol-aligners',
          programme: 'aligners',
          status: 'active',
          endsOn: DateTime(2027, 3, 1),
        ),
      ],
    );
    await pumpApp(
      tester,
      FakeAccountRepository(patients: [elena]),
      programmes: repo,
    );
    await signIn(tester);
    await tester.ensureVisible(find.byKey(const Key('leave-aligners')));
    await tester.pumpAndSettle();
    await tapKey(tester, 'leave-aligners');
    expect(repo.left, ['enrol-aligners']);
  });
}
