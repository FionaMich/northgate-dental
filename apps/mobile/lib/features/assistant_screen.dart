import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/assistant_repository.dart';
import '../design/tokens.dart';
import '../state.dart';
import '../data/call_repository.dart';
import 'chat_widgets.dart';
import 'nora_call_screen.dart';
import 'voice_screen.dart';

/// Chat with Northgate's virtual receptionist, in the patient's language. It always opens by saying it is an AI;
/// bookings and cancellations wait for the patient's own button; anything clinical goes to the team.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _Line {
  _Line(this.text, {this.mine = false}) : at = DateTime.now();
  final String text;
  final bool mine;
  final DateTime at;
  bool read =
      false; // the patient's message turns blue once Nora has answered it
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

  bool _startingCall = false;

  /// A call with Nora when the server offers one; otherwise the phone's own voice screen.
  Future<void> _openVoice() async {
    if (_startingCall) return; // a second tap while the server answers must not start a second call
    setState(() => _startingCall = true);
    final navigator = Navigator.of(context);
    NoraCall? call;
    try {
      call = await ref.read(callRepositoryProvider).start(_language);
    } on Exception {
      call = null; // CallsUnavailable, or no network: the phone's voice still works
    }
    if (!mounted) return;
    setState(() => _startingCall = false);
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => call == null
            ? VoiceScreen(language: _language)
            : NoraCallScreen(call: call, language: _language),
      ),
    );
  }

  static const _starters = {
    'Book a cleaning': Icons.event_available_rounded,
    'Opening hours': Icons.schedule_rounded,
    'Pay my bill': Icons.credit_card_rounded,
    'Talk to a member of our team': Icons.support_agent_rounded,
  };

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
              _Line(
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
        for (final l in _lines) {
          l.read = true;
        }
        if (turn.reply != null) _lines.add(_Line(turn.reply!));
        _confirm = turn.confirm;
      });
    } on AssistantError catch (e) {
      if (mounted) setState(() => _lines.add(_Line(e.message)));
    } on Exception {
      if (mounted) {
        setState(
          () => _lines.add(
            _Line(
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
      _lines.add(
        _Line(
          accept
              ? (_confirm?['yes'] as String? ?? 'Confirm')
              : (_confirm?['no'] as String? ?? 'Not now'),
          mine: true,
        ),
      );
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
    return Scaffold(
      backgroundColor: chatWallpaper,
      appBar: AppBar(
        backgroundColor: Palette.deepSea,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Row(
          children: [
            const CircleAvatar(
              radius: 17,
              backgroundColor: Color(0xFFDDF4EC),
              backgroundImage: AssetImage('assets/images/nora/idle.png'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nora',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    _waiting ? 'typing…' : 'AI assistant · online',
                    key: const Key('chat-presence'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFA9DCD1),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('open-voice'),
            tooltip: 'Talk to Nora',
            icon: const Icon(Icons.graphic_eq_rounded),
            onPressed: _startingCall ? null : _openVoice,
          ),
          TextButton.icon(
            key: const Key('pick-language'),
            onPressed: _pickLanguage,
            icon: const Icon(
              Icons.translate_rounded,
              color: Colors.white,
              size: 18,
            ),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                assistantLanguages[_language]!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                children: [
                  const ChatDayChip('Today'),
                  for (final (i, l) in _lines.indexed)
                    ChatBubble(
                      text: l.text,
                      at: l.at,
                      mine: l.mine,
                      first: i == 0 || _lines[i - 1].mine != l.mine,
                      delivery: !l.mine
                          ? null
                          : l.read
                          ? Delivery.read
                          : Delivery.delivered,
                    ),
                  if (_lines.length == 1 && !_waiting)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final MapEntry(key: s, value: icon)
                              in _starters.entries)
                            ActionChip(
                              key: Key('starter-$s'),
                              avatar: Icon(icon),
                              label: Text(s),
                              onPressed: () => _send(s),
                            ),
                        ],
                      ),
                    ),
                  if (_confirm != null)
                    _ConfirmCard(confirm: _confirm!, onAnswer: _answer),
                  if (_waiting) const ChatTyping(who: 'Nora'),
                ],
              ),
            ),
          ),
          ChatComposer(
            controller: _input,
            onSend: _send,
            label: 'Message to Nora',
            hint: 'Message',
            enabled: _confirm == null,
            canSend: !_waiting && _confirm == null,
          ),
        ],
      ),
    );
  }
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({required this.confirm, required this.onAnswer});
  final Map<String, dynamic> confirm;
  final void Function(bool) onAnswer;

  @override
  Widget build(BuildContext context) {
    // Wording comes from the server's reviewed texts in the patient's language; English only as a fallback.
    final booking = confirm['action'] == 'book';
    String text(String key, String fallback) =>
        (confirm[key] as String?) ?? fallback;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: booking ? Palette.teal : Palette.error,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            text('title', booking ? 'Book this visit?' : 'Cancel this visit?'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Palette.deepSea,
            ),
          ),
          if (confirm['detail'] != null) ...[
            const SizedBox(height: 6),
            Text(
              confirm['detail'] as String,
              style: const TextStyle(height: 1.4, color: Palette.deepSea),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('confirm-no'),
                  onPressed: () => onAnswer(false),
                  child: Text(text('no', 'Not now')),
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
                  child: Text(
                    text('yes', booking ? 'Confirm' : 'Cancel visit'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
