import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'de.dart';
import 'es.dart';
import 'fr.dart';
import 'it.dart';
import 'lt.dart';
import 'nl.dart';
import 'sv.dart';

/// The app in the patient's language. English is the source: every screen is written in English, and what it shows
/// is looked up here on the way to the screen (see `Text` in ui.dart), so a screen needs no translation code of its
/// own. A string with no translation stays in English, never blank.
///
/// Sentences with a changing part ("3 items", "Hi, Michelle") are stored once with `{}` where the part goes; the
/// part itself is translated too when it is a known word (a month, a weekday).

const appLanguages = {
  'en': 'English',
  'fr': 'Français',
  'nl': 'Nederlands',
  'de': 'Deutsch',
  'es': 'Español',
  'it': 'Italiano',
  'lt': 'Lietuvių',
  'sv': 'Svenska',
};

const _tables = <String, Map<String, String>>{
  'fr': fr,
  'nl': nl,
  'de': de,
  'es': es,
  'it': it,
  'lt': lt,
  'sv': sv,
};

/// The language the app is shown in. Set from the phone's language at start, or by the patient in Profile.
final appLanguage = ValueNotifier<String>('en');

final _memo = <String, Map<String, String>>{};
final _patterns = <String, List<(RegExp, String)>>{};

List<(RegExp, String)> _patternsFor(String language) =>
    _patterns[language] ??= [
      for (final MapEntry(:key, :value) in _tables[language]!.entries)
        if (key.contains('{}') && !key.startsWith('='))
          (
            RegExp(
              '^${key.split('{}').map(RegExp.escape).join('(.+?)')}\$',
              dotAll: true,
            ),
            value,
          ),
    ];

const _saved = 'app_language';

/// The patient's saved choice, else the phone's language when we have it, else English.
Future<void> loadAppLanguage() async {
  String? saved;
  try {
    saved = await const FlutterSecureStorage().read(key: _saved);
  } on Exception {
    saved = null; // no secure storage (a test, a locked phone): the phone's language will do
  }
  final phone = PlatformDispatcher.instance.locale.languageCode;
  appLanguage.value = appLanguages.containsKey(saved)
      ? saved!
      : appLanguages.containsKey(phone)
      ? phone
      : 'en';
}

/// A language is not patient data, so it is kept across sign-outs.
Future<void> setAppLanguage(String language) async {
  if (!appLanguages.containsKey(language)) return;
  appLanguage.value = language;
  try {
    await const FlutterSecureStorage().write(key: _saved, value: language);
  } on Exception {
    // the choice still holds until the app closes
  }
}

/// [text] in the app's language, or [text] itself when there is nothing to translate.
String tr(String text) {
  final language = appLanguage.value;
  final table = _tables[language];
  if (table == null || text.isEmpty) return text;
  final memo = _memo[language] ??= {};
  return memo[text] ??= _translate(text, table, language);
}

String _translate(String text, Map<String, String> table, String language) {
  final exact = table[text];
  if (exact != null) return exact;
  for (final (pattern, template) in _patternsFor(language)) {
    final match = pattern.firstMatch(text);
    if (match == null) continue;
    var i = 0;
    return template.replaceAllMapped('{}', (_) {
      i += 1;
      final part = match.group(i) ?? '';
      return _translate(
        part,
        table,
        language,
      ); // a month, a weekday or a smaller sentence inside
    });
  }
  return text;
}

/// A sentence built from parts at one call site: [template] has `{}` where each of [parts] goes. The translation
/// may put them to different words but keeps their order. Stored under `=template`, so it is never matched against
/// other text the way the patterns in [tr] are.
String trf(String template, List<Object?> parts) {
  final shape = _tables[appLanguage.value]?['=$template'] ?? template;
  var i = 0;
  return shape.replaceAllMapped('{}', (_) => '${parts[i++]}');
}

/// Every English string the tables translate, for the completeness test.
Map<String, Map<String, String>> get translationTables => _tables;
