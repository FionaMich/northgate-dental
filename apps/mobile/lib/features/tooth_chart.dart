import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../data/care_repository.dart';
import '../design/tokens.dart';

/// The 32 permanent teeth seen from above, on two sculpted arches set in the gums, as the patient faces you
/// (Universal numbering, the patient's right on the left of the screen). Each tooth is drawn by type: molars with four
/// cusps and their grooves, premolars with two, pointed canines and flat incisors, shaded like enamel. What happened is
/// painted on the surface it happened to (the top, front, back, cheek or tongue side); tap a tooth for its story.
class ToothChart extends StatelessWidget {
  const ToothChart({super.key, required this.procedures, required this.findings});
  final List<Procedure> procedures;
  final List<Finding> findings;

  // One side of an arch, back to front: three molars, two premolars, canine, lateral and central incisor.
  static const _types = [_Kind.molar, _Kind.molar, _Kind.molar, _Kind.premolar, _Kind.premolar, _Kind.canine, _Kind.incisor, _Kind.incisor];
  static const _sideWidths = [1.30, 1.34, 1.38, 0.98, 0.98, 0.92, 0.80, 0.92];
  static const _open = 0.26; // radians left open at the back of each arch
  static const _depth = {_Kind.molar: 1.18, _Kind.premolar: 1.02, _Kind.canine: 0.92, _Kind.incisor: 0.62};

  @override
  Widget build(BuildContext context) => Column(
    children: [
      LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = w * 1.04;
          // Sized so neighbouring teeth just touch along the arch (arch length / summed tooth widths).
          final unit = w / 15.6;
          final widths = [..._sideWidths, ..._sideWidths.reversed];
          final kinds = [..._types, ..._types.reversed];
          final total = widths.fold(0.0, (a, b) => a + b);
          final teeth = <Widget>[];
          for (final upper in [true, false]) {
            final cx = w / 2, cy = upper ? h * 0.45 : h * 0.55;
            final rx = w * 0.42, ry = h * 0.40;
            var run = 0.0;
            for (var k = 0; k < 16; k++) {
              final mid = (run + widths[k] / 2) / total;
              run += widths[k];
              // The two arches are U shapes that stop short of meeting, like real jaws seen from above.
              final theta = upper ? math.pi + _open + mid * (math.pi - 2 * _open) : math.pi - _open - mid * (math.pi - 2 * _open);
              final x = cx + rx * math.cos(theta), y = cy + ry * math.sin(theta);
              final number = upper ? '${k + 1}' : '${32 - k}';
              final tw = unit * widths[k], th = unit * _depth[kinds[k]]! * 1.12;
              // Mesial (towards the middle of the face): screen right on the patient's right side, mirrored on the left;
              // the lower arch is turned half a circle, which flips it again.
              final mesial = (k < 8) == upper ? 1.0 : -1.0;
              teeth.add(
                Positioned(
                  left: x - tw / 2,
                  top: y - th / 2,
                  child: Transform.rotate(
                    angle: theta + math.pi / 2,
                    child: _ToothButton(
                      number: number,
                      kind: kinds[k],
                      size: Size(tw, th),
                      mesial: mesial,
                      procedures: procedures.where((p) => p.tooth == number).toList(),
                      findings: findings.where((f) => f.tooth == number).toList(),
                    ),
                  ),
                ),
              );
            }
          }
          return SizedBox(
            width: w,
            height: h,
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _GumsPainter())),
                ...teeth,
                Align(
                  alignment: const Alignment(0, -0.1),
                  child: Text('UPPER', style: TextStyle(fontSize: 10.5, letterSpacing: 2, fontWeight: FontWeight.w700, color: Palette.muted.withValues(alpha: 0.7))),
                ),
                Align(
                  alignment: const Alignment(0, 0.1),
                  child: Text('LOWER', style: TextStyle(fontSize: 10.5, letterSpacing: 2, fontWeight: FontWeight.w700, color: Palette.muted.withValues(alpha: 0.7))),
                ),
                Align(
                  alignment: const Alignment(-1, 0),
                  child: Text('Right', style: TextStyle(fontSize: 11, color: Palette.muted.withValues(alpha: 0.7))),
                ),
                Align(
                  alignment: const Alignment(1, 0),
                  child: Text('Left', style: TextStyle(fontSize: 11, color: Palette.muted.withValues(alpha: 0.7))),
                ),
              ],
            ),
          );
        },
      ),
      const SizedBox(height: 10),
      const Wrap(
        spacing: 14,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          _Key(Palette.teal, 'Treated'),
          _Key(Palette.apricot, 'Planned'),
          _Key(Color(0xFFB8C2C6), 'Existing filling'),
          _Key(Color(0xFFE8C98A), 'Crown'),
          _Key(null, 'Noted by the dentist'),
        ],
      ),
      const SizedBox(height: 6),
      const Text('Tap a tooth to see what was done', style: TextStyle(fontSize: 12, color: Palette.muted)),
    ],
  );
}

