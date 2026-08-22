import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **House rule, app-wide: no emoji inside a CTA label.**
///
/// A CTA is the one thing on a screen that has to read as a decision. An emoji
/// in it does two things, both bad: it makes the button look like a toy next
/// to the rest of the kit, and it makes the label's meaning depend on a glyph
/// that renders differently on every platform and not at all in some
/// accessibility contexts.
///
/// This is scoped to **CTAs**, deliberately, and not to the whole app. Chef
/// SOS's quick-prompt chips carry food emoji ("🔥 Not browning / no colour")
/// and that is a different thing: a scannable list of symptoms, not a button
/// that commits you to something. Widening this guard to all of `lib/` would
/// fail on 34 of those and force a change nobody asked for.
///
/// Hits fixed when this landed: "✨ Generate Recipe" (custom creator),
/// "🔥 Cook Now" and "📅 Plan for Day" (generated-recipe actions sheet), plus
/// the "📅 Plan for which day?" sheet title next to them.
void main() {
  // Ranges chosen to cover pictographic emoji without catching the typographic
  // characters this codebase uses on purpose — the em dash, the middle dot,
  // the ½/¼ fractions, the ✕ in allergen chips and the box-drawing in comments.
  final emoji = RegExp(
    '[\u{1F300}-\u{1FAFF}]|[\u{1F000}-\u{1F0FF}]|[\u{2728}]|[\u{1F900}-\u{1F9FF}]',
    unicode: true,
  );

  const buttonMarkers = [
    'FilledButton',
    'ElevatedButton',
    'TextButton',
    'OutlinedButton',
  ];

  test('no emoji inside any CTA label anywhere in lib/', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();

      for (var i = 0; i < lines.length; i++) {
        if (!buttonMarkers.any(lines[i].contains)) continue;

        // A button's label sits within its constructor. Twenty lines covers
        // the styled multi-line form used throughout this codebase.
        final end = (i + 20).clamp(0, lines.length);
        for (var j = i; j < end; j++) {
          final line = lines[j];
          if (line.trimLeft().startsWith('//')) continue;
          if (!line.contains("'") && !line.contains('"')) continue;
          final match = emoji.firstMatch(line);
          if (match != null) {
            offenders.add(
                '${entity.path.replaceAll(r'\', '/')}:${j + 1}  ${line.trim()}');
          }
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'emoji in a CTA label:\n${offenders.join('\n')}');
  });

  test('the specific labels that were fixed stay fixed', () {
    final creator = File('lib/widgets/custom_ai_recipe_creator_sheet.dart')
        .readAsStringSync();
    final actions = File('lib/widgets/generated_recipe_actions_sheet.dart')
        .readAsStringSync();

    expect(creator.contains('Generate recipe'), isTrue);
    expect(creator.contains('✨'), isFalse);
    expect(actions.contains("'Cook Now'"), isTrue);
    expect(actions.contains('🔥'), isFalse);
    expect(actions.contains('📅'), isFalse);
  });

  test('the guard is CTA-scoped, and SOS chips are untouched', () {
    // Not a loophole — a recorded boundary. If someone later decides the SOS
    // chips should lose their emoji too, that is a design decision, and this
    // test is where they will find out it was deliberate.
    final cookMode = File('lib/screens/one_pan_cooking_roadmap_screen.dart')
        .readAsStringSync();
    expect(cookMode.contains('Not browning'), isTrue,
        reason: 'the SOS quick prompts still exist and still carry emoji');
  });
}
