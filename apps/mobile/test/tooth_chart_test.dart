import 'package:dental/data/care_repository.dart';
import 'package:dental/features/tooth_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('Universal numbers become plain names', () {
    expect(toothName('1'), 'Upper right third molar');
    expect(toothName('8'), 'Upper right central incisor');
    expect(toothName('14'), 'Upper left first molar');
    expect(toothName('19'), 'Lower left first molar');
    expect(toothName('27'), 'Lower right canine');
    expect(toothName('32'), 'Lower right third molar');
  });

  testWidgets('tapping a tooth tells its story in plain words', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: ToothChart(
                procedures: [
                  Procedure(
                    service: 'Composite filling, one surface',
                    status: 'planned',
                    tooth: '14',
                    surface: 'O',
                  ),
                ],
                findings: [
                  Finding(tooth: '14', surface: 'O', condition: 'caries'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel(RegExp('^Tooth 14:')));
    await tester.pumpAndSettle();
    expect(find.text('Upper left first molar'), findsOneWidget);
    expect(
      find.text('Planned: Composite filling, one surface (biting surface)'),
      findsOneWidget,
    );
    expect(find.text('Decay (biting surface)'), findsOneWidget);
  });
}
