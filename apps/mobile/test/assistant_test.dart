import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'appointments_test.dart' show elena;
import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

void main() {
  testWidgets('the chat opens by saying it is an AI and answers in the chosen language', (tester) async {
    final assistant = FakeAssistantRepository();
    await pumpApp(tester, FakeAccountRepository(patients: [elena]), assistant: assistant);
    await signIn(tester);
    await tapKey(tester, 'open-assistant');
    expect(find.text('Hi, I am an AI assistant.'), findsOneWidget, reason: 'every conversation starts with the AI disclosure');

    await tapKey(tester, 'pick-language');
    await tapKey(tester, 'language-es');
    expect(find.text('Hola, soy la recepcionista virtual (IA).'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('assistant-input')), '¿A qué hora abre Quincy?');
    await tapKey(tester, 'assistant-send');
    expect(assistant.sent, ['es:¿A qué hora abre Quincy?']);
    expect(find.text('Quincy opens at 07:00 on Mondays.'), findsOneWidget);
  });

  testWidgets('a booking waits for the patient to press Confirm', (tester) async {
    final assistant = FakeAssistantRepository()..proposeBooking = true;
    await pumpApp(tester, FakeAccountRepository(patients: [elena]), assistant: assistant);
    await signIn(tester);
    await tapKey(tester, 'open-assistant');
    await tapKey(tester, 'starter-Book a cleaning');
    expect(find.text('Book this visit?'), findsOneWidget);
    expect(assistant.answers, isEmpty, reason: 'nothing is booked until the button');
    await tapKey(tester, 'confirm-yes');
    expect(assistant.answers, [true]);
    expect(find.text('Booked.'), findsOneWidget);
  });

  testWidgets('the picker offers exactly the seven supported languages', (tester) async {
    await pumpApp(tester, FakeAccountRepository(patients: [elena]), assistant: FakeAssistantRepository());
    await signIn(tester);
    await tapKey(tester, 'open-assistant');
    await tapKey(tester, 'pick-language');
    for (final code in ['en', 'fr', 'nl', 'de', 'es', 'lt', 'sv']) {
      expect(find.byKey(Key('language-$code')), findsOneWidget, reason: code);
    }
    expect(find.byKey(const Key('language-ar')), findsNothing);
  });
}
