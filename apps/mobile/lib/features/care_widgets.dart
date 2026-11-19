import 'package:material_ui/material_ui.dart';

import '../data/care_repository.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/tokens.dart';

/// White rounded card with the house shadow.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: DecoratedBox(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), boxShadow: lift()),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 0, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: Palette.deepSea),
          ),
        ),
        if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

/// A rounded icon tile used at the start of rows and empty states.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.size = 52, this.dark = false});
  final IconData icon;
  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: dark
          ? buttonGradient
          : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white, Color(0xFFDDEFEB)]),
      borderRadius: BorderRadius.circular(size * 0.32),
      boxShadow: [BoxShadow(color: Palette.deepSea.withValues(alpha: 0.12), blurRadius: 14, offset: const Offset(0, 6), spreadRadius: -6)],
    ),
    child: Icon(icon, color: dark ? Colors.white : Palette.teal, size: size * 0.46),
  );
}

/// Calm, specific message where data would be, so no screen is ever a blank gap.
class EmptyNote extends StatelessWidget {
  const EmptyNote({super.key, required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title, body;

  @override
  Widget build(BuildContext context) => Panel(
    child: Row(
      children: [
        IconTile(icon),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Palette.deepSea),
              ),
              const SizedBox(height: 3),
              Text(body, style: const TextStyle(fontSize: 14, height: 1.4, color: Palette.muted)),
            ],
          ),
        ),
      ],
    ),
  );
}

/// One past visit in a list.
class VisitTile extends StatelessWidget {
  const VisitTile({super.key, required this.visit, this.onTap});
  final Visit visit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final detail = visit.procedures.isEmpty
        ? visit.location
        : '${visit.procedures.length} procedure${visit.procedures.length == 1 ? '' : 's'} · ${visit.location}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 56,
              decoration: BoxDecoration(color: Palette.enamel, borderRadius: BorderRadius.circular(16)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    shortMonth(visit.at),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Palette.teal),
                  ),
                  Text(
                    '${visit.at.day}',
                    style: const TextStyle(fontSize: 20, height: 1.1, fontWeight: FontWeight.w800, color: Palette.deepSea),
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
                    visitTitle(visit.kind),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Palette.deepSea),
                  ),
                  const SizedBox(height: 2),
                  Text(detail, style: const TextStyle(fontSize: 13, color: Palette.muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF9AB0AC)),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet with what happened at one visit.
Future<void> showVisit(BuildContext context, Visit visit) => showModalBottomSheet(
  context: context,
  backgroundColor: Colors.white,
  showDragHandle: true,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(visitTitle(visit.kind), style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            '${weekday(visit.at)} ${dayMonthYear(visit.at)} · ${visit.location}',
            style: const TextStyle(color: Palette.muted, fontSize: 15),
          ),
          const SizedBox(height: 20),
          if (visit.procedures.isEmpty)
            const Text('No procedures were recorded at this visit.', style: TextStyle(color: Palette.muted, fontSize: 15))
          else
            for (final p in visit.procedures) ProcedureRow(p),
        ],
      ),
    ),
  ),
);

class ProcedureRow extends StatelessWidget {
  const ProcedureRow(this.procedure, {super.key});
  final Procedure procedure;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: procedure.done ? Palette.teal : Colors.transparent,
            border: procedure.done ? null : Border.all(color: Palette.apricot, width: 3),
          ),
          child: procedure.done ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            procedureLabel(procedure),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Palette.deepSea),
          ),
        ),
        Text(
          procedure.done ? 'Done' : 'Planned',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: procedure.done ? Palette.teal : const Color(0xFFB0662E)),
        ),
      ],
    ),
  );
}

/// Placeholder blocks while data loads.
class LoadingPanels extends StatelessWidget {
  const LoadingPanels({super.key});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final h in const [150.0, 110.0, 180.0])
        Container(
          height: h,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(26)),
        ),
    ],
  );
}
