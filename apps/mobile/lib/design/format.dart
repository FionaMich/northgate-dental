import '../data/care_repository.dart';
import '../l10n/l10n.dart';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String weekday(DateTime d) => tr(_days[d.weekday - 1]);
String shortMonth(DateTime d) =>
    String.fromCharCodes(tr(_months[d.month - 1]).runes.take(3));
String dayMonth(DateTime d) => '${d.day} ${tr(_months[d.month - 1])}';
String dayMonthYear(DateTime d) => '${dayMonth(d)} ${d.year}';
String monthYear(DateTime d) => '${tr(_months[d.month - 1])} ${d.year}';
String clock(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String visitTitle(String kind) => switch (kind) {
  'exam' => 'Exam',
  'hygiene' => 'Hygiene visit',
  'treatment' => 'Treatment',
  'emergency' => 'Emergency visit',
  'consultation' => 'Consultation',
  _ => 'Visit',
};

String procedureLabel(Procedure p) => p.tooth == null
    ? p.service
    : trf('{} · tooth {}{}', [
        tr(p.service),
        p.tooth,
        p.surface == null ? '' : ', ${surfaceLabel(p.surface!)}',
      ]);

/// Whole cents as US dollars: 21000 becomes \$210.00.
String dollars(int cents) {
  final whole = (cents ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '\$$whole.${(cents % 100).toString().padLeft(2, '0')}';
}

/// Tooth surfaces in plain words (M, O, D, B, L, F, I).
String surfaceLabel(String surface) {
  const words = {
    'M': 'front side',
    'O': 'top surface',
    'D': 'back side',
    'B': 'cheek side',
    'L': 'tongue side',
    'F': 'lip side',
    'I': 'biting edge',
  };
  return surface.split('').map((c) => tr(words[c] ?? c)).join(' ${tr('and')} ');
}

/// What the dentist noted on a tooth, in plain words.
String conditionLabel(String condition) => switch (condition) {
  'caries' => 'Decay',
  'filled' => 'Filling',
  'crown' => 'Crown',
  'missing' => 'Missing tooth',
  'implant' => 'Implant',
  'root_canal' => 'Root canal treated',
  'fractured' => 'Cracked',
  'sealant' => 'Sealant',
  _ => condition,
};
