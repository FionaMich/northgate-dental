import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/assistant_repository.dart';
import '../design/art.dart';
import '../design/tokens.dart';
import '../state.dart';

/// Chat with Northgate's virtual receptionist, in the patient's language. It always opens by saying it is an AI;
/// bookings and cancellations wait for the patient's own button; anything clinical goes to the team.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _Line {
  const _Line(this.text, {this.mine = false});
  final String text;
  final bool mine;
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _lines = <_Line>[];
  late final String _thread = List.generate(
    24,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();
  String _language = 'en';
  bool _waiting = false;
  Map<String, dynamic>? _confirm;

  static const _starters = [
    'Book a cleaning',
    'Opening hours',
    'Pay my bill',
    'Talk to a person',
  ];

  @override
  void initState() {
    super.initState();
    _hello();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _hello() async {
    try {
      final text = await ref.read(assistantRepositoryProvider).hello(_language);
      if (mounted) {
        setState(
          () => _lines
            ..clear()
            ..add(_Line(text)),
        );
      }
    } on Exception {
      if (mounted) {
        setState(
          () => _lines
            ..clear()
            ..add(
              const _Line(
                'The receptionist is unavailable right now. Please call your clinic.',
              ),
            ),
        );
      }
    }
  }

  Future<void> _run(Future<AssistantTurn> Function() call) async {
    setState(() => _waiting = true);
    _toEnd();
    try {
      final turn = await call();
      if (!mounted) return;
      setState(() {
        if (turn.reply != null) _lines.add(_Line(turn.reply!));
        _confirm = turn.confirm;
      });
    } on AssistantError catch (e) {
      if (mounted) setState(() => _lines.add(_Line(e.message)));
    } on Exception {
      if (mounted) {
        setState(
          () => _lines.add(
            const _Line(
              'Something went wrong. Please try again, or call your clinic.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _waiting = false);
      _toEnd();
    }
  }

  void _send([String? text]) {
    final message = (text ?? _input.text).trim();
    if (message.isEmpty || _waiting) return;
    _input.clear();
    setState(() => _lines.add(_Line(message, mine: true)));
    _run(
      () => ref
          .read(assistantRepositoryProvider)
          .send(_thread, message, _language),
    );
  }

  void _answer(bool accept) {
    setState(() {
      _lines.add(_Line(accept ? 'Yes, confirm' : 'Not now', mine: true));
      _confirm = null;
    });
    _run(
      () => ref
          .read(assistantRepositoryProvider)
          .confirm(_thread, accept, _language),
    );
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });

  Future<void> _pickLanguage() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final MapEntry(:key, :value) in assistantLanguages.entries)
              ListTile(
                key: Key('language-$key'),
                title: Text(value),
                trailing: key == _language
                    ? const Icon(Icons.check_rounded, color: Palette.teal)
                    : null,
                onTap: () => Navigator.of(context).pop(key),
              ),
          ],
        ),
      ),
    );
    if (picked != null && picked != _language) {
      setState(() => _language = picked);
      _hello();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rtl = _language == 'ar';
    return Scaffold(
      backgroundColor: Palette.mist,
      appBar: AppBar(
        backgroundColor: Palette.deepSea,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: const Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Center(child: Tooth3D(height: 26)),
            ),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Receptionist',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                Text(
                  'AI assistant · answers in 12 languages',
                  style: TextStyle(fontSize: 12, color: Color(0xFFA9DCD1)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            key: const Key('pick-language'),
            onPressed: _pickLanguage,
            icon: const Icon(
              Icons.translate_rounded,
              color: Colors.white,
              size: 18,
            ),
            label: Text(
              assistantLanguages[_language]!,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  for (final l in _lines) _Bubble(line: l),
                  if (_lines.length == 1 && !_waiting)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in _starters)
                          ActionChip(
                            key: Key('starter-$s'),
                            label: Text(s),
                            onPressed: () => _send(s),
                          ),
                      ],
                    ),
                  if (_confirm != null)
                    _ConfirmCard(confirm: _confirm!, onAnswer: _answer),
                  if (_waiting) const _Writing(),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('assistant-input'),
                      controller: _input,
                      enabled: _confirm == null,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Type in any of our languages',
                        counterText: '',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton.filled(
                    key: const Key('assistant-send'),
                    onPressed: _waiting || _confirm != null ? null : _send,
                    style: IconButton.styleFrom(backgroundColor: Palette.teal),
                    icon: const Icon(Icons.arrow_upward_rounded),
                    tooltip: 'Send',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.line});
  final _Line line;

  @override
  Widget build(BuildContext context) => Align(
    alignment: line.mine
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart,
    child: Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.8,
      ),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: line.mine ? Palette.teal : Colors.white,
        borderRadius: BorderRadiusDirectional.only(
          topStart: const Radius.circular(18),
          topEnd: const Radius.circular(18),
          bottomStart: Radius.circular(line.mine ? 18 : 4),
          bottomEnd: Radius.circular(line.mine ? 4 : 18),
        ),
        boxShadow: [
          BoxShadow(
            color: Palette.deepSea.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: SelectableText(
        line.text,
        style: TextStyle(
          fontSize: 15,
          height: 1.4,
          color: line.mine ? Colors.white : Palette.deepSea,
        ),
      ),
    ),
  );
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({required this.confirm, required this.onAnswer});
  final Map<String, dynamic> confirm;
  final void Function(bool) onAnswer;

  @override
  Widget build(BuildContext context) {
    final booking = confirm['action'] == 'book';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.teal, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            booking ? 'Book this visit?' : 'Cancel this visit?',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Palette.deepSea,
            ),
          ),
          const SizedBox(height: 6),
          if (booking)
            Text(
              '${confirm['when']} · ${confirm['clinic']}',
              style: const TextStyle(color: Palette.deepSea),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('confirm-no'),
                  onPressed: () => onAnswer(false),
                  child: const Text('Not now'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const Key('confirm-yes'),
                  onPressed: () => onAnswer(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: booking ? Palette.teal : Palette.error,
                  ),
                  child: Text(booking ? 'Confirm' : 'Cancel visit'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Writing extends StatelessWidget {
  const _Writing();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Palette.teal),
        ),
        SizedBox(width: 10),
        Flexible(
          child: Text(
            'Writing… this can take up to a minute',
            style: TextStyle(fontSize: 13, color: Palette.muted),
          ),
        ),
      ],
    ),
  );
}
