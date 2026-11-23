import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../data/account_repository.dart';
import '../data/care_repository.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../state.dart';
import 'care_widgets.dart';

/// Takes or chooses one photo and returns its bytes. The temporary file is deleted at once,
/// so card photos are never kept on the phone. Tests replace this with fixed bytes.
final photoPickerProvider =
    Provider<Future<Uint8List?> Function(ImageSource source)>(
      (ref) => (source) async {
        final file = await ImagePicker().pickImage(
          source: source,
          maxWidth: 1600,
          imageQuality: 80,
        );
        if (file == null) return null;
        final bytes = await file.readAsBytes();
        try {
          await File(file.path).delete();
        } on FileSystemException {
          // The system already cleaned it up.
        }
        return bytes;
      },
    );

/// Insurance cards on file for one person.
final coveragesProvider = FutureProvider.autoDispose
    .family<List<Coverage>, String>(
      retry: (_, _) => null,
      (ref, patientId) =>
          ref.watch(careRepositoryProvider).coverages(patientId),
    );

String coverageStatus(String status) => switch (status) {
  'verified' => 'Verified',
  'rejected' => 'Please add it again',
  _ => 'Checking your card',
};

/// Add an insurance card: company, member ID, and a photo of each side.
class CoverageScreen extends ConsumerStatefulWidget {
  const CoverageScreen({super.key, required this.patient});
  final LinkedPatient patient;

  @override
  ConsumerState<CoverageScreen> createState() => _CoverageScreenState();
}

