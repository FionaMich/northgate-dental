import 'package:dental/data/assistant_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nora's replies can take minutes; the token must outlive the turn.
void main() {
  final now = DateTime(2026, 11, 26, 15, 47);
  int at(Duration d) => now.add(d).millisecondsSinceEpoch ~/ 1000;

  test('a token with less than 5 minutes left is refreshed before talking to Nora', () {
    expect(needsRefresh(at(const Duration(minutes: 3)), now), isTrue);
    expect(needsRefresh(at(const Duration(seconds: -10)), now), isTrue, reason: 'already expired');
  });

  test('a fresh token is used as it is, and no session means nothing to refresh', () {
    expect(needsRefresh(at(const Duration(minutes: 50)), now), isFalse);
    expect(needsRefresh(null, now), isFalse);
  });
}
