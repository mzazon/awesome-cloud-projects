#!/bin/bash

# Real-time Video Collaboration with WebRTC and Cloud Run - Deployment Script
# This script deploys a complete video collaboration platform using:
# - Cloud Run for WebRTC signaling server
# - Firestore for room management
# - Identity-Aware Proxy for authentication

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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check for required tools
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    if ! command_exists docker; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! command_exists node; then
        log_error "Node.js is not installed. Please install Node.js first."
        exit 1
    fi
    
    if ! command_exists npm; then
        log_error "npm is not installed. Please install npm first."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Set configuration variables
configure_environment() {
    log_info "Configuring environment variables..."
    
    # Set default values or use environment variables
    export PROJECT_ID="${PROJECT_ID:-video-collab-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export SERVICE_NAME="${SERVICE_NAME:-webrtc-signaling}"
    export USER_EMAIL="${USER_EMAIL:-}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export FIRESTORE_DATABASE="video-rooms-${RANDOM_SUFFIX}"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Service Name: ${SERVICE_NAME}"
    log_info "Firestore Database: ${FIRESTORE_DATABASE}"
    
    # Prompt for user email if not provided
    if [[ -z "${USER_EMAIL}" ]]; then
        log_warning "USER_EMAIL not set. This is required for IAP configuration."
        read -p "Enter your email address for IAP access: " USER_EMAIL
        export USER_EMAIL
    fi
    
    log_success "Environment configured"
}

# Create and configure GCP project
setup_project() {
    log_info "Setting up GCP project..."
    
    # Check if project exists, create if it doesn't
    if ! gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log_info "Creating new project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" --name="Video Collaboration Platform"
        
        # Link billing account if available
        BILLING_ACCOUNT=$(gcloud billing accounts list --filter="open:true" --format="value(name)" --limit=1 2>/dev/null || true)
        if [[ -n "${BILLING_ACCOUNT}" ]]; then
            log_info "Linking billing account: ${BILLING_ACCOUNT}"
            gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT}"
        else
            log_warning "No billing account found. Please link a billing account manually."
        fi
    else
        log_info "Using existing project: ${PROJECT_ID}"
    fi
    
    # Set project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    log_success "Project setup completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required APIs..."
    
    local apis=(
        "run.googleapis.com"
        "firestore.googleapis.com"
        "iap.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}"
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "Required APIs enabled"
}

# Create Firestore database
create_firestore_database() {
    log_info "Creating Firestore database..."
    
    # Check if database already exists
    if gcloud firestore databases describe "${FIRESTORE_DATABASE}" >/dev/null 2>&1; then
        log_warning "Firestore database ${FIRESTORE_DATABASE} already exists"
    else
        log_info "Creating Firestore database: ${FIRESTORE_DATABASE}"
        gcloud firestore databases create \
            --database="${FIRESTORE_DATABASE}" \
            --location="${REGION}" \
            --type=firestore-native
    fi
    
    # Set as default database
    gcloud config set firestore/database "${FIRESTORE_DATABASE}"
    
    log_success "Firestore database configured: ${FIRESTORE_DATABASE}"
}

# Create application structure
create_application() {
    log_info "Creating WebRTC signaling application..."
    
    # Create temporary working directory
    WORK_DIR=$(mktemp -d)
    cd "${WORK_DIR}"
    
    # Create application directory structure
    mkdir -p webrtc-signaling/{src,public}
    cd webrtc-signaling
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "webrtc-signaling-server",
  "version": "1.0.0",
  "description": "WebRTC signaling server for video collaboration",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "socket.io": "^4.7.2",
    "@google-cloud/firestore": "^7.1.0",
    "cors": "^2.8.5"
  }
}
EOF
    
    # Create server.js
    cat > src/server.js << 'EOF'
const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const { Firestore } = require('@google-cloud/firestore');
const cors = require('cors');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

app.use(cors());
app.use(express.json());
app.use(express.static('public'));

const firestore = new Firestore();
const PORT = process.env.PORT || 8080;

