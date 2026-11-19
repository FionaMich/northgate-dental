import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/account_repository.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../state.dart';

/// Runs an account call with a busy flag and a plain-language error.
mixin _Busy<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool busy = false;
  String? error;

  Future<bool> run(Future<void> Function(AccountRepository repo) call) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await call(ref.read(accountRepositoryProvider));
      return true;
    } on AccountError catch (e) {
      if (mounted) setState(() => error = e.message);
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

List<(String, bool)> _rules(String p) => [
  ('10+ characters', PasswordRules.longEnough(p)),
  ('Upper case', PasswordRules.hasUpper(p)),
  ('Lower case', PasswordRules.hasLower(p)),
  ('A number', PasswordRules.hasDigit(p)),
];

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> with _Busy {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _show = false;

  bool get _ready => _name.text.trim().isNotEmpty && _email.text.contains('@') && PasswordRules.ok(_password.text);

  Future<void> _create() async {
    if (!_ready) return;
    final email = _email.text.trim();
    if (await run((r) => r.signUp(name: _name.text, email: email, password: _password.text)) && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CodeScreen(email: email, purpose: CodePurpose.signUp),
        ),
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AuthLayout(
      heroFraction: 0.24,
      showBack: true,
      children: [
        Text('Create your account', style: text.headlineMedium),
        const SizedBox(height: 6),
        Text('We will email you a code to confirm it is you.', style: text.bodyLarge),
        const SizedBox(height: 22),
        TextField(
          key: const Key('name'),
          controller: _name,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Full name'),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const Key('password'),
          controller: _password,
          obscureText: !_show,
          autofillHints: const [AutofillHints.newPassword],
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _create(),
          decoration: InputDecoration(
            labelText: 'Password',
            suffixIcon: IconButton(
              tooltip: _show ? 'Hide password' : 'Show password',
              icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              onPressed: () => setState(() => _show = !_show),
            ),
          ),
        ),
        const SizedBox(height: 12),
        PasswordChecklist(rules: _rules(_password.text)),
        if (error != null) ...[const SizedBox(height: 14), ErrorNote(error!)],
        const SizedBox(height: 22),
        PrimaryButton(key: const Key('create-account'), label: 'Create account', busy: busy, onPressed: _ready ? _create : null),
        const SizedBox(height: 14),
        const Text(
          'By creating an account you agree that Northgate Dental may use your email to send sign-in codes. This app holds synthetic data only.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.45, color: Palette.muted),
        ),
      ],
    );
  }
}

enum CodePurpose { signUp, reset }

/// Enter the 6-digit code from the email. Used for sign-up and for password reset.
class CodeScreen extends ConsumerStatefulWidget {
  const CodeScreen({super.key, required this.email, required this.purpose});
  final String email;
  final CodePurpose purpose;

  @override
  ConsumerState<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends ConsumerState<CodeScreen> with _Busy {
  static const _wait = 60;
  int _left = _wait;
  Timer? _timer;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _left = _wait);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 1) t.cancel();
      if (mounted) setState(() => _left--);
    });
  }

  Future<void> _verify(String code) async {
    final nav = Navigator.of(context);
    if (widget.purpose == CodePurpose.signUp) {
      if (await run((r) => r.verifySignUpCode(widget.email, code))) nav.popUntil((r) => r.isFirst);
    } else {
      if (await run((r) => r.verifyResetCode(widget.email, code))) {
        nav.pushReplacement(MaterialPageRoute(builder: (_) => const NewPasswordScreen()));
      }
    }
    if (error != null && mounted) setState(() => _attempt++); // fresh boxes after a wrong code
  }

  Future<void> _resend() async {
    final ok = await run(
      (r) => widget.purpose == CodePurpose.signUp ? r.resendSignUpCode(widget.email) : r.sendPasswordReset(widget.email),
    );
    if (ok) _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AuthLayout(
      heroFraction: 0.3,
      showBack: true,
      children: [
        Text('Check your email', style: text.headlineMedium),
        const SizedBox(height: 6),
        Text(
          widget.purpose == CodePurpose.signUp
              ? 'We sent a 6-digit code to ${widget.email}. It expires in 10 minutes.'
              : 'If an account uses ${widget.email}, we sent it a 6-digit code. It expires in 10 minutes.',
          style: text.bodyLarge,
        ),
        const SizedBox(height: 24),
        CodeBoxes(key: ValueKey(_attempt), enabled: !busy, onCompleted: _verify),
        if (error != null) ...[const SizedBox(height: 16), ErrorNote(error!)],
        const SizedBox(height: 20),
        Center(
          child: _left > 0
              ? Text(
                  'Send a new code in ${_left}s',
                  style: const TextStyle(color: Palette.muted, fontWeight: FontWeight.w600),
                )
              : TextButton(key: const Key('resend'), onPressed: busy ? null : _resend, child: const Text('Send a new code')),
        ),
        const SizedBox(height: 4),
        const Center(
          child: Text('Check your spam folder if it has not arrived.', style: TextStyle(fontSize: 13, color: Palette.muted)),
        ),
      ],
    );
  }
}

