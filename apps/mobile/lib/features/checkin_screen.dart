import 'package:dental/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/programme_repository.dart';
import '../design/tokens.dart';
import '../design/widgets.dart';
import '../state.dart';
import 'care_widgets.dart';

/// Today's recovery check-in (W24). The answer goes to a database function that applies the clinic's fixed rules
/// (W25): the app only shows what the clinic decided, in reviewed words, and the emergency text never depends on a
/// model.
class CheckinScreen extends ConsumerStatefulWidget {
  const CheckinScreen({super.key, required this.checkinId});
  final String checkinId;

  @override
  ConsumerState<CheckinScreen> createState() => _CheckinScreenState();
}

const _symptoms = {
  'bleeding': 'Bleeding',
  'swelling': 'Swelling',
  'fever': 'Fever or chills',
  'numbness': 'Numbness',
  'bad_taste': 'A bad taste',
};

class _CheckinScreenState extends ConsumerState<CheckinScreen> {
  double _pain = 2;
  String? _feeling;
  final Set<String> _picked = {};
  final _note = TextEditingController();
  bool _sending = false;
  String? _level;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final level = await ref
          .read(programmeRepositoryProvider)
          .answer(
            widget.checkinId,
            pain: _pain.round(),
            feeling: _feeling!,
            symptoms: _picked.toList(),
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      ref.invalidate(programmesProvider);
      if (mounted) setState(() => _level = level);
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not send your check-in. Please try again, or call your clinic.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.mist,
      appBar: AppBar(
        backgroundColor: Palette.deepSea,
        foregroundColor: Colors.white,
        title: const Text("Today's check-in"),
      ),
      body: _level != null
          ? _Result(level: _level!)
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              children: [
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'How much pain do you have?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Palette.deepSea,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '0 is none, 10 is the worst you can imagine.',
                        style: TextStyle(color: Palette.muted),
                      ),
                      Slider(
                        key: const Key('checkin-pain'),
                        value: _pain,
                        max: 10,
                        divisions: 10,
                        label: '${_pain.round()}',
                        activeColor: Palette.teal,
                        onChanged: (v) => setState(() => _pain = v),
                      ),
                      Center(
                        child: Text(
                          '${_pain.round()} / 10',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Palette.deepSea,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Compared with yesterday, you feel',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Palette.deepSea,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final (key, label) in [
                            ('better', 'Better'),
                            ('same', 'The same'),
                            ('worse', 'Worse'),
                          ])
                            ChoiceChip(
                              key: Key('checkin-$key'),
                              label: Text(label),
                              selected: _feeling == key,
                              selectedColor: Palette.enamel,
                              onSelected: (_) => setState(() => _feeling = key),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Anything else today?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Palette.deepSea,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final MapEntry(:key, :value)
                              in _symptoms.entries)
                            FilterChip(
                              key: Key('checkin-symptom-$key'),
                              label: Text(value),
                              selected: _picked.contains(key),
                              selectedColor: Palette.enamel,
                              onSelected: (on) => setState(
                                () =>
                                    on ? _picked.add(key) : _picked.remove(key),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('checkin-note'),
                        controller: _note,
                        maxLength: 500,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: tr(
                            'Anything you want the team to know (optional)',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                PrimaryButton(
                  key: const Key('checkin-send'),
                  label: tr('Send my check-in'),
                  onPressed: _feeling == null || _sending ? null : _send,
                ),
                const SizedBox(height: 14),
                const Text(
                  'If you have trouble breathing or swallowing, or swelling spreading to your eye or neck, call 911 now.',
                  style: TextStyle(color: Palette.muted, fontSize: 13),
                ),
              ],
            ),
    );
  }
}

/// What the clinic's rules decided, in fixed words.
class _Result extends StatelessWidget {
  const _Result({required this.level});
  final String level;

  @override
  Widget build(BuildContext context) {
    final emergency = level == 'emergency';
    final (title, body) = switch (level) {
      'emergency' => (
        'Please get help now',
        'What you told us needs urgent care. Call 911 if you have trouble breathing or swallowing, or call your clinic now. We have alerted the team.',
      ),
      'task' => (
        'Thank you, the team will call you',
        'A member of the team will call you today to check how you are.',
      ),
      'nudge' => (
        'Thank you for checking in',
        'The team will keep an eye on your answers. Tell us tomorrow how you are.',
      ),
      _ => (
        'Thank you, healing as expected',
        'See you at tomorrow\'s check-in.',
      ),
    };
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          key: Key('checkin-result-$level'),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: emergency ? const Color(0xFFFDECEA) : Palette.enamel,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: emergency ? Palette.error : Palette.teal),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                emergency ? Icons.warning_rounded : Icons.check_circle_rounded,
                color: emergency ? Palette.error : Palette.teal,
                size: 36,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Palette.deepSea,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: Palette.deepSea,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: tr('Done'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

/// The Home card for a care programme: join it (consent), or open today's check-in.
class CareProgrammeCard extends ConsumerWidget {
  const CareProgrammeCard({super.key, required this.programme});
  final CareProgramme programme;

  static const _titles = {
    'post_procedure': 'Your recovery programme',
    'aligners': 'Your aligner programme',
    'recall': 'Your check-up reminders',
  };
  static const _consent = {
    'post_procedure': 'A short check-in each day while you heal. The team sees your answers and calls you if anything needs a closer look.',
    'aligners': 'Share how many hours you wear your aligners each day, so your orthodontist can see how it is going.',
    'recall': 'A reminder when your next check-up is due.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(programmeRepositoryProvider);
    final p = programme;
    final Widget action;
    if (p.invited) {
      action = PrimaryButton(
        key: Key('join-${p.programme}'),
        label: tr('Join the programme'),
        onPressed: () async {
          await repo.join(p.id);
          ref.invalidate(programmesProvider);
        },
      );
    } else if (p.programme == 'post_procedure' &&
        p.todayCheckinId != null &&
        !p.todayAnswered) {
      action = PrimaryButton(
        key: const Key('open-checkin'),
        label: tr("Today's check-in"),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CheckinScreen(checkinId: p.todayCheckinId!),
          ),
        ),
      );
    } else {
      action = Row(
        children: [
          Expanded(
            child: Text(
              p.programme == 'post_procedure'
                  ? (p.todayAnswered
                        ? 'Checked in today. Thank you.'
                        : 'Your next check-in opens at 10:00.')
                  : 'You are in this programme.',
              style: const TextStyle(color: Palette.muted),
            ),
          ),
          TextButton(
            key: Key('leave-${p.programme}'),
            onPressed: () async {
              await repo.leave(p.id);
              ref.invalidate(programmesProvider);
            },
            child: const Text('Leave the programme'),
          ),
        ],
      );
    }
    return Container(
      key: Key('care-${p.programme}'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TintIcon(Icons.favorite_rounded, Tint.teal, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _titles[p.programme] ?? 'Your care programme',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Palette.deepSea,
                  ),
                ),
              ),
            ],
          ),
          if (p.invited) ...[
            const SizedBox(height: 10),
            Text(
              _consent[p.programme] ?? '',
              style: const TextStyle(
                fontSize: 13.5,
                color: Palette.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'You can leave at any time.',
              style: TextStyle(fontSize: 13, color: Palette.muted),
            ),
          ],
          const SizedBox(height: 14),
          action,
        ],
      ),
    );
  }
}
