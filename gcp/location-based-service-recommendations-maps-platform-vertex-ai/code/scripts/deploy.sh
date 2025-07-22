#!/bin/bash

# Location-Based Service Recommendations Deployment Script
# This script deploys the complete infrastructure for AI-powered location recommendations
# using Google Maps Platform and Vertex AI

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
error_exit() {
    log_error "$1"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up resources created so far..."
    
    # Only cleanup if PROJECT_ID is set and not empty
    if [[ -n "${PROJECT_ID:-}" ]]; then
        # Delete Cloud Run service if it exists
        if gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
            log_info "Cleaning up Cloud Run service..."
            gcloud run services delete "${SERVICE_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --quiet || true
        fi
        
        # Delete Firestore database if it exists
        if gcloud firestore databases describe "${FIRESTORE_DATABASE}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
            log_info "Cleaning up Firestore database..."
            gcloud firestore databases delete "${FIRESTORE_DATABASE}" --project="${PROJECT_ID}" --quiet || true
        fi
        
        # Delete service account if it exists
        if gcloud iam service-accounts describe "location-ai-service@${PROJECT_ID}.iam.gserviceaccount.com" --project="${PROJECT_ID}" >/dev/null 2>&1; then
            log_info "Cleaning up service account..."
            gcloud iam service-accounts delete "location-ai-service@${PROJECT_ID}.iam.gserviceaccount.com" --project="${PROJECT_ID}" --quiet || true
        fi
        
        # Delete API key if it exists
        local api_key_name
        api_key_name=$(gcloud services api-keys list --project="${PROJECT_ID}" --format="value(name)" --filter="displayName:'Location Recommender API Key'" 2>/dev/null || true)
        if [[ -n "${api_key_name}" ]]; then
            log_info "Cleaning up API key..."
            gcloud services api-keys delete "${api_key_name}" --project="${PROJECT_ID}" --quiet || true
        fi
    fi
    
    # Clean up local files
    if [[ -d "recommendation-service" ]]; then
        log_info "Cleaning up local application files..."
        rm -rf recommendation-service
    fi
    
    [[ -f "firestore-indexes.yaml" ]] && rm -f firestore-indexes.yaml
    [[ -f "vertex-ai-config.json" ]] && rm -f vertex-ai-config.json
    [[ -f "test-integration.js" ]] && rm -f test-integration.js
    
    log_error "Cleanup completed. Please check the Google Cloud Console for any remaining resources."
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Main deployment function
main() {
    log_info "Starting Location-Based Service Recommendations deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Initialize project variables
    initialize_project
    
    # Create and configure project
    create_project
    
    # Enable required APIs
    enable_apis
    
    # Create Google Maps Platform API Key
    create_maps_api_key
    
    # Initialize Cloud Firestore Database
    setup_firestore
    
    # Configure Vertex AI Maps Grounding
    configure_vertex_ai
    
    # Create and deploy Cloud Run service
    deploy_cloud_run_service
    
    # Configure Vertex AI integration
    setup_vertex_ai_integration
    
    # Test the deployment
    test_deployment
    
    # Display deployment summary
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command_exists gcloud; then
        error_exit "Google Cloud CLI (gcloud) is not installed. Please install it from: https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | grep -q .; then
        error_exit "Not authenticated with Google Cloud. Please run: gcloud auth login"
    fi
    
    # Check if curl is available
    if ! command_exists curl; then
        error_exit "curl is not installed. Please install curl to test the deployment."
    fi
    
    # Check if jq is available (optional but recommended)
    if ! command_exists jq; then
        log_warning "jq is not installed. JSON output will not be formatted. Install jq for better output formatting."
    fi
    
    # Check if node and npm are available for local testing
    if ! command_exists node; then
        log_warning "Node.js is not installed. Local testing will be limited."
    fi
    
    log_success "Prerequisites check completed"
}

# Initialize project variables
initialize_project() {
    log_info "Initializing project variables..."
    
    # Set environment variables for the project
    export PROJECT_ID="${PROJECT_ID:-location-ai-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export SERVICE_NAME="${SERVICE_NAME:-location-recommender}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    export FIRESTORE_DATABASE="recommendations-${RANDOM_SUFFIX}"
    export MAPS_API_KEY_NAME="maps-api-key-${RANDOM_SUFFIX}"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Service Name: ${SERVICE_NAME}"
    log_info "Firestore Database: ${FIRESTORE_DATABASE}"
    
    log_success "Project variables initialized"
}

# Create and configure project
create_project() {
    log_info "Creating new Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log_warning "Project ${PROJECT_ID} already exists. Using existing project."
    else
        # Create new project
        gcloud projects create "${PROJECT_ID}" \
            --name="Location-Based AI Recommendations" || error_exit "Failed to create project"
        
        log_success "Project ${PROJECT_ID} created successfully"
    fi
    
    # Set as active project
    gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set active project"
    gcloud config set compute/region "${REGION}" || error_exit "Failed to set default region"
    
    # Check if billing is enabled
    local billing_account
    billing_account=$(gcloud billing projects describe "${PROJECT_ID}" --format="value(billingAccountName)" 2>/dev/null || true)
    
    if [[ -z "${billing_account}" ]]; then
        log_warning "Billing is not enabled for this project. Some services may not work."
        log_warning "Please enable billing in the Google Cloud Console: https://console.cloud.google.com/billing"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error_exit "Deployment cancelled by user"
        fi
    fi
    
    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "run.googleapis.com"
        "aiplatform.googleapis.com"
        "firestore.googleapis.com"
        "maps-backend.googleapis.com"
        "places-backend.googleapis.com"
        "geocoding-backend.googleapis.com"
        "mapsgrounding.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" || error_exit "Failed to enable ${api}"
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "Required APIs enabled successfully"
}

# Create Google Maps Platform API Key
create_maps_api_key() {
    log_info "Creating Google Maps Platform API Key..."
    
    # Check if API key already exists
    local existing_key_name
    existing_key_name=$(gcloud services api-keys list \
        --format="value(name)" \
        --filter="displayName:'Location Recommender API Key'" 2>/dev/null || true)
    
    if [[ -n "${existing_key_name}" ]]; then
        log_warning "API key 'Location Recommender API Key' already exists. Using existing key."
        export MAPS_API_KEY=$(gcloud services api-keys get-key-string "${existing_key_name}")
    else
        # Create API key for Maps Platform services
        gcloud services api-keys create \
            --display-name="Location Recommender API Key" \
            --api-target=service=maps-backend.googleapis.com \
            --api-target=service=places-backend.googleapis.com \
            --api-target=service=geocoding-backend.googleapis.com || error_exit "Failed to create API key"
        
        # Get the API key value
        local key_name
        key_name=$(gcloud services api-keys list \
            --format="value(name)" \
            --filter="displayName:'Location Recommender API Key'")
        
        export MAPS_API_KEY=$(gcloud services api-keys get-key-string "${key_name}")
    fi
    
    if [[ -z "${MAPS_API_KEY}" ]]; then
        error_exit "Failed to retrieve API key value"
    fi
    
    log_success "Maps Platform API key created: ${MAPS_API_KEY:0:10}..."
}

# Initialize Cloud Firestore Database
setup_firestore() {
    log_info "Setting up Cloud Firestore database..."
    
    # Check if database already exists
    if gcloud firestore databases describe "${FIRESTORE_DATABASE}" >/dev/null 2>&1; then
        log_warning "Firestore database ${FIRESTORE_DATABASE} already exists. Using existing database."
    else
        # Create Firestore database in native mode
        gcloud firestore databases create \
            --location="${REGION}" \
            --database="${FIRESTORE_DATABASE}" || error_exit "Failed to create Firestore database"
        
        log_success "Firestore database ${FIRESTORE_DATABASE} created"
    fi
    
    # Create indexes for efficient querying
    log_info "Creating Firestore indexes..."
    cat > firestore-indexes.yaml << 'EOF'
indexes:
  - collectionGroup: user_preferences
    fields:
      - fieldPath: userId
        order: ASCENDING
      - fieldPath: lastUpdated
        order: DESCENDING
  - collectionGroup: recommendations_cache
    fields:
      - fieldPath: locationHash
        order: ASCENDING
      - fieldPath: timestamp
        order: DESCENDING
EOF
    
    # Deploy indexes (this may fail if indexes already exist, which is OK)
    gcloud firestore indexes composite create firestore-indexes.yaml \
        --database="${FIRESTORE_DATABASE}" || log_warning "Indexes may already exist"
    
    log_success "Firestore database configuration completed"
}

# Configure Vertex AI Maps Grounding
configure_vertex_ai() {
    log_info "Configuring Vertex AI Maps Grounding..."
    
    # Store configuration for later use
    cat > vertex-ai-config.json << EOF
{
  "project_id": "${PROJECT_ID}",
  "region": "${REGION}",
  "model": "gemini-2.5-flash",
  "maps_grounding_enabled": true,
  "maps_api_key": "${MAPS_API_KEY}"
}
EOF
    
    log_warning "Maps Grounding access requires manual approval"
    log_info "Complete the opt-in form at:"
    log_info "https://docs.google.com/forms/d/e/1FAIpQLSdJixRKhCjPQ6jO34tHLtTzaypHE4FDKpX2BFsUwHrOLLg9IQ/viewform"
    log_info "Project ID: ${PROJECT_ID}"
    
    log_success "Vertex AI configuration prepared"
}

# Create and deploy Cloud Run service
deploy_cloud_run_service() {
    log_info "Creating and deploying Cloud Run service..."
    
    # Create the main application code
    mkdir -p recommendation-service
    cd recommendation-service
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "location-recommender",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "@google-cloud/firestore": "^7.1.0",
    "@google-cloud/aiplatform": "^3.11.0",
    "@googlemaps/google-maps-services-js": "^3.3.42",
    "express": "^4.18.2",
    "cors": "^2.8.5"
  },
  "engines": {
    "node": "18"
  }
}
EOF
    
    # Create the main server application
    cat > server.js << 'EOF'
