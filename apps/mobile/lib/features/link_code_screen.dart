import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/account_repository.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../state.dart';

/// Shown until the sign-in is linked to a patient record. The patient confirms their date of birth;
/// the record must already use the email they proved at sign-up. A front-desk code is the fallback.
class LinkCodeScreen extends ConsumerStatefulWidget {
  const LinkCodeScreen({super.key});

  @override
  ConsumerState<LinkCodeScreen> createState() => _LinkCodeScreenState();
}

class _LinkCodeScreenState extends ConsumerState<LinkCodeScreen> {
  final _dob = TextEditingController();
  final _code = TextEditingController();
  bool _useCode = false;
  String? _error;
  bool _busy = false;

  /// MM/DD/YYYY as typed, or null if it is not a real past date.
  DateTime? get _birthDate {
    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(_dob.text);
    if (m == null) return null;
    final (month, day, year) = (int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    final d = DateTime(year, month, day);
    final real = d.month == month && d.day == day && year >= 1900 && d.isBefore(DateTime.now());
    return real ? d : null;
  }

  Future<void> _go(Future<String?> Function(AccountRepository repo) attempt) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final problem = await attempt(ref.read(accountRepositoryProvider));
      if (problem == null) {
        ref.invalidate(linkedPatientsProvider);
      } else if (mounted) {
        setState(() => _error = problem);
      }
    } on AccountError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _linkWithBirthDate() async {
    final dob = _birthDate;
    if (dob == null) return setState(() => _error = 'Enter your date of birth as MM/DD/YYYY.');
    await _go(
      (r) async => switch (await r.linkByBirthDate(dob)) {
        LinkOutcome.linked => null,
        LinkOutcome.noMatch =>
          'We could not find a record for your email with that date of birth. Check the date, or use a code from the front desk.',
        LinkOutcome.locked => 'Too many tries. Ask the front desk for a code, or try again tomorrow.',
      },
    );
  }

  Future<void> _linkWithCode() => _go((r) async {
    await r.redeemCode(_code.text);
    return null;
  });

  @override
  void dispose() {
    _dob.dispose();
    _code.dispose();
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
                  Stack(
                    children: [
                      HeroStage(height: (box.maxHeight * 0.36).clamp(220, 320), quietCorner: true),
                      Positioned(
                        right: 8,
                        top: 8 + MediaQuery.paddingOf(context).top,
                        child: TextButton(
                          key: const Key('sign-out'),
                          style: TextButton.styleFrom(foregroundColor: Colors.white),
                          onPressed: () => ref.read(accountRepositoryProvider).signOut(),
                          child: const Text('Sign out'),
                        ),
                      ),
                    ],
                  ),
                  BottomSheetPanel(
                    children: [
                      Text(_useCode ? 'Use a front-desk code' : 'Find your record', style: text.headlineMedium),
                      const SizedBox(height: 6),
                      Text(
                        _useCode
                            ? 'Enter the 16-character code from the front desk. It works once and lasts 7 days.'
                            : 'Confirm your date of birth and we will find the record that uses this email.',
                        style: text.bodyLarge,
                      ),
                      const SizedBox(height: 22),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _useCode
                            ? TextField(
                                key: const Key('code'),
                                controller: _code,
                                textCapitalization: TextCapitalization.characters,
                                autocorrect: false,
                                enableSuggestions: false,
                                maxLength: 16,
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]'))],
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 3, color: Palette.deepSea),
                                onSubmitted: (_) => _linkWithCode(),
                                decoration: const InputDecoration(labelText: 'Code', counterText: ''),
                              )
                            : TextField(
                                key: const Key('dob'),
                                controller: _dob,
                                keyboardType: TextInputType.number,
                                autofillHints: const [AutofillHints.birthday],
                                inputFormatters: [_DateMask()],
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 2, color: Palette.deepSea),
                                onSubmitted: (_) => _linkWithBirthDate(),
                                decoration: const InputDecoration(labelText: 'Date of birth', hintText: 'MM/DD/YYYY'),
                              ),
                      ),
                      if (_error != null) ...[const SizedBox(height: 14), ErrorNote(_error!)],
                      const SizedBox(height: 22),
                      PrimaryButton(
                        key: const Key('link'),
                        label: 'Link my record',
                        busy: _busy,
                        onPressed: _useCode ? _linkWithCode : _linkWithBirthDate,
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          key: const Key('switch-link-method'),
                          onPressed: () => setState(() {
                            _useCode = !_useCode;
                            _error = null;
                          }),
                          child: Text(_useCode ? 'Use my date of birth instead' : 'I have a code from the front desk'),
                        ),
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

/// Keeps digits only and adds the slashes: 04121988 becomes 04/12/1988.
class _DateMask extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue next) {
    final digits = next.text.replaceAll(RegExp(r'\D'), '');
    final d = digits.length > 8 ? digits.substring(0, 8) : digits;
    final out = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 2 || i == 4) out.write('/');
      out.write(d[i]);
    }
    final s = out.toString();
    return TextEditingValue(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    );
  }
}