// Room management and signaling logic
io.on('connection', (socket) => {
  console.log('User connected:', socket.id);

  socket.on('join-room', async (roomId) => {
    socket.join(roomId);
    
    // Update room participants in Firestore
    const roomRef = firestore.collection('rooms').doc(roomId);
    await roomRef.set({
      participants: Firestore.FieldValue.arrayUnion(socket.id),
      lastActivity: new Date()
    }, { merge: true });
    
    socket.to(roomId).emit('user-joined', socket.id);
  });

  socket.on('webrtc-offer', (data) => {
    socket.to(data.target).emit('webrtc-offer', {
      offer: data.offer,
      sender: socket.id
    });
  });

  socket.on('webrtc-answer', (data) => {
    socket.to(data.target).emit('webrtc-answer', {
      answer: data.answer,
      sender: socket.id
    });
  });

  socket.on('ice-candidate', (data) => {
    socket.to(data.target).emit('ice-candidate', {
      candidate: data.candidate,
      sender: socket.id
    });
  });

  socket.on('disconnect', async () => {
    console.log('User disconnected:', socket.id);
    // Remove from all rooms in Firestore
    const roomsQuery = await firestore.collection('rooms')
      .where('participants', 'array-contains', socket.id)
      .get();
    
    roomsQuery.forEach(async (doc) => {
      await doc.ref.update({
        participants: Firestore.FieldValue.arrayRemove(socket.id)
      });
    });
  });
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy' });
});

server.listen(PORT, () => {
  console.log(`Signaling server running on port ${PORT}`);
});
EOF
    
    # Create HTML interface
    cat > public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Video Collaboration Platform</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .video-container { display: flex; flex-wrap: wrap; gap: 20px; }
        video { width: 300px; height: 200px; border: 1px solid #ccc; }
        .controls { margin: 20px 0; }
        button { padding: 10px 20px; margin: 5px; }
    </style>
</head>
<body>
    <h1>Video Collaboration Platform</h1>
    <div class="controls">
        <input type="text" id="roomId" placeholder="Enter Room ID" value="room-123">
        <button id="joinRoom">Join Room</button>
        <button id="leaveRoom">Leave Room</button>
        <button id="toggleVideo">Toggle Video</button>
        <button id="toggleAudio">Toggle Audio</button>
    </div>
    <div class="video-container">
        <video id="localVideo" autoplay muted></video>
        <div id="remoteVideos"></div>
    </div>
    <script src="/socket.io/socket.io.js"></script>
    <script src="app.js"></script>
</body>
</html>
EOF
    
    # Create client-side JavaScript
    cat > public/app.js << 'EOF'
const socket = io();
const localVideo = document.getElementById('localVideo');
const remoteVideos = document.getElementById('remoteVideos');
const joinRoomBtn = document.getElementById('joinRoom');
const leaveRoomBtn = document.getElementById('leaveRoom');
const toggleVideoBtn = document.getElementById('toggleVideo');
const toggleAudioBtn = document.getElementById('toggleAudio');
const roomIdInput = document.getElementById('roomId');

let localStream;
let peerConnections = {};
let currentRoom = null;

const configuration = {
  iceServers: [
    { urls: 'stun:stun.l.google.com:19302' },
    { urls: 'stun:stun1.l.google.com:19302' }
  ]
};

// Get local media stream
async function getLocalStream() {
  try {
    localStream = await navigator.mediaDevices.getUserMedia({
      video: true,
      audio: true
    });
    localVideo.srcObject = localStream;
    return true;
  } catch (error) {
    console.error('Error accessing media devices:', error);
    return false;
  }
}

// Create peer connection
function createPeerConnection(userId) {
  const peerConnection = new RTCPeerConnection(configuration);
  
  // Add local stream tracks
  localStream.getTracks().forEach(track => {
    peerConnection.addTrack(track, localStream);
  });

  // Handle remote stream
  peerConnection.ontrack = (event) => {
    const remoteStream = event.streams[0];
    let remoteVideo = document.getElementById(`remote-${userId}`);
    
    if (!remoteVideo) {
      remoteVideo = document.createElement('video');
      remoteVideo.id = `remote-${userId}`;
      remoteVideo.autoplay = true;
      remoteVideos.appendChild(remoteVideo);
    }
    
    remoteVideo.srcObject = remoteStream;
  };

  // Handle ICE candidates
  peerConnection.onicecandidate = (event) => {
    if (event.candidate) {
      socket.emit('ice-candidate', {
        target: userId,
        candidate: event.candidate
      });
    }
  };

  return peerConnection;
}

// Join room
joinRoomBtn.addEventListener('click', async () => {
  const roomId = roomIdInput.value.trim();
  if (!roomId) return;

  const hasMedia = await getLocalStream();
  if (!hasMedia) return;

  currentRoom = roomId;
  socket.emit('join-room', roomId);
  joinRoomBtn.disabled = true;
  leaveRoomBtn.disabled = false;
});

// Socket event handlers
socket.on('user-joined', async (userId) => {
  const peerConnection = createPeerConnection(userId);
  peerConnections[userId] = peerConnection;

  const offer = await peerConnection.createOffer();
  await peerConnection.setLocalDescription(offer);

  socket.emit('webrtc-offer', {
    target: userId,
    offer: offer
  });
});

socket.on('webrtc-offer', async (data) => {
  const peerConnection = createPeerConnection(data.sender);
  peerConnections[data.sender] = peerConnection;

  await peerConnection.setRemoteDescription(data.offer);
  const answer = await peerConnection.createAnswer();
  await peerConnection.setLocalDescription(answer);

  socket.emit('webrtc-answer', {
    target: data.sender,
    answer: answer
  });
});

socket.on('webrtc-answer', async (data) => {
  const peerConnection = peerConnections[data.sender];
  if (peerConnection) {
    await peerConnection.setRemoteDescription(data.answer);
  }
});

socket.on('ice-candidate', async (data) => {
  const peerConnection = peerConnections[data.sender];
  if (peerConnection) {
    await peerConnection.addIceCandidate(data.candidate);
  }
});

// Toggle video/audio controls
toggleVideoBtn.addEventListener('click', () => {
  if (localStream) {
    const videoTrack = localStream.getVideoTracks()[0];
    if (videoTrack) {
      videoTrack.enabled = !videoTrack.enabled;
      toggleVideoBtn.textContent = videoTrack.enabled ? 'Turn Off Video' : 'Turn On Video';
    }
  }
});

toggleAudioBtn.addEventListener('click', () => {
  if (localStream) {
    const audioTrack = localStream.getAudioTracks()[0];
    if (audioTrack) {
      audioTrack.enabled = !audioTrack.enabled;
      toggleAudioBtn.textContent = audioTrack.enabled ? 'Mute Audio' : 'Unmute Audio';
    }
  }
});

// Leave room functionality
leaveRoomBtn.addEventListener('click', () => {
  if (currentRoom) {
    // Close all peer connections
    Object.values(peerConnections).forEach(pc => pc.close());
    peerConnections = {};
    
    // Stop local stream
    if (localStream) {
      localStream.getTracks().forEach(track => track.stop());
      localVideo.srcObject = null;
    }
    
    // Remove remote videos
    remoteVideos.innerHTML = '';
    
    socket.disconnect();
    currentRoom = null;
    joinRoomBtn.disabled = false;
    leaveRoomBtn.disabled = true;
  }
});
EOF
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
# Use official Node.js runtime as base image
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application code
COPY . .

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nodejs -u 1001

# Change ownership of the working directory
RUN chown -R nodejs:nodejs /app
USER nodejs

# Expose port
EXPOSE 8080

# Start application
CMD ["npm", "start"]
EOF
    
    # Store the work directory for later cleanup
    echo "${WORK_DIR}" > /tmp/webrtc_deploy_workdir
    
    log_success "WebRTC signaling application created"
}

