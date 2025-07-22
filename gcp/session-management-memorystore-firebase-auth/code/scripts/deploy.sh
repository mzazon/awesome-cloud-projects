#!/bin/bash

# Session Management with Cloud Memorystore and Firebase Auth - Deployment Script
# This script deploys a complete session management system using Cloud Memorystore Redis,
# Firebase Authentication, Cloud Functions, and Cloud Scheduler for automated cleanup.

set -euo pipefail

# Color codes for output formatting
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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI is not installed. Please install it first:"
        log_error "https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with Google Cloud. Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if project is set
    if ! gcloud config get-value project >/dev/null 2>&1; then
        log_error "No project set. Please run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    
    # Check if Firebase CLI is available (optional but recommended)
    if ! command_exists firebase; then
        log_warning "Firebase CLI not found. Some Firebase configuration steps may need manual setup."
        log_warning "Install Firebase CLI: npm install -g firebase-tools"
    fi
    
    # Check if Node.js is available for function development
    if ! command_exists node; then
        log_warning "Node.js not found. Required for Cloud Functions development."
        log_warning "Install Node.js: https://nodejs.org/"
    fi
    
    log_success "Prerequisites check completed"
}

# Function to initialize environment variables
initialize_environment() {
    log_info "Initializing environment variables..."
    
    # Set environment variables for consistent resource naming
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="us-central1"
    export ZONE="us-central1-a"
    export REDIS_INSTANCE_NAME="session-store"
    export FIREBASE_PROJECT_ID="${PROJECT_ID}"
    
    # Generate unique suffix for resource names to avoid conflicts
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export FUNCTION_NAME="session-manager-${RANDOM_SUFFIX}"
    export SECRET_NAME="redis-connection-${RANDOM_SUFFIX}"
    export CLEANUP_FUNCTION_NAME="session-cleanup-${RANDOM_SUFFIX}"
    export SCHEDULER_JOB_NAME="session-cleanup-job-${RANDOM_SUFFIX}"
    
    # Configure gcloud defaults for consistent operations
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Environment configured for project: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Redis instance: ${REDIS_INSTANCE_NAME}"
    log_info "Function name: ${FUNCTION_NAME}"
    log_info "Random suffix: ${RANDOM_SUFFIX}"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "redis.googleapis.com"
        "cloudfunctions.googleapis.com" 
        "secretmanager.googleapis.com"
        "firebase.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "cloudscheduler.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled successfully"
}

