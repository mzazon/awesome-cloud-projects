#!/bin/bash

# Deploy script for Custom Voice Generation with Chirp 3 and Functions
# This script automates the deployment of the voice generation infrastructure
# Following the recipe: custom-voice-generation-chirp-functions

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        error "curl is not installed. Please install curl."
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed. Please install openssl."
        exit 1
    fi
    
    # Check if authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set environment variables for GCP resources
    export PROJECT_ID="${PROJECT_ID:-voice-gen-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="${BUCKET_NAME:-voice-audio-${RANDOM_SUFFIX}}"
    export FUNCTION_NAME="${FUNCTION_NAME:-voice-synthesis-${RANDOM_SUFFIX}}"
    export DB_INSTANCE="${DB_INSTANCE:-voice-profiles-${RANDOM_SUFFIX}}"
    
    # Store variables in a file for cleanup script
    cat > .env.deploy << EOF
export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export ZONE="${ZONE}"
export BUCKET_NAME="${BUCKET_NAME}"
export FUNCTION_NAME="${FUNCTION_NAME}"
export DB_INSTANCE="${DB_INSTANCE}"
EOF
    
    info "Environment variables:"
    info "  PROJECT_ID: ${PROJECT_ID}"
    info "  REGION: ${REGION}"
    info "  BUCKET_NAME: ${BUCKET_NAME}"
    info "  DB_INSTANCE: ${DB_INSTANCE}"
    
    log "Environment setup completed"
}

# Function to configure GCP project
configure_gcp_project() {
    log "Configuring GCP project..."
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" || {
        error "Failed to set project. Please check if project ${PROJECT_ID} exists and you have access."
        exit 1
    }
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log "GCP project configured successfully"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required APIs..."
    
    local apis=(
        "texttospeech.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "sqladmin.googleapis.com"
        "eventarc.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        info "Enabling ${api}..."
        gcloud services enable "${api}" || {
            error "Failed to enable ${api}"
            exit 1
        }
    done
    
    # Wait for APIs to be fully enabled
    info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log "APIs enabled successfully"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket..."
    
    # Create storage bucket for audio files
    gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_NAME}" || {
        error "Failed to create storage bucket"
        exit 1
    }
    
    # Enable versioning for audio file protection
    gsutil versioning set on "gs://${BUCKET_NAME}" || {
        warn "Failed to enable versioning on bucket"
    }
    
    # Create directory structure for organization
    info "Creating bucket directory structure..."
    echo "" | gsutil cp - "gs://${BUCKET_NAME}/samples/.keep" || {
        warn "Failed to create samples directory"
    }
    echo "" | gsutil cp - "gs://${BUCKET_NAME}/generated/.keep" || {
        warn "Failed to create generated directory"
    }
    
    log "Cloud Storage bucket created: ${BUCKET_NAME}"
}

# Function to create Cloud SQL database
create_cloud_sql() {
    log "Creating Cloud SQL database..."
    
    # Create Cloud SQL instance for voice profile metadata
    gcloud sql instances create "${DB_INSTANCE}" \
        --database-version=POSTGRES_15 \
        --tier=db-f1-micro \
        --region="${REGION}" \
        --storage-type=SSD \
        --storage-size=10GB \
        --backup \
        --enable-ip-alias || {
        error "Failed to create Cloud SQL instance"
        exit 1
    }
    
    # Set database root password
    DB_PASSWORD=$(openssl rand -base64 32)
    gcloud sql users set-password postgres \
        --instance="${DB_INSTANCE}" \
        --password="${DB_PASSWORD}" || {
        error "Failed to set database password"
        exit 1
    }
    
    # Create application database
    gcloud sql databases create voice_profiles \
        --instance="${DB_INSTANCE}" || {
        error "Failed to create application database"
        exit 1
    }
    
    # Store password securely
    echo "export DB_PASSWORD=\"${DB_PASSWORD}\"" >> .env.deploy
    
    log "Cloud SQL instance created: ${DB_INSTANCE}"
    info "Database password stored in .env.deploy file"
}

# Function to create function source code
create_function_code() {
    log "Creating Cloud Functions source code..."
    
    # Create function source directory
    mkdir -p voice-functions/profile-manager
    mkdir -p voice-functions/synthesis
    
    # Create profile manager function
    cat > voice-functions/profile-manager/package.json << 'EOF'
{
  "name": "voice-profile-manager",
  "version": "1.0.0",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.3.0",
    "@google-cloud/storage": "^7.7.0",
    "pg": "^8.11.3",
    "express": "^4.18.2"
  }
}
EOF
    
    cat > voice-functions/profile-manager/index.js << 'EOF'
const functions = require('@google-cloud/functions-framework');
const {Storage} = require('@google-cloud/storage');
const {Client} = require('pg');

