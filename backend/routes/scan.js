const express = require('express');
const router = express.Router();
const requireAuth = require('../middleware/firebaseAuth');

const VISION_URL = 'https://vision.googleapis.com/v1/images:annotate';
const MAX_IMAGE_BYTES = 8 * 1024 * 1024;

// OCR for product labels (Module 8, FR-2).
// POST /api/scan/ocr { imageBase64 } -> { success, text }
// Needs GOOGLE_VISION_API_KEY in .env; the key stays on the server.
router.post('/ocr', requireAuth, async (req, res) => {
  const key = process.env.GOOGLE_VISION_API_KEY;
  if (!key) {
    return res.status(503).json({
      success: false,
      error: 'Label scanning is not configured on the server (missing GOOGLE_VISION_API_KEY).'
    });
  }

  const { imageBase64 } = req.body;
  if (typeof imageBase64 !== 'string' || imageBase64.length === 0) {
    return res.status(400).json({ success: false, error: 'imageBase64 is required' });
  }
  // base64 is ~4/3 the size of the bytes it encodes
  if (imageBase64.length * 0.75 > MAX_IMAGE_BYTES) {
    return res.status(413).json({ success: false, error: 'Image is too large' });
  }

  try {
    const response = await fetch(`${VISION_URL}?key=${encodeURIComponent(key)}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        requests: [{
          image: { content: imageBase64 },
          features: [{ type: 'DOCUMENT_TEXT_DETECTION' }]
        }]
      })
    });
    const data = await response.json();
    if (!response.ok || data.responses?.[0]?.error) {
      const message = data.error?.message || data.responses?.[0]?.error?.message || 'Vision API error';
      console.error('Vision API error:', message);
      return res.status(502).json({ success: false, error: 'Text recognition failed. Please try again.' });
    }
    const text = data.responses?.[0]?.fullTextAnnotation?.text || '';
    res.json({ success: true, text });
  } catch (error) {
    console.error('OCR request failed:', error);
    res.status(502).json({ success: false, error: 'Text recognition failed. Please try again.' });
  }
});

module.exports = router;
