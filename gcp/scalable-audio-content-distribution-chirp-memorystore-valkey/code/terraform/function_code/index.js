/**
 * Audio Processor Cloud Function
 * 
 * This function orchestrates the audio generation and caching workflow for the
 * scalable audio content distribution platform. It handles Text-to-Speech requests,
 * manages Valkey caching, and optimizes delivery through Cloud Storage.
 */

const textToSpeech = require('@google-cloud/text-to-speech');
const { Storage } = require('@google-cloud/storage');
const redis = require('redis');
const crypto = require('crypto');
const { getSecret } = require('@google-cloud/secret-manager');

// Initialize Google Cloud clients
const ttsClient = new textToSpeech.TextToSpeechClient();
const storage = new Storage();

// Environment variables from Terraform deployment
const BUCKET_NAME = process.env.BUCKET_NAME || '${bucket_name}';
const VALKEY_HOST = process.env.VALKEY_HOST || '${valkey_host}';
const VALKEY_PORT = process.env.VALKEY_PORT || '${valkey_port}';
const PROJECT_ID = process.env.PROJECT_ID;

// Initialize storage bucket
const bucket = storage.bucket(BUCKET_NAME);

// Redis client configuration for Valkey
let redisClient;

/**
 * Initialize Redis client connection
 */
async function initRedisClient() {
  if (!redisClient) {
    redisClient = redis.createClient({
      socket: {
        host: VALKEY_HOST,
        port: parseInt(VALKEY_PORT)
      },
      retry_strategy: (options) => {
        if (options.error && options.error.code === 'ECONNREFUSED') {
          console.error('Redis connection refused');
          return new Error('Redis connection refused');
        }
        if (options.total_retry_time > 1000 * 60 * 60) {
          console.error('Redis retry time exhausted');
          return new Error('Retry time exhausted');
        }
        if (options.attempt > 10) {
          console.error('Redis max attempts reached');
          return new Error('Max attempts reached');
        }
        // Exponential backoff
        return Math.min(options.attempt * 100, 3000);
      }
    });

    redisClient.on('error', (err) => {
      console.error('Redis client error:', err);
    });

    redisClient.on('connect', () => {
      console.log('Connected to Valkey instance');
    });

    redisClient.on('disconnect', () => {
      console.log('Disconnected from Valkey instance');
    });
  }
  
  if (!redisClient.isOpen) {
    await redisClient.connect();
  }
  
  return redisClient;
}

/**
 * Generate a unique cache key based on text and voice configuration
 */
function generateCacheKey(text, voiceConfig) {
  const contentHash = crypto
    .createHash('md5')
    .update(JSON.stringify({ text, voiceConfig }))
    .digest('hex');
  return `audio:${contentHash}`;
}

/**
 * Generate audio using Text-to-Speech API with Chirp 3 capabilities
 */
async function generateAudio(text, voiceConfig) {
  try {
    const request = {
      input: { text },
      voice: {
        languageCode: voiceConfig.languageCode || 'en-US',
        name: voiceConfig.voiceName || 'en-US-Casual',
        ssmlGender: voiceConfig.gender || 'NEUTRAL'
      },
      audioConfig: {
        audioEncoding: voiceConfig.audioEncoding || 'MP3',
        sampleRateHertz: voiceConfig.sampleRateHertz || 24000,
        effectsProfileId: voiceConfig.effectsProfile || ['headphone-class-device'],
        speakingRate: voiceConfig.speakingRate || 1.0,
        pitch: voiceConfig.pitch || 0.0,
        volumeGainDb: voiceConfig.volumeGainDb || 0.0
      }
    };

    console.log('Generating audio with Text-to-Speech API:', {
      textLength: text.length,
      voice: request.voice,
      audioConfig: request.audioConfig
    });

    const [response] = await ttsClient.synthesizeSpeech(request);
    
    if (!response.audioContent) {
      throw new Error('No audio content generated');
    }

    console.log(`Audio generated successfully, size: ${response.audioContent.length} bytes`);
    return response.audioContent;
    
  } catch (error) {
    console.error('Text-to-Speech API error:', error);
    throw new Error(`Audio generation failed: ${error.message}`);
  }
}

