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

// Database Connection
mongoose.connect(process.env.MONGODB_URI)
.then(() => console.log('Connected to MongoDB'))
.catch(err => console.error('MongoDB connection error:', err));

// Routes
const healthProfileRoutes = require('./routes/healthProfile');
const foodRoutes = require('./routes/food');
const scanRoutes = require('./routes/scan');
app.use('/api/profile', healthProfileRoutes);
app.use('/api/food', foodRoutes);
app.use('/api/scan', scanRoutes);

// Start Server
app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