enum _Kind { molar, premolar, canine, incisor }

const _kindNames = {_Kind.molar: 'molar', _Kind.premolar: 'premolar', _Kind.canine: 'canine', _Kind.incisor: 'incisor'};

/// "Upper left first molar" for Universal tooth numbers 1 to 32.
String toothName(String number) {
  final n = int.tryParse(number);
  if (n == null || n < 1 || n > 32) return 'Tooth $number';
  final upper = n <= 16;
  final side = (upper ? n <= 8 : n >= 25) ? 'right' : 'left';
  final fromBack = upper ? (n <= 8 ? n : 17 - n) : (n >= 25 ? 33 - n : n - 16); // 1 = third molar ... 8 = central incisor
  const names = ['third molar', 'second molar', 'first molar', 'second premolar', 'first premolar', 'canine', 'lateral incisor', 'central incisor'];
  return '${upper ? 'Upper' : 'Lower'} $side ${names[fromBack - 1]}';
}

String _surfaceWords(String? surface) {
  if (surface == null || surface.isEmpty) return '';
  const words = {'O': 'biting surface', 'I': 'biting edge', 'M': 'front side', 'D': 'back side', 'B': 'cheek side', 'F': 'lip side', 'L': 'tongue side'};
  return ' (${surface.split('').map((c) => words[c] ?? c).join(', ')})';
}

String _conditionWords(String c) => switch (c) {
  'caries' => 'Decay',
  'filled' => 'Existing filling',
  'crown' => 'Crown',
  'missing' => 'Missing tooth',
  'implant' => 'Implant',
  'root_canal' => 'Root canal treated',
  'fractured' => 'Cracked or broken',
  'sealant' => 'Sealant',
  _ => c,
};

class _ToothButton extends StatelessWidget {
  const _ToothButton({
    required this.number,
    required this.kind,
    required this.size,
    required this.mesial,
    required this.procedures,
    required this.findings,
  });
  final String number;
  final _Kind kind;
  final Size size;
  final double mesial;
  final List<Procedure> procedures;
  final List<Finding> findings;

