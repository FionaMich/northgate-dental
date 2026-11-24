import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dental/ui.dart';

import '../data/account_repository.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../state.dart';

/// Shown until the sign-in has a patient record. Existing patients confirm their date of birth (the record must
/// already use the email proved at sign-up); new patients register and a record is created for them.
class LinkCodeScreen extends ConsumerStatefulWidget {
  const LinkCodeScreen({super.key});

  @override
  ConsumerState<LinkCodeScreen> createState() => _LinkCodeScreenState();
}

class _LinkCodeScreenState extends ConsumerState<LinkCodeScreen> {
  final _dob = TextEditingController();
  final _given = TextEditingController();
  final _family = TextEditingController();
  String? _sex;
  bool _newPatient = false;
  String? _error;
  bool _busy = false;

  /// MM/DD/YYYY as typed, or null if it is not a real past date.
  DateTime? get _birthDate {
    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(_dob.text);
    if (m == null) return null;
    final (month, day, year) = (
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
    );
    final d = DateTime(year, month, day);
    final real =
        d.month == month &&
        d.day == day &&
        year >= 1900 &&
        d.isBefore(DateTime.now());
    return real ? d : null;
  }

  Future<void> _go(
    Future<String?> Function(AccountRepository repo) attempt,
  ) async {
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
    if (dob == null) {
      return setState(() => _error = 'Enter your date of birth as MM/DD/YYYY.');
    }
    await _go(
      (r) async => switch (await r.linkByBirthDate(dob)) {
        LinkOutcome.linked => null,
        LinkOutcome.noMatch => 'We could not find a record for your email with that date of birth. Check the date, or register as a new patient.',
        LinkOutcome.locked =>
          'Too many tries. Please call the practice, or try again tomorrow.',
      },
    );
  }

  Future<void> _register() async {
    final dob = _birthDate;
    if (_given.text.trim().isEmpty || _family.text.trim().isEmpty) {
      return setState(() => _error = 'Enter your first and last name.');
    }
    if (dob == null) {
      return setState(() => _error = 'Enter your date of birth as MM/DD/YYYY.');
    }
    if (_sex == null) {
      return setState(() => _error = 'Choose an option for sex at birth.');
    }
    await _go((r) async {
      await r.registerNewPatient(
        given: _given.text.trim(),
        family: _family.text.trim(),
        birthDate: dob,
        sex: _sex!,
      );
      return null;
    });
  }

  @override
  void dispose() {
    for (final c in [_dob, _given, _family]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: heroGradient,
          image: heroPhoto,
        ),
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Stack(
                    children: [
                      HeroStage(
                        height: (box.maxHeight * 0.36).clamp(220, 320),
                        quietCorner: true,
                      ),
                      Positioned(
                        right: 8,
                        top: 8 + MediaQuery.paddingOf(context).top,
                        child: TextButton(
                          key: const Key('sign-out'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () =>
                              ref.read(accountRepositoryProvider).signOut(),
                          child: const Text('Sign out'),
                        ),
                      ),
                    ],
                  ),
                  BottomSheetPanel(
                    children: [
                      Text(
                        _newPatient
                            ? 'Register as a new patient'
                            : 'Find your record',
                        style: text.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _newPatient
                            ? 'Tell us who you are and we will create your Northgate record.'
                            : 'Confirm your date of birth and we will find the record that uses this email.',
                        style: text.bodyLarge,
                      ),
                      const SizedBox(height: 18),
                      SegmentedButton<bool>(
                        key: const Key('patient-kind'),
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('I am a patient'),
                          ),
                          ButtonSegment(value: true, label: Text('I am new')),
                        ],
                        selected: {_newPatient},
                        onSelectionChanged: (v) => setState(() {
                          _newPatient = v.first;
                          _error = null;
                        }),
                      ),
                      const SizedBox(height: 20),
                      if (_newPatient) ...[
                        TextField(
                          key: const Key('given-name'),
                          controller: _given,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.givenName],
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: tr('First name'),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          key: const Key('family-name'),
                          controller: _family,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.familyName],
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: tr('Last name'),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextField(
                        key: const Key('dob'),
                        controller: _dob,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.birthday],
                        inputFormatters: [_DateMask()],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: Palette.deepSea,
                        ),
                        onSubmitted: (_) =>
                            _newPatient ? _register() : _linkWithBirthDate(),
                        decoration: InputDecoration(
                          labelText: tr('Date of birth'),
                          hintText: 'MM/DD/YYYY',
                        ),
                      ),
                      if (_newPatient) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Sex at birth',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Palette.deepSea,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final (value, label) in const [
                              ('female', 'Female'),
                              ('male', 'Male'),
                              ('unknown', 'Prefer not to say'),
                            ])
                              ChoiceChip(
                                key: Key('sex-$value'),
                                label: Text(label),
                                selected: _sex == value,
                                onSelected: (_) => setState(() => _sex = value),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Used for your dental care only. Children under 18 are added by a parent or guardian at the practice.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: Palette.muted,
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        ErrorNote(_error!),
                      ],
                      const SizedBox(height: 22),
                      PrimaryButton(
                        key: const Key('link'),
                        label: _newPatient
                            ? 'Create my record'
                            : 'Find my record',
                        busy: _busy,
                        onPressed: _newPatient ? _register : _linkWithBirthDate,
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
  TextEditingValue formatEditUpdate(
    TextEditingValue old,
    TextEditingValue next,
  ) {
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