class ResetRequestScreen extends ConsumerStatefulWidget {
  const ResetRequestScreen({super.key, this.email = ''});
  final String email;

  @override
  ConsumerState<ResetRequestScreen> createState() => _ResetRequestScreenState();
}

class _ResetRequestScreenState extends ConsumerState<ResetRequestScreen> with _Busy {
  late final _email = TextEditingController(text: widget.email);

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!email.contains('@')) return setState(() => error = 'Enter the email you signed up with.');
    if (await run((r) => r.sendPasswordReset(email)) && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CodeScreen(email: email, purpose: CodePurpose.reset),
        ),
      );
    }
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AuthLayout(
      showBack: true,
      children: [
        Text('Reset your password', style: text.headlineMedium),
        const SizedBox(height: 6),
        Text('Enter your email and we will send you a code to choose a new password.', style: text.bodyLarge),
        const SizedBox(height: 22),
        TextField(
          key: const Key('email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          onSubmitted: (_) => _send(),
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        if (error != null) ...[const SizedBox(height: 14), ErrorNote(error!)],
        const SizedBox(height: 22),
        PrimaryButton(key: const Key('send-reset'), label: 'Send code', busy: busy, onPressed: _send),
      ],
    );
  }
}

class NewPasswordScreen extends ConsumerStatefulWidget {
  const NewPasswordScreen({super.key});

  @override
  ConsumerState<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends ConsumerState<NewPasswordScreen> with _Busy {
  final _password = TextEditingController();
  bool _show = false;

  Future<void> _save() async {
    final nav = Navigator.of(context);
    if (PasswordRules.ok(_password.text) && await run((r) => r.setNewPassword(_password.text))) {
      nav.popUntil((r) => r.isFirst);
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AuthLayout(
      heroFraction: 0.3,
      children: [
        Text('Choose a new password', style: text.headlineMedium),
        const SizedBox(height: 6),
        Text('You will use it the next time you sign in.', style: text.bodyLarge),
        const SizedBox(height: 22),
        TextField(
          key: const Key('password'),
          controller: _password,
          obscureText: !_show,
          autofillHints: const [AutofillHints.newPassword],
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            labelText: 'New password',
            suffixIcon: IconButton(
              tooltip: _show ? 'Hide password' : 'Show password',
              icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              onPressed: () => setState(() => _show = !_show),
            ),
          ),
        ),
        const SizedBox(height: 12),
        PasswordChecklist(rules: _rules(_password.text)),
        if (error != null) ...[const SizedBox(height: 14), ErrorNote(error!)],
        const SizedBox(height: 22),
        PrimaryButton(
          key: const Key('save-password'),
          label: 'Save and sign in',
          busy: busy,
          onPressed: PasswordRules.ok(_password.text) ? _save : null,
        ),
      ],
    );
  }
}
