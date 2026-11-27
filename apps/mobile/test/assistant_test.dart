import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'appointments_test.dart' show elena;
import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

void main() {
  testWidgets(
    'the chat opens by saying it is an AI and answers in the chosen language',
    (tester) async {
      final assistant = FakeAssistantRepository();
      await pumpApp(
        tester,
        FakeAccountRepository(patients: [elena]),
        assistant: assistant,
      );
      await signIn(tester);
      await tapKey(tester, 'open-assistant');
      expect(
        find.text('Hi, I am an AI assistant.'),
        findsOneWidget,
        reason: 'every conversation starts with the AI disclosure',
      );

      await tapKey(tester, 'pick-language');
      await tapKey(tester, 'language-es');
      expect(
        find.text('Hola, soy la recepcionista virtual (IA).'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('assistant-input')),
        '¿A qué hora abre Quincy?',
      );
      await tapKey(tester, 'assistant-send');
      expect(assistant.sent, ['es:¿A qué hora abre Quincy?']);
      expect(find.text('Quincy opens at 07:00 on Mondays.'), findsOneWidget);
      // messenger manners: the patient's message shows as read once Nora has answered, and nobody is typing
      expect(find.byKey(const Key('ticks-read')), findsOneWidget);
      // the quick replies stay after the first message and send in the patient's language
      await tapKey(tester, 'quick-Opening hours');
      expect(assistant.sent.last, 'es:Horario de apertura');
      expect(find.byKey(const Key('chat-typing')), findsNothing);
      expect(find.text('AI assistant · online'), findsOneWidget);
      expect(find.textContaining('up to a minute'), findsNothing);
    },
  );

  testWidgets('a booking waits for the patient to press Confirm', (
    tester,
  ) async {
    final assistant = FakeAssistantRepository()..proposeBooking = true;
    await pumpApp(
      tester,
      FakeAccountRepository(patients: [elena]),
      assistant: assistant,
    );
    await signIn(tester);
    await tapKey(tester, 'open-assistant');
    await tapKey(tester, 'starter-Book a cleaning');
    expect(find.text('Book this visit?'), findsOneWidget);
    expect(
      assistant.answers,
      isEmpty,
      reason: 'nothing is booked until the button',
    );
    await tapKey(tester, 'confirm-yes');
    expect(assistant.answers, [true]);
    expect(find.text('Booked.'), findsOneWidget);
  });

  testWidgets('the picker offers exactly the eight supported languages', (
    tester,
  ) async {
    await pumpApp(
      tester,
      FakeAccountRepository(patients: [elena]),
      assistant: FakeAssistantRepository(),
    );
    await signIn(tester);
    await tapKey(tester, 'open-assistant');
    await tapKey(tester, 'pick-language');
    for (final code in ['en', 'fr', 'nl', 'de', 'es', 'it', 'lt', 'sv']) {
      expect(find.byKey(Key('language-$code')), findsOneWidget, reason: code);
    }
    expect(find.byKey(const Key('language-ar')), findsNothing);
  });

  testWidgets(
    'Nora speaks her greeting, hears the patient and answers aloud with captions',
    (tester) async {
      final assistant = FakeAssistantRepository();
      final voice = FakeVoiceEngine()..heard.add('What time does Quincy open?');
      await pumpApp(
        tester,
        FakeAccountRepository(patients: [elena]),
        assistant: assistant,
        voice: voice,
      );
      await signIn(tester);
      await tapKey(tester, 'open-assistant');
      await tapKey(tester, 'open-voice');
      expect(
        voice.spoken.first,
        'en:Hi, I am an AI assistant.',
        reason: 'the AI disclosure is spoken first',
      );
      expect(assistant.sent.last, 'en:What time does Quincy open?');
      expect(voice.spoken.last, 'en:Quincy opens at 07:00 on Mondays.');
      expect(
        find.text('Quincy opens at 07:00 on Mondays.'),
        findsOneWidget,
        reason: 'captions for every spoken reply',
      );
      expect(
        find.text('You said: “What time does Quincy open?”'),
        findsOneWidget,
        reason: 'the patient sees exactly the words Nora received',
      );
    },
  );

  testWidgets(
    'a spoken booking still waits for the button, never for a spoken yes',
    (tester) async {
      final assistant = FakeAssistantRepository()..proposeBooking = true;
      final voice = FakeVoiceEngine()..heard.add('Book a cleaning');
      await pumpApp(
        tester,
        FakeAccountRepository(patients: [elena]),
        assistant: assistant,
        voice: voice,
      );
      await signIn(tester);
      await tapKey(tester, 'open-assistant');
      await tapKey(tester, 'open-voice');
      await tapKey(tester, 'voice-mic');
      expect(find.byKey(const Key('voice-yes')), findsOneWidget);
      expect(assistant.answers, isEmpty);
      await tapKey(tester, 'voice-yes');
      expect(assistant.answers, [true]);
    },
  );

  testWidgets(
    'with no on-device recogniser the microphone is off and Nora says so',
    (tester) async {
      await pumpApp(
        tester,
        FakeAccountRepository(patients: [elena]),
        voice: FakeVoiceEngine(available: false),
      );
      await signIn(tester);
      await tapKey(tester, 'open-assistant');
      await tapKey(tester, 'open-voice');
      expect(find.textContaining('Voice is not available'), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const Key('voice-mic'))),
        isSemantics(
          label: 'Speak to Nora',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
        reason: 'a screen reader hears that the microphone is off, not a button that does nothing',
      );
    },
  );

  testWidgets(
    'the Nora card on Home is a button of its own for screen readers',
    (tester) async {
      await pumpApp(tester, FakeAccountRepository(patients: [elena]));
      await signIn(tester);
      final card = tester.getSemantics(find.byKey(const Key('open-assistant')));
      expect(
        card.label,
        startsWith('Ask Nora'),
        reason: 'not merged into the visit card above it',
      );
      expect(card.getSemanticsData().flagsCollection.isButton, isTrue);
    },
  );

  testWidgets('the message field has a name a screen reader can read', (
    tester,
  ) async {
    await pumpApp(tester, FakeAccountRepository(patients: [elena]));
    await signIn(tester);
    await tapKey(tester, 'open-assistant');
    expect(find.bySemanticsLabel(RegExp('^Message to Nora')), findsOneWidget);
  });

  testWidgets(
    'turn-taking: after Nora answers she listens again without another tap',
    (tester) async {
      final assistant = FakeAssistantRepository();
      final voice = FakeVoiceEngine()
        ..heard.addAll(['What time does Quincy open?', 'And on Saturday?']);
      await pumpApp(
        tester,
        FakeAccountRepository(patients: [elena]),
        assistant: assistant,
        voice: voice,
      );
      await signIn(tester);
      await tapKey(tester, 'open-assistant');
      await tapKey(tester, 'open-voice');
      expect(assistant.sent, [
        'en:What time does Quincy open?',
        'en:And on Saturday?',
      ]);
      expect(
        find.text('Tap the microphone and speak'),
        findsOneWidget,
        reason: 'silence ends the loop',
      );
    },
  );

  testWidgets(
    'turn-taking: tapping the microphone while Nora speaks interrupts her and listens',
    (tester) async {
      final assistant = FakeAssistantRepository();
      final voice = FakeVoiceEngine(longSpeech: true)
        ..heard.add('What time does Quincy open?');
      await pumpApp(
        tester,
        FakeAccountRepository(patients: [elena]),
        assistant: assistant,
        voice: voice,
      );
      await signIn(tester);
      await tapKey(tester, 'open-assistant');
      await tapKey(tester, 'open-voice'); // Nora is still reading the AI notice
      await tapKey(tester, 'voice-mic');
      expect(assistant.sent, ['en:What time does Quincy open?']);
    },
  );

  testWidgets(
    'a language pack missing on the phone turns the microphone off instead of failing silently',
    (tester) async {
      // Seen on a Galaxy A12: the language is listed, but on-device recognition fails with LANGUAGE_PACK_ERROR (13).
      final assistant = FakeAssistantRepository();
      final voice = FakeVoiceEngine(packMissing: true);
      await pumpApp(
        tester,
        FakeAccountRepository(patients: [elena]),
        assistant: assistant,
        voice: voice,
      );
      await signIn(tester);
      await tapKey(tester, 'open-assistant');
      await tapKey(tester, 'open-voice');
      await tapKey(tester, 'voice-mic');
      expect(find.textContaining('Voice is not available'), findsOneWidget);
      expect(assistant.sent, isEmpty, reason: 'nothing reaches Nora');
    },
  );
}
