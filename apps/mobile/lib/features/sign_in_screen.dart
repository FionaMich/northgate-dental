import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/account_repository.dart';
import '../design/tokens.dart';
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
                      if (_error != null) ...[const SizedBox(height: 14), ErrorNote(_error!)],
                      const SizedBox(height: 22),
                      PrimaryButton(key: const Key('sign-in'), label: 'Sign in', busy: _busy, onPressed: _submit),
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
