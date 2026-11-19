import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../design/tokens.dart';
import '../state.dart';
import 'care_widgets.dart';

/// Every past visit for the person on screen, newest first, grouped by year.
class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final care = ref.watch(careSummaryProvider);
    final name = ref.watch(currentPatientProvider)?.firstName ?? '';
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: Palette.teal,
        onRefresh: () => ref.refresh(careSummaryProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          children: [
            Text('Records', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 4),
            Text('Visits and treatment for $name', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 20),
            ...care.when(
              loading: () => const [LoadingPanels()],
              error: (_, _) => [
                Panel(
                  onTap: () => ref.invalidate(careSummaryProvider),
                  child: const Text('Could not load your records. Tap to try again.'),
                ),
              ],
              data: (c) {
                if (c.visits.isEmpty) {
                  return const [
                    EmptyNote(
                      icon: Icons.history_rounded,
                      title: 'No visits yet',
                      body: 'After your first appointment, what was done shows here.',
                    ),
                  ];
                }
                final years = <int, List<Widget>>{};
                for (final v in c.visits) {
                  years
                      .putIfAbsent(v.at.year, () => [])
                      .add(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            VisitTile(visit: v, onTap: () => showVisit(context, v)),
                            for (final p in v.procedures)
                              Padding(padding: const EdgeInsets.only(left: 66, right: 4), child: ProcedureRow(p)),
                          ],
                        ),
                      );
                }
                return [
                  for (final e in years.entries) ...[
                    SectionTitle('${e.key}'),
                    Panel(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Column(children: e.value),
                    ),
                    const SizedBox(height: 14),
                  ],
                ];
              },
            ),
          ],
        ),
      ),
    );
  }
}
