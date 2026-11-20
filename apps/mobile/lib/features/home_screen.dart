import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/care_repository.dart';
import '../design/art.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../state.dart';
import 'booking_screen.dart';
import 'care_widgets.dart';
import 'plan_screen.dart';
import 'shell.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final care = ref.watch(careSummaryProvider);
    return RefreshIndicator(
      color: Palette.teal,
      onRefresh: () => ref.refresh(careSummaryProvider.future),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          const _Header(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Transform.translate(
              offset: const Offset(0, -34),
              child: care.when(
                loading: () => const LoadingPanels(),
                error: (_, _) => Panel(
                  onTap: () => ref.invalidate(careSummaryProvider),
                  child: const Text(
                    'Could not load your visits. Tap to try again.',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Palette.deepSea),
                  ),
                ),
                data: (c) => _Body(care: c),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(linkedPatientsProvider).value ?? const [];
    final current = ref.watch(currentPatientProvider);
    final now = DateTime.now();
    return Container(
      decoration: const BoxDecoration(
        gradient: heroGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16 + MediaQuery.paddingOf(context).top, 20, 60),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(right: -6, top: 92, child: Orb(size: 54, tone: OrbTone.teal)),
          const Positioned(right: 112, top: 60, child: Orb(size: 14)),
          const Positioned(right: 14, top: 40, child: Float(child: Tooth3D(height: 120))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Lockup(onDark: true, markHeight: 30),
              const SizedBox(height: 34),
              Text(
                '${weekday(now)} ${dayMonth(now)}',
                style: const TextStyle(color: Color(0xFFA9DCD1), fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 220,
                child: Text(
                  'Hello, ${current?.firstName ?? ''}',
                  style: Theme.of(context).textTheme.headlineLarge!.copyWith(color: Colors.white),
                ),
              ),
              if (people.length > 1) ...[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in people)
                      _PersonChip(
                        key: Key('person-${p.id}'),
                        label: p.isSelf ? '${p.firstName} (you)' : p.firstName,
                        selected: p.id == current?.id,
                        onTap: () => ref.read(selectedPatientProvider.notifier).select(p.id),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.care});
  final CareSummary care;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final next = care.upcoming.firstOrNull;
    final plan = care.activePlan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Reveal(child: next != null ? _NextVisit(next) : const _BookPrompt()),
        const SizedBox(height: 22),
        Reveal(
          order: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('Treatment plan'),
              plan != null
                  ? _PlanCard(plan)
                  : const EmptyNote(
                      icon: Icons.assignment_outlined,
                      title: 'No treatment plan',
                      body: 'If your dentist recommends treatment, the plan and each step appear here.',
                    ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Reveal(
          order: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                'Recent visits',
                action: care.visits.length > 2 ? 'See all' : null,
                onAction: () => ref.read(shellTabProvider.notifier).go(ShellTab.records),
              ),
              care.visits.isEmpty
                  ? const EmptyNote(
                      icon: Icons.history_rounded,
                      title: 'No visits yet',
                      body: 'After your first appointment, what was done shows here.',
                    )
                  : Panel(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Column(
                        children: [for (final v in care.visits.take(3)) VisitTile(visit: v, onTap: () => showVisit(context, v))],
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

void _openBooking(BuildContext context, WidgetRef ref) {
  final person = ref.read(currentPatientProvider);
  if (person == null) return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingScreen(patient: person)));
}

/// No visit yet: invite the patient to book one.
class _BookPrompt extends ConsumerWidget {
  const _BookPrompt();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            IconTile(Icons.event_available_outlined),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No visit booked',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Palette.deepSea),
                  ),
                  SizedBox(height: 3),
                  Text('Pick a time at your clinic in under a minute.', style: TextStyle(fontSize: 14, height: 1.4, color: Palette.muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PrimaryButton(key: const Key('book-visit'), label: 'Book a visit', onPressed: () => _openBooking(context, ref)),
      ],
    ),
  );
}

Future<void> _confirmCancel(BuildContext context, WidgetRef ref, Appointment a) async {
  final yes = await showModalBottomSheet<bool>(
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
            const Center(child: IconTile(Icons.event_busy_rounded, size: 64)),
            const SizedBox(height: 18),
            Text('Cancel this visit?', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              '${a.service}, ${weekday(a.startsAt)} ${dayMonth(a.startsAt)} at ${clock(a.startsAt)}. The time goes back to other patients.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, height: 1.5, color: Palette.muted),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('confirm-cancel'),
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: Palette.error,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                textStyle: const TextStyle(fontFamily: uiFont, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              child: const Text('Cancel visit'),
            ),
            const SizedBox(height: 10),
            TextButton(
              key: const Key('keep-visit'),
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: const Text('Keep my visit'),
            ),
          ],
        ),
      ),
    ),
  );
  if (yes != true || !context.mounted) return;
  try {
    await ref.read(careRepositoryProvider).cancel(a.id);
    ref.invalidate(careSummaryProvider);
  } on BookingError catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}

class _NextVisit extends ConsumerWidget {
  const _NextVisit(this.appointment);
  final Appointment appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Next visit',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Palette.teal),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xFFDDF3EE), borderRadius: BorderRadius.circular(999)),
              child: const Text(
                'Booked',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Palette.tealDark),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Container(
              width: 62,
              height: 68,
              decoration: BoxDecoration(gradient: buttonGradient, borderRadius: BorderRadius.circular(18)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    weekday(appointment.startsAt),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFCDEFE7)),
                  ),
                  Text(
                    '${appointment.startsAt.day}',
                    style: const TextStyle(fontSize: 26, height: 1.05, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appointment.service,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: Palette.deepSea),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${clock(appointment.startsAt)} to ${clock(appointment.endsAt)} · ${appointment.location}',
                    style: const TextStyle(fontSize: 14, color: Palette.muted),
                  ),
                  Text(dayMonthYear(appointment.startsAt), style: const TextStyle(fontSize: 13, color: Palette.muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('cancel-visit'),
            onPressed: () => _confirmCancel(context, ref, appointment),
            style: TextButton.styleFrom(foregroundColor: Palette.error),
            child: const Text('Cancel visit'),
          ),
        ),
      ],
    ),
  );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard(this.plan);
  final Plan plan;

  @override
  Widget build(BuildContext context) {
    final total = plan.phases.length;
    final current = plan.current;
    final progress = total == 0 ? 0.0 : plan.donePhases / total;
    return Panel(
      key: const Key('plan-card'),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlanScreen(plan: plan))),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            height: 58,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 7,
                  backgroundColor: const Color(0xFFE2EEEB),
                  color: Palette.teal,
                  strokeCap: StrokeCap.round,
                ),
                Center(
                  child: Text(
                    '${(progress * 100).round()}%',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Palette.deepSea),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current == null ? 'All phases done' : 'Phase ${plan.donePhases + 1} of $total',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Palette.deepSea),
                ),
                const SizedBox(height: 3),
                Text(current?.name ?? 'Well done. Keep up your check-ups.', style: const TextStyle(fontSize: 14, color: Palette.muted)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF9AB0AC)),
        ],
      ),
    );
  }
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: selected ? 1 : 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: selected ? Palette.deepSea : Colors.white),
        ),
      ),
    ),
  );
}
