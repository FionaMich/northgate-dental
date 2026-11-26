import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dental/ui.dart';

import '../data/aftercare.dart';
import '../data/care_repository.dart';
import '../data/team_chat_repository.dart';
import '../design/art.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../state.dart';
import 'assistant_screen.dart';
import 'aftercare_screen.dart';
import 'booking_screen.dart';
import 'care_widgets.dart';
import 'dentist_screen.dart';
import 'plan_screen.dart';
import 'shell.dart';
import 'team_chat_screen.dart';
import 'video_visit_screen.dart';

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
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Palette.deepSea,
                    ),
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
        image: heroPhoto,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16 + MediaQuery.paddingOf(context).top,
        20,
        60,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            right: 14,
            top: 40,
            child: Float(child: Tooth3D(height: 120)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Lockup(onDark: true, markHeight: 30),
              const SizedBox(height: 34),
              Text(
                '${weekday(now)} ${dayMonth(now)}',
                style: const TextStyle(
                  color: Color(0xFFA9DCD1),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 220,
                child: Text(
                  'Hello, ${current?.firstName ?? ''}',
                  style: Theme.of(context).textTheme.headlineLarge!
                      .copyWith(color: Colors.white),
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
                        label: p.isSelf
                            ? '${p.firstName} ${tr('(you)')}'
                            : p.firstName,
                        selected: p.id == current?.id,
                        onTap: () => ref
                            .read(selectedPatientProvider.notifier)
                            .select(p.id),
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
    final recall = next == null ? _recallDue(care) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Reveal(child: next != null ? _NextVisit(next) : const _BookPrompt()),
        const SizedBox(height: 22),
        const Reveal(child: _AskReceptionist()),
        const _TeamConversation(),
        const SizedBox(height: 22),
        if (_recentAftercare(care) case (final visit, final sheet)) ...[
          Reveal(
            child: _AftercareCard(visit: visit, sheet: sheet),
          ),
          const SizedBox(height: 22),
        ],
        if (recall != null) ...[
          Reveal(child: _RecallCard(due: recall)),
          const SizedBox(height: 22),
        ],
        const Reveal(order: 1, child: _OurServices()),
        const Reveal(order: 1, child: _Team()),
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
                onAction: () =>
                    ref.read(shellTabProvider.notifier).go(ShellTab.records),
              ),
              care.visits.isEmpty
                  ? const EmptyNote(
                      icon: Icons.history_rounded,
                      title: 'No visits yet',
                      body: 'After your first appointment, what was done shows here.',
                    )
                  : Panel(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      child: Column(
                        children: [
                          for (final v in care.visits.take(3))
                            VisitTile(
                              visit: v,
                              onTap: () => showVisit(context, v),
                            ),
                        ],
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
  Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => BookingScreen(patient: person)));
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
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Palette.deepSea,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Pick a time at your clinic in under a minute.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Palette.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          key: const Key('book-visit'),
          label: 'Book a visit',
          onPressed: () => _openBooking(context, ref),
        ),
      ],
    ),
  );
}