const express = require('express');
const cors = require('cors');
const { Firestore } = require('@google-cloud/firestore');
const { PredictionServiceClient } = require('@google-cloud/aiplatform');
const { Client } = require('@googlemaps/google-maps-services-js');

const app = express();
const port = process.env.PORT || 8080;

// Initialize clients
const firestore = new Firestore({
  databaseId: process.env.FIRESTORE_DATABASE
});
const aiplatform = new PredictionServiceClient();
const mapsClient = new Client({});

app.use(cors());
app.use(express.json());

// Health check endpoint
app.get('/', (req, res) => {
  res.json({ 
    status: 'healthy', 
    service: 'location-recommender',
    timestamp: new Date().toISOString()
  });
});

// Main recommendation endpoint
app.post('/recommend', async (req, res) => {
  try {
    const { userId, latitude, longitude, preferences, radius = 5000 } = req.body;
    
    if (!userId || !latitude || !longitude) {
      return res.status(400).json({ 
        error: 'Missing required fields: userId, latitude, longitude' 
      });
    }

    // Get nearby places using Maps API
    const placesResponse = await mapsClient.placesNearby({
      params: {
        location: { lat: latitude, lng: longitude },
        radius: radius,
        type: preferences?.category || 'restaurant',
        key: process.env.MAPS_API_KEY
      }
    });

    // Store user location and preferences
    await firestore.collection('user_preferences').doc(userId).set({
      lastLocation: { latitude, longitude },
      preferences: preferences || {},
      lastUpdated: new Date()
    }, { merge: true });

    // Prepare context for Vertex AI
    const locationContext = {
      places: placesResponse.data.results.slice(0, 10),
      userPreferences: preferences,
      location: { latitude, longitude }
    };

    // Generate AI-powered recommendations
    const recommendations = await generateRecommendations(locationContext);

    res.json({
      recommendations,
      location: { latitude, longitude },
      radius,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('Recommendation error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

async function generateRecommendations(context) {
  // Simulate AI recommendations with place data
  // In production, this would use Vertex AI with Maps Grounding
  return context.places.map((place, index) => ({
    id: place.place_id,
    name: place.name,
    rating: place.rating || 4.0,
    vicinity: place.vicinity,
    types: place.types,
    confidence: Math.max(0.7, Math.random()),
    reason: `Recommended based on location and preferences`
  })).sort((a, b) => b.confidence - a.confidence);
}

app.listen(port, () => {
  console.log(`Location Recommender API running on port ${port}`);
});
EOF
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM node:18-slim
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
EXPOSE 8080
CMD ["npm", "start"]
EOF
    
    cd ..
    
    log_info "Deploying to Cloud Run..."
    
    # Deploy to Cloud Run
    gcloud run deploy "${SERVICE_NAME}" \
        --source ./recommendation-service \
        --region="${REGION}" \
        --allow-unauthenticated \
        --set-env-vars="FIRESTORE_DATABASE=${FIRESTORE_DATABASE}" \
        --set-env-vars="MAPS_API_KEY=${MAPS_API_KEY}" \
        --set-env-vars="PROJECT_ID=${PROJECT_ID}" \
        --cpu=1 \
        --memory=512Mi \
        --min-instances=0 \
        --max-instances=10 || error_exit "Failed to deploy Cloud Run service"
    
    # Get service URL
    export SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" \
        --region="${REGION}" \
        --format="value(status.url)")
    
    if [[ -z "${SERVICE_URL}" ]]; then
        error_exit "Failed to retrieve service URL"
    fi
    
    log_success "Service deployed at: ${SERVICE_URL}"
}

# Configure Vertex AI integration
setup_vertex_ai_integration() {
    log_info "Setting up Vertex AI integration..."
    
    # Create service account for AI operations
    local service_account_email="location-ai-service@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "${service_account_email}" >/dev/null 2>&1; then
        log_warning "Service account already exists. Using existing account."
    else
        gcloud iam service-accounts create location-ai-service \
            --display-name="Location AI Recommendation Service" || error_exit "Failed to create service account"
    fi
    
    # Grant necessary permissions
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${service_account_email}" \
        --role="roles/aiplatform.user" || error_exit "Failed to grant AI platform permissions"
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${service_account_email}" \
        --role="roles/datastore.user" || error_exit "Failed to grant Firestore permissions"
    
    # Update Cloud Run service to use the service account
    gcloud run services update "${SERVICE_NAME}" \
        --region="${REGION}" \
        --service-account="${service_account_email}" || error_exit "Failed to update Cloud Run service account"
    
    log_success "Vertex AI integration configured with proper permissions"
}

# Test the deployment
test_deployment() {
    log_info "Testing the deployment..."
    
    # Test health endpoint
    log_info "Testing health endpoint..."
    local health_response
    health_response=$(curl -s -w "%{http_code}" "${SERVICE_URL}/" -o /tmp/health_response.json || echo "000")
    
    if [[ "${health_response}" == "200" ]]; then
        log_success "Health check passed"
        if command_exists jq; then
            jq '.' /tmp/health_response.json
        else
            cat /tmp/health_response.json
        fi
    else
        log_warning "Health check failed with status: ${health_response}"
    fi
    
    # Test recommendation endpoint
    log_info "Testing recommendation endpoint..."
    local recommendation_response
    recommendation_response=$(curl -s -w "%{http_code}" -X POST "${SERVICE_URL}/recommend" \
        -H "Content-Type: application/json" \
        -d '{
          "userId": "test-user-deployment",
          "latitude": 37.7749,
          "longitude": -122.4194,
          "preferences": {
            "category": "restaurant",
            "cuisine": "italian"
          },
          "radius": 1500
        }' -o /tmp/recommendation_response.json || echo "000")
    
    if [[ "${recommendation_response}" == "200" ]]; then
        log_success "Recommendation test passed"
        if command_exists jq; then
            local rec_count
            rec_count=$(jq '.recommendations | length' /tmp/recommendation_response.json 2>/dev/null || echo "0")
            log_info "Found ${rec_count} recommendations"
        fi
    else
        log_warning "Recommendation test failed with status: ${recommendation_response}"
        if [[ -f /tmp/recommendation_response.json ]]; then
            cat /tmp/recommendation_response.json
        fi
    fi
    
    # Clean up temp files
    rm -f /tmp/health_response.json /tmp/recommendation_response.json
}

# Display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo "===================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Service Name: ${SERVICE_NAME}"
    echo "Service URL: ${SERVICE_URL}"
    echo "Firestore Database: ${FIRESTORE_DATABASE}"
    echo "Maps API Key: ${MAPS_API_KEY:0:10}..."
    echo ""
    echo "Next Steps:"
    echo "1. Complete Maps Grounding opt-in form for full AI capabilities"
    echo "2. Monitor costs in Google Cloud Console"
    echo "3. Configure additional security as needed"
    echo "4. Test the service with your application"
    echo ""
    echo "Important Files Created:"
    echo "- recommendation-service/ (application code)"
    echo "- firestore-indexes.yaml (database indexes)"
    echo "- vertex-ai-config.json (AI configuration)"
    echo ""
    echo "To clean up resources, run: ./scripts/destroy.sh"
}

# Run main function
main "$@"