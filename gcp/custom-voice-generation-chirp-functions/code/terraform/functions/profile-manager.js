// Voice Profile Management Function for Chirp 3 Voice Generation System
// Manages voice profile creation, updates, and retrieval with Cloud SQL integration

const functions = require('@google-cloud/functions-framework');
const {Storage} = require('@google-cloud/storage');
const {Client} = require('pg');

const storage = new Storage();
const bucketName = process.env.BUCKET_NAME || '${bucket_name}';

// Database configuration using Cloud SQL Proxy
const dbConfig = {
  host: `/cloudsql/$${process.env.PROJECT_ID}:$${process.env.REGION}:$${process.env.DB_INSTANCE}`,
  user: 'postgres',
  password: process.env.DB_PASSWORD,
  database: 'voice_profiles',
  ssl: false
};

/**
 * HTTP Cloud Function for managing voice profiles
 * Supports GET (list profiles) and POST (create profile) operations
 */
functions.http('profileManager', async (req, res) => {
  // Set CORS headers for web access
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
  
  // Handle preflight OPTIONS request
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  
  const client = new Client(dbConfig);
  
  try {
    await client.connect();
    console.log('Connected to Cloud SQL database');
    
    // Initialize database table if not exists
    await client.query(`
      CREATE TABLE IF NOT EXISTS voice_profiles (
        id SERIAL PRIMARY KEY,
        profile_name VARCHAR(255) UNIQUE NOT NULL,
        voice_style VARCHAR(100) NOT NULL,
        language_code VARCHAR(10) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        audio_sample_path VARCHAR(500),
        synthesis_config JSONB,
        usage_count INTEGER DEFAULT 0,
        is_active BOOLEAN DEFAULT true
      )
    `);
    
    // Create indexes for better query performance
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_voice_profiles_name ON voice_profiles(profile_name);
      CREATE INDEX IF NOT EXISTS idx_voice_profiles_created ON voice_profiles(created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_voice_profiles_active ON voice_profiles(is_active);
    `);
    
    switch (req.method) {
      case 'POST':
        await handleCreateProfile(req, res, client);
        break;
        
      case 'GET':
        await handleListProfiles(req, res, client);
        break;
        
      default:
        res.status(405).json({
          success: false,
          error: 'Method not allowed',
          allowedMethods: ['GET', 'POST']
        });
    }
  } catch (error) {
    console.error('Profile management error:', error);
    res.status(500).json({
      success: false,
      error: error.message,
      timestamp: new Date().toISOString()
    });
  } finally {
    try {
      await client.end();
    } catch (closeError) {
      console.error('Error closing database connection:', closeError);
    }
  }
});

/**
 * Handle profile creation requests
 */
async function handleCreateProfile(req, res, client) {
  const { profileName, voiceStyle, languageCode, synthesisConfig, audioSamplePath } = req.body;
  
  // Validate required fields
  if (!profileName || !voiceStyle || !languageCode) {
    return res.status(400).json({
      success: false,
      error: 'Missing required fields: profileName, voiceStyle, languageCode',
      requiredFields: ['profileName', 'voiceStyle', 'languageCode']
    });
  }
  
  // Validate voice style for Chirp 3 compatibility
  const validVoiceStyles = [
    'en-US-Chirp3-HD-Achernar',
    'en-US-Chirp3-HD-Charon',
    'en-US-Chirp3-HD-Demetrios',
    'en-US-Chirp3-HD-Fenrir',
    'en-US-Chirp3-HD-Galene',
    'en-US-Chirp3-HD-Hyperion',
    'en-US-Chirp3-HD-Iris',
    'en-US-Chirp3-HD-Kasey',
    'en-US-Chirp3-HD-Luna',
    'en-US-Chirp3-HD-Mira'
  ];
  
  if (!validVoiceStyles.some(style => voiceStyle.includes('Chirp3-HD'))) {
    return res.status(400).json({
      success: false,
      error: 'Invalid voice style. Must be a Chirp 3: HD voice',
      validStyles: validVoiceStyles.slice(0, 5), // Show first 5 examples
      note: 'See Google Cloud Text-to-Speech documentation for complete list'
    });
  }
  
  try {
    const result = await client.query(
      `INSERT INTO voice_profiles 
       (profile_name, voice_style, language_code, synthesis_config, audio_sample_path) 
       VALUES ($1, $2, $3, $4, $5) 
       RETURNING *`,
      [
        profileName,
        voiceStyle,
        languageCode,
        JSON.stringify(synthesisConfig || {}),
        audioSamplePath || null
      ]
    );
    
    console.log(`Created voice profile: $${profileName} with style: $${voiceStyle}`);
    
    res.status(201).json({
      success: true,
      profile: result.rows[0],
      message: 'Voice profile created successfully',
      timestamp: new Date().toISOString()
    });
  } catch (dbError) {
    if (dbError.code === '23505') { // Unique constraint violation
      res.status(409).json({
        success: false,
        error: 'Profile name already exists',
        profileName: profileName
      });
    } else {
      throw dbError;
    }
  }
}

/**
 * Handle profile listing requests with optional filtering
 */
async function handleListProfiles(req, res, client) {
  const { active, limit = 50, offset = 0, search } = req.query;
  
  let query = 'SELECT * FROM voice_profiles';
  let params = [];
  let conditions = [];
  
  // Filter by active status
  if (active !== undefined) {
    conditions.push(`is_active = $${params.length + 1}`);
    params.push(active === 'true');
  }
  
  // Search by profile name
  if (search) {
    conditions.push(`profile_name ILIKE $${params.length + 1}`);
    params.push(`%${search}%`);
  }
  
  // Add WHERE clause if conditions exist
  if (conditions.length > 0) {
    query += ' WHERE ' + conditions.join(' AND ');
  }
  
  // Add ordering and pagination
  query += ` ORDER BY created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
  params.push(parseInt(limit), parseInt(offset));
  
  try {
    const result = await client.query(query, params);
    
    // Get total count for pagination
    let countQuery = 'SELECT COUNT(*) FROM voice_profiles';
    let countParams = [];
    
    if (conditions.length > 0) {
      countQuery += ' WHERE ' + conditions.join(' AND ');
      countParams = params.slice(0, -2); // Remove limit and offset
    }
    
    const countResult = await client.query(countQuery, countParams);
    const totalCount = parseInt(countResult.rows[0].count);
    
    res.json({
      success: true,
      profiles: result.rows,
      pagination: {
        total: totalCount,
        limit: parseInt(limit),
        offset: parseInt(offset),
        hasMore: (parseInt(offset) + parseInt(limit)) < totalCount
      },
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    throw error;
  }
}