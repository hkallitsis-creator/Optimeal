import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/services/confidence_climb_service.dart';
import 'package:optimeal/widgets/what_you_learned_sheet.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('WhatYouLearnedSheet — confidence question', () {
    testWidgets('does not appear on a first-ever completion (empty repeatTechniqueIds)', (tester) async {
      await tester.pumpWidget(_wrap(const WhatYouLearnedSheet(
        curriculumLessonIds: ['sauteing'],
      )));
      await tester.pumpAndSettle();

      expect(find.text('Are you comfortable with this technique?'), findsNothing);
    });

    testWidgets('appears verbatim for a repeat completion', (tester) async {
      await tester.pumpWidget(_wrap(const WhatYouLearnedSheet(
        curriculumLessonIds: ['sauteing'],
        repeatTechniqueIds: {'sauteing'},
      )));
      await tester.pumpAndSettle();

      expect(find.text('Are you comfortable with this technique?'), findsOneWidget);
      expect(find.text("Yes, it's automatic now"), findsOneWidget);
      expect(find.text('Not yet, still takes concentration'), findsOneWidget);
    });

    testWidgets('"Yes, it\'s automatic now" marks the technique comfortable and swaps to an acknowledgement', (tester) async {
      await tester.pumpWidget(_wrap(const WhatYouLearnedSheet(
        curriculumLessonIds: ['sauteing'],
        repeatTechniqueIds: {'sauteing'},
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Yes, it's automatic now"));
      await tester.pumpAndSettle();

      expect(find.text('Thanks — noted.'), findsOneWidget);
      expect(find.text('Are you comfortable with this technique?'), findsNothing);
      expect(await ConfidenceClimbService().loadComfortableTechniqueIds(), {'sauteing'});
    });

    testWidgets('"Not yet, still takes concentration" acknowledges without marking comfortable', (tester) async {
      await tester.pumpWidget(_wrap(const WhatYouLearnedSheet(
        curriculumLessonIds: ['sauteing'],
        repeatTechniqueIds: {'sauteing'},
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not yet, still takes concentration'));
      await tester.pumpAndSettle();

      expect(find.text('Thanks — noted.'), findsOneWidget);
      expect(await ConfidenceClimbService().loadComfortableTechniqueIds(), isEmpty);
    });
  });
}
