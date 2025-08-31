#!/bin/bash

# Smart Parking Management System - Deployment Script
# This script deploys the complete smart parking management infrastructure on Google Cloud Platform
# Uses Maps Platform, Pub/Sub, Firestore, and Cloud Functions for real-time parking space monitoring

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
readonly LOG_FILE="${SCRIPT_DIR}/deployment.log"
readonly ERROR_LOG="${SCRIPT_DIR}/deployment_errors.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $*" | tee -a "$ERROR_LOG" >&2
}

log_success() {
    echo -e "${GREEN}✅ $*${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}ℹ️  $*${NC}" | tee -a "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check logs at $ERROR_LOG"
    log_error "To clean up partial deployment, run: $SCRIPT_DIR/destroy.sh"
    exit 1
}

trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_error "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Install with: sudo apt-get install jq (Ubuntu) or brew install jq (macOS)"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed and required for random string generation"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found"
        log_error "Run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Configuration setup
setup_configuration() {
    log_info "Setting up deployment configuration..."
    
    # Set default values or prompt for input
    export PROJECT_ID="${PROJECT_ID:-smart-parking-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export PUBSUB_TOPIC="parking-events-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="process-parking-data-${RANDOM_SUFFIX}"
    export FIRESTORE_COLLECTION="parking_spaces"
    
    # Create configuration file for cleanup script
    cat > "$SCRIPT_DIR/.deployment_config" << EOF
PROJECT_ID=$PROJECT_ID
REGION=$REGION
ZONE=$ZONE
PUBSUB_TOPIC=$PUBSUB_TOPIC
FUNCTION_NAME=$FUNCTION_NAME
FIRESTORE_COLLECTION=$FIRESTORE_COLLECTION
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    log_success "Configuration setup completed"
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Random Suffix: $RANDOM_SUFFIX"
}

# Project setup
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_warning "Project $PROJECT_ID already exists, using existing project"
    else
        log_info "Creating new project: $PROJECT_ID"
        gcloud projects create "$PROJECT_ID" \
            --name="Smart Parking Management" || {
            log_error "Failed to create project $PROJECT_ID"
            exit 1
        }
    fi
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    # Check if billing is enabled (required for API enablement)
    if ! gcloud beta billing projects describe "$PROJECT_ID" &>/dev/null; then
        log_warning "Billing is not enabled for this project"
        log_warning "You may need to enable billing manually in the Google Cloud Console"
        log_warning "Continuing with deployment, but some services may fail to enable"
    fi
    
    log_success "Project setup completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "pubsub.googleapis.com"
        "cloudfunctions.googleapis.com"
        "firestore.googleapis.com"
        "maps-backend.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
        "run.googleapis.com"
        "eventarc.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            log_success "Enabled $api"
        else
            log_error "Failed to enable $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All APIs enabled successfully"
}

# Create Pub/Sub infrastructure
create_pubsub() {
    log_info "Creating Pub/Sub topic and subscription..."
    
    # Create Pub/Sub topic for parking sensor data
    if gcloud pubsub topics create "$PUBSUB_TOPIC" --quiet; then
        log_success "Created Pub/Sub topic: $PUBSUB_TOPIC"
    else
        log_error "Failed to create Pub/Sub topic"
        exit 1
    fi
    
    # Create subscription for message processing
    if gcloud pubsub subscriptions create parking-processing \
        --topic="$PUBSUB_TOPIC" \
        --quiet; then
        log_success "Created Pub/Sub subscription: parking-processing"
    else
        log_error "Failed to create Pub/Sub subscription"
        exit 1
    fi
    
    log_success "Pub/Sub infrastructure created"
}

# Initialize Firestore database
initialize_firestore() {
    log_info "Initializing Firestore database..."
    
    # Check if Firestore is already initialized
    if gcloud firestore databases list --format="value(name)" | grep -q "projects/$PROJECT_ID/databases/(default)"; then
        log_warning "Firestore database already exists"
    else
        log_info "Creating Firestore database in Native mode..."
        if gcloud firestore databases create --region="$REGION" --quiet; then
            log_success "Firestore database created"
        else
            log_error "Failed to create Firestore database"
            exit 1
        fi
    fi
    
    log_success "Firestore initialization completed"
}

