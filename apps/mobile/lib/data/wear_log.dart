import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Aligner wear sessions for one person: start, and end (null while the aligners are in).
class WearLog {
  const WearLog(this.sessions);
  final List<(DateTime, DateTime?)> sessions;

  static const goal = Duration(hours: 22);

  bool get wearing => sessions.isNotEmpty && sessions.last.$2 == null;

  /// Time worn on [day] (local midnight to midnight), counting a running session up to [now].
  Duration wornOn(DateTime day, {required DateTime now}) {
    final from = DateTime(day.year, day.month, day.day);
    final to = DateTime(day.year, day.month, day.day + 1);
    var total = Duration.zero;
    for (final (start, end) in sessions) {
      final s = start.isAfter(from) ? start : from;
      final e = [end ?? now, to, now].reduce((a, b) => a.isBefore(b) ? a : b);
      if (e.isAfter(s)) total += e.difference(s);
    }
    return total;
  }

  WearLog start(DateTime at) =>
      wearing ? this : WearLog([...sessions, (at, null)]);

  /// Ends the running session and drops sessions older than two weeks (only the last 7 days are shown).
  WearLog stop(DateTime at) {
    if (!wearing) return this;
    final cutoff = at.subtract(const Duration(days: 14));
    return WearLog([
      for (final s in sessions.take(sessions.length - 1))
        if (s.$2 != null && s.$2!.isAfter(cutoff)) s,
      (sessions.last.$1, at),
    ]);
  }

  String encode() => jsonEncode([
    for (final (s, e) in sessions) [s.toIso8601String(), e?.toIso8601String()],
  ]);

  static WearLog decode(String? raw) => raw == null
      ? const WearLog([])
      : WearLog([
          for (final r in jsonDecode(raw) as List)
            (
              DateTime.parse(r[0] as String),
              r[1] == null ? null : DateTime.parse(r[1] as String),
            ),
        ]);
}

/// Where wear logs live: only on this phone, encrypted, and wiped on sign-out.
abstract class WearStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> clearAll();
}

/// The phone's encrypted store (Android Keystore, iOS Keychain).
class SecureWearStore implements WearStore {
  static const _prefix = 'aligner:';
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> clearAll() async {
    for (final key in (await _storage.readAll()).keys.where(
      (k) => k.startsWith(_prefix),
    )) {
      await _storage.delete(key: key);
    }
  }
}
