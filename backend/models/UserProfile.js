const mongoose = require('mongoose');

const UserProfileSchema = new mongoose.Schema({
  // Firebase Auth UID of the owner. Sparse so legacy (pre-auth) documents are allowed.
  uid: { type: String, unique: true, sparse: true },
  fullName: { type: String, required: true },
  dob: { type: String },
  gender: { type: String },
  height: {
    value: { type: Number },
    unit: { type: String, enum: ['cm', 'ft'], default: 'cm' }
  },
  weight: {
    value: { type: Number },
    unit: { type: String, enum: ['kg', 'lbs'], default: 'kg' }
  },
  medicalConditions: [{ type: String }],
  foodAllergies: [{ type: String }],
  medications: { type: String },
  primaryGoal: { type: String },
  activityLevel: { type: String },
  workoutFrequency: { type: Number },
  targetWeight: {
    value: { type: Number },
    unit: { type: String, enum: ['kg', 'lbs'], default: 'kg' }
  },
  calculatedBMI: { type: Number },
  healthClassification: { type: String },
  planVariant: { type: Number, default: 0, min: 0 }
}, { timestamps: true });

module.exports = mongoose.model('UserProfile', UserProfileSchema);