  @override
  Widget build(BuildContext context) {
    final done = procedures.any((p) => p.done), planned = procedures.any((p) => !p.done);
    final noted = findings.isNotEmpty;
    final states = [if (done) 'treated', if (planned) 'treatment planned', if (noted) 'finding'];
    return Semantics(
      label: states.isEmpty ? 'Tooth $number' : 'Tooth $number: ${states.join(', ')}',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showTooth(context),
        child: ExcludeSemantics(
          child: CustomPaint(
            size: size,
            painter: _ToothPainter(kind: kind, mesial: mesial, procedures: procedures, findings: findings),
          ),
        ),
      ),
    );
  }

  void _showTooth(BuildContext context) {
    final lines = [
      for (final p in procedures) (p.done ? Palette.teal : Palette.apricot, '${p.done ? 'Done' : 'Planned'}: ${p.service}${_surfaceWords(p.surface)}'),
      for (final f in findings) (const Color(0xFFB35F1E), '${_conditionWords(f.condition)}${_surfaceWords(f.surface)}'),
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 54,
                  height: 54,
                  child: Center(
                    child: CustomPaint(
                      size: Size(size.width * 1.9, size.height * 1.9),
                      painter: _ToothPainter(kind: kind, mesial: 1, procedures: procedures, findings: findings),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(toothName(number), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Palette.deepSea)),
                      Text('Tooth $number · ${_kindNames[kind]}', style: const TextStyle(fontSize: 13, color: Palette.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (lines.isEmpty)
              const Text('Nothing recorded on this tooth at this visit.', style: TextStyle(color: Palette.muted))
            else
              for (final (color, text) in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 5), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.35, color: Palette.deepSea))),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// One tooth from above. Local axes: up (negative y) is the cheek or lip side, the mesial side is towards +x times
/// [mesial]. Light comes from the top left of the screen.
class _ToothPainter extends CustomPainter {
  _ToothPainter({required this.kind, required this.mesial, required this.procedures, required this.findings});
  final _Kind kind;
  final double mesial;
  final List<Procedure> procedures;
  final List<Finding> findings;

  bool _has(String condition) => findings.any((f) => f.condition == condition);

  Path _outline(Size s) {
    final w = s.width, h = s.height;
    final r = Rect.fromLTWH(0, 0, w, h);
    switch (kind) {
      case _Kind.molar:
        // A rounded, slightly lobed square: four cusps make four soft bulges.
        return Path()
          ..moveTo(w * 0.18, h * 0.06)
          ..quadraticBezierTo(w * 0.5, -h * 0.04, w * 0.82, h * 0.06)
          ..quadraticBezierTo(w * 1.02, h * 0.18, w * 0.97, h * 0.5)
          ..quadraticBezierTo(w * 1.02, h * 0.84, w * 0.8, h * 0.95)
          ..quadraticBezierTo(w * 0.5, h * 1.04, w * 0.2, h * 0.95)
          ..quadraticBezierTo(-w * 0.02, h * 0.84, w * 0.03, h * 0.5)
          ..quadraticBezierTo(-w * 0.02, h * 0.18, w * 0.18, h * 0.06)
          ..close();
      case _Kind.premolar:
        return Path()..addRRect(RRect.fromRectAndRadius(r.deflate(w * 0.03), Radius.elliptical(w * 0.46, h * 0.42)));
      case _Kind.canine:
        // Broader on the cheek side, coming to a soft point: the cusp tip.
        return Path()
          ..moveTo(w * 0.5, h * 0.02)
          ..quadraticBezierTo(w * 0.98, h * 0.12, w * 0.95, h * 0.55)
          ..quadraticBezierTo(w * 0.86, h * 0.98, w * 0.5, h * 0.98)
          ..quadraticBezierTo(w * 0.14, h * 0.98, w * 0.05, h * 0.55)
          ..quadraticBezierTo(w * 0.02, h * 0.12, w * 0.5, h * 0.02)
          ..close();
      case _Kind.incisor:
        // Seen from above an incisor is a thin, curved edge: wider than deep.
        return Path()
          ..moveTo(w * 0.04, h * 0.32)
          ..quadraticBezierTo(w * 0.5, -h * 0.08, w * 0.96, h * 0.32)
          ..quadraticBezierTo(w * 1.0, h * 0.78, w * 0.5, h * 0.98)
          ..quadraticBezierTo(w * 0.0, h * 0.78, w * 0.04, h * 0.32)
          ..close();
    }
  }

  /// The part of the outline a surface letter covers.
  Path _surface(Size s, String letter) {
    final w = s.width, h = s.height;
    final mesialRight = mesial > 0;
    final rect = switch (letter) {
      'O' || 'I' => Rect.fromCenter(center: Offset(w / 2, h / 2), width: w * 0.56, height: h * 0.5),
      'B' || 'F' => Rect.fromLTWH(0, 0, w, h * 0.3),
      'L' => Rect.fromLTWH(0, h * 0.7, w, h * 0.3),
      'M' => mesialRight ? Rect.fromLTWH(w * 0.72, 0, w * 0.28, h) : Rect.fromLTWH(0, 0, w * 0.28, h),
      'D' => mesialRight ? Rect.fromLTWH(0, 0, w * 0.28, h) : Rect.fromLTWH(w * 0.72, 0, w * 0.28, h),
      _ => Rect.fromLTWH(0, 0, w, h),
    };
    return Path.combine(PathOperation.intersect, _outline(s), Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(w * 0.2))));
  }

  void _paintMarks(Canvas canvas, Size s, String? surface, Color color) {
    final paint = Paint()..color = color.withValues(alpha: 0.88);
    final letters = (surface == null || surface.isEmpty) ? ['O'] : surface.split('');
    for (final l in letters) {
      canvas.drawPath(_surface(s, l), paint);
    }
  }

  @override
  void paint(Canvas canvas, Size s) {
    final outline = _outline(s);
    final rect = Offset.zero & s;
    final missing = _has('missing');

    if (missing) {
      // An empty space in the arch: a dashed ghost of the tooth.
      final ghost = Paint()
        ..color = Palette.muted.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      for (final metric in outline.computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 5) {
          canvas.drawPath(metric.extractPath(d, d + 2.5), ghost);
        }
      }
      return;
    }

    // Contact shadow on the gum, then the enamel body with light from the top left.
    canvas.drawPath(
      outline.shift(const Offset(0.8, 1.6)),
      Paint()
        ..color = const Color(0xFF5B2E33).withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
    );
    final crown = _has('crown');
    final implant = _has('implant');
    canvas.drawPath(
      outline,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: crown
              ? const [Color(0xFFFFF6DE), Color(0xFFF1D9A4), Color(0xFFCFAE6C)]
              : implant
              ? const [Color(0xFFF7FAFB), Color(0xFFD9E1E4), Color(0xFFAFBCC2)]
              : const [Color(0xFFFFFFFF), Color(0xFFF3F1EA), Color(0xFFD9D5C8)],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );

    // Anatomy: grooves between cusps and a soft highlight on each cusp.
    final groove = Paint()
      ..color = const Color(0xFF9E978A).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.7, s.width * 0.045)
      ..strokeCap = StrokeCap.round;
    final w = s.width, h = s.height;
    List<Offset> cusps;
    switch (kind) {
      case _Kind.molar:
        canvas.drawLine(Offset(w * 0.2, h * 0.5), Offset(w * 0.8, h * 0.5), groove);
        canvas.drawLine(Offset(w * 0.5, h * 0.2), Offset(w * 0.5, h * 0.8), groove);
        cusps = [Offset(w * 0.3, h * 0.3), Offset(w * 0.7, h * 0.3), Offset(w * 0.3, h * 0.7), Offset(w * 0.7, h * 0.7)];
      case _Kind.premolar:
        canvas.drawLine(Offset(w * 0.22, h * 0.5), Offset(w * 0.78, h * 0.5), groove);
        cusps = [Offset(w * 0.5, h * 0.3), Offset(w * 0.5, h * 0.72)];
      case _Kind.canine:
        cusps = [Offset(w * 0.5, h * 0.45)];
      case _Kind.incisor:
        canvas.drawLine(Offset(w * 0.2, h * 0.42), Offset(w * 0.8, h * 0.42), groove..strokeWidth = math.max(0.6, w * 0.03));
        cusps = [Offset(w * 0.5, h * 0.55)];
    }
    if (!crown && !implant) {
      for (final c in cusps) {
        canvas.drawCircle(
          c,
          w * (kind == _Kind.molar ? 0.2 : 0.24),
          Paint()
            ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.95), Colors.white.withValues(alpha: 0)])
                .createShader(Rect.fromCircle(center: c.translate(-w * 0.04, -h * 0.04), radius: w * 0.24)),
        );
      }
    }

    // Existing fillings and sealants, then this visit's treatment: planned in apricot, done in teal.
    for (final f in findings.where((f) => f.condition == 'filled' || f.condition == 'sealant')) {
      _paintMarks(canvas, s, f.surface, f.condition == 'filled' ? const Color(0xFFAAB5BA) : const Color(0xFFDDEFF0));
    }
    for (final p in procedures.where((p) => !p.done)) {
      _paintMarks(canvas, s, p.surface, Palette.apricot);
    }
    for (final p in procedures.where((p) => p.done)) {
      _paintMarks(canvas, s, p.surface, Palette.teal);
    }
    // Decay as a dark spot, a crack as a line, a root canal as a small dot.
    for (final f in findings) {
      final at = f.surface == null || f.surface!.isEmpty ? Offset(w / 2, h / 2) : _surface(s, f.surface![0]).getBounds().center;
      switch (f.condition) {
        case 'caries':
          canvas.drawCircle(at, w * 0.11, Paint()..color = const Color(0xFF5A3A1E).withValues(alpha: 0.85));
        case 'fractured':
          canvas.drawPath(
            Path()
              ..moveTo(w * 0.3, h * 0.15)
              ..lineTo(w * 0.48, h * 0.45)
              ..lineTo(w * 0.42, h * 0.6)
              ..lineTo(w * 0.62, h * 0.88),
            Paint()
              ..color = const Color(0xFF4A3426)
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1, w * 0.05),
          );
        case 'root_canal':
          canvas.drawCircle(Offset(w / 2, h / 2), w * 0.08, Paint()..color = const Color(0xFFC0392B).withValues(alpha: 0.75));
      }
    }

    // A crisp enamel rim, and the dentist's ring around anything noted.
    canvas.drawPath(
      outline,
      Paint()
        ..color = const Color(0xFFB9B2A3).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    // The dentist's ring marks what needs attention, not long-standing work such as a crown or an old filling.
    if (findings.any((f) => const {'caries', 'fractured', 'root_canal'}.contains(f.condition))) {
      canvas.drawPath(
        _outline(s),
        Paint()
          ..color = const Color(0xFFB35F1E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.6, w * 0.08),
      );
    }
  }

  @override
  bool shouldRepaint(_ToothPainter old) => old.procedures != procedures || old.findings != findings || old.kind != kind;
}

