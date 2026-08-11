import 'package:flutter/material.dart';

import 'package:optimeal/chef_curiculum_reference.dart';
import 'package:optimeal/chef_curiculum_techniques.dart';
import 'package:optimeal/theme/app_design_tokens.dart';

/// Shared rendering for a single `chefTechniqueDrawers`/`chefReferenceDrawers`
/// entry — used by [WhatYouLearnedSheet] (post-cook recap) and the Home
/// "Technique of the Week" card, so both present curriculum content the same
/// way rather than each inventing their own formatting.
class ResolvedDrawerEntry {
  const ResolvedDrawerEntry({required this.key, required this.title, required this.teaser, required this.fullText});

  final String key;
  final String title;
  final String teaser;
  final String fullText;
}

/// Resolves a list of drawer keys (technique or reference) into parsed
/// entries, skipping any that don't exist or fail to parse. Preserves input
/// order and de-duplicates repeated keys.
Iterable<ResolvedDrawerEntry> resolveDrawerEntries(List<String> keys) sync* {
  final seen = <String>{};

  for (final rawKey in keys) {
    final key = rawKey.trim();
    if (key.isEmpty) continue;
    if (!seen.add(key)) continue;

    final content = chefTechniqueDrawers[key] ?? chefReferenceDrawers[key];
    if (content == null) continue;

    final parsed = _parseDrawer(content);
    if (parsed == null) continue;

    yield ResolvedDrawerEntry(key: key, title: parsed.$1, teaser: parsed.$2, fullText: content.trim());
  }
}

/// Resolves a single drawer key, or null if it doesn't exist / fails to parse.
ResolvedDrawerEntry? resolveDrawerEntry(String key) {
  final entries = resolveDrawerEntries([key]).toList(growable: false);
  return entries.isEmpty ? null : entries.first;
}

/// All drawer keys eligible to be featured as "Technique of the Week" —
/// every technique/reference drawer except `general_tips`, which is a
/// generic SOS fallback rather than a taught technique (same exclusion
/// [ChefService.matchedCurriculumDrawerKeys] applies).
List<String> get featurableDrawerKeys {
  final keys = <String>[...chefTechniqueDrawers.keys, ...chefReferenceDrawers.keys];
  keys.remove('general_tips');
  return keys;
}

/// Picks this week's featured technique deterministically from the ISO week
/// number, so it's stable across app opens/devices within the same week and
/// rotates automatically without needing any stored state.
ResolvedDrawerEntry? techniqueOfTheWeek({DateTime? now}) {
  final keys = featurableDrawerKeys;
  if (keys.isEmpty) return null;
  final date = now ?? DateTime.now();
  final weekNumber = date.difference(DateTime(date.year, 1, 1)).inDays ~/ 7;
  final index = weekNumber % keys.length;
  return resolveDrawerEntry(keys[index]);
}

/// Parses a drawer into (title, teaser).
///
/// Title: Everything after the first "TECHNIQUE: " prefix.
/// Teaser: First sentence of the next non-blank line after the technique line.
(String, String)? _parseDrawer(String raw) {
  final lines = raw.split('\n').map((e) => e.trim()).toList(growable: false);
  if (lines.isEmpty) return null;

  final techIndex = lines.indexWhere((l) => l.toUpperCase().startsWith('TECHNIQUE:'));
  if (techIndex == -1) return null;

  final techLine = lines[techIndex];
  final title = techLine.substring('TECHNIQUE:'.length).trim();
  if (title.isEmpty) return null;

  String? nextNonBlank;
  for (var i = techIndex + 1; i < lines.length; i++) {
    final l = lines[i];
    if (l.isEmpty) continue;
    nextNonBlank = l;
    break;
  }
  if (nextNonBlank == null) return null;

  var teaser = nextNonBlank;
  final dot = teaser.indexOf('.');
  if (dot != -1) teaser = teaser.substring(0, dot + 1);
  teaser = teaser.trim();

  if (teaser.length > 140) {
    teaser = '${teaser.substring(0, 137).trimRight()}...';
  }

  return (title, teaser);
}

class _DrawerBodySection {
  const _DrawerBodySection({required this.label, required this.bullets});

  final String label;
  final List<String> bullets;
}

