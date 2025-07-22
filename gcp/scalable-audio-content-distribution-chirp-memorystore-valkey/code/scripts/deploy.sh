#!/bin/bash

# Scalable Audio Content Distribution with Chirp 3 and Memorystore Valkey - Deployment Script
# This script deploys the complete infrastructure for the audio content distribution solution

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup of partial deployment..."
    # Call cleanup script if it exists
    if [[ -f "$(dirname "$0")/destroy.sh" ]]; then
        bash "$(dirname "$0")/destroy.sh" --force || true
    fi
    exit 1
}

trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        log_error "curl is not available. Please install curl."
        exit 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is not available. Please install jq for JSON parsing."
        exit 1
    fi
    
    # Check if openssl is available
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not available. Please install openssl."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Check if current project is set
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "No project is set. Please run 'gcloud config set project PROJECT_ID'."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to prompt for user confirmation
confirm_deployment() {
    PROJECT_ID=$(gcloud config get-value project)
    BILLING_ACCOUNT=$(gcloud beta billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null || echo "Not configured")
    
    echo ""
    log_info "=== DEPLOYMENT CONFIRMATION ==="
    log_info "Project ID: $PROJECT_ID"
    log_info "Billing Account: $BILLING_ACCOUNT"
    log_info "Region: ${REGION:-us-central1}"
    log_info ""
    log_warning "This deployment will create the following resources:"
    log_info "  • Cloud Storage bucket for audio assets"
    log_info "  • Memorystore for Valkey instance (3 nodes)"
    log_info "  • VPC network and subnet"
    log_info "  • Cloud Function for audio processing"
    log_info "  • Cloud Run service for content management"
    log_info "  • Cloud CDN with global distribution"
    log_info "  • Service accounts and IAM bindings"
    log_info ""
    log_warning "Estimated monthly cost: \$50-200 (depending on usage)"
    log_info ""
    
    if [[ "${AUTO_APPROVE:-false}" != "true" ]]; then
        read -p "Do you want to continue with the deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="${BUCKET_NAME:-audio-content-${RANDOM_SUFFIX}}"
    export VALKEY_INSTANCE="${VALKEY_INSTANCE:-audio-cache-${RANDOM_SUFFIX}}"
    export FUNCTION_NAME="${FUNCTION_NAME:-audio-processor-${RANDOM_SUFFIX}}"
    export CDN_IP_NAME="${CDN_IP_NAME:-audio-cdn-ip-${RANDOM_SUFFIX}}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Create state file for tracking deployment
    cat > deployment_state.json << EOF
{
    "project_id": "$PROJECT_ID",
    "region": "$REGION",
    "zone": "$ZONE",
    "bucket_name": "$BUCKET_NAME",
    "valkey_instance": "$VALKEY_INSTANCE",
    "function_name": "$FUNCTION_NAME",
    "cdn_ip_name": "$CDN_IP_NAME",
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "deployment_status": "in_progress"
}
EOF
    
    log_success "Environment variables configured"
    log_info "Resources will be created with suffix: ${RANDOM_SUFFIX}"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "texttospeech.googleapis.com"
        "memcache.googleapis.com"
        "storage.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudcdn.googleapis.com"
        "compute.googleapis.com"
        "run.googleapis.com"
        "cloudbuild.googleapis.com"
        "iam.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api" --quiet
    done
    
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "Required APIs enabled successfully"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: ${BUCKET_NAME}"
    
    # Create bucket with regional storage
    gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_NAME}"
    
    # Configure CORS for web application access
    cat > cors.json << 'EOF'
