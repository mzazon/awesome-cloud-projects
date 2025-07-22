/**
 * User Lifecycle Management Worker Service
 * 
 * This Cloud Run service processes user lifecycle tasks including:
 * - User engagement tracking and scoring
 * - Lifecycle stage transitions 
 * - Automated retention campaigns
 * - Analytics processing and reporting
 */

const express = require('express');
const cors = require('cors');
const { CloudTasksClient } = require('@google-cloud/tasks');
const { Logging } = require('@google-cloud/logging');
const { SecretManagerServiceClient } = require('@google-cloud/secret-manager');
const admin = require('firebase-admin');
const { Pool } = require('pg');

// Initialize Firebase Admin SDK
if (!admin.apps.length) {
  admin.initializeApp();
}

// Initialize services
const app = express();
const tasksClient = new CloudTasksClient();
const logging = new Logging();
const log = logging.log('user-lifecycle');
const secretManagerClient = new SecretManagerServiceClient();

// Environment variables
const PROJECT_ID = process.env.PROJECT_ID || '${project_id}';
const REGION = process.env.REGION || '${region}';
const TASK_QUEUE_NAME = process.env.TASK_QUEUE_NAME || '${task_queue_name}';
const CONNECTION_NAME = process.env.CONNECTION_NAME || '${connection_name}';
const WORKER_SERVICE_NAME = process.env.WORKER_SERVICE_NAME || '${worker_service_name}';
const PORT = process.env.PORT || 8080;

// Database connection pool
let dbPool = null;

// Initialize database connection
async function initializeDatabase() {
  try {
    // Get database password from Secret Manager
    const [version] = await secretManagerClient.accessSecretVersion({
      name: `projects/$${PROJECT_ID}/secrets/user-lifecycle-db-password/versions/latest`,
    });
    
    const dbPassword = version.payload.data.toString();
    
    // Create database connection pool
    dbPool = new Pool({
      host: `/cloudsql/$${CONNECTION_NAME}`,
      user: 'app_user',
      password: dbPassword,
      database: 'user_analytics',
      ssl: {
        rejectUnauthorized: false
      },
      max: 5,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 2000,
    });
    
    // Test database connection
    await dbPool.query('SELECT NOW()');
    console.log('✅ Database connection established successfully');
    
    return dbPool;
  } catch (error) {
    console.error('❌ Failed to initialize database connection:', error);
    throw error;
  }
}

// Middleware
app.use(express.json({ limit: '10mb' }));
app.use(cors({
  origin: ['https://localhost:3000', 'https://*.web.app', 'https://*.firebaseapp.com'],
  credentials: true
}));

// Request logging middleware
app.use((req, res, next) => {
  const start = Date.now();
  const reqId = Math.random().toString(36).substr(2, 9);
  
  req.requestId = reqId;
  console.log(`[${reqId}] ${req.method} ${req.path} - ${req.ip}`);
  
  res.on('finish', () => {
    const duration = Date.now() - start;
    console.log(`[${reqId}] ${res.statusCode} - ${duration}ms`);
  });
  
  next();
});

// ============================================================================
// HEALTH CHECK ENDPOINTS
// ============================================================================

