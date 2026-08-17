// Sensory Cue Vocabulary — signed by Chef Harris, 17.08.2026.
//
// Source of truth: the signed document "Sensory Cue Vocabulary - Draft v0.2"
// (all 27 entries kept as printed, zero strikes). Every `observable`,
// `harrisSays`, `ifNotReady` and `ifOvershot` string below is VERBATIM from
// that document. Do not edit the voice text in code review — wording changes
// go back to Harris and arrive as a new signed version of this file.
//
// This is the third instance of the closed-vocabulary pattern (after the cut
// vocabulary and the curriculum drawer keys): the model declares a cue_key
// from [SensoryCueVocabulary.allKeys] and the app renders Harris's voice from
// here. The full text of this file is NEVER sent in a prompt — only the key
// list and compact selection hints. Voice lives app-side.
//
// Schema note: `CuePhase.during` (the heat-and-sound family) is an addition
// beyond the signed document, which defined only readiness and doneness.
// Flagged to Harris on 17.08.2026.

/// When in a step's lifecycle a cue fires.
enum CuePhase {
  /// Fires BEFORE the timer starts. Nothing goes in the pan until it passes.
  readiness,

  /// Fires DURING the step — the pan tells you the heat is wrong before
  /// anything looks wrong.
  during,

  /// Fires when the timer ends. The cue is the authority; the timer is only
  /// an estimate of when to start checking.
  doneness,
}

enum CueSense { sight, touch, sound, smell, taste, time }

class SensoryCue {
  const SensoryCue({
    required this.key,
    required this.senses,
    required this.phase,
    required this.observable,
    required this.harrisSays,
    this.ifNotReady,
    this.ifOvershot,
    this.action,
    this.safetyNote,
    this.mandatoryOnPoultryAndPork = false,
  });

  /// snake_case, stable, never shown to the user. The model declares this.
  final String key;

  final List<CueSense> senses;
  final CuePhase phase;

  /// What is actually true when it is ready. Neutral, factual.
  final String observable;

  /// The line in Chef Harris's voice. The field that matters most.
  final String harrisSays;

  /// Remedy when the cue has not passed yet. Verbatim from the document.
  final String? ifNotReady;

  /// "You have gone too far" — the more common beginner failure.
  final String? ifOvershot;

  /// Used instead of ifNotReady where the document specifies an action
  /// (pan_gone_quiet only).
  final String? action;

  /// Safety-critical annotation (juices_run_clear only).
  final String? safetyNote;

  /// Absence of this cue on a poultry or pork step is a validator flag
  /// regardless of stated time.
  final bool mandatoryOnPoultryAndPork;
}

class SensoryCueVocabulary {
  SensoryCueVocabulary._();

  /// Escape value the model MUST be able to declare when nothing fits —
  /// exactly like the explicit `none` in the cut vocabulary. A wrong cue is
  /// worse than a missing one.
  static const String noCueKey = 'no_cue';

  /// Every valid declarable key, including [noCueKey]. Validate model
  /// declarations against this list; anything else is rejected and treated
  /// as [noCueKey].
  static final List<String> allKeys = List.unmodifiable([
    for (final c in entries) c.key,
    noCueKey,
  ]);

  static SensoryCue? byKey(String key) {
    for (final c in entries) {
      if (c.key == key) return c;
    }
    return null;
  }

