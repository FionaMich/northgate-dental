import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/account_repository.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../state.dart';
import 'care_widgets.dart';

/// Preferred clinic and home address. Shown once after linking, and from Profile to edit.
class DetailsScreen extends ConsumerWidget {
  const DetailsScreen({super.key, required this.patient, this.editing = false});
  final LinkedPatient patient;
  final bool editing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinics = ref.watch(clinicsProvider);
    final details = ref.watch(patientDetailsProvider(patient.id));
    if (clinics.hasError || details.hasError) {
      return AuthLayout(
        heroFraction: 0.22,
        showBack: editing,
        children: [
          const EmptyNote(
            icon: Icons.wifi_off_rounded,
            title: 'Could not load your details',
            body: 'Check your connection, then try again.',
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => ref
              ..invalidate(clinicsProvider)
              ..invalidate(patientDetailsProvider(patient.id)),
            child: const Text('Try again'),
          ),
        ],
      );
    }
    if (!clinics.hasValue || !details.hasValue) {
      return const AuthLayout(heroFraction: 0.22, children: [LoadingPanels()]);
    }
    return _DetailsForm(patient: patient, editing: editing, clinics: clinics.value!, initial: details.value!);
  }
}

class _DetailsForm extends ConsumerStatefulWidget {
  const _DetailsForm({required this.patient, required this.editing, required this.clinics, required this.initial});
  final LinkedPatient patient;
  final bool editing;
  final List<Clinic> clinics;
  final PatientDetails initial;

  @override
  ConsumerState<_DetailsForm> createState() => _DetailsFormState();
}

class _DetailsFormState extends ConsumerState<_DetailsForm> {
  final _form = GlobalKey<FormState>();
  late String? _clinic = widget.initial.clinicId;
  late final _line1 = TextEditingController(text: widget.initial.line1);
  late final _line2 = TextEditingController(text: widget.initial.line2);
  late final _city = TextEditingController(text: widget.initial.city);
  late final _state = TextEditingController(text: widget.initial.state.isEmpty ? 'MA' : widget.initial.state);
  late final _zip = TextEditingController(text: widget.initial.zip);
  bool _busy = false;
  bool _tried = false; // after the first Save, errors update as the person types
  String? _error;

