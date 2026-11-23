import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Governance: fonts ship in the app, so no user's IP address goes to a font CDN.
void main() {
  test('fonts are bundled and nothing loads them from a URL at runtime', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/fonts/PlusJakartaSans-Regular.ttf'));
    expect(pubspec, contains('assets/fonts/Lato-Black.ttf'));
    expect(pubspec, isNot(contains('google_fonts')));
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      final src = f.readAsStringSync();
      expect(src, isNot(contains('fonts.googleapis.com')), reason: f.path);
      expect(src, isNot(contains('fonts.gstatic.com')), reason: f.path);
    }
    for (final font in [
      'PlusJakartaSans-Regular.ttf',
      'Lato-Black.ttf',
      'Lato-OFL.txt',
      'PlusJakartaSans-OFL.txt',
    ]) {
      expect(File('assets/fonts/$font').existsSync(), isTrue, reason: font);
    }
  });
}
