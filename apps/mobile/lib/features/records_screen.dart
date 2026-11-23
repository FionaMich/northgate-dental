import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/care_repository.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../state.dart';
import 'care_widgets.dart';
import 'visit_screen.dart';

/// Everything the practice has recorded for the person on screen: documents to open, and a timeline of visits.
class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final care = ref.watch(careSummaryProvider);
    final name = ref.watch(currentPatientProvider)?.firstName ?? '';
    final c = care.value;
    return RefreshIndicator(
      color: Palette.teal,
      onRefresh: () => ref.refresh(careSummaryProvider.future),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          PageHero(
            title: 'Records',
            subtitle: 'Visits, X-rays and summaries for $name.',
            facts: [
              if (c != null)
                (
                  Icons.event_note_rounded,
                  '${c.visits.length} ${c.visits.length == 1 ? 'visit' : 'visits'}',
                ),
              if (c != null && c.documents.isNotEmpty)
                (Icons.folder_open_rounded, '${c.documents.length} documents'),
            ],
          ),
          OverHero(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: care.when(
                  loading: () => const [LoadingPanels()],
                  error: (_, _) => [
                    Panel(
                      onTap: () => ref.invalidate(careSummaryProvider),
                      child: const Text(
                        'Could not load your records. Tap to try again.',
                      ),
                    ),
                  ],
                  data: (c) => [
                    if (c.documents.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(6, 0, 6, 10),
                        child: Text(
                          'DOCUMENTS',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                            color: Color(0xFFA9DCD1),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 172,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          itemCount: c.documents.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (_, i) => Reveal(
                            order: i,
                            child: DocumentTile(
                              document: c.documents[i],
                              card: true,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                    ],
                    if (c.visits.isEmpty)
                      const EmptyNote(
                        icon: Icons.history_rounded,
                        title: 'No visits yet',
                        body: 'After your first appointment, what was done shows here.',
                      )
                    else ...[
                      const SectionTitle('Your visits'),
                      for (final (i, v) in c.visits.indexed) ...[
                        if (i == 0 || c.visits[i - 1].at.year != v.at.year)
                          _YearMark(v.at.year),
                        Reveal(
                          order: i,
                          child: _TimelineVisit(
                            visit: v,
                            last: i == c.visits.length - 1,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _YearMark extends StatelessWidget {
  const _YearMark(this.year);
  final int year;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 6, 0, 10),
    child: Text(
      '$year',
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
        color: Palette.muted,
      ),
    ),
  );
}

/// One visit on the timeline: a date block, a node on the rail, and a compact card.
class _TimelineVisit extends StatelessWidget {
  const _TimelineVisit({required this.visit, required this.last});
  final Visit visit;
  final bool last;

  static Tint tintFor(String kind) => switch (kind) {
    'hygiene' => Tint.sky,
    'treatment' => Tint.violet,
    'emergency' => Tint.rose,
    _ => Tint.teal,
  };

  @override
  Widget build(BuildContext context) {
    final v = visit;
    final tint = tintFor(v.kind);
    final planned = v.procedures.where((p) => !p.done).length;
    final names = v.procedures.map((p) => p.service).toList();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 46,
            child: Column(
              children: [
                const SizedBox(height: 16),
                Text(
                  shortMonth(v.at),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Palette.muted,
                  ),
                ),
                Text(
                  '${v.at.day}',
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    color: Palette.deepSea,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 26,
            child: Column(
              children: [
                const SizedBox(height: 22),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: tint.ink,
                    shape: BoxShape.circle,
                    border: Border.all(color: tint.wash, width: 3),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(width: 2, color: const Color(0xFFD9E6E3)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Panel(
                key: Key('visit-${v.id}'),
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                onTap: () => showVisit(context, v),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            visitTitle(v.kind),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Palette.deepSea,
                            ),
                          ),
                        ),
                        if (planned > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Tint.apricot.wash,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$planned planned',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Tint.apricot.ink,
                              ),
                            ),
                          ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF9DB3AF),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        v.location,
                        if (v.dentist != null) v.dentist!,
                      ].join('  ·  '),
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Palette.muted,
                      ),
                    ),
                    if (names.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final n in names.take(2)) _Chip(n, tint),
                          if (names.length > 2)
                            _Chip('+${names.length - 2} more', tint),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.tint);
  final String label;
  final Tint tint;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 220),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: tint.wash,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: tint.ink,
      ),
    ),
  );
}
