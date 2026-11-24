import 'package:dental/data/account_repository.dart';
import 'package:dental/data/care_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

const elena = LinkedPatient(id: 'p-elena', name: 'Elena Marsh', isSelf: true);

final _visits = [
  Visit(
    id: 'v2',
    at: DateTime(2026, 10, 22, 10),
    kind: 'treatment',
    location: 'Back Bay',
    procedures: const [
      Procedure(service: 'Composite filling', status: 'completed', tooth: '3'),
    ],
  ),
  Visit(
    id: 'v1',
    at: DateTime(2026, 9, 2, 9),
    kind: 'exam',
    location: 'Back Bay',
  ),
];

final _plan = Plan(
  id: 'plan-1',
  status: 'accepted',
  phases: const [
    PlanPhase(
      sequence: 1,
      name: 'Urgent care',
      procedures: [
        Procedure(
          service: 'Composite filling',
          status: 'completed',
          tooth: '3',
        ),
      ],
    ),
    PlanPhase(
      sequence: 2,
      name: 'Restore',
      procedures: [
        Procedure(service: 'Porcelain crown', status: 'planned', tooth: '19'),
      ],
    ),
    PlanPhase(
      sequence: 3,
      name: 'Maintain',
      procedures: [Procedure(service: 'Periodic exam', status: 'planned')],
    ),
  ],
);

Future<void> openHome(WidgetTester tester, CareSummary care) async {
  await pumpApp(
    tester,
    FakeAccountRepository(patients: const [elena]),
    care: FakeCareRepository({'p-elena': care}),
  );
  await signIn(tester);
}

void main() {
  testWidgets('home shows the next visit with its service, day and place', (
    tester,
  ) async {
    await openHome(
      tester,
      CareSummary(
        upcoming: [
          Appointment(
            id: 'a1',
            startsAt: DateTime(2026, 11, 24, 10, 30),
            endsAt: DateTime(2026, 11, 24, 11, 15),
            service: 'Adult cleaning',
            location: 'Back Bay',
            status: 'booked',
          ),
        ],
      ),
    );
    expect(find.text('Adult cleaning'), findsOneWidget);
    expect(find.textContaining('10:30'), findsOneWidget);
    expect(find.textContaining('Back Bay'), findsWidgets);
  });

  testWidgets('with nothing booked, home says so instead of leaving a gap', (
    tester,
  ) async {
    await openHome(tester, const CareSummary());
    expect(find.text('No visit booked'), findsOneWidget);
    expect(find.text('No treatment plan'), findsOneWidget);
    expect(find.text('No visits yet'), findsOneWidget);
  });

  testWidgets('recent visits are newest first and Records lists them all', (
    tester,
  ) async {
    await openHome(tester, CareSummary(visits: _visits));
    final newer = tester.getTopLeft(find.text('Treatment').first).dy;
    final older = tester.getTopLeft(find.text('Exam').first).dy;
    expect(newer, lessThan(older));
    await tapKey(tester, 'tab-records');
    expect(
      find.text('Composite filling'),
      findsOneWidget,
      reason: 'each visit lists what was done as short chips',
    );
  });

  testWidgets('the plan card shows progress and opens the phase list', (
    tester,
  ) async {
    await openHome(tester, CareSummary(plans: [_plan]));
    expect(find.text('Phase 2 of 3'), findsOneWidget);
    await tapKey(tester, 'plan-card');
    expect(find.text('Restore'), findsWidgets);
    expect(find.text('Porcelain crown · tooth 19'), findsOneWidget);
  });

  testWidgets(
    'a failed load says so at once, with a retry, never an endless spinner',
    (tester) async {
      await pumpApp(
        tester,
        FakeAccountRepository(patients: const [elena]),
        care: FakeCareRepository(const {}, true),
      );
      await signIn(tester);
      expect(
        find.text('Could not load your visits. Tap to try again.'),
        findsOneWidget,
      );
    },
  );
}
