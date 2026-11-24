import 'package:dental/data/call_repository.dart';
import 'package:dental/features/nora_call_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'appointments_test.dart' show elena;
import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

/// Voice calls with Nora through Stream (ADR 0015): the phone shows what she heard and said, and bookings still wait
/// for the button. Without a call service, the phone's own voice screen takes over.
void main() {
  Future<FakeCallRepository> openCall(
    WidgetTester tester, {
    bool available = true,
  }) async {
    final calls = FakeCallRepository(available: available);
    await pumpApp(
      tester,
      FakeAccountRepository(patients: [elena]),
      calls: calls,
    );
    await signIn(tester);
    await tapKey(tester, 'open-assistant');
    await tapKey(tester, 'open-voice');
    return calls;
  }

  testWidgets(
    'the voice button starts a call and shows both sides as captions',
    (tester) async {
      final calls = await openCall(tester);
      final call = calls.calls.single;
      expect(call.joined, isTrue);
      expect(find.text('Calling Nora…'), findsOneWidget);

      call.controller.add(const NoraJoined());
      call.controller.add(
        const NoraCaption(
          'nora',
          'Hi, I am Nora, an AI assistant. How can I help?',
        ),
      );
      await tester.pump();
      expect(
        find.text('Hi, I am Nora, an AI assistant. How can I help?'),
        findsOneWidget,
      );

      call.controller.add(const NoraCaption('you', 'When does Quincy open?'));
      call.controller.add(const NoraMoodEvent('thinking'));
      await tester.pump();
      expect(find.text('You said: “When does Quincy open?”'), findsOneWidget);
      expect(find.text('Nora is thinking…'), findsOneWidget);
      expect(calls.languages, ['en']);
    },
  );

  testWidgets('a booking proposed by voice still waits for the button', (
    tester,
  ) async {
    final calls = await openCall(tester);
    final call = calls.calls.single;
    call.controller.add(const NoraJoined());
    call.controller.add(
      const NoraConfirm({
        'title': 'Book this visit?',
        'detail': 'Friday 27 November at 10:00',
        'yes': 'Confirm',
        'no': 'Not now',
      }),
    );
    await tester.pump();
    expect(
      call.answers,
      isEmpty,
      reason: 'saying yes books nothing; only the button does',
    );
    await tapKey(tester, 'call-yes');
    expect(call.answers, [true]);
    expect(find.byKey(const Key('call-yes')), findsNothing);
  });

  testWidgets('ending the call leaves it, and mute reaches the call', (
    tester,
  ) async {
    final calls = await openCall(tester);
    final call = calls.calls.single;
    call.controller.add(const NoraJoined());
    await tester.pump();
    await tapKey(tester, 'call-mute');
    expect(call.muted, isTrue);
    expect(find.text('Your microphone is off'), findsOneWidget);
    await tapKey(tester, 'call-end');
    expect(call.left, isTrue);
    expect(
      find.byKey(const Key('call-status')),
      findsNothing,
      reason: 'back in the chat',
    );
  });

  testWidgets(
    'without a call service the voice button opens the phone voice screen',
    (tester) async {
      await openCall(tester, available: false);
      expect(find.byKey(const Key('voice-mic')), findsOneWidget);
      expect(find.byKey(const Key('call-status')), findsNothing);
    },
  );

  testWidgets(
    'when Nora does not pick up, the screen says so and the call can be ended',
    (tester) async {
      final calls = await openCall(tester);
      await tester.pump(
        NoraCallScreen.pickUpTimeout + const Duration(seconds: 1),
      );
      expect(
        find.textContaining('Nora cannot take calls right now'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('call-use-phone-voice')),
        findsNothing,
        reason: 'no phone-voice offer on a call',
      );
      await tapKey(tester, 'call-end');
      expect(calls.calls.single.left, isTrue);
    },
  );
}
