#!/bin/bash

# Deploy script for URL Shortener with Cloud Functions and Firestore
# This script creates a complete serverless URL shortening solution on Google Cloud Platform

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
    log_error "Deployment failed. Check the logs above for details."
    log_info "You can run ./destroy.sh to clean up any partially created resources."
    exit 1
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI is not installed. Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found. Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if firebase CLI is installed
    if ! command -v firebase &> /dev/null; then
        log_warning "Firebase CLI is not installed. Installing via npm..."
        if command -v npm &> /dev/null; then
            npm install -g firebase-tools
        else
            log_error "npm is required to install Firebase CLI. Please install Node.js and npm first."
            exit 1
        fi
    fi
    
    # Check if Node.js is available for function deployment
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed. Please install Node.js 16 or later."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Allow user to override project ID
    if [[ -z "${PROJECT_ID:-}" ]]; then
        read -p "Enter Google Cloud Project ID (or press Enter to create a new one): " PROJECT_ID
        if [[ -z "$PROJECT_ID" ]]; then
            PROJECT_ID="url-shortener-$(date +%s)"
            log_info "Generated project ID: $PROJECT_ID"
        fi
    fi
    
    export PROJECT_ID
    export REGION="${REGION:-us-central1}"
    export FUNCTION_NAME="${FUNCTION_NAME:-url-shortener}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    export RANDOM_SUFFIX
    
    log_success "Environment configured - Project: $PROJECT_ID, Region: $REGION"
}

# Create or configure Google Cloud project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project exists
    if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_info "Project $PROJECT_ID already exists. Using existing project."
    else
        log_info "Creating new Google Cloud project: $PROJECT_ID"
        gcloud projects create "$PROJECT_ID" --name="URL Shortener Project" || {
            log_error "Failed to create project. The project ID might already be taken globally."
            exit 1
        }
    fi
    
    # Set the project as active
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set functions/region "$REGION"
    
    # Check if billing is enabled
    if ! gcloud billing projects describe "$PROJECT_ID" &>/dev/null; then
        log_warning "Billing is not enabled for this project."
        log_warning "Please enable billing at: https://console.cloud.google.com/billing/linkedaccount?project=$PROJECT_ID"
        read -p "Press Enter after enabling billing to continue..."
    fi
    
    log_success "Project setup completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "firestore.googleapis.com"
        "cloudbuild.googleapis.com"
        "firebase.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api"
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully activated..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Initialize Firestore database
setup_firestore() {
    log_info "Setting up Firestore database..."
    
    # Check if Firestore is already initialized
    if gcloud firestore databases describe --database="(default)" &>/dev/null; then
        log_info "Firestore database already exists"
    else
        log_info "Creating Firestore database in Native mode..."
        gcloud firestore databases create --region="$REGION"
        
        # Wait for database to be ready
        log_info "Waiting for Firestore database to be ready..."
        sleep 30
    fi
    
    log_success "Firestore database is ready"
}

# Create function source code
create_function_code() {
    log_info "Creating Cloud Function source code..."
    
    # Create temporary directory for function code
    FUNCTION_DIR=$(mktemp -d)
    cd "$FUNCTION_DIR"
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "url-shortener",
  "version": "1.0.0",
  "description": "Serverless URL shortener using Cloud Functions and Firestore",
  "main": "index.js",
  "engines": {
    "node": "20"
  },
  "dependencies": {
    "@google-cloud/firestore": "^7.10.0",
    "@google-cloud/functions-framework": "^3.4.0"
  }
}
EOF
    
    # Create the main function implementation
    cat > index.js << 'EOF'
const { Firestore } = require('@google-cloud/firestore');
const functions = require('@google-cloud/functions-framework');

// Initialize Firestore client
const firestore = new Firestore();
const COLLECTION_NAME = 'url-mappings';