# Function to create Redis instance
create_redis_instance() {
    log_info "Creating Cloud Memorystore Redis instance..."
    
    # Check if Redis instance already exists
    if gcloud redis instances describe "${REDIS_INSTANCE_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        log_warning "Redis instance ${REDIS_INSTANCE_NAME} already exists"
        return 0
    fi
    
    # Create Redis instance with optimized settings for session storage
    if gcloud redis instances create "${REDIS_INSTANCE_NAME}" \
        --size=1 \
        --region="${REGION}" \
        --redis-version=redis_7_0 \
        --tier=basic \
        --display-name="Session Store" \
        --labels=purpose=session-management,environment=production,deployed-by=script; then
        
        log_success "Redis instance creation initiated"
    else
        log_error "Failed to create Redis instance"
        exit 1
    fi
    
    # Wait for instance creation to complete
    log_info "Waiting for Redis instance to become ready (this may take 3-5 minutes)..."
    local timeout=600  # 10 minutes timeout
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        local state=$(gcloud redis instances describe "${REDIS_INSTANCE_NAME}" \
            --region="${REGION}" \
            --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        if [ "$state" = "READY" ]; then
            log_success "Redis instance is ready"
            break
        elif [ "$state" = "CREATING" ]; then
            log_info "Redis instance still creating... (${elapsed}s elapsed)"
            sleep 30
            elapsed=$((elapsed + 30))
        else
            log_error "Redis instance in unexpected state: $state"
            exit 1
        fi
    done
    
    if [ $elapsed -ge $timeout ]; then
        log_error "Timeout waiting for Redis instance to become ready"
        exit 1
    fi
    
    # Display Redis instance details
    local redis_host=$(gcloud redis instances describe "${REDIS_INSTANCE_NAME}" \
        --region="${REGION}" \
        --format="value(host)")
    local redis_port=$(gcloud redis instances describe "${REDIS_INSTANCE_NAME}" \
        --region="${REGION}" \
        --format="value(port)")
    
    log_success "Redis instance created successfully"
    log_info "Host: ${redis_host}"
    log_info "Port: ${redis_port}"
}

# Function to store Redis connection in Secret Manager
create_secret() {
    log_info "Storing Redis connection details in Secret Manager..."
    
    # Retrieve Redis instance connection details
    local redis_host=$(gcloud redis instances describe "${REDIS_INSTANCE_NAME}" \
        --region="${REGION}" \
        --format="value(host)")
    
    local redis_port=$(gcloud redis instances describe "${REDIS_INSTANCE_NAME}" \
        --region="${REGION}" \
        --format="value(port)")
    
    # Create connection string for Redis client
    local redis_connection_string="redis://${redis_host}:${redis_port}"
    
    # Check if secret already exists
    if gcloud secrets describe "${SECRET_NAME}" >/dev/null 2>&1; then
        log_warning "Secret ${SECRET_NAME} already exists, updating..."
        echo "${redis_connection_string}" | gcloud secrets versions add "${SECRET_NAME}" \
            --data-file=-
    else
        # Store connection details securely in Secret Manager
        echo "${redis_connection_string}" | gcloud secrets create "${SECRET_NAME}" \
            --data-file=-
    fi
    
    log_success "Redis connection details stored securely in Secret Manager"
}

# Function to configure Firebase Authentication
configure_firebase_auth() {
    log_info "Configuring Firebase Authentication..."
    
    # Initialize Firebase in the current project (if not already done)
    if command_exists firebase; then
        firebase projects:addfirebase "${PROJECT_ID}" 2>/dev/null || {
            log_info "Firebase already initialized for project"
        }
        
        # Note: Firebase Auth provider configuration typically requires web console setup
        log_info "Firebase Authentication setup initiated"
        log_warning "Complete Firebase Auth setup in the console: https://console.firebase.google.com/project/${PROJECT_ID}/authentication"
    else
        log_warning "Firebase CLI not available. Manual setup required:"
        log_warning "1. Visit: https://console.firebase.google.com/project/${PROJECT_ID}/authentication"
        log_warning "2. Enable Email/Password authentication"
        log_warning "3. Configure any additional providers as needed"
    fi
    
    log_success "Firebase Authentication configuration completed"
}

# Function to create session management function
create_session_function() {
    log_info "Creating Cloud Function for session management..."
    
    # Create temporary directory for function code
    local temp_dir=$(mktemp -d)
    cd "${temp_dir}"
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "session-manager",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "redis": "^4.6.0",
    "firebase-admin": "^11.11.0",
    "express": "^4.18.0",
    "@google-cloud/secret-manager": "^5.0.0",
    "@google-cloud/logging": "^10.0.0"
  }
}
EOF
    
    # Create the main session management function
    cat > index.js << 'EOF'
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

async function initializeRedis() {
  if (!redisClient) {
    try {
      const [version] = await secretClient.accessSecretVersion({
        name: `projects/${process.env.GOOGLE_CLOUD_PROJECT}/secrets/${process.env.SECRET_NAME}/versions/latest`,
      });
      const connectionString = version.payload.data.toString();
      
      redisClient = redis.createClient({ url: connectionString });
      await redisClient.connect();
      console.log('Redis client connected successfully');
    } catch (error) {
      console.error('Redis connection failed:', error);
      throw error;
    }
  }
  return redisClient;
}

