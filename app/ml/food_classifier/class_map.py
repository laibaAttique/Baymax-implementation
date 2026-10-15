"""Maps dataset class names to the ids in the app's food catalogue (assets/data/foods.json).

The model is trained ONLY on classes that map to a catalogue food, so every prediction
has calorie data behind it. Classes with no catalogue match are skipped (and listed by the
training script so you can add those foods to the catalogue and re-train).
"""
import re

# Food-101 (https://data.vision.ee.ethz.ch/cvl/datasets_extra/food-101/) -> catalogue id
FOOD101 = {
    'chicken_curry': 'chicken_curry',
    'samosa': 'samosa',
    'pizza': 'pizza_slice',
    'french_fries': 'french_fries',
    'ice_cream': 'ice_cream',
    'omelette': 'omelette',
    'hummus': 'hummus',
    'hamburger': 'chicken_burger',
    'club_sandwich': 'chicken_sandwich',
    'grilled_salmon': 'grilled_fish',
    'spaghetti_bolognese': 'pasta',
    'spaghetti_carbonara': 'pasta',
    'macaroni_and_cheese': 'pasta',
    'greek_salad': 'green_salad',
    'chocolate_cake': 'cake_slice',
    'red_velvet_cake': 'cake_slice',
    'carrot_cake': 'cake_slice',
}

# Other datasets (Indian / South-Asian food sets, your own photos): normalised folder name -> id.
# Folder names are lower-cased with non-letters turned into '_' before lookup.
SYNONYMS = {
    'biryani': 'chicken_biryani', 'chicken_biryani': 'chicken_biryani', 'biriyani': 'chicken_biryani',
    'butter_chicken': 'butter_chicken', 'murgh_makhani': 'butter_chicken',
    'chicken_tikka': 'chicken_tikka', 'tandoori_chicken': 'chicken_tikka',
    'chicken_karahi': 'chicken_karahi', 'kadai_chicken': 'chicken_karahi', 'karahi': 'chicken_karahi',
    'chana_masala': 'chana_masala', 'chole': 'chana_masala',
    'naan': 'naan', 'garlic_naan': 'naan',
    'chapati': 'roti', 'roti': 'roti', 'phulka': 'roti', 'tandoori_roti': 'roti',
    'paratha': 'paratha', 'aloo_paratha': 'aloo_paratha',
    'dal': 'daal', 'daal': 'daal', 'dal_tadka': 'daal', 'dal_makhani': 'daal', 'dal_fry': 'daal',
    'palak_paneer': 'palak_paneer', 'saag_paneer': 'palak_paneer',
    'kheer': 'kheer', 'rice_pudding': 'kheer',
    'gulab_jamun': 'gulab_jamun',
    'lassi': 'lassi_sweet', 'sweet_lassi': 'lassi_sweet',
    'pakora': 'pakora', 'pakoda': 'pakora',
    'raita': 'raita',
    'khichdi': 'khichdi', 'pulao': 'pulao', 'haleem': 'haleem',
    'nihari': 'beef_nihari', 'beef_nihari': 'beef_nihari',
    'seekh_kebab': 'seekh_kebab', 'shami_kebab': 'shami_kebab',
    'suji_halwa': 'suji_halwa', 'sooji_halwa': 'suji_halwa', 'sheera': 'suji_halwa',
    'aloo_gobi': 'aloo_gobi', 'bhindi_masala': 'bhindi', 'bhindi': 'bhindi',
    'rajma': 'rajma', 'rajma_chawal': 'rajma',
    'mutton_curry': 'mutton_curry', 'mutton_karahi': 'mutton_curry',
    'paneer': 'paneer', 'samosa': 'samosa',
    'chai': 'tea_milk', 'masala_chai': 'tea_milk', 'doodh_patti': 'tea_milk',
    'bhindi_fry': 'bhindi',
}

# Foods the datasets contain that the catalogue does NOT yet have. Adding them to
# assets/data/foods.json (and re-seeding Firestore) lets the model recognise them too.
SUGGESTED_NEW_FOODS = [
    'fried_rice', 'pancakes', 'waffles', 'donuts', 'sushi', 'tacos', 'ramen', 'dosa', 'idli', 'jalebi',
    'rasgulla', 'ras_malai', 'kofta', 'kadhi', 'poha', 'upma',
]


def normalise(name: str) -> str:
    return re.sub(r'[^a-z]+', '_', name.lower()).strip('_')


def resolve(name: str, food101: bool = False):
    """Catalogue id for a dataset class name, or None."""
    key = normalise(name)
    if food101 and key in FOOD101:
        return FOOD101[key]
    return SYNONYMS.get(key)
