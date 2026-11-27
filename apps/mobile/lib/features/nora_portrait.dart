import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dental/ui.dart';

import '../design/tokens.dart';

enum NoraMood { idle, listening, thinking, speaking }

/// Nora's portrait, shared by the voice screen and the call screen: breathes when idle, pulses a ring while
/// listening, glows while speaking. With reduce motion on, it stays still; the status line still says what she does.
class NoraPortrait extends ConsumerStatefulWidget {
  const NoraPortrait({super.key, required this.mood});
  final NoraMood mood;

  @override
  ConsumerState<NoraPortrait> createState() => _NoraPortraitState();
}

class _NoraPortraitState extends ConsumerState<NoraPortrait>
    with TickerProviderStateMixin {
  late final _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _breath.stop();
      _pulse.stop();
    } else {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
      if (!_pulse.isAnimating) _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mood = widget.mood;
    final pose = switch (mood) {
      NoraMood.listening => 'listening',
      NoraMood.speaking => 'speaking',
      _ => 'idle',
    };
    return AnimatedBuilder(
      animation: Listenable.merge([_breath, _pulse]),
      builder: (_, _) {
        final breathe = 1 + 0.018 * Curves.easeInOut.transform(_breath.value);
        return SizedBox(
          width: 300,
          height: 300,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (mood == NoraMood.listening)
                for (final offset in [0.0, 0.5])
                  Opacity(
                    opacity:
                        (1 - ((_pulse.value + offset) % 1)).clamp(0, 1) * 0.5,
                    child: Container(
                      width: 220 + 80 * ((_pulse.value + offset) % 1),
                      height: 220 + 80 * ((_pulse.value + offset) % 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Palette.shine, width: 3),
                      ),
                    ),
                  ),
              Transform.scale(
                scale: mood == NoraMood.speaking ? breathe * 1.02 : breathe,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFDDF4EC),
                    border: Border.all(color: Colors.white, width: 5),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (mood == NoraMood.speaking
                                    ? Palette.shine
                                    : Colors.black)
                                .withValues(
                                  alpha: mood == NoraMood.speaking
                                      ? 0.55
                                      : 0.25,
                                ),
                        blurRadius: mood == NoraMood.speaking ? 40 : 24,
                        spreadRadius: mood == NoraMood.speaking ? 4 : 0,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Image.asset(
                        'assets/images/nora/$pose.png',
                        key: ValueKey(pose),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