// Session management function
functions.http('sessionManager', async (req, res) => {
  try {
    // CORS headers
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    
    const client = await initializeRedis();
    const { action, token, sessionData } = req.body;
    
    if (!action || !token) {
      return res.status(400).json({ error: 'Missing required fields: action, token' });
    }
    
    // Verify Firebase token
    let decodedToken;
    try {
      decodedToken = await admin.auth().verifyIdToken(token);
    } catch (error) {
      await log.warning({ message: 'Invalid Firebase token', error: error.message });
      return res.status(401).json({ error: 'Invalid authentication token' });
    }
    
    const userId = decodedToken.uid;
    const sessionKey = `session:${userId}`;
    
    switch (action) {
      case 'create':
        const session = {
          userId,
          email: decodedToken.email,
          createdAt: Date.now(),
          lastAccessed: Date.now(),
          deviceInfo: req.headers['user-agent'] || 'unknown',
          ipAddress: req.ip || 'unknown',
          ...sessionData
        };
        
        await client.setEx(sessionKey, 3600, JSON.stringify(session));
        await log.info({ message: 'Session created', userId, sessionKey });
        
        res.json({ success: true, sessionId: sessionKey, expiresIn: 3600 });
        break;
        
      case 'validate':
        const existingSession = await client.get(sessionKey);
        if (existingSession) {
          const sessionObj = JSON.parse(existingSession);
          sessionObj.lastAccessed = Date.now();
          await client.setEx(sessionKey, 3600, JSON.stringify(sessionObj));
          
          res.json({ valid: true, session: sessionObj });
        } else {
          res.json({ valid: false, message: 'Session not found or expired' });
        }
        break;
        
      case 'destroy':
        await client.del(sessionKey);
        await log.info({ message: 'Session destroyed', userId, sessionKey });
        res.json({ success: true, message: 'Session destroyed successfully' });
        break;
        
      case 'refresh':
        const currentSession = await client.get(sessionKey);
        if (currentSession) {
          const sessionObj = JSON.parse(currentSession);
          sessionObj.lastAccessed = Date.now();
          await client.setEx(sessionKey, 3600, JSON.stringify(sessionObj));
          res.json({ success: true, session: sessionObj, expiresIn: 3600 });
        } else {
          res.status(404).json({ error: 'Session not found' });
        }
        break;
        
      default:
        res.status(400).json({ error: 'Invalid action. Supported: create, validate, destroy, refresh' });
    }
  } catch (error) {
    console.error('Session operation failed:', error);
    await log.error({ message: 'Session operation failed', error: error.message });
    res.status(500).json({ error: 'Internal server error' });
  }
});
EOF
    
    # Deploy the session management function
    log_info "Deploying session management function..."
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime=nodejs18 \
        --source=. \
        --entry-point=sessionManager \
        --trigger=http \
        --allow-unauthenticated \
        --set-env-vars="SECRET_NAME=${SECRET_NAME}" \
        --memory=512MB \
        --timeout=60s \
        --region="${REGION}" \
        --quiet; then
        
        log_success "Session management function deployed successfully"
    else
        log_error "Failed to deploy session management function"
        cd - >/dev/null
        rm -rf "${temp_dir}"
        exit 1
    fi
    
    # Grant function access to Secret Manager
    log_info "Granting Secret Manager access to function..."
    local function_sa="${PROJECT_ID}@appspot.gserviceaccount.com"
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${function_sa}" \
        --role="roles/secretmanager.secretAccessor" \
        --quiet
    
    # Get function URL for client integration
    local function_url=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)")
    
    log_success "Function URL: ${function_url}"
    
    # Clean up temporary directory
    cd - >/dev/null
    rm -rf "${temp_dir}"
}

# Function to create session cleanup function
create_cleanup_function() {
    log_info "Creating automated session cleanup function..."
    
    # Create temporary directory for cleanup function code
    local temp_dir=$(mktemp -d)
    cd "${temp_dir}"
    
    # Create package.json for cleanup function
    cat > package.json << 'EOF'
{
  "name": "session-cleanup",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "redis": "^4.6.0",
    "@google-cloud/secret-manager": "^5.0.0",
    "@google-cloud/logging": "^10.0.0"
  }
}
EOF
    
    # Create cleanup logic with analytics
    cat > index.js << 'EOF'
const functions = require('@google-cloud/functions-framework');
const redis = require('redis');
const { SecretManagerServiceClient } = require('@google-cloud/secret-manager');
const { Logging } = require('@google-cloud/logging');

const secretClient = new SecretManagerServiceClient();
const logging = new Logging();
const log = logging.log('session-cleanup');

