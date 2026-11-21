import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../design/art.dart';
import '../design/motion.dart';
import '../design/tokens.dart';

/// How long the intro stays on screen. Tests set it to zero.
final introDurationProvider = Provider<Duration>((ref) => const Duration(minutes: 1));

/// First screen on a cold start: clinic photo under a green wash, a tooth being brushed, then the app.
class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends ConsumerState<IntroScreen> with SingleTickerProviderStateMixin {
  late final Duration _length = ref.read(introDurationProvider);
  // preserve: the intro's length is a timer, not decoration, so reduce-motion must not shorten it.
  late final _progress = AnimationController(vsync: this, duration: _length, animationBehavior: AnimationBehavior.preserve);
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _progress.forward().whenCompleteOrCancel(_finish);
  }

  void _finish() {
    if (_left || !mounted) return;
    _left = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Northgate Dental. Tap to continue.',
    button: true,
    child: GestureDetector(
      onTap: _finish,
      child: Scaffold(
        backgroundColor: Palette.heroBottom,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/images/intro_clinic.jpg', fit: BoxFit.cover, excludeFromSemantics: true),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xB31A8E7E), Color(0xD90C4C46), Color(0xF7072B29)],
                  stops: [0, 0.5, 1],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
                child: Column(
                  children: [
                    const Align(alignment: Alignment.centerLeft, child: Lockup(onDark: true, markHeight: 34)),
                    const Spacer(),
                    const BrushingTooth(size: 210),
                    const SizedBox(height: 36),
                    const Text(
                      'Healthy smiles across Boston',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 26, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -0.6),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Your visits, plans and bookings in one place.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFCDEFE7), fontSize: 15, height: 1.4),
                    ),
                    const Spacer(),
                    AnimatedBuilder(
                      animation: _progress,
                      builder: (_, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: _progress.value,
                          minHeight: 4,
                          color: Palette.shine,
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Tap anywhere to continue', style: TextStyle(color: Color(0xFFA9DCD1), fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A mint tooth being brushed, with sparkles: the loading animation.
class BrushingTooth extends StatefulWidget {
  const BrushingTooth({super.key, this.size = 200});
  final double size;

  @override
  State<BrushingTooth> createState() => _BrushingToothState();
}

class _BrushingToothState extends State<BrushingTooth> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduceMotion(context) ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(painter: _BrushPainter(_c.value)),
      ),
    ),
  );
}

class _BrushPainter extends CustomPainter {
  _BrushPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    // Soft halo behind the tooth.
    canvas.drawCircle(
      Offset(s / 2, s * 0.5),
      s * 0.46,
      Paint()
        ..shader = RadialGradient(colors: [Palette.shine.withValues(alpha: 0.35), Palette.shine.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: Offset(s / 2, s * 0.5), radius: s * 0.46)),
    );
    // Mint-tinted tooth, drawn with the shared art.
    final toothH = s * 0.62;
    canvas.save();
    canvas.translate((s - toothH * 160 / 214) / 2, s * 0.2);
    paintMintTooth(canvas, Size(toothH * 160 / 214, toothH));
    canvas.restore();

    // Toothbrush sweeping across the crown.
    final sweep = math.sin(t * 2 * math.pi);
    canvas.save();
    canvas.translate(s * 0.5 + sweep * s * 0.14, s * 0.2);
    canvas.rotate(-0.42 + sweep * 0.06);
    final handle = RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.06, -s * 0.03, s * 0.42, s * 0.07), Radius.circular(s * 0.035));
    canvas.drawRRect(
      handle,
      Paint()
        ..shader = const LinearGradient(colors: [Color(0xFFFFC79A), Palette.apricot, Color(0xFFD9864B)]).createShader(handle.outerRect),
    );
    final head = RRect.fromRectAndRadius(Rect.fromLTWH(-s * 0.12, -s * 0.035, s * 0.2, s * 0.08), Radius.circular(s * 0.03));
    canvas.drawRRect(head, Paint()..color = Palette.shine);
    final bristle = Paint()..color = Colors.white;
    for (var i = 0; i < 6; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-s * 0.105 + i * s * 0.03, s * 0.045, s * 0.02, s * 0.06), Radius.circular(s * 0.008)),
        bristle,
      );
    }
    canvas.restore();

    // Sparkles that twinkle in turn.
    for (final (x, y, phase, r) in const [
      (0.2, 0.28, 0.0, 0.045),
      (0.82, 0.36, 0.33, 0.035),
      (0.72, 0.78, 0.66, 0.04),
      (0.24, 0.72, 0.5, 0.03),
    ]) {
      final a = (math.sin((t + phase) * 2 * math.pi) + 1) / 2;
      _sparkle(canvas, Offset(s * x, s * y), s * r * (0.6 + 0.4 * a), Colors.white.withValues(alpha: 0.35 + 0.65 * a));
    }
  }

  void _sparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BrushPainter old) => old.t != t;
}
