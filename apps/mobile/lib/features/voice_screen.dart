import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/assistant_repository.dart';
import '../data/voice_engine.dart';
import '../design/tokens.dart';
import '../state.dart';

/// Talk to Nora: she listens (on the phone), answers through the assistant service and speaks her reply aloud, with
/// captions. Her portrait changes with what she is doing, like a video call: idle and breathing, listening with a
/// pulsing ring, thinking, and speaking.
class VoiceScreen extends ConsumerStatefulWidget {
  const VoiceScreen({super.key, this.language = 'en'});
  final String language;

  @override
  ConsumerState<VoiceScreen> createState() => _VoiceScreenState();
}

enum NoraMood { idle, listening, thinking, speaking }

class _VoiceScreenState extends ConsumerState<VoiceScreen> with TickerProviderStateMixin {
  late final _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final String _thread = List.generate(24, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
  late String _language = widget.language;
  NoraMood _mood = NoraMood.idle;
  String _caption = '';
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce motion on the phone: Nora stays still; the status line still says what she is doing.
    if (MediaQuery.disableAnimationsOf(context)) {
      _breath.stop();
      _pulse.stop();
    } else {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
      if (!_pulse.isAnimating) _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _voice.stopListening();
    _voice.stopSpeaking();
    _breath.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _say(String text) async {
    if (!mounted) return;
    setState(() {
      _caption = text;
      _mood = NoraMood.speaking;
    });
    try {
      await _voice.speak(text, _language);
    } finally {
      if (mounted) setState(() => _mood = NoraMood.idle);
    }
  }

  Future<void> _greet() async {
    try {
      _voiceAvailable = await _voice.canListen(_language);
      await _say(await ref.read(assistantRepositoryProvider).hello(_language));
    } on Exception {
      if (mounted) setState(() => _caption = 'Nora is unavailable right now. Please call your clinic.');
    }
  }

  Future<void> _run(Future<AssistantTurn> Function() call) async {
    setState(() => _mood = NoraMood.thinking);
    try {
      final turn = await call();
      if (!mounted) return;
      setState(() => _confirm = turn.confirm);
      if (turn.confirm != null) {
        await _say('${turn.confirm!['title']} ${turn.confirm!['detail'] ?? ''}');
      } else if (turn.reply != null) {
        await _say(turn.reply!);
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
    await voice.stopSpeaking();
    setState(() {
      _mood = NoraMood.listening;
      _heard = '';
    });
    final words = await voice.listen(_language, (w) => mounted ? setState(() => _heard = w) : null);
    if (!mounted) return;
    if (words.trim().isEmpty) {
      setState(() => _mood = NoraMood.idle);
      return;
    }
    await _run(() => ref.read(assistantRepositoryProvider).send(_thread, words, _language));
  }

  void _answer(bool accept) {
    setState(() => _confirm = null);
    _run(() => ref.read(assistantRepositoryProvider).confirm(_thread, accept, _language));
  }

  @override
  Widget build(BuildContext context) {
    final pose = switch (_mood) {
      NoraMood.listening => 'listening',
      NoraMood.speaking => 'speaking',
      _ => 'idle',
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
                  const BackButton(color: Colors.white),
                  const Expanded(
                    child: Text(
                      'Nora',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
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
                              for (final MapEntry(:key, :value) in assistantLanguages.entries)
                                ListTile(title: Text(value), onTap: () => Navigator.of(context).pop(key)),
                            ],
                          ),
                        ),
                      );
                      if (picked != null && picked != _language) {
                        setState(() => _language = picked);
                        _greet();
                      }
                    },
                    child: Text(assistantLanguages[_language]!, style: const TextStyle(color: Colors.white)),
                  ),
                ],
              ),
              // The portrait shrinks on short screens so captions and buttons never overflow.
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: FittedBox(
                        child:
                            // Nora's portrait: breathes when idle, pulses a ring while listening, glows while speaking.
                            AnimatedBuilder(
                              animation: Listenable.merge([_breath, _pulse]),
                              builder: (_, _) {
                                final breathe = 1 + 0.018 * Curves.easeInOut.transform(_breath.value);
                                return SizedBox(
                                  width: 300,
                                  height: 300,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      if (_mood == NoraMood.listening)
                                        for (final offset in [0.0, 0.5])
                                          Opacity(
                                            opacity: (1 - ((_pulse.value + offset) % 1)).clamp(0, 1) * 0.5,
                                            child: Container(
                                              width: 220 + 80 * ((_pulse.value + offset) % 1),
                                              height: 220 + 80 * ((_pulse.value + offset) % 1),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(color: Palette.shine, width: 3),
                                              ),
                                            ),
                                          ),
                                      Transform.scale(
                                        scale: _mood == NoraMood.speaking ? breathe * 1.02 : breathe,
                                        child: Container(
                                          width: 220,
                                          height: 220,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: const Color(0xFFDDF4EC),
                                            border: Border.all(color: Colors.white, width: 5),
                                            boxShadow: [
                                              BoxShadow(
                                                color: (_mood == NoraMood.speaking ? Palette.shine : Colors.black)
                                                    .withValues(alpha: _mood == NoraMood.speaking ? 0.55 : 0.25),
                                                blurRadius: _mood == NoraMood.speaking ? 40 : 24,
                                                spreadRadius: _mood == NoraMood.speaking ? 4 : 0,
                                              ),
                                            ],
                                          ),
                                          child: ClipOval(
                                            child: AnimatedSwitcher(
                                              duration: const Duration(milliseconds: 220),
                                              child: Image.asset(
                                                'assets/images/nora/$pose.png',
                                                key: ValueKey(pose),
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      switch (_mood) {
                        NoraMood.listening => 'Listening…',
                        NoraMood.thinking => 'Nora is thinking… this can take up to a minute',
                        NoraMood.speaking => 'Nora is speaking',
                        NoraMood.idle =>
                          _voiceAvailable
                              ? 'Tap the microphone and speak'
                              : 'Voice is not available on this phone in this language',
                      },
                      key: const Key('voice-status'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFA9DCD1), fontSize: 13.5),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    key: ValueKey(_mood == NoraMood.listening ? _heard : _caption),
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: SingleChildScrollView(
                      child: Text(
                        _mood == NoraMood.listening ? (_heard.isEmpty ? '…' : _heard) : _caption,
                        key: const Key('voice-caption'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          height: 1.45,
                          fontStyle: _mood == NoraMood.listening ? FontStyle.italic : FontStyle.normal,
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
                label: _mood == NoraMood.listening ? 'Stop listening' : 'Speak to Nora',
                child: GestureDetector(
                  key: const Key('voice-mic'),
                  onTap: !_voiceAvailable || _mood == NoraMood.thinking || _confirm != null
                      ? null
                      : (_mood == NoraMood.listening ? () => _voice.stopListening() : _listen),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _mood == NoraMood.listening ? Palette.error : Palette.shine,
                      boxShadow: [BoxShadow(color: Palette.shine.withValues(alpha: 0.45), blurRadius: 24)],
                    ),
                    child: Icon(
                      _mood == NoraMood.listening ? Icons.stop_rounded : Icons.mic_rounded,
                      size: 38,
                      color: Palette.deepSea,
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
