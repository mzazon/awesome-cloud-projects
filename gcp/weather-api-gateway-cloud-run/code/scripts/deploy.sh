#!/bin/bash

# Weather API Gateway with Cloud Run - Deployment Script
# This script deploys a serverless weather API gateway using Google Cloud Run and Cloud Storage

set -e  # Exit on any error

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

# Configuration
DEFAULT_REGION="us-central1"
DEFAULT_SERVICE_NAME="weather-api-gateway"
REQUIRED_APIS=("run.googleapis.com" "storage.googleapis.com" "cloudbuild.googleapis.com")

# Parse command line arguments
DRY_RUN=false
FORCE=false
REGION=""
PROJECT_ID=""
SERVICE_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --service-name)
            SERVICE_NAME="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run         Show what would be deployed without making changes"
            echo "  --force           Skip confirmation prompts"
            echo "  --region REGION   GCP region (default: ${DEFAULT_REGION})"
            echo "  --project-id ID   GCP project ID (will create if not specified)"
            echo "  --service-name    Cloud Run service name (default: ${DEFAULT_SERVICE_NAME})"
            echo "  --help           Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set defaults
REGION=${REGION:-$DEFAULT_REGION}
SERVICE_NAME=${SERVICE_NAME:-$DEFAULT_SERVICE_NAME}

log_info "Starting Weather API Gateway deployment..."

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud SDK (gcloud) is not installed"
        log_error "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed (part of Google Cloud SDK)"
        exit 1
    fi
    
    # Check if jq is installed (for JSON parsing)
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some JSON parsing may not work optimally"
        log_warning "Install with: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Project setup
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID="weather-gateway-$(date +%s)"
        log_info "Generated project ID: $PROJECT_ID"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            # Create new project
            if gcloud projects create "$PROJECT_ID" --name="Weather API Gateway"; then
                log_success "Created new project: $PROJECT_ID"
            else
                log_error "Failed to create project. You may need to specify an existing project with --project-id"
                exit 1
            fi
        fi
    else
        # Check if project exists
        if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
            log_error "Project $PROJECT_ID does not exist"
            exit 1
        fi
        log_info "Using existing project: $PROJECT_ID"
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Set default project and region
        gcloud config set project "$PROJECT_ID"
        gcloud config set run/region "$REGION"
        log_success "Project configuration updated"
    fi
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        for api in "${REQUIRED_APIS[@]}"; do
            log_info "Enabling $api..."
            if gcloud services enable "$api"; then
                log_success "Enabled $api"
            else
                log_error "Failed to enable $api"
                exit 1
            fi
        done
    else
        for api in "${REQUIRED_APIS[@]}"; do
            log_info "[DRY RUN] Would enable $api"
        done
    fi
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for caching..."
    
    # Generate unique bucket name
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    BUCKET_NAME="weather-cache-${RANDOM_SUFFIX}"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create storage bucket
        if gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"; then
            log_success "Created storage bucket: $BUCKET_NAME"
        else
            log_error "Failed to create storage bucket"
            exit 1
        fi
        
        # Create lifecycle policy for cache expiration
        cat > lifecycle.json << EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {"age": 1}
      }
    ]
  }
}
EOF
        
        if gsutil lifecycle set lifecycle.json "gs://$BUCKET_NAME"; then
            log_success "Applied lifecycle policy (1-day expiration)"
            rm -f lifecycle.json
        else
            log_warning "Failed to apply lifecycle policy"
        fi
    else
        log_info "[DRY RUN] Would create bucket: weather-cache-XXXXXX"
        log_info "[DRY RUN] Would apply 1-day lifecycle policy"
    fi
    
    # Export bucket name for later use
    export BUCKET_NAME
}

# Create application files
create_application_files() {
    log_info "Creating weather API gateway application files..."
    
    # Create application directory
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p weather-gateway
        cd weather-gateway
        
        # Create main application file
        cat > main.py << 'EOF'
import os
import json
import requests
from datetime import datetime
from flask import Flask, request, jsonify
from google.cloud import storage

app = Flask(__name__)
storage_client = storage.Client()
bucket_name = os.environ.get('BUCKET_NAME')

@app.route('/weather', methods=['GET'])
def get_weather():
    city = request.args.get('city', 'New York')
    cache_key = f"weather_{city.replace(' ', '_').lower()}.json"
    
    try:
        # Check cache first
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(cache_key)
        
        if blob.exists():
            cached_data = json.loads(blob.download_as_text())
            cached_data['cached'] = True
            return jsonify(cached_data)
        
        # Fetch from external API (mock response for demo)
        weather_data = {
            'city': city,
            'temperature': 72,
            'condition': 'Sunny',
            'humidity': 65,
            'timestamp': datetime.now().isoformat(),
            'cached': False
        }
        
        # Cache the response
        blob.upload_from_string(json.dumps(weather_data))
        
        return jsonify(weather_data)
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy', 'service': 'weather-api-gateway'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF

        # Create requirements file
        cat > requirements.txt << EOF
Flask==3.1.0
google-cloud-storage==2.18.2
requests==2.32.3
gunicorn==23.0.0
EOF

        # Create Dockerfile
        cat > Dockerfile << EOF
FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD exec gunicorn --bind :\$PORT --workers 1 --threads 8 main:app
EOF

        log_success "Application files created in weather-gateway/"
    else
        log_info "[DRY RUN] Would create application files in weather-gateway/"
    fi
}

