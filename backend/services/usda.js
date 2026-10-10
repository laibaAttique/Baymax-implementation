// Thin client for the USDA FoodData Central API (https://fdc.nal.usda.gov/api-guide).
// Nutrient values returned by the search endpoint are per 100 g of food.

const SEARCH_URL = 'https://api.nal.usda.gov/fdc/v1/foods/search';

// FDC nutrient numbers
const ENERGY_KCAL = ['208', '957', '958']; // Energy; Atwater general / specific factors
const PROTEIN = '203';
const FAT = '204';
const CARBS = '205';

function nutrientValue(nutrients, numbers) {
  const list = Array.isArray(numbers) ? numbers : [numbers];
  for (const number of list) {
    const found = nutrients.find((n) => String(n.nutrientNumber) === number && typeof n.value === 'number');
    if (found) return found.value;
  }
  return undefined;
}

/** Converts one FDC search hit to our per-100 g shape; null if it has no energy value. */
function normalizeFood(food) {
  const nutrients = food.foodNutrients || [];
  const kcal = nutrientValue(nutrients, ENERGY_KCAL);
  if (kcal === undefined) return null;
  return {
    fdcId: String(food.fdcId),
    name: food.description,
    dataType: food.dataType,
    kcal,
    protein: nutrientValue(nutrients, PROTEIN) ?? 0,
    carbs: nutrientValue(nutrients, CARBS) ?? 0,
    fat: nutrientValue(nutrients, FAT) ?? 0,
    source: 'USDA FoodData Central'
  };
}

const cache = new Map(); // query -> { at, foods }
const CACHE_MS = 10 * 60 * 1000;

class UsdaError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

async function searchFoods(query, { pageSize = 10 } = {}) {
  const key = process.env.USDA_API_KEY || 'DEMO_KEY';
  const cacheKey = `${pageSize}:${query.toLowerCase()}`;
  const hit = cache.get(cacheKey);
  if (hit && Date.now() - hit.at < CACHE_MS) return hit.foods;

  const url = new URL(SEARCH_URL);
  url.searchParams.set('query', query);
  // Reference-quality datasets only (no branded/label data).
  url.searchParams.set('dataType', 'Foundation,SR Legacy');
  url.searchParams.set('pageSize', String(pageSize));
  url.searchParams.set('api_key', key);

  const response = await fetch(url);
  if (response.status === 429) throw new UsdaError('USDA rate limit reached. Add a USDA_API_KEY to .env.', 503);
  if (!response.ok) throw new UsdaError(`USDA API error (${response.status})`, 502);

  const data = await response.json();
  const foods = (data.foods || []).map(normalizeFood).filter(Boolean);
  cache.set(cacheKey, { at: Date.now(), foods });
  return foods;
}

module.exports = { searchFoods, normalizeFood, UsdaError };
