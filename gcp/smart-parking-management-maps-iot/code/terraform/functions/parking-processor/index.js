/**
 * Smart Parking Management - Parking Data Processor Cloud Function
 * Processes parking sensor data from Pub/Sub messages and updates Firestore
 * 
 * This function is triggered by Pub/Sub messages from IoT parking sensors
 * and performs the following operations:
 * 1. Parse and validate incoming sensor data
 * 2. Update parking space status in Firestore
 * 3. Update zone-level statistics with atomic transactions
 * 4. Handle errors gracefully with proper logging
 */

const { Firestore } = require('@google-cloud/firestore');

// Initialize Firestore client with project configuration
const firestore = new Firestore({
  projectId: '${project_id}',
  // Enable retries for better reliability
  settings: {
    retries: 3,
    // Use cloud logging for better observability
    preferRest: true,
    // Configure timeout for operations
    clientConfig: {
      grpc: {
        keepalive_time_ms: 30000,
        keepalive_timeout_ms: 5000,
        keepalive_permit_without_calls: true,
        http2_max_pings_without_data: 0,
        http2_min_time_between_pings_ms: 10000,
        http2_min_ping_interval_without_data_ms: 300000
      }
    }
  }
});

// Collection references for parking data
const PARKING_SPACES_COLLECTION = '${parking_spaces_collection}';
const PARKING_ZONES_COLLECTION = '${parking_zones_collection}';

/**
 * Main Cloud Function entry point for processing parking sensor data
 * @param {Object} message - Pub/Sub message containing sensor data
 * @param {Object} context - Cloud Function context information
 * @returns {Promise<Object>} Processing result
 */
exports.processParkingData = async (message, context) => {
  console.log('Starting parking data processing...', {
    messageId: context.messageId,
    timestamp: context.timestamp,
    eventType: context.eventType
  });

  try {
    // Parse and validate sensor data from Pub/Sub message
    const sensorData = await parseSensorData(message);
    console.log('Parsed sensor data:', {
      spaceId: sensorData.space_id,
      occupied: sensorData.occupied,
      zone: sensorData.zone,
      confidence: sensorData.confidence
    });

    // Validate required fields in sensor data
    await validateSensorData(sensorData);

    // Update parking space status in Firestore
    await updateParkingSpace(sensorData);

    // Update zone-level statistics with atomic transaction
    await updateZoneStatistics(sensorData);

    console.log('Successfully processed parking data', {
      spaceId: sensorData.space_id,
      status: sensorData.occupied ? 'occupied' : 'available',
      zone: sensorData.zone || 'default'
    });

    return {
      success: true,
      space_id: sensorData.space_id,
      status: sensorData.occupied ? 'occupied' : 'available',
      processed_at: new Date().toISOString()
    };

  } catch (error) {
    console.error('Error processing parking data:', {
      error: error.message,
      stack: error.stack,
      messageId: context.messageId,
      messageData: message.data ? Buffer.from(message.data, 'base64').toString() : 'No data'
    });

    // Re-throw error to trigger Pub/Sub retry mechanism
    throw new Error(`Failed to process parking data: $${error.message}`);
  }
};

/**
 * Parse sensor data from Pub/Sub message
 * @param {Object} message - Pub/Sub message object
 * @returns {Object} Parsed sensor data
 */
async function parseSensorData(message) {
  if (!message.data) {
    throw new Error('No data found in Pub/Sub message');
  }

  try {
    // Decode base64 message data and parse JSON
    const messageData = Buffer.from(message.data, 'base64').toString();
    const sensorData = JSON.parse(messageData);

    // Add processing metadata
    sensorData.received_at = new Date().toISOString();
    sensorData.message_id = message.messageId || 'unknown';

    return sensorData;

  } catch (parseError) {
    throw new Error(`Failed to parse sensor data: $${parseError.message}`);
  }
}

/**
 * Validate required fields in sensor data
 * @param {Object} sensorData - Parsed sensor data
 * @throws {Error} If validation fails
 */
async function validateSensorData(sensorData) {
  const requiredFields = ['space_id', 'sensor_id', 'occupied'];
  const missingFields = requiredFields.filter(field => !(field in sensorData));

  if (missingFields.length > 0) {
    throw new Error(`Missing required fields: $${missingFields.join(', ')}`);
  }

  // Validate data types
  if (typeof sensorData.space_id !== 'string' || sensorData.space_id.trim() === '') {
    throw new Error('space_id must be a non-empty string');
  }

  if (typeof sensorData.sensor_id !== 'string' || sensorData.sensor_id.trim() === '') {
    throw new Error('sensor_id must be a non-empty string');
  }

  if (typeof sensorData.occupied !== 'boolean') {
    throw new Error('occupied must be a boolean value');
  }

  // Validate optional fields
  if (sensorData.confidence !== undefined) {
    if (typeof sensorData.confidence !== 'number' || sensorData.confidence < 0 || sensorData.confidence > 1) {
      throw new Error('confidence must be a number between 0 and 1');
    }
  }

  if (sensorData.location !== undefined) {
    if (!sensorData.location.lat || !sensorData.location.lng) {
      throw new Error('location must include lat and lng coordinates');
    }
  }
}