# Deploy to Cloud Run
deploy_cloud_run() {
    log_info "Deploying signaling server to Cloud Run..."
    
    # Change to application directory
    WORK_DIR=$(cat /tmp/webrtc_deploy_workdir)
    cd "${WORK_DIR}/webrtc-signaling"
    
    # Deploy using Cloud Build and Cloud Run
    log_info "Building and deploying with Cloud Run..."
    gcloud run deploy "${SERVICE_NAME}" \
        --source . \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --memory 512Mi \
        --cpu 1 \
        --min-instances 0 \
        --max-instances 10 \
        --port 8080 \
        --set-env-vars "FIRESTORE_DATABASE=${FIRESTORE_DATABASE}" \
        --timeout 900
    
    # Get service URL
    export SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" \
        --region "${REGION}" \
        --format 'value(status.url)')
    
    log_success "Signaling server deployed to Cloud Run"
    log_info "Service URL: ${SERVICE_URL}"
    
    # Store service URL for later use
    echo "${SERVICE_URL}" > /tmp/webrtc_service_url
}

# Configure IAP permissions
configure_iap_permissions() {
    log_info "Configuring Identity-Aware Proxy permissions..."
    
    # Add IAP users
    if [[ -n "${USER_EMAIL}" ]]; then
        log_info "Adding IAP access for: ${USER_EMAIL}"
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="user:${USER_EMAIL}" \
            --role="roles/iap.httpsResourceAccessor"
        
        log_success "IAP permissions configured for ${USER_EMAIL}"
    else
        log_warning "USER_EMAIL not provided, skipping IAP user configuration"
    fi
    
    # Provide manual configuration instructions
    log_info "Manual IAP configuration required:"
    log_info "1. Configure OAuth consent screen at:"
    log_info "   https://console.cloud.google.com/apis/credentials/consent?project=${PROJECT_ID}"
    log_info "2. Create OAuth 2.0 client at:"
    log_info "   https://console.cloud.google.com/apis/credentials?project=${PROJECT_ID}"
    log_info "3. Enable IAP at:"
    log_info "   https://console.cloud.google.com/security/iap?project=${PROJECT_ID}"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Get service URL
    SERVICE_URL=$(cat /tmp/webrtc_service_url 2>/dev/null || echo "")
    
    if [[ -z "${SERVICE_URL}" ]]; then
        log_error "Service URL not found"
        return 1
    fi
    
    # Test health endpoint
    log_info "Testing health endpoint..."
    if curl -f -s "${SERVICE_URL}/health" | grep -q "healthy"; then
        log_success "Health check passed"
    else
        log_warning "Health check failed - service may still be starting"
    fi
    
    # Check Firestore database
    log_info "Verifying Firestore database..."
    if gcloud firestore databases describe "${FIRESTORE_DATABASE}" >/dev/null 2>&1; then
        log_success "Firestore database verified"
    else
        log_error "Firestore database not found"
        return 1
    fi
    
    # Test Socket.IO endpoint
    log_info "Testing Socket.IO endpoint..."
    if curl -I -s "${SERVICE_URL}/socket.io/?EIO=4&transport=polling" | grep -q "200 OK"; then
        log_success "Socket.IO endpoint accessible"
    else
        log_warning "Socket.IO endpoint test failed"
    fi
    
    log_success "Deployment validation completed"
}

