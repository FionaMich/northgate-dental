import 'package:dental/ui.dart';

import '../data/aftercare.dart';
import '../data/care_repository.dart';
import '../design/format.dart';
import '../design/tokens.dart';
import 'care_widgets.dart';

/// Aftercare for one visit: right now, today and this week, each ticked off as its time passes.
class AftercareScreen extends StatelessWidget {
  const AftercareScreen({
    super.key,
    required this.visit,
    required this.sheet,
    this.now,
  });
  final Visit visit;
  final AftercareSheet sheet;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final done = aftercareDone(visit.at, now ?? DateTime.now());
    return Scaffold(
      backgroundColor: Palette.mist,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: heroGradient,
              image: heroPhoto,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 20, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      tooltip: tr('Back'),
                      color: Colors.white,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sheet.title,
                            style: const TextStyle(
                              fontSize: 28,
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            trf('{} on {} {} at {}', [
                              tr(visitTitle(visit.kind)),
                              weekday(visit.at),
                              dayMonth(visit.at),
                              visit.location,
                            ]),
                            style: const TextStyle(
                              fontSize: 15,
                              color: Color(0xFFCDEFE7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Phase('Right now', sheet.rightNow, done.rightNow, Tint.rose),
                _Phase('Today', sheet.today, done.today, Tint.apricot),
                _Phase('This week', sheet.thisWeek, done.thisWeek, Tint.teal),
                const SizedBox(height: 6),
                Panel(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const TintIcon(Icons.call_rounded, Tint.rose),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          AftercareSheet.callUs,
                          style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.5,
                            color: Palette.deepSea,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Phase extends StatelessWidget {
  const _Phase(this.title, this.steps, this.over, this.tint);
  final String title;
  final List<String> steps;
  final bool over;
  final Tint tint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: RowGroup(
      title: over ? '$title  ·  done' : title,
      rows: [
        for (final s in steps)
          GroupRow(
            icon: over
                ? Icons.check_rounded
                : Icons.radio_button_unchecked_rounded,
            tint: over ? Tint.teal : tint,
            title: s,
          ),
      ],
    ),
  );
}
