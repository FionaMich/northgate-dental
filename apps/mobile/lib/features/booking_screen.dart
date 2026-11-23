import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/account_repository.dart';
import '../data/care_repository.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../state.dart';
import 'care_widgets.dart';
import 'clinic_screen.dart';
import 'dentist_screen.dart';

/// Services the patient may book at one clinic.
final bookableServicesProvider = FutureProvider.autoDispose
    .family<List<BookableService>, String>(
      retry: (_, _) => null,
      (ref, clinicId) => ref.watch(careRepositoryProvider).services(clinicId),
    );

/// Free times for a clinic and service over the next 14 days.
final slotsProvider = FutureProvider.autoDispose
    .family<List<Slot>, (String, String)>(
      retry: (_, _) => null,
      (ref, key) => ref
          .watch(careRepositoryProvider)
          .slots(key.$1, key.$2, DateTime.now()),
    );

/// Book a visit: clinic, service, day, time, then a 10-minute hold to confirm.
class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({
    super.key,
    required this.patient,
    this.dentistId,
    this.clinicId,
    this.serviceId,
    this.replaces,
    this.category,
  });

  /// Start with the service list filtered to this group (from "Our services" on Home).
  final String? category;
  final LinkedPatient patient;

  /// Start with this dentist, clinic and service chosen (from a dentist's profile, or when rescheduling).
  final String? dentistId, clinicId, serviceId;

  /// Rescheduling: the visit to cancel once the new time is confirmed (never before, so nobody is left unbooked).
  final Appointment? replaces;

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  late String? _clinic = widget.clinicId;
  late String? _dentist = widget.dentistId; // null: any available dentist
  late String? _service = widget.serviceId;
  late String? _category = widget.category;
  String _search = '';
  DateTime? _day;
  Slot? _slot;
  bool _busy = false;
  String? _error;

  void _pickClinic(String id) => setState(() {
    _clinic = id;
    _service = _day = _slot = null;
    _error = null;
  });

  Future<void> _hold(
    List<Clinic> clinics,
    List<BookableService> services,
  ) async {
    final slot = _slot!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(careRepositoryProvider)
          .hold(
            clinicId: _clinic!,
            serviceId: _service!,
            slot: slot,
            patientId: widget.patient.id,
          );
      if (!mounted) return;
      setState(
        () => _busy = false,
      ); // the hold is in place; the sheet takes over
      final booked = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        builder: (_) => _HoldSheet(
          appointmentId: id,
          slot: slot,
          service: services.firstWhere((s) => s.id == _service),
          clinic: clinics.firstWhere((c) => c.id == _clinic),
        ),
      );
      if (!mounted) return;
      if (booked == true) {
        if (widget.replaces case final old?) {
          try {
            await ref.read(careRepositoryProvider).cancel(old.id);
          } on BookingError {
            // The new visit stands; the old one stays visible so the patient can cancel it by hand.
          }
        }
        ref.invalidate(careSummaryProvider);
        if (mounted) Navigator.of(context).pop();
      } else {
        setState(() => _slot = null);
        ref.invalidate(slotsProvider((_clinic!, _service!)));
      }
    } on BookingError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _slot = null;
      });
      ref.invalidate(slotsProvider((_clinic!, _service!)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinics = ref.watch(clinicsProvider).value;
    final details = ref.watch(patientDetailsProvider(widget.patient.id)).value;
    final clinic = _clinic ?? details?.clinicId ?? clinics?.firstOrNull?.id;
    final services = clinic == null
        ? null
        : ref.watch(bookableServicesProvider(clinic));
    final slots = clinic == null || _service == null
        ? null
        : ref.watch(slotsProvider((clinic, _service!)));
    _clinic ??= clinic;

    final allSlots = slots?.value ?? const <Slot>[];
    final team = ref.watch(dentistsProvider).value ?? const <Dentist>[];
    final offering = [
      for (final d in team)
        if (allSlots.any((s) => s.practitionerId == d.id)) d,
    ];
    // One time per start for "any dentist"; only the chosen dentist's times otherwise.
    final seenStarts = <DateTime>{};
    final shown = [
      for (final s in allSlots)
        if (_dentist == null
            ? seenStarts.add(s.startsAt)
            : s.practitionerId == _dentist)
          s,
    ];
    final days = <DateTime, List<Slot>>{};
    for (final s in shown) {
      days
          .putIfAbsent(
            DateTime(s.startsAt.year, s.startsAt.month, s.startsAt.day),
            () => [],
          )
          .add(s);
    }
    final day = _day ?? days.keys.firstOrNull;
    final times = days[day] ?? const <Slot>[];

    return Scaffold(
      backgroundColor: Palette.mist,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _Header(
              clinics: clinics ?? const [],
              selected: clinic,
              onPick: _pickClinic,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 140),
            sliver: SliverList.list(
              children: [
                const SectionTitle('What do you need?'),
                switch (services) {
                  null || AsyncLoading() => const _Loading(),
                  AsyncError() => const EmptyNote(
                    icon: Icons.wifi_off_rounded,
                    title: 'Could not load services',
                    body: 'Check your connection and try again.',
                  ),
                  AsyncData(:final value) => Column(
                    children: [
                      TextField(
                        key: const Key('service-search'),
                        onChanged: (v) =>
                            setState(() => _search = v.trim().toLowerCase()),
                        decoration: const InputDecoration(
                          labelText: 'Search services',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final cat in [
                              null,
                              ...{for (final s in value) s.category},
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  key: Key('category-${cat ?? 'all'}'),
                                  label: Text(cat ?? 'All'),
                                  selected: _category == cat,
                                  onSelected: (_) =>
                                      setState(() => _category = cat),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final s in value.where(
                        (s) =>
                            (_category == null || s.category == _category) &&
                            (_search.isEmpty ||
                                '${s.name} ${s.summary}'.toLowerCase().contains(
                                  _search,
                                )),
                      ))
                        _Choice(
                          key: Key('service-${s.id}'),
                          selected: s.id == _service,
                          title: s.name,
                          minutes: s.minutes,
                          summary: s.summary,
                          photo: s.photoAsset,
                          onTap: () => setState(() {
                            _service = s.id;
                            _day = _slot = null;
                            _error = null;
                          }),
                        ),
                    ],
                  ),
                },
                if (_service != null && offering.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  const SectionTitle('Choose your dentist'),
                  _DentistChoice(
                    key: const Key('dentist-any'),
                    title: 'Any available dentist',
                    detail: 'The earliest times at this clinic',
                    selected: _dentist == null,
                    onTap: () => setState(() {
                      _dentist = null;
                      _day = _slot = null;
                    }),
                  ),
                  for (final d in offering)
                    _DentistChoice(
                      key: Key('dentist-${d.id}'),
                      dentist: d,
                      title: d.name,
                      detail: d.title,
                      selected: _dentist == d.id,
                      onTap: () => setState(() {
                        _dentist = d.id;
                        _day = _slot = null;
                      }),
                      onInfo: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DentistScreen(dentist: d),
                        ),
                      ),
                    ),
                ],
                if (_service != null) ...[
                  const SizedBox(height: 26),
                  SectionTitle(
                    days.isEmpty
                        ? 'Pick a day'
                        : 'Pick a day · ${monthYear(days.keys.first)}',
                  ),
                  if (slots == null || slots.isLoading)
                    const _Loading()
                  else if (slots.hasError)
                    const EmptyNote(
                      icon: Icons.wifi_off_rounded,
                      title: 'Could not load times',
                      body: 'Check your connection and try again.',
                    )
                  else if (days.isEmpty)
                    const EmptyNote(
                      icon: Icons.event_busy_rounded,
                      title: 'No free times in the next two weeks',
                      body: 'Try another clinic, or call the practice and we will find you a time.',
                    )
                  else ...[
                    SizedBox(
                      height: 104,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: days.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (_, i) {
                          final d = days.keys.elementAt(i);
                          return _DayTile(
                            key: Key('day-$i'),
                            day: d,
                            count: days[d]!.length,
                            selected: d == day,
                            onTap: () => setState(() {
                              _day = d;
                              _slot = null;
                            }),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 26),
                    SectionTitle(
                      'Pick a time · ${weekday(day!)} ${dayMonth(day)}',
                    ),
                    _TimeGrid(
                      times: times,
                      selected: _slot,
                      onPick: (s) => setState(() => _slot = s),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Times are local to the clinic.',
                      style: TextStyle(fontSize: 13, color: Palette.muted),
                    ),
                  ],
                ],
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  ErrorNote(_error!),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _slot == null
          ? null
          : SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: lift(1.2),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${weekday(_slot!.startsAt)} ${dayMonth(_slot!.startsAt)}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Palette.muted,
                            ),
                          ),
                          Text(
                            '${clock(_slot!.startsAt)} to ${clock(_slot!.endsAt)}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Palette.deepSea,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 168,
                      child: PrimaryButton(
                        key: const Key('hold'),
                        label: 'Hold this time',
                        busy: _busy,
                        onPressed: () => _hold(clinics!, services!.value!),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.clinics,
    required this.selected,
    required this.onPick,
  });
  final List<Clinic> clinics;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: heroGradient,
      image: heroPhoto,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
    ),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              tooltip: 'Back',
              color: Colors.white,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 14),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Book a visit',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (clinics.where((c) => c.id == selected).firstOrNull
                      case final c?)
                    TextButton.icon(
                      key: const Key('about-clinic'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF8FE3C8),
                      ),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ClinicScreen(clinic: c),
                        ),
                      ),
                      icon: const Icon(Icons.info_outline_rounded, size: 18),
                      label: const Text('Clinic info'),
                    ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (final c in clinics)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Pressable(
                        onTap: () => onPick(c.id),
                        child: InkWell(
                          key: Key('clinic-${c.id}'),
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => onPick(c.id),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: c.id == selected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.location_on_rounded,
                                  size: 16,
                                  color: c.id == selected
                                      ? Palette.teal
                                      : Colors.white70,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  c.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: c.id == selected
                                        ? Palette.deepSea
                                        : Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A service card: name, length and what happens; teal ring when chosen.
class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.selected,
    required this.title,
    required this.minutes,
    required this.summary,
    required this.photo,
    required this.onTap,
  });
  final bool selected;
  final String title, summary, photo;
  final int minutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Semantics(
      button: true,
      selected: selected,
      child: Pressable(
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: selected ? Palette.enamel : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? Palette.teal : Palette.line,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    photo,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    excludeFromSemantics: true,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                                color: Palette.deepSea,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Palette.mist,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$minutes min',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Palette.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (summary.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          summary,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: Palette.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected ? Palette.teal : Palette.line,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    super.key,
    required this.day,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final DateTime day;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${weekday(day)} ${dayMonth(day)}, $count times',
    child: Pressable(
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 66,
          decoration: BoxDecoration(
            gradient: selected ? buttonGradient : null,
            color: selected ? null : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? Colors.transparent : Palette.line,
            ),
            boxShadow: selected ? lift(0.8) : null,
          ),
          child: ExcludeSemantics(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  weekday(day),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? const Color(0xFFCDEFE7) : Palette.muted,
                  ),
                ),
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : Palette.deepSea,
                  ),
                ),
                Text(
                  count == 1 ? '1 time' : '$count times',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected ? const Color(0xFFCDEFE7) : Palette.teal,
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

/// Times split into morning and afternoon, as pills.
class _TimeGrid extends StatelessWidget {
  const _TimeGrid({
    required this.times,
    required this.selected,
    required this.onPick,
  });
  final List<Slot> times;
  final Slot? selected;
  final ValueChanged<Slot> onPick;

  @override
  Widget build(BuildContext context) {
    final groups = [
      ('Morning', times.where((s) => s.startsAt.hour < 12)),
      ('Afternoon', times.where((s) => s.startsAt.hour >= 12)),
    ];
    var index = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, slots) in groups)
          if (slots.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 10),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Palette.muted,
                ),
              ),
            ),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.4,
              children: [
                for (final s in slots)
                  Builder(
                    builder: (_) {
                      final on = selected?.startsAt == s.startsAt;
                      return Semantics(
                        button: true,
                        selected: on,
                        child: InkWell(
                          key: Key('slot-${index++}'),
                          onTap: () => onPick(s),
                          borderRadius: BorderRadius.circular(14),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: on ? Palette.teal : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: on ? Palette.teal : Palette.line,
                              ),
                            ),
                            child: Text(
                              clock(s.startsAt),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: on ? Colors.white : Palette.deepSea,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

/// The held time, a 10-minute countdown, and Confirm. Shows "You are booked" only after the server confirms.
class _HoldSheet extends ConsumerStatefulWidget {
  const _HoldSheet({
    required this.appointmentId,
    required this.slot,
    required this.service,
    required this.clinic,
  });
  final String appointmentId;
  final Slot slot;
  final BookableService service;
  final Clinic clinic;

  @override
  ConsumerState<_HoldSheet> createState() => _HoldSheetState();
}

class _HoldSheetState extends ConsumerState<_HoldSheet> {
  static const _holdSeconds = 600;
  int _left = _holdSeconds;
  Timer? _timer;
  bool _busy = false;
  bool _booked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) {
        t.cancel();
        setState(() => _error = holdExpiredError);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(careRepositoryProvider).confirm(widget.appointmentId);
      _timer?.cancel();
      if (mounted) setState(() => _booked = true);
    } on BookingError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _release() async {
    _timer?.cancel();
    try {
      await ref.read(careRepositoryProvider).cancel(widget.appointmentId);
    } on BookingError {
      // The hold expires on its own within 10 minutes; nothing else to do.
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.slot;
    final expired = _left <= 0;
    final mmss =
        '${(_left ~/ 60).clamp(0, 10)}:${(_left % 60).clamp(0, 59).toString().padLeft(2, '0')}';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: _booked
              ? Column(
                  key: const ValueKey('booked'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    const Center(
                      child: Reveal(
                        child: IconTile(Icons.check_rounded, size: 72),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'You are booked',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.service.name} at ${widget.clinic.name}, ${weekday(s.startsAt)} ${dayMonth(s.startsAt)} at ${clock(s.startsAt)}.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Palette.muted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      key: const Key('booking-done'),
                      label: 'Done',
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ],
                )
              : Column(
                  key: const ValueKey('held'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Confirm your visit',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: expired
                                ? const Color(0xFFFBE4E2)
                                : const Color(0xFFFFF1E4),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            expired ? 'Expired' : mmss,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: expired
                                  ? Palette.error
                                  : const Color(0xFFB35F1E),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      expired
                          ? ''
                          : 'Held for you for $mmss. Nothing is booked until you confirm.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Palette.muted,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Panel(
                      child: Column(
                        children: [
                          _Row(
                            Icons.medical_services_outlined,
                            widget.service.name,
                            '${widget.service.minutes} minutes',
                          ),
                          const Divider(height: 24, color: Palette.line),
                          _Row(
                            Icons.event_rounded,
                            '${weekday(s.startsAt)} ${dayMonthYear(s.startsAt)}',
                            '${clock(s.startsAt)} to ${clock(s.endsAt)}',
                          ),
                          const Divider(height: 24, color: Palette.line),
                          _Row(
                            Icons.location_on_outlined,
                            widget.clinic.name,
                            widget.clinic.address,
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      ErrorNote(_error!),
                    ],
                    const SizedBox(height: 22),
                    PrimaryButton(
                      key: const Key('confirm-booking'),
                      label: 'Confirm booking',
                      busy: _busy,
                      onPressed: expired ? null : _confirm,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      key: const Key('release-hold'),
                      onPressed: _busy ? null : _release,
                      child: const Text('Choose another time'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.title, this.subtitle);
  final IconData icon;
  final String title, subtitle;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconTile(icon, size: 42),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Palette.deepSea,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 13, color: Palette.muted),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
  );
}

/// One choice in "Choose your dentist": a photo (or the team icon for "any"), name and role; the info button opens the profile.
class _DentistChoice extends StatelessWidget {
  const _DentistChoice({
    super.key,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
    this.dentist,
    this.onInfo,
  });
  final Dentist? dentist;
  final String title, detail;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onInfo;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          decoration: BoxDecoration(
            color: selected ? Palette.enamel : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? Palette.teal : Palette.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              dentist == null
                  ? const TintIcon(Icons.groups_rounded, Tint.teal, size: 52)
                  : DentistAvatar(
                      name: dentist!.name,
                      asset: dentist!.photoAsset,
                    ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Palette.deepSea,
                      ),
                    ),
                    Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (onInfo != null)
                IconButton(
                  tooltip: 'About $title',
                  onPressed: onInfo,
                  icon: const Icon(
                    Icons.info_outline_rounded,
                    color: Palette.teal,
                  ),
                ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? Palette.teal : Palette.line,
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    ),
  );
}
