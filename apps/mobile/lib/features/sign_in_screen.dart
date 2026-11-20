import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/account_repository.dart';
import '../design/tokens.dart';
import 'auth_screens.dart';
import '../design/widgets.dart';
import '../state.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    ref.read(signedOutNoticeProvider.notifier).clear();
    ref.read(passwordChangedNoticeProvider.notifier).clear();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountRepositoryProvider).signIn(_email.text, _password.text);
    } on AccountError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: heroGradient),
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  HeroStage(height: (box.maxHeight * 0.42).clamp(240, 380)),
                  BottomSheetPanel(
                    children: [
                      if (ref.watch(passwordChangedNoticeProvider)) ...[
                        const _SignedOutNote('Password saved. Sign in with your new password.'),
                        const SizedBox(height: 18),
                      ] else if (ref.watch(signedOutNoticeProvider)) ...[
                        const _SignedOutNote('You have signed out. Your sign-in was removed from this phone.'),
                        const SizedBox(height: 18),
                      ],
                      Text('Welcome back', style: text.headlineMedium),
                      const SizedBox(height: 6),
                      Text('Visits, plans and bookings across Back Bay, Cambridge and Quincy.', style: text.bodyLarge),
                      const SizedBox(height: 22),
                      TextField(
                        key: const Key('email'),
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Email'),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        key: const Key('password'),
                        controller: _password,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(labelText: 'Password'),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: const Key('go-reset'),
                          onPressed: () =>
                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResetRequestScreen(email: _email.text.trim()))),
                          child: const Text('Forgot password?'),
                        ),
                      ),
                      if (_error != null) ...[ErrorNote(_error!), const SizedBox(height: 14)],
                      const SizedBox(height: 8),
                      PrimaryButton(key: const Key('sign-in'), label: 'Sign in', busy: _busy, onPressed: _submit),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('New to Northgate?', style: TextStyle(color: Palette.muted, fontSize: 15)),
                          TextButton(
                            key: const Key('go-sign-up'),
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignUpScreen())),
                            child: const Text('Create an account'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignedOutNote extends StatelessWidget {
  const _SignedOutNote(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: Palette.enamel, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Palette.teal, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Palette.tealDark, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}
