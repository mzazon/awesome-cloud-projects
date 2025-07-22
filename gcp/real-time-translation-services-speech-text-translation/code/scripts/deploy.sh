#!/bin/bash

# Real-Time Translation Services Deployment Script
# Creates GCP infrastructure for speech-to-text and translation services
# Recipe: real-time-translation-services-speech-text-translation

set -euo pipefail

# Colors for output
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
    log_error "Deployment failed. Cleaning up resources..."
    if [[ -n "${PROJECT_ID:-}" ]]; then
        log_warning "To manually clean up, run: gcloud projects delete ${PROJECT_ID}"
    fi
    exit 1
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check for required tools
    for tool in openssl curl; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is required but not installed"
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="translation-platform-$(date +%s)"
        log_info "Generated PROJECT_ID: ${PROJECT_ID}"
    fi
    
    # Set default values
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export SERVICE_NAME="translation-service-${RANDOM_SUFFIX}"
    export FIRESTORE_DATABASE="translation-db-${RANDOM_SUFFIX}"
    export BILLING_ACCOUNT="${BILLING_ACCOUNT:-}"
    
    log_info "Environment configured:"
    log_info "  PROJECT_ID: ${PROJECT_ID}"
    log_info "  REGION: ${REGION}"
    log_info "  SERVICE_NAME: ${SERVICE_NAME}"
    
    # Save environment variables to file for cleanup script
    cat > .env.deploy << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
SERVICE_NAME=${SERVICE_NAME}
FIRESTORE_DATABASE=${FIRESTORE_DATABASE}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
}

# Create and configure GCP project
create_project() {
    log_info "Creating GCP project: ${PROJECT_ID}..."
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_warning "Project ${PROJECT_ID} already exists. Using existing project."
    else
        gcloud projects create "${PROJECT_ID}" \
            --name="Real-time Translation Platform" \
            --set-as-default
        log_success "Project created successfully"
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Link billing account if provided
    if [[ -n "${BILLING_ACCOUNT}" ]]; then
        log_info "Linking billing account: ${BILLING_ACCOUNT}"
        gcloud billing projects link "${PROJECT_ID}" \
            --billing-account="${BILLING_ACCOUNT}"
        log_success "Billing account linked"
    else
        log_warning "No billing account provided. You may need to enable billing manually."
        log_warning "Set BILLING_ACCOUNT environment variable to enable automatic billing setup."
    fi
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "speech.googleapis.com"
        "translate.googleapis.com"
        "run.googleapis.com"
        "firestore.googleapis.com"
        "pubsub.googleapis.com"
        "cloudbuild.googleapis.com"
        "iam.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" --quiet
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create service account
create_service_account() {
    log_info "Creating service account for translation services..."
    
    local sa_name="translation-service"
    local sa_email="${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "${sa_email}" &> /dev/null; then
        log_warning "Service account ${sa_email} already exists"
    else
        gcloud iam service-accounts create "${sa_name}" \
            --display-name="Real-time Translation Service" \
            --description="Service account for speech and translation APIs"
        log_success "Service account created"
    fi
    
    # Grant necessary permissions
    local roles=(
        "roles/speech.client"
        "roles/translate.user"
        "roles/datastore.user"
        "roles/pubsub.publisher"
        "roles/storage.objectAdmin"
    )
    
    for role in "${roles[@]}"; do
        log_info "Granting role ${role} to service account..."
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${sa_email}" \
            --role="${role}" \
            --quiet
    done
    
    log_success "Service account configured with required permissions"
}

# Initialize Firestore database
setup_firestore() {
    log_info "Setting up Firestore database..."
    
    # Check if Firestore is already initialized
    if gcloud firestore databases describe --database="(default)" &> /dev/null; then
        log_warning "Firestore database already exists"
    else
        gcloud firestore databases create \
            --location="${REGION}" \
            --type=firestore-native \
            --quiet
        log_success "Firestore database created"
    fi
    
    # Wait for Firestore to be ready
    log_info "Waiting for Firestore to be ready..."
    sleep 15
    
    # Create composite index for conversation queries
    log_info "Creating Firestore indexes..."
    if gcloud firestore indexes composite create \
        --collection-group=conversations \
        --field-config=field-path=userId,order=ascending \
        --field-config=field-path=timestamp,order=descending \
        --quiet 2>/dev/null; then
        log_success "Firestore indexes created"
    else
        log_warning "Index creation failed or already exists"
    fi
}

# Create Pub/Sub resources
setup_pubsub() {
    log_info "Setting up Pub/Sub messaging..."
    
    # Create topics
    local topics=("translation-events" "translation-dlq")
    for topic in "${topics[@]}"; do
        if gcloud pubsub topics describe "${topic}" &> /dev/null; then
            log_warning "Topic ${topic} already exists"
        else
            gcloud pubsub topics create "${topic}" --quiet
            log_success "Topic ${topic} created"
        fi
    done
    
    # Create subscription
    if gcloud pubsub subscriptions describe "translation-processor" &> /dev/null; then
        log_warning "Subscription translation-processor already exists"
    else
        gcloud pubsub subscriptions create "translation-processor" \
            --topic="translation-events" \
            --message-retention-duration=7d \
            --quiet
        log_success "Pub/Sub subscription created"
    fi
}

# Create Cloud Storage bucket
setup_storage() {
    log_info "Setting up Cloud Storage for audio files..."
    
    local bucket_name="${PROJECT_ID}-audio-files"
    
    # Check if bucket already exists
    if gsutil ls "gs://${bucket_name}" &> /dev/null; then
        log_warning "Bucket gs://${bucket_name} already exists"
    else
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${bucket_name}"
        log_success "Storage bucket created"
    fi
    
    # Set lifecycle policy
    cat > lifecycle.json << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 30,
          "matchesStorageClass": ["STANDARD"]
        }
      }
    ]
  }
}
EOF
    
    gsutil lifecycle set lifecycle.json "gs://${bucket_name}"
    gsutil versioning set on "gs://${bucket_name}"
    rm -f lifecycle.json
    
    log_success "Storage bucket configured with lifecycle policy"
}

