import 'package:material_ui/material_ui.dart';

import 'art.dart';
import 'tokens.dart';

/// Full-width primary action with the brand gradient and a soft lift.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: buttonGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Palette.tealDark.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 12), spreadRadius: -12),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: 56,
              child: Center(
                child: busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Text(
                        label,
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A plain-language problem message the person can act on.
class ErrorNote extends StatelessWidget {
  const ErrorNote(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 20, color: Palette.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Palette.error, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Deep teal stage with the rendered tooth and floating spheres, behind sign-in and linking.
class HeroStage extends StatelessWidget {
  const HeroStage({super.key, required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(right: 36, top: height * 0.12, child: const Orb(size: 64)),
        Positioned(
          left: 40,
          bottom: height * 0.14,
          child: const Orb(size: 40, tone: OrbTone.pearl),
        ),
        Positioned(
          right: 30,
          bottom: height * 0.2,
          child: const Orb(size: 26, tone: OrbTone.teal),
        ),
        Positioned(left: 24, top: 18, child: const Lockup(onDark: true, markHeight: 34)),
        Align(
          alignment: const Alignment(0, 0.35),
          child: Tooth3D(height: height * 0.5),
        ),
      ],
    ),
  );
}

/// White sheet that rises from the bottom over a hero stage.
class BottomSheetPanel extends StatelessWidget {
  const BottomSheetPanel({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );
}