[
  {
    "origin": ["*"],
    "method": ["GET", "HEAD"],
    "responseHeader": ["Content-Type", "Range"],
    "maxAgeSeconds": 3600
  }
]
EOF
    
    gsutil cors set cors.json "gs://${BUCKET_NAME}"
    
    # Set up lifecycle policy for cost optimization
    cat > lifecycle.json << 'EOF'
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
      "condition": {"age": 30}
    },
    {
      "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
      "condition": {"age": 90}
    }
  ]
}
EOF
    
    gsutil lifecycle set lifecycle.json "gs://${BUCKET_NAME}"
    
    # Clean up temporary files
    rm -f cors.json lifecycle.json
    
    log_success "Cloud Storage bucket created and configured"
}

# Function to create VPC network
create_vpc_network() {
    log_info "Creating VPC network and subnet..."
    
    # Create VPC network
    gcloud compute networks create audio-network \
        --subnet-mode regional \
        --quiet
    
    # Create subnet
    gcloud compute networks subnets create audio-subnet \
        --network audio-network \
        --range 10.0.0.0/24 \
        --region "${REGION}" \
        --quiet
    
    log_success "VPC network and subnet created"
}

# Function to deploy Memorystore for Valkey
deploy_valkey_instance() {
    log_info "Deploying Memorystore for Valkey instance: ${VALKEY_INSTANCE}"
    
    # Create Memorystore for Valkey instance
    gcloud memcache instances create "${VALKEY_INSTANCE}" \
        --size 2 \
        --region "${REGION}" \
        --network audio-network \
        --node-count 3 \
        --enable-auth \
        --valkey-version 8.0 \
        --quiet
    
    # Wait for instance to be ready
    log_info "Waiting for Valkey instance to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local state=$(gcloud memcache instances describe "${VALKEY_INSTANCE}" \
            --region "${REGION}" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        if [[ "$state" == "READY" ]]; then
            break
        fi
        
        log_info "Attempt $attempt/$max_attempts: Valkey instance state is $state"
        sleep 60
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_error "Valkey instance failed to become ready within timeout"
        exit 1
    fi
    
    # Get connection details
    export VALKEY_HOST=$(gcloud memcache instances describe "${VALKEY_INSTANCE}" \
        --region "${REGION}" --format="value(host)")
    export VALKEY_PORT=6379
    
    log_success "Memorystore for Valkey instance deployed successfully"
    log_info "Connection: ${VALKEY_HOST}:${VALKEY_PORT}"
}

# Function to configure Text-to-Speech API
configure_tts_api() {
    log_info "Configuring Text-to-Speech API..."
    
    # Create service account
    gcloud iam service-accounts create tts-service-account \
        --display-name "Text-to-Speech Service Account" \
        --quiet || log_warning "Service account may already exist"
    
    # Grant necessary permissions
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:tts-service-account@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/cloudtts.user" \
        --quiet
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:tts-service-account@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/storage.objectAdmin" \
        --quiet
    
    # Create service account key
    gcloud iam service-accounts keys create tts-key.json \
        --iam-account="tts-service-account@${PROJECT_ID}.iam.gserviceaccount.com" \
        --quiet
    
    # Test API connectivity
    log_info "Testing Text-to-Speech API connectivity..."
    local test_response=$(curl -s -X POST \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        -d '{
            "input": {"text": "Testing Chirp 3 audio generation for scalable content distribution."},
            "voice": {"languageCode": "en-US", "name": "en-US-Casual"},
            "audioConfig": {"audioEncoding": "MP3", "sampleRateHertz": 24000}
        }' \
        "https://texttospeech.googleapis.com/v1/text:synthesize" || echo "FAILED")
    
    if echo "$test_response" | grep -q "audioContent"; then
        log_success "Text-to-Speech API configured and tested successfully"
    else
        log_warning "Text-to-Speech API test returned unexpected response"
    fi
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    log_info "Deploying audio processing Cloud Function..."
    
    # Create function directory
    mkdir -p audio-processor-function
    cd audio-processor-function
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "audio-processor",
  "version": "1.0.0",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.3.0",
    "@google-cloud/text-to-speech": "^5.3.0",
    "@google-cloud/storage": "^7.7.0",
    "redis": "^4.6.0",
    "crypto": "^1.0.1"
  }
}
EOF
    
    # Create main function file
    cat > index.js << 'EOF'