# Create service account for MQTT integration
create_service_account() {
    log_info "Creating service account for MQTT broker integration..."
    
    local sa_name="mqtt-pubsub-publisher"
    local sa_email="${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Create service account
    if gcloud iam service-accounts create "$sa_name" \
        --display-name="MQTT to Pub/Sub Publisher" \
        --quiet; then
        log_success "Created service account: $sa_name"
    else
        log_warning "Service account may already exist"
    fi
    
    # Grant Pub/Sub publisher permissions
    if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${sa_email}" \
        --role="roles/pubsub.publisher" \
        --quiet; then
        log_success "Granted Pub/Sub publisher role to service account"
    else
        log_error "Failed to grant permissions to service account"
        exit 1
    fi
    
    # Create and save service account key
    local key_file="$SCRIPT_DIR/mqtt-sa-key.json"
    if gcloud iam service-accounts keys create "$key_file" \
        --iam-account="$sa_email" \
        --quiet; then
        log_success "Created service account key: $key_file"
        log_warning "Keep this key file secure and do not commit to version control"
    else
        log_error "Failed to create service account key"
        exit 1
    fi
    
    log_success "Service account setup completed"
}

# Deploy Cloud Functions
deploy_cloud_functions() {
    log_info "Deploying Cloud Functions..."
    
    local functions_dir="$PROJECT_ROOT/terraform/functions"
    
    # Deploy parking data processor function
    log_info "Deploying parking data processor function..."
    if (cd "$functions_dir/parking-processor" && \
        gcloud functions deploy "$FUNCTION_NAME" \
            --gen2 \
            --runtime nodejs20 \
            --trigger-topic "$PUBSUB_TOPIC" \
            --source . \
            --entry-point processParkingData \
            --memory 256MB \
            --timeout 60s \
            --region "$REGION" \
            --quiet); then
        log_success "Deployed parking data processor function"
    else
        log_error "Failed to deploy parking data processor function"
        exit 1
    fi
    
    # Deploy parking management API
    log_info "Deploying parking management API..."
    if (cd "$functions_dir/parking-api" && \
        gcloud functions deploy parking-management-api \
            --gen2 \
            --runtime nodejs20 \
            --trigger-http \
            --allow-unauthenticated \
            --source . \
            --entry-point parkingApi \
            --memory 256MB \
            --timeout 60s \
            --region "$REGION" \
            --quiet); then
        log_success "Deployed parking management API"
    else
        log_error "Failed to deploy parking management API"
        exit 1
    fi
    
    # Get API endpoint URL
    local api_endpoint
    api_endpoint=$(gcloud functions describe parking-management-api \
        --region="$REGION" \
        --gen2 \
        --format="value(serviceConfig.uri)")
    
    echo "API_ENDPOINT=$api_endpoint" >> "$SCRIPT_DIR/.deployment_config"
    
    log_success "Cloud Functions deployment completed"
    log_info "API Endpoint: $api_endpoint"
}

# Create Maps Platform API key
create_maps_api_key() {
    log_info "Creating Maps Platform API key..."
    
    # Create Maps Platform API key
    if gcloud services api-keys create \
        --display-name="Smart Parking Maps API" \
        --quiet; then
        log_success "Created Maps Platform API key"
    else
        log_error "Failed to create Maps Platform API key"
        exit 1
    fi
    
    # Get the API key details
    local api_key_name
    api_key_name=$(gcloud services api-keys list \
        --filter="displayName:'Smart Parking Maps API'" \
        --format="value(name)" | head -1)
    
    if [ -n "$api_key_name" ]; then
        local maps_api_key
        maps_api_key=$(gcloud services api-keys get-key-string "$api_key_name")
        
        # Restrict API key to Maps services
        if gcloud services api-keys update "$api_key_name" \
            --api-target=service=maps-backend.googleapis.com \
            --quiet; then
            log_success "API key restricted to Maps services"
        else
            log_warning "Failed to restrict API key, manual restriction recommended"
        fi
        
        # Save API key information
        echo "MAPS_API_KEY=$maps_api_key" >> "$SCRIPT_DIR/.deployment_config"
        echo "API_KEY_NAME=$api_key_name" >> "$SCRIPT_DIR/.deployment_config"
        
        log_success "Maps Platform API key created and configured"
        log_warning "API Key: ${maps_api_key:0:20}... (truncated for security)"
    else
        log_error "Failed to retrieve API key information"
        exit 1
    fi
}