  @override
  void dispose() {
    for (final c in [_line1, _line2, _city, _state, _zip]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_tried) setState(() => _tried = true);
    if (!_form.currentState!.validate()) return;
    if (_clinic == null) return setState(() => _error = 'Choose the clinic you would like to visit.');
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(accountRepositoryProvider);
    var line1 = _line1.text.trim(), city = _city.text.trim(), state = _state.text.trim().toUpperCase(), zip = _zip.text.trim();
    final i = widget.initial;
    final unchanged = line1 == i.line1 && city == i.city && state == i.state && zip == i.zip;
    try {
      // A new or changed address must be a real one: check it, and save the official form the patient confirms.
      if (!unchanged) {
        final matches = await repo.verifyAddress(line1: line1, city: city, state: state, zip: zip);
        if (matches.isEmpty) {
          if (mounted) {
            setState(() => _error = 'We could not find that address. Check the street number, street name and ZIP code.');
          }
          return;
        }
        if (!mounted) return;
        setState(() => _busy = false);
        final picked = await _confirmAddress(context, matches);
        if (picked == null || !mounted) return;
        setState(() => _busy = true);
        (line1, city, state, zip) = (picked.line1, picked.city, picked.state, picked.zip);
      }
      await repo.saveDetails(
        widget.patient.id,
        PatientDetails(clinicId: _clinic, line1: line1, line2: _line2.text.trim(), city: city, state: state, zip: zip),
      );
      ref.invalidate(patientDetailsProvider(widget.patient.id));
      if (widget.editing) {
        if (mounted) Navigator.of(context).pop();
      } else {
        ref.invalidate(linkedPatientsProvider); // the gate moves on to Home
      }
    } on AccountError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String? _required(String? v, String message) => (v ?? '').trim().isEmpty ? message : null;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AuthLayout(
      heroFraction: 0.22,
      showBack: widget.editing,
      children: [
        Text(widget.editing ? 'Clinic and address' : 'Choose your clinic', style: text.headlineMedium),
        const SizedBox(height: 6),
        Text(
          widget.editing
              ? 'Changes apply to your next booking.'
              : 'Welcome, ${widget.patient.firstName}. Pick where you would like your visits; you can change it any time.',
          style: text.bodyLarge,
        ),
        const SizedBox(height: 20),
        for (final (i, c) in widget.clinics.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Reveal(
              order: i,
              child: _ClinicCard(clinic: c, selected: c.id == _clinic, onTap: () => setState(() => _clinic = c.id)),
            ),
          ),
        const SizedBox(height: 18),
        const SectionTitle('Home address'),
        Form(
          key: _form,
          autovalidateMode: _tried ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          child: AutofillGroup(
            child: Column(
              children: [
                TextFormField(
                  key: const Key('line1'),
                  controller: _line1,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.streetAddressLine1],
                  textInputAction: TextInputAction.next,
                  validator: (v) => _required(v, 'Enter your street address.'),
                  decoration: const InputDecoration(labelText: 'Street address'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('line2'),
                  controller: _line2,
                  autofillHints: const [AutofillHints.streetAddressLine2],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Apartment or suite (optional)'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('city'),
                  controller: _city,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.addressCity],
                  textInputAction: TextInputAction.next,
                  validator: (v) => _required(v, 'Enter your city or town.'),
                  decoration: const InputDecoration(labelText: 'City or town'),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 104,
                      child: TextFormField(
                        key: const Key('state'),
                        controller: _state,
                        textCapitalization: TextCapitalization.characters,
                        autofillHints: const [AutofillHints.addressState],
                        textInputAction: TextInputAction.next,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')), LengthLimitingTextInputFormatter(2)],
                        validator: (v) => RegExp(r'^[A-Za-z]{2}$').hasMatch((v ?? '').trim()) ? null : '2 letters',
                        decoration: const InputDecoration(labelText: 'State'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const Key('zip'),
                        controller: _zip,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.postalCode],
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9-]')), LengthLimitingTextInputFormatter(10)],
                        onFieldSubmitted: (_) => _save(),
                        validator: (v) => RegExp(r'^[0-9]{5}(-[0-9]{4})?$').hasMatch((v ?? '').trim()) ? null : 'Enter a 5-digit ZIP code.',
                        decoration: const InputDecoration(labelText: 'ZIP code'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: Palette.muted),
            SizedBox(width: 6),
            Expanded(
              child: Text('Only your care team sees your address.', style: TextStyle(fontSize: 13, color: Palette.muted)),
            ),
          ],
        ),
        if (_error != null) ...[const SizedBox(height: 14), ErrorNote(_error!)],
        const SizedBox(height: 22),
        PrimaryButton(
          key: const Key('save-details'),
          label: widget.editing ? 'Save changes' : 'Save and continue',
          busy: _busy,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// "Is this your address?": the official form(s) the Census Bureau found. Returns the one picked, or null to edit.
Future<AddressMatch?> _confirmAddress(BuildContext context, List<AddressMatch> matches) => showModalBottomSheet<AddressMatch>(
  context: context,
  backgroundColor: Colors.white,
  showDragHandle: true,
  isScrollControlled: true,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: IconTile(Icons.where_to_vote_rounded, size: 64)),
          const SizedBox(height: 16),
          Text('Is this your address?', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          const Text(
            'We checked it against the US Census Bureau address list.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Palette.muted),
          ),
          const SizedBox(height: 18),
          for (final (n, m) in matches.indexed) ...[
            Panel(
              onTap: () => Navigator.of(context).pop(m),
              child: Row(
                key: Key('address-match-$n'),
                children: [
                  const Icon(Icons.home_rounded, color: Palette.teal),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      m.oneLine,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Palette.deepSea),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Palette.muted),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Edit the address')),
        ],
      ),
    ),
  ),
);

/// A selectable clinic: teal ring and check when chosen.
class _ClinicCard extends StatelessWidget {
  const _ClinicCard({required this.clinic, required this.selected, required this.onTap});
  final Clinic clinic;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${clinic.name}, ${clinic.address}',
    child: Pressable(
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('clinic-${clinic.id}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? Palette.enamel : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? Palette.teal : Palette.line, width: selected ? 2 : 1),
              boxShadow: selected ? lift(0.6) : null,
            ),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  const IconTile(Icons.location_on_rounded, size: 44),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          clinic.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Palette.deepSea),
                        ),
                        const SizedBox(height: 2),
                        Text(clinic.address, style: const TextStyle(fontSize: 13, height: 1.35, color: Palette.muted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                    child: selected
                        ? const Icon(Icons.check_circle_rounded, key: ValueKey(true), color: Palette.teal, size: 26)
                        : const Icon(Icons.circle_outlined, key: ValueKey(false), color: Palette.line, size: 26),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
