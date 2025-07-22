/**
 * Supply Chain API Ingestion Cloud Function
 * Provides HTTP endpoint for supply chain partners to submit transaction data
 */

const {PubSub} = require('@google-cloud/pubsub');
const crypto = require('crypto');

// Initialize Pub/Sub client
const pubsub = new PubSub({
  projectId: '${project_id}'
});

// Configuration
const PUBSUB_TOPIC = process.env.PUBSUB_TOPIC || 'supply-chain-events';
const MAX_REQUEST_SIZE = 1024 * 1024; // 1MB

/**
 * Validates incoming request data
 */
function validateRequestData(data) {
  // Check required fields
  const requiredFields = ['product_id', 'supplier_id', 'transaction_type', 'quantity', 'location'];
  const missing = requiredFields.filter(field => !data[field]);
  
  if (missing.length > 0) {
    throw new Error(`Missing required fields: ${missing.join(', ')}`);
  }
  
  // Validate data types and ranges
  if (typeof data.product_id !== 'number' || data.product_id <= 0) {
    throw new Error('product_id must be a positive number');
  }
  
  if (typeof data.supplier_id !== 'number' || data.supplier_id <= 0) {
    throw new Error('supplier_id must be a positive number');
  }
  
  if (typeof data.quantity !== 'number' || data.quantity <= 0) {
    throw new Error('quantity must be a positive number');
  }
  
  if (typeof data.location !== 'string' || data.location.trim().length === 0) {
    throw new Error('location must be a non-empty string');
  }
  
  if (data.location.length > 255) {
    throw new Error('location must be 255 characters or less');
  }
  
  // Validate transaction type
  const validTypes = ['MANUFACTURE', 'SHIP', 'RECEIVE', 'TRANSFER', 'QUALITY_CHECK', 'DELIVER'];
  const transactionType = data.transaction_type.toUpperCase();
  
  if (!validTypes.includes(transactionType)) {
    throw new Error(`Invalid transaction_type. Must be one of: ${validTypes.join(', ')}`);
  }
  
  // Validate optional fields
  if (data.batch_number && typeof data.batch_number !== 'string') {
    throw new Error('batch_number must be a string');
  }
  
  if (data.temperature && (typeof data.temperature !== 'number' || data.temperature < -100 || data.temperature > 100)) {
    throw new Error('temperature must be a number between -100 and 100 Celsius');
  }
  
  if (data.quality_score && (typeof data.quality_score !== 'number' || data.quality_score < 0 || data.quality_score > 100)) {
    throw new Error('quality_score must be a number between 0 and 100');
  }
  
  return true;
}

/**
 * Generates blockchain hash for the event
 */
function generateBlockchainHash(eventData) {
  // Create deterministic hash from event data
  const hashInput = {
    product_id: eventData.product_id,
    supplier_id: eventData.supplier_id,
    transaction_type: eventData.transaction_type.toUpperCase(),
    quantity: eventData.quantity,
    location: eventData.location.trim(),
    timestamp: eventData.timestamp,
    batch_number: eventData.batch_number || null
  };
  
  const hashString = JSON.stringify(hashInput, Object.keys(hashInput).sort());
  return '0x' + crypto.createHash('sha256').update(hashString).digest('hex');
}

/**
 * Enriches event data with metadata
 */
function enrichEventData(rawData) {
  const timestamp = new Date().toISOString();
  
  const enrichedData = {
    ...rawData,
    transaction_type: rawData.transaction_type.toUpperCase(),
    location: rawData.location.trim(),
    timestamp: timestamp,
    source: 'api_ingestion',
    version: '1.0'
  };
  
  // Generate blockchain hash
  enrichedData.blockchain_hash = generateBlockchainHash(enrichedData);
  
  // Add optional metadata
  if (rawData.batch_number) {
    enrichedData.batch_number = rawData.batch_number.trim();
  }
  
  if (typeof rawData.temperature === 'number') {
    enrichedData.temperature = rawData.temperature;
  }
  
  if (typeof rawData.quality_score === 'number') {
    enrichedData.quality_score = rawData.quality_score;
  }
  
  if (rawData.notes) {
    enrichedData.notes = rawData.notes.trim().substring(0, 500); // Limit notes length
  }
  
  return enrichedData;
}

