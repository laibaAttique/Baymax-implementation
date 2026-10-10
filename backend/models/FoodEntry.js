const mongoose = require('mongoose');

// One logged food item (Module 7). Nutrition is stored already scaled to
// the quantity the user ate.
const FoodEntrySchema = new mongoose.Schema({
  uid: { type: String, required: true, index: true },
  date: { type: String, required: true, match: /^\d{4}-\d{2}-\d{2}$/ }, // user's local day, YYYY-MM-DD
  meal: { type: String, required: true, enum: ['Breakfast', 'Lunch', 'Dinner', 'Snack'] },
  name: { type: String, required: true, trim: true, maxlength: 120 },
  quantity: { type: Number, default: 1, min: 0 },
  unit: { type: String, default: 'serving', maxlength: 30 },
  kcal: { type: Number, required: true, min: 0, max: 20000 },
  protein: { type: Number, default: 0, min: 0 },
  carbs: { type: Number, default: 0, min: 0 },
  fat: { type: Number, default: 0, min: 0 },
  source: { type: String, enum: ['text', 'image', 'manual'], default: 'text' }
}, { timestamps: true });

FoodEntrySchema.index({ uid: 1, date: 1 });

module.exports = mongoose.model('FoodEntry', FoodEntrySchema);