functions.cloudEvent('sessionCleanup', async (cloudEvent) => {
  console.log('Session cleanup triggered:', cloudEvent);
  
  try {
    // Get Redis connection from Secret Manager
    const [version] = await secretClient.accessSecretVersion({
      name: `projects/${process.env.GOOGLE_CLOUD_PROJECT}/secrets/${process.env.SECRET_NAME}/versions/latest`,
    });
    const connectionString = version.payload.data.toString();
    
    const client = redis.createClient({ url: connectionString });
    await client.connect();
    console.log('Connected to Redis for cleanup');
    
    // Find all session keys
    const keys = await client.keys('session:*');
    let cleanedCount = 0;
    let activeCount = 0;
    let errorCount = 0;
    
    console.log(`Found ${keys.length} session keys to process`);
    
    for (const key of keys) {
      try {
        const sessionData = await client.get(key);
        if (sessionData) {
          const session = JSON.parse(sessionData);
          const hoursSinceLastAccess = (Date.now() - session.lastAccessed) / (1000 * 60 * 60);
          
          // Clean sessions older than 24 hours
          if (hoursSinceLastAccess > 24) {
            await client.del(key);
            cleanedCount++;
            console.log(`Cleaned session: ${key} (${hoursSinceLastAccess.toFixed(1)} hours old)`);
          } else {
            activeCount++;
          }
        } else {
          // Remove keys without data
          await client.del(key);
          cleanedCount++;
        }
      } catch (sessionError) {
        console.error(`Error processing session ${key}:`, sessionError);
        errorCount++;
      }
    }
    
    const cleanupStats = {
      message: 'Session cleanup completed',
      cleanedSessions: cleanedCount,
      activeSessions: activeCount,
      totalProcessed: keys.length,
      errors: errorCount,
      timestamp: new Date().toISOString()
    };
    
    await log.info(cleanupStats);
    console.log('Cleanup completed:', cleanupStats);
    
    await client.disconnect();
  } catch (error) {
    const errorLog = { message: 'Cleanup failed', error: error.message, timestamp: new Date().toISOString() };
    await log.error(errorLog);
    console.error('Cleanup failed:', error);
    throw error;
  }
});

// HTTP trigger version for manual testing
functions.http('sessionCleanupHttp', async (req, res) => {
  try {
    // Simulate cloud event for manual trigger
    const cloudEvent = { data: { trigger: 'manual' } };
    await functions.cloudEvent('sessionCleanup')(cloudEvent);
    res.json({ success: true, message: 'Manual cleanup completed' });
  } catch (error) {
    console.error('Manual cleanup failed:', error);
    res.status(500).json({ error: 'Cleanup failed', details: error.message });
  }
});
EOF
    
    # Deploy cleanup function
    log_info "Deploying session cleanup function..."
    if gcloud functions deploy "${CLEANUP_FUNCTION_NAME}" \
        --gen2 \
        --runtime=nodejs18 \
        --source=. \
        --entry-point=sessionCleanupHttp \
        --trigger=http \
        --set-env-vars="SECRET_NAME=${SECRET_NAME}" \
        --memory=256MB \
        --timeout=300s \
        --region="${REGION}" \
        --quiet; then
        
        log_success "Session cleanup function deployed successfully"
    else
        log_error "Failed to deploy session cleanup function"
        cd - >/dev/null
        rm -rf "${temp_dir}"
        exit 1
    fi
    
    # Clean up temporary directory
    cd - >/dev/null
    rm -rf "${temp_dir}"
}

# Function to configure Cloud Scheduler
configure_scheduler() {
    log_info "Configuring Cloud Scheduler for automated cleanup..."
    
    # Get cleanup function URL
    local cleanup_function_url=$(gcloud functions describe "${CLEANUP_FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)")
    
    # Check if scheduler job already exists
    if gcloud scheduler jobs describe "${SCHEDULER_JOB_NAME}" --location="${REGION}" >/dev/null 2>&1; then
        log_warning "Scheduler job ${SCHEDULER_JOB_NAME} already exists"
        return 0
    fi
    
    # Create scheduled job to run cleanup every 6 hours
    if gcloud scheduler jobs create http "${SCHEDULER_JOB_NAME}" \
        --location="${REGION}" \
        --schedule="0 */6 * * *" \
        --uri="${cleanup_function_url}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"trigger":"scheduled"}' \
        --description="Automated session cleanup every 6 hours" \
        --quiet; then
        
        log_success "Automated cleanup scheduled to run every 6 hours"
    else
        log_error "Failed to create scheduler job"
        exit 1
    fi
}

