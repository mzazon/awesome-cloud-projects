/**
 * Supply Chain Event Processor Cloud Function
 * Processes supply chain events from Pub/Sub and updates Cloud SQL database
 */

const {PubSub} = require('@google-cloud/pubsub');
const {SecretManagerServiceClient} = require('@google-cloud/secret-manager');
const {Client} = require('pg');

// Initialize clients
const pubsub = new PubSub({
  projectId: '${project_id}'
});
const secretClient = new SecretManagerServiceClient();

// Database configuration
const DB_CONFIG = {
  host: process.env.DB_INSTANCE || 'localhost',
  database: process.env.DB_NAME || 'supply_chain',
  user: process.env.DB_USER || 'supply_chain_user',
  port: 5432,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
  connectionTimeoutMillis: 30000,
  idleTimeoutMillis: 30000,
  max: 10
};

/**
 * Retrieves database password from Secret Manager
 */
async function getDatabasePassword() {
  try {
    const secretName = `projects/${process.env.PROJECT_ID}/secrets/${process.env.DB_PASSWORD}/versions/latest`;
    const [version] = await secretClient.accessSecretVersion({
      name: secretName
    });
    return version.payload.data.toString();
  } catch (error) {
    console.error('Failed to retrieve database password from Secret Manager:', error);
    // Fallback to environment variable for local development
    return process.env.DB_PASSWORD;
  }
}

/**
 * Creates a database connection with retry logic
 */
async function createDatabaseConnection() {
  const password = await getDatabasePassword();
  const config = {
    ...DB_CONFIG,
    password: password
  };

  const client = new Client(config);
  
  // Retry connection up to 3 times
  let attempts = 0;
  const maxAttempts = 3;
  
  while (attempts < maxAttempts) {
    try {
      await client.connect();
      console.log('Successfully connected to database');
      return client;
    } catch (error) {
      attempts++;
      console.error(`Database connection attempt ${attempts} failed:`, error.message);
      
      if (attempts >= maxAttempts) {
        throw new Error(`Failed to connect to database after ${maxAttempts} attempts: ${error.message}`);
      }
      
      // Wait before retrying (exponential backoff)
      await new Promise(resolve => setTimeout(resolve, 1000 * Math.pow(2, attempts - 1)));
    }
  }
}

/**
 * Validates supply chain event data
 */
function validateEventData(eventData) {
  const requiredFields = [
    'product_id', 
    'supplier_id', 
    'transaction_type', 
    'quantity', 
    'location'
  ];
  
  const missing = requiredFields.filter(field => !eventData[field]);
  if (missing.length > 0) {
    throw new Error(`Missing required fields: ${missing.join(', ')}`);
  }
  
  // Validate data types
  if (typeof eventData.product_id !== 'number' || eventData.product_id <= 0) {
    throw new Error('product_id must be a positive number');
  }
  
  if (typeof eventData.supplier_id !== 'number' || eventData.supplier_id <= 0) {
    throw new Error('supplier_id must be a positive number');
  }
  
  if (typeof eventData.quantity !== 'number' || eventData.quantity <= 0) {
    throw new Error('quantity must be a positive number');
  }
  
  // Validate transaction type
  const validTypes = ['MANUFACTURE', 'SHIP', 'RECEIVE', 'TRANSFER', 'QUALITY_CHECK', 'DELIVER'];
  if (!validTypes.includes(eventData.transaction_type.toUpperCase())) {
    throw new Error(`Invalid transaction_type. Must be one of: ${validTypes.join(', ')}`);
  }
  
  return true;
}

/**
 * Inserts transaction into database
 */
async function insertTransaction(client, eventData) {
  const query = `
    INSERT INTO transactions (
      product_id, 
      supplier_id, 
      transaction_type, 
      quantity, 
      location, 
      blockchain_hash,
      timestamp,
      verified
    )
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
    RETURNING transaction_id, timestamp
  `;
  
  const values = [
    eventData.product_id,
    eventData.supplier_id,
    eventData.transaction_type.toUpperCase(),
    eventData.quantity,
    eventData.location,
    eventData.blockchain_hash || null,
    eventData.timestamp || new Date().toISOString(),
    false // Initially unverified
  ];
  
  try {
    const result = await client.query(query, values);
    console.log(`Transaction inserted with ID: ${result.rows[0].transaction_id}`);
    return result.rows[0];
  } catch (error) {
    console.error('Database insertion error:', error);
    throw new Error(`Failed to insert transaction: ${error.message}`);
  }
}

/**
 * Publishes verification request to blockchain verification topic
 */
async function publishVerificationRequest(transactionData) {
  try {
    const verificationData = {
      transaction_id: transactionData.transaction_id,
      blockchain_hash: transactionData.blockchain_hash,
      timestamp: transactionData.timestamp,
      verification_type: 'SUPPLY_CHAIN_EVENT'
    };
    
    const topic = pubsub.topic('${project_id}', 'blockchain-verification');
    await topic.publish(Buffer.from(JSON.stringify(verificationData)));
    
    console.log(`Verification request published for transaction ${transactionData.transaction_id}`);
  } catch (error) {
    console.error('Failed to publish verification request:', error);
    // Don't throw here - this is a non-critical operation
  }
}

/**
 * Main function to process supply chain events
 */
exports.processSupplyChainEvent = async (cloudEvent) => {
  console.log('Processing supply chain event:', JSON.stringify(cloudEvent, null, 2));
  
  let client;
  
  try {
    // Parse the Pub/Sub message
    const pubsubMessage = cloudEvent.data;
    const eventData = JSON.parse(Buffer.from(pubsubMessage.data, 'base64').toString());
    
    console.log('Decoded event data:', JSON.stringify(eventData, null, 2));
    
    // Validate event data
    validateEventData(eventData);
    
    // Create database connection
    client = await createDatabaseConnection();
    
    // Start transaction for data consistency
    await client.query('BEGIN');
    
    try {
      // Insert transaction record
      const transactionResult = await insertTransaction(client, eventData);
      
      // Commit transaction
      await client.query('COMMIT');
      
      // Publish to blockchain verification queue (async, non-blocking)
      if (eventData.blockchain_hash) {
        await publishVerificationRequest({
          ...transactionResult,
          blockchain_hash: eventData.blockchain_hash
        });
      }
      
      console.log(`Successfully processed supply chain event for transaction ${transactionResult.transaction_id}`);
      
    } catch (error) {
      // Rollback on error
      await client.query('ROLLBACK');
      throw error;
    }
    
  } catch (error) {
    console.error('Error processing supply chain event:', error);
    
    // Log error details for debugging
    console.error('Error details:', {
      message: error.message,
      stack: error.stack,
      timestamp: new Date().toISOString()
    });
    
    throw error; // Re-throw to trigger Pub/Sub retry
    
  } finally {
    // Clean up database connection
    if (client) {
      try {
        await client.end();
        console.log('Database connection closed');
      } catch (error) {
        console.error('Error closing database connection:', error);
      }
    }
  }
};