import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stream_chat/stream_chat.dart' as sc;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'assistant_repository.dart' show assistantBase;

/// The patient's conversation with the clinic team, carried by Stream Chat (ADR 0018). Our server checks the session,
/// makes the patient's own channel and signs the token; the phone then talks to Stream directly.

class TeamChatUnavailable implements Exception {
  const TeamChatUnavailable();
}

enum TeamDelivery { sending, delivered, read }

class TeamMessage {
  const TeamMessage({
    required this.id,
    required this.text,
    required this.mine,
    required this.at,
    this.delivery = TeamDelivery.delivered,
    this.system = false,
    this.sender,
  });
  final String id;

  /// Written by the system (a request filed, an emergency notice), not by a person.
  final bool system;

  /// The team member's name and role, for their messages.
  final String? sender;
  final String text;
  final bool mine;
  final DateTime at;

  /// For the patient's own messages: on its way, with the team, or seen by the team.
  final TeamDelivery delivery;
}

abstract class TeamChat {
  /// Every message so far, oldest first; a new list each time anything changes.
  Stream<List<TeamMessage>> get messages;
  Stream<bool> get teamTyping;
  Future<void> open();
  Future<void> send(String text);

  /// The patient is writing: the team sees the typing dots.
  void typing();
  Future<void> close();
}

/// Where the patient's conversation with the team stands, for Home.
class TeamStatus {
  const TeamStatus(this.state, this.unread);
  final String state; // none, waiting, unread or open
  final int unread;
}

abstract class TeamChatRepository {
  /// Throws [TeamChatUnavailable] when the server offers no team chat.
  Future<TeamChat> start();
  Future<TeamStatus> status();
}

class StreamTeamChatRepository implements TeamChatRepository {
  StreamTeamChatRepository(this._auth);
  final GoTrueClient _auth;

  Future<HttpClientResponse> _ask(
    String method,
    String path, [
    Object? body,
  ]) async {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final request = await http.openUrl(
      method,
      Uri.parse('$assistantBase$path'),
    );
    final token = _auth.currentSession?.accessToken;
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    return request.close().timeout(const Duration(seconds: 20));
  }

  @override
  Future<TeamStatus> status() async {
    try {
      final response = await _ask('GET', '/assistant/team-chat/status');
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) return const TeamStatus('none', 0);
      final j = jsonDecode(text) as Map<String, dynamic>;
      return TeamStatus(
        j['state'] as String? ?? 'none',
        j['unread'] as int? ?? 0,
      );
    } on Exception {
      return const TeamStatus('none', 0);
    }
  }

  /// The patient's message goes through our server, which checks it for red flags before the team sees it.
  Future<void> _send(String text) async {
    final response = await _ask('POST', '/assistant/team-chat/send', {
      'message': text,
    });
    await response.drain<void>();
    if (response.statusCode != 200) throw const TeamChatUnavailable();
  }

  @override
  Future<TeamChat> start() async {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await http.postUrl(
        Uri.parse('$assistantBase/assistant/team-chat'),
      );
      final token = _auth.currentSession?.accessToken;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) throw const TeamChatUnavailable();
      return _StreamTeamChat(jsonDecode(text) as Map<String, dynamic>, _send);
    } on IOException {
      throw const TeamChatUnavailable();
    } on TimeoutException {
      throw const TeamChatUnavailable();
    } finally {
      http.close();
    }
  }
}

class _StreamTeamChat implements TeamChat {
  _StreamTeamChat(this._ticket, this._sendThroughServer);
  final Map<String, dynamic> _ticket;
  final Future<void> Function(String) _sendThroughServer;
  final _messages = StreamController<List<TeamMessage>>.broadcast();
  final _typing = StreamController<bool>.broadcast();
  final _subs = <StreamSubscription<dynamic>>[];
  sc.StreamChatClient? _client;
  sc.Channel? _channel;

  String get _me => _ticket['user_id'] as String;

  @override
  Stream<List<TeamMessage>> get messages => _messages.stream;
  @override
  Stream<bool> get teamTyping => _typing.stream;

  @override
  Future<void> open() async {
    final client = _client = sc.StreamChatClient(
      _ticket['api_key'] as String,
      logLevel: sc.Level.OFF, // messages are the patient's words: nothing about them goes to the device log
    );
    await client.connectUser(sc.User(id: _me), _ticket['token'] as String);
    final channel = _channel = client.channel(
      'messaging',
      id: _ticket['channel_id'] as String,
    );
    await channel.watch();
    final state = channel.state!;
    _subs
      ..add(state.messagesStream.listen((_) => _emit()))
      ..add(state.readStream.listen((_) => _emit()))
      ..add(
        state.typingEventsStream.listen(
          (who) => _typing.add(who.keys.any((u) => u.id != _me)),
        ),
      );
    _emit();
    unawaited(channel.markRead());
  }

  void _emit() {
    final state = _channel?.state;
    if (state == null || _messages.isClosed) return;
    // The team has read a message when anyone but the patient has read up to it.
    final seen = state.read
        .where((r) => r.user.id != _me)
        .map((r) => r.lastRead)
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    _messages.add([
      for (final m in state.messages)
        if ((m.text ?? '').isNotEmpty && !m.isDeleted)
          TeamMessage(
            id: m.id,
            text: m.text!,
            mine: m.user?.id == _me,
            at: m.createdAt.toLocal(),
            system: m.type == 'system',
            sender: m.user?.id == _me || m.type == 'system'
                ? null
                : (m.user?.name ?? 'Northgate team'),
            delivery: m.state.isOutgoing
                ? TeamDelivery.sending
                : seen != null && !m.createdAt.isAfter(seen)
                ? TeamDelivery.read
                : TeamDelivery.delivered,
          ),
    ]);
    if (state.messages.isNotEmpty && state.messages.last.user?.id != _me) {
      unawaited(_channel!.markRead());
    }
  }

  @override
  Future<void> send(String text) async {
    await _sendThroughServer(text);
  }

  @override
  void typing() => unawaited(_channel?.keyStroke());

  @override
  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _messages.close();
    await _typing.close();
    final client = _client;
    _client = null;
    try {
      await client?.disconnectUser();
      await client?.dispose();
    } on Exception {
      // Best effort: the token dies within the hour anyway.
    }
  }
}