const storage = new Storage();
const bucketName = process.env.BUCKET_NAME;

// Database configuration
const dbConfig = {
  host: `/cloudsql/${process.env.PROJECT_ID}:${process.env.REGION}:${process.env.DB_INSTANCE}`,
  user: 'postgres',
  password: process.env.DB_PASSWORD,
  database: 'voice_profiles'
};

functions.http('profileManager', async (req, res) => {
  const client = new Client(dbConfig);
  
  try {
    await client.connect();
    
    // Initialize database table if not exists
    await client.query(`
      CREATE TABLE IF NOT EXISTS voice_profiles (
        id SERIAL PRIMARY KEY,
        profile_name VARCHAR(255) UNIQUE NOT NULL,
        voice_style VARCHAR(100) NOT NULL,
        language_code VARCHAR(10) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        audio_sample_path VARCHAR(500),
        synthesis_config JSONB
      )
    `);
    
    switch (req.method) {
      case 'POST':
        const {profileName, voiceStyle, languageCode, synthesisConfig} = req.body;
        
        const result = await client.query(
          'INSERT INTO voice_profiles (profile_name, voice_style, language_code, synthesis_config) VALUES ($1, $2, $3, $4) RETURNING *',
          [profileName, voiceStyle, languageCode, JSON.stringify(synthesisConfig)]
        );
        
        res.json({
          success: true,
          profile: result.rows[0],
          message: 'Voice profile created successfully'
        });
        break;
        
      case 'GET':
        const profiles = await client.query('SELECT * FROM voice_profiles ORDER BY created_at DESC');
        res.json({
          success: true,
          profiles: profiles.rows
        });
        break;
        
      default:
        res.status(405).json({error: 'Method not allowed'});
    }
  } catch (error) {
    console.error('Profile management error:', error);
    res.status(500).json({error: error.message});
  } finally {
    await client.end();
  }
});
EOF
    
    # Create synthesis function
    cat > voice-functions/synthesis/package.json << 'EOF'
{
  "name": "voice-synthesis",
  "version": "1.0.0",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.3.0",
    "@google-cloud/text-to-speech": "^5.3.0",
    "@google-cloud/storage": "^7.7.0",
    "pg": "^8.11.3"
  }
}
EOF
    
    cat > voice-functions/synthesis/index.js << 'EOF'
const functions = require('@google-cloud/functions-framework');
const textToSpeech = require('@google-cloud/text-to-speech');
const {Storage} = require('@google-cloud/storage');
const {Client} = require('pg');
const crypto = require('crypto');

const ttsClient = new textToSpeech.TextToSpeechClient();
const storage = new Storage();
const bucketName = process.env.BUCKET_NAME;

