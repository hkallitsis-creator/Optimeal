import 'package:flutter_test/flutter_test.dart';
import 'package:optimeal/data/cooking_times.dart';

/// Resolution of a declared key to a band, including the four signed size
/// multipliers and the four shape adjustments (section 2 of the signed table).
void main() {
  group('bands', () {
    test('band boundaries match the signed definitions', () {
      expect(bandForMinutes(0), CookBand.b1);
      expect(bandForMinutes(2), CookBand.b1);
      expect(bandForMinutes(3), CookBand.b2);
      expect(bandForMinutes(5), CookBand.b2);
      expect(bandForMinutes(6), CookBand.b3);
      expect(bandForMinutes(9), CookBand.b3);
      expect(bandForMinutes(10), CookBand.b4);
      expect(bandForMinutes(15), CookBand.b4);
      expect(bandForMinutes(16), CookBand.b5);
      expect(bandForMinutes(25), CookBand.b5);
      expect(bandForMinutes(26), CookBand.b6);
      expect(bandForMinutes(120), CookBand.b6);
    });

    test('labels and distances are the form the flag log uses', () {
      expect(CookBand.b1.label, 'B1');
      expect(CookBand.b6.label, 'B6');
      expect(CookBand.b4.distanceTo(CookBand.b4), 0);
      expect(CookBand.b4.distanceTo(CookBand.b5), 1);
      expect(CookBand.b1.distanceTo(CookBand.b4), 3);
    });
  });

  group('size and shape scaling', () {
    test('the four multipliers are the signed values, not band shifts', () {
      expect(SizeRelativeToReference.half.multiplier, 0.4);
      expect(SizeRelativeToReference.reference.multiplier, 1.0);
      expect(SizeRelativeToReference.double.multiplier, 2.5);
      expect(SizeRelativeToReference.triple.multiplier, 5.0);
    });

    test("the doc's own worked example: x0.4 on a 12 min B4 lands in B2", () {
      // Called out explicitly in the doc as the reason multipliers are NOT
      // equivalent to one-band shifts — this is a two-band drop.
      expect(bandForMinutes(12 * 0.4), CookBand.b2);
    });

    test('a key at its reference cut resolves to exactly its printed band', () {
      expect(CookingTimes.resolveBands('potato_waxy_2cm_dice'),
          [CookingTimes.row('potato_waxy_2cm_dice')!.bands.single]);
      expect(CookingTimes.resolveBands('spinach_whole_leaf'), [CookBand.b1]);
    });

    test('doubling thickness pushes a key up, halving pushes it down', () {
      final reference = CookingTimes.resolveBands('carrot_1cm_dice').single;
      final doubled = CookingTimes.resolveBands('carrot_1cm_dice',
          size: SizeRelativeToReference.double).single;
      final halved = CookingTimes.resolveBands('carrot_1cm_dice',
          size: SizeRelativeToReference.half).single;

      expect(doubled.index, greaterThan(reference.index));
      expect(halved.index, lessThan(reference.index));
    });

    test('shredded or grated is always B1, whatever the density', () {
      for (final key in ['potato_waxy_2cm_dice', 'carrot_1cm_dice', 'spinach_whole_leaf']) {
        expect(
          CookingTimes.resolveBands(key, shape: CutShape.shreddedOrGrated),
          [CookBand.b1],
          reason: key,
        );
      }
    });

    test('whole and round adds a factor on top; strips take one off', () {
      expect(CutShape.wholeOrRound.factor, 1.5);
      expect(CutShape.stripsJulienneBatons.factor, 0.8);
      expect(CutShape.slicedDiscs.factor, 1.0);
      expect(CutShape.asReference.factor, 1.0);
    });
  });

  group('whole muscle versus minced', () {
    test('they are separate rows with separate bands, not one row scaled', () {
      final steak = CookingTimes.row('beef_steak_2cm_med_rare')!;
      final mince = CookingTimes.row('beef_mince_loose')!;

      expect(steak.isComminuted, isFalse);
      expect(mince.isComminuted, isTrue);
      expect(mince.referenceCut, 'loose');
      expect(steak.referenceCut, isNot('loose'));
    });

    test('every comminuted row is marked, and nothing else is', () {
      final marked =
          CookingTimes.rows.where((r) => r.isComminuted).map((r) => r.key).toSet();
      expect(marked, {'pork_mince_loose', 'beef_mince_loose', 'sausage_whole'});
      expect(CookingTimes.row('chicken_breast_2cm_dice')!.isComminuted, isFalse);
      expect(CookingTimes.row('tofu_firm_2cm_cube')!.isComminuted, isFalse);
    });

    test('a minced row scales like any other — the distinction is the row, not the rule', () {
      expect(
        CookingTimes.resolveBands('beef_mince_loose', size: SizeRelativeToReference.half),
        isNotEmpty,
      );
    });
  });

  group('the two exceptional rows', () {
    test('red lentils resolves to nothing at all — every timing check skips it', () {
      expect(CookingTimes.isKnown('red_lentils_simmer'), isTrue,
          reason: 'the key stays declarable; it is the TIMING that is pending');
      expect(CookingTimes.isTimingPending('red_lentils_simmer'), isTrue);
      expect(CookingTimes.resolveBands('red_lentils_simmer'), isEmpty);
      expect(
        CookingTimes.resolveBands('red_lentils_simmer',
            size: SizeRelativeToReference.triple),
        isEmpty,
        reason: 'scaling a pending row must not conjure a band out of nothing',
      );
    });

    test('lamb keeps both of its printed bands', () {
      expect(CookingTimes.resolveBands('lamb_diced_2cm_dice'),
          [CookBand.b3, CookBand.b6]);
    });
  });

  group('unknown and absent keys', () {
    test('resolve to nothing rather than to a guess', () {
      expect(CookingTimes.resolveBands(null), isEmpty);
      expect(CookingTimes.resolveBands(''), isEmpty);
      expect(CookingTimes.resolveBands('carrot'), isEmpty);
      expect(CookingTimes.resolveBands('POTATO_WAXY_2CM_DICE'), isEmpty);
      expect(CookingTimes.isKnown('unicorn_2cm_dice'), isFalse);
    });
  });

  group('the injected prompt key list', () {
    test('is every key, sorted, and nothing else', () {
      final parts = CookingTimes.promptKeyList.split(', ');
      expect(parts, hasLength(74));
      expect(parts.toSet(), CookingTimes.allKeys);
      expect(parts, orderedEquals(parts.toList()..sort()));
    });

    test('is stable across calls — it sits in the cached prompt prefix', () {
      expect(CookingTimes.promptKeyList, CookingTimes.promptKeyList);
    });
  });
}