const textToSpeech = require('@google-cloud/text-to-speech');
const {Storage} = require('@google-cloud/storage');
const redis = require('redis');
const crypto = require('crypto');

const ttsClient = new textToSpeech.TextToSpeechClient();
const storage = new Storage();
const bucket = storage.bucket(process.env.BUCKET_NAME);

// Redis client configuration
const redisClient = redis.createClient({
  socket: {
    host: process.env.VALKEY_HOST,
    port: process.env.VALKEY_PORT
  }
});

exports.processAudio = async (req, res) => {
  try {
    const { text, voiceConfig = {}, cacheKey } = req.body;
    
    // Generate cache key based on text and voice configuration
    const contentHash = crypto.createHash('md5')
      .update(JSON.stringify({ text, voiceConfig }))
      .digest('hex');
    const finalCacheKey = cacheKey || `audio:${contentHash}`;
    
    // Check cache first
    await redisClient.connect();
    const cachedUrl = await redisClient.get(finalCacheKey);
    
    if (cachedUrl) {
      await redisClient.disconnect();
      return res.json({ 
        audioUrl: cachedUrl, 
        cached: true,
        processingTime: '< 1ms'
      });
    }
    
    // Generate new audio content
    const startTime = Date.now();
    const request = {
      input: { text },
      voice: {
        languageCode: voiceConfig.languageCode || 'en-US',
        name: voiceConfig.voiceName || 'en-US-Casual',
        ssmlGender: voiceConfig.gender || 'NEUTRAL'
      },
      audioConfig: {
        audioEncoding: 'MP3',
        sampleRateHertz: 24000,
        effectsProfileId: ['headphone-class-device']
      }
    };
    
    const [response] = await ttsClient.synthesizeSpeech(request);
    
    // Upload to Cloud Storage
    const fileName = `generated-audio/${contentHash}.mp3`;
    const file = bucket.file(fileName);
    
    await file.save(response.audioContent, {
      metadata: {
        contentType: 'audio/mpeg',
        cacheControl: 'public, max-age=3600'
      }
    });
    
    // Make file publicly accessible
    await file.makePublic();
    
    const publicUrl = `https://storage.googleapis.com/${process.env.BUCKET_NAME}/${fileName}`;
    
    // Cache the URL with 1-hour expiration
    await redisClient.setEx(finalCacheKey, 3600, publicUrl);
    await redisClient.disconnect();
    
    const processingTime = Date.now() - startTime;
    
    res.json({
      audioUrl: publicUrl,
      cached: false,
      processingTime: `${processingTime}ms`,
      fileSize: response.audioContent.length
    });
    
  } catch (error) {
    console.error('Audio processing error:', error);
    res.status(500).json({ error: 'Audio processing failed' });
  }
};
EOF
    
    # Deploy the Cloud Function
    gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime nodejs18 \
        --trigger-http \
        --allow-unauthenticated \
        --set-env-vars="BUCKET_NAME=${BUCKET_NAME},VALKEY_HOST=${VALKEY_HOST},VALKEY_PORT=${VALKEY_PORT}" \
        --memory 512MB \
        --timeout 60s \
        --region "${REGION}" \
        --quiet
    
    cd ..
    
    log_success "Cloud Function deployed successfully"
}

