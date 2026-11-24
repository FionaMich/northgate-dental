import 'package:dental/data/care_repository.dart' show clinicTime;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'visit times are in the clinic\'s time, whatever zone the phone is in',
    () {
      // Seen on a phone in Nairobi: a 10:00 Boston cleaning showed as 18:00.
      expect(
        clinicTime('2026-11-25T15:00:00Z').hour,
        10,
        reason: 'Boston in winter is UTC-5',
      );
      expect(
        clinicTime('2026-07-01T14:00:00Z').hour,
        10,
        reason: 'and UTC-4 in summer',
      );
    },
  );
}
