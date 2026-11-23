import 'package:dental/data/aligner_reminders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 21, 12);

  test('a visit gets an evening-before and a morning-of reminder, with no treatment named', () {
    final r = visitReminderTimes(DateTime(2026, 11, 27, 9, 30), now);
    expect(r, [
      (DateTime(2026, 11, 26, 18), 'Dental visit tomorrow at 09:30'),
      (DateTime(2026, 11, 27, 8), 'Dental visit today at 09:30'),
    ]);
  });

  test('an early visit is reminded two hours before instead of at 8am', () {
    final r = visitReminderTimes(DateTime(2026, 11, 27, 8, 30), now);
    expect(r.last.$1, DateTime(2026, 11, 27, 6, 30));
  });

  test('reminders already in the past are skipped', () {
    final r = visitReminderTimes(
      DateTime(2026, 11, 22, 10),
      DateTime(2026, 11, 21, 19),
    );
    expect(r, [(DateTime(2026, 11, 22, 8), 'Dental visit today at 10:00')]);
  });
}