/// Asks before cancelling a visit; used on Home and in Visits.
Future<void> confirmCancelVisit(
  BuildContext context,
  WidgetRef ref,
  Appointment a,
) async {
  final yes = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: IconTile(Icons.event_busy_rounded, size: 64)),
            const SizedBox(height: 18),
            Text(
              'Cancel this visit?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              trf('{}, {} {} at {}. The time goes back to other patients.', [
                tr(a.service),
                weekday(a.startsAt),
                dayMonth(a.startsAt),
                clock(a.startsAt),
              ]),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Palette.muted,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('confirm-cancel'),
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: Palette.error,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                textStyle: const TextStyle(
                  fontFamily: uiFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('Cancel visit'),
            ),
            const SizedBox(height: 10),
            TextButton(
              key: const Key('keep-visit'),
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
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
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
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
            const Expanded(
              child: Text(
                'Next visit',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Palette.teal,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFDDF3EE),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Booked',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Palette.tealDark,
                ),
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
              decoration: BoxDecoration(
                gradient: buttonGradient,
                borderRadius: BorderRadius.circular(18),
              ),
              child: FittedBox(
                // a fixed date tile: the day and date shrink to fit at large text sizes
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      weekday(appointment.startsAt),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFCDEFE7),
                      ),
                    ),
                    Text(
                      '${appointment.startsAt.day}',
                      style: const TextStyle(
                        fontSize: 26,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appointment.service,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: Palette.deepSea,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    trf('{} to {} · {}', [
                      clock(appointment.startsAt),
                      clock(appointment.endsAt),
                      appointment.location,
                    ]),
                    style: const TextStyle(fontSize: 14, color: Palette.muted),
                  ),
                  Text(
                    dayMonthYear(appointment.startsAt),
                    style: const TextStyle(fontSize: 13, color: Palette.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        JoinVideoButton(appointment: appointment),
        const Divider(height: 1, color: Color(0xFFE8EFEE)),
        const SizedBox(height: 10),
        // Side by side when both fit; on narrow phones or large text the button moves under the dentist, never "Cancel vi...".
        OverflowBar(
          alignment: appointment.dentist == null
              ? MainAxisAlignment.end
              : MainAxisAlignment.spaceBetween,
          overflowSpacing: 10,
          children: [
            if (appointment.dentist != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DentistAvatar(
                    name: appointment.dentist!,
                    asset: appointment.dentistPhoto == null
                        ? null
                        : 'assets/images/team/${appointment.dentistPhoto}.jpg',
                    size: 38,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'With ${appointment.dentist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Palette.deepSea,
                      ),
                    ),
                  ),
                ],
              ),
            OutlinedButton(
              key: const Key('cancel-visit'),
              onPressed: () => confirmCancelVisit(context, ref, appointment),
              style: dangerOutline,
              child: const Text('Cancel visit', maxLines: 1, softWrap: false),
            ),
          ],
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
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => PlanScreen(plan: plan))),
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Palette.deepSea,
                    ),
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
                  current == null
                      ? 'All phases done'
                      : 'Phase ${plan.donePhases + 1} of $total',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Palette.deepSea,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  current?.name ?? 'Well done. Keep up your check-ups.',
                  style: const TextStyle(fontSize: 14, color: Palette.muted),
                ),
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
  const _PersonChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
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
          border: Border.all(
            color: Colors.white.withValues(alpha: selected ? 1 : 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: selected ? Palette.deepSea : Colors.white,
          ),
        ),
      ),
    ),
  );
}

/// "Your dental team": faces to tap, each opening that person's profile.
class _Team extends ConsumerWidget {
  const _Team();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(dentistsProvider).value ?? const [];
    if (team.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('Your dental team'),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: team.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) {
                final d = team[i];
                return InkWell(
                  key: Key('team-${d.id}'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DentistScreen(dentist: d),
                    ),
                  ),
                  child: SizedBox(
                    width: 78,
                    child: Column(
                      children: [
                        DentistAvatar(
                          name: d.name,
                          asset: d.photoAsset,
                          size: 64,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          d.name.replaceAll('Dr ', '').split(',').first,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            color: Palette.deepSea,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A treatment visit in the last 7 days that has aftercare.
(Visit, AftercareSheet)? _recentAftercare(CareSummary care) {
  for (final v in care.visits) {
    if (DateTime.now().difference(v.at) > const Duration(days: 7)) {
      break; // visits are newest first
    }
    if (aftercareFor(v) case final sheet?) return (v, sheet);
  }
  return null;
}

/// When the next six-monthly check-up is due, if that is within 45 days or already past.
DateTime? _recallDue(CareSummary care) {
  final last = care.visits
      .where((v) => v.kind == 'exam' || v.kind == 'hygiene')
      .firstOrNull;
  if (last == null) return null;
  final due = DateTime(last.at.year, last.at.month + 6, last.at.day);
  return due.difference(DateTime.now()).inDays <= 45 ? due : null;
}

class _AftercareCard extends StatelessWidget {
  const _AftercareCard({required this.visit, required this.sheet});
  final Visit visit;
  final AftercareSheet sheet;

  @override
  Widget build(BuildContext context) {
    final done = aftercareDone(visit.at, DateTime.now());
    final step = !done.rightNow
        ? 'Right now'
        : (!done.today ? 'Today' : 'This week');
    return Panel(
      key: const Key('aftercare-card'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AftercareScreen(visit: visit, sheet: sheet),
        ),
      ),
      child: Row(
        children: [
          const TintIcon(Icons.healing_rounded, Tint.rose, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sheet.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Palette.deepSea,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$step: what to do and what to avoid',
                  style: const TextStyle(fontSize: 13.5, color: Palette.muted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF9DB3AF)),
        ],
      ),
    );
  }
}

class _RecallCard extends ConsumerWidget {
  const _RecallCard({required this.due});
  final DateTime due;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = due.difference(DateTime.now()).inDays;
    final when = days < 0
        ? 'was due ${-days < 14 ? '${-days} days' : '${(-days / 7).round()} weeks'} ago'
        : (days < 14
              ? 'is due in $days days'
              : 'is due in ${(days / 7).round()} weeks');
    return Container(
      key: const Key('recall-card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Tint.apricot.wash,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF6D9BF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TintIcon(Icons.event_repeat_rounded, Tint.apricot, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Time for a check-up',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Palette.deepSea,
                      ),
                    ),
                    Text(
                      'Your six-monthly check-up $when.',
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            key: const Key('book-checkup'),
            label: 'Book a check-up',
            onPressed: () => _openBooking(context, ref),
          ),
        ],
      ),
    );
  }
}

/// "Our services": a chip per group, each opening booking already filtered to it.
class _OurServices extends ConsumerWidget {
  const _OurServices();

