import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/account_repository.dart';
import '../data/aligner_reminders.dart';
import '../data/wear_log.dart';
import '../design/format.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import 'care_widgets.dart';

/// "Now", replaceable in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The phone's encrypted store for wear logs, replaceable in tests.
final wearStoreProvider = Provider<WearStore>((ref) => SecureWearStore());

/// Phone reminders to put aligners back in, replaceable in tests.
final alignerRemindersProvider = Provider<AlignerReminders>((ref) => LocalAlignerReminders());

String hoursMinutes(Duration d) => '${d.inHours}h ${d.inMinutes % 60}m';

/// Aligner wear timer: put aligners in, take them out, and see today's total against 22 hours.
/// Kept only on this phone (encrypted), and removed when the person signs out.
class AlignerScreen extends ConsumerStatefulWidget {
  const AlignerScreen({super.key, required this.patient});
  final LinkedPatient patient;

  @override
  ConsumerState<AlignerScreen> createState() => _AlignerScreenState();
}

class _AlignerScreenState extends ConsumerState<AlignerScreen> {
  WearLog? _log;
  Timer? _tick;

  String get _key => 'aligner:${widget.patient.id}';

  @override
  void initState() {
    super.initState();
    ref.read(wearStoreProvider).read(_key).then((raw) {
      if (mounted) setState(() => _log = WearLog.decode(raw));
    });
    // Refresh the running total once a minute while the screen is open.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && (_log?.wearing ?? false)) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    final now = ref.read(clockProvider)();
    final log = _log!;
    final next = log.wearing ? log.stop(now) : log.start(now);
    setState(() => _log = next);
    await ref.read(wearStoreProvider).write(_key, next.encode());
    final reminders = ref.read(alignerRemindersProvider);
    try {
      next.wearing ? await reminders.backIn() : await reminders.takenOut(now);
    } on Exception {
      // Reminders are a nicety: if the phone refuses them, the timer still works.
    }
  }

  @override
  Widget build(BuildContext context) {
    final log = _log;
    final now = ref.watch(clockProvider)();
    final today = log?.wornOn(now, now: now) ?? Duration.zero;
    final progress = (today.inMinutes / WearLog.goal.inMinutes).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Palette.mist,
      body: ListView(
        padding: EdgeInsets.zero,
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
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      color: Colors.white,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 4, 12, 20),
                      child: Text(
                        'Aligner timer',
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.8, color: Colors.white),
                      ),
                    ),
                    Center(
                      child: Semantics(
                        label: '${hoursMinutes(today)} of 22 hours today',
                        child: SizedBox.square(
                          dimension: 220,
                          child: CustomPaint(
                            painter: _Ring(progress),
                            child: ExcludeSemantics(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    hoursMinutes(today),
                                    style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w700, color: Colors.white),
                                  ),
                                  const Text('of 22h today', style: TextStyle(fontSize: 15, color: Color(0xFFCDEFE7))),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
            child: log == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Panel(
                        child: Row(
                          children: [
                            IconTile(log.wearing ? Icons.sentiment_satisfied_rounded : Icons.do_not_disturb_on_outlined, size: 48),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    log.wearing ? 'Aligners in' : 'Aligners out',
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Palette.deepSea),
                                  ),
                                  Text(
                                    log.wearing
                                        ? 'Since ${clock(log.sessions.last.$1)}. Take them out only to eat, drink anything but water, and brush.'
                                        : 'Put them back in after eating and brushing. We will remind you after 30 minutes.',
                                    style: const TextStyle(fontSize: 14, height: 1.4, color: Palette.muted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      PrimaryButton(
                        key: const Key('wear-toggle'),
                        label: log.wearing ? 'Take aligners out' : 'Put aligners in',
                        onPressed: _toggle,
                      ),
                      const SizedBox(height: 26),
                      const SectionTitle('Last 7 days'),
                      Panel(
                        child: _Week(log: log, now: now),
                      ),
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          Icon(Icons.lock_outline_rounded, size: 16, color: Palette.muted),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Kept only on this phone, encrypted, and removed when you sign out.',
                              style: TextStyle(fontSize: 13, color: Palette.muted),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Progress ring: a soft track and a mint arc that fills towards 22 hours.
class _Ring extends CustomPainter {
  _Ring(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.075;
    final arc = rect.deflate(stroke / 2);
    canvas.drawArc(
      arc,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.white.withValues(alpha: 0.14),
    );
    if (progress > 0) {
      canvas.drawArc(
        arc,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..shader = const SweepGradient(colors: [Palette.shine, Color(0xFF8FE3C8), Palette.shine]).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_Ring old) => old.progress != progress;
}

class _Week extends StatelessWidget {
  const _Week({required this.log, required this.now});
  final WearLog log;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final days = [for (var i = 6; i >= 0; i--) DateTime(now.year, now.month, now.day - i)];
    return SizedBox(
      height: 130,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in days)
            Expanded(
              child: Builder(
                builder: (_) {
                  final worn = log.wornOn(d, now: now);
                  final share = (worn.inMinutes / WearLog.goal.inMinutes).clamp(0.0, 1.0);
                  final met = worn >= WearLog.goal;
                  return Semantics(
                    label: '${weekday(d)}: ${hoursMinutes(worn)}',
                    child: ExcludeSemantics(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('${worn.inHours}h', style: const TextStyle(fontSize: 11, color: Palette.muted)),
                          const SizedBox(height: 4),
                          Container(
                            width: 22,
                            height: 4 + 76 * share,
                            decoration: BoxDecoration(
                              color: met ? Palette.teal : const Color(0xFFB9DDD5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            weekday(d).substring(0, 1),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Palette.deepSea),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
