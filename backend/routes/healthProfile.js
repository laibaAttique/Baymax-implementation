const express = require('express');
const router = express.Router();
const UserProfile = require('../models/UserProfile');
const requireAuth = require('../middleware/firebaseAuth');

// Fields a client may set on its own profile (uid always comes from the token).
const EDITABLE_FIELDS = [
  'fullName', 'dob', 'gender', 'height', 'weight', 'medicalConditions',
  'foodAllergies', 'medications', 'primaryGoal', 'activityLevel',
  'workoutFrequency', 'targetWeight', 'calculatedBMI', 'healthClassification', 'planVariant'
];

// --- Authenticated, per-user endpoints (used by the Flutter app) ---

// Create or update the signed-in user's profile
router.put('/me', requireAuth, async (req, res) => {
  try {
    const update = {};
    for (const field of EDITABLE_FIELDS) {
      if (req.body[field] !== undefined) update[field] = req.body[field];
    }
    const profile = await UserProfile.findOneAndUpdate(
      { uid: req.uid },
      { $set: update },
      { upsert: true, returnDocument: 'after', runValidators: true, setDefaultsOnInsert: true }
    );
    res.status(200).json({ success: true, profileId: profile._id, data: profile });
  } catch (error) {
    if (error.name === 'ValidationError' || error.name === 'CastError') {
      return res.status(400).json({ success: false, error: error.message });
    }
    console.error('Error saving profile:', error);
    res.status(500).json({ success: false, error: 'Server Error' });
  }
});

// Get the signed-in user's profile
router.get('/me', requireAuth, async (req, res) => {
  try {
    const profile = await UserProfile.findOne({ uid: req.uid });
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Profile not found' });
    }
    res.status(200).json({ success: true, data: profile });
  } catch (error) {
    console.error('Error fetching profile:', error);
    res.status(500).json({ success: false, error: 'Server Error' });
  }
});

// --- Legacy unauthenticated endpoints (used by the static web prototype) ---

// Create or update health profile
router.post('/', async (req, res) => {
  try {
    const profileData = req.body;
    
    // In a real app with auth, we'd use the authenticated user's ID
    // For this prototype, we'll create a new profile each time
    // and return the ID so the frontend can retrieve it for the result screens
    const newProfile = new UserProfile(profileData);
    await newProfile.save();
    
    res.status(201).json({ 
      success: true, 
      message: 'Profile saved successfully',
      profileId: newProfile._id
    });
  } catch (error) {
    console.error('Error saving profile:', error);
    res.status(500).json({ success: false, error: 'Server Error' });
  }
});

// Get health profile by ID
router.get('/:id', async (req, res) => {
  try {
    const profile = await UserProfile.findById(req.params.id);
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Profile not found' });
    }
    res.status(200).json({ success: true, data: profile });
  } catch (error) {
    console.error('Error fetching profile:', error);
    res.status(500).json({ success: false, error: 'Server Error' });
  }
});

module.exports = router;
