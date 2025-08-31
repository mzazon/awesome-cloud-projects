const { Firestore } = require('@google-cloud/firestore');
const functions = require('@google-cloud/functions-framework');

// Initialize Firestore client
const firestore = new Firestore();
const COLLECTION_NAME = 'url-mappings';

// Generate random short ID
function generateShortId() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  for (let i = 0; i < 6; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

// Validate URL format
function isValidUrl(string) {
  try {
    const url = new URL(string);
    return url.protocol === 'http:' || url.protocol === 'https:';
  } catch (_) {
    return false;
  }
}

// HTTP Cloud Function for URL shortening and redirection
functions.http('urlShortener', async (req, res) => {
  // Get CORS configuration from environment variables
  const corsOrigins = process.env.CORS_ORIGINS ? process.env.CORS_ORIGINS.split(',') : ['*'];
  const corsMethods = process.env.CORS_METHODS ? process.env.CORS_METHODS.split(',') : ['GET', 'POST', 'OPTIONS'];

  // Enable CORS for web applications
  const origin = req.get('Origin');
  if (corsOrigins.includes('*') || corsOrigins.includes(origin)) {
    res.set('Access-Control-Allow-Origin', corsOrigins.includes('*') ? '*' : origin);
  }
  res.set('Access-Control-Allow-Methods', corsMethods.join(', '));
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.set('Access-Control-Max-Age', '3600');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  try {
    if (req.method === 'POST' && req.path === '/shorten') {
      // Shorten URL endpoint
      const { url } = req.body;

      if (!url || !isValidUrl(url)) {
        return res.status(400).json({ 
          error: 'Invalid URL provided',
          message: 'Please provide a valid HTTP or HTTPS URL' 
        });
      }

      // Generate unique short ID with retry logic
      let shortId;
      let attempts = 0;
      const maxAttempts = 5;

      do {
        shortId = generateShortId();
        const existingDoc = await firestore.collection(COLLECTION_NAME).doc(shortId).get();
        if (!existingDoc.exists) break;
        attempts++;
      } while (attempts < maxAttempts);

      if (attempts >= maxAttempts) {
        return res.status(500).json({ 
          error: 'Unable to generate unique short ID',
          message: 'Please try again' 
        });
      }

      // Store URL mapping in Firestore
      await firestore.collection(COLLECTION_NAME).doc(shortId).set({
        originalUrl: url,
        shortId: shortId,
        createdAt: new Date(),
        clickCount: 0,
        userAgent: req.get('User-Agent') || 'unknown',
        createdBy: req.ip || 'unknown'
      });

      const shortUrl = `https://${req.get('host')}/${shortId}`;
      
      res.status(200).json({
        success: true,
        shortUrl: shortUrl,
        shortId: shortId,
        originalUrl: url,
        createdAt: new Date().toISOString()
      });

    } else if (req.method === 'GET' && req.path !== '/' && req.path !== '/health') {
      // URL redirection endpoint
      const shortId = req.path.substring(1); // Remove leading slash

      if (!shortId) {
        return res.status(400).json({ 
          error: 'Short ID required',
          message: 'Please provide a valid short ID in the URL path' 
        });
      }

      // Lookup original URL in Firestore
      const doc = await firestore.collection(COLLECTION_NAME).doc(shortId).get();

      if (!doc.exists) {
        return res.status(404).json({ 
          error: 'Short URL not found',
          message: `No URL mapping found for short ID: ${shortId}` 
        });
      }

      const data = doc.data();
      
      // Increment click count atomically
      await firestore.collection(COLLECTION_NAME).doc(shortId).update({
        clickCount: (data.clickCount || 0) + 1,
        lastAccessed: new Date(),
        lastAccessedBy: req.ip || 'unknown',
        lastUserAgent: req.get('User-Agent') || 'unknown'
      });

      // Redirect to original URL
      res.redirect(301, data.originalUrl);

    } else if (req.method === 'GET' && req.path === '/health') {
      // Health check endpoint
      res.status(200).json({
        status: 'healthy',
        service: 'URL Shortener',
        timestamp: new Date().toISOString(),
        version: '1.0.0'
      });

    } else if (req.method === 'GET' && req.path === '/stats' && req.query.shortId) {
      // Statistics endpoint for a specific short URL
      const shortId = req.query.shortId;
      
      const doc = await firestore.collection(COLLECTION_NAME).doc(shortId).get();
      
      if (!doc.exists) {
        return res.status(404).json({ 
          error: 'Short URL not found',
          message: `No URL mapping found for short ID: ${shortId}` 
        });
      }

      const data = doc.data();
      
      res.status(200).json({
        shortId: data.shortId,
        originalUrl: data.originalUrl,
        clickCount: data.clickCount || 0,
        createdAt: data.createdAt?.toDate()?.toISOString() || null,
        lastAccessed: data.lastAccessed?.toDate()?.toISOString() || null
      });

    } else {
      // API documentation endpoint
      res.status(200).json({
        message: 'URL Shortener API',
        version: '1.0.0',
        endpoints: {
          'POST /shorten': {
            description: 'Create short URL',
            body: { url: 'https://example.com' },
            response: 'Returns short URL and metadata'
          },
          'GET /{shortId}': {
            description: 'Redirect to original URL',
            response: '301 redirect to original URL'
          },
          'GET /stats?shortId={shortId}': {
            description: 'Get statistics for a short URL',
            response: 'Returns click count and metadata'
          },
          'GET /health': {
            description: 'Health check endpoint',
            response: 'Service health status'
          },
          'GET /': {
            description: 'API documentation',
            response: 'This documentation'
          }
        },
        usage: {
          shorten: `curl -X POST https://${req.get('host')}/shorten -H "Content-Type: application/json" -d '{"url": "https://example.com"}'`,
          redirect: `curl -I https://${req.get('host')}/ABC123`,
          stats: `curl https://${req.get('host')}/stats?shortId=ABC123`,
          health: `curl https://${req.get('host')}/health`
        },
        cors: {
          enabled: true,
          allowedOrigins: corsOrigins,
          allowedMethods: corsMethods
        }
      });
    }

  } catch (error) {
    console.error('Function error:', error);
    res.status(500).json({ 
      error: 'Internal server error',
      message: 'An unexpected error occurred. Please try again later.',
      timestamp: new Date().toISOString()
    });
  }
});