import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// The blueprint's tooth outline (Figure 1), in a 160 x 214 box.
Path _tooth(Size s) {
  final sx = s.width / 160, sy = s.height / 214;
  Offset p(double x, double y) => Offset((x - 20) * sx, (y - 6) * sy);
  void c(Path path, List<double> v) {
    final a = p(v[0], v[1]), b = p(v[2], v[3]), e = p(v[4], v[5]);
    path.cubicTo(a.dx, a.dy, b.dx, b.dy, e.dx, e.dy);
  }

  final start = p(100, 32);
  final path = Path()..moveTo(start.dx, start.dy);
  for (final v in const [
    [82.0, 16.0, 44.0, 12.0, 31.0, 40.0],
    [20.0, 64.0, 27.0, 95.0, 37.0, 120.0],
    [45.0, 140.0, 47.0, 170.0, 55.0, 196.0],
    [61.0, 214.0, 77.0, 212.0, 81.0, 194.0],
    [86.0, 171.0, 90.0, 152.0, 100.0, 152.0],
    [110.0, 152.0, 114.0, 171.0, 119.0, 194.0],
    [123.0, 212.0, 139.0, 214.0, 145.0, 196.0],
    [153.0, 170.0, 155.0, 140.0, 163.0, 120.0],
    [173.0, 95.0, 180.0, 64.0, 169.0, 40.0],
    [156.0, 12.0, 118.0, 16.0, 100.0, 32.0],
  ]) {
    c(path, v);
  }
  return path..close();
}

Path _shine(Size s) {
  final sx = s.width / 160, sy = s.height / 214;
  return Path()
    ..moveTo((64 - 20) * sx, (58 - 6) * sy)
    ..cubicTo(
      (74 - 20) * sx,
      (49 - 6) * sy,
      (88 - 20) * sx,
      (48 - 6) * sy,
      (98 - 20) * sx,
      (54 - 6) * sy,
    );
}

/// Flat outline mark, as drawn in the blueprint.
class ToothMark extends StatelessWidget {
  const ToothMark({
    super.key,
    this.height = 48,
    this.stroke = Palette.teal,
    this.fill = Palette.enamel,
  });
  final double height;
  final Color stroke, fill;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(height * 160 / 214, height),
    painter: _MarkPainter(stroke, fill),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.stroke, this.fill);
  final Color stroke, fill;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.height * 0.06;
    final inner = Size(size.width - w, size.height - w);
    canvas.translate(w / 2, w / 2);
    final tooth = _tooth(inner);
    canvas.drawPath(tooth, Paint()..color = fill);
    canvas.drawPath(
      tooth,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      _shine(inner),
      Paint()
        ..color = Palette.shine
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.8
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.stroke != stroke || old.fill != fill;
}

/// The rendered enamel tooth used for depth on hero backgrounds.
class Tooth3D extends StatelessWidget {
  const Tooth3D({super.key, this.height = 180, this.crown = false});
  final double height;
  final bool crown;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size(height * 160 / 214, height * 1.12),
      painter: _Tooth3DPainter(crown),
    ),
  );
}

class _Tooth3DPainter extends CustomPainter {
  _Tooth3DPainter(this.crown);
  final bool crown;

  @override
  void paint(Canvas canvas, Size size) {
    final toothSize = Size(size.width, size.width * 214 / 160);
    final rect = Offset.zero & toothSize;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.96),
        width: size.width * 0.8,
        height: size.height * 0.07,
      ),
      Paint()
        ..color = const Color(0xFF021614).withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    final tooth = _tooth(toothSize);
    canvas.drawPath(
      tooth,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment(-0.7, -1),
          end: Alignment(0.7, 1),
          colors: [
            Colors.white,
            Color(0xFFEAF6F2),
            Color(0xFFB9DED4),
            Color(0xFF7FBFB0),
          ],
          stops: [0, 0.45, 0.8, 1],
        ).createShader(rect),
    );
    canvas.drawPath(
      tooth,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.36, -0.56),
          radius: 0.5,
          colors: [Colors.white, Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    if (crown) {
      final sx = toothSize.width / 160, sy = toothSize.height / 214;
      canvas.drawPath(
        Path()
          ..moveTo(24 * sx, 28 * sy)
          ..cubicTo(50 * sx, 12 * sy, 110 * sx, 12 * sy, 136 * sx, 28 * sy)
          ..lineTo(130 * sx, 46 * sy)
          ..cubicTo(106 * sx, 34 * sy, 54 * sx, 34 * sy, 30 * sx, 46 * sy)
          ..close(),
        Paint()..color = Palette.apricot.withValues(alpha: 0.92),
      );
    }
    canvas.drawPath(
      _shine(toothSize),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = toothSize.width * 0.07
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_Tooth3DPainter old) => old.crown != crown;
}