class _CoverageScreenState extends ConsumerState<CoverageScreen> {
  final _form = GlobalKey<FormState>();
  final _payer = TextEditingController();
  final _member = TextEditingController();
  final _group = TextEditingController();
  Uint8List? _front, _back;
  InsurancePlan? _plan;
  bool _notListed = false; // the patient types the company instead
  bool _tried = false, _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_payer, _member, _group]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(bool front) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('photo-camera'),
              leading: const IconTile(Icons.photo_camera_rounded, size: 44),
              title: const Text(
                'Take a photo',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              key: const Key('photo-gallery'),
              leading: const IconTile(Icons.photo_library_rounded, size: 44),
              title: const Text(
                'Choose from your photos',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (source == null) return;
    final bytes = await ref.read(photoPickerProvider)(source);
    if (bytes != null && mounted) {
      setState(() => front ? _front = bytes : _back = bytes);
    }
  }

  Future<void> _save() async {
    setState(() {
      _tried = true;
      _error = null;
    });
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(careRepositoryProvider)
          .addCoverage(
            patientId: widget.patient.id,
            planId: _notListed ? null : _plan!.id,
            payer: _notListed ? _payer.text.trim() : _plan!.name,
            memberId: _member.text.trim(),
            group: _group.text.trim(),
            front: _front,
            back: _back,
          );
      ref.invalidate(coveragesProvider(widget.patient.id));
      if (mounted) Navigator.of(context).pop();
    } on CoverageError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String? _required(String? v, String message) =>
      (v ?? '').trim().isEmpty ? message : null;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AuthLayout(
      heroFraction: 0.2,
      showBack: true,
      children: [
        Text('Add insurance card', style: text.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'The front desk checks it before your next visit.',
          style: text.bodyLarge,
        ),
        const SizedBox(height: 20),
        Form(
          key: _form,
          autovalidateMode: _tried
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: Column(
            children: [
              FormField<void>(
                validator: (_) => _notListed || _plan != null
                    ? null
                    : 'Choose your insurance plan.',
                builder: (field) => InkWell(
                  key: const Key('plan-picker'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    final choice = await _choosePlan(context);
                    if (choice == null) return;
                    setState(() {
                      _notListed = choice.id.isEmpty;
                      _plan = _notListed ? null : choice;
                    });
                    field.didChange(null);
                  },
                  child: InputDecorator(
                    isEmpty: _plan == null && !_notListed,
                    decoration: InputDecoration(
                      labelText: 'Insurance plan',
                      errorText: field.errorText,
                      suffixIcon: const Icon(Icons.expand_more_rounded),
                    ),
                    child: Text(
                      _notListed ? 'Not listed' : _plan?.name ?? '',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Palette.deepSea,
                      ),
                    ),
                  ),
                ),
              ),
              if (_notListed) ...[
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('payer'),
                  controller: _payer,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      _required(v, 'Enter the insurance company.'),
                  decoration: const InputDecoration(
                    labelText: 'Insurance company, as on the card',
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('member-id'),
                controller: _member,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    _required(v, 'Enter the member ID from the card.'),
                decoration: const InputDecoration(labelText: 'Member ID'),
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('group'),
                controller: _group,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Group number (optional)',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _PhotoTile(
                key: const Key('photo-front'),
                label: 'Front of card',
                bytes: _front,
                onTap: () => _pick(true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PhotoTile(
                key: const Key('photo-back'),
                label: 'Back of card',
                bytes: _back,
                onTap: () => _pick(false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: Palette.muted),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Photos are optional and help the front desk check your cover faster. They go to your private folder at Northgate and are not kept on this phone.',
                style: TextStyle(fontSize: 13, color: Palette.muted),
              ),
            ),
          ],
        ),
        if (_error != null) ...[const SizedBox(height: 14), ErrorNote(_error!)],
        const SizedBox(height: 22),
        PrimaryButton(
          key: const Key('save-coverage'),
          label: 'Save card',
          busy: _busy,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// The plan list, searchable, public programmes first. Returns a plan, or a plan with an empty ID for "not listed".
Future<InsurancePlan?> _choosePlan(BuildContext context) =>
    showModalBottomSheet<InsurancePlan>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (_) =>
          const FractionallySizedBox(heightFactor: 0.85, child: _PlanSheet()),
    );

final insurancePlansProvider = FutureProvider.autoDispose<List<InsurancePlan>>(
  retry: (_, _) => null,
  (ref) => ref.watch(careRepositoryProvider).insurancePlans(),
);

class _PlanSheet extends ConsumerStatefulWidget {
  const _PlanSheet();

  @override
  ConsumerState<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends ConsumerState<_PlanSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(insurancePlansProvider);
    final shown =
        (plans.value ?? const <InsurancePlan>[])
            .where(
              (p) => p.name.toLowerCase().contains(_query.trim().toLowerCase()),
            )
            .toList()
          ..sort(
            (a, b) => (a.kind == 'commercial' ? 1 : 0).compareTo(
              b.kind == 'commercial' ? 1 : 0,
            ),
          );
    Widget tile(InsurancePlan p) => ListTile(
      key: Key('plan-${p.name}'),
      leading: IconTile(
        p.kind == 'commercial'
            ? Icons.shield_outlined
            : Icons.account_balance_outlined,
        size: 42,
      ),
      title: Text(
        p.name,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Palette.deepSea,
        ),
      ),
      subtitle: Text(switch (p.kind) {
        'medicaid' => 'State programme (Medicaid)',
        'medicare' => 'Federal programme',
        _ => 'Private dental plan',
      }),
      onTap: () => Navigator.of(context).pop(p),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: TextField(
              key: const Key('plan-search'),
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                labelText: 'Search plans',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: plans.hasError
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Could not load the plans. You can still type your plan below.',
                    ),
                  )
                : ListView(
                    children: [
                      for (final p in shown) tile(p),
                      const Divider(height: 24),
                      ListTile(
                        key: const Key('plan-other'),
                        leading: const IconTile(Icons.edit_outlined, size: 42),
                        title: const Text(
                          'My plan is not listed',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Palette.deepSea,
                          ),
                        ),
                        subtitle: const Text(
                          'Type the company name from your card',
                        ),
                        onTap: () => Navigator.of(context).pop(
                          const InsurancePlan(
                            id: '',
                            name: '',
                            kind: 'commercial',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    super.key,
    required this.label,
    required this.bytes,
    required this.onTap,
  });
  final String label;
  final Uint8List? bytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: bytes == null
        ? 'Add $label photo'
        : '$label photo added. Tap to retake.',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 1.586, // a bank-card shape
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Palette.enamel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: bytes == null ? Palette.line : Palette.teal,
              width: bytes == null ? 1 : 2,
            ),
          ),
          child: ExcludeSemantics(
            child: bytes == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.add_a_photo_rounded,
                        color: Palette.teal,
                        size: 28,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Palette.deepSea,
                        ),
                      ),
                    ],
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
                        bytes!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: Palette.enamel),
                      ),
                      const Positioned(
                        right: 8,
                        top: 8,
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: Palette.teal,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    ),
  );
}

/// Profile section: cards on file and the button to add one.
class CoveragePanel extends ConsumerWidget {
  const CoveragePanel({super.key, required this.patient});
  final LinkedPatient patient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(coveragesProvider(patient.id)).value ?? const [];
    void add() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => CoverageScreen(patient: patient)));
    return RowGroup(
      title: 'Insurance',
      rows: [
        for (final c in cards)
          GroupRow(
            icon: Icons.shield_outlined,
            tint: c.status == 'rejected' ? Tint.rose : Tint.apricot,
            title: c.payer,
            detail: coverageStatus(c.status),
            trailing: c.status == 'verified'
                ? Icon(Icons.verified_rounded, color: Tint.teal.ink)
                : null,
          ),
        GroupRow(
          key: const Key('add-coverage'),
          icon: Icons.add_card_rounded,
          tint: Tint.apricot,
          title: cards.isEmpty ? 'Add insurance card' : 'Add another card',
          detail: cards.isEmpty
              ? 'So the front desk can check your cover before your visit'
              : null,
          onTap: add,
        ),
      ],
    );
  }
}