// Health check endpoint for Cloud Run
app.get('/health', async (req, res) => {
  try {
    // Check database connection
    if (dbPool) {
      await dbPool.query('SELECT 1');
    }
    
    res.status(200).json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      version: '1.0.0',
      services: {
        database: dbPool ? 'connected' : 'disconnected',
        firebase: admin.apps.length > 0 ? 'initialized' : 'not-initialized'
      }
    });
  } catch (error) {
    console.error('Health check failed:', error);
    res.status(503).json({
      status: 'unhealthy',
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// Readiness probe endpoint
app.get('/ready', async (req, res) => {
  try {
    if (!dbPool) {
      throw new Error('Database not initialized');
    }
    
    await dbPool.query('SELECT 1');
    res.status(200).json({ status: 'ready' });
  } catch (error) {
    res.status(503).json({ status: 'not-ready', error: error.message });
  }
});

// ============================================================================
// TASK PROCESSING ENDPOINTS
// ============================================================================

// Process user engagement task
app.post('/tasks/process-engagement', async (req, res) => {
  const { requestId } = req;
  
  try {
    const { firebase_uid, activity_type, activity_data, task_type, scheduled } = req.body;
    
    await log.info(`[${requestId}] Processing engagement task`, {
      firebase_uid,
      activity_type,
      task_type,
      scheduled: scheduled || false
    });
    
    if (task_type === 'daily_analysis') {
      // Process daily engagement analysis for all users
      await processDailyEngagementAnalysis(requestId);
    } else if (firebase_uid && activity_type) {
      // Process individual user engagement event
      await processUserEngagement(requestId, firebase_uid, activity_type, activity_data);
    } else {
      throw new Error('Invalid task parameters');
    }
    
    await log.info(`[${requestId}] Engagement task completed successfully`);
    res.status(200).json({ 
      status: 'success',
      message: 'Engagement task processed successfully',
      requestId 
    });
    
  } catch (error) {
    await log.error(`[${requestId}] Failed to process engagement task`, { 
      error: error.message,
      stack: error.stack 
    });
    res.status(500).json({ 
      status: 'error',
      error: error.message,
      requestId 
    });
  }
});

// Process retention campaign task
app.post('/tasks/retention-campaign', async (req, res) => {
  const { requestId } = req;
  
  try {
    const { firebase_uid, campaign_type, task_type, scheduled } = req.body;
    
    await log.info(`[${requestId}] Processing retention campaign`, {
      firebase_uid,
      campaign_type,
      task_type,
      scheduled: scheduled || false
    });
    
    if (task_type === 'weekly_retention') {
      await processWeeklyRetentionCheck(requestId);
    } else if (task_type === 'lifecycle_review') {
      await processMonthlyLifecycleReview(requestId);
    } else if (firebase_uid && campaign_type) {
      await processRetentionCampaign(requestId, firebase_uid, campaign_type);
    } else {
      throw new Error('Invalid campaign parameters');
    }
    
    await log.info(`[${requestId}] Retention campaign completed successfully`);
    res.status(200).json({ 
      status: 'success',
      message: 'Retention campaign processed successfully',
      requestId 
    });
    
  } catch (error) {
    await log.error(`[${requestId}] Failed to process retention campaign`, { 
      error: error.message,
      stack: error.stack 
    });
    res.status(500).json({ 
      status: 'error',
      error: error.message,
      requestId 
    });
  }
});

// ============================================================================
// BUSINESS LOGIC FUNCTIONS
// ============================================================================

// Process individual user engagement event
async function processUserEngagement(requestId, firebase_uid, activity_type, activity_data) {
  if (!dbPool) throw new Error('Database not initialized');
  
  const client = await dbPool.connect();
  
  try {
    await client.query('BEGIN');
    
    // Record user activity
    await client.query(
      'INSERT INTO user_activities (firebase_uid, activity_type, activity_data) VALUES ($1, $2, $3)',
      [firebase_uid, activity_type, JSON.stringify(activity_data || {})]
    );
    
    // Update user engagement metrics
    await updateEngagementScore(client, firebase_uid);
    
    // Check for lifecycle transitions
    await checkLifecycleTransition(client, requestId, firebase_uid);
    
    await client.query('COMMIT');
    console.log(`[${requestId}] ✅ Processed engagement for user: ${firebase_uid}`);
    
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

// Update engagement score based on recent activity
async function updateEngagementScore(client, firebase_uid) {
  const result = await client.query(`
    SELECT 
      COUNT(*) as activity_count,
      EXTRACT(EPOCH FROM (NOW() - MIN(timestamp)))/86400 as days_active
    FROM user_activities 
    WHERE firebase_uid = $1 AND timestamp > NOW() - INTERVAL '30 days'
  `, [firebase_uid]);
  
  const { activity_count, days_active } = result.rows[0];
  const engagement_score = Math.min(100, (parseInt(activity_count) * 2) + (parseFloat(days_active) * 3));
  
  await client.query(`
    INSERT INTO user_engagement (firebase_uid, engagement_score, last_activity, updated_at)
    VALUES ($1, $2, NOW(), NOW())
    ON CONFLICT (firebase_uid) 
    DO UPDATE SET 
      engagement_score = $2, 
      last_activity = NOW(), 
      updated_at = NOW()
  `, [firebase_uid, engagement_score]);
}

// Check for lifecycle stage transitions
async function checkLifecycleTransition(client, requestId, firebase_uid) {
  const result = await client.query(
    'SELECT engagement_score, lifecycle_stage FROM user_engagement WHERE firebase_uid = $1',
    [firebase_uid]
  );
  
  if (result.rows.length === 0) return;
  
  const { engagement_score, lifecycle_stage } = result.rows[0];
  let new_stage = lifecycle_stage;
  
  // Determine new lifecycle stage based on engagement score
  if (engagement_score > 80 && lifecycle_stage !== 'champion') {
    new_stage = 'champion';
  } else if (engagement_score > 50 && lifecycle_stage === 'new') {
    new_stage = 'active';
  } else if (engagement_score < 20 && lifecycle_stage !== 'at_risk') {
    new_stage = 'at_risk';
  }
  
  // Update lifecycle stage if changed
  if (new_stage !== lifecycle_stage) {
    await client.query(
      'UPDATE user_engagement SET lifecycle_stage = $1 WHERE firebase_uid = $2',
      [new_stage, firebase_uid]
    );
    
    console.log(`[${requestId}] 🔄 User ${firebase_uid} transitioned from ${lifecycle_stage} to ${new_stage}`);
    
    // Schedule appropriate retention campaign for at-risk users
    if (new_stage === 'at_risk') {
      await scheduleRetentionCampaign(firebase_uid, 'at_risk_email');
    }
  }
}

// Process daily engagement analysis for all users
async function processDailyEngagementAnalysis(requestId) {
  if (!dbPool) throw new Error('Database not initialized');
  
  const client = await dbPool.connect();
  
  try {
    // Get all users who have been active in the last 60 days
    const result = await client.query(`
      SELECT DISTINCT firebase_uid 
      FROM user_activities 
      WHERE timestamp > NOW() - INTERVAL '60 days'
    `);
    
    console.log(`[${requestId}] 📊 Processing daily analysis for ${result.rows.length} users`);
    
    for (const row of result.rows) {
      await updateEngagementScore(client, row.firebase_uid);
      await checkLifecycleTransition(client, requestId, row.firebase_uid);
    }
    
    console.log(`[${requestId}] ✅ Daily engagement analysis completed`);
    
  } finally {
    client.release();
  }
}

// Process weekly retention check for at-risk users
async function processWeeklyRetentionCheck(requestId) {
  if (!dbPool) throw new Error('Database not initialized');
  
  const client = await dbPool.connect();
  
  try {
    // Find at-risk users who haven't been contacted recently
    const result = await client.query(`
      SELECT ue.firebase_uid, ue.engagement_score, ue.last_activity
      FROM user_engagement ue
      LEFT JOIN lifecycle_actions la ON ue.firebase_uid = la.firebase_uid 
        AND la.action_type = 'weekly_retention_email'
        AND la.created_at > NOW() - INTERVAL '7 days'
      WHERE ue.lifecycle_stage = 'at_risk' 
        AND ue.last_activity > NOW() - INTERVAL '30 days'
        AND la.id IS NULL
    `);
    
    console.log(`[${requestId}] 📧 Found ${result.rows.length} at-risk users for retention campaigns`);
    
    for (const row of result.rows) {
      await scheduleRetentionCampaign(row.firebase_uid, 'weekly_retention_email');
    }
    
    console.log(`[${requestId}] ✅ Weekly retention check completed`);
    
  } finally {
    client.release();
  }
}

// Process monthly lifecycle review
async function processMonthlyLifecycleReview(requestId) {
  if (!dbPool) throw new Error('Database not initialized');
  
  const client = await dbPool.connect();
  
  try {
    // Generate comprehensive lifecycle analytics
    const analytics = await client.query(`
      SELECT 
        lifecycle_stage,
        COUNT(*) as user_count,
        AVG(engagement_score) as avg_engagement,
        COUNT(*) FILTER (WHERE last_activity > NOW() - INTERVAL '7 days') as active_7d,
        COUNT(*) FILTER (WHERE last_activity > NOW() - INTERVAL '30 days') as active_30d
      FROM user_engagement
      GROUP BY lifecycle_stage
      ORDER BY avg_engagement DESC
    `);
    
    console.log(`[${requestId}] 📈 Monthly lifecycle analytics:`, analytics.rows);
    
    // Log the analytics for reporting
    await log.info(`[${requestId}] Monthly lifecycle review completed`, {
      analytics: analytics.rows,
      timestamp: new Date().toISOString()
    });
    
    console.log(`[${requestId}] ✅ Monthly lifecycle review completed`);
    
  } finally {
    client.release();
  }
}

// Process individual retention campaign
async function processRetentionCampaign(requestId, firebase_uid, campaign_type) {
  if (!dbPool) throw new Error('Database not initialized');
  
  try {
    // Get user information from Firebase
    const userRecord = await admin.auth().getUser(firebase_uid);
    
    // Log campaign execution (in production, integrate with email service)
    const client = await dbPool.connect();
    
    try {
      await client.query(
        'INSERT INTO lifecycle_actions (firebase_uid, action_type, action_status, executed_at) VALUES ($1, $2, $3, NOW())',
        [firebase_uid, campaign_type, 'completed']
      );
      
      console.log(`[${requestId}] 📧 Retention campaign sent to ${userRecord.email}: ${campaign_type}`);
      
    } finally {
      client.release();
    }
    
  } catch (error) {
    console.error(`[${requestId}] Failed to process retention campaign:`, error);
    throw error;
  }
}

// Schedule retention campaign task
async function scheduleRetentionCampaign(firebase_uid, campaign_type) {
  try {
    const parent = `projects/${PROJECT_ID}/locations/${REGION}/queues/${TASK_QUEUE_NAME}`;
    const serviceUrl = `https://${WORKER_SERVICE_NAME}-${PROJECT_ID}.a.run.app`;
    
    const task = {
      httpRequest: {
        httpMethod: 'POST',
        url: `${serviceUrl}/tasks/retention-campaign`,
        body: Buffer.from(JSON.stringify({ 
          firebase_uid, 
          campaign_type 
        })).toString('base64'),
        headers: { 'Content-Type': 'application/json' },
      },
      scheduleTime: {
        seconds: Math.floor(Date.now() / 1000) + 3600, // 1 hour delay
      },
    };
    
    await tasksClient.createTask({ parent, task });
    console.log(`📅 Scheduled retention campaign for user ${firebase_uid}: ${campaign_type}`);
    
  } catch (error) {
    console.error('Failed to schedule retention campaign:', error);
    throw error;
  }
}

// ============================================================================
// ERROR HANDLING
// ============================================================================

// Global error handler
app.use((error, req, res, next) => {
  console.error(`[${req.requestId || 'unknown'}] Unhandled error:`, error);
  
  res.status(500).json({
    status: 'error',
    message: 'Internal server error',
    requestId: req.requestId || 'unknown'
  });
});

// Handle 404 routes
app.use('*', (req, res) => {
  res.status(404).json({
    status: 'error',
    message: 'Route not found',
    path: req.originalUrl
  });
});

// ============================================================================
// APPLICATION STARTUP
// ============================================================================

// Graceful shutdown handler
process.on('SIGTERM', async () => {
  console.log('🛑 Received SIGTERM signal, shutting down gracefully...');
  
  if (dbPool) {
    await dbPool.end();
    console.log('✅ Database connections closed');
  }
  
  process.exit(0);
});

// Start server
async function startServer() {
  try {
    // Initialize database connection
    await initializeDatabase();
    
    // Start HTTP server
    const server = app.listen(PORT, '0.0.0.0', () => {
      console.log(`🚀 User Lifecycle Worker started on port ${PORT}`);
      console.log(`📊 Project: ${PROJECT_ID}`);
      console.log(`🌍 Region: ${REGION}`);
      console.log(`⚡ Task Queue: ${TASK_QUEUE_NAME}`);
      console.log(`🗄️  Database: ${CONNECTION_NAME}`);
      console.log(`✅ Service ready to process user lifecycle tasks`);
    });
    
    // Handle server shutdown
    process.on('SIGTERM', () => {
      console.log('🛑 SIGTERM received, shutting down server...');
      server.close(() => {
        console.log('✅ HTTP server closed');
      });
    });
    
  } catch (error) {
    console.error('❌ Failed to start server:', error);
    process.exit(1);
  }
}

// Start the application
startServer().catch(console.error);