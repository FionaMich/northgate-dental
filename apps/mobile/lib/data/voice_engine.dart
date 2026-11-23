import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// The phone's own speech recogniser and voice, behind one small interface (tests use a fake).
///
/// Privacy: recognition is requested on the device. If the phone cannot recognise a language on the device, the voice
/// screen says so and offers typing, rather than sending the patient's voice to a cloud recogniser.
abstract class VoiceEngine {
  /// Whether listening works on this phone for [language], on the device.
  Future<bool> canListen(String language);

  /// Listens until the patient stops; [onWords] gets the words so far; completes with the final sentence.
  Future<String> listen(String language, void Function(String words) onWords);

  Future<void> stopListening();

  /// Speaks [text] in [language]; completes when the voice has finished.
  Future<void> speak(String text, String language);

  Future<void> stopSpeaking();
}

/// The locale each assistant language is spoken and recognised in.
const voiceLocales = {
  'en': 'en-US',
  'fr': 'fr-FR',
  'nl': 'nl-NL',
  'de': 'de-DE',
  'es': 'es-ES',
  'it': 'it-IT',
  'lt': 'lt-LT',
  'sv': 'sv-SE',
};

class DeviceVoiceEngine implements VoiceEngine {
  final _speech = SpeechToText();
  final _tts = FlutterTts();
  bool _ready = false;

  Future<bool> _init() async => _ready = _ready || await _speech.initialize();

  @override
  Future<bool> canListen(String language) async {
    if (!await _init()) return false;
    final wanted = voiceLocales[language]!.replaceAll('-', '_').toLowerCase();
    final locales = await _speech.locales();
    return locales.any((l) => l.localeId.toLowerCase() == wanted || l.localeId.toLowerCase().startsWith(wanted.split('_').first));
  }

  @override
  Future<String> listen(String language, void Function(String words) onWords) async {
    final done = Completer<String>();
    var last = '';
    _speech.statusListener = (status) {
      if ((status == 'done' || status == 'notListening') && !done.isCompleted) done.complete(last);
    };
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: voiceLocales[language]!.replaceAll('-', '_'),
        onDevice: true, // the patient's voice stays on the phone
        partialResults: true,
        cancelOnError: true,
        pauseFor: const Duration(seconds: 2),
        listenFor: const Duration(seconds: 30),
      ),
      onResult: (SpeechRecognitionResult r) {
        last = r.recognizedWords;
        onWords(last);
        if (r.finalResult && !done.isCompleted) done.complete(last);
      },
    );
    return done.future;
  }

  @override
  Future<void> stopListening() => _speech.stop();

  @override
  Future<void> speak(String text, String language) async {
    await _tts.setLanguage(voiceLocales[language]!);
    await _tts.setSpeechRate(0.48); // a calm receptionist pace
    await _tts.awaitSpeakCompletion(true);
    await _tts.speak(text);
  }

  @override
  Future<void> stopSpeaking() => _tts.stop();
}
