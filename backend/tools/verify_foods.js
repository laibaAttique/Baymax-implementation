// Compares the app's local food table with USDA FoodData Central.
//
//   node tools/verify_foods.js "<path to app>/assets/data/foods.json" [--write]
//
// Needs USDA_API_KEY in .env. Prints a per-food comparison (local kcal per
// serving vs USDA kcal for the same weight). With --write it also marks the
// foods whose USDA match is within TOLERANCE as `source: "usda"` with the
// matched `fdcId`, and replaces their numbers with the USDA values scaled to
// the serving weight. Foods without a USDA query (mixed Pakistani dishes) are
// left as estimates.
require('dotenv').config();
const fs = require('fs');
const { searchFoods } = require('../services/usda');

const TOLERANCE = 0.25; // accept a match only if kcal differs by <= 25%

// food id -> USDA search phrase. Only generic foods that USDA actually covers.
const QUERIES = {
  boiled_egg: 'egg whole cooked hard-boiled',
  fried_egg: 'egg whole cooked fried',
  oatmeal: 'oatmeal cooked with water',
  cornflakes: 'cereals ready-to-eat corn flakes',
  white_bread: 'bread white commercially prepared',
  wholewheat_bread: 'bread whole-wheat commercially prepared',
  milk: 'milk whole 3.25% milkfat',
  skim_milk: 'milk nonfat fluid',
  yogurt: 'yogurt plain whole milk',
  paneer: 'cheese cottage',
  cheese_slice: 'cheese american processed',
  green_tea: 'tea green brewed',
  black_coffee: 'beverages coffee brewed prepared with tap water',
  white_rice: 'rice white long-grain regular cooked',
  brown_rice: 'rice brown long-grain cooked',
  quinoa: 'quinoa cooked',
  pasta: 'spaghetti cooked enriched without added salt',
  potato_boiled: 'potatoes boiled cooked in skin flesh',
  sweet_potato: 'sweet potato cooked baked in skin',
  french_fries: 'potatoes french fried frozen oven-heated',
  grilled_chicken: 'chicken broilers or fryers breast meat only cooked roasted',
  grilled_fish: 'fish salmon atlantic farmed cooked dry heat',
  tuna_canned: 'fish tuna light canned in water drained solids',
  grilled_shrimp: 'crustaceans shrimp cooked moist heat',
  daal: 'lentils mature seeds cooked boiled without salt',
  chana_masala: 'chickpeas mature seeds cooked boiled without salt',
  rajma: 'beans kidney red mature seeds cooked boiled without salt',
  steamed_veg: 'vegetables mixed frozen cooked boiled drained without salt',
  green_salad: 'lettuce cos or romaine raw',
  tofu: 'tofu raw firm prepared with calcium sulfate',
  almonds: 'nuts almonds',
  mixed_nuts: 'nuts mixed nuts dry roasted with peanuts without salt added',
  peanuts: 'peanuts all types raw',
  peanut_butter: 'peanut butter smooth style without salt',
  butter: 'butter without salt',
  ghee: 'butter oil anhydrous',
  olive_oil: 'oil olive salad or cooking',
  dates: 'dates medjool',
  banana: 'bananas raw',
  apple: 'apples raw with skin',
  orange: 'oranges raw all commercial varieties',
  mango: 'mangos raw',
  guava: 'guavas common raw',
  grapes: 'grapes red or green raw',
  watermelon: 'watermelon raw',
  papaya: 'papayas raw',
  strawberries: 'strawberries raw',
  pomegranate: 'pomegranates raw',
  orange_juice: 'orange juice raw',
  cola: 'beverages carbonated cola regular',
  coconut_water: 'beverages coconut water ready-to-drink unsweetened',
  hummus: 'hummus commercial',
  ice_cream: 'ice creams vanilla',
  chocolate: 'candies milk chocolate',
  pizza_slice: 'pizza cheese topping regular crust frozen cooked',
  potato_chips: 'snacks potato chips plain salted'
};

async function main() {
  const file = process.argv[2];
  const write = process.argv.includes('--write');
  if (!file) {
    console.error('Usage: node tools/verify_foods.js <foods.json> [--write]');
    process.exit(1);
  }
  if (!process.env.USDA_API_KEY) {
    console.error('USDA_API_KEY is not set in .env (get a free key at https://api.data.gov/signup/).');
    process.exit(1);
  }

  const foods = JSON.parse(fs.readFileSync(file, 'utf8'));
  let verified = 0, rejected = 0, skipped = 0;

  for (const food of foods) {
    const query = QUERIES[food.id];
    if (!query) { skipped++; continue; }

    let results;
    try {
      results = await searchFoods(query, { pageSize: 3 });
    } catch (e) {
      console.log(`! ${food.id}: ${e.message}`);
      continue;
    }
    const best = results[0];
    if (!best) { console.log(`? ${food.id}: no USDA result for "${query}"`); rejected++; continue; }

    const factor = food.grams / 100;
    const usdaKcal = best.kcal * factor;
    const diff = (food.kcal - usdaKcal) / usdaKcal;
    const ok = Math.abs(diff) <= TOLERANCE;
    console.log(
      `${ok ? 'OK ' : 'DIFF'} ${food.id.padEnd(18)} local ${String(food.kcal).padStart(4)} kcal | USDA ${usdaKcal.toFixed(0).padStart(4)} kcal` +
      ` (${(diff * 100).toFixed(0)}%) | ${best.name} [${best.fdcId}]`
    );
    if (ok) {
      verified++;
      if (write) {
        const r1 = (n) => Math.round(n * 10) / 10;
        food.kcal = Math.round(usdaKcal);
        food.protein = r1(best.protein * factor);
        food.carbs = r1(best.carbs * factor);
        food.fat = r1(best.fat * factor);
        food.source = 'usda';
        food.fdcId = best.fdcId;
      }
    } else {
      rejected++;
    }
  }

  console.log(`\nVerified ${verified}, differ/missing ${rejected}, no USDA equivalent (kept as estimates) ${skipped}.`);
  if (write) {
    fs.writeFileSync(file, JSON.stringify(foods, null, 1));
    console.log(`Updated ${file}`);
  } else {
    console.log('Dry run: nothing written. Re-run with --write to apply the OK rows.');
  }
}

main();