/**
 * Upload audio content to Cloud Storage
 */
async function uploadToStorage(audioContent, fileName) {
  try {
    const file = bucket.file(fileName);
    
    await file.save(audioContent, {
      metadata: {
        contentType: 'audio/mpeg',
        cacheControl: 'public, max-age=3600',
        contentDisposition: 'inline',
        customMetadata: {
          generatedAt: new Date().toISOString(),
          platform: 'audio-distribution',
          version: '1.0'
        }
      },
      resumable: false
    });

    // Make file publicly accessible
    await file.makePublic();

    const publicUrl = `https://storage.googleapis.com/${BUCKET_NAME}/${fileName}`;
    console.log(`Audio uploaded to storage: ${publicUrl}`);
    
    return publicUrl;
    
  } catch (error) {
    console.error('Storage upload error:', error);
    throw new Error(`Storage upload failed: ${error.message}`);
  }
}

/**
 * Cache audio URL in Valkey with TTL
 */
async function cacheAudioUrl(cacheKey, audioUrl, ttl = 3600) {
  try {
    const client = await initRedisClient();
    await client.setEx(cacheKey, ttl, audioUrl);
    
    // Set additional metadata
    await client.setEx(`${cacheKey}:meta`, ttl, JSON.stringify({
      cachedAt: new Date().toISOString(),
      ttl: ttl,
      url: audioUrl
    }));
    
    console.log(`Audio URL cached: ${cacheKey} -> ${audioUrl}`);
    
  } catch (error) {
    console.error('Cache operation error:', error);
    // Don't fail the entire request if caching fails
  }
}

/**
 * Retrieve cached audio URL from Valkey
 */
async function getCachedAudioUrl(cacheKey) {
  try {
    const client = await initRedisClient();
    const cachedUrl = await client.get(cacheKey);
    
    if (cachedUrl) {
      // Update cache statistics
      await client.incr(`stats:cache_hits`);
      console.log(`Cache hit for key: ${cacheKey}`);
      return cachedUrl;
    } else {
      await client.incr(`stats:cache_misses`);
      console.log(`Cache miss for key: ${cacheKey}`);
      return null;
    }
    
  } catch (error) {
    console.error('Cache retrieval error:', error);
    // Return null to fall back to generation
    return null;
  }
}

/**
 * Validate input parameters
 */
function validateInput(text, voiceConfig) {
  if (!text || typeof text !== 'string') {
    throw new Error('Text input is required and must be a string');
  }
  
  if (text.length > 5000) {
    throw new Error('Text input exceeds maximum length of 5000 characters');
  }
  
  if (voiceConfig && typeof voiceConfig !== 'object') {
    throw new Error('Voice configuration must be an object');
  }
  
  // Validate voice configuration parameters
  if (voiceConfig) {
    const validLanguageCodes = ['en-US', 'en-GB', 'es-ES', 'fr-FR', 'de-DE', 'it-IT', 'ja-JP', 'ko-KR'];
    const validGenders = ['MALE', 'FEMALE', 'NEUTRAL'];
    const validEncodings = ['MP3', 'LINEAR16', 'OGG_OPUS', 'MULAW', 'ALAW'];
    
    if (voiceConfig.languageCode && !validLanguageCodes.includes(voiceConfig.languageCode)) {
      throw new Error(`Invalid language code: ${voiceConfig.languageCode}`);
    }
    
    if (voiceConfig.gender && !validGenders.includes(voiceConfig.gender)) {
      throw new Error(`Invalid gender: ${voiceConfig.gender}`);
    }
    
    if (voiceConfig.audioEncoding && !validEncodings.includes(voiceConfig.audioEncoding)) {
      throw new Error(`Invalid audio encoding: ${voiceConfig.audioEncoding}`);
    }
  }
}

/**
 * Main Cloud Function entry point
 * Processes audio generation requests with intelligent caching
 */
