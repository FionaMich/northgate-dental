import 'package:dental/data/team_chat_repository.dart';
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
    final nora = FakeAssistantRepository()..handOver = true;
    await pumpApp(
      tester,
      FakeAccountRepository(patients: [elena]),
      assistant: nora,
      teamChat: repo,
    );
    await signIn(tester);
    // the team is reached through Nora: once she hands over, her chat offers the team chat
    await tapKey(tester, 'open-assistant');
    await tester.enterText(
      find.byKey(const Key('assistant-input')),
      'I would like to speak to a member of the Northgate team',
    );
    await tapKey(tester, 'assistant-send');
    await tapKey(tester, 'open-team-chat');
    return repo;
  }

  testWidgets(
    'after Nora hands over, the team chat opens; the team\'s messages, typing and read ticks show',
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
    'Home shows the team conversation only while it is open, and says when a reply is unread',
    (tester) async {
      final repo = FakeTeamChatRepository(state: const TeamStatus('unread', 1));
      await pumpApp(
        tester,
        FakeAccountRepository(patients: [elena]),
        teamChat: repo,
      );
      await signIn(tester);
      expect(find.text('1 new message from the team'), findsOneWidget);
      await tapKey(tester, 'open-team-conversation');
      expect(repo.chats, hasLength(1), reason: 'it opens the conversation');
    },
  );

  testWidgets(
    'with no conversation, Home has no team card: Nora is the one way in',
    (tester) async {
      await pumpApp(tester, FakeAccountRepository(patients: [elena]));
      await signIn(tester);
      expect(find.byKey(const Key('open-team-conversation')), findsNothing);
    },
  );

  testWidgets(
    'a system line is shown as a line, and a team reply carries the writer\'s name',
    (tester) async {
      final repo = FakeTeamChatRepository(state: const TeamStatus('open', 0));
      await pumpApp(
        tester,
        FakeAccountRepository(patients: [elena]),
        teamChat: repo,
      );
      await signIn(tester);
      await tapKey(tester, 'open-team-conversation');
      repo.chats.single.show([
        TeamMessage(
          id: 's1',
          text: 'Your request was passed to the Northgate team (NGD-12).',
          mine: false,
          at: DateTime(2026, 11, 26, 10),
          system: true,
        ),
        TeamMessage(
          id: 'r1',
          text: 'Hello, I can help with that.',
          mine: false,
          at: DateTime(2026, 11, 26, 10, 5),
          sender: 'Sam · front desk',
        ),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('team-system-s1')), findsOneWidget);
      expect(find.text('Sam · front desk'), findsOneWidget);
    },
  );
}