# Function to configure Cloud CDN
configure_cloud_cdn() {
    log_info "Configuring Cloud CDN for global distribution..."
    
    # Create backend bucket for CDN
    gcloud compute backend-buckets create audio-backend \
        --gcs-bucket-name "${BUCKET_NAME}" \
        --quiet
    
    # Create URL map for CDN routing
    gcloud compute url-maps create audio-cdn-map \
        --default-backend-bucket audio-backend \
        --quiet
    
    # Create HTTP(S) proxy
    gcloud compute target-http-proxies create audio-http-proxy \
        --url-map audio-cdn-map \
        --quiet
    
    # Reserve static IP for CDN
    gcloud compute addresses create "${CDN_IP_NAME}" \
        --global \
        --quiet
    
    export CDN_IP=$(gcloud compute addresses describe "${CDN_IP_NAME}" \
        --global --format="value(address)")
    
    # Create forwarding rule
    gcloud compute forwarding-rules create audio-http-rule \
        --address "${CDN_IP}" \
        --global \
        --target-http-proxy audio-http-proxy \
        --ports 80 \
        --quiet
    
    # Configure cache settings for audio content
    gcloud compute backend-buckets update audio-backend \
        --cache-mode CACHE_ALL_STATIC \
        --default-ttl 3600 \
        --max-ttl 86400 \
        --client-ttl 1800 \
        --quiet
    
    log_success "Cloud CDN configured successfully"
    log_info "CDN Endpoint: http://${CDN_IP}"
}

# Function to deploy Cloud Run service
deploy_cloud_run_service() {
    log_info "Deploying audio management Cloud Run service..."
    
    # Create service directory
    mkdir -p audio-management-service
    cd audio-management-service
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 8080
CMD ["node", "server.js"]
EOF
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "audio-management-service",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "redis": "^4.6.0",
    "axios": "^1.6.0",
    "@google-cloud/monitoring": "^4.0.0"
  }
}
EOF
    
    # Create main service file
    cat > server.js << 'EOF'
const express = require('express');
const redis = require('redis');
const axios = require('axios');

const app = express();
app.use(express.json());

const FUNCTION_URL = process.env.FUNCTION_URL;
const VALKEY_HOST = process.env.VALKEY_HOST;
const CDN_ENDPOINT = process.env.CDN_ENDPOINT;