# Function to set up monitoring
setup_monitoring() {
    log_info "Setting up monitoring and alerting..."
    
    # Create alerting policy for Redis memory usage
    local policy_file=$(mktemp)
    cat > "${policy_file}" << EOF
{
  "displayName": "Redis Memory Usage Alert - ${REDIS_INSTANCE_NAME}",
  "conditions": [
    {
      "displayName": "Redis memory usage high",
      "conditionThreshold": {
        "filter": "resource.type=\"redis_instance\" AND resource.label.instance_id=\"${REDIS_INSTANCE_NAME}\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 0.8,
        "duration": "300s"
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "enabled": true
}
EOF
    
    # Create the alerting policy
    if gcloud alpha monitoring policies create --policy-from-file="${policy_file}" >/dev/null 2>&1; then
        log_success "Monitoring alert policy created for Redis memory usage"
    else
        log_warning "Failed to create monitoring alert policy (may require additional permissions)"
    fi
    
    rm -f "${policy_file}"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Redis Instance: ${REDIS_INSTANCE_NAME}"
    echo "Session Function: ${FUNCTION_NAME}"
    echo "Cleanup Function: ${CLEANUP_FUNCTION_NAME}"
    echo "Secret Name: ${SECRET_NAME}"
    echo "Scheduler Job: ${SCHEDULER_JOB_NAME}"
    echo ""
    
    # Get function URLs
    local session_url=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)" 2>/dev/null || echo "Error retrieving URL")
    
    local cleanup_url=$(gcloud functions describe "${CLEANUP_FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)" 2>/dev/null || echo "Error retrieving URL")
    
    echo "=== FUNCTION ENDPOINTS ==="
    echo "Session Management: ${session_url}"
    echo "Manual Cleanup: ${cleanup_url}"
    echo ""
    
    echo "=== NEXT STEPS ==="
    echo "1. Complete Firebase Authentication setup in the console:"
    echo "   https://console.firebase.google.com/project/${PROJECT_ID}/authentication"
    echo ""
    echo "2. Test the session management endpoint:"
    echo "   curl -X POST ${session_url} -H 'Content-Type: application/json' -d '{\"action\":\"create\",\"token\":\"YOUR_FIREBASE_TOKEN\"}'"
    echo ""
    echo "3. Monitor Redis performance in the console:"
    echo "   https://console.cloud.google.com/memorystore/redis/instances"
    echo ""
    echo "4. View function logs:"
    echo "   gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}"
    echo ""
    
    # Save deployment info to file
    cat > deployment-info.txt << EOF
Session Management Deployment Information
========================================
Deployment Date: $(date)
Project ID: ${PROJECT_ID}
Region: ${REGION}

Resources Created:
- Redis Instance: ${REDIS_INSTANCE_NAME}
- Session Function: ${FUNCTION_NAME}
- Cleanup Function: ${CLEANUP_FUNCTION_NAME}
- Secret: ${SECRET_NAME}
- Scheduler Job: ${SCHEDULER_JOB_NAME}

Function URLs:
- Session Management: ${session_url}
- Manual Cleanup: ${cleanup_url}

Firebase Console: https://console.firebase.google.com/project/${PROJECT_ID}/authentication
Redis Console: https://console.cloud.google.com/memorystore/redis/instances
EOF
    
    log_success "Deployment information saved to deployment-info.txt"
}

# Main deployment function
main() {
    echo "========================================"
    echo "Session Management System Deployment"
    echo "========================================"
    echo ""
    
    check_prerequisites
    initialize_environment
    enable_apis
    create_redis_instance
    create_secret
    configure_firebase_auth
    create_session_function
    create_cleanup_function
    configure_scheduler
    setup_monitoring
    display_summary
    
    log_success "Session management system deployed successfully!"
    echo ""
    echo "To clean up all resources, run: ./destroy.sh"
}

# Run main function
main "$@"