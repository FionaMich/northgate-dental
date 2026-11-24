import 'package:material_ui/material_ui.dart';

import '../data/care_repository.dart';
import '../design/art.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import 'visit_screen.dart';

/// White rounded card with the house shadow.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE3ECEA)),
        boxShadow: lift(),
      ),
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
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: Palette.deepSea,
            ),
          ),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
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
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFDDEFEB)],
            ),
      borderRadius: BorderRadius.circular(size * 0.32),
      boxShadow: [
        BoxShadow(
          color: Palette.deepSea.withValues(alpha: 0.12),
          blurRadius: 14,
          offset: const Offset(0, 6),
          spreadRadius: -6,
        ),
      ],
    ),
    child: Icon(
      icon,
      color: dark ? Colors.white : Palette.teal,
      size: size * 0.46,
    ),
  );
}

/// Calm, specific message where data would be, so no screen is ever a blank gap.
class EmptyNote extends StatelessWidget {
  const EmptyNote({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });
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
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Palette.deepSea,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: const TextStyle(
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
              decoration: BoxDecoration(
                color: Palette.enamel,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    shortMonth(visit.at),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Palette.teal,
                    ),
                  ),
                  Text(
                    '${visit.at.day}',
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: Palette.deepSea,
                    ),
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Palette.deepSea,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(fontSize: 13, color: Palette.muted),
                  ),
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
/// Opens the full visit page.
Future<void> showVisit(BuildContext context, Visit visit) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => VisitScreen(visit: visit)));

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
            border: procedure.done
                ? null
                : Border.all(color: Palette.apricot, width: 3),
          ),
          child: procedure.done
              ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            procedureLabel(procedure),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Palette.deepSea,
            ),
          ),
        ),
        Text(
          procedure.done ? 'Done' : 'Planned',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: procedure.done ? Palette.teal : const Color(0xFFB0662E),
          ),
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
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(26),
          ),
        ),
    ],
  );
}

/// The branded top of a tab: gradient, 3D art, title, a short line, and optional facts as glass pills.
class PageHero extends StatelessWidget {
  const PageHero({
    super.key,
    required this.title,
    required this.subtitle,
    this.facts = const [],
    this.leading,
  });
  final String title, subtitle;
  final List<(IconData, String)> facts;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: heroGradient,
      image: heroPhoto,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
    ),
    padding: EdgeInsets.fromLTRB(
      22,
      22 + MediaQuery.paddingOf(context).top,
      22,
      58,
    ),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        const Positioned(
          right: -4,
          top: -6,
          child: Float(child: Tooth3D(height: 92)),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[leading!, const SizedBox(height: 14)],
            Text(
              title,
              style: Theme.of(context).textTheme.headlineLarge!
                  .copyWith(color: Colors.white),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 250,
              child: Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: Color(0xFFCDEFE7),
                ),
              ),
            ),
            if (facts.isNotEmpty) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (icon, label) in facts)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 15, color: const Color(0xFF8FE3C8)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
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

/// Pulls the first content up over the hero's rounded bottom edge.
class OverHero extends StatelessWidget {
  const OverHero({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Transform.translate(offset: const Offset(0, -34), child: child);
}

/// A tinted square icon, for rows and cards.
class TintIcon extends StatelessWidget {
  const TintIcon(this.icon, this.tint, {super.key, this.size = 40});
  final IconData icon;
  final Tint tint;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: tint.wash,
      borderRadius: BorderRadius.circular(size * 0.32),
    ),
    child: Icon(icon, color: tint.ink, size: size * 0.52),
  );
}

/// A titled group of rows in one rounded card (settings style).
class RowGroup extends StatelessWidget {
  const RowGroup({
    super.key,
    required this.title,
    required this.rows,
    this.onHero = false,
  });
  final String title;
  final List<Widget> rows;

  /// The title sits over the page's dark header (first group after a PageHero), so it is drawn light.
  final bool onHero;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: onHero ? const Color(0xFFA9DCD1) : Palette.muted,
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE3ECEA)),
          boxShadow: lift(0.8),
        ),
        child: Column(
          children: [
            for (final (i, r) in rows.indexed) ...[
              if (i > 0)
                const Divider(height: 1, indent: 70, color: Color(0xFFE8EFEE)),
              r,
            ],
          ],
        ),
      ),
    ],
  );
}

/// One row: tinted icon, title, optional detail, and a trailing action or chevron.
class GroupRow extends StatelessWidget {
  const GroupRow({
    super.key,
    required this.icon,
    required this.tint,
    required this.title,
    this.detail,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final Tint tint;
  final String title;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            TintIcon(icon, tint),
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
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail!,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        color: Palette.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing ??
                (onTap == null
                    ? const SizedBox()
                    : const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF9DB3AF),
                      )),
          ],
        ),
      ),
    ),
  );
}
