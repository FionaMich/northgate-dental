import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/assistant_repository.dart';
import '../data/voice_engine.dart';
import '../design/tokens.dart';
import '../state.dart';
import 'nora_portrait.dart';

/// Talk to Nora: she listens (on the phone), answers through the assistant service and speaks her reply aloud, with
/// captions. Her portrait changes with what she is doing, like a video call: idle and breathing, listening with a
/// pulsing ring, thinking, and speaking.
class VoiceScreen extends ConsumerStatefulWidget {
  const VoiceScreen({super.key, this.language = 'en'});
  final String language;

  @override
  ConsumerState<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends ConsumerState<VoiceScreen> {
  late final String _thread = List.generate(
    24,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();
  late String _language = widget.language;
  NoraMood _mood = NoraMood.idle;
  String _caption = '';
  String _youSaid =
      ''; // the exact words sent to Nora, shown so the patient can check them
  final _captionScroll = ScrollController();
  String _heard = '';
  Map<String, dynamic>? _confirm;
  bool _voiceAvailable = true;
  late final VoiceEngine _voice = ref.read(voiceEngineProvider);

  @override
  void initState() {
    super.initState();
    _greet();
  }

  @override
  void dispose() {
    _voice.stopListening();
    _voice.stopSpeaking();
    _captionScroll.dispose();
    super.dispose();
  }

  /// Speaks [text]; true when Nora finished without being interrupted.
  Future<bool> _say(String text) async {
    if (!mounted) return false;
    setState(() {
      _caption = text;
      _mood = NoraMood.speaking;
    });
    try {
      await _voice.speak(text, _language);
    } finally {
      // Only settle if nothing else (listening after an interruption) has taken over.
      if (mounted && _mood == NoraMood.speaking) {
        setState(() => _mood = NoraMood.idle);
      }
    }
    return mounted && _mood == NoraMood.idle;
  }

  /// Turn-taking: once Nora has finished speaking, listen for the patient's reply without another tap.
  Future<void> _sayThenListen(String text) async {
    if (await _say(text) && _voiceAvailable && _confirm == null) {
      await _listen();
    }
  }

  Future<void> _greet() async {
    try {
      _voiceAvailable = await _voice.canListen(_language);
      await _sayThenListen(
        await ref.read(assistantRepositoryProvider).hello(_language),
      );
    } on Exception {
      if (mounted) {
        setState(
          () => _caption =
              'Nora is unavailable right now. Please call your clinic.',
        );
      }
    }
  }

  Future<void> _run(Future<AssistantTurn> Function() call) async {
    setState(() => _mood = NoraMood.thinking);
    try {
      final turn = await call();
      if (!mounted) return;
      setState(() => _confirm = turn.confirm);
      if (turn.confirm != null) {
        await _say(
          '${turn.confirm!['title']} ${turn.confirm!['detail'] ?? ''}',
        );
      } else if (turn.reply != null) {
        await _sayThenListen(turn.reply!);
      } else {
        setState(() => _mood = NoraMood.idle);
      }
    } on AssistantError catch (e) {
      _fail(e.message);
    } on Exception {
      _fail('Something went wrong. Please try again.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _caption = message;
      _mood = NoraMood.idle;
    });
  }

  Future<void> _listen() async {
    final voice = _voice;
    unawaited(voice.stopSpeaking()); // some phone voices never complete stop(); the patient must not wait for it
    setState(() {
      _mood = NoraMood.listening;
      _heard = '';
    });
    final String words;
    try {
      words = await voice.listen(
        _language,
        (w) => mounted ? setState(() => _heard = w) : null,
      );
    } on VoiceUnavailable {
      if (mounted) {
        setState(() {
          _voiceAvailable = false;
          _mood = NoraMood.idle;
        });
      }
      return;
    }
    if (!mounted) return;
    if (words.trim().isEmpty) {
      setState(() => _mood = NoraMood.idle);
      return;
    }
    setState(() => _youSaid = words.trim());
    await _run(
      () =>
          ref.read(assistantRepositoryProvider).send(_thread, words, _language),
    );
  }

  void _answer(bool accept) {
    setState(() => _confirm = null);
    _run(
      () => ref
          .read(assistantRepositoryProvider)
          .confirm(_thread, accept, _language),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.heroBottom,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: heroGradient),
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  const BackButton(color: Colors.white),
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
                  TextButton(
                    key: const Key('voice-language'),
                    onPressed: () async {
                      final picked = await showModalBottomSheet<String>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final MapEntry(:key, :value)
                                  in assistantLanguages.entries)
                                ListTile(
                                  title: Text(value),
                                  onTap: () => Navigator.of(context).pop(key),
                                ),
                            ],
                          ),
                        ),
                      );
                      if (picked != null && picked != _language) {
                        setState(() => _language = picked);
                        _greet();
                      }
                    },
                    child: Text(
                      assistantLanguages[_language]!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              // The portrait shrinks on short screens so captions and buttons never overflow.
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: FittedBox(child: NoraPortrait(mood: _mood)),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      switch (_mood) {
                        NoraMood.listening => 'Listening…',
                        NoraMood.thinking =>
                          'Nora is thinking… one moment',
                        NoraMood.speaking => 'Nora is speaking',
                        NoraMood.idle =>
                          _voiceAvailable ? 'Tap the microphone and speak' : 'Voice is not available on this phone in this language',
                      },
                      key: const Key('voice-status'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFA9DCD1),
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (_youSaid.isNotEmpty && _mood != NoraMood.listening)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                  child: Text(
                    'You said: “$_youSaid”',
                    key: const Key('voice-you-said'),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                // One scroll view; only the words fade, so the scrollbar has a single position to follow.
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  // Long answers used to be cut at 180 px with no sign of more; the portrait above shrinks to make room.
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.3,
                  ),
                  child: Scrollbar(
                    controller: _captionScroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _captionScroll,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: KeyedSubtree(
                          key: ValueKey(
                            _mood == NoraMood.listening ? _heard : _caption,
                          ),
                          child: Text(
                            _mood == NoraMood.listening
                                ? (_heard.isEmpty ? '…' : _heard)
                                : _caption,
                            key: const Key('voice-caption'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              height: 1.45,
                              fontStyle: _mood == NoraMood.listening
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
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
                          key: const Key('voice-no'),
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
                          key: const Key('voice-yes'),
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
              Semantics(
                button: true,
                enabled: _voiceAvailable,
                label: _mood == NoraMood.listening
                    ? 'Stop listening'
                    : 'Speak to Nora',
                child: GestureDetector(
                  key: const Key('voice-mic'),
                  onTap:
                      !_voiceAvailable ||
                          _mood == NoraMood.thinking ||
                          _confirm != null
                      ? null
                      : (_mood == NoraMood.listening
                            ? () => _voice.stopListening()
                            : _listen),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: !_voiceAvailable
                          ? Colors.white.withValues(alpha: 0.12)
                          : (_mood == NoraMood.listening
                                ? Palette.error
                                : Palette.shine),
                      boxShadow: _voiceAvailable
                          ? [
                              BoxShadow(
                                color: Palette.shine.withValues(alpha: 0.45),
                                blurRadius: 24,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      !_voiceAvailable
                          ? Icons.mic_off_rounded
                          : (_mood == NoraMood.listening
                                ? Icons.stop_rounded
                                : Icons.mic_rounded),
                      size: 38,
                      color: _voiceAvailable ? Palette.deepSea : Colors.white54,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}
