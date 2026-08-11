/// Chef Harris Curriculum — Lookup Drawers (Bucket B, part 3 of 3)
///
/// Unlike the technique/reference drawers (narrative how-to text), this
/// content is ingredient/topic-keyed — looked up by name rather than by
/// cooking method. Three separate tables:
///   - chefIngredientSubstitutions: "what can I use instead of X"
///   - chefFlavorPairings: "what goes with X" / classic flavor bridges
///   - chefCuisineProfiles: "make this taste like [region]"
///
/// Same injection pattern as the other two files: only the matching
/// entry/entries get pulled into a given AI call, not the whole table.
///
/// EDITING: Each value is a plain text block. Safe to tweak wording or
/// swap suggestions inside any entry without touching anything else.
library chef_curriculum_lookups;

// ---------------------------------------------------------------------
// INGREDIENT SUBSTITUTIONS
// Keyed by ingredient (lowercase, underscores). Grouped by category via
// comments only — the map itself is flat so lookup by ingredient name
// is a single step.
// ---------------------------------------------------------------------

const Map<String, String> chefIngredientSubstitutions = {
  // --- Vegetables: Leafy Greens ---
  'spinach': 'Subs: Swiss chard leaves, baby kale, beet greens. Flavor: mild, mineral, slightly earthy (chard/beet greens similar but more mineral). Texture: tender, wilts fast — chard stems need 2–3 min longer than spinach leaves, add stems first, leaves last 30 sec. Nutrition: chard/beet greens higher fiber, similar iron.',
  'kale': 'Subs: collard greens, Swiss chard, mustard greens. Flavor: collards earthy-bitter like kale; mustard greens peppery-hot. Texture: kale/collards fibrous and sturdy, mustard greens more tender. Nutrition: collards higher calcium, mustard greens higher vitamin C. Cook: collards need 5–10 min longer braise than kale; mustard greens wilt almost as fast as spinach.',
  'arugula': 'Subs: watercress, baby mustard greens, small amount of radicchio. Flavor: peppery, sharp, slightly bitter (watercress close, radicchio adds bitterness). Texture: tender, delicate leaves. Cook: best raw/added last — high heat destroys the peppery bite quickly.',
  'romaine_iceberg': 'Subs: napa cabbage, butter lettuce, endive. Flavor: mild, clean, faintly sweet. Texture: crunchy (romaine/iceberg/napa) vs soft (butter lettuce). Cook: not typically cooked; if grilling romaine/napa, quick high heat only (1–2 min/side).',
  'bok_choy': 'Subs: napa cabbage, tatsoi, broccoli rabe stems. Flavor: mild-sweet, slightly mustardy (rabe more bitter). Texture: crisp stem + tender leaf. Cook: separate stems (2–3 min) from leaves (30–60 sec) regardless of substitute.',

  // --- Vegetables: Root ---
  'carrot': 'Subs: parsnip, sweet potato (small dice), swede/rutabaga. Flavor: parsnip sweeter-earthier, swede more mineral/bitter. Texture: all firm and starchy-fibrous raw, soften similarly. Nutrition: sweet potato much higher vitamin A. Cook: parsnip cooks slightly faster; swede needs 5–10 min longer to soften.',
  'potato_starchy': 'Subs: sweet potato, parsnip, celeriac. Flavor: sweet potato sweet, celeriac nutty-celery. Texture: Russet fluffy cooked, celeriac denser/wetter. Cook: celeriac takes longer to mash smooth; sweet potato roasts faster (watch edges for burning).',
  'potato_waxy': 'Subs: turnip, jicama (raw/salad use only). Flavor: turnip peppery-mineral, jicama sweet-nutty raw. Texture: all hold shape well cooked/diced. Cook: turnip needs less cook time to reach fork-tender.',
  'beet': 'Subs: turnip + a pinch of sugar/honey, braised red cabbage. Flavor: turnip lacks beet\'s earthy sweetness, compensate with sugar. Cook: beets take notably longer to roast/boil (45–60 min) than turnip (20–25 min).',
  'celeriac': 'Subs: parsnip + a stalk of celery (flavor blend), turnip. Flavor: parsnip+celery combo approximates the nutty-celery profile. Cook: the blend cooks in a fraction of the time celeriac needs — cook parsnip normally, add minced raw celery in the last few minutes.',
  'ginger_root': 'Subs: galangal, ground ginger at ¼ the volume. Flavor: galangal more piney/citrus-forward, ground ginger more one-note hot. Cook: ground ginger should be bloomed in oil briefly, not added raw like fresh.',

  // --- Vegetables: Cruciferous ---
  'broccoli': 'Subs: broccolini, cauliflower, broccoli rabe. Flavor: broccolini milder-sweeter, rabe more bitter. Cook: broccolini cooks 2–3 min faster; blanch rabe first to tame bitterness.',
  'cauliflower': 'Subs: broccoli, romanesco, cabbage (for roasting). Flavor: romanesco nuttier, cabbage sweeter when roasted. Cook: romanesco cooks nearly identically; cabbage wedges need a similar 20–25 min roast.',
  'brussels_sprouts': 'Subs: quartered cabbage, broccoli florets. Flavor: cabbage milder-sweeter, less "sulfurous." Cook: cabbage wedges roast in similar time (20–25 min at 200°C) but char faster on cut edges — watch closely.',
  'cabbage_green': 'Subs: napa cabbage, savoy cabbage, shredded brussels sprouts. Flavor: napa milder-sweeter, savoy slightly earthier. Cook: napa cooks notably faster (about half the time) than dense green cabbage.',
  'radish': 'Subs: turnip (small dice), daikon. Flavor: daikon milder and sweeter, turnip peppery. Cook: daikon takes longer to become tender than a quick-cooking radish.',

  // --- Vegetables: Alliums ---
  'yellow_onion': 'Subs: shallot (1.5x qty for mild sweetness), white onion, leek (white part). Flavor: shallot sweeter/delicate, leek milder-grassier. Cook: shallots caramelize faster (less water); leeks need thorough washing for grit and cook slightly faster.',
  'garlic': 'Subs: garlic scapes (2–3x qty), garlic powder (⅛ tsp per clove), asafoetida (pinch, for allium-free needs). Flavor: scapes milder-grassier, powder more one-note. Cook: powder should be added earlier with dry spices, not bloomed the same way as fresh minced garlic (burns differently).',
  'scallion': 'Subs: chives (garnish use), leek thin-sliced (cooked use). Flavor: chives milder/more delicate, leek sweeter. Cook: chives are raw-only/garnish; leek needs 3–5 min sauté minimum.',
  'leek': 'Subs: scallion (white + light green, bulk qty), yellow onion (mild sub). Flavor: scallion sharper/more oniony, onion less delicate. Cook: onion needs slightly less time to soften than leek\'s fibrous layers.',

  // --- Vegetables: Nightshades ---
  'tomato_fresh': 'Subs: roasted red pepper (for sauces), tamarind + a touch of sugar (acid/umami depth). Flavor: roasted pepper sweeter/less acidic, tamarind sourer/tangier. Cook: roasted pepper needs no reduction time; dilute and briefly simmer tamarind to mellow it.',
  'tomato_canned_paste': 'Subs: sun-dried tomato paste, roasted red pepper paste. Flavor: sun-dried more concentrated-sweet-umami, pepper paste milder. Cook: sun-dried paste can scorch faster due to sugar concentration — bloom briefly, don\'t overcook. Use less than a 1:1 swap since sun-dried is more concentrated.',
  'bell_pepper': 'Subs: poblano (milder heat), zucchini (texture-only, different flavor). Flavor: poblano earthier with mild heat, zucchini neutral. Cook: poblano may need charring/peeling for some prep; zucchini cooks faster, watch for mush.',
  'eggplant': 'Subs: zucchini (lower absorption), portobello mushroom (umami-forward). Flavor: zucchini milder/waterier, portobello meatier-umami. Cook: zucchini needs less oil and less cook time; portobello sears faster and releases more liquid.',
  'chili_pepper_fresh': 'Subs: serrano (hotter, less qty), poblano (milder, more qty). Note: adjust quantity to Scoville level, not 1:1 — serrano is roughly 2x hotter than jalapeño.',

  // --- Vegetables: Gourds & Squashes ---
  'zucchini': 'Subs: yellow squash, cucumber (raw use only), eggplant. Flavor: yellow squash nearly identical, cucumber cool/fresh, eggplant earthier. Cook: never use cucumber as a like-for-like cooked sub; eggplant needs more oil and longer cook.',
  'butternut_squash': 'Subs: pumpkin, acorn squash, sweet potato. Flavor: all sweet-earthy-nutty, sweet potato slightly more caramel-forward. Cook: sweet potato cooks slightly faster; pumpkin similar timing to butternut.',
  'pumpkin': 'Subs: butternut squash, kabocha squash. Flavor: kabocha nuttier-sweeter, less watery. Cook: kabocha (skin on) cooks well without peeling, saving prep time.',
  'cucumber': 'Subs: zucchini (raw, young/small only), jicama. Flavor: jicama sweeter-nuttier, zucchini more neutral/grassy. Note: typically raw use for all three in this context.',

  // --- Fruits: Stone Fruits ---
  'peach': 'Subs: nectarine, apricot at 2:1 (more concentrated). Flavor: nectarine nearly identical, apricot more tart-concentrated. Cook: apricot may need slightly less cook time due to smaller size/higher sugar concentration.',
  'plum': 'Subs: apricot, cherry for baking (adjust sugar). Flavor: apricot milder-sweeter, cherry tarter/deeper color. Cook: factor in pitting time for cherries; similar roast/bake timing to plum.',
  'cherry': 'Subs: dried cranberry (reconstituted, for baking), chopped plum. Flavor: cranberry tarter/needs more sugar, plum sweeter/milder. Cook: reconstitute dried cranberries in warm liquid 10 min before using.',
  'apricot': 'Subs: peach at ½ qty (less concentrated), reconstituted dried apricot. Cook: dried apricot needs 15–20 min soak in warm water/juice before use in place of fresh.',

  // --- Fruits: Pomes ---
  'apple': 'Subs: pear, quince (cooked only, needs sugar). Flavor: pear milder/less acidic, quince tart-floral and astringent raw. Texture: quince is rock-hard raw, must be cooked. Cook: quince requires 40–60 min simmer to become tender/edible, never eaten raw.',
  'pear': 'Subs: firmer apple varieties for baking, Asian pear for raw/salad use. Cook: Asian pear resists softening under heat — not ideal where the recipe needs it to go fully soft.',
  'quince': 'Subs: apple + pear blend (approximates pectin + flavor). Cook: the blend cooks in about ⅓ the time quince requires.',

  // --- Fruits: Berries ---
  'strawberry': 'Subs: raspberry, chopped stone fruit (for baking bulk). Flavor: raspberry tarter/more floral, stone fruit sweeter/less acidic. Cook: raspberry breaks down faster under heat — reduce cook time slightly in jams/compotes.',
  'blueberry': 'Subs: blackberry, reconstituted dried cranberry. Flavor: blackberry earthier-tarter, cranberry sharper/less sweet. Cook: blackberries hold shape slightly better under heat than blueberries.',
  'raspberry': 'Subs: blackberry, chopped strawberry. Flavor: blackberry deeper/earthier, strawberry sweeter/milder. Cook: all break down at similar rates when heated.',
  'cranberry': 'Subs: dried cherry, pomegranate arils (fresh use). Flavor: cherry sweeter/less tart, pomegranate bright-tart-juicy. Cook: fresh cranberry needs 10–15 min simmer with sugar to break down into a sauce; dried cherry needs none.',

  // --- Fruits: Tropical ---
  'mango': 'Subs: peach (less tropical-forward), papaya. Flavor: peach milder/less floral, papaya more musky-sweet. Cook: papaya breaks down faster under heat than mango\'s firmer flesh.',
  'pineapple': 'Subs: mango (for sweetness, less acidity), citrus + a touch of vinegar (for marinade tang). Note: pineapple\'s bromelain enzyme actively tenderizes proteins — no substitute here replicates this functional property, only the flavor.',
  'banana': 'Subs: plantain (savory cooking only, not raw-sweet), avocado (baking, as a fat/moisture sub only, not sweetness). Cook: plantain requires actual cooking (fried/boiled) to be palatable, unlike ripe banana.',
  'papaya': 'Subs: mango, cantaloupe (salad/raw use). Note: papaya also contains papain, a tenderizing enzyme not replicated by substitutes.',

  // --- Proteins: Animal ---
  'chicken_breast': 'Subs: turkey breast, pork loin. Flavor: turkey nearly identical (slightly drier), pork loin milder-sweeter. Cook: pork loin can handle slightly higher heat before drying out; turkey behaves almost identically to chicken.',
  'chicken_thigh': 'Subs: duck leg (richer), pork shoulder (for braises). Flavor: duck much richer/fattier, pork shoulder milder/forgiving. Cook: render duck fat slowly first; pork shoulder needs a longer braise than chicken thigh.',
  'ground_beef': 'Subs: ground turkey, ground pork, lentil-mushroom blend (lower-fat/veg version). Flavor: turkey much milder, pork sweeter-fattier, lentil-mushroom earthier-umami. Cook: the lentil-mushroom blend needs less rendering time (no fat) but can scorch faster without it.',
  'beef_steak': 'Subs: bone-in pork chop, portobello mushroom cap (vegetarian). Flavor: pork milder-sweeter, portobello deeply umami/"meaty" but distinct. Cook: portobello needs less time and lower heat than steak — releases liquid, can overcook/turn rubbery fast. Portobello is much lower protein, pair with another protein source elsewhere in the dish.',
  'pork_shoulder_braising': 'Subs: beef chuck, lamb shoulder. Flavor: beef more mineral-forward, lamb distinctly gamier-richer. Cook: comparable braise times (2.5–3.5 hrs) across all three.',
  'lamb': 'Subs: beef (milder, less gamey), goat (closest actual flavor match). Note: goat is notably leaner than lamb, needs a shorter high-heat cook or a moist/braised method to avoid toughness from its leanness.',

  // --- Proteins: Seafood ---
  'salmon': 'Subs: Arctic char, trout. Flavor: char nearly identical, trout milder/less rich. Cook: all cook at similar rates and doneness cues (opaque, flakes easily).',
  'white_fish': 'Subs: haddock, tilapia, pollock. Note: thinner fillets (tilapia) cook notably faster — watch closely to avoid overcooking.',
  'shrimp': 'Subs: scallops (larger, sweeter), firm white fish (cubed). Cook: scallops need a hard sear and very short cook (1–2 min/side) to avoid rubberiness — a different technique demand than shrimp.',
  'tuna_steak': 'Subs: swordfish, salmon (different fat profile). Flavor: swordfish meaty-mild (closest texture match), salmon much richer/fattier. Cook: swordfish behaves almost identically to tuna for searing; watch salmon for faster fat rendering.',
  'mussels_clams': 'Subs: interchangeable with each other near 1:1, or increase aromatics if omitting entirely. Cook: similar steam-open cook times (5–8 min) for both.',

  // --- Proteins: Plant (tofu/tempeh/legumes) ---
  'firm_tofu': 'Subs: tempeh, extra-firm paneer-style pressed cheese (non-vegan). Flavor: tempeh nuttier/more fermented-funky, tofu neutral (takes on marinade flavor). Cook: tempeh benefits from a brief steam/simmer before pan-searing to mellow bitterness — tofu doesn\'t need this step.',
  'silken_tofu': 'Subs: soaked/blended cashew cream, Greek yogurt (non-vegan). Cook: cashew cream needs no cooking; yogurt can split if boiled directly — add off high heat.',
  'black_beans': 'Subs: kidney beans, pinto beans. Cook: nearly identical cook times if using dried; canned versions all interchangeable 1:1.',
  'chickpeas': 'Subs: white beans (cannellini, navy), lentils (texture-different applications). Cook: lentils cook significantly faster (20–30 min) than dried chickpeas (60–90 min).',
  'lentils_brown_green': 'Subs: split peas, quinoa (texture-different, bulk/protein in salads). Cook: split peas take slightly longer than lentils; quinoa cooks faster (15 min).',

  // --- Eggs & Dairy Alternatives ---
  'egg_binding': 'Subs: flax egg (1 tbsp ground flax + 3 tbsp water, rest 5 min), unsweetened applesauce (¼ cup, for baking). Cook: flax egg needs the 5-min rest to gel before use; applesauce works best in sweeter baked goods only.',
  'egg_leavening_meringue': 'Subs: aquafaba (3 tbsp chickpea liquid = 1 egg white). Cook: aquafaba takes slightly longer to whip to stiff peaks than egg whites — be patient, don\'t add sugar too early.',
  'milk_dairy': 'Subs: oat milk (best for baking/neutral use), almond milk (lighter), soy milk (highest protein match). Cook: oat milk behaves most predictably under heat (less separation risk) than almond milk in hot sauces.',
  'butter': 'Subs: ghee/clarified butter (non-vegan, higher smoke point), coconut oil (vegan). Cook: ghee\'s higher smoke point (~250°C) makes it more forgiving for high-heat searing than regular butter.',
  'heavy_cream': 'Subs: full-fat canned coconut cream (vegan), blended cashew cream. Cook: coconut cream can separate/curdle if boiled too aggressively — bring sauces to a gentle simmer only.',

  // --- Fresh Herbs: Soft ---
  'basil': 'Subs: mint (smaller qty, cooler/sweeter), Thai basil (closer, more anise-forward). Note: add raw/at the very end — heat destroys volatile aromatics fast.',
  'cilantro': 'Subs: flat-leaf parsley + a squeeze of lime (approximates the bright-citrusy note), Thai basil. Note: same rule — add raw/at the very end, never cooked for extended time.',
  'parsley': 'Subs: cilantro (if the flavor profile fits), chervil (milder, slightly anise-like). Note: chervil is even more heat-sensitive than parsley — add at the absolute last moment.',
  'mint': 'Subs: basil (savory dishes), a small amount of tarragon (different but complementary bright note). Note: all soft herbs follow the "add last" rule.',
  'dill': 'Subs: fennel fronds, tarragon. Flavor: fennel fronds milder anise-note, tarragon stronger anise-licorice. Cook: fennel fronds hold up marginally better to brief heat than dill.',
  'chives': 'Subs: scallion green part (finely minced), garlic scapes (minced). Note: garnish-only across the board — none of these should be cooked.',

  // --- Fresh Herbs: Hard/Woody ---
  'rosemary': 'Subs: thyme (milder, more versatile), sage (earthier, use less). Note: woody herbs can handle extended cook times (braises, roasts) unlike soft herbs — that\'s their defining trait.',
  'thyme': 'Subs: oregano (more assertive), rosemary (stronger, use less). Cook: oregano can be added slightly later than thyme since it\'s a touch less heat-tolerant, but still a long-cook herb.',
  'oregano': 'Subs: marjoram (gentler, sweeter version), thyme. Cook: marjoram is slightly more delicate — can be added a bit later in a long cook than oregano.',
  'sage': 'Subs: rosemary (use less, more piney), thyme (milder, all-purpose). Note: sage crisps beautifully when fried in butter — rosemary doesn\'t crisp the same way, this specific technique isn\'t transferable 1:1.',
  'bay_leaf': 'Subs: extra thyme + a pinch of nutmeg (approximates the depth in stocks/braises). Note: approximation only, bay\'s specific flavor compound is hard to replicate directly. Works identically as a long-simmer aromatic; remove any whole substitute sprigs the same way.',

  // --- Spices: Warm ---
  'cinnamon': 'Subs: allspice (¾ qty, more complex), nutmeg (small qty, more concentrated). Cook: bloom in fat early for savory dishes, or per standard baking timing for sweets.',
  'nutmeg': 'Subs: allspice (small qty), mace (nearly identical — mace is nutmeg\'s outer covering, the closest possible match). Note: freshly grated nutmeg/mace loses potency fast once exposed to air, use slightly more pre-ground jar version to compensate.',
  'allspice': 'Subs: equal parts cinnamon + clove + nutmeg (classic DIY blend closely approximates its naturally complex profile).',
  'clove': 'Subs: allspice (milder), a small pinch of five-spice powder if the flavor direction fits. Note: clove is very potent — err toward less when substituting, adjust up as needed.',

  // --- Spices: Pungent ---
  'black_pepper': 'Subs: white pepper (milder, more one-note hot, less floral), pink peppercorn (fruitier, milder). Note: white pepper is traditional in pale sauces for visual reasons, not just flavor — good default swap when color matters.',
  'chili_powder_ground': 'Subs: paprika + a small pinch of cayenne (controls heat separately from color/flavor). Cook: bloom briefly in fat like other ground spices, watch closely as it burns/turns bitter fast.',
  'mustard_seed_whole': 'Subs: ground mustard at ¼ the volume (no tempering/popping effect), horseradish (small amount, different application). Cook: whole seed needs tempering/popping in hot oil (10–20 sec); ground mustard skips this step entirely.',
  'horseradish': 'Subs: wasabi (closer, more intense, use less), strong Dijon mustard. Note: wasabi\'s heat dissipates faster than horseradish\'s — add close to serving either way.',

  // --- Spices: Earthy ---
  'cumin': 'Subs: ground coriander (milder, more citrusy-earthy), caraway (sharper, more distinct). Cook: bloom briefly in oil to unlock full aromatic potential, same as cumin itself.',
  'turmeric': 'Subs: saffron (color match, very different flavor, use sparingly), curry powder (already contains turmeric, adjust other spices down). Cook: saffron blooms in warm liquid, not oil, unlike turmeric. Note: turmeric\'s curcumin (anti-inflammatory compound) isn\'t present in the substitutes.',
  'coriander_ground': 'Subs: cumin (earthier, less citrusy), caraway (small qty). Cook: same bloom timing as cumin.',
  'paprika_sweet': 'Subs: smoked paprika (adds smokiness — not a neutral sub), ground ancho chili (mild, fruity-smoky). Note: all ground peppers bloom and can scorch/bitter quickly at high heat — add with care.',

  // --- Spices: Floral ---
  'saffron': 'Subs: turmeric + a pinch of sugar (color-only approximation, no floral note), safflower/"Mexican saffron" (closer floral-mild profile). Cook: saffron must bloom in warm (not boiling) liquid for several minutes to release color/flavor — substitutes skip this step.',
  'cardamom': 'Subs: cinnamon + a small pinch of nutmeg (rough approximation), allspice (small qty). Note: neither fully replicates cardamom\'s distinct floral-citrus complexity. Ground cardamom loses potency fast — buy whole pods and grind fresh when possible.',
  'lavender_culinary': 'Subs: rosemary (small qty, very different but floral-piney), dried rose petals (closer floral note). Note: use culinary-grade only — ornamental/non-food-grade dried flowers are not safe substitutes.',
  'rose_water': 'Subs: orange blossom water (both floral waters, different flower source, similar function — slightly more citrus-forward). Note: both are potent, start with half the called-for amount and adjust up.',

  // --- Acids: Juices ---
  'lemon_juice': 'Subs: lime juice, white wine vinegar diluted 1:1 with water. Flavor: lime slightly more floral/less sharp, vinegar sharper/less fruity. Note: acid should generally be added at the end of cooking to preserve brightness across all three.',
  'lime_juice': 'Subs: lemon juice, rice vinegar (milder, slightly sweet). Note: rice vinegar\'s mildness means you may need slightly more volume to hit the same acidity level.',
  'orange_juice': 'Subs: tangerine/clementine juice, lemon juice + a touch of honey (for marinades needing OJ\'s sweet-acid balance). Cook: reducing orange juice for sauces takes notably longer than a lemon+honey mix since OJ has more water content.',

  // --- Acids: Zests ---
  'lemon_zest': 'Subs: lime zest, orange zest (sweeter, less sharp). Note: zest is best added raw/at the end — prolonged heat cooks off the bright volatile oils.',
  'orange_zest': 'Subs: tangerine zest (closest sweet-floral match), lemon zest (sharper, less sweet). Note: same "add at the end" rule as lemon zest.',

  // --- Acids: Vinegars ---
  'red_wine_vinegar': 'Subs: sherry vinegar (deeper/nuttier), balsamic (sweeter, use less). Note: balsamic can scorch/burn if reduced too aggressively due to sugar content — watch closely.',
  'white_wine_vinegar': 'Subs: champagne vinegar (very close, slightly more delicate), rice vinegar (noticeably milder). Note: rice vinegar\'s mildness may need volume adjustment upward for the same punch.',
  'balsamic_vinegar': 'Subs: red wine vinegar + a touch of honey/brown sugar (approximates the sweet-tart balance, loses aged-wood complexity). Note: this blend reduces faster than true aged balsamic — less natural sugar concentration to start.',
  'rice_vinegar': 'Subs: apple cider vinegar diluted slightly (fruitier/sharper), white wine vinegar (cleaner, less sweet). Note: rice vinegar\'s natural mild sweetness means straight substitutes may need a small pinch of sugar to match.',

  // --- Acids: Fermented ---
  'tamarind_paste': 'Subs: lime juice + a touch of brown sugar + a pinch of soy sauce (approximates sour-sweet-umami complexity). Note: approximation only, tamarind\'s specific fruity-sour-funky depth is hard to replicate exactly. The substitute blend needs no simmering to "open up" the way tamarind paste sometimes does.',
  'fish_sauce': 'Subs: soy sauce + a small pinch of anchovy paste (closest), or soy sauce alone (vegetarian-friendlier but less complex). Cook: added near the end as a finishing/seasoning addition, not simmered for long periods, same as fish sauce.',
  'yogurt_marinade': 'Subs: buttermilk (tangier/thinner), kefir (similar tang, slightly effervescent). Note: all three tenderize proteins similarly in a marinade via mild acidity + enzymes.',

  // --- Grains ---
  'white_rice': 'Subs: jasmine rice, basmati rice. Flavor: jasmine more floral-fragrant, basmati nuttier with more distinct grain separation. Cook: basmati benefits from a rinse + soak; similar cook times (15–18 min) for both.',
  'brown_rice': 'Subs: farro, quinoa. Flavor: farro nuttier-chewier, quinoa lighter/slightly grassy. Nutrition: quinoa is a complete protein, farro higher fiber. Cook: farro can take slightly longer (25–30 min); quinoa cooks faster (15 min).',
  'pasta_wheat': 'Subs: rice noodles (gluten-free), chickpea pasta (higher protein). Cook: rice noodles cook much faster (often just a soak, not a boil) — watch closely to avoid mush.',
  'couscous': 'Subs: quinoa, bulgur wheat. Flavor: bulgur nuttier/earthier, quinoa lighter/more neutral. Cook: couscous is nearly instant (5 min steep); bulgur needs 10–15 min simmer, quinoa needs 15 min simmer.',
  'quinoa': 'Subs: millet, bulgur (not gluten-free). Nutrition: quinoa remains the only true complete protein of the three. Cook: millet\'s cook time is comparable to quinoa (15–20 min).',
  'oats_rolled': 'Subs: quinoa flakes, buckwheat groats (for porridge use). Nutrition: buckwheat higher protein, complete amino acid profile. Cook: buckwheat groats need slightly longer to soften fully than rolled oats.',

  // --- Fats & Oils ---
  'extra_virgin_olive_oil': 'Subs: avocado oil (higher smoke point, more neutral), good-quality sunflower oil. Note: EVOO is best reserved for finishing/raw use (low smoke point ~190°C); avocado oil (~270°C) is the better direct high-heat sub.',
  'neutral_cooking_oil': 'Subs: refined avocado oil, refined sunflower oil, refined peanut oil — all share similarly high smoke points (200°C+), largely interchangeable for frying/searing.',
  'sesame_oil_toasted': 'Subs: peanut oil + a few drops of tahini (rough aromatic approximation). Note: toasted sesame oil should never be used as the primary high-heat cooking fat regardless of substitute — it\'s a finishing oil with a low smoke point.',
  'coconut_oil': 'Subs: butter (richer dairy note, non-vegan), refined coconut oil (neutral flavor, same fat behavior). Note: coconut oil\'s melting point (~24°C) is close to butter\'s — both behave similarly in baking applications.',

  // --- Sweeteners ---
  'white_sugar': 'Subs: honey at ¾ qty (reduce other liquid slightly), maple syrup at ¾ qty (same adjustment). Cook: liquid sweeteners caramelize/brown faster than granulated sugar — lower oven temp by ~10°C in baking to compensate.',
  'brown_sugar': 'Subs: white sugar + 1 tbsp molasses per cup (DIY approximation), coconut sugar. Cook: coconut sugar behaves very similarly under heat to brown sugar in most applications.',
  'honey': 'Subs: maple syrup (deeper/less floral), agave nectar (very neutral-sweet, sweeter per volume — use slightly less). Cook: all three brown/caramelize at roughly similar rates, watch closely near the end of any reduction.',
  'maple_syrup': 'Subs: honey, brown rice syrup (very neutral, milder). Cook: brown rice syrup doesn\'t caramelize/brown as readily as maple syrup — expect a paler final color in baked goods.',

  // --- Ferments, Umami & Pantry ---
  'soy_sauce': 'Subs: tamari (gluten-free, nearly identical), coconut aminos (milder, sweeter, significantly lower sodium). Note: coconut aminos may need a pinch of added salt to match soy sauce\'s seasoning power.',
  'miso_paste': 'Subs: tahini + a splash of soy sauce (rough umami-savory approximation), or soy sauce alone (thinner, less complex). Note: approximation only, miso\'s fermented depth is hard to fully replicate. Add off high heat/at the end to preserve live cultures and delicate flavor — same rule applies to the substitute.',
  'parmesan_umami_booster': 'Subs: nutritional yeast (vegan, milder-nuttier), pecorino (sharper, saltier). Note: nutritional yeast doesn\'t brown/crisp under a broiler the way parmesan does — different finishing behavior.',
  'worcestershire_sauce': 'Subs: soy sauce + a small splash of vinegar + a pinch of sugar (rough approximation of the sweet-sour-umami balance). Works the same as a finishing/seasoning splash, not a long-simmer ingredient in either case.',
  'stock_broth': 'Subs: bouillon cube/paste + water (concentrated, adjust salt down elsewhere), vegetable scrap stock (zero-waste option, milder/more variable). Cook: scrap stock benefits from a longer simmer (45–60 min) to fully extract flavor from vegetable trim.',
};

