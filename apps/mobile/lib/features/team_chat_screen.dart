import 'dart:async';

import 'package:dental/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/team_chat_repository.dart';
import '../design/tokens.dart';
import '../state.dart';
import 'chat_widgets.dart';

/// Opens the team chat, or says plainly that it is not available.
Future<void> openTeamChat(BuildContext context, WidgetRef ref) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final chat = await ref.read(teamChatRepositoryProvider).start();
    await navigator.push(
      MaterialPageRoute(builder: (_) => TeamChatScreen(chat: chat)),
    );
  } on TeamChatUnavailable {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'The team chat is unavailable right now. Please call your clinic.',
        ),
      ),
    );
  }
}

/// The patient's conversation with the clinic team: real people, replying during opening hours. Messages show when
/// they were sent, when the team has them and when the team has read them.
class TeamChatScreen extends StatefulWidget {
  const TeamChatScreen({super.key, required this.chat});
  final TeamChat chat;

  @override
  State<TeamChatScreen> createState() => _TeamChatScreenState();
}

class _TeamChatScreenState extends State<TeamChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _subs = <StreamSubscription<dynamic>>[];
  var _messages = const <TeamMessage>[];
  bool _typing = false;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _subs
      ..add(
        widget.chat.messages.listen((m) {
          if (!mounted) return;
          setState(() => _messages = m);
          _toEnd();
        }),
      )
      ..add(
        widget.chat.teamTyping.listen((t) {
          if (mounted) setState(() => _typing = t);
        }),
      );
    _input.addListener(() {
      if (_input.text.isNotEmpty) widget.chat.typing();
    });
    _open();
  }

  Future<void> _open() async {
    try {
      await widget.chat.open();
      if (mounted) setState(() => _ready = true);
    } on Exception {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _input.dispose();
    _scroll.dispose();
    widget.chat.close();
    super.dispose();
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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || !_ready) return;
    _input.clear();
    try {
      await widget.chat.send(text);
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your message was not sent. Please try again.'),
        ),
      );
      _input.text = text;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
            child: Icon(
              Icons.support_agent_rounded,
              color: Palette.teal,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Northgate team',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _typing ? 'typing…' : 'Replies during opening hours',
                  key: const Key('team-presence'),
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
    ),
    body: Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            children: [
              const _Notice(
                'You are writing to the Northgate team, not to Nora. For an emergency, call 911.',
              ),
              if (_failed)
                const _Notice(
                  'The team chat is unavailable right now. Please call your clinic.',
                )
              else if (!_ready)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(
                    child: CircularProgressIndicator(color: Palette.teal),
                  ),
                ),
              for (final (i, m) in _messages.indexed)
                ChatBubble(
                  key: Key('team-message-${m.id}'),
                  text: m.text,
                  at: m.at,
                  mine: m.mine,
                  first: i == 0 || _messages[i - 1].mine != m.mine,
                  delivery: !m.mine
                      ? null
                      : switch (m.delivery) {
                          TeamDelivery.sending => Delivery.sent,
                          TeamDelivery.delivered => Delivery.delivered,
                          TeamDelivery.read => Delivery.read,
                        },
                ),
              if (_typing) const ChatTyping(who: 'Northgate team'),
            ],
          ),
        ),
        ChatComposer(
          controller: _input,
          onSend: _send,
          label: 'Message to the team',
          hint: 'Message',
          enabled: _ready,
          canSend: _ready,
          fieldKey: const Key('team-input'),
          sendKey: const Key('team-send'),
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4D6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.35,
          color: Palette.deepSea,
        ),
      ),
    ),
  );
}