# Deploy to Cloud Run
deploy_cloud_run() {
    log_info "Deploying to Cloud Run..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Deploy to Cloud Run with automatic build
        if gcloud run deploy "$SERVICE_NAME" \
            --source . \
            --region "$REGION" \
            --allow-unauthenticated \
            --set-env-vars "BUCKET_NAME=$BUCKET_NAME" \
            --memory 512Mi \
            --cpu 1 \
            --max-instances 10 \
            --timeout 60s; then
            
            log_success "Cloud Run service deployed successfully"
            
            # Get the service URL
            SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
                --region "$REGION" \
                --format 'value(status.url)')
            
            log_success "Service URL: $SERVICE_URL"
            export SERVICE_URL
        else
            log_error "Failed to deploy Cloud Run service"
            exit 1
        fi
    else
        log_info "[DRY RUN] Would deploy Cloud Run service: $SERVICE_NAME"
        log_info "[DRY RUN] Would use environment variable BUCKET_NAME=$BUCKET_NAME"
    fi
}

# Configure IAM permissions
configure_permissions() {
    log_info "Configuring service account permissions..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Get the Cloud Run service account
        SERVICE_ACCOUNT=$(gcloud run services describe "$SERVICE_NAME" \
            --region "$REGION" \
            --format 'value(spec.template.spec.serviceAccountName)')
        
        if [[ -n "$SERVICE_ACCOUNT" ]]; then
            # Grant storage permissions
            if gsutil iam ch "serviceAccount:$SERVICE_ACCOUNT:objectAdmin" "gs://$BUCKET_NAME"; then
                log_success "Granted storage permissions to service account"
            else
                log_warning "Failed to grant bucket-level permissions"
            fi
            
            # Grant project-level storage permissions as backup
            if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$SERVICE_ACCOUNT" \
                --role="roles/storage.objectAdmin"; then
                log_success "Granted project-level storage permissions"
            else
                log_warning "Failed to grant project-level permissions"
            fi
        else
            log_warning "Could not retrieve service account information"
        fi
    else
        log_info "[DRY RUN] Would configure IAM permissions for Cloud Run service account"
    fi
}

# Test the deployment
test_deployment() {
    log_info "Testing the deployed API gateway..."
    
    if [[ "$DRY_RUN" == "false" ]] && [[ -n "$SERVICE_URL" ]]; then
        # Wait a moment for the service to be fully ready
        sleep 10
        
        # Test health endpoint
        if curl -s -f "$SERVICE_URL/health" > /dev/null; then
            log_success "Health check passed"
        else
            log_warning "Health check failed - service may still be starting"
        fi
        
        # Test weather endpoint
        if curl -s -f "$SERVICE_URL/weather?city=London" > /dev/null; then
            log_success "Weather API test passed"
        else
            log_warning "Weather API test failed - check service logs"
        fi
        
        log_info "Test the API manually with:"
        log_info "curl \"$SERVICE_URL/weather?city=London\""
        log_info "curl \"$SERVICE_URL/health\""
    else
        log_info "[DRY RUN] Would test deployed service endpoints"
    fi
}

# Save deployment info
save_deployment_info() {
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create deployment info file
        cat > ../deployment-info.json << EOF
{
  "project_id": "$PROJECT_ID",
  "region": "$REGION",
  "service_name": "$SERVICE_NAME",
  "bucket_name": "$BUCKET_NAME",
  "service_url": "$SERVICE_URL",
  "deployed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
        log_success "Deployment information saved to deployment-info.json"
        
        # Return to original directory
        cd ..
    fi
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial deployment..."
    
    # Try to delete Cloud Run service if it was created
    if [[ -n "$SERVICE_NAME" ]] && [[ "$DRY_RUN" == "false" ]]; then
        gcloud run services delete "$SERVICE_NAME" \
            --region "$REGION" \
            --quiet 2>/dev/null || true
    fi
    
    # Try to delete bucket if it was created
    if [[ -n "$BUCKET_NAME" ]] && [[ "$DRY_RUN" == "false" ]]; then
        gsutil -m rm -r "gs://$BUCKET_NAME" 2>/dev/null || true
    fi
    
    # Clean up local files
    rm -rf weather-gateway lifecycle.json 2>/dev/null || true
}

# Confirmation prompt
confirm_deployment() {
    if [[ "$FORCE" == "false" ]] && [[ "$DRY_RUN" == "false" ]]; then
        echo
        log_info "Deployment Configuration:"
        log_info "  Project ID: $PROJECT_ID"
        log_info "  Region: $REGION"
        log_info "  Service Name: $SERVICE_NAME"
        log_info "  Estimated Cost: $0.01-$0.10 for testing"
        echo
        read -p "Continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
}

# Main deployment flow
main() {
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Run deployment steps
    check_prerequisites
    setup_project
    confirm_deployment
    enable_apis
    create_storage_bucket
    create_application_files
    deploy_cloud_run
    configure_permissions
    test_deployment
    save_deployment_info
    
    # Final success message
    echo
    log_success "Weather API Gateway deployment completed successfully!"
    echo
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Deployment Summary:"
        log_info "  Project ID: $PROJECT_ID"
        log_info "  Service URL: $SERVICE_URL"
        log_info "  Storage Bucket: $BUCKET_NAME"
        echo
        log_info "Next Steps:"
        log_info "1. Test the API: curl \"$SERVICE_URL/weather?city=London\""
        log_info "2. View logs: gcloud run services logs tail $SERVICE_NAME --region=$REGION"
        log_info "3. Monitor costs: gcloud billing budgets list"
        log_info "4. Clean up when done: ./destroy.sh"
    else
        log_info "This was a dry run. Use './deploy.sh' to actually deploy."
    fi
}

# Run main function
main "$@"