import 'package:dental/data/account_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

Future<void> enterCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byKey(const Key('code-input')), code);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the sign-up screen shows no synthetic data label (decision 2026-11-19)', (tester) async {
    await pumpApp(tester, FakeAccountRepository());
    await tapKey(tester, 'go-sign-up');
    expect(find.textContaining(RegExp('synthetic data|not a real practice', caseSensitive: false)), findsNothing);
  });

  testWidgets('a new patient signs up, confirms the emailed code and is asked to link a record (E34)', (tester) async {
    final repo = await pumpApp(tester, FakeAccountRepository());
    await tapKey(tester, 'go-sign-up');
    await tester.enterText(find.byKey(const Key('name')), 'Jordan Lee');
    await tester.enterText(find.byKey(const Key('email')), 'jordan@northgate.synthetic');
    await tester.enterText(find.byKey(const Key('password')), 'Synthetic123');
    await tester.pumpAndSettle();
    await tapKey(tester, 'create-account');
    expect(repo.sent, ['signup:jordan@northgate.synthetic']);
    expect(find.textContaining('jordan@northgate.synthetic'), findsOneWidget);
    await enterCode(tester, '123456');
    expect(find.text('Find your record'), findsOneWidget);
  });

  testWidgets('a weak password keeps Create account switched off', (tester) async {
    final repo = await pumpApp(tester, FakeAccountRepository());
    await tapKey(tester, 'go-sign-up');
    await tester.enterText(find.byKey(const Key('name')), 'Jordan Lee');
    await tester.enterText(find.byKey(const Key('email')), 'jordan@northgate.synthetic');
    await tester.enterText(find.byKey(const Key('password')), 'short');
    await tester.pumpAndSettle();
    await tapKey(tester, 'create-account');
    expect(repo.sent, isEmpty);
  });

  testWidgets('a wrong code is refused and resend waits 60 seconds (E41)', (tester) async {
    final repo = await pumpApp(tester, FakeAccountRepository());
    await tapKey(tester, 'go-sign-up');
    await tester.enterText(find.byKey(const Key('name')), 'Jordan Lee');
    await tester.enterText(find.byKey(const Key('email')), 'jordan@northgate.synthetic');
    await tester.enterText(find.byKey(const Key('password')), 'Synthetic123');
    await tester.pumpAndSettle();
    await tapKey(tester, 'create-account');
    await enterCode(tester, '000000');
    expect(find.text(codeError), findsOneWidget);
    expect(find.textContaining('Send a new code in'), findsOneWidget);
    await tester.pump(const Duration(seconds: 61));
    await tapKey(tester, 'resend');
    expect(repo.sent.last, 'resend:jordan@northgate.synthetic');
  });

  testWidgets('forgot password: same answer for any email, then code, then a new password signs in', (tester) async {
    final repo = await pumpApp(tester, FakeAccountRepository());
    await tapKey(tester, 'go-reset');
    await tester.enterText(find.byKey(const Key('email')), 'whoever@northgate.synthetic');
    await tapKey(tester, 'send-reset');
    expect(find.textContaining('If an account uses whoever@northgate.synthetic'), findsOneWidget);
    await enterCode(tester, '123456');
    await tester.enterText(find.byKey(const Key('password')), 'NewSynthetic9');
    await tester.pumpAndSettle();
    await tapKey(tester, 'save-password');
    expect(repo.newPassword, 'NewSynthetic9');
  });

  testWidgets('too many requests shows a calm wait message (E42)', (tester) async {
    final repo = FakeAccountRepository()..rateLimited = true;
    await pumpApp(tester, repo);
    await tapKey(tester, 'go-reset');
    await tester.enterText(find.byKey(const Key('email')), 'elena@northgate.synthetic');
    await tapKey(tester, 'send-reset');
    expect(find.text(tooManyError), findsOneWidget);
  });

  testWidgets('sign-out asks first; Cancel keeps you signed in', (tester) async {
    final repo = await pumpApp(
      tester,
      FakeAccountRepository(
        patients: const [LinkedPatient(id: 'p-elena', name: 'Elena Marsh', isSelf: true)],
      ),
    );
    await signIn(tester);
    await tapKey(tester, 'tab-profile');
    await tapKey(tester, 'sign-out');
    await tapKey(tester, 'cancel-sign-out');
    expect(repo.signOutCalls, 0);
    expect(find.text('Profile'), findsWidgets);
  });
}