exports.processAudio = async (req, res) => {
  const startTime = Date.now();
  
  try {
    // Set CORS headers
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    
    // Handle preflight requests
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    
    // Only allow POST requests for audio generation
    if (req.method !== 'POST') {
      res.status(405).json({ 
        error: 'Method not allowed',
        message: 'Only POST requests are supported'
      });
      return;
    }
    
    // Extract and validate request parameters
    const { text, voiceConfig = {}, cacheKey, forceregenerate = false } = req.body;
    
    // Validate input
    validateInput(text, voiceConfig);
    
    // Generate cache key
    const finalCacheKey = cacheKey || generateCacheKey(text, voiceConfig);
    
    // Check cache first (unless force regeneration is requested)
    let cachedUrl = null;
    if (!forceregenerate) {
      cachedUrl = await getCachedAudioUrl(finalCacheKey);
    }
    
    if (cachedUrl) {
      const processingTime = Date.now() - startTime;
      res.json({
        audioUrl: cachedUrl,
        cached: true,
        processingTime: `${processingTime}ms`,
        cacheKey: finalCacheKey,
        timestamp: new Date().toISOString()
      });
      return;
    }
    
    // Generate new audio content
    console.log('Generating new audio content for text:', text.substring(0, 100) + '...');
    const audioContent = await generateAudio(text, voiceConfig);
    
    // Create unique filename
    const fileExtension = voiceConfig.audioEncoding === 'MP3' ? 'mp3' : 'wav';
    const fileName = `generated-audio/${finalCacheKey.replace('audio:', '')}.${fileExtension}`;
    
    // Upload to Cloud Storage
    const publicUrl = await uploadToStorage(audioContent, fileName);
    
    // Cache the URL for future requests
    await cacheAudioUrl(finalCacheKey, publicUrl, 3600);
    
    const processingTime = Date.now() - startTime;
    
    // Return successful response
    res.json({
      audioUrl: publicUrl,
      cached: false,
      processingTime: `${processingTime}ms`,
      fileSize: audioContent.length,
      cacheKey: finalCacheKey,
      fileName: fileName,
      timestamp: new Date().toISOString(),
      voiceConfig: voiceConfig
    });
    
  } catch (error) {
    console.error('Audio processing error:', error);
    
    const processingTime = Date.now() - startTime;
    
    res.status(500).json({
      error: 'Audio processing failed',
      message: error.message,
      processingTime: `${processingTime}ms`,
      timestamp: new Date().toISOString()
    });
  } finally {
    // Clean up Redis connection if needed
    if (redisClient && redisClient.isOpen) {
      try {
        await redisClient.disconnect();
      } catch (err) {
        console.error('Error disconnecting from Redis:', err);
      }
    }
  }
};

/**
 * Health check endpoint
 */
exports.healthCheck = async (req, res) => {
  try {
    res.set('Access-Control-Allow-Origin', '*');
    
    // Basic health checks
    const health = {
      status: 'healthy',
      timestamp: new Date().toISOString(),
      version: '1.0.0',
      services: {}
    };
    
    // Check Valkey connectivity
    try {
      const client = await initRedisClient();
      await client.ping();
      health.services.valkey = 'connected';
    } catch (error) {
      health.services.valkey = 'error';
      health.status = 'degraded';
    }
    
    // Check Cloud Storage connectivity
    try {
      await bucket.exists();
      health.services.storage = 'connected';
    } catch (error) {
      health.services.storage = 'error';
      health.status = 'degraded';
    }
    
    // Check Text-to-Speech API connectivity (lightweight test)
    try {
      // Just check if the client is initialized properly
      health.services.tts = ttsClient ? 'connected' : 'error';
    } catch (error) {
      health.services.tts = 'error';
      health.status = 'degraded';
    }
    
    const statusCode = health.status === 'healthy' ? 200 : 503;
    res.status(statusCode).json(health);
    
  } catch (error) {
    console.error('Health check error:', error);
    res.status(500).json({
      status: 'unhealthy',
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
};