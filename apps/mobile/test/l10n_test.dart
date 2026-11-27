import 'package:dental/l10n/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => appLanguage.value = 'en');

  test(
    'every language translates the same strings and keeps every changing part',
    () {
      final tables = translationTables;
      expect(tables.keys.toSet(), appLanguages.keys.toSet()..remove('en'));
      final keys = tables['fr']!.keys.toSet();
      expect(keys.length, greaterThan(500));
      for (final MapEntry(key: language, value: table) in tables.entries) {
        expect(table.keys.toSet(), keys, reason: language);
        for (final MapEntry(:key, :value) in table.entries) {
          expect(value.trim(), isNotEmpty, reason: '$language: $key');
          expect(
            '{}'.allMatches(value).length,
            '{}'.allMatches(key).length,
            reason: '$language: $key',
          );
        }
      }
    },
  );

  test('English is the source and is never changed', () {
    expect(tr('Book a visit'), 'Book a visit');
    expect(trf('{} to {}', ['09:00', '09:30']), '09:00 to 09:30');
  });

  test('a string, a sentence with a changing part, and a sentence inside a sentence', () {
    appLanguage.value = 'fr';
    expect(tr('Book a visit'), 'Réserver une visite');
    expect(tr('Hello, Michelle'), 'Bonjour, Michelle');
    expect(tr('3 times'), '3 créneaux');
    expect(
      tr('Your six-monthly check-up is due in 5 days.'),
      'Votre contrôle semestriel est prévu dans 5 jours.',
    );
    expect(tr('Pick a time · Mon June'), 'Choisissez un créneau · lun. juin');
    appLanguage.value = 'de';
    expect(trf('{} to {}', ['09:00', '09:30']), '09:00 bis 09:30');
    expect(trf('Tooth {}{}', [14, '']), 'Zahn 14');
  });

  test('what has no translation is shown as it is, and small words never rewrite other text', () {
    appLanguage.value = 'fr';
    expect(tr('Dr Amara Okafor'), 'Dr Amara Okafor');
    expect(tr('Time to relax at home'), 'Time to relax at home');
    expect(
      tr('Monday to Friday'),
      'Monday to Friday',
      reason: 'the "to" sentence is only built with trf',
    );
    expect(tr(''), '');
  });
}
