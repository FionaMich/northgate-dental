import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dental/ui.dart';

import '../data/assistant_repository.dart';
import '../design/tokens.dart';
import '../state.dart';
import '../data/call_repository.dart';
import 'chat_widgets.dart';
import 'nora_call_screen.dart';
import 'team_chat_screen.dart';
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
  String _language = appLanguage.value; // Nora starts in the app's language
  bool _waiting = false;
  Map<String, dynamic>? _confirm;
  bool _teamOffered =
      false; // Nora passed something to the team in this conversation

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

  static const _team = 'Talk to a member of our team';
  static const _starters = {
    'Book a cleaning': Icons.event_available_rounded,
    'Opening hours': Icons.schedule_rounded,
    'Pay my bill': Icons.credit_card_rounded,
    _team: Icons.support_agent_rounded,
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
        _teamOffered = _teamOffered || turn.team;
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

  void _send([String? text, bool team = false]) {
    final message = (text ?? _input.text).trim();
    if (message.isEmpty || _waiting) return;
    _input.clear();
    setState(() => _lines.add(_Line(message, mine: true)));
    _run(
      () => ref
          .read(assistantRepositoryProvider)
          .send(_thread, message, _language, team: team),
    );
  }

  /// The patient's button on a card; [replyBy] ("app" or "call") answers the team card.
  void _answer(bool accept, {String? replyBy, String? phone}) {
    final said = switch (replyBy) {
      'call' => _confirm?['call'] as String? ?? 'Call me back',
      _ when accept => _confirm?['yes'] as String? ?? 'Confirm',
      _ => _confirm?['no'] as String? ?? 'Not now',
    };
    setState(() {
      _lines.add(_Line(said, mine: true));
      _confirm = null;
    });
    _run(
      () => ref
          .read(assistantRepositoryProvider)
          .confirm(_thread, accept, _language, replyBy: replyBy, phone: phone),
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
            tooltip: tr('Talk to Nora'),
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
                              onPressed: () =>
                                  _send(trIn(_language, s), s == _team), // in the patient's language, as they would write it
                            ),
                        ],
                      ),
                    ),
                  if (_confirm?['action'] == 'team')
                    _TeamCard(card: _confirm!, onAnswer: _answer)
                  else if (_confirm != null)
                    _ConfirmCard(confirm: _confirm!, onAnswer: _answer),
                  if (_teamOffered && !_waiting)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FilledButton.tonalIcon(
                          key: const Key('open-team-chat'),
                          onPressed: () => openTeamChat(context, ref),
                          icon: const Icon(Icons.support_agent_rounded),
                          label: const Text(
                            'Open your conversation with the team',
                          ),
                        ),
                      ),
                    ),
                  if (_waiting) const ChatTyping(who: 'Nora'),
                ],
              ),
            ),
          ),
          // The same four requests stay one tap away for the whole conversation, like quick replies in a messenger.
          if (_lines.length > 1 && !_waiting && _confirm == null)
            SizedBox(
              height: 46,
              child: ListView(
                key: const Key('quick-replies'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                children: [
                  for (final MapEntry(key: s, value: icon) in _starters.entries)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ActionChip(
                        key: Key('quick-$s'),
                        avatar: Icon(icon, size: 18),
                        label: Text(s),
                        backgroundColor: Colors.white,
                        onPressed: () => _send(trIn(_language, s), s == _team),
                      ),
                    ),
                ],
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

/// How the team should reply: here in the app, or a call back on a number the patient types. The wording comes from
/// the server's reviewed texts in the patient's language; the number is checked here and again on the server.
class _TeamCard extends StatefulWidget {
  const _TeamCard({required this.card, required this.onAnswer});
  final Map<String, dynamic> card;
  final void Function(bool, {String? replyBy, String? phone}) onAnswer;

  @override
  State<_TeamCard> createState() => _TeamCardState();
}

class _TeamCardState extends State<_TeamCard> {
  final _phone = TextEditingController();
  bool _calling = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  String _text(String key, String fallback) =>
      (widget.card[key] as String?) ?? fallback;

  bool get _numberOk {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '').length;
    return digits >= 7 &&
        digits <= 15; // the server's rule for a callback number
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.teal, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.support_agent_rounded, color: Palette.teal),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _text('title', 'How would you like the team to reply?'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Palette.deepSea,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!_calling) ...[
            FilledButton.icon(
              key: const Key('team-app'),
              onPressed: () => widget.onAnswer(true, replyBy: 'app'),
              style: FilledButton.styleFrom(backgroundColor: Palette.teal),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: Text(_text('yes', 'Reply in the app')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('team-call'),
              onPressed: () => setState(() => _calling = true),
              icon: const Icon(Icons.call_rounded),
              label: Text(_text('call', 'Call me back')),
            ),
          ] else ...[
            TextField(
              key: const Key('team-phone'),
              controller: _phone,
              autofocus: true,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _text('phone', 'Your phone number'),
                prefixIcon: const Icon(Icons.call_rounded),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              key: const Key('team-call-send'),
              onPressed: _numberOk
                  ? () => widget.onAnswer(
                      true,
                      replyBy: 'call',
                      phone: _phone.text.trim(),
                    )
                  : null,
              style: FilledButton.styleFrom(backgroundColor: Palette.teal),
              child: Text(_text('call', 'Call me back')),
            ),
          ],
          TextButton(
            key: const Key('team-no'),
            onPressed: () => widget.onAnswer(false),
            child: Text(_text('no', 'Not now')),
          ),
        ],
      ),
    );
  }
}
