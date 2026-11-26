import 'package:dental/data/team_chat_repository.dart';
import 'package:dental/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'appointments_test.dart' show elena;
import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

/// The patient's chat with the clinic team through Stream Chat (ADR 0018): a messenger with delivery and read ticks.
void main() {
  Future<FakeTeamChatRepository> openTeamChat(
    WidgetTester tester, {
    bool available = true,
  }) async {
    final repo = FakeTeamChatRepository(available: available);
    await pumpApp(
      tester,
      FakeAccountRepository(patients: [elena]),
      extra: [teamChatRepositoryProvider.overrideWithValue(repo)],
    );
    await signIn(tester);
    await tapKey(tester, 'open-team-chat-home');
    return repo;
  }

  testWidgets(
    'Home opens the team chat; the team\'s messages, typing and read ticks show',
    (tester) async {
      final chat = (await openTeamChat(tester)).chats.single;
      expect(chat.opened, isTrue);
      expect(find.text('Northgate team'), findsOneWidget);
      expect(find.textContaining('not to Nora'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('team-input')),
        'Can you check my insurance?',
      );
      expect(chat.keystrokes, greaterThan(0), reason: 'the team sees typing');
      await tapKey(tester, 'team-send');
      expect(chat.sent, ['Can you check my insurance?']);
      expect(find.byKey(const Key('ticks-delivered')), findsOneWidget);

      chat.typingController.add(true);
      await tester.pump();
      await tester.pump();
      expect(find.text('typing…'), findsOneWidget);
      chat.typingController.add(false);
      chat.show([
        TeamMessage(
          id: 'a',
          text: 'Can you check my insurance?',
          mine: true,
          at: DateTime(2026, 11, 25, 10, 5),
          delivery: TeamDelivery.read,
        ),
        TeamMessage(
          id: 'b',
          text: 'Hello, this is Sam at the front desk. Checking now.',
          mine: false,
          at: DateTime(2026, 11, 25, 10, 6),
        ),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('ticks-read')), findsOneWidget);
      expect(
        find.text('Hello, this is Sam at the front desk. Checking now.'),
        findsOneWidget,
      );
      expect(find.text('10:06'), findsOneWidget);
    },
  );

  testWidgets('without a team chat service the patient is told to call', (
    tester,
  ) async {
    final repo = await openTeamChat(tester, available: false);
    expect(repo.chats, isEmpty);
    expect(find.textContaining('team chat is unavailable'), findsOneWidget);
  });

  testWidgets(
    'Home offers a video consultation and says plainly when it is unavailable',
    (tester) async {
      final consult = FakeConsultRepository(available: false);
      await pumpApp(
        tester,
        FakeAccountRepository(patients: [elena]),
        extra: [consultRepositoryProvider.overrideWithValue(consult)],
      );
      await signIn(tester);
      await tapKey(tester, 'open-video-visit');
      expect(consult.asked, 1);
      expect(
        find.textContaining('Video consultations are unavailable'),
        findsOneWidget,
      );
    },
  );
}
