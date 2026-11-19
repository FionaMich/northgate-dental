import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'art.dart';
import 'motion.dart';
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
  const HeroStage({super.key, required this.height, this.quietCorner = false});
  final double height;

  /// Keeps the top-right corner clear for a close button.
  final bool quietCorner;

  @override
  // Starts below the status bar so the logo and art never sit under the clock.
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
    child: SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 36,
            top: height * (quietCorner ? 0.42 : 0.12),
            child: const Float(distance: 10, phase: 0.3, child: Orb(size: 64)),
          ),
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
            child: Float(child: Tooth3D(height: height * 0.5)),
          ),
        ],
      ),
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

/// Every signed-out screen: hero art on top, a white sheet with the form below, optional back button.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.children, this.heroFraction = 0.36, this.showBack = false});
  final List<Widget> children;
  final double heroFraction;
  final bool showBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DecoratedBox(
      decoration: const BoxDecoration(gradient: heroGradient),
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Stack(
                  children: [
                    HeroStage(height: (box.maxHeight * heroFraction).clamp(200, 380), quietCorner: showBack),
                    if (showBack)
                      Positioned(
                        right: 12,
                        top: 10 + MediaQuery.paddingOf(context).top,
                        child: IconButton.filledTonal(
                          tooltip: 'Back',
                          style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.14), foregroundColor: Colors.white),
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                  ],
                ),
                BottomSheetPanel(children: children),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Six boxes for an emailed code. One hidden text field underneath keeps paste, autofill and screen readers working.
class CodeBoxes extends StatefulWidget {
  const CodeBoxes({super.key, required this.onCompleted, this.enabled = true});
  final ValueChanged<String> onCompleted;
  final bool enabled;

  @override
  State<CodeBoxes> createState() => _CodeBoxesState();
}

class _CodeBoxesState extends State<CodeBoxes> {
  final _c = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      setState(() {});
      if (_c.text.length == 6) widget.onCompleted(_c.text);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => _focus.requestFocus(),
    child: Stack(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 6; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 48,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i < _c.text.length ? Colors.white : const Color(0xFFF4F8F7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _focus.hasFocus && i == _c.text.length.clamp(0, 5) ? Palette.teal : Palette.line,
                    width: _focus.hasFocus && i == _c.text.length.clamp(0, 5) ? 2 : 1,
                  ),
                ),
                child: Text(
                  i < _c.text.length ? _c.text[i] : '',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Palette.deepSea),
                ),
              ),
          ],
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              key: const Key('code-input'),
              controller: _c,
              focusNode: _focus,
              enabled: widget.enabled,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(counterText: '', border: InputBorder.none, filled: false),
            ),
          ),
        ),
      ],
    ),
  );
}

/// A tick list that turns green as the password meets each server rule.
class PasswordChecklist extends StatelessWidget {
  const PasswordChecklist({super.key, required this.rules});
  final List<(String, bool)> rules;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 6,
    children: [
      for (final (label, met) in rules)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                met ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                key: ValueKey(met),
                size: 18,
                color: met ? Palette.teal : const Color(0xFF9AB0AC),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: met ? Palette.teal : Palette.muted),
            ),
          ],
        ),
    ],
  );
}