// ---------------------------------------------------------------------
// FLAVOR & AROMA PAIRINGS
// Classic ingredient trios/combos with the flavor logic behind them and
// how to swap a component without losing the underlying "bridge."
// ---------------------------------------------------------------------

const Map<String, String> chefFlavorPairings = {
  'cumin_coriander': 'Cumin + Coriander — warm-earthy-smoky (cumin) balanced by bright-citrusy-floral (coriander); together cover both the low and high end of the aromatic spectrum. Backbone of garam masala, taco seasoning, many curry bases. Swap cumin for caraway (sharper, more anise-forward); swap coriander for a small amount of citrus zest for the bright lift alone. The logic holds as long as one earthy-warm and one bright-citrusy element remain.',
  'basil_garlic_tomato': 'Basil + Garlic + Tomato — the flavor bridge under most Italian/Mediterranean cooking: tomato\'s umami-acidity, rounded by garlic\'s pungent depth, cut through by basil\'s sweet-peppery oils. Acid + aromatic + herb is a template that repeats across cuisines with different specifics. Swap basil for oregano/marjoram for a more savory, rustic direction; swap tomato for roasted red pepper for a different acid source, keeping garlic constant. Garlic is the least swappable — its pungent depth is structurally load-bearing.',
  'ginger_soy_sesame': 'Ginger + Soy + Sesame — the East Asian equivalent of basil-garlic-tomato: ginger\'s warm peppery-citrus brightness, soy\'s deep salty umami, sesame\'s nutty richness/aroma. Hits sweet/salty/umami/aromatic simultaneously — appears in marinades, dressings, stir-fry sauces across Chinese/Japanese/Korean cooking. Swap soy for tamari (near-identical, gluten-free) or coconut aminos (milder, needs a pinch of salt); swap sesame oil for a few drops of tahini in neutral oil. Ginger is hardest to replace cleanly — galangal is closest but shifts piney-citrus.',
  'garlic_onion_chili': 'Garlic + Onion + Chili — the aromatic base of an enormous range of global cuisines, hitting pungent-sweet (onion), pungent-sharp (garlic), and heat (chili) simultaneously. Swap fresh chili for dried/ground (reduce quantity, more concentrated) or a few dashes of hot sauce added later. Keep onion and garlic paired even when substituting — shallot can stand in for onion while garlic stays constant.',
  'rosemary_garlic_lemon': 'Rosemary + Garlic + Lemon — classic Mediterranean/roasting combination for lamb, chicken, roasted potatoes: rosemary\'s piney intensity stands up to high heat, garlic adds depth, lemon cuts richness. Swap rosemary for thyme (milder, more all-purpose); swap lemon for white wine vinegar for the acid cut without the citrus top note. Garlic is the connective tissue in most versions.',
  'chili_lime_cilantro': 'Chili + Lime + Cilantro — backbone of Latin American and Southeast Asian fresh salsas/finishing garnishes: heat, sharp acid brightness, fresh citrusy-green herb. Built specifically for RAW/finishing use — loses most character under sustained heat. Swap cilantro for flat-leaf parsley + extra lime zest (common swap for cilantro-aversion); swap lime for lemon (less floral, sharper). Chili variety can shift (jalapeño/serrano/Thai) to control heat while preserving the logic.',
  'fennel_orange_olive_oil': 'Fennel + Orange + Olive Oil — Mediterranean/Italian classic: fennel\'s anise-forward crunch/sweetness pairs with orange\'s bright citrus sweetness, tied together by peppery olive oil. Swap fennel for celery + a small pinch of fennel seed if fresh bulb isn\'t available; swap orange for blood orange or tangerine. Olive oil is best kept as-is — its peppery finish is part of the specific bridge.',
  'cinnamon_clove_nutmeg': 'Cinnamon + Clove + Nutmeg (warm baking spice trio) — layers at different intensities: cinnamon\'s sweet-woody base, clove\'s sharp penetrating warmth, nutmeg\'s nutty-musky depth. The "holiday baking" signature from pumpkin pie to mulled wine. Swap the whole trio for allspice in a pinch (flatter, less layered); swap nutmeg for mace (nearly identical). Clove is the most potent — reduce it first if the blend tastes too sharp/medicinal.',
  'miso_butter_garlic': 'Miso + Butter + Garlic — modern fusion staple: miso\'s fermented umami-saltiness + butter\'s richness + garlic\'s pungency creates an intensely savory, almost "meaty" flavor bomb, often finishing pasta, roasted vegetables, or grilled proteins. Swap miso for grated parmesan + a splash of soy sauce for a similar umami-salt hit; swap butter for high-quality olive oil for a dairy-free version (less rich mouthfeel). Garlic remains the connective aromatic in most variations.',
  'tomato_basil_balsamic': 'Tomato + Basil + Balsamic — extension of the basil-tomato bridge with balsamic\'s sweet-tart concentrated acidity added; the logic behind caprese-style dishes. Swap balsamic for red wine vinegar + a touch of honey; swap basil for a small amount of mint for a cooler, less peppery variation.',
  'curry_leaf_mustard_coconut': 'Curry Leaf + Mustard Seed + Coconut — South Indian tempering (tadka) foundation: mustard seed popped in hot oil gives a sharp nutty pop, curry leaf a distinct citrusy-nutty aroma, coconut rounds it out with sweetness/richness. Curry leaf is genuinely difficult to substitute — closest approximation is bay leaf + a bit of lime zest (imperfect). Swap mustard seed for ground mustard added later (loses the tempering "pop" texture but keeps some pungency). Coconut milk can be swapped for cashew cream for a different but still rich finishing texture.',
  'smoked_paprika_cumin_oregano': 'Smoked Paprika + Cumin + Oregano — backbone of many Spanish, Mexican, Tex-Mex spice blends: smoky-sweet base, earthy warmth, herbaceous bitter counterpoint that keeps it from being one-dimensional. Swap smoked paprika for regular paprika + a few drops of liquid smoke (changes the flavor meaningfully — smoke is doing real work). Swap oregano for marjoram for a gentler, sweeter note.',
  'dill_lemon_garlic': 'Dill + Lemon + Garlic — Northern European/Mediterranean bridge for fish, yogurt sauces, potato dishes: dill\'s fresh anise-grassy character brightened by lemon, deepened by garlic, light enough not to overwhelm delicate proteins. Swap dill for fennel fronds or tarragon; swap lemon for white wine vinegar for a sharper, less floral acid note. Specifically suited to delicate applications — doesn\'t hold up as well under long, high-heat cooking as heartier pairings.',
  'chili_chocolate_cinnamon': 'Chili + Chocolate + Cinnamon — found in Mexican mole sauces: chili\'s heat and chocolate\'s bitter-sweet richness create a surprising but balanced depth, cinnamon bridges the two. A masterclass in how heat and sweetness/bitterness can support rather than clash. Swap dark chocolate for unsweetened cocoa powder + a touch of sugar; swap cinnamon for allspice. Chili variety (ancho, guajillo, chipotle) can shift the smoke/heat/fruitiness balance while keeping the core bridge intact.',
  'anchovy_garlic_chili': 'Anchovy + Garlic + Chili (Aglio e Olio base) — anchovy dissolves into oil for pure savory umami without a distinct fishy presence once cooked; garlic is the aromatic backbone; chili flakes add background heat. An intensely flavorful base for pasta/vegetable dishes with very few ingredients. Swap anchovy for a small amount of miso paste (vegetarian-friendlier) or a splash of fish sauce (functionally closest). Chili flake quantity is the easiest lever to adjust heat without disturbing the base.',
  'ginger_garlic_scallion': 'Ginger + Garlic + Scallion (Chinese aromatic trio) — the default base for most Chinese stir-fries and braises: ginger\'s peppery warmth cuts richness/gaminess, garlic adds pungent depth, scallion ties them together without overpowering. Swap scallion for a small amount of leek white part (milder, needs slightly longer to soften). Ginger is hardest of the three to replace cleanly — galangal is closest but shifts toward citrus-piney.',
  'vanilla_cinnamon_brown_sugar': 'Vanilla + Cinnamon + Brown Sugar (classic "warm dessert" trio) — vanilla\'s sweet floral roundness anchors it, cinnamon adds woody warmth, brown sugar\'s molasses notes deepen with a caramel undertone. Appears across baked goods, oatmeal, spiced beverages globally. Swap vanilla extract for a scraped vanilla bean (more intense/floral) or maple extract; swap brown sugar for coconut sugar for a similar caramel depth with a slightly different mineral undertone.',
};

