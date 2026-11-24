import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/call_repository.dart';
import '../design/tokens.dart';
import 'nora_portrait.dart';

/// A voice call with Nora through Stream (ADR 0015). The phone carries the patient's voice to our server, where Nora
/// listens, thinks and speaks; this screen shows her portrait, live captions of both sides, and the Confirm buttons,
/// which remain the only way to book or cancel. If Nora does not pick up, the screen says so.
class NoraCallScreen extends ConsumerStatefulWidget {
  const NoraCallScreen({super.key, required this.call, this.language = 'en'});
  final NoraCall call;
  final String language;

  /// How long the patient waits for Nora to pick up before the fallback is offered.
  static const pickUpTimeout = Duration(seconds: 25);

  @override
  ConsumerState<NoraCallScreen> createState() => _NoraCallScreenState();
}

enum _Phase { connecting, live, noAnswer, ended }

class _NoraCallScreenState extends ConsumerState<NoraCallScreen> {
  _Phase _phase = _Phase.connecting;
  NoraMood _mood = NoraMood.idle;
  String _caption = '';
  String _youSaid = '';
  Map<String, dynamic>? _confirm;
  bool _muted = false;
  String _error = '';
  StreamSubscription<NoraCallEvent>? _sub;
  Timer? _pickUp;
  final _captionScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _sub = widget.call.events.listen(_on);
    _pickUp = Timer(NoraCallScreen.pickUpTimeout, () {
      if (mounted && _phase == _Phase.connecting) {
        setState(() => _phase = _Phase.noAnswer);
      }
    });
    _join();
  }

  Future<void> _join() async {
    try {
      await widget.call.join();
    } on Exception {
      if (mounted) {
        setState(() {
          _phase = _Phase.noAnswer;
          _error = 'The call could not start.';
        });
      }
    }
  }

  void _on(NoraCallEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event) {
        case NoraJoined():
          _phase = _Phase.live;
          _pickUp?.cancel();
        case NoraCaption(:final who, :final text):
          if (who == 'you') {
            _youSaid = text;
          } else {
            _caption = text;
          }
        case NoraMoodEvent(:final mood):
          _mood = NoraMood.values.asNameMap()[mood] ?? NoraMood.idle;
        case NoraConfirm(:final card):
          _confirm = card;
          _caption = '${card['title'] ?? ''} ${card['detail'] ?? ''}'.trim();
          _mood = NoraMood.idle;
        case NoraEnded():
          _phase = _Phase.ended;
          _mood = NoraMood.idle;
      }
    });
  }

  Future<void> _answer(bool accept) async {
    setState(() => _confirm = null);
    await widget.call.answer(accept);
  }

  bool _hangingUp = false;

  Future<void> _hangUp() async {
    if (_hangingUp) return;
    _hangingUp = true;
    _pickUp?.cancel();
    final navigator = Navigator.of(context);
    try {
      await widget.call.leave();
    } finally {
      if (mounted) navigator.pop();
    }
  }

  @override
  void dispose() {
    _pickUp?.cancel();
    _sub?.cancel();
    _captionScroll.dispose();
    // The system back gesture skips _hangUp: the call must still end, or the microphone would stay open.
    if (!_hangingUp) unawaited(widget.call.leave());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = switch (_phase) {
      _Phase.connecting => 'Calling Nora…',
      _Phase.noAnswer =>
        _error.isNotEmpty ? _error : 'Nora cannot take calls right now.',
      _Phase.ended => 'Call ended',
      _Phase.live => switch (_mood) {
        NoraMood.listening => 'Nora is listening',
        NoraMood.thinking => 'Nora is thinking…',
        NoraMood.speaking => 'Nora is speaking',
        NoraMood.idle =>
          _confirm != null
              ? 'Nothing is booked until you confirm'
              : _muted
              ? 'Your microphone is off'
              : 'Just talk, Nora can hear you',
      },
    };
    return Scaffold(
      backgroundColor: Palette.heroBottom,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: heroGradient),
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  BackButton(color: Colors.white, onPressed: _hangUp),
                  const Expanded(
                    child: Text(
                      'Nora',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: Text(
                      'Voice call',
                      style: TextStyle(color: Color(0xFFA9DCD1), fontSize: 13),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: FittedBox(
                        child: NoraPortrait(
                          mood: _phase == _Phase.live ? _mood : NoraMood.idle,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      status,
                      key: const Key('call-status'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFA9DCD1),
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (_youSaid.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                  child: Text(
                    'You said: “$_youSaid”',
                    key: const Key('call-you-said'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFA9DCD1),
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              if (_caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.3,
                    ),
                    child: Scrollbar(
                      controller: _captionScroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _captionScroll,
                        child: Text(
                          _caption,
                          key: const Key('call-caption'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_confirm != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('call-no'),
                          onPressed: () => _answer(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            minimumSize: const Size.fromHeight(50),
                          ),
                          child: Text(_confirm!['no'] as String? ?? 'Not now'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          key: const Key('call-yes'),
                          onPressed: () => _answer(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: Palette.shine,
                            foregroundColor: Palette.deepSea,
                            minimumSize: const Size.fromHeight(50),
                          ),
                          child: Text(_confirm!['yes'] as String? ?? 'Confirm'),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RoundButton(
                    key: const Key('call-mute'),
                    label: _muted ? 'Unmute' : 'Mute',
                    icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    color: Colors.white.withValues(alpha: 0.16),
                    iconColor: Colors.white,
                    enabled: _phase == _Phase.live,
                    onTap: () async {
                      setState(() => _muted = !_muted);
                      await widget.call.setMuted(_muted);
                    },
                  ),
                  const SizedBox(width: 28),
                  _RoundButton(
                    key: const Key('call-end'),
                    label: 'End call',
                    icon: Icons.call_end_rounded,
                    color: Palette.error,
                    iconColor: Colors.white,
                    enabled: true,
                    onTap: _hangUp,
                  ),
                ],
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.enabled,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final Color iconColor;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? color : Colors.white.withValues(alpha: 0.08),
          ),
          child: Icon(
            icon,
            size: 32,
            color: enabled ? iconColor : Colors.white38,
          ),
        ),
      ),
    );
  }
}
