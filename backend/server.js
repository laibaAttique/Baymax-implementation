const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const bodyParser = require('body-parser');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
// Label photos for OCR arrive as base64 JSON, so allow a larger body than the 100kb default.
app.use(bodyParser.json({ limit: '12mb' }));
app.use(express.static('public')); // Serve static files from 'public' directory

// Database Connection (optional — app now uses Firebase; MongoDB is legacy)
if (process.env.MONGODB_URI) {
  mongoose.connect(process.env.MONGODB_URI)
    .then(() => console.log('Connected to MongoDB'))
    .catch(err => console.error('MongoDB connection error:', err));
} else {
  console.log('MONGODB_URI not set — skipping MongoDB connection (Firebase is primary).');
}

// Routes
const healthProfileRoutes = require('./routes/healthProfile');
const foodRoutes = require('./routes/food');
const scanRoutes = require('./routes/scan');
const voiceRoutes = require('./routes/voice');
require('./services/dialogflow').warmUp().then((ok) => {
  if (ok) console.log('Dialogflow ready.');
});
app.use('/api/profile', healthProfileRoutes);
app.use('/api/food', foodRoutes);
app.use('/api/scan', scanRoutes);
app.use('/api/voice', voiceRoutes);

// Start Server
app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