/// The gums: two soft pink horseshoes the teeth sit in, with a lighter rim and a little depth.
class _GumsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    for (final upper in [true, false]) {
      final cy = upper ? h * 0.45 : h * 0.55;
      final oval = Rect.fromCenter(center: Offset(w / 2, cy), width: w * 0.84, height: h * 0.80);
      final start = upper ? math.pi + ToothChart._open - 0.05 : ToothChart._open - 0.05;
      const sweep = math.pi - 2 * ToothChart._open + 0.1;
      final band = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = w * 0.085
        ..shader = RadialGradient(
          center: Alignment(0, upper ? -0.2 : 0.2),
          radius: 0.7,
          colors: const [Color(0xFFF7C9C6), Color(0xFFEFA9A8), Color(0xFFE39593)],
          stops: const [0, 0.7, 1],
        ).createShader(oval.inflate(w * 0.06));
      canvas.drawArc(oval, start, sweep, false, band);
      canvas.drawArc(
        oval.inflate(w * 0.05),
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(_GumsPainter old) => false;
}

class _Key extends StatelessWidget {
  const _Key(this.color, this.label);
  final Color? color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: color == null ? Border.all(color: const Color(0xFFB35F1E), width: 2) : null,
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12, color: Palette.muted)),
    ],
  );
}