# Cleanup temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove work directory if it exists
    if [[ -f /tmp/webrtc_deploy_workdir ]]; then
        WORK_DIR=$(cat /tmp/webrtc_deploy_workdir)
        if [[ -d "${WORK_DIR}" ]]; then
            rm -rf "${WORK_DIR}"
            log_info "Removed temporary directory: ${WORK_DIR}"
        fi
        rm -f /tmp/webrtc_deploy_workdir
    fi
    
    # Keep service URL for destroy script
    # rm -f /tmp/webrtc_service_url
    
    log_success "Temporary files cleaned up"
}

# Display deployment summary
display_summary() {
    log_success "=== Deployment Summary ==="
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Firestore Database: ${FIRESTORE_DATABASE}"
    log_info "Cloud Run Service: ${SERVICE_NAME}"
    
    SERVICE_URL=$(cat /tmp/webrtc_service_url 2>/dev/null || echo "Not available")
    log_info "Service URL: ${SERVICE_URL}"
    
    if [[ -n "${USER_EMAIL}" ]]; then
        log_info "IAP User: ${USER_EMAIL}"
    fi
    
    echo
    log_info "Next Steps:"
    log_info "1. Complete OAuth consent screen configuration"
    log_info "2. Create OAuth 2.0 client credentials"
    log_info "3. Enable Identity-Aware Proxy"
    log_info "4. Access your video collaboration platform at: ${SERVICE_URL}"
    echo
    log_info "To test multi-user functionality:"
    log_info "- Open multiple browser windows to ${SERVICE_URL}"
    log_info "- Use the same room ID in all windows"
    log_info "- Allow camera/microphone access when prompted"
    echo
    log_warning "Remember to run ./destroy.sh when finished to avoid ongoing charges"
}

# Main deployment function
main() {
    log_info "Starting deployment of Real-time Video Collaboration Platform..."
    
    # Trap errors and cleanup
    trap cleanup_temp_files EXIT
    
    validate_prerequisites
    configure_environment
    setup_project
    enable_apis
    create_firestore_database
    create_application
    deploy_cloud_run
    configure_iap_permissions
    validate_deployment
    cleanup_temp_files
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"