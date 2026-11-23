// Screenshots of every page at phone size, for design reviews. Skipped in normal runs and CI.
// Run: flutter test test/screenshots_test.dart --dart-define=SCREENSHOTS=true --update-goldens
// Output: docs/screenshots/app/*.png (private docs folder).
import 'dart:io';

import 'package:dental/data/account_repository.dart';
import 'package:dental/data/care_repository.dart';
import 'package:dental/data/shop_repository.dart';
import 'package:dental/features/visit_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';
import 'sign_in_and_linking_test.dart' show pumpApp, signIn, tapKey;

const shots = bool.fromEnvironment('SCREENSHOTS');

Future<void> loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(rootBundle.load(f));
    }
    await loader.load();
  }

  final fonts = Directory('assets/fonts').listSync().map((e) => e.path).where((p) => p.endsWith('.ttf')).toList();
  await family('PlusJakartaSans', fonts.where((f) => f.contains('PlusJakarta')).toList());
  await family('Lato', fonts.where((f) => f.contains('Lato')).toList());
  final sdk = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/development/flutter';
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(ByteData.sublistView(File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())),
    );
  await icons.load();
}

final now = DateTime.now();
final visit = Visit(
  id: 'v-1',
  at: DateTime(now.year, now.month - 3, 22, 10),
  kind: 'exam',
  location: 'Cambridge',
  dentist: 'Dr Amara Okafor',
  reason: 'Six-monthly check-up',
  procedures: const [
    Procedure(service: 'Comprehensive oral exam', status: 'completed', feeCents: 14000),
    Procedure(service: 'Adult cleaning', status: 'completed', feeCents: 12000),
    Procedure(service: 'Composite filling, one surface', status: 'planned', tooth: '14', surface: 'O', feeCents: 21000),
  ],
  findings: const [
    Finding(tooth: '14', surface: 'O', condition: 'caries'),
    Finding(tooth: '3', surface: 'MO', condition: 'filled'),
    Finding(tooth: '19', condition: 'crown'),
    Finding(tooth: '1', condition: 'missing'),
    Finding(tooth: '30', surface: 'O', condition: 'sealant'),
  ],
);

CareSummary richCare() => CareSummary(
  upcoming: [
    Appointment(
      id: 'a-1',
      startsAt: DateTime(now.year, now.month, now.day + 6, 9, 30),
      endsAt: DateTime(now.year, now.month, now.day + 6, 10, 30),
      service: 'Composite filling, one surface',
      location: 'Cambridge',
      status: 'booked',
    ),
  ],
  visits: [
    visit,
    Visit(
      id: 'v-2',
      at: DateTime(now.year - 1, 11, 3, 14),
      kind: 'hygiene',
      location: 'Back Bay',
      procedures: const [Procedure(service: 'Adult cleaning', status: 'completed', feeCents: 12000)],
    ),
  ],
  plans: const [
    Plan(
      id: 'p-1',
      status: 'in_progress',
      phases: [
        PlanPhase(
          sequence: 1,
          name: 'Fillings',
          procedures: [Procedure(service: 'Composite filling, one surface', status: 'planned', tooth: '14')],
        ),
        PlanPhase(
          sequence: 2,
          name: 'Review',
          procedures: [Procedure(service: 'Comprehensive oral exam', status: 'planned')],
        ),
      ],
    ),
  ],
  documents: [
    PracticeDocument(
      id: 'd-1',
      encounterId: 'v-1',
      kind: 'xray',
      title: 'Bitewing X-ray',
      path: 'p/x.jpg',
      contentType: 'image/jpeg',
      sharedAt: now,
    ),
    PracticeDocument(
      id: 'd-2',
      encounterId: 'v-1',
      kind: 'visit_summary',
      title: 'Visit summary',
      path: 'p/s.pdf',
      contentType: 'application/pdf',
      sharedAt: now,
    ),
  ],
);

