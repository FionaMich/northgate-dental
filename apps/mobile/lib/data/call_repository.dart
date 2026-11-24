import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:stream_video_flutter/stream_video_flutter.dart' as sv;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'assistant_repository.dart' show assistantBase;

/// A voice call with Nora (ADR 0015). The phone joins a Stream call; Nora joins from our server, listens, thinks and
/// speaks there. The phone shows what she heard and said (captions) and the Confirm buttons, which stay the only way
/// to book or cancel. Nothing is recorded.
abstract class CallRepository {
  /// Starts a call; throws [CallsUnavailable] when the server offers no calls (the on-device voice screen is the fallback).
  Future<NoraCall> start(String language);
}

class CallsUnavailable implements Exception {
  const CallsUnavailable();
}

/// What the phone hears from a call: Nora's words, her state, a card to confirm, the end.
sealed class NoraCallEvent {
  const NoraCallEvent();
}

class NoraJoined extends NoraCallEvent {
  const NoraJoined();
}

/// Nora heard the patient ([who] == 'you') or said something herself ([who] == 'nora').
class NoraCaption extends NoraCallEvent {
  const NoraCaption(this.who, this.text);
  final String who;
  final String text;
}

/// listening, thinking or speaking.
class NoraMoodEvent extends NoraCallEvent {
  const NoraMoodEvent(this.mood);
  final String mood;
}

class NoraConfirm extends NoraCallEvent {
  const NoraConfirm(this.card);
  final Map<String, dynamic> card;
}

class NoraEnded extends NoraCallEvent {
  const NoraEnded(this.reason);
  final String reason;
}

abstract class NoraCall {
  Stream<NoraCallEvent> get events;
  Future<void> join();
  Future<void> setMuted(bool muted);

  /// The patient's answer to a confirm card; the only write path in a call.
  Future<void> answer(bool accept);
  Future<void> leave();
}

/// Asks our server for a call ticket (it checks the session and signs the token), then joins through the Stream SDK.
class StreamCallRepository implements CallRepository {
  StreamCallRepository(this._auth);
  final GoTrueClient _auth;

  /// The patient's Confirm or Not now for a call: a write, so it goes to our server with the verified session.
  Future<void> _confirm(String callId, bool accept) async {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await http.postUrl(
        Uri.parse('$assistantBase/assistant/call/$callId/confirm'),
      );
      final token = _auth.currentSession?.accessToken;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'thread': 'call-$callId', 'accept': accept}));
      final response = await request.close().timeout(
        const Duration(seconds: 150),
      );
      await response.drain<void>();
    } finally {
      http.close();
    }
  }

  @override
  Future<NoraCall> start(String language) async {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await http.postUrl(
        Uri.parse('$assistantBase/assistant/call'),
      );
      final token = _auth.currentSession?.accessToken;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.headers.set('X-Language', language);
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw const CallsUnavailable(); // 503 when the server has no call service; anything else is the same to the patient
      }
      return _StreamNoraCall(
        jsonDecode(text) as Map<String, dynamic>,
        _confirm,
      );
    } on IOException {
      throw const CallsUnavailable();
    } finally {
      http.close();
    }
  }
}

class _StreamNoraCall implements NoraCall {
  _StreamNoraCall(this._ticket, this._confirm);
  final Map<String, dynamic> _ticket;
  final Future<void> Function(String callId, bool accept) _confirm;
  final _events = StreamController<NoraCallEvent>.broadcast();
  sv.StreamVideo? _client;
  sv.Call? _call;
  final _subs = <StreamSubscription<dynamic>>[];
  bool _left =
      false; // leave() can arrive while join() is still waiting on the server

  @override
  Stream<NoraCallEvent> get events => _events.stream;

  @override
  Future<void> join() async {
    // The display name is fixed: Stream never learns the patient's name (ADR 0015).
    final client = _client = sv.StreamVideo(
      _ticket['api_key'] as String,
      user: sv.User.regular(
        userId: _ticket['user_id'] as String,
        name: 'Patient',
      ),
      userToken: _ticket['token'] as String,
      failIfSingletonExists: false,
    );
    final call = _call = client.makeCall(
      callType: sv.StreamCallType.custom(_ticket['call_type'] as String),
      id: _ticket['call_id'] as String,
    );
    _subs.add(call.callEvents.on<sv.StreamCallCustomEvent>(_onCustom));
    _subs.add(
      call.callEvents.on<sv.StreamCallParticipantJoinedEvent>((e) {
        if (e.participant.userId == 'nora') {
          _events.add(const NoraJoined());
        }
      }),
    );
    _subs.add(
      call.callEvents.on<sv.StreamCallParticipantLeftEvent>((e) {
        if (e.participant.userId == 'nora') {
          _events.add(const NoraEnded('nora-left'));
        }
      }),
    );
    _subs.add(
      call.callEvents.on<sv.StreamCallEndedEvent>(
        (_) => _events.add(const NoraEnded('ended')),
      ),
    );
    // Connect first, so the create and join never race the client's background connection.
    final connected = await client.connect();
    if (_left) return;
    if (connected.isFailure) {
      debugPrint('nora-call: connect failed: ${connected.getErrorOrNull()}');
      throw const CallsUnavailable();
    }
    final created = await call.getOrCreate();
    if (_left) return;
    if (created.isFailure) {
      debugPrint('nora-call: create failed: ${created.getErrorOrNull()}');
      throw const CallsUnavailable();
    }
    final joined = await call.join();
    if (_left) return;
    if (joined.isFailure) {
      debugPrint('nora-call: join failed: ${joined.getErrorOrNull()}');
      throw const CallsUnavailable();
    }
    if (call.state.value.otherParticipants.any((p) => p.userId == 'nora')) {
      _events.add(const NoraJoined());
    }
  }

  void _onCustom(sv.StreamCallCustomEvent e) {
    if (e.senderUserId != 'nora') return; // only Nora's events drive the screen
    final data = e.custom ?? const {};
    switch (data['kind']) {
      case 'caption':
        _events.add(
          NoraCaption(
            data['who'] as String? ?? 'nora',
            data['text'] as String? ?? '',
          ),
        );
      case 'mood':
        _events.add(NoraMoodEvent(data['mood'] as String? ?? 'idle'));
      case 'confirm':
        _events.add(
          NoraConfirm(
            Map<String, dynamic>.from(data['card'] as Map? ?? const {}),
          ),
        );
    }
  }

  @override
  Future<void> setMuted(bool muted) async {
    await _call?.setMicrophoneEnabled(enabled: !muted);
  }

  @override
  Future<void> answer(bool accept) =>
      _confirm(_ticket['call_id'] as String, accept);

  @override
  Future<void> leave() async {
    if (_left) return;
    _left = true;
    for (final s in _subs) {
      await s.cancel();
    }
    // Best effort: a failed leave must never trap the patient on the screen; the token dies within the hour anyway.
    try {
      await _call?.leave();
    } on Exception {
      // ignored
    }
    try {
      await _client?.dispose();
    } on Exception {
      // ignored
    }
    await _events.close();
  }
}
