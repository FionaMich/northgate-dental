import 'package:dental/ui.dart';

import '../data/care_repository.dart';
import '../design/art.dart';
import '../design/tokens.dart';
import 'care_widgets.dart';

/// One treatment plan, phase by phase.
class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key, required this.plan});
  final Plan plan;

  @override
  Widget build(BuildContext context) {
    final current = plan.current;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Palette.mist,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Treatment plan',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          Container(
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: const RadialGradient(
                center: Alignment(-0.6, -1),
                radius: 1.4,
                colors: [Colors.white, Color(0xFFDDEFEB), Color(0xFFB9DED4)],
                stops: [0, 0.55, 1],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: 40,
                  bottom: 14,
                  child: Tooth3D(height: 150, crown: current != null),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: SizedBox(
                    width: 170,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current == null
                              ? 'Complete'
                              : 'Phase ${plan.donePhases + 1} of ${plan.phases.length}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Palette.tealDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          current?.name ?? 'Every phase is done',
                          style: const TextStyle(
                            fontSize: 24,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: Palette.deepSea,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          for (final phase in plan.phases) ...[
            SectionTitle(phase.name),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: phase.procedures.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'No procedures in this phase yet.',
                        style: TextStyle(color: Palette.muted),
                      ),
                    )
                  : Column(
                      children: [
                        for (final p in phase.procedures) ProcedureRow(p),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
          ],
          const SizedBox(height: 8),
          const Text(
            'Costs and booking for each step arrive with insurance and booking in later updates.',
            style: TextStyle(fontSize: 13, color: Palette.muted),
          ),
        ],
      ),
    );
  }
}