// Generate random short ID
function generateShortId() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  for (let i = 0; i < 6; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

// Validate URL format
function isValidUrl(string) {
  try {
    const url = new URL(string);
    return url.protocol === 'http:' || url.protocol === 'https:';
  } catch (_) {
    return false;
  }
}

// HTTP Cloud Function for URL shortening and redirection
functions.http('urlShortener', async (req, res) => {
  // Enable CORS for web applications
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  try {
    if (req.method === 'POST' && req.path === '/shorten') {
      // Shorten URL endpoint
      const { url } = req.body;

      if (!url || !isValidUrl(url)) {
        return res.status(400).json({ error: 'Invalid URL provided' });
      }

      // Generate unique short ID with retry logic
      let shortId;
      let attempts = 0;
      const maxAttempts = 5;

      do {
        shortId = generateShortId();
        const existingDoc = await firestore.collection(COLLECTION_NAME).doc(shortId).get();
        if (!existingDoc.exists) break;
        attempts++;
      } while (attempts < maxAttempts);

      if (attempts >= maxAttempts) {
        return res.status(500).json({ error: 'Unable to generate unique short ID' });
      }

      // Store URL mapping in Firestore
      await firestore.collection(COLLECTION_NAME).doc(shortId).set({
        originalUrl: url,
        shortId: shortId,
        createdAt: new Date(),
        clickCount: 0
      });

      const shortUrl = `https://${req.get('host')}/${shortId}`;
      
      res.status(200).json({
        shortUrl: shortUrl,
        shortId: shortId,
        originalUrl: url
      });

    } else if (req.method === 'GET' && req.path !== '/') {
      // URL redirection endpoint
      const shortId = req.path.substring(1); // Remove leading slash

      if (!shortId) {
        return res.status(400).json({ error: 'Short ID required' });
      }

      // Lookup original URL in Firestore
      const doc = await firestore.collection(COLLECTION_NAME).doc(shortId).get();

      if (!doc.exists) {
        return res.status(404).json({ error: 'Short URL not found' });
      }

      const data = doc.data();
      
      // Increment click count atomically
      await firestore.collection(COLLECTION_NAME).doc(shortId).update({
        clickCount: (data.clickCount || 0) + 1,
        lastAccessed: new Date()
      });

      // Redirect to original URL
      res.redirect(301, data.originalUrl);

    } else {
      // API documentation endpoint
      res.status(200).json({
        message: 'URL Shortener API',
        endpoints: {
          'POST /shorten': 'Create short URL (body: {"url": "https://example.com"})',
          'GET /{shortId}': 'Redirect to original URL'
        }
      });
    }

  } catch (error) {
    console.error('Function error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});
EOF
    
    export FUNCTION_DIR
    log_success "Function source code created in: $FUNCTION_DIR"
}

# Deploy Cloud Function
deploy_function() {
    log_info "Deploying Cloud Function..."
    
    cd "$FUNCTION_DIR"
    
    # Deploy the HTTP Cloud Function
    gcloud functions deploy "$FUNCTION_NAME" \
        --runtime nodejs20 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point urlShortener \
        --memory 256MB \
        --timeout 60s \
        --max-instances 10
    
    # Get the function URL
    FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
        --format="value(httpsTrigger.url)")
    
    export FUNCTION_URL
    log_success "Cloud Function deployed at: $FUNCTION_URL"
}

# Configure Firestore security rules
setup_firestore_rules() {
    log_info "Setting up Firestore security rules..."
    
    cd "$FUNCTION_DIR"
    
    # Authenticate with Firebase
    if ! firebase projects:list | grep -q "$PROJECT_ID"; then
        log_info "Authenticating with Firebase..."
        firebase login --no-localhost
    fi
    
    # Use the project
    firebase use "$PROJECT_ID" --token "$(gcloud auth print-access-token)" 2>/dev/null || firebase use "$PROJECT_ID"
    
    # Create Firestore security rules file
    cat > firestore.rules << 'EOF'
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow read access to url-mappings for redirects
    match /url-mappings/{shortId} {
      allow read: if true;
      allow write: if false; // Only Cloud Function can write
    }
    
    // Deny all other access
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
EOF
    
    # Deploy Firestore security rules
    firebase deploy --only firestore:rules --token "$(gcloud auth print-access-token)" 2>/dev/null || firebase deploy --only firestore:rules
    
    log_success "Firestore security rules deployed"
}

# Test the deployment
test_deployment() {
    log_info "Testing the deployed URL shortener..."
    
    # Test URL shortening
    log_info "Testing URL shortening endpoint..."
    TEST_RESPONSE=$(curl -s -X POST "$FUNCTION_URL/shorten" \
        -H "Content-Type: application/json" \
        -d '{"url": "https://cloud.google.com/functions"}' || echo "FAILED")
    
    if [[ "$TEST_RESPONSE" == "FAILED" ]] || [[ ! "$TEST_RESPONSE" =~ "shortUrl" ]]; then
        log_error "URL shortening test failed"
        return 1
    fi
    
    # Extract short ID from response for redirect test
    SHORT_ID=$(echo "$TEST_RESPONSE" | grep -o '"shortId":"[^"]*"' | cut -d'"' -f4)
    
    if [[ -n "$SHORT_ID" ]]; then
        log_info "Testing URL redirection..."
        REDIRECT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$FUNCTION_URL/$SHORT_ID" || echo "FAILED")
        
        if [[ "$REDIRECT_STATUS" == "301" ]]; then
            log_success "All tests passed successfully!"
        else
            log_warning "URL shortening works but redirection test failed (Status: $REDIRECT_STATUS)"
        fi
    else
        log_warning "Could not extract short ID for redirect test"
    fi
    
    log_success "Basic functionality test completed"
}

# Cleanup temporary files
cleanup_temp_files() {
    if [[ -n "${FUNCTION_DIR:-}" ]] && [[ -d "$FUNCTION_DIR" ]]; then
        rm -rf "$FUNCTION_DIR"
        log_info "Cleaned up temporary files"
    fi
}

# Main deployment flow
main() {
    log_info "Starting URL Shortener deployment..."
    echo "=============================================="
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    setup_firestore
    create_function_code
    deploy_function
    setup_firestore_rules
    test_deployment
    cleanup_temp_files
    
    echo "=============================================="
    log_success "Deployment completed successfully!"
    echo ""
    log_info "Your URL Shortener is ready at: $FUNCTION_URL"
    echo ""
    echo "Usage examples:"
    echo "1. Create a short URL:"
    echo "   curl -X POST $FUNCTION_URL/shorten \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '{\"url\": \"https://example.com\"}'"
    echo ""
    echo "2. Access shortened URL:"
    echo "   curl $FUNCTION_URL/{shortId}"
    echo ""
    echo "3. View API documentation:"
    echo "   curl $FUNCTION_URL/"
    echo ""
    log_info "Project: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Function: $FUNCTION_NAME"
    echo ""
    log_warning "Remember to run ./destroy.sh when you're done to avoid ongoing charges!"
}

# Run main function
main "$@"