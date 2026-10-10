const express = require('express');
const mongoose = require('mongoose');
const router = express.Router();
const FoodEntry = require('../models/FoodEntry');
const requireAuth = require('../middleware/firebaseAuth');

const FIELDS = ['date', 'meal', 'name', 'quantity', 'unit', 'kcal', 'protein', 'carbs', 'fat', 'source'];
const MAX_BATCH = 50;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

router.use(requireAuth);

// List the signed-in user's entries for one day: GET /api/food?date=YYYY-MM-DD
router.get('/', async (req, res) => {
  const { date } = req.query;
  if (typeof date !== 'string' || !DATE_RE.test(date)) {
    return res.status(400).json({ success: false, error: 'date=YYYY-MM-DD is required' });
  }
  try {
    const entries = await FoodEntry.find({ uid: req.uid, date }).sort({ createdAt: 1 });
    res.json({ success: true, data: entries });
  } catch (error) {
    console.error('Error listing food entries:', error);
    res.status(500).json({ success: false, error: 'Server Error' });
  }
});

// Add one or more entries: POST /api/food { entries: [...] }
router.post('/', async (req, res) => {
  const incoming = Array.isArray(req.body.entries) ? req.body.entries : [];
  if (incoming.length === 0 || incoming.length > MAX_BATCH) {
    return res.status(400).json({ success: false, error: `entries must contain 1-${MAX_BATCH} items` });
  }
  try {
    const docs = incoming.map((e) => {
      const doc = { uid: req.uid };
      for (const f of FIELDS) {
        if (e[f] !== undefined) doc[f] = e[f];
      }
      return doc;
    });
    const saved = await FoodEntry.insertMany(docs);
    res.status(201).json({ success: true, data: saved });
  } catch (error) {
    if (error.name === 'ValidationError') {
      return res.status(400).json({ success: false, error: error.message });
    }
    console.error('Error saving food entries:', error);
    res.status(500).json({ success: false, error: 'Server Error' });
  }
});

// Delete one of the user's own entries
router.delete('/:id', async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) {
    return res.status(400).json({ success: false, error: 'Invalid id' });
  }
  try {
    const removed = await FoodEntry.findOneAndDelete({ _id: req.params.id, uid: req.uid });
    if (!removed) return res.status(404).json({ success: false, error: 'Entry not found' });
    res.json({ success: true });
  } catch (error) {
    console.error('Error deleting food entry:', error);
    res.status(500).json({ success: false, error: 'Server Error' });
  }
});

module.exports = router;
