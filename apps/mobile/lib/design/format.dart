import '../data/care_repository.dart';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String weekday(DateTime d) => _days[d.weekday - 1];
String shortMonth(DateTime d) => _months[d.month - 1].substring(0, 3);
String dayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';
String dayMonthYear(DateTime d) => '${dayMonth(d)} ${d.year}';
String clock(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String visitTitle(String kind) => switch (kind) {
  'exam' => 'Exam',
  'hygiene' => 'Hygiene visit',
  'treatment' => 'Treatment',
  'emergency' => 'Emergency visit',
  'consultation' => 'Consultation',
  _ => 'Visit',
};

String procedureLabel(Procedure p) => p.tooth == null ? p.service : '${p.service} · tooth ${p.tooth}';
