const functions = require('@google-cloud/functions-framework');
const admin = require('firebase-admin');
const redis = require('redis');
const { SecretManagerServiceClient } = require('@google-cloud/secret-manager');
const { Logging } = require('@google-cloud/logging');

// Initialize Firebase Admin SDK
admin.initializeApp();

// Initialize clients
const secretClient = new SecretManagerServiceClient();
const logging = new Logging();
const log = logging.log('session-manager');

let redisClient;

/**
 * Initialize Redis client with connection details from Secret Manager
 */
async function initializeRedis() {
  if (!redisClient) {
    try {
      // Get Redis connection details from Secret Manager
      const [version] = await secretClient.accessSecretVersion({
        name: '${secret_name}/versions/latest',
      });
      
      const secretPayload = JSON.parse(version.payload.data.toString());
      
      redisClient = redis.createClient({ 
        url: secretPayload.connection_url,
        socket: {
          reconnectStrategy: (retries) => Math.min(retries * 50, 500)
        }
      });
      
      redisClient.on('error', (err) => {
        console.error('Redis Client Error:', err);
      });
      
      await redisClient.connect();
      console.log('Redis client connected successfully');
    } catch (error) {
      console.error('Failed to initialize Redis client:', error);
      throw error;
    }
  }
  return redisClient;
}

/**
 * Session management function with Firebase Auth integration
 */
functions.http('sessionManager', async (req, res) => {
  // Set CORS headers
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  
  try {
    const client = await initializeRedis();
    const { action, token, sessionData, sessionId } = req.body;
    
    if (!action) {
      return res.status(400).json({ error: 'Action parameter is required' });
    }
    
    // For create and validate actions, verify Firebase token
    let decodedToken, userId;
    if (action === 'create' || action === 'validate') {
      if (!token) {
        return res.status(400).json({ error: 'Firebase token is required' });
      }
      
      try {
        decodedToken = await admin.auth().verifyIdToken(token);
        userId = decodedToken.uid;
      } catch (error) {
        await log.warning({ 
          message: 'Invalid Firebase token', 
          error: error.message,
          action: action 
        });
        return res.status(401).json({ error: 'Invalid authentication token' });
      }
    }
    
    const sessionKey = sessionId || `session:$${userId}`;
    
    switch (action) {
      case 'create':
        try {
          const session = {
            userId,
            email: decodedToken.email,
            createdAt: Date.now(),
            lastAccessed: Date.now(),
            deviceInfo: req.headers['user-agent'] || 'unknown',
            ipAddress: req.ip || req.connection.remoteAddress || 'unknown',
            sessionId: sessionKey,
            ...sessionData
          };
          
          // Set session with 1 hour TTL (3600 seconds)
          await client.setEx(sessionKey, 3600, JSON.stringify(session));
          
          await log.info({ 
            message: 'Session created successfully', 
            userId, 
            sessionKey,
            email: decodedToken.email 
          });
          
          res.json({ 
            success: true, 
            sessionId: sessionKey,
            expiresAt: Date.now() + (3600 * 1000)
          });
        } catch (error) {
          await log.error({ 
            message: 'Failed to create session', 
            error: error.message, 
            userId 
          });
          res.status(500).json({ error: 'Failed to create session' });
        }
        break;
        
      case 'validate':
        try {
          const existingSession = await client.get(sessionKey);
          if (existingSession) {
            const sessionObj = JSON.parse(existingSession);
            
            // Update last accessed time
            sessionObj.lastAccessed = Date.now();
            await client.setEx(sessionKey, 3600, JSON.stringify(sessionObj));
            
            await log.info({ 
              message: 'Session validated successfully', 
              userId, 
              sessionKey 
            });
            
            res.json({ 
              valid: true, 
              session: sessionObj,
              expiresAt: Date.now() + (3600 * 1000)
            });
          } else {
            await log.info({ 
              message: 'Session not found or expired', 
              userId, 
              sessionKey 
            });
            res.json({ valid: false });
          }
        } catch (error) {
          await log.error({ 
            message: 'Failed to validate session', 
            error: error.message, 
            userId 
          });
          res.status(500).json({ error: 'Failed to validate session' });
        }
        break;
        
      case 'destroy':
        try {
          if (!sessionId) {
            return res.status(400).json({ error: 'Session ID is required for destroy action' });
          }
          
          const result = await client.del(sessionId);
          
          await log.info({ 
            message: 'Session destroyed', 
            sessionId,
            deleted: result > 0 
          });
          
          res.json({ 
            success: true, 
            deleted: result > 0 
          });
        } catch (error) {
          await log.error({ 
            message: 'Failed to destroy session', 
            error: error.message, 
            sessionId 
          });
          res.status(500).json({ error: 'Failed to destroy session' });
        }
        break;
        
      case 'list':
        try {
          // Admin action - list all sessions (with pagination)
          const pattern = req.body.pattern || 'session:*';
          const limit = Math.min(req.body.limit || 100, 1000);
          
          const keys = await client.keys(pattern);
          const sessions = [];
          
          for (let i = 0; i < Math.min(keys.length, limit); i++) {
            try {
              const sessionData = await client.get(keys[i]);
              if (sessionData) {
                const session = JSON.parse(sessionData);
                sessions.push({
                  sessionId: keys[i],
                  userId: session.userId,
                  email: session.email,
                  createdAt: session.createdAt,
                  lastAccessed: session.lastAccessed
                });
              }
            } catch (parseError) {
              console.warn(`Failed to parse session data for key: $${keys[i]}`);
            }
          }
          
          await log.info({ 
            message: 'Sessions listed', 
            count: sessions.length,
            totalKeys: keys.length 
          });
          
          res.json({ 
            sessions,
            total: keys.length,
            returned: sessions.length 
          });
        } catch (error) {
          await log.error({ 
            message: 'Failed to list sessions', 
            error: error.message 
          });
          res.status(500).json({ error: 'Failed to list sessions' });
        }
        break;
        
      default:
        res.status(400).json({ 
          error: 'Invalid action',
          validActions: ['create', 'validate', 'destroy', 'list']
        });
    }
  } catch (error) {
    await log.error({ 
      message: 'Session operation failed', 
      error: error.message,
      action: req.body?.action 
    });
    res.status(500).json({ error: 'Internal server error' });
  }
});