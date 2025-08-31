/**
 * Smart Parking Management - Parking Management API Cloud Function
 * Provides REST API endpoints for parking space search and zone statistics
 * 
 * This function provides the following API endpoints:
 * - GET /parking/search - Find available parking spaces near a location
 * - GET /parking/zones/:zoneId/stats - Get statistics for a parking zone
 * - GET /health - Health check endpoint
 * - GET /api-info - API documentation endpoint
 */

const { Firestore } = require('@google-cloud/firestore');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');

// Initialize Firestore client with project configuration
const firestore = new Firestore({
  projectId: '${project_id}',
  settings: {
    retries: 3,
    preferRest: true,
    clientConfig: {
      grpc: {
        keepalive_time_ms: 30000,
        keepalive_timeout_ms: 5000,
        keepalive_permit_without_calls: true
      }
    }
  }
});

// Collection references
const PARKING_SPACES_COLLECTION = '${parking_spaces_collection}';
const PARKING_ZONES_COLLECTION = '${parking_zones_collection}';

// Initialize Express app
const app = express();

// Security middleware
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      scriptSrc: ["'self'"],
      connectSrc: ["'self'"]
    }
  }
}));

// CORS configuration for web applications
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS ? process.env.ALLOWED_ORIGINS.split(',') : true,
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-API-Key'],
  credentials: true
}));

// JSON parsing middleware
app.use(express.json({ limit: '10mb' }));

// Request logging middleware
app.use((req, res, next) => {
  console.log('API Request:', {
    method: req.method,
    path: req.path,
    query: req.query,
    userAgent: req.get('User-Agent'),
    timestamp: new Date().toISOString()
  });
  next();
});

// ================================================================================
// API ENDPOINTS
// ================================================================================

/**
 * GET /parking/search - Find available parking spaces near a location
 * Query parameters:
 * - lat: Latitude (required)
 * - lng: Longitude (required)
 * - radius: Search radius in meters (optional, default: 1000)
 * - limit: Maximum number of results (optional, default: 10)
 * - status: Filter by status - 'available' or 'occupied' (optional, default: 'available')
 */