  static const _groups = [
    'Check-ups',
    'Fillings and crowns',
    'Cosmetic',
    'Orthodontics',
    'Surgery and implants',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Our services'),
        SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: _groups.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final label = _groups[i];
              void open() {
                final person = ref.read(currentPatientProvider);
                if (person == null) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        BookingScreen(patient: person, category: label),
                  ),
                );
              }

              return Semantics(
                button: true,
                label: tr(label),
                excludeSemantics: true,
                child: Pressable(
                  onTap: open,
                  child: GestureDetector(
                    key: Key('our-services-$i'),
                    onTap: open,
                    child: Container(
                      width: 140,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: lift(0.8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Image.asset(
                              categoryPhoto(label),
                              fit: BoxFit.cover,
                              excludeFromSemantics: true,
                            ),
                          ),
                          Container(
                            height: 54,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.25,
                                fontWeight: FontWeight.w700,
                                color: Palette.deepSea,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

/// The patient's conversation with the team, shown only while a request is waiting, open or has an unread reply.
/// Nora stays the one way in; this card only brings the patient back to a conversation that already exists.
class _TeamConversation extends ConsumerStatefulWidget {
  const _TeamConversation();

  @override
  ConsumerState<_TeamConversation> createState() => _TeamConversationState();
}

class _TeamConversationState extends ConsumerState<_TeamConversation> {
  late Future<TeamStatus> _status = ref
      .read(teamChatRepositoryProvider)
      .status();

  Future<void> _open() async {
    await openTeamChat(context, ref);
    if (mounted) {
      setState(() => _status = ref.read(teamChatRepositoryProvider).status());
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TeamStatus>(
    future: _status,
    builder: (context, snap) {
      final s = snap.data;
      if (s == null || s.state == 'none') return const SizedBox.shrink();
      final unread = s.state == 'unread';
      final (title, detail) = switch (s.state) {
        'unread' => (
          s.unread == 1
              ? '1 new message from the team'
              : '${s.unread} new messages from the team',
          'Tap to read and reply',
        ),
        'waiting' => ('Your request to the team', 'Waiting for a reply'),
        _ => ('Your conversation with the team', 'Open'),
      };
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Semantics(
          container: true,
          button: true,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              key: const Key('open-team-conversation'),
              borderRadius: BorderRadius.circular(22),
              onTap: _open,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Badge(
                      isLabelVisible: unread,
                      backgroundColor: Palette.shine,
                      smallSize: 10,
                      child: const Icon(
                        Icons.support_agent_rounded,
                        color: Palette.teal,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: unread
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              color: Palette.deepSea,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            detail,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Palette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Palette.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Opens the receptionist chat: an AI assistant that answers in 8 languages and hands over to the team.
class _AskReceptionist extends StatelessWidget {
  const _AskReceptionist();

  @override
  // A button of its own for screen readers (it was merged into the visit card above it).
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    child: Material(
      color: Palette.deepSea,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        key: const Key('open-assistant'),
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const AssistantScreen())),
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.forum_rounded, color: Palette.shine, size: 30),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ask Nora, our AI receptionist',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Book, change or pay, any time, in 8 languages',
                      style: TextStyle(fontSize: 13, color: Color(0xFFA9DCD1)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    ),
  );
}
