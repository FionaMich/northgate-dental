import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// The languages the receptionist speaks: code, and the name in that language (shown in the picker).
const assistantLanguages = {
  'en': 'English',
  'es': 'Español',
  'pt': 'Português',
  'ht': 'Kreyòl ayisyen',
  'zh-Hans': '简体中文',
  'zh-Hant': '繁體中文',
  'vi': 'Tiếng Việt',
  'ar': 'العربية',
  'fr': 'Français',
  'ru': 'Русский',
  'ko': '한국어',
  'tl': 'Tagalog',
};

/// What the assistant said, or a booking or cancellation waiting for the patient's button.
class AssistantTurn {
  const AssistantTurn({this.reply, this.confirm});
  final String? reply;
  final Map<String, dynamic>? confirm;
}

class AssistantError implements Exception {
  const AssistantError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Where the assistant service lives (behind the WAF on the VM); a build can point elsewhere.
const assistantBase = String.fromEnvironment('ASSISTANT_BASE', defaultValue: 'https://84-12-126-31.sslip.io');

abstract class AssistantRepository {
  Future<String> hello(String language);
  Future<AssistantTurn> send(String thread, String message, String language);
  Future<AssistantTurn> confirm(String thread, bool accept, String language);
}

/// Talks to the assistant service with the patient's own Supabase token; the service checks it with Supabase.
class HttpAssistantRepository implements AssistantRepository {
  HttpAssistantRepository(this._auth);
  final GoTrueClient _auth;
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  Future<Map<String, dynamic>> _call(String method, String path, String language, [Map<String, dynamic>? body]) async {
    final request = await _http.openUrl(method, Uri.parse('$assistantBase$path'));
    final token = _auth.currentSession?.accessToken;
    if (token != null) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.set('X-Language', language);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    // The model runs on a CPU server: allow a long reply rather than give up on a patient mid-sentence.
    final response = await request.close().timeout(const Duration(seconds: 150));
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw AssistantError(response.statusCode == 401 ? 'Please sign in again.' : 'The receptionist is unavailable right now. Please try again or call your clinic.');
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }

  AssistantTurn _turn(Map<String, dynamic> j) => AssistantTurn(reply: j['reply'] as String?, confirm: j['confirm'] as Map<String, dynamic>?);

  @override
  Future<String> hello(String language) async => (await _call('GET', '/assistant/hello?language=$language', language))['reply'] as String;

  @override
  Future<AssistantTurn> send(String thread, String message, String language) async =>
      _turn(await _call('POST', '/assistant/chat', language, {'thread': thread, 'message': message}));

  @override
  Future<AssistantTurn> confirm(String thread, bool accept, String language) async =>
      _turn(await _call('POST', '/assistant/confirm', language, {'thread': thread, 'accept': accept}));
}