/**
 * Update parking space document in Firestore
 * @param {Object} sensorData - Validated sensor data
 */
async function updateParkingSpace(sensorData) {
  const spaceRef = firestore
    .collection(PARKING_SPACES_COLLECTION)
    .doc(sensorData.space_id);

  const updateData = {
    space_id: sensorData.space_id,
    status: sensorData.occupied ? 'occupied' : 'available',
    last_updated: Firestore.Timestamp.now(),
    sensor_id: sensorData.sensor_id,
    confidence: sensorData.confidence || 0.95,
    // Update location only if provided
    ...(sensorData.location && { location: sensorData.location }),
    // Store zone information
    ...(sensorData.zone && { zone: sensorData.zone }),
    // Add processing metadata
    last_message_id: sensorData.message_id,
    processed_at: Firestore.Timestamp.now()
  };

  try {
    // Use merge: true to preserve existing fields not being updated
    await spaceRef.set(updateData, { merge: true });

    console.log('Updated parking space document', {
      spaceId: sensorData.space_id,
      status: updateData.status,
      confidence: updateData.confidence
    });

  } catch (firestoreError) {
    throw new Error(`Failed to update parking space: $${firestoreError.message}`);
  }
}

/**
 * Update zone-level statistics using atomic transactions
 * @param {Object} sensorData - Validated sensor data
 */
async function updateZoneStatistics(sensorData) {
  const zoneName = sensorData.zone || 'default';
  const zoneRef = firestore
    .collection(PARKING_ZONES_COLLECTION)
    .doc(zoneName);

  try {
    await firestore.runTransaction(async (transaction) => {
      // Read current zone data
      const zoneDoc = await transaction.get(zoneRef);
      const zoneData = zoneDoc.data() || {
        zone_id: zoneName,
        available: 0,
        total: 0,
        spaces: {},
        last_updated: null,
        created_at: Firestore.Timestamp.now()
      };

      // Calculate availability changes
      const isNowAvailable = !sensorData.occupied;
      const wasAvailable = zoneData.spaces?.[sensorData.space_id] !== 'occupied';

      // Update availability count
      if (isNowAvailable && !wasAvailable) {
        zoneData.available = (zoneData.available || 0) + 1;
      } else if (!isNowAvailable && wasAvailable) {
        zoneData.available = Math.max((zoneData.available || 0) - 1, 0);
      }

      // Initialize spaces object if it doesn't exist
      zoneData.spaces = zoneData.spaces || {};

      // Update space status in zone tracking
      const previousStatus = zoneData.spaces[sensorData.space_id];
      zoneData.spaces[sensorData.space_id] = sensorData.occupied ? 'occupied' : 'available';

      // Update total count if this is a new space
      if (!previousStatus) {
        zoneData.total = (zoneData.total || 0) + 1;
        // If this is a new space and it's available, increment available count
        if (isNowAvailable) {
          zoneData.available = (zoneData.available || 0) + 1;
        }
      }

      // Update zone metadata
      zoneData.last_updated = Firestore.Timestamp.now();
      zoneData.occupancy_rate = zoneData.total > 0 ?
        ((zoneData.total - zoneData.available) / zoneData.total) : 0;

      // Atomic write to zone document
      transaction.set(zoneRef, zoneData, { merge: true });

      console.log('Updated zone statistics', {
        zone: zoneName,
        available: zoneData.available,
        total: zoneData.total,
        occupancyRate: (zoneData.occupancy_rate * 100).toFixed(1) + '%'
      });
    });

  } catch (transactionError) {
    throw new Error(`Failed to update zone statistics: $${transactionError.message}`);
  }
}

/**
 * Health check function for monitoring
 * @returns {Object} Health status
 */
exports.healthCheck = async () => {
  try {
    // Test Firestore connectivity
    await firestore.collection('_health_check').limit(1).get();

    return {
      status: 'healthy',
      timestamp: new Date().toISOString(),
      services: {
        firestore: 'connected'
      }
    };

  } catch (error) {
    return {
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      error: error.message
    };
  }
};