/// Splits a raw drawer entry (`TECHNIQUE: ...\nRATIOS: ...\nHEAT: ...`) into
/// labeled sections, each broken into individual sentence-level bullets.
///
/// The `TECHNIQUE:` line itself is skipped since it's already shown as the
/// card's title. Sentence splitting (rather than a fixed bullet format in
/// the source data) works because the drawers are hand-written as one
/// self-contained sentence per point — this keeps the raw strings usable
/// as-is for the AI system prompt while giving this UI a bulleted look.
List<_DrawerBodySection> _parseDrawerSections(String raw) {
  final labelPattern = RegExp(r'^([A-Z][A-Z /]{2,30}):\s*(.*)$');
  final sentenceSplit = RegExp(r'(?<=[.!?])\s+(?=[A-Z0-9(])');

  final sections = <_DrawerBodySection>[];
  for (final line in raw.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed == '[Omitted long context line]') continue;

    final match = labelPattern.firstMatch(trimmed);
    if (match == null) continue;

    final label = match.group(1)!.trim();
    if (label == 'TECHNIQUE') continue;

    final body = match.group(2)!.trim();
    if (body.isEmpty) continue;

    final numberedPrefix = RegExp(r'^\(\d+\)\s*');
    final bullets = body
        .split(sentenceSplit)
        .map((s) => s.trim().replaceFirst(numberedPrefix, ''))
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    sections.add(_DrawerBodySection(label: label, bullets: bullets));
  }
  return sections;
}

/// Matches temperatures (e.g. "200–230°C/400–450°F") and durations (e.g.
/// "10–15 min") so they can be bolded/colored inline — the numbers a cook
/// actually scans for while mid-recipe.
final RegExp _drawerHighlightPattern = RegExp(
  r'(\d+(?:[–-]\d+)?\s?°[CF](?:/\d+(?:[–-]\d+)?\s?°[CF])?)'
  r'|(\d+(?:[–-]\d+)?\+?\s?(?:seconds?|secs?|minutes?|mins?|hours?|hrs?)\b)',
  caseSensitive: false,
);

List<InlineSpan> _highlightedSpans(String text, TextStyle baseStyle, TextStyle highlightStyle) {
  final spans = <InlineSpan>[];
  var last = 0;
  for (final match in _drawerHighlightPattern.allMatches(text)) {
    if (match.start > last) {
      spans.add(TextSpan(text: text.substring(last, match.start), style: baseStyle));
    }
    spans.add(TextSpan(text: match.group(0), style: highlightStyle));
    last = match.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last), style: baseStyle));
  }
  return spans;
}

/// Renders a drawer's full text as labeled, bulleted sections with
/// temperatures/durations bolded inline.
class FormattedDrawerBody extends StatelessWidget {
  const FormattedDrawerBody({super.key, required this.rawText});

  final String rawText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sections = _parseDrawerSections(rawText);

    final baseStyle = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.45, fontWeight: FontWeight.w600) ??
        const TextStyle();
    final highlightStyle = baseStyle.copyWith(color: AppDesignTokens.ctaTerracotta, fontWeight: FontWeight.w900);

    if (sections.isEmpty) {
      return Text(rawText, style: baseStyle);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var s = 0; s < sections.length; s++) ...[
          if (s > 0) const SizedBox(height: 12),
          Text(
            sections[s].label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppDesignTokens.deepForest,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          for (final bullet in sections[s].bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(color: scheme.onSurfaceVariant.withValues(alpha: 0.6), shape: BoxShape.circle),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(TextSpan(children: _highlightedSpans(bullet, baseStyle, highlightStyle))),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// Title + teaser + tap-to-expand full breakdown for one [ResolvedDrawerEntry].
class DrawerCard extends StatefulWidget {
  const DrawerCard({super.key, required this.entry, this.initiallyOpen = false});

  final ResolvedDrawerEntry entry;
  final bool initiallyOpen;

  @override
  State<DrawerCard> createState() => _DrawerCardState();
}

class _DrawerCardState extends State<DrawerCard> {
  late bool _isOpen = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppDesignTokens.backgroundSage.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.entry.title,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: AppDesignTokens.textCharcoal, height: 1.2),
          ),
          const SizedBox(height: 10),
          Text(
            widget.entry.teaser,
            style: theme.textTheme.bodyMedium?.copyWith(color: AppDesignTokens.textCharcoal.withValues(alpha: 0.82), height: 1.35, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _DrawerDisclosure(
            isOpen: _isOpen,
            onToggle: () => setState(() => _isOpen = !_isOpen),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_isOpen
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: scheme.outline.withValues(alpha: 0.14)),
                      ),
                      child: FormattedDrawerBody(rawText: widget.entry.fullText),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Disclosure pill patterned after Cook Mode's _ScienceNoteDisclosure.
class _DrawerDisclosure extends StatelessWidget {
  const _DrawerDisclosure({required this.isOpen, required this.onToggle});

  final bool isOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.18);
    final border = theme.colorScheme.outline.withValues(alpha: 0.14);

    return Semantics(
      button: true,
      label: 'See the full breakdown',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Icon(Icons.menu_book_rounded, size: 18, color: theme.colorScheme.tertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'See the full breakdown',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                turns: isOpen ? 0.5 : 0,
                child: Icon(Icons.expand_more_rounded, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
