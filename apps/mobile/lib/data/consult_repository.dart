import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'assistant_repository.dart' show assistantBase;

/// A video consultation with the clinic team through Stream (ADR 0015). Our server checks the session and signs a
/// one-hour token for the patient's own room; Stream records and transcribes nothing on this call type.

class ConsultUnavailable implements Exception {
  const ConsultUnavailable();
}

abstract class ConsultRepository {
  /// The ticket for one booked video consultation's room: api_key, token, user_id, call_type, call_id.
  Future<Map<String, dynamic>> ticket(String appointmentId);
}

class HttpConsultRepository implements ConsultRepository {
  HttpConsultRepository(this._auth);
  final GoTrueClient _auth;

  @override
  Future<Map<String, dynamic>> ticket(String appointmentId) async {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await http.postUrl(
        Uri.parse('$assistantBase/assistant/consult'),
      );
      final token = _auth.currentSession?.accessToken;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'appointment_id': appointmentId}));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) throw const ConsultUnavailable();
      return jsonDecode(text) as Map<String, dynamic>;
    } on IOException {
      throw const ConsultUnavailable();
    } on TimeoutException {
      throw const ConsultUnavailable();
    } finally {
      http.close();
    }
  }
}