# Test deployment with sample data
test_deployment() {
    log_info "Testing deployment with sample sensor data..."
    
    # Create test sensor data
    local test_data='{"space_id":"A001","sensor_id":"parking-sensor-01","occupied":false,"confidence":0.98,"zone":"downtown","location":{"lat":37.7749,"lng":-122.4194},"timestamp":"'$(date -Iseconds)'"}'
    
    # Publish test message to Pub/Sub topic
    if echo "$test_data" | gcloud pubsub topics publish "$PUBSUB_TOPIC" --message=-; then
        log_success "Published test sensor data"
    else
        log_error "Failed to publish test data"
        exit 1
    fi
    
    # Wait for processing
    log_info "Waiting for message processing..."
    sleep 15
    
    # Test API endpoint
    local api_endpoint
    api_endpoint=$(grep "API_ENDPOINT=" "$SCRIPT_DIR/.deployment_config" | cut -d'=' -f2)
    
    if [ -n "$api_endpoint" ]; then
        log_info "Testing API endpoint..."
        if curl -s --fail "$api_endpoint/parking/zones/downtown/stats" > /dev/null; then
            log_success "API endpoint is responding"
        else
            log_warning "API endpoint test failed, but deployment may still be successful"
        fi
    fi
    
    log_success "Deployment testing completed"
}

# Generate deployment summary
generate_summary() {
    log_info "Generating deployment summary..."
    
    local summary_file="$SCRIPT_DIR/deployment_summary.txt"
    
    cat > "$summary_file" << EOF
Smart Parking Management System - Deployment Summary
====================================================

Deployment Date: $(date)
Project ID: $PROJECT_ID
Region: $REGION

Resources Created:
- Pub/Sub Topic: $PUBSUB_TOPIC
- Pub/Sub Subscription: parking-processing
- Cloud Function (Processor): $FUNCTION_NAME
- Cloud Function (API): parking-management-api
- Firestore Database: Native mode in $REGION
- Service Account: mqtt-pubsub-publisher
- Maps Platform API Key: Created and restricted

API Endpoint:
$(grep "API_ENDPOINT=" "$SCRIPT_DIR/.deployment_config" | cut -d'=' -f2)

Maps API Key:
$(grep "MAPS_API_KEY=" "$SCRIPT_DIR/.deployment_config" | cut -d'=' -f2 | cut -c1-20)... (truncated)

Next Steps:
1. Configure your MQTT broker to publish to the Pub/Sub topic
2. Use the service account key for MQTT broker authentication
3. Integrate the API endpoint with your applications
4. Monitor Cloud Function logs for message processing

Cleanup:
To remove all resources, run: $SCRIPT_DIR/destroy.sh

Configuration saved to: $SCRIPT_DIR/.deployment_config
Service account key saved to: $SCRIPT_DIR/mqtt-sa-key.json
EOF
    
    log_success "Deployment summary saved to: $summary_file"
    
    # Display summary
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Deployment Completed Successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$summary_file"
    echo ""
    echo -e "${YELLOW}Important Security Notes:${NC}"
    echo -e "${YELLOW}- Keep the service account key file secure${NC}"
    echo -e "${YELLOW}- Restrict API access in production environments${NC}"
    echo -e "${YELLOW}- Monitor costs and set billing alerts${NC}"
    echo ""
}

# Main deployment function
main() {
    log_info "Starting Smart Parking Management System deployment..."
    log_info "Deployment logs: $LOG_FILE"
    log_info "Error logs: $ERROR_LOG"
    
    check_prerequisites
    setup_configuration
    setup_project
    enable_apis
    create_pubsub
    initialize_firestore
    create_service_account
    deploy_cloud_functions
    create_maps_api_key
    test_deployment
    generate_summary
    
    log_success "Smart Parking Management System deployment completed successfully!"
}

# Check for dry run mode
if [[ "${1:-}" == "--dry-run" ]]; then
    log_info "Dry run mode - showing what would be deployed"
    log_info "Configuration:"
    setup_configuration
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Pub/Sub Topic: $PUBSUB_TOPIC"
    echo "Function Name: $FUNCTION_NAME"
    echo ""
    echo "APIs to enable: pubsub.googleapis.com, cloudfunctions.googleapis.com, firestore.googleapis.com, maps-backend.googleapis.com, cloudbuild.googleapis.com"
    echo "Resources to create: Pub/Sub topic, subscription, Cloud Functions, Firestore database, service account, Maps API key"
    exit 0
fi

# Run main deployment
main "$@"