const michelle = LinkedPatient(id: 'p-m', name: 'Michelle Fiona', isSelf: true);

Future<void> shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  // Photos decode on real time, which the fake test clock never gives them: wait for each one before capturing.
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../../docs/screenshots/app/$name.png'));
}

void main() {
  setUpAll(loadFonts);

  Future<FakeCareRepository> app(WidgetTester tester, {List<LinkedPatient> people = const [michelle], bool signIn_ = true}) async {
    tester.view.physicalSize = const Size(720, 1600); // Galaxy A12
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final care = FakeCareRepository({'p-m': richCare()});
    await pumpApp(
      tester,
      FakeAccountRepository(patients: people),
      care: care,
      extra: [pdfViewProvider.overrideWithValue((_) => const SizedBox())],
    );
    if (signIn_) await signIn(tester);
    return care;
  }

  testWidgets('screenshots', skip: !shots, (tester) async {
    await app(tester, signIn_: false);
    await shot(tester, '01-sign-in');
    await tapKey(tester, 'go-sign-up');
    await shot(tester, '02-create-account');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await signIn(tester);
    await shot(tester, '03-home');
    await tapKey(tester, 'tab-records');
    await shot(tester, '04-records');
    await tapKey(tester, 'visit-v-1');
    await shot(tester, '05-visit');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapKey(tester, 'tab-profile');
    await shot(tester, '06-profile');
    await tapKey(tester, 'open-aligner');
    await shot(tester, '07-aligner');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapKey(tester, 'add-coverage');
    await shot(tester, '08-insurance');
  });

  testWidgets('screenshots: booking and onboarding', skip: !shots, (tester) async {
    await app(
      tester,
      people: const [LinkedPatient(id: 'p-m', name: 'Michelle Fiona', isSelf: true, detailsConfirmed: false)],
    );
    await shot(tester, '09-choose-clinic');
  });

  testWidgets('screenshots: link record', skip: !shots, (tester) async {
    await app(tester, people: const []);
    await shot(tester, '10-find-record');
  });

  testWidgets('screenshots: book a visit', skip: !shots, (tester) async {
    await app(tester, people: const [michelle]);
    final repo = FakeCareRepository({'p-m': const CareSummary()});
    // Home without a visit shows "Book a visit".
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, FakeAccountRepository(patients: [michelle]), care: repo);
    await signIn(tester);
    await tapKey(tester, 'book-visit');
    await tapKey(tester, 'service-cleaning');
    await tapKey(tester, 'day-0');
    await tapKey(tester, 'slot-0');
    await shot(tester, '11-booking');
  });

  testWidgets('screenshots: shop', skip: !shots, (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final shop = FakeShopRepository(items: const [
      ShopProduct(id: 'brush', name: 'Sonic electric toothbrush', category: 'brush', summary: 'Two-minute timer, pressure sensor and a 30-day battery.',
        description: 'The brush our hygienists recommend most: 31,000 strokes a minute and a pressure sensor that slows down when you press too hard.',
        priceCents: 7900, imageKey: 'sonic-brush', tags: ['Everyday', 'Gums']),
      ShopProduct(id: 'heads', name: 'Replacement brush heads, 2 pack', category: 'brush', summary: 'Change every three months.',
        description: 'Soft, end-rounded bristles that fade when it is time to change.', priceCents: 1400, imageKey: 'brush-heads',
        refillMonths: 3, tags: ['Everyday']),
      ShopProduct(id: 'flosser', name: 'Cordless water flosser', category: 'clean_between', summary: 'Three pressure modes.',
        description: 'Good for implants and braces.', priceCents: 6900, imageKey: 'water-flosser', tags: ['Gums', 'Implants']),
      ShopProduct(id: 'interdental', name: 'Interdental brushes, mixed sizes', category: 'clean_between', summary: 'For bridges, braces and gaps.',
        description: 'Eight sizes in one pack.', priceCents: 850, imageKey: 'interdental', refillMonths: 3, tags: ['Gums']),
      ShopProduct(id: 'sensitive', name: 'Sensitive toothpaste', category: 'paste_and_rinse', summary: 'Potassium nitrate formula.',
        description: 'Daily toothpaste for sensitive teeth.', priceCents: 750, imageKey: 'sensitive-paste', refillMonths: 3, tags: ['Sensitive']),
      ShopProduct(id: 'kids', name: "Kids' sonic toothbrush", category: 'kids', summary: 'Gentle mode and a fun timer.',
        description: 'Made for ages 3 to 10.', priceCents: 3900, imageKey: 'kids-brush', tags: ['Kids']),
    ]);
    await pumpApp(tester, FakeAccountRepository(patients: [michelle]), shop: shop,
        care: FakeCareRepository({'p-m': richCare()}), extra: [pdfViewProvider.overrideWithValue((_) => const SizedBox())]);
    await signIn(tester);
    await tapKey(tester, 'tab-shop');
    await shot(tester, '20-shop');
    await tapKey(tester, 'product-heads');
    await shot(tester, '21-product');
    await tapKey(tester, 'add-to-bag');
    await tapKey(tester, 'product-brush');
    await tapKey(tester, 'add-to-bag');
    await tapKey(tester, 'open-bag');
    await shot(tester, '22-bag');
  });

  testWidgets('screenshots: assistant', skip: !shots, (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final assistant = FakeAssistantRepository();
    await pumpApp(tester, FakeAccountRepository(patients: [michelle]), assistant: assistant,
        care: FakeCareRepository({'p-m': richCare()}), extra: [pdfViewProvider.overrideWithValue((_) => const SizedBox())]);
    await signIn(tester);
    await tapKey(tester, 'open-assistant');
    await tapKey(tester, 'pick-language');
    await tapKey(tester, 'language-es');
    await shot(tester, '23-assistant');
    assistant.proposeBooking = true;
    await tester.enterText(find.byKey(const Key('assistant-input')), 'Quiero una limpieza en Quincy el viernes por la mañana');
    await tapKey(tester, 'assistant-send');
    await shot(tester, '24-assistant-confirm');
  });

  // The style audit: every remaining page, at normal and at large system text (1.3x).
  for (final scale in [1.0, 1.3]) {
    testWidgets('screenshots: audit at text ${scale}x', skip: !shots, (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final tag = scale == 1.0 ? 'a' : 'b';
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final rich = richCare();
      final care = FakeCareRepository({
        'p-m': CareSummary(
          upcoming: rich.upcoming,
          plans: rich.plans,
          documents: rich.documents,
          visits: [
            Visit(
              id: 'v-x',
              at: now.subtract(const Duration(hours: 4)),
              kind: 'treatment',
              location: 'Back Bay',
              procedures: const [Procedure(service: 'Simple extraction', status: 'completed')],
            ),
            ...rich.visits,
          ],
        ),
      });
      await pumpApp(tester, FakeAccountRepository(patients: [michelle]), care: care,
          voice: FakeVoiceEngine(), extra: [pdfViewProvider.overrideWithValue((_) => const SizedBox())]);
      await signIn(tester);
      await shot(tester, '30$tag-home');
      await tapKey(tester, 'aftercare-card');
      await shot(tester, '31$tag-aftercare');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapKey(tester, 'tab-appointments');
      await shot(tester, '32$tag-appointments');
      await tapKey(tester, 'tab-shop');
      await shot(tester, '33$tag-shop');
      await tapKey(tester, 'tab-profile');
      await tapKey(tester, 'open-payments');
      await shot(tester, '34$tag-payments');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapKey(tester, 'open-orders');
      await shot(tester, '35$tag-orders');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapKey(tester, 'tab-home');
      await tapKey(tester, 'open-assistant');
      await shot(tester, '36$tag-chat');
      await tapKey(tester, 'open-voice');
      await shot(tester, '37$tag-nora');
    });
  }
}