functions.http('voiceSynthesis', async (req, res) => {
  try {
    const {text, profileId, voiceStyle = 'en-US-Chirp3-HD-Achernar'} = req.body;
    
    if (!text) {
      return res.status(400).json({error: 'Text is required'});
    }
    
    // Configure Chirp 3: HD voice synthesis request
    const request = {
      input: {text: text},
      voice: {
        name: voiceStyle,
        languageCode: 'en-US'
      },
      audioConfig: {
        audioEncoding: 'MP3',
        speakingRate: 1.0,
        pitch: 0.0,
        volumeGainDb: 0.0,
        effectsProfileId: ['telephony-class-application']
      }
    };
    
    // Perform text-to-speech synthesis
    console.log('Synthesizing speech with Chirp 3:', voiceStyle);
    const [response] = await ttsClient.synthesizeSpeech(request);
    
    // Generate unique filename for audio output
    const audioId = crypto.randomUUID();
    const fileName = `generated/voice_${audioId}.mp3`;
    
    // Upload synthesized audio to Cloud Storage
    const file = storage.bucket(bucketName).file(fileName);
    await file.save(response.audioContent, {
      metadata: {
        contentType: 'audio/mp3',
        metadata: {
          profileId: profileId || 'default',
          voiceStyle: voiceStyle,
          synthesizedAt: new Date().toISOString()
        }
      }
    });
    
    // Generate signed URL for audio access
    const [signedUrl] = await file.getSignedUrl({
      action: 'read',
      expires: Date.now() + 24 * 60 * 60 * 1000 // 24 hours
    });
    
    res.json({
      success: true,
      audioId: audioId,
      audioUrl: signedUrl,
      fileName: fileName,
      voiceStyle: voiceStyle,
      message: 'Voice synthesis completed successfully'
    });
    
  } catch (error) {
    console.error('Voice synthesis error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});
EOF
    
    log "Function source code created successfully"
}

# Function to deploy Cloud Functions
deploy_functions() {
    log "Deploying Cloud Functions..."
    
    # Deploy profile management function
    info "Deploying profile management function..."
    (cd voice-functions/profile-manager && \
    gcloud functions deploy profile-manager \
        --runtime nodejs18 \
        --trigger-http \
        --allow-unauthenticated \
        --memory 256MB \
        --timeout 60s \
        --set-env-vars "BUCKET_NAME=${BUCKET_NAME},PROJECT_ID=${PROJECT_ID},REGION=${REGION},DB_INSTANCE=${DB_INSTANCE},DB_PASSWORD=${DB_PASSWORD}") || {
        error "Failed to deploy profile management function"
        exit 1
    }
    
    # Deploy voice synthesis function
    info "Deploying voice synthesis function..."
    (cd voice-functions/synthesis && \
    gcloud functions deploy voice-synthesis \
        --runtime nodejs18 \
        --trigger-http \
        --allow-unauthenticated \
        --memory 512MB \
        --timeout 120s \
        --set-env-vars "BUCKET_NAME=${BUCKET_NAME}") || {
        error "Failed to deploy voice synthesis function"
        exit 1
    }
    
    # Get function URLs for testing
    PROFILE_URL=$(gcloud functions describe profile-manager --format="value(httpsTrigger.url)")
    SYNTHESIS_URL=$(gcloud functions describe voice-synthesis --format="value(httpsTrigger.url)")
    
    # Store URLs in environment file
    echo "export PROFILE_URL=\"${PROFILE_URL}\"" >> .env.deploy
    echo "export SYNTHESIS_URL=\"${SYNTHESIS_URL}\"" >> .env.deploy
    
    log "Cloud Functions deployed successfully"
    info "Profile Manager URL: ${PROFILE_URL}"
    info "Voice Synthesis URL: ${SYNTHESIS_URL}"
}

# Function to configure IAM permissions
configure_iam() {
    log "Configuring IAM permissions..."
    
    # Create service account for enhanced security
    gcloud iam service-accounts create voice-synthesis-sa \
        --display-name="Voice Synthesis Service Account" || {
        warn "Service account might already exist"
    }
    
    # Grant necessary permissions to service account
    local service_account="voice-synthesis-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${service_account}" \
        --role="roles/cloudsql.client" || {
        warn "Failed to add Cloud SQL client role"
    }
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${service_account}" \
        --role="roles/storage.objectAdmin" || {
        warn "Failed to add Storage object admin role"
    }
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${service_account}" \
        --role="roles/cloudtts.user" || {
        warn "Failed to add Text-to-Speech user role"
    }
    
    log "IAM permissions configured successfully"
}

# Function to test the deployment
test_deployment() {
    log "Testing deployment..."
    
    # Source the environment variables
    source .env.deploy
    
    # Wait for functions to be ready
    info "Waiting for functions to be ready..."
    sleep 30
    
    # Create sample voice profile
    info "Creating sample voice profile..."
    curl -X POST "${PROFILE_URL}" \
        -H "Content-Type: application/json" \
        -d '{
          "profileName": "customer-service-assistant",
          "voiceStyle": "en-US-Chirp3-HD-Achernar",
          "languageCode": "en-US",
          "synthesisConfig": {
            "speakingRate": 1.0,
            "pitch": 0.0,
            "volumeGainDb": 2.0
          }
        }' || {
        warn "Failed to create sample voice profile"
    }
    
    # Test voice synthesis
    info "Testing voice synthesis..."
    curl -X POST "${SYNTHESIS_URL}" \
        -H "Content-Type: application/json" \
        -d '{
          "text": "Welcome to our customer service. How may I assist you today?",
          "profileId": "1",
          "voiceStyle": "en-US-Chirp3-HD-Achernar"
        }' || {
        warn "Failed to test voice synthesis"
    }
    
    log "Deployment testing completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    
    source .env.deploy
    
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Bucket Name: ${BUCKET_NAME}"
    echo "Database Instance: ${DB_INSTANCE}"
    echo "Profile Manager URL: ${PROFILE_URL}"
    echo "Voice Synthesis URL: ${SYNTHESIS_URL}"
    echo ""
    echo "Environment variables stored in: .env.deploy"
    echo "Function source code in: voice-functions/"
    echo ""
    echo "To test the deployment:"
    echo "1. Create a voice profile using the Profile Manager URL"
    echo "2. Generate speech using the Voice Synthesis URL"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "Starting deployment of Custom Voice Generation with Chirp 3 and Functions"
    
    check_prerequisites
    setup_environment
    configure_gcp_project
    enable_apis
    create_storage_bucket
    create_cloud_sql
    create_function_code
    deploy_functions
    configure_iam
    test_deployment
    display_summary
    
    log "Deployment completed successfully!"
    info "Resources are now ready for voice generation with Chirp 3"
}

# Run main function
main "$@"