app.get('/parking/search', async (req, res) => {
  try {
    const startTime = Date.now();
    
    // Validate required parameters
    const { lat, lng, radius = 1000, limit = 10, status = 'available' } = req.query;
    
    if (!lat || !lng) {
      return res.status(400).json({
        error: 'Missing required parameters',
        message: 'Latitude (lat) and longitude (lng) are required',
        example: '/parking/search?lat=37.7749&lng=-122.4194&radius=1000'
      });
    }

    // Validate parameter types and ranges
    const latitude = parseFloat(lat);
    const longitude = parseFloat(lng);
    const searchRadius = Math.min(parseInt(radius), 5000); // Max 5km radius
    const resultLimit = Math.min(parseInt(limit), 50); // Max 50 results

    if (isNaN(latitude) || latitude < -90 || latitude > 90) {
      return res.status(400).json({
        error: 'Invalid latitude',
        message: 'Latitude must be a number between -90 and 90'
      });
    }

    if (isNaN(longitude) || longitude < -180 || longitude > 180) {
      return res.status(400).json({
        error: 'Invalid longitude', 
        message: 'Longitude must be a number between -180 and 180'
      });
    }

    // Query parking spaces from Firestore
    let query = firestore.collection(PARKING_SPACES_COLLECTION);
    
    // Filter by status if specified
    if (status && status !== 'all') {
      query = query.where('status', '==', status);
    }

    // Limit query size for performance
    query = query.limit(Math.min(resultLimit * 5, 200));

    const spacesSnapshot = await query.get();

    if (spacesSnapshot.empty) {
      return res.json({
        total: 0,
        spaces: [],
        search_params: { lat: latitude, lng: longitude, radius: searchRadius },
        message: 'No parking spaces found in the database'
      });
    }

    // Process and filter spaces by distance
    const availableSpaces = [];
    spacesSnapshot.forEach(doc => {
      const space = doc.data();
      
      // Calculate distance if location is available
      if (space.location && space.location.lat && space.location.lng) {
        const distance = calculateDistance(
          latitude, longitude,
          space.location.lat, space.location.lng
        );
        
        // Filter by radius
        if (distance <= searchRadius) {
          availableSpaces.push({
            id: doc.id,
            ...space,
            distance: Math.round(distance),
            estimated_walk_time: Math.round(distance / 83.33), // ~5 km/h walking speed
            coordinates: space.location
          });
        }
      }
    });

    // Sort by distance and limit results
    availableSpaces.sort((a, b) => a.distance - b.distance);
    const limitedResults = availableSpaces.slice(0, resultLimit);

    const processingTime = Date.now() - startTime;

    res.json({
      total: limitedResults.length,
      total_in_radius: availableSpaces.length,
      spaces: limitedResults,
      search_params: {
        lat: latitude,
        lng: longitude, 
        radius: searchRadius,
        status: status,
        limit: resultLimit
      },
      metadata: {
        processing_time_ms: processingTime,
        timestamp: new Date().toISOString()
      }
    });

    console.log('Search completed:', {
      lat: latitude,
      lng: longitude,
      radius: searchRadius,
      results: limitedResults.length,
      processingTime: processingTime
    });

  } catch (error) {
    console.error('Search error:', {
      error: error.message,
      stack: error.stack,
      query: req.query
    });
    
    res.status(500).json({
      error: 'Internal server error',
      message: 'Failed to search parking spaces',
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * GET /parking/zones/:zoneId/stats - Get statistics for a parking zone
 * Path parameters:
 * - zoneId: ID of the parking zone
 */
app.get('/parking/zones/:zoneId/stats', async (req, res) => {
  try {
    const startTime = Date.now();
    const { zoneId } = req.params;

    if (!zoneId || zoneId.trim() === '') {
      return res.status(400).json({
        error: 'Invalid zone ID',
        message: 'Zone ID is required and cannot be empty'
      });
    }

    // Get zone statistics from Firestore
    const zoneDoc = await firestore
      .collection(PARKING_ZONES_COLLECTION)
      .doc(zoneId)
      .get();

    if (!zoneDoc.exists) {
      return res.status(404).json({
        error: 'Zone not found',
        message: `Parking zone '${zoneId}' does not exist`,
        zone_id: zoneId
      });
    }

    const zoneData = zoneDoc.data();
    const processingTime = Date.now() - startTime;

    // Calculate additional statistics
    const occupancyRate = zoneData.total > 0 ? 
      ((zoneData.total - zoneData.available) / zoneData.total * 100) : 0;

    const response = {
      zone_id: zoneId,
      available: zoneData.available || 0,
      occupied: (zoneData.total || 0) - (zoneData.available || 0),
      total: zoneData.total || 0,
      occupancy_rate: parseFloat(occupancyRate.toFixed(1)),
      availability_rate: parseFloat((100 - occupancyRate).toFixed(1)),
      last_updated: zoneData.last_updated,
      created_at: zoneData.created_at,
      metadata: {
        processing_time_ms: processingTime,
        timestamp: new Date().toISOString(),
        space_count: zoneData.spaces ? Object.keys(zoneData.spaces).length : 0
      }
    };

    res.json(response);

    console.log('Zone stats retrieved:', {
      zoneId: zoneId,
      available: response.available,
      total: response.total,
      occupancyRate: response.occupancy_rate,
      processingTime: processingTime
    });

  } catch (error) {
    console.error('Zone stats error:', {
      error: error.message,
      stack: error.stack,
      zoneId: req.params.zoneId
    });
    
    res.status(500).json({
      error: 'Internal server error',
      message: 'Failed to retrieve zone statistics',
      zone_id: req.params.zoneId,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * GET /parking/zones - List all available parking zones
 */
app.get('/parking/zones', async (req, res) => {
  try {
    const startTime = Date.now();
    const { limit = 50 } = req.query;
    const resultLimit = Math.min(parseInt(limit), 100);

    const zonesSnapshot = await firestore
      .collection(PARKING_ZONES_COLLECTION)
      .limit(resultLimit)
      .get();

    const zones = [];
    zonesSnapshot.forEach(doc => {
      const zoneData = doc.data();
      const occupancyRate = zoneData.total > 0 ? 
        ((zoneData.total - zoneData.available) / zoneData.total * 100) : 0;

      zones.push({
        zone_id: doc.id,
        available: zoneData.available || 0,
        total: zoneData.total || 0,
        occupancy_rate: parseFloat(occupancyRate.toFixed(1)),
        last_updated: zoneData.last_updated
      });
    });

    const processingTime = Date.now() - startTime;

    res.json({
      total_zones: zones.length,
      zones: zones,
      metadata: {
        processing_time_ms: processingTime,
        timestamp: new Date().toISOString()
      }
    });

  } catch (error) {
    console.error('Zones list error:', error);
    res.status(500).json({
      error: 'Internal server error',
      message: 'Failed to retrieve zones list'
    });
  }
});

/**
 * GET /health - Health check endpoint for monitoring
 */
app.get('/health', async (req, res) => {
  try {
    const startTime = Date.now();
    
    // Test Firestore connectivity
    await firestore.collection('_health_check').limit(1).get();
    
    const processingTime = Date.now() - startTime;

    res.json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      services: {
        firestore: 'connected',
        api: 'operational'
      },
      performance: {
        firestore_response_time_ms: processingTime
      },
      version: '1.0.0'
    });

  } catch (error) {
    console.error('Health check failed:', error);
    
    res.status(503).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      error: error.message,
      services: {
        firestore: 'disconnected',
        api: 'operational'
      }
    });
  }
});

/**
 * GET /api-info - API documentation endpoint
 */
app.get('/api-info', (req, res) => {
  res.json({
    name: 'Smart Parking Management API',
    version: '1.0.0',
    description: 'REST API for finding parking spaces and zone statistics',
    endpoints: {
      'GET /parking/search': {
        description: 'Find available parking spaces near a location',
        parameters: {
          lat: 'Latitude (required)',
          lng: 'Longitude (required)', 
          radius: 'Search radius in meters (optional, default: 1000, max: 5000)',
          limit: 'Maximum results (optional, default: 10, max: 50)',
          status: 'Filter by status: available, occupied, or all (optional, default: available)'
        },
        example: '/parking/search?lat=37.7749&lng=-122.4194&radius=1000'
      },
      'GET /parking/zones/:zoneId/stats': {
        description: 'Get statistics for a specific parking zone',
        parameters: {
          zoneId: 'Zone identifier (required, path parameter)'
        },
        example: '/parking/zones/downtown/stats'
      },
      'GET /parking/zones': {
        description: 'List all available parking zones',
        parameters: {
          limit: 'Maximum zones to return (optional, default: 50, max: 100)'
        },
        example: '/parking/zones?limit=20'
      },
      'GET /health': {
        description: 'Health check endpoint for monitoring',
        parameters: 'None',
        example: '/health'
      }
    },
    rate_limits: {
      search: '100 requests per minute',
      zone_stats: '200 requests per minute',
      health: '1000 requests per minute'
    },
    timestamp: new Date().toISOString()
  });
});

/**
 * Handle 404 errors for unknown endpoints
 */
app.use('*', (req, res) => {
  res.status(404).json({
    error: 'Endpoint not found',
    message: `The endpoint ${req.method} ${req.originalUrl} does not exist`,
    available_endpoints: [
      'GET /parking/search',
      'GET /parking/zones/:zoneId/stats', 
      'GET /parking/zones',
      'GET /health',
      'GET /api-info'
    ],
    timestamp: new Date().toISOString()
  });
});

/**
 * Global error handler
 */
app.use((error, req, res, next) => {
  console.error('Unhandled error:', {
    error: error.message,
    stack: error.stack,
    url: req.url,
    method: req.method
  });

  res.status(500).json({
    error: 'Internal server error',
    message: 'An unexpected error occurred',
    timestamp: new Date().toISOString()
  });
});

// ================================================================================
// UTILITY FUNCTIONS
// ================================================================================

/**
 * Calculate distance between two geographic points using Haversine formula
 * @param {number} lat1 - Latitude of first point
 * @param {number} lon1 - Longitude of first point  
 * @param {number} lat2 - Latitude of second point
 * @param {number} lon2 - Longitude of second point
 * @returns {number} Distance in meters
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371000; // Earth's radius in meters
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
  
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  
  return R * c;
}

// Export the Express app for Cloud Functions
exports.parkingApi = app;