  static const List<SensoryCue> entries = [
    // ── Readiness — is the pan ready ─────────────────────────────────────
    SensoryCue(
      key: 'water_beads_and_dances',
      senses: [CueSense.sight],
      phase: CuePhase.readiness,
      observable:
          'Stainless steel pan. Drops of water bead up and skate across the surface instead of evaporating.',
      harrisSays:
          'Flick a few drops of water in. If they bead up and dance instead of vanishing, the pan is ready.',
      ifNotReady: 'more_heat',
      ifOvershot:
          'they vanish on contact and the pan smokes - take it off for a minute.',
    ),
    SensoryCue(
      key: 'oil_shimmers',
      senses: [CueSense.sight],
      phase: CuePhase.readiness,
      observable:
          'Oil runs thin and loose, with a visible shimmer when the pan is tilted.',
      harrisSays: 'Tilt the pan. When the oil runs thin and shimmers, it is ready.',
      ifNotReady: 'more_heat',
      ifOvershot: 'wisps of smoke means too hot - pull it off the heat.',
    ),
    SensoryCue(
      key: 'bubbles_around_spoon',
      senses: [CueSense.sight],
      phase: CuePhase.readiness,
      observable:
          'Steady bubbles rise around a wooden spoon handle dipped into hot oil.',
      harrisSays:
          'Dip the handle of a wooden spoon in. Steady bubbles around it and you are ready to cook. Nothing, give it some time.',
      ifNotReady: 'more_heat',
      ifOvershot: 'violent bubbling and smoke - too hot.',
    ),
    SensoryCue(
      key: 'butter_foam_subsides',
      senses: [CueSense.sight, CueSense.smell],
      phase: CuePhase.readiness,
      observable:
          'Butter foams hard, then the foaming stops and the smell turns nutty.',
      harrisSays:
          'Butter foams, then goes quiet. When the foaming stops and it smells nutty, that is your moment.',
      ifNotReady: 'more_time',
      ifOvershot:
          'brown specks and a sharp smell - it has gone past, start again.',
    ),
    SensoryCue(
      key: 'rolling_boil',
      senses: [CueSense.sight],
      phase: CuePhase.readiness,
      observable:
          'Large bubbles across the whole surface that do not stop when stirred.',
      harrisSays:
          'Big bubbles that keep going when you stir. Small bubbles at the edge is not boiling yet.',
      ifNotReady: 'more_heat',
      ifOvershot: 'boiling over - lower it.',
    ),
    SensoryCue(
      key: 'oven_actually_preheated',
      senses: [CueSense.time],
      phase: CuePhase.readiness,
      observable:
          'The oven beeps well before the oven itself is at temperature.',
      harrisSays:
          'The beep means the air is hot, not the oven. Give it ten more minutes before anything goes in.',
      ifNotReady: 'more_time',
    ),
    SensoryCue(
      key: 'sizzle_on_contact',
      senses: [CueSense.sound],
      phase: CuePhase.readiness,
      observable: 'Food sizzles the instant it touches the pan.',
      harrisSays:
          'It should sizzle the moment it touches down. If it goes in silent, take it back out and wait.',
      ifNotReady: 'more_heat',
    ),
    SensoryCue(
      key: 'surface_dry',
      senses: [CueSense.sight, CueSense.touch],
      phase: CuePhase.readiness,
      observable:
          'No visible moisture on the food before it goes in the pan.',
      harrisSays:
          'Pat it dry before it goes near the pan. Wet food steams, it does not brown.',
      ifNotReady: 'pat dry and wait',
    ),

    // ── Heat and sound — is the heat right (fires DURING the step) ───────
    SensoryCue(
      key: 'sizzle_steady',
      senses: [CueSense.sound],
      phase: CuePhase.during,
      observable: 'An even, continuous sizzle - neither silence nor spitting.',
      harrisSays:
          'Listen to the pan. A steady even sizzle means the heat is right.',
      ifNotReady: 'more_heat',
      ifOvershot: 'spitting and cracking - bring it down.',
    ),
    SensoryCue(
      key: 'pan_gone_quiet',
      senses: [CueSense.sound],
      phase: CuePhase.during,
      observable: 'The sizzle stops because the liquid has evaporated.',
      harrisSays:
          'If the pan goes quiet, the liquid has gone. Add a splash before anything catches.',
      action: 'stir_and_wait',
    ),
    SensoryCue(
      key: 'aggressive_roar',
      senses: [CueSense.sound],
      phase: CuePhase.during,
      observable:
          'Loud continuous roar - correct for stir-frying, wrong for almost everything else.',
      harrisSays:
          'A roar is right for a wok and wrong for a pan. If your pan is roaring, it is too hot.',
      ifOvershot: 'less_heat',
    ),

    // ── Doneness by touch ────────────────────────────────────────────────
    SensoryCue(
      key: 'fork_slides_easily',
      senses: [CueSense.touch],
      phase: CuePhase.doneness,
      observable:
          'A fork pushed into the thickest piece goes in and comes out with almost no resistance.',
      harrisSays:
          'Push a fork into the biggest piece. In and out easily and it is done.',
      ifNotReady: 'more_time',
      ifOvershot: 'it falls apart on the fork - it has gone too soft.',
    ),
    SensoryCue(
      key: 'fork_meets_resistance',
      senses: [CueSense.touch],
      phase: CuePhase.doneness,
      observable:
          'A fork goes in firmly and has to be pulled back out. Still has bite.',
      harrisSays:
          'Pinch a piece with your fork. It should go in firmly and come back out reluctantly. That is crunchy, and that is what we want here.',
      ifNotReady: 'more_time',
      ifOvershot: 'it slides straight through - you have lost the bite.',
    ),
    SensoryCue(
      key: 'released_from_pan',
      senses: [CueSense.touch],
      phase: CuePhase.doneness,
      observable:
          'The piece lets go of the pan when nudged, instead of sticking.',
      harrisSays:
          'Give it a nudge. If it sticks, it is not ready to turn. It lets go when it is.',
      ifNotReady: 'more_time',
    ),
    SensoryCue(
      key: 'flakes_apart',
      senses: [CueSense.touch],
      phase: CuePhase.doneness,
      observable: 'Gentle pressure separates it along its natural lines.',
      harrisSays:
          'Press gently with a fork. If it starts to come apart in flakes, it is done.',
      ifNotReady: 'more_time',
      ifOvershot: 'dry and chalky - it needed less.',
    ),
    SensoryCue(
      key: 'springs_back',
      senses: [CueSense.touch],
      phase: CuePhase.doneness,
      observable:
          'Firm under a finger with a little bounce, not soft and not hard.',
      harrisSays:
          'Press the middle with a finger. Firm with a little spring means done. Still soft and it needs longer.',
      ifNotReady: 'more_time',
      ifOvershot: 'hard with no give - overcooked.',
    ),

    // ── Doneness by sight ────────────────────────────────────────────────
    SensoryCue(
      key: 'edges_browned',
      senses: [CueSense.sight],
      phase: CuePhase.doneness,
      observable:
          'Golden to deep brown on the faces touching the pan, not just warmed through.',
      harrisSays:
          'Lift one piece and look underneath. A real golden edge, not pale.',
      ifNotReady: 'more_time',
      ifOvershot: 'dark brown at the edges going bitter - less_heat.',
    ),
    SensoryCue(
      key: 'sides_browned',
      senses: [CueSense.sight],
      phase: CuePhase.doneness,
      observable:
          'Colour appears at the sides while the centre is still pale. Oven baking only.',
      harrisSays:
          'Colour on the sides is your signal. Do not wait for the middle to brown or they will be dry.',
      ifNotReady: 'more_time',
      ifOvershot: 'dry and crumbly - pull at the first colour next time.',
    ),
    SensoryCue(
      key: 'translucent_no_colour',
      senses: [CueSense.sight],
      phase: CuePhase.doneness,
      observable:
          'Softened and glassy at the edges with no browning at all.',
      harrisSays:
          'Onions should go glassy and soft with no colour on them at all.',
      ifNotReady: 'more_time',
      ifOvershot: 'any browning and you are past sweating - less_heat.',
    ),
    SensoryCue(
      key: 'deep_mahogany',
      senses: [CueSense.sight],
      phase: CuePhase.doneness,
      observable:
          'Deep even brown throughout, jammy, sweet-smelling. Takes 35 minutes or more.',
      harrisSays:
          'Deep brown and jammy. This takes far longer than you think - closer to 35 minutes than 10.',
      ifNotReady: 'more_time',
      ifOvershot: 'black flecks and a bitter smell - start again.',
    ),
    SensoryCue(
      key: 'reduced_by_half',
      senses: [CueSense.sight],
      phase: CuePhase.doneness,
      observable: 'The liquid sits at roughly half the level it started at.',
      harrisSays:
          'Look at the line the liquid left on the pan. Down to about half.',
      ifNotReady: 'more_time',
      ifOvershot: 'reduced to nothing and catching - add a splash.',
    ),
    SensoryCue(
      key: 'coats_the_spoon',
      senses: [CueSense.sight],
      phase: CuePhase.doneness,
      observable:
          'A finger drawn across the back of a coated spoon leaves a line that holds.',
      harrisSays:
          'Draw a finger across the back of the spoon. If the line holds, it is thick enough. If it runs back, keep going.',
      ifNotReady: 'more_time',
      ifOvershot: 'thick and gluey - loosen with a splash.',
    ),

    // ── Doneness by smell and taste ──────────────────────────────────────
    SensoryCue(
      key: 'alcohol_cooked_off',
      senses: [CueSense.smell],
      phase: CuePhase.doneness,
      observable: 'The sharp alcoholic edge is gone from the steam.',
      harrisSays:
          'Smell the pan. If there is no sharp alcoholic edge left, it is done.',
      ifNotReady: 'more_time',
    ),
    SensoryCue(
      key: 'aroma_sweetened',
      senses: [CueSense.smell],
      phase: CuePhase.doneness,
      observable:
          'The raw sharp note is gone and the smell has turned sweet.',
      harrisSays:
          'Lean over the pan. Onions smelling sweet instead of raw and sharp - that is the turn.',
      ifNotReady: 'more_time',
    ),
    SensoryCue(
      key: 'spices_bloomed',
      senses: [CueSense.smell],
      phase: CuePhase.doneness,
      observable:
          'Spices go from dusty to warm and fragrant, usually inside a minute.',
      harrisSays:
          'Spices go from dusty to warm and fragrant fast. The moment you smell them, move on.',
      ifNotReady: 'more_time',
      ifOvershot: 'bitter and acrid means burnt - start the spices again.',
    ),
    SensoryCue(
      key: 'tastes_seasoned',
      senses: [CueSense.taste],
      phase: CuePhase.doneness,
      observable: 'Salt level is correct at this stage, not left to the end.',
      harrisSays:
          'Taste it now, not at the end. If it tastes flat it needs salt, not more cooking.',
      ifNotReady: 'season and taste again',
    ),

    // ── Safety — the one that is not a preference ────────────────────────
    SensoryCue(
      key: 'juices_run_clear',
      senses: [CueSense.sight],
      phase: CuePhase.doneness,
      observable:
          'Cut into the thickest part: flesh opaque and white throughout, juices clear, no pink flesh and no pink or red juice.',
      harrisSays:
          'Cut into the thickest part. White all the way through and the juices clear. Any pink at all and it goes back on. A thermometer in the thickest part does the same job faster.',
      ifNotReady: 'more_time',
      safetyNote: 'Never: assume by time alone.',
      mandatoryOnPoultryAndPork: true,
    ),
  ];
}
