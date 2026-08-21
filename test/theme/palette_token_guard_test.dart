import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Palette v1.2 (variant D) is the app's **sole** colour source.
///
/// This test walks `lib/` and fails if a raw colour literal reappears anywhere
/// outside `app_design_tokens.dart`. It exists because that is precisely how
/// the codebase ended up with two disagreeing palettes: `AppDesignTokens` and
/// `LightModeColors`/`DarkModeColors` drifted apart quietly, one hardcoded
/// value at a time, and nothing failed while they did. A grep is only as good
/// as the last person who remembered to run it.
///
/// Being a plain source scan, this catches drift the type system cannot: a new
/// widget with `Color(0xFF...)` inline compiles perfectly and looks fine on
/// whoever's screen it was written on.

/// The one file allowed to define colours.
const String _tokensFile = 'lib/theme/app_design_tokens.dart';

/// Files exempt from the sweep, each for a signed reason.
///
/// The technique diagram painters were listed as exempt by the v1.2 spec (its
/// "signed diagram palette": `#E8804A`, `#F2A06E`, `#C9D6C0`, black outlines).
/// They are **not** listed here, because that palette does not exist in this
/// codebase — `technique_diagrams.dart` already draws entirely from
/// `AppDesignTokens` and carries no literal at all, so it passes the guard on
/// its own merits and needs no exemption. If those signed diagram values are
/// ever actually introduced, add the painter file here rather than weakening
/// the rule.
const Set<String> _exemptFiles = <String>{
  // The DEV environment badge is deliberately off-palette: it is a build-mode
  // warning, not part of the product's visual language, and it must not blend
  // in. It uses Material's `Colors.red`/`Colors.black26`, so it has no literal
  // to catch — listed here to record the decision, not because it is failing.
  'lib/widgets/dev_environment_badge.dart',
};

/// `Color(0xFF...)` / `Color(0x...)` and the `0xFF...` form on its own.
final RegExp _colorLiteral = RegExp(r'0[xX][0-9a-fA-F]{6,8}');

/// Strips `//` line comments, `///` doc comments and `/* */` blocks, so that a
/// comment *documenting* an old hex ("was `0xFF284236`") does not trip the
/// guard. Those comments are the migration record and are worth keeping.
String _stripComments(String source) {
  final withoutBlocks = source.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return withoutBlocks
      .split('\n')
      .map((line) {
        final idx = line.indexOf('//');
        if (idx == -1) return line;
        // Not perfect for a `//` inside a string literal (a URL, say) — but
        // truncating there can only ever hide a literal from the scan on a
        // line that also contains a comment marker, never invent one.
        return line.substring(0, idx);
      })
      .join('\n');
}

void main() {
  test('no colour literal exists in lib/ outside the design tokens file', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue,
        reason: 'run this test from the project root');

    final offenders = <String>[];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;

      final relative = entity.path.replaceAll(r'\', '/');
      if (relative == _tokensFile) continue;
      if (_exemptFiles.contains(relative)) continue;

      final lines = _stripComments(entity.readAsStringSync()).split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (_colorLiteral.hasMatch(lines[i])) {
          offenders.add('$relative:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Palette v1.2 is the sole colour source. Every colour belongs in '
          '$_tokensFile as a named semantic token, and widgets reference the '
          'token. If one of these genuinely is not a colour, or is a signed '
          'exception, add it to _exemptFiles with the reason.\n'
          'Found:\n${offenders.join('\n')}',
    );
  });

  test('the tokens file itself is the only place colours are declared', () {
    // Complements the sweep above: proves the guard is actually looking at
    // something. If the tokens file ever stopped declaring literals, the sweep
    // would pass vacuously and the palette would have moved somewhere else.
    final tokens = File(_tokensFile).readAsStringSync();
    expect(_colorLiteral.allMatches(_stripComments(tokens)).length,
        greaterThan(20),
        reason: 'the palette should be declared in $_tokensFile');
  });

  test('the v1.2 (variant D) values are the signed ones', () {
    // The guard above stops literals from spreading; this one stops the
    // *values* from being edited back. Every hex here is signed — the palette
    // from the 2026-08-21 card §2, the two illustration colours from the
    // loading-card card.
    final tokens = _stripComments(File(_tokensFile).readAsStringSync());

    const signed = <String, String>{
      'backgroundSage': '0xFFB3C29A',
      'surfaceIvory': '0xFFF8F3E9',
      'quietRowSurface': '0xFFFDFBF5',
      'neutralPillTint': '0xFFEFE8D8',
      'ctaTerracotta': '0xFFC05C35',
      'terracottaOnLight': '0xFFA44E2B',
      'champagneTint': '0xFFF7DBCB',
      'sageTeachingPanel': '0xFFDDE6C6',
      'sageStripOnCanvas': '0xFFDDE6C6',
      'goldEarnedFill': '0xFFEDA24E',
      'goldEarnedOnLight': '0xFFC77E1F',
      'goldEarnedBadgeTint': '0xFFFBEED8',
      // Illustration-only, signed with the loading card (2026-08-22). Pinned
      // here for the same reason as the palette: so they cannot drift, and so
      // adding them did not mean weakening the guard.
      'illustrationWoodTan': '0xFFD9A066',
      'illustrationWoodTanShade': '0xFFC68B4E',
    };

    for (final entry in signed.entries) {
      expect(
        tokens,
        contains('${entry.key} = Color(${entry.value})'),
        reason: '${entry.key} must be ${entry.value} (palette v1.2, variant D)',
      );
    }
  });
}