# Create and deploy translation service
deploy_translation_service() {
    log_info "Preparing translation service application..."
    
    # Create temporary directory for application
    local app_dir="./translation-app-${RANDOM_SUFFIX}"
    mkdir -p "${app_dir}/src"
    cd "${app_dir}"
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "real-time-translation-service",
  "version": "1.0.0",
  "description": "Real-time translation service with Speech-to-Text and Translation APIs",
  "main": "src/index.js",
  "scripts": {
    "start": "node src/index.js",
    "dev": "nodemon src/index.js"
  },
  "dependencies": {
    "@google-cloud/speech": "^6.0.0",
    "@google-cloud/translate": "^8.0.0",
    "@google-cloud/firestore": "^7.0.0",
    "@google-cloud/pubsub": "^4.0.0",
    "express": "^4.18.0",
    "ws": "^8.14.0",
    "uuid": "^9.0.0",
    "cors": "^2.8.5"
  },
  "engines": {
    "node": ">=18"
  }
}
EOF
    
    # Create main service implementation
    cat > src/index.js << 'EOF'
const express = require('express');
const WebSocket = require('ws');
const speech = require('@google-cloud/speech');
const {Translate} = require('@google-cloud/translate').v2;
const {Firestore} = require('@google-cloud/firestore');
const {PubSub} = require('@google-cloud/pubsub');
const {v4: uuidv4} = require('uuid');
const cors = require('cors');

// Initialize Google Cloud clients
const speechClient = new speech.SpeechClient();
const translateClient = new Translate();
const firestore = new Firestore();
const pubsub = new PubSub();

const app = express();
const PORT = process.env.PORT || 8080;

