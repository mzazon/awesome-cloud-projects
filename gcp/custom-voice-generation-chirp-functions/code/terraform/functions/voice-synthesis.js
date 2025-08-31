// Voice Synthesis Function with Chirp 3: HD Voices
// Synthesizes speech using Google Cloud Text-to-Speech API with advanced Chirp 3 voices

const functions = require('@google-cloud/functions-framework');
const textToSpeech = require('@google-cloud/text-to-speech');
const {Storage} = require('@google-cloud/storage');
const crypto = require('crypto');

const ttsClient = new textToSpeech.TextToSpeechClient();
const storage = new Storage();
const bucketName = process.env.BUCKET_NAME || '${bucket_name}';

/**
 * HTTP Cloud Function for voice synthesis using Chirp 3: HD voices
 * Supports text-to-speech conversion with customizable voice parameters
 */
functions.http('voiceSynthesis', async (req, res) => {
  // Set CORS headers for web access
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
  
  // Handle preflight OPTIONS request
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  
  if (req.method !== 'POST') {
    return res.status(405).json({
      success: false,
      error: 'Method not allowed. Only POST requests are supported.',
      allowedMethods: ['POST']
    });
  }
  
  try {
    const {
      text,
      profileId,
      voiceStyle = 'en-US-Chirp3-HD-Achernar',
      languageCode = 'en-US',
      audioConfig = {}
    } = req.body;
    
    // Validate required parameters
    if (!text || text.trim().length === 0) {
      return res.status(400).json({
        success: false,
        error: 'Text is required and cannot be empty',
        example: {
          text: "Hello, this is a sample text for voice synthesis.",
          voiceStyle: "en-US-Chirp3-HD-Achernar"
        }
      });
    }
    
    // Validate text length (Text-to-Speech API limits)
    if (text.length > 5000) {
      return res.status(400).json({
        success: false,
        error: 'Text exceeds maximum length of 5000 characters',
        textLength: text.length,
        maxLength: 5000
      });
    }
    
    // Validate voice style for Chirp 3 compatibility
    if (!voiceStyle.includes('Chirp3-HD')) {
      return res.status(400).json({
        success: false,
        error: 'Voice style must be a Chirp 3: HD voice',
        providedStyle: voiceStyle,
        examples: [
          'en-US-Chirp3-HD-Achernar',
          'en-US-Chirp3-HD-Charon',
          'en-US-Chirp3-HD-Demetrios'
        ]
      });
    }
    
    // Default audio configuration optimized for Chirp 3
    const defaultAudioConfig = {
      audioEncoding: 'MP3',
      speakingRate: 1.0,
      pitch: 0.0,
      volumeGainDb: 0.0,
      effectsProfileId: ['telephony-class-application']
    };
    
    // Merge provided audio config with defaults
    const finalAudioConfig = { ...defaultAudioConfig, ...audioConfig };
    
    // Validate audio configuration parameters
    if (finalAudioConfig.speakingRate < 0.25 || finalAudioConfig.speakingRate > 4.0) {
      return res.status(400).json({
        success: false,
        error: 'Speaking rate must be between 0.25 and 4.0',
        providedRate: finalAudioConfig.speakingRate
      });
    }
    
    if (finalAudioConfig.pitch < -20.0 || finalAudioConfig.pitch > 20.0) {
      return res.status(400).json({
        success: false,
        error: 'Pitch must be between -20.0 and 20.0',
        providedPitch: finalAudioConfig.pitch
      });
    }
    
    // Configure Chirp 3: HD voice synthesis request
    const synthesisRequest = {
      input: { text: text.trim() },
      voice: {
        name: voiceStyle,
        languageCode: languageCode
      },
      audioConfig: finalAudioConfig
    };
    
    console.log(`Starting synthesis with Chirp 3 voice: $${voiceStyle}`);
    console.log(`Text length: $${text.length} characters`);
    
    // Perform text-to-speech synthesis with error handling
    let synthesisResponse;
    try {
      [synthesisResponse] = await ttsClient.synthesizeSpeech(synthesisRequest);
    } catch (ttsError) {
      console.error('Text-to-Speech API error:', ttsError);
      return res.status(500).json({
        success: false,
        error: 'Voice synthesis failed',
        details: ttsError.message,
        voiceStyle: voiceStyle,
        suggestion: 'Please check voice style compatibility and try again'
      });
    }
    
    if (!synthesisResponse.audioContent) {
      return res.status(500).json({
        success: false,
        error: 'No audio content received from synthesis',
        voiceStyle: voiceStyle
      });
    }
    
    // Generate unique identifier and filename for audio output
    const audioId = crypto.randomUUID();
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const fileName = `generated/voice_$${audioId}_$${timestamp}.mp3`;
    
    // Prepare metadata for the audio file
    const metadata = {
      contentType: 'audio/mp3',
      cacheControl: 'public, max-age=31536000', // 1 year cache
      metadata: {
        profileId: profileId || 'default',
        voiceStyle: voiceStyle,
        languageCode: languageCode,
        synthesizedAt: new Date().toISOString(),
        textLength: text.length.toString(),
        audioId: audioId,
        speakingRate: finalAudioConfig.speakingRate.toString(),
        pitch: finalAudioConfig.pitch.toString(),
        volumeGainDb: finalAudioConfig.volumeGainDb.toString()
      }
    };
    
    // Upload synthesized audio to Cloud Storage
    console.log(`Uploading audio to: $${fileName}`);
    const file = storage.bucket(bucketName).file(fileName);
    
    try {
      await file.save(synthesisResponse.audioContent, metadata);
      console.log(`Audio uploaded successfully: $${fileName}`);
    } catch (uploadError) {
      console.error('Storage upload error:', uploadError);
      return res.status(500).json({
        success: false,
        error: 'Failed to save audio file',
        details: uploadError.message
      });
    }
    
    // Generate signed URL for secure audio access (24 hours)
    let signedUrl;
    try {
      [signedUrl] = await file.getSignedUrl({
        action: 'read',
        expires: Date.now() + 24 * 60 * 60 * 1000, // 24 hours
        version: 'v4'
      });
    } catch (urlError) {
      console.error('Signed URL generation error:', urlError);
      return res.status(500).json({
        success: false,
        error: 'Failed to generate audio access URL',
        details: urlError.message
      });
    }
    
    // Prepare success response
    const response = {
      success: true,
      audioId: audioId,
      audioUrl: signedUrl,
      fileName: fileName,
      voiceStyle: voiceStyle,
      languageCode: languageCode,
      audioConfig: finalAudioConfig,
      metadata: {
        textLength: text.length,
        synthesizedAt: new Date().toISOString(),
        expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
        profileId: profileId || 'default'
      },
      message: 'Voice synthesis completed successfully using Chirp 3: HD technology'
    };
    
    console.log(`Synthesis completed successfully. Audio ID: $${audioId}`);
    res.json(response);
    
  } catch (error) {
    console.error('Voice synthesis error:', error);
    res.status(500).json({
      success: false,
      error: 'Internal server error during voice synthesis',
      details: error.message,
      timestamp: new Date().toISOString(),
      suggestion: 'Please try again or contact support if the issue persists'
    });
  }
});