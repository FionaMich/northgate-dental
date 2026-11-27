import 'package:dental/features/chat_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Links in Nora's replies are highlighted and get a button, so a payment link is never lost in the text.
void main() {
  const reply =
      'The secure payment link is ready: https://n8n.example/webhook/pay?t=abc123. It is also in your email.';

  Future<void> bubble(WidgetTester tester, {bool mine = false}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              text: reply,
              at: DateTime(2026, 11, 27, 11, 5),
              mine: mine,
            ),
          ),
        ),
      );

  test('a link ending a sentence is found without its full stop', () {
    expect(
      chatLinks(reply).single.toString(),
      'https://n8n.example/webhook/pay?t=abc123',
    );
    expect(
      linkLabel(Uri.parse('https://n8n.example/webhook/move?t=x')),
      'Choose a new time',
    );
  });

  testWidgets(
    'a payment link in Nora\'s reply is highlighted and has a Pay securely button',
    (tester) async {
      await bubble(tester);
      expect(find.byKey(const Key('chat-link-pay')), findsOneWidget);
      expect(find.text('Pay securely'), findsOneWidget);
      final rich = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .textSpan!;
      final link = (rich.children!).whereType<TextSpan>().firstWhere(
        (s) => s.text == 'https://n8n.example/webhook/pay?t=abc123',
      );
      expect(
        link.style!.fontWeight,
        FontWeight.w700,
        reason: 'the link stands out in the text',
      );
      expect(link.style!.backgroundColor, isNotNull);
    },
  );

  testWidgets('the patient\'s own messages get no link button', (tester) async {
    await bubble(tester, mine: true);
    expect(find.byKey(const Key('chat-link-pay')), findsNothing);
  });
}