enum OrbTone { mint, teal, pearl }

/// A lit sphere, for depth behind screens.
class Orb extends StatelessWidget {
  const Orb({super.key, required this.size, this.tone = OrbTone.mint});
  final double size;
  final OrbTone tone;

  static const _tones = {
    OrbTone.mint: [Color(0xFFE9FFF7), Color(0xFF8FE3C8), Color(0xFF1E9C83)],
    OrbTone.teal: [Color(0xFF6FD6C0), Color(0xFF16857A), Color(0xFF063E3A)],
    OrbTone.pearl: [Colors.white, Color(0xFFE7F1EE), Color(0xFFA9C9C1)],
  };

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 0.75,
          colors: _tones[tone]!,
          stops: const [0, 0.4, 1],
        ),
      ),
    ),
  );
}

/// The Northgate Dental lockup: tooth mark, wordmark and the three towns.
class Lockup extends StatelessWidget {
  const Lockup({super.key, this.onDark = false, this.markHeight = 44});
  final bool onDark;
  final double markHeight;

  @override
  Widget build(BuildContext context) {
    final strong = onDark ? Colors.white : Palette.deepSea;
    final soft = onDark ? const Color(0xFF8FE3C8) : Palette.teal;
    return Semantics(
      label: 'Northgate Dental',
      child: ExcludeSemantics(
        child: MediaQuery.withNoTextScaling(
          // the lockup is artwork: it keeps its proportions at any text size, and shrinks if space is short
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ToothMark(
                  height: markHeight,
                  stroke: onDark ? const Color(0xFF8FE3C8) : Palette.teal,
                  fill: onDark ? Colors.transparent : Palette.enamel,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Northgate ',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: strong,
                            ),
                          ),
                          TextSpan(
                            text: 'Dental',
                            style: TextStyle(
                              fontWeight: FontWeight.w400,
                              color: soft,
                            ),
                          ),
                        ],
                      ),
                      style: TextStyle(
                        fontFamily: logoFont,
                        fontSize: markHeight * 0.5,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'BACK BAY · CAMBRIDGE · QUINCY',
                      style: TextStyle(
                        fontFamily: logoFont,
                        fontSize: math.max(9, markHeight * 0.17),
                        letterSpacing: 2.2,
                        color: onDark
                            ? const Color(0xFFA9DCD1)
                            : const Color(0xFF4A5A63),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The mint-tinted variation of the tooth, used by the brushing loader.
void paintMintTooth(Canvas canvas, Size size) {
  final rect = Offset.zero & size;
  final tooth = _tooth(size);
  canvas.drawPath(
    tooth.shift(Offset(0, size.height * 0.04)),
    Paint()
      ..color = const Color(0xFF021614).withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
  );
  canvas.drawPath(
    tooth,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment(-0.7, -1),
        end: Alignment(0.7, 1),
        colors: [
          Colors.white,
          Color(0xFFDFF8EF),
          Color(0xFF9EE3CC),
          Color(0xFF5BBFA6),
        ],
        stops: [0, 0.4, 0.78, 1],
      ).createShader(rect),
  );
  canvas.drawPath(
    tooth,
    Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.36, -0.56),
        radius: 0.5,
        colors: [Colors.white, Color(0x00FFFFFF)],
      ).createShader(rect),
  );
  canvas.drawPath(
    _shine(size),
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.07
      ..strokeCap = StrokeCap.round,
  );
}