// Redis client for cache management
const redisClient = redis.createClient({
  socket: { host: VALKEY_HOST, port: 6379 }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Generate audio content
app.post('/api/audio/generate', async (req, res) => {
  try {
    const response = await axios.post(FUNCTION_URL, req.body);
    res.json({
      ...response.data,
      cdnUrl: response.data.audioUrl.replace('storage.googleapis.com', CDN_ENDPOINT)
    });
  } catch (error) {
    res.status(500).json({ error: 'Audio generation failed' });
  }
});

// Batch processing endpoint
app.post('/api/audio/batch', async (req, res) => {
  const { texts, voiceConfig } = req.body;
  const results = [];
  
  for (const text of texts) {
    try {
      const response = await axios.post(FUNCTION_URL, { text, voiceConfig });
      results.push({ text, success: true, result: response.data });
    } catch (error) {
      results.push({ text, success: false, error: error.message });
    }
  }
  
  res.json({ batchResults: results, processed: results.length });
});

// Cache analytics endpoint
app.get('/api/cache/stats', async (req, res) => {
  try {
    await redisClient.connect();
    const info = await redisClient.info('memory');
    await redisClient.disconnect();
    
    res.json({
      cacheInfo: info,
      endpoint: VALKEY_HOST,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({ error: 'Cache stats unavailable' });
  }
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Audio Management Service running on port ${PORT}`);
});
EOF
    
    # Build and deploy to Cloud Run
    log_info "Building container image..."
    gcloud builds submit --tag "gcr.io/${PROJECT_ID}/audio-management-service" --quiet
    
    # Get Function URL
    export FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region "${REGION}" --format="value(httpsTrigger.url)")
    
    # Deploy to Cloud Run
    gcloud run deploy audio-management-service \
        --image "gcr.io/${PROJECT_ID}/audio-management-service" \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --set-env-vars="FUNCTION_URL=${FUNCTION_URL},VALKEY_HOST=${VALKEY_HOST},CDN_ENDPOINT=${CDN_IP}" \
        --memory 512Mi \
        --cpu 1 \
        --min-instances 1 \
        --max-instances 10 \
        --quiet
    
    cd ..
    
    log_success "Cloud Run service deployed successfully"
}

# Function to perform post-deployment validation
validate_deployment() {
    log_info "Performing post-deployment validation..."
    
    # Get Cloud Run service URL
    local service_url=$(gcloud run services describe audio-management-service \
        --platform managed --region "${REGION}" --format="value(status.url)" 2>/dev/null || echo "")
    
    if [[ -z "$service_url" ]]; then
        log_error "Could not retrieve Cloud Run service URL"
        return 1
    fi
    
    # Test health endpoint
    log_info "Testing health endpoint..."
    local health_response=$(curl -s "${service_url}/health" || echo "FAILED")
    
    if echo "$health_response" | grep -q "healthy"; then
        log_success "Health check passed"
    else
        log_warning "Health check returned unexpected response: $health_response"
    fi
    
    # Test audio generation (if API is accessible)
    log_info "Testing audio generation endpoint..."
    local audio_test=$(curl -s -X POST "${service_url}/api/audio/generate" \
        -H "Content-Type: application/json" \
        -d '{
            "text": "Test audio generation",
            "voiceConfig": {
                "languageCode": "en-US",
                "voiceName": "en-US-Casual"
            }
        }' || echo "FAILED")
    
    if echo "$audio_test" | grep -q "audioUrl"; then
        log_success "Audio generation test passed"
    else
        log_warning "Audio generation test failed or returned unexpected response"
    fi
    
    # Update deployment state
    jq '.deployment_status = "completed" | .service_url = "'$service_url'" | .cdn_ip = "'$CDN_IP'"' deployment_state.json > deployment_state.tmp && mv deployment_state.tmp deployment_state.json
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log_info "=== DEPLOYMENT SUMMARY ==="
    log_success "All infrastructure has been deployed successfully!"
    echo ""
    log_info "Resource Details:"
    log_info "  • Project ID: ${PROJECT_ID}"
    log_info "  • Region: ${REGION}"
    log_info "  • Storage Bucket: ${BUCKET_NAME}"
    log_info "  • Valkey Instance: ${VALKEY_INSTANCE}"
    log_info "  • Cloud Function: ${FUNCTION_NAME}"
    log_info "  • CDN IP: ${CDN_IP}"
    echo ""
    
    local service_url=$(gcloud run services describe audio-management-service \
        --platform managed --region "${REGION}" --format="value(status.url)" 2>/dev/null || echo "Not available")
    
    log_info "Service Endpoints:"
    log_info "  • Audio Management API: ${service_url}"
    log_info "  • CDN Endpoint: http://${CDN_IP}"
    echo ""
    
    log_info "Next Steps:"
    log_info "  1. Test the audio generation API using the provided endpoints"
    log_info "  2. Configure domain name for production use (optional)"
    log_info "  3. Set up monitoring and alerting"
    log_info "  4. Review and adjust cache TTL settings based on usage patterns"
    echo ""
    
    log_warning "Important: This deployment incurs ongoing costs. Use destroy.sh to clean up when done."
    echo ""
    
    log_info "Deployment state saved to: deployment_state.json"
}

# Main deployment function
main() {
    local start_time=$(date +%s)
    
    log_info "Starting deployment of Scalable Audio Content Distribution solution..."
    log_info "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    
    # Run deployment steps
    check_prerequisites
    confirm_deployment
    setup_environment
    enable_apis
    create_storage_bucket
    create_vpc_network
    deploy_valkey_instance
    configure_tts_api
    deploy_cloud_function
    configure_cloud_cdn
    deploy_cloud_run_service
    validate_deployment
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    display_summary
    log_success "Deployment completed successfully in ${duration} seconds!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --project)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --auto-approve    Skip confirmation prompts"
            echo "  --project ID      Specify Google Cloud project ID"
            echo "  --region REGION   Specify deployment region (default: us-central1)"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main deployment
main