// ---------------------------------------------------------------------
// GLOBAL CUISINE FLAVOR PROFILES
// Keyed by region. Each block: aromatic base, core herbs/spices, primary
// acids, umami/salt sources, fats/cooking mediums, and key substitutions
// for when regional items are unavailable.
// ---------------------------------------------------------------------

const Map<String, String> chefCuisineProfiles = {
  'mediterranean': 'Mediterranean — Aromatic base: onion + garlic, often with fennel or celery, olive oil as the cooking medium from the start. Herbs/spices: oregano, rosemary, thyme, bay leaf, basil, black pepper, sometimes saffron (Spain/Southern Italy). Acids: lemon juice and zest, red or white wine vinegar, sometimes capers. Umami/salt: anchovy, parmesan/pecorino, olives, sun-dried tomato, cured meats (prosciutto, pancetta). Fat: extra virgin olive oil dominant, butter in some Northern Mediterranean/Provençal dishes. Key subs: anchovy → miso or fish sauce; pecorino → parmesan or nutritional yeast; capers → chopped green olives; saffron → turmeric + pinch of sugar (color only, not flavor).',
  'middle_eastern': 'Middle Eastern — Aromatic base: onion + garlic, frequently with a warm spice bloom (cumin, coriander) built directly in. Herbs/spices: za\'atar (thyme, sumac, sesame blend), sumac, cumin, cinnamon, allspice, mint, parsley. Acids: lemon juice, pomegranate molasses, sumac (dual-purpose spice and acid). Umami/salt: tahini, preserved lemon, labneh/strained yogurt, olives. Fat: olive oil, clarified butter (samneh/ghee-style), tahini as a finishing fat. Key subs: sumac → lemon zest + a small pinch of salt (approximates tang, loses fruity-tart specificity); pomegranate molasses → reduced balsamic + lemon juice blend; preserved lemon → fresh lemon zest + a pinch of extra salt, rested 10 minutes.',
  'indian': 'Indian — Aromatic base: onion + garlic + ginger ("ginger-garlic paste"), often bloomed with whole spices in hot oil/ghee first (tempering/tadka). Herbs/spices: cumin, coriander, turmeric, garam masala, mustard seed, curry leaf, cardamom, fresh cilantro. Acids: tamarind, lime juice, yogurt (marinades and finished dishes), tomato (acid + body). Umami/salt: yogurt, ghee, occasionally dried fish/shrimp paste in coastal regional cooking. Fat: ghee, mustard oil (regionally, especially Bengal), neutral vegetable oil. Key subs: curry leaf → bay leaf + lime zest (imperfect but closest common-pantry approximation); ghee → butter or neutral oil with a pinch of salt reduced; tamarind → lime juice + brown sugar + a small pinch of soy sauce; garam masala → DIY blend of cumin, coriander, cardamom, cinnamon, clove, black pepper.',
  'southeast_asian': 'Southeast Asian — Aromatic base: garlic + shallot + chili, often ground into a paste with lemongrass and galangal (Thai) or a simpler garlic-shallot base (Vietnamese, many Indonesian dishes). Herbs/spices: lemongrass, galangal, Thai basil, kaffir lime leaf, cilantro, star anise (Vietnamese pho-style). Acids: lime juice, tamarind, rice vinegar. Umami/salt: fish sauce, shrimp paste, soy sauce, palm sugar (balances rather than purely sweetens). Fat: coconut milk/oil, neutral vegetable oil, occasionally lard in some Vietnamese/Filipino dishes. Key subs: fish sauce → soy sauce + a pinch of anchovy paste; galangal → ginger (different, more one-note hot vs galangal\'s citrus-pine complexity); kaffir lime leaf → lime zest (loses floral depth, keeps citrus brightness); palm sugar → brown sugar or coconut sugar.',
  'japanese': 'Japanese — Aromatic base: minimal in the Western sense — dashi (kombu + bonito stock) functions as the flavor base rather than a sautéed vegetable-aromatic mix; ginger and scallion used more as accents. Herbs/spices: shiso, sansho pepper, togarashi (chili blend), wasabi, ginger. Acids: rice vinegar, yuzu juice (where available), citrus (sudachi, yuzu). Umami/salt: soy sauce, miso, dashi (kombu/bonito), katsuobushi (bonito flakes) — arguably the most explicitly umami-forward flavor architecture of any global tradition. Fat: neutral oil for frying (tempura), toasted sesame oil as a finishing note, minimal butter/dairy historically. Key subs: dashi → a light vegetable or mushroom stock with a small splash of soy sauce; yuzu → a blend of lemon + lime + a touch of orange juice; katsuobushi → a small amount of soy sauce + mushroom powder for a vegetarian umami approximation.',
  'latin_american': 'Latin American — Aromatic base: sofrito (onion, garlic, bell pepper, tomato — Caribbean/Puerto Rican) or the Mexican base of onion, garlic, and charred/roasted chilies. Herbs/spices: cumin, Mexican oregano (more citrusy-pungent than Mediterranean oregano), cilantro, achiote/annatto, chili varieties (ancho, guajillo, chipotle). Acids: lime juice, vinegar-based hot sauces, tomatillo (tart/acidic base for salsa verde). Umami/salt: cotija/queso fresco, epazote (regionally), charred chilies add a smoky depth that functions umami-adjacent. Fat: lard (traditional), neutral vegetable oil, occasionally butter in some Central/South American baking. Key subs: Mexican oregano → regular oregano + a small pinch of cumin; achiote → paprika + a small pinch of turmeric for color (flavor won\'t fully match); tomatillo → green tomato + a splash of lime juice; lard → a neutral oil or butter blend, accepting a flavor shift.',
  'north_american': 'North American — Aromatic base: mirepoix (onion, carrot, celery) — the direct Western-European-derived base underlying most classic North American savory cooking (soups, stews, gravies). Herbs/spices: thyme, bay leaf, black pepper, paprika, chili powder (Tex-Mex-influenced regions), dill (upper Midwest/German-influenced regions). Acids: cider vinegar, lemon juice, mustard (both condiment and cooking acid/emulsifier). Umami/salt: Worcestershire sauce, bacon/pork fat rendering, cheddar and other aged cheeses, ketchup (a genuine umami-sweet-acid contributor in many home-cooking applications). Fat: butter, rendered animal fats (bacon, beef tallow), neutral vegetable oil. Key subs: Worcestershire → soy sauce + vinegar + a pinch of sugar; bacon fat → butter or a neutral oil with a small pinch of smoked paprika; buttermilk (biscuits/dressings) → milk + a splash of vinegar or lemon juice, rested 5–10 minutes.',
  'northern_european': 'Northern European — Aromatic base: onion + leek, often built slowly at low heat (sweated, not browned) as the foundation for soups and braises. Herbs/spices: dill, caraway, juniper berry, bay leaf, allspice, black pepper. Acids: vinegar (heavy in pickling traditions), lingonberry or other tart berry sauces, mustard. Umami/salt: cured/smoked fish (herring, gravlax-style salmon), aged cheeses, rye bread as a textural-umami component. Fat: butter dominant, rendered pork fat in some Baltic/Scandinavian traditions. Key subs: juniper berry → a small pinch of rosemary + black pepper; lingonberry → cranberry sauce (very close, slightly more tart); caraway → fennel seed or cumin depending on whether an anise-leaning or earthy-leaning result is wanted.',
  'central_european': 'Central European — Aromatic base: onion + garlic, frequently paired with paprika bloomed directly in fat (Hungarian tradition) or built into a roux-thickened base (Austrian/German/Czech tradition). Herbs/spices: paprika (sweet and hot), caraway, marjoram, dill, black pepper, nutmeg (cream-based dishes). Acids: sour cream, vinegar (pickling, braised cabbage), lemon juice in lighter preparations. Umami/salt: smoked/cured pork (bacon, speck, kielbasa), aged Alpine cheeses (Gruyère, Appenzeller), mushrooms (dried, for depth in stocks/sauces). Fat: butter, lard, rendered pork fat. Key subs: sour cream → Greek yogurt (tangier, lower fat) or crème fraîche (richer, closer match); Gruyère/Appenzeller → a good aged cheddar or Comté as a reasonably close Alpine-style melting sub; paprika (sweet) → smoked paprika at reduced quantity if a smoky note is acceptable, or bell pepper powder for a milder color-only sub.',
  'west_east_african': 'West/East African — Aromatic base: onion + garlic + ginger, frequently built with tomato and a chili paste base (West Africa), or onion + garlic + berbere spice blend bloomed in niter kibbeh/spiced clarified butter (Ethiopian/East African). Herbs/spices: berbere (Ethiopian chili-spice blend), suya spice (West African, peanut-forward), grains of paradise, ginger, scotch bonnet chili. Acids: lime juice, tamarind (regionally), tomato as both acid and body. Umami/salt: dried/smoked fish, peanut (fat and umami-savory base in West African groundnut stews), fermented locust bean (iru/dawadawa). Fat: palm oil (West Africa, distinct red color/flavor), niter kibbeh/spiced clarified butter (East Africa/Ethiopia), peanut oil. Key subs: palm oil → annatto/achiote oil for similar red color, or neutral oil + a small pinch of paprika for color only; berbere → DIY blend of chili powder, fenugreek, cardamom, ginger, and a pinch of cinnamon; niter kibbeh → ghee + a small pinch of ground cardamom and cumin bloomed briefly; scotch bonnet → habanero (very close relative, nearly interchangeable heat and fruitiness).',
};