/**
 * Publishes event to Pub/Sub topic
 */
async function publishEvent(eventData) {
  try {
    const topic = pubsub.topic(PUBSUB_TOPIC);
    
    // Add message attributes for routing and filtering
    const messageAttributes = {
      eventType: 'supply_chain_transaction',
      transactionType: eventData.transaction_type,
      supplierId: eventData.supplier_id.toString(),
      productId: eventData.product_id.toString(),
      timestamp: eventData.timestamp
    };
    
    // Publish message
    const messageId = await topic.publishMessage({
      data: Buffer.from(JSON.stringify(eventData)),
      attributes: messageAttributes
    });
    
    console.log(`Event published to Pub/Sub with message ID: ${messageId}`);
    return messageId;
    
  } catch (error) {
    console.error('Failed to publish event to Pub/Sub:', error);
    throw new Error(`Failed to publish event: ${error.message}`);
  }
}

/**
 * Handles CORS headers
 */
function setCorsHeaders(res) {
  res.set({
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-API-Key',
    'Access-Control-Max-Age': '3600',
    'Content-Type': 'application/json'
  });
}

/**
 * Main HTTP function for supply chain data ingestion
 */
exports.supplyChainIngestion = async (req, res) => {
  console.log(`Received ${req.method} request to supply chain ingestion API`);
  
  // Set CORS headers
  setCorsHeaders(res);
  
  // Handle preflight OPTIONS request
  if (req.method === 'OPTIONS') {
    res.status(200).send('');
    return;
  }
  
  // Only allow POST requests
  if (req.method !== 'POST') {
    console.log(`Method ${req.method} not allowed`);
    res.status(405).json({
      error: 'Method Not Allowed',
      message: 'Only POST requests are accepted',
      allowed_methods: ['POST']
    });
    return;
  }
  
  try {
    // Check request size
    const contentLength = parseInt(req.get('content-length') || '0');
    if (contentLength > MAX_REQUEST_SIZE) {
      res.status(413).json({
        error: 'Request Too Large',
        message: `Request size ${contentLength} exceeds maximum allowed size ${MAX_REQUEST_SIZE} bytes`
      });
      return;
    }
    
    // Parse request body
    if (!req.body || typeof req.body !== 'object') {
      res.status(400).json({
        error: 'Bad Request',
        message: 'Request body must be valid JSON'
      });
      return;
    }
    
    console.log('Processing supply chain event:', JSON.stringify(req.body, null, 2));
    
    // Validate request data
    validateRequestData(req.body);
    
    // Enrich event data
    const enrichedEventData = enrichEventData(req.body);
    
    // Publish to Pub/Sub
    const messageId = await publishEvent(enrichedEventData);
    
    // Return success response
    const response = {
      success: true,
      message: 'Supply chain event processed successfully',
      transaction_hash: enrichedEventData.blockchain_hash,
      timestamp: enrichedEventData.timestamp,
      message_id: messageId,
      event_id: `${enrichedEventData.product_id}-${enrichedEventData.supplier_id}-${Date.now()}`
    };
    
    console.log('Successfully processed supply chain event:', response.event_id);
    res.status(200).json(response);
    
  } catch (error) {
    console.error('Error processing supply chain ingestion request:', error);
    
    // Determine error type and status code
    let statusCode = 500;
    let errorType = 'Internal Server Error';
    
    if (error.message.includes('Missing required fields') || 
        error.message.includes('must be') || 
        error.message.includes('Invalid transaction_type')) {
      statusCode = 400;
      errorType = 'Bad Request';
    }
    
    const errorResponse = {
      error: errorType,
      message: error.message,
      timestamp: new Date().toISOString(),
      request_id: req.get('X-Cloud-Trace-Context') || 'unknown'
    };
    
    res.status(statusCode).json(errorResponse);
  }
};