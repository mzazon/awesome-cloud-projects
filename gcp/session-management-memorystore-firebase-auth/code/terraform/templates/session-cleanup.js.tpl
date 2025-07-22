const functions = require('@google-cloud/functions-framework');
const redis = require('redis');
const { SecretManagerServiceClient } = require('@google-cloud/secret-manager');
const { Logging } = require('@google-cloud/logging');

const secretClient = new SecretManagerServiceClient();
const logging = new Logging();
const log = logging.log('session-cleanup');

/**
 * Session cleanup function for automated maintenance
 */
functions.cloudEvent('sessionCleanup', async (cloudEvent) => {
  console.log('Session cleanup started at:', new Date().toISOString());
  
  let client;
  try {
    // Get Redis connection from Secret Manager
    const [version] = await secretClient.accessSecretVersion({
      name: '${secret_name}/versions/latest',
    });
    
    const secretPayload = JSON.parse(version.payload.data.toString());
    
    client = redis.createClient({ 
      url: secretPayload.connection_url,
      socket: {
        reconnectStrategy: (retries) => Math.min(retries * 50, 500)
      }
    });
    
    client.on('error', (err) => {
      console.error('Redis Client Error:', err);
    });
    
    await client.connect();
    console.log('Connected to Redis for cleanup operation');
    
    // Configuration
    const sessionTtlHours = ${session_ttl_hours};
    const batchSize = 100;
    const maxProcessingTime = 240000; // 4 minutes max processing time
    const startTime = Date.now();
    
    // Find sessions older than TTL
    let cursor = 0;
    let totalProcessed = 0;
    let cleanedCount = 0;
    let activeCount = 0;
    let errorCount = 0;
    
    do {
      if (Date.now() - startTime > maxProcessingTime) {
        console.log('Reached maximum processing time, stopping cleanup');
        break;
      }
      
      // Scan for session keys in batches
      const result = await client.scan(cursor, {
        MATCH: 'session:*',
        COUNT: batchSize
      });
      
      cursor = result.cursor;
      const keys = result.keys;
      
      if (keys.length === 0) {
        continue;
      }
      
      // Process each session
      for (const key of keys) {
        try {
          const sessionData = await client.get(key);
          if (sessionData) {
            const session = JSON.parse(sessionData);
            const hoursSinceLastAccess = (Date.now() - session.lastAccessed) / (1000 * 60 * 60);
            
            if (hoursSinceLastAccess > sessionTtlHours) {
              await client.del(key);
              cleanedCount++;
              console.log(`Cleaned expired session: $${key} (inactive for $${hoursSinceLastAccess.toFixed(1)} hours)`);
            } else {
              activeCount++;
            }
          } else {
            // Key exists but no data - clean it up
            await client.del(key);
            cleanedCount++;
          }
          
          totalProcessed++;
        } catch (sessionError) {
          errorCount++;
          console.error(`Error processing session $${key}:`, sessionError.message);
        }
      }
      
      // Small delay between batches to avoid overwhelming Redis
      if (cursor !== 0) {
        await new Promise(resolve => setTimeout(resolve, 10));
      }
      
    } while (cursor !== 0);
    
    // Generate cleanup statistics
    const endTime = Date.now();
    const processingTimeSeconds = (endTime - startTime) / 1000;
    
    const cleanupStats = {
      totalProcessed,
      cleanedSessions: cleanedCount,
      activeSessions: activeCount,
      errorCount,
      processingTimeSeconds: processingTimeSeconds.toFixed(2),
      sessionTtlHours,
      timestamp: new Date().toISOString()
    };
    
    // Log comprehensive cleanup results
    await log.info({
      message: 'Session cleanup completed successfully',
      ...cleanupStats
    });
    
    console.log('Session cleanup completed:', cleanupStats);
    
    // Optional: Store cleanup metrics in Redis for monitoring
    try {
      await client.setEx(
        'cleanup:last_run', 
        86400, // 24 hours TTL
        JSON.stringify(cleanupStats)
      );
    } catch (metricsError) {
      console.warn('Failed to store cleanup metrics:', metricsError.message);
    }
    
  } catch (error) {
    await log.error({ 
      message: 'Session cleanup failed', 
      error: error.message,
      stack: error.stack 
    });
    console.error('Session cleanup failed:', error);
    throw error;
  } finally {
    // Ensure Redis connection is closed
    if (client) {
      try {
        await client.disconnect();
        console.log('Redis connection closed');
      } catch (disconnectError) {
        console.warn('Error closing Redis connection:', disconnectError.message);
      }
    }
  }
});

/**
 * HTTP trigger for manual cleanup invocation
 */
functions.http('sessionCleanup', async (req, res) => {
  // Set CORS headers
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
  
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }
  
  try {
    console.log('Manual session cleanup triggered');
    
    // Create a mock cloud event for the cleanup function
    const mockCloudEvent = {
      trigger: 'manual',
      timestamp: new Date().toISOString()
    };
    
    // Call the cleanup function
    await functions.cloudEvent('sessionCleanup')(mockCloudEvent);
    
    res.json({ 
      success: true, 
      message: 'Session cleanup completed successfully',
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    console.error('Manual cleanup failed:', error);
    await log.error({ 
      message: 'Manual session cleanup failed', 
      error: error.message 
    });
    res.status(500).json({ 
      error: 'Cleanup failed', 
      message: error.message 
    });
  }
});