// Configure CORS and middleware
app.use(cors());
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// WebSocket server for real-time communication
const server = require('http').createServer(app);
const wss = new WebSocket.Server({ server });

// Active translation sessions
const activeSessions = new Map();

class TranslationSession {
  constructor(ws, sessionId, sourceLanguage, targetLanguages) {
    this.ws = ws;
    this.sessionId = sessionId;
    this.sourceLanguage = sourceLanguage;
    this.targetLanguages = targetLanguages;
    this.recognizeStream = null;
    this.conversationRef = firestore.collection('conversations').doc(sessionId);
    this.initializeConversation();
  }

  async initializeConversation() {
    await this.conversationRef.set({
      sessionId: this.sessionId,
      sourceLanguage: this.sourceLanguage,
      targetLanguages: this.targetLanguages,
      createdAt: new Date(),
      messages: []
    });
  }

  startSpeechRecognition() {
    const request = {
      config: {
        encoding: 'WEBM_OPUS',
        sampleRateHertz: 48000,
        languageCode: this.sourceLanguage,
        enableAutomaticPunctuation: true,
        enableWordTimeOffsets: true,
        model: 'latest_long'
      },
      interimResults: true,
    };

    this.recognizeStream = speechClient
      .streamingRecognize(request)
      .on('data', async (data) => {
        if (data.results[0] && data.results[0].alternatives[0]) {
          const transcript = data.results[0].alternatives[0].transcript;
          const isFinal = data.results[0].isFinal;
          
          if (isFinal) {
            await this.handleTranscription(transcript);
          } else {
            // Send interim results for immediate feedback
            this.ws.send(JSON.stringify({
              type: 'interim_transcript',
              text: transcript,
              sessionId: this.sessionId
            }));
          }
        }
      })
      .on('error', (error) => {
        console.error('Speech recognition error:', error);
        this.ws.send(JSON.stringify({
          type: 'error',
          message: 'Speech recognition failed',
          error: error.message
        }));
      });
  }

  async handleTranscription(originalText) {
    try {
      const messageId = uuidv4();
      const translations = {};
      
      // Translate to all target languages
      for (const targetLang of this.targetLanguages) {
        const [translation] = await translateClient.translate(originalText, {
          from: this.sourceLanguage,
          to: targetLang,
        });
        translations[targetLang] = translation;
      }

      // Store in Firestore
      const messageData = {
        messageId,
        originalText,
        translations,
        timestamp: new Date(),
        sourceLanguage: this.sourceLanguage
      };

      await this.conversationRef.update({
        messages: firestore.FieldValue.arrayUnion(messageData)
      });

      // Publish to Pub/Sub for analytics
      await pubsub.topic('translation-events').publish(
        Buffer.from(JSON.stringify({
          sessionId: this.sessionId,
          messageId,
          sourceLanguage: this.sourceLanguage,
          targetLanguages: this.targetLanguages,
          characterCount: originalText.length
        }))
      );

      // Send real-time results to client
      this.ws.send(JSON.stringify({
        type: 'translation_complete',
        messageId,
        originalText,
        translations,
        sessionId: this.sessionId
      }));

    } catch (error) {
      console.error('Translation error:', error);
      this.ws.send(JSON.stringify({
        type: 'error',
        message: 'Translation failed',
        error: error.message
      }));
    }
  }

  processAudioChunk(audioData) {
    if (this.recognizeStream) {
      this.recognizeStream.write(audioData);
    }
  }

  endSession() {
    if (this.recognizeStream) {
      this.recognizeStream.end();
    }
    activeSessions.delete(this.sessionId);
  }
}

// WebSocket connection handler
wss.on('connection', (ws, req) => {
  console.log('New WebSocket connection established');
  
  ws.on('message', async (message) => {
    try {
      const data = JSON.parse(message);
      
      switch (data.type) {
        case 'start_session':
          const sessionId = uuidv4();
          const session = new TranslationSession(
            ws,
            sessionId,
            data.sourceLanguage || 'en-US',
            data.targetLanguages || ['es', 'fr', 'de']
          );
          
          activeSessions.set(sessionId, session);
          session.startSpeechRecognition();
          
          ws.send(JSON.stringify({
            type: 'session_started',
            sessionId,
            sourceLanguage: session.sourceLanguage,
            targetLanguages: session.targetLanguages
          }));
          break;
          
        case 'audio_data':
          const activeSession = activeSessions.get(data.sessionId);
          if (activeSession) {
            const audioBuffer = Buffer.from(data.audio, 'base64');
            activeSession.processAudioChunk(audioBuffer);
          }
          break;
          
        case 'end_session':
          const endSession = activeSessions.get(data.sessionId);
          if (endSession) {
            endSession.endSession();
            ws.send(JSON.stringify({
              type: 'session_ended',
              sessionId: data.sessionId
            }));
          }
          break;
      }
    } catch (error) {
      console.error('WebSocket message error:', error);
      ws.send(JSON.stringify({
        type: 'error',
        message: 'Invalid message format',
        error: error.message
      }));
    }
  });

  ws.on('close', () => {
    // Clean up any active sessions for this connection
    for (const [sessionId, session] of activeSessions) {
      if (session.ws === ws) {
        session.endSession();
      }
    }
    console.log('WebSocket connection closed');
  });
});

// Start server
server.listen(PORT, () => {
  console.log(`Real-time translation service running on port ${PORT}`);
});
EOF
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
# Use official Node.js runtime as base image
FROM node:18-slim

# Create app directory
WORKDIR /usr/src/app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy application source
COPY src/ ./src/

# Create non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser appuser
RUN chown -R appuser:appuser /usr/src/app
USER appuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Start application
CMD ["npm", "start"]
EOF
    
    # Create .dockerignore
    cat > .dockerignore << 'EOF'
node_modules
npm-debug.log
.git
.gitignore
README.md
.env
.nyc_output
coverage
.nyc_output
.coverage
EOF
    
    log_info "Deploying translation service to Cloud Run..."
    
    # Deploy to Cloud Run
    gcloud run deploy "${SERVICE_NAME}" \
        --source . \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --service-account="translation-service@${PROJECT_ID}.iam.gserviceaccount.com" \
        --memory=2Gi \
        --cpu=2 \
        --concurrency=1000 \
        --max-instances=10 \
        --timeout=300 \
        --set-env-vars="PROJECT_ID=${PROJECT_ID}" \
        --quiet
    
    # Get service URL
    export SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" \
        --region "${REGION}" \
        --format="value(status.url)")
    
    # Save service URL to environment file
    echo "SERVICE_URL=${SERVICE_URL}" >> ../.env.deploy
    
    cd ..
    rm -rf "${app_dir}"
    
    log_success "Translation service deployed successfully"
    log_success "Service URL: ${SERVICE_URL}"
}

# Create test client
create_test_client() {
    log_info "Creating test client..."
    
    local client_dir="./client-test"
    mkdir -p "${client_dir}"
    
    cat > "${client_dir}/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Real-Time Translation Test</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .container { max-width: 800px; margin: 0 auto; }
        .status { padding: 10px; border-radius: 5px; margin: 10px 0; }
        .success { background-color: #d4edda; color: #155724; }
        .error { background-color: #f8d7da; color: #721c24; }
        .transcript { margin: 20px 0; padding: 15px; background: #f8f9fa; border-radius: 5px; }
        .translation { margin: 10px 0; padding: 10px; background: #e9ecef; border-radius: 3px; }
        button { padding: 10px 20px; margin: 5px; cursor: pointer; }
        .recording { background-color: #dc3545; color: white; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Real-Time Translation Service Test</h1>
        
        <div>
            <label for="sourceLanguage">Source Language:</label>
            <select id="sourceLanguage">
                <option value="en-US">English (US)</option>
                <option value="es-ES">Spanish</option>
                <option value="fr-FR">French</option>
                <option value="de-DE">German</option>
            </select>
        </div>
        
        <div>
            <label>Target Languages:</label>
            <input type="checkbox" id="es" value="es" checked> Spanish
            <input type="checkbox" id="fr" value="fr" checked> French
            <input type="checkbox" id="de" value="de" checked> German
            <input type="checkbox" id="ja" value="ja"> Japanese
        </div>
        
        <div>
            <button id="startBtn">Start Recording</button>
            <button id="stopBtn" disabled>Stop Recording</button>
        </div>
        
        <div id="status" class="status"></div>
        <div id="transcripts"></div>
        
        <script>
            const SERVICE_URL = '${SERVICE_URL}'.replace('https://', 'wss://');
            let ws = null;
            let mediaRecorder = null;
            let sessionId = null;
            
            document.getElementById('startBtn').addEventListener('click', startRecording);
            document.getElementById('stopBtn').addEventListener('click', stopRecording);
            
            function updateStatus(message, isError = false) {
                const statusDiv = document.getElementById('status');
                statusDiv.textContent = message;
                statusDiv.className = 'status ' + (isError ? 'error' : 'success');
            }
            
            async function startRecording() {
                try {
                    // Get selected languages
                    const sourceLanguage = document.getElementById('sourceLanguage').value;
                    const targetLanguages = Array.from(document.querySelectorAll('input[type="checkbox"]:checked'))
                        .map(cb => cb.value);
                    
                    if (targetLanguages.length === 0) {
                        updateStatus('Please select at least one target language', true);
                        return;
                    }
                    
                    // Connect to WebSocket
                    ws = new WebSocket(SERVICE_URL);
                    
                    ws.onopen = () => {
                        updateStatus('Connected to translation service');
                        
                        // Start translation session
                        ws.send(JSON.stringify({
                            type: 'start_session',
                            sourceLanguage: sourceLanguage,
                            targetLanguages: targetLanguages
                        }));
                    };
                    
                    ws.onmessage = (event) => {
                        const data = JSON.parse(event.data);
                        handleWebSocketMessage(data);
                    };
                    
                    ws.onerror = (error) => {
                        updateStatus('WebSocket error: ' + error.message, true);
                    };
                    
                    // Get microphone access
                    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
                    
                    mediaRecorder = new MediaRecorder(stream, {
                        mimeType: 'audio/webm;codecs=opus'
                    });
                    
                    mediaRecorder.ondataavailable = (event) => {
                        if (event.data.size > 0 && ws && ws.readyState === WebSocket.OPEN) {
                            const reader = new FileReader();
                            reader.onload = () => {
                                const audioData = reader.result.split(',')[1];
                                ws.send(JSON.stringify({
                                    type: 'audio_data',
                                    sessionId: sessionId,
                                    audio: audioData
                                }));
                            };
                            reader.readAsDataURL(event.data);
                        }
                    };
                    
                    mediaRecorder.start(100); // Send data every 100ms
                    
                    document.getElementById('startBtn').disabled = true;
                    document.getElementById('stopBtn').disabled = false;
                    document.getElementById('startBtn').textContent = 'Recording...';
                    document.getElementById('startBtn').className = 'recording';
                    
                } catch (error) {
                    updateStatus('Error starting recording: ' + error.message, true);
                }
            }
            
            function stopRecording() {
                if (mediaRecorder && mediaRecorder.state !== 'inactive') {
                    mediaRecorder.stop();
                    mediaRecorder.stream.getTracks().forEach(track => track.stop());
                }
                
                if (ws && sessionId) {
                    ws.send(JSON.stringify({
                        type: 'end_session',
                        sessionId: sessionId
                    }));
                }
                
                if (ws) {
                    ws.close();
                }
                
                document.getElementById('startBtn').disabled = false;
                document.getElementById('stopBtn').disabled = true;
                document.getElementById('startBtn').textContent = 'Start Recording';
                document.getElementById('startBtn').className = '';
                
                updateStatus('Recording stopped');
            }
            
            function handleWebSocketMessage(data) {
                const transcriptsDiv = document.getElementById('transcripts');
                
                switch (data.type) {
                    case 'session_started':
                        sessionId = data.sessionId;
                        updateStatus('Translation session started');
                        break;
                        
                    case 'interim_transcript':
                        updateStatus('Listening: ' + data.text);
                        break;
                        
                    case 'translation_complete':
                        const transcriptDiv = document.createElement('div');
                        transcriptDiv.className = 'transcript';
                        transcriptDiv.innerHTML = '<strong>Original:</strong> ' + data.originalText;
                        
                        Object.entries(data.translations).forEach(([lang, translation]) => {
                            const translationDiv = document.createElement('div');
                            translationDiv.className = 'translation';
                            translationDiv.innerHTML = '<strong>' + lang.toUpperCase() + ':</strong> ' + translation;
                            transcriptDiv.appendChild(translationDiv);
                        });
                        
                        transcriptsDiv.appendChild(transcriptDiv);
                        updateStatus('Translation completed');
                        break;
                        
                    case 'session_ended':
                        updateStatus('Session ended');
                        break;
                        
                    case 'error':
                        updateStatus('Error: ' + data.message, true);
                        break;
                }
            }
        </script>
    </div>
</body>
</html>
EOF
    
    log_success "Test client created at: $(pwd)/${client_dir}/index.html"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Cloud Run service
    if gcloud run services describe "${SERVICE_NAME}" --region "${REGION}" &> /dev/null; then
        log_success "Cloud Run service is running"
        
        # Test health endpoint
        if curl -f "${SERVICE_URL}/health" &> /dev/null; then
            log_success "Health endpoint is responding"
        else
            log_warning "Health endpoint not responding yet (may need time to warm up)"
        fi
    else
        log_error "Cloud Run service not found"
        return 1
    fi
    
    # Check Firestore
    if gcloud firestore databases describe --database="(default)" &> /dev/null; then
        log_success "Firestore database is active"
    else
        log_warning "Firestore database not found"
    fi
    
    # Check Pub/Sub
    if gcloud pubsub topics describe "translation-events" &> /dev/null; then
        log_success "Pub/Sub topics are configured"
    else
        log_warning "Pub/Sub topics not found"
    fi
    
    # Check Storage bucket
    if gsutil ls "gs://${PROJECT_ID}-audio-files" &> /dev/null; then
        log_success "Storage bucket is configured"
    else
        log_warning "Storage bucket not found"
    fi
}

# Display deployment summary
show_summary() {
    log_success "=== DEPLOYMENT COMPLETE ==="
    echo
    log_info "Project Details:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Service Name: ${SERVICE_NAME}"
    echo
    log_info "Service Endpoints:"
    log_info "  Translation Service: ${SERVICE_URL}"
    log_info "  Health Check: ${SERVICE_URL}/health"
    log_info "  WebSocket: ${SERVICE_URL/https:/wss:}"
    echo
    log_info "Test Client:"
    log_info "  Open client-test/index.html in a web browser to test the service"
    echo
    log_info "Next Steps:"
    log_info "  1. Open the test client to verify real-time translation"
    log_info "  2. Configure your applications to use the WebSocket endpoint"
    log_info "  3. Monitor usage in the Google Cloud Console"
    echo
    log_warning "Remember to run ./destroy.sh when you're done testing to avoid charges"
    echo
    log_info "Environment variables saved to .env.deploy for cleanup"
}

# Main deployment function
main() {
    log_info "Starting deployment of Real-Time Translation Services..."
    echo
    
    check_prerequisites
    setup_environment
    create_project
    enable_apis
    create_service_account
    setup_firestore
    setup_pubsub
    setup_storage
    deploy_translation_service
    create_test_client
    validate_deployment
    show_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"