import '../models/food.dart';
import '../utils/fuzzy.dart';

/// Where a food can go in a meal plan: its role (main, carb, veg, fruit, drink, breakfast dish, snack, dessert), the meals it suits, and
/// health tags (fried, processed, highSugar, refined, highSodium) that the plan uses to keep it away from people it does not suit.
class MealProfile {
  final String role;
  final List<String> meals;
  final List<String> tags;
  const MealProfile(this.role, this.meals, this.tags);
}

/// Decides, from a food's name, serving and nutrition numbers, whether and where it can appear in a generated meal plan. The curated
/// foods carry this information by hand; the ~2,700 foods of the searchable list (team list, Indian Nutrient Databank, USDA SR Legacy)
/// do not, so this puts them through the same door with transparent rules (below).
///
/// A food is left out of plans (returns null) when it is not something a person eats as a meal or a side:
///  - raw meat, fish, poultry or eggs, offal and skin, dry uncooked grains and pulses, flours;
///  - oils, fats, sauces, dressings, sugar, spices, powders, supplements, baby food;
///  - pork, ham, bacon and similar, alcohol (many members cannot eat them; the plan never suggests them);
///  - a serving under 25 g or measured in spoonfuls, a serving over 700 g, an energy figure outside 15 to 900 kcal;
///  - numbers that contradict themselves: energy that differs from 4 x protein + 4 x carbohydrate + 9 x fat by more than 30%,
///    or a single serving with more than 90 g of fat, 120 g of protein or 200 g of carbohydrate.
///
/// None of the three lists has sodium, sugar or fibre figures, so the health tags come from the name alone (a pickle is high in salt,
/// a juice is high in sugar). They are a guess, and the plan treats a tagged food as unsuitable for people who need to avoid that tag.
class MealRoles {
  MealRoles._();

  /// A word list as a set that holds each word, its singular ("cookies" -> "cooky" is not enough on its own) and its plural.
  static Set<String> _w(String s) => {
        for (final w in s.split(' ').where((w) => w.isNotEmpty)) ...[w, Fuzzy.singular(w), if (!w.endsWith('s')) '${w}s'],
      };

  static final _never = _w('oil oils shortening margarine lard tallow suet dripping dressing sauce sauces gravy syrup syrups sugar sugars sweetener '
      'sweeteners candy candies gum spice spices seasoning seasonings extract flavoring flavouring vinegar salt yeast baking powder powders formula '
      'infant baby supplement supplements beverage mix mixes alcoholic beer wine liquor vodka whiskey whisky rum gin brandy liqueur cocktail cider '
      'soda cola carbonated energy pork ham bacon sausage sausages pepperoni salami hotdog frankfurter chitterlings gelatin gelatine capers '
      'relish pickle pickles pickled ketchup mustard mayonnaise honey molasses jelly jam jams marmalade topping toppings frosting icing '
      'skin giblets gizzard heart mechanically tongue brain brains blood feet spleen lungs tripe offal bone broth bouillon stock cube');

  static final _animal = _w('beef lamb mutton goat veal chicken turkey duck goose quail fish salmon tuna cod shrimp prawn crab lobster oyster clam '
      'mussel squid egg eggs liver kidney sardine mackerel herring trout tilapia catfish meat poultry game');

  static final _rawWords = _w('raw uncooked unprepared dry dehydrated');

  static final _fruits = _w('apple apples banana bananas orange oranges mango mangoes guava grape grapes watermelon papaya pear pears peach peaches plum plums '
      'pomegranate strawberry strawberries blueberry blueberries raspberry raspberries melon cantaloupe honeydew kiwi kiwifruit pineapple cherry cherries apricot apricots '
      'litchi lychee clementine clementines tangerine tangerines mandarin jackfruit sapota chikoo jamun berries grapefruit nectarine persimmon');
  static final _fruitNot = _w('pie cake jam juice canned syrup dried pudding cobbler muffin bread sauce pickle chutney candied glazed sandwich raita shake milkshake curry paratha cream');

  static final _vegs = _w('spinach broccoli cauliflower cabbage carrot carrots tomato tomatoes cucumber lettuce okra bhindi gourd pumpkin beans brinjal eggplant '
      'capsicum zucchini radish turnip beetroot beet mushroom mushrooms saag palak salad sabzi sabji vegetable vegetables veggies celery kale asparagus '
      'lauki tinda turai karela methi sprouts peas butternut acorn cress leeks leek raita');
  static final _soup = _w('soup soups shorba');

  static final _drinks = _w('tea chai coffee juice lassi smoothie shake milkshake buttermilk lemonade nimbu sharbat milk kefir squash');
  static final _drinkNot = _w('chocolate cake pudding candy powder dry condensed evaporated cream ice butternut acorn summer winter');

  static final _bfast = _w('omelette omelet scrambled poha upma idli dosa uttapam oatmeal porridge oats cereal cornflakes muesli granola toast pancake pancakes waffle '
      'waffles cheela chilla daliya dalia breakfast quiche frittata bhurji');

  static final _carbs = _w('rice roti chapati chapatti phulka naan bread pasta spaghetti macaroni noodles quinoa couscous potato potatoes paratha tortilla '
      'barley millet bajra jowar ragi bulgur pita puri poori kulcha bun buns');

  static final _mains = _w('chicken mutton lamb beef fish prawn shrimp paneer dal daal dhal lentil lentils chickpea chickpeas chana chole rajma tofu biryani pulao '
      'khichdi kebab kabab tikka karahi korma keema stew masala curry turkey sabudana sandwich burger pizza wrap shawarma haleem nihari kofta cutlet fillet '
      'steak roast casserole lasagne lasagna risotto stirfry stir sambar rasam kadhi egg eggs');

  static final _snacks = _w('almonds almond cashew cashews walnut walnuts pistachio pistachios peanuts peanut popcorn biscuit biscuits cookie cookies cracker crackers chips '
      'samosa pakora pakoras bar bars cheese yogurt yoghurt nuts seeds hummus dates raisins namkeen chaat bhel khakhra wafer wafers');

  static final _desserts = _w('cake cakes pie pies pudding kheer halwa halva icecream gulab jamun jalebi barfi burfi ladoo laddu kulfi chocolate brownie doughnut donut pastry '
      'pastries custard rasgulla rasmalai cookie dessert sweet sweets muffin cupcake tart tarts fudge souffle mousse trifle sorbet sundae shrikhand payasam phirni');

  static final _fried = _w('fried frying fries samosa pakora pakoras puri poori bhatura kachori tempura nuggets chips crisps deep jalebi');
  static final _processed = _w('canned processed instant packaged sausage nuggets burger pizza noodles cereal cornflakes biscuit biscuits cookie cookies cracker crackers '
      'chips crisps wafer wafers frozen readymade fast');
  static final _sugary = _w('juice sweet sweetened sugar syrup candy jam kheer halwa halva jalebi gulab jamun barfi ladoo laddu kulfi cake pudding pie ice cream icecream '
      'chocolate sherbet sharbat squash lemonade shake smoothie sweets pastry doughnut donut brownie');
  static final _refined = _w('maida naan white refined biscuit biscuits cake pastry cracker crackers noodles pasta macaroni spaghetti bun buns kulcha puri poori bhatura');
  /// Grains and pulses, which are listed dry (about 3.4 kcal a gram) as often as cooked (about 1.3): a dry one is not a meal.
  static final _grains = _w('rice barley millet quinoa oats wheat pasta noodles couscous bulgur dal daal lentil lentils chickpea chickpeas beans bean semolina vermicelli corn');
  static final _cookedWords = _w('cooked boiled steamed prepared khichdi khichri pulao biryani curry soup porridge upma poha idli dosa roti chapati bread paratha');

  static final _salty = _w('canned cured salted brine smoked namkeen papad chips crisps instant processed sausage cheese');

  static bool _any(Set<String> tokens, Set<String> words) => tokens.any(words.contains);

  /// The profile of [f], or null when the food does not belong in a meal plan.
  static MealProfile? classify(FoodItem f) {
    final name = Fuzzy.normalize(f.name);
    if (name.isEmpty) return null;
    final tokens = name.split(' ').map(Fuzzy.singular).toSet()..addAll(name.split(' '));
    final serving = Fuzzy.normalize(f.servingLabel);

    // ---- things that are never a meal ---------------------------------------------------------------------------------------
    if (_any(tokens, _never)) return null;
    if (RegExp(r'\b(tbsp|tablespoon|tsp|teaspoon|pinch|dash|drop|packet|sachet|dry|uncooked)\b').hasMatch(serving)) return null;
    final raw = _any(tokens, _rawWords);
    if (raw && _any(tokens, _animal)) return null; // raw meat, fish, eggs
    if (_any(tokens, _w('flour meal starch bran germ')) && !_any(tokens, _w('bread roti chapati cereal'))) return null;
    if (raw && _any(tokens, _w('rice lentil lentils beans bean chickpea chickpeas pasta noodles oats quinoa millet barley wheat grain grains cereal'))) return null;

    if (_any(tokens, _grains) && !_any(tokens, _cookedWords) && f.kcal / f.grams > 2.2) return null; // dry grain or pulse

    // ---- numbers that must make sense ---------------------------------------------------------------------------------------
    if (f.grams < 25 || f.grams > 700) return null;
    if (f.kcal < 15 || f.kcal > 900) return null;
    if (f.fat > 90 || f.protein > 120 || f.carbs > 200) return null;
    final computed = 4 * f.protein + 4 * f.carbs + 9 * f.fat;
    if (f.kcal >= 40 && (computed - f.kcal).abs() > 0.3 * f.kcal) return null;
    if (f.protein + f.carbs + f.fat > f.grams * 1.02) return null; // more nutrients than food

    // ---- role -----------------------------------------------------------------------------------------------------------------
    String? role;
    final fried = _any(tokens, _fried) || name.contains('deep fried');
    if (_any(tokens, _desserts) && !_any(tokens, _w('fruit salad'))) {
      role = 'dessert';
    } else if (name.startsWith('snacks ') && f.kcal >= 40 && f.kcal <= 450) {
      role = 'snack'; // USDA files packaged snacks (chips, bars, sticks) under "Snacks, ..."
    } else if (_any(tokens, _bfast) && f.kcal >= 80 && f.kcal <= 650) {
      role = 'bfast';
    } else if (_any(tokens, _drinks) && !_any(tokens, _drinkNot) && f.kcal <= 350 && !(tokens.contains('milk') && tokens.contains('powder'))) {
      role = 'drink';
    } else if (_any(tokens, _soup) && f.kcal <= 250) {
      role = 'veg';
    } else if (tokens.contains('raita')) {
      role = 'veg';
    } else if (_any(tokens, _mains) && f.kcal >= 120) {
      role = 'main';
    } else if (_any(tokens, _carbs) && f.kcal >= 50) {
      role = 'carb';
    } else if (_any(tokens, _fruits) && !_any(tokens, _fruitNot)) {
      role = 'fruit';
    } else if (_any(tokens, _vegs) && f.kcal <= 200) {
      role = 'veg';
    } else if (_any(tokens, _snacks) && f.kcal >= 40 && f.kcal <= 450) {
      role = 'snack';
    }
    if (role == 'veg' && tokens.contains('sandwich')) return null; // a sandwich with no protein is not a vegetable side
    if (role == null) return null;
    if (role == 'main' && f.protein < 6) role = _any(tokens, _carbs) ? 'carb' : (f.kcal <= 200 ? 'veg' : null); // a "main" with no protein is a side
    if (role == null) return null;

    // ---- tags ---------------------------------------------------------------------------------------------------------------
    final tags = <String>{};
    if (fried) tags.add('fried');
    if (_any(tokens, _processed)) tags.add('processed');
    if (_any(tokens, _sugary) || (role == 'drink' && f.carbs >= 20 && !tokens.contains('milk'))) tags.add('highSugar');
    if (_any(tokens, _refined) && !_any(tokens, _w('whole wholemeal brown multigrain'))) tags.add('refined');
    if (_any(tokens, _salty)) tags.add('highSodium');
    if (role == 'dessert') tags.add('highSugar');
    if (role == 'main' && f.protein / (f.kcal == 0 ? 1 : f.kcal) * 4 >= 0.3 && f.fat * 9 / f.kcal <= 0.3) tags.add('lean');

    final meals = switch (role) {
      'bfast' => ['breakfast'],
      'drink' => ['breakfast', 'snack'],
      'fruit' => ['breakfast', 'snack'],
      'carb' => _any(tokens, _w('bread toast paratha')) ? ['breakfast', 'lunch', 'dinner'] : ['lunch', 'dinner'],
      'main' || 'veg' => ['lunch', 'dinner'],
      _ => ['snack'], // snack, dessert
    };
    return MealProfile(role, meals, tags.toList());
  }

  /// [f] as a plan food: curated foods keep what their data file says; any other food gets its role from [classify] (or null).
  static FoodItem? asPlanFood(FoodItem f) {
    if (!f.isBulk) return f;
    final p = classify(f);
    if (p == null) return null;
    return f.withPlan(role: p.role, meals: p.meals, tags: p.tags);
  }
}
