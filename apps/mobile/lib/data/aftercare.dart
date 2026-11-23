import 'care_repository.dart';

/// Care after a treatment, in plain words, grouped by when it applies. No medicine doses: the app never gives
/// medicine advice (AGENTS.md section 9); it points to what the dentist advised and to the clinic or 911.
/// Content needs a dentist's review before real patients use it.
class AftercareSheet {
  const AftercareSheet({
    required this.title,
    required this.rightNow,
    required this.today,
    required this.thisWeek,
  });
  final String title;
  final List<String> rightNow, today, thisWeek;

  static const callUs =
      'Call the clinic if bleeding does not stop with pressure, swelling spreads, or you have a fever. '
      'In an emergency, call 911.';
}

const _sheets = <String, AftercareSheet>{
  'extraction': AftercareSheet(
    title: 'After your extraction',
    rightNow: [
      'Bite gently on the gauze for 30 to 45 minutes.',
      'Do not rinse, spit or touch the area.',
    ],
    today: [
      'Eat soft, cool food on the other side.',
      'No straws, smoking or hot drinks for 24 hours.',
      'Rest with your head raised.',
    ],
    thisWeek: [
      'From tomorrow, rinse gently with warm salt water after meals.',
      'Brush carefully around the area.',
    ],
  ),
  'implant': AftercareSheet(
    title: 'After your implant',
    rightNow: [
      'Bite gently on the gauze for 30 to 45 minutes.',
      'Hold a cold pack to your cheek, 10 minutes on and 10 off.',
    ],
    today: [
      'Soft, cool food only.',
      'No smoking, straws or hot drinks.',
      'Take pain relief only as your dentist advised.',
    ],
    thisWeek: [
      'Rinse gently with warm salt water after meals.',
      'Avoid chewing on the implant side.',
      'Come to your check on the date given.',
    ],
  ),
  'root canal': AftercareSheet(
    title: 'After your root canal treatment',
    rightNow: ['Wait until the numbness wears off before eating.'],
    today: [
      'The tooth may feel tender; take pain relief only as your dentist advised.',
      'Chew on the other side.',
    ],
    thisWeek: [
      'Avoid hard food on this tooth until it has its crown.',
      'Book the crown if your dentist planned one.',
    ],
  ),
  'filling': AftercareSheet(
    title: 'After your filling',
    rightNow: [
      'Wait until the numbness wears off (2 to 3 hours) before eating or hot drinks.',
    ],
    today: ['Some sensitivity to cold is normal.'],
    thisWeek: [
      'If your bite feels high or the sensitivity grows, let us know and we will adjust it.',
    ],
  ),
  'whitening': AftercareSheet(
    title: 'After whitening',
    rightNow: ['Some sensitivity is normal and fades within a day or two.'],
    today: ['Avoid coffee, tea, red wine, curry and smoking for 48 hours.'],
    thisWeek: ['Use a toothpaste for sensitive teeth if you need to.'],
  ),
  'cleaning': AftercareSheet(
    title: 'After your cleaning',
    rightNow: ['Your gums may feel a little tender.'],
    today: ['Brush gently twice a day and clean between your teeth.'],
    thisWeek: [
      'Keep it up: gums that bleed less each day are getting healthier.',
    ],
  ),
};

/// The sheet for a visit's completed treatment, most involved first (an extraction matters more than a cleaning).
AftercareSheet? aftercareFor(Visit v) {
  final done = v.procedures
      .where((p) => p.done)
      .map((p) => p.service.toLowerCase())
      .toList();
  for (final key in _sheets.keys) {
    if (done.any((s) => s.contains(key))) return _sheets[key];
  }
  return null;
}

/// Which groups are over: right now ends after 3 hours, today after 24 hours, this week after 7 days.
({bool rightNow, bool today, bool thisWeek}) aftercareDone(
  DateTime visit,
  DateTime now,
) {
  final since = now.difference(visit);
  return (
    rightNow: since > const Duration(hours: 3),
    today: since > const Duration(hours: 24),
    thisWeek: since > const Duration(days: 7),
  );
}
