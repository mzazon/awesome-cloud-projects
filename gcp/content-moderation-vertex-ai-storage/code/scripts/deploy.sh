#!/bin/bash

# Content Moderation with Vertex AI and Cloud Storage - Deployment Script
# This script deploys the complete content moderation infrastructure

set -e
set -u
set -o pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    log "Running in dry-run mode - no resources will be created"
fi

# Execute command with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    log "$description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    if ! eval "$cmd"; then
        error "Failed to execute: $cmd"
        return 1
    fi
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if project is set
    if [[ -z "${GOOGLE_CLOUD_PROJECT:-}" ]]; then
        GOOGLE_CLOUD_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$GOOGLE_CLOUD_PROJECT" ]]; then
            error "No Google Cloud project set. Please run 'gcloud config set project PROJECT_ID' first."
            exit 1
        fi
    fi
    
    success "Prerequisites check passed"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Set default values if not already set
    export PROJECT_ID="${GOOGLE_CLOUD_PROJECT}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource naming
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 7)")
    export BUCKET_INCOMING="content-incoming-${RANDOM_SUFFIX}"
    export BUCKET_QUARANTINE="content-quarantine-${RANDOM_SUFFIX}"
    export BUCKET_APPROVED="content-approved-${RANDOM_SUFFIX}"
    export TOPIC_NAME="content-moderation-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="content-moderator-${RANDOM_SUFFIX}"
    export NOTIFICATION_FUNCTION="quarantine-notifier-${RANDOM_SUFFIX}"
    export SERVICE_ACCOUNT_NAME="content-moderator-sa"
    
    # Display configuration
    log "Configuration:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    echo "  Zone: $ZONE"
    echo "  Incoming Bucket: $BUCKET_INCOMING"
    echo "  Quarantine Bucket: $BUCKET_QUARANTINE"
    echo "  Approved Bucket: $BUCKET_APPROVED"
    echo "  Topic Name: $TOPIC_NAME"
    echo "  Function Name: $FUNCTION_NAME"
    echo "  Notification Function: $NOTIFICATION_FUNCTION"
    echo "  Service Account: $SERVICE_ACCOUNT_NAME"
    echo "  Random Suffix: $RANDOM_SUFFIX"
    
    success "Environment initialized"
}

# Enable required APIs
enable_apis() {
    log "Enabling required APIs..."
    
    local apis=(
        "storage.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "aiplatform.googleapis.com"
        "eventarc.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        execute_command "gcloud services enable $api --project=$PROJECT_ID" "Enabling $api"
    done
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    success "APIs enabled successfully"
}

# Create Cloud Storage buckets
create_storage_buckets() {
    log "Creating Cloud Storage buckets..."
    
    # Create incoming content bucket
    execute_command "gsutil mb -p $PROJECT_ID -c STANDARD -l $REGION gs://$BUCKET_INCOMING" \
        "Creating incoming content bucket"
    
    # Create quarantine bucket
    execute_command "gsutil mb -p $PROJECT_ID -c STANDARD -l $REGION gs://$BUCKET_QUARANTINE" \
        "Creating quarantine bucket"
    
    # Create approved content bucket
    execute_command "gsutil mb -p $PROJECT_ID -c STANDARD -l $REGION gs://$BUCKET_APPROVED" \
        "Creating approved content bucket"
    
    # Configure lifecycle policy for quarantine bucket
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > /tmp/lifecycle.json << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {"age": 30}
      }
    ]
  }
}
EOF
        execute_command "gsutil lifecycle set /tmp/lifecycle.json gs://$BUCKET_QUARANTINE" \
            "Setting lifecycle policy for quarantine bucket"
        rm -f /tmp/lifecycle.json
    fi
    
    success "Storage buckets created successfully"
}

# Create Pub/Sub topic and subscription
create_pubsub_resources() {
    log "Creating Pub/Sub resources..."
    
    # Create topic
    execute_command "gcloud pubsub topics create $TOPIC_NAME --message-retention-duration=7d --project=$PROJECT_ID" \
        "Creating Pub/Sub topic"
    
    # Create subscription
    execute_command "gcloud pubsub subscriptions create ${TOPIC_NAME}-subscription --topic=$TOPIC_NAME --ack-deadline=600 --message-retention-duration=7d --max-delivery-attempts=3 --project=$PROJECT_ID" \
        "Creating Pub/Sub subscription"
    
    success "Pub/Sub resources created successfully"
}

# Create service account with permissions
create_service_account() {
    log "Creating service account and setting permissions..."
    
    # Create service account
    execute_command "gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME --display-name='Content Moderation Service Account' --description='Service account for automated content moderation' --project=$PROJECT_ID" \
        "Creating service account"
    
    local service_account_email="$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com"
    
    # Grant necessary permissions
    local roles=(
        "roles/storage.objectAdmin"
        "roles/aiplatform.user"
        "roles/pubsub.publisher"
    )
    
    for role in "${roles[@]}"; do
        execute_command "gcloud projects add-iam-policy-binding $PROJECT_ID --member='serviceAccount:$service_account_email' --role='$role'" \
            "Granting $role to service account"
    done
    
    success "Service account created and permissions granted"
}

# Deploy content moderation function
deploy_content_moderation_function() {
    log "Deploying content moderation function..."
    
    # Create temporary directory for function code
    local temp_dir="/tmp/content-moderator-$$"
    mkdir -p "$temp_dir"
    
    # Copy function code from terraform directory
    local function_code_dir="$(dirname "$0")/../terraform/function_code"
    
    if [[ ! -d "$function_code_dir" ]]; then
        error "Function code directory not found: $function_code_dir"
        return 1
    fi
    
    cp "$function_code_dir/main.py" "$temp_dir/"
    cp "$function_code_dir/requirements.txt" "$temp_dir/"
    
    # Deploy function
    local service_account_email="$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com"
    
    execute_command "gcloud functions deploy $FUNCTION_NAME --gen2 --runtime=python311 --region=$REGION --source=$temp_dir --entry-point=moderate_content --trigger-event-filters='type=google.cloud.storage.object.v1.finalized' --trigger-event-filters='bucket=$BUCKET_INCOMING' --service-account=$service_account_email --set-env-vars='GCP_PROJECT=$PROJECT_ID,QUARANTINE_BUCKET=$BUCKET_QUARANTINE,APPROVED_BUCKET=$BUCKET_APPROVED' --memory=1024MB --timeout=540s --max-instances=10 --project=$PROJECT_ID" \
        "Deploying content moderation function"
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    success "Content moderation function deployed successfully"
}

# Deploy notification function
deploy_notification_function() {
    log "Deploying notification function..."
    
    # Create temporary directory for function code
    local temp_dir="/tmp/notification-$$"
    mkdir -p "$temp_dir"
    
    # Copy function code from terraform directory
    local function_code_dir="$(dirname "$0")/../terraform/function_code"
    
    if [[ ! -d "$function_code_dir" ]]; then
        error "Function code directory not found: $function_code_dir"
        return 1
    fi
    
    cp "$function_code_dir/notification.py" "$temp_dir/main.py"
    cp "$function_code_dir/notification_requirements.txt" "$temp_dir/requirements.txt"
    
    # Deploy function
    local service_account_email="$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com"
    
    execute_command "gcloud functions deploy $NOTIFICATION_FUNCTION --gen2 --runtime=python311 --region=$REGION --source=$temp_dir --entry-point=notify_quarantine --trigger-event-filters='type=google.cloud.storage.object.v1.finalized' --trigger-event-filters='bucket=$BUCKET_QUARANTINE' --service-account=$service_account_email --set-env-vars='QUARANTINE_BUCKET=$BUCKET_QUARANTINE' --memory=256MB --timeout=60s --project=$PROJECT_ID" \
        "Deploying notification function"
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    success "Notification function deployed successfully"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "Dry-run completed successfully"
        return 0
    fi
    
    # Check buckets
    local buckets=("$BUCKET_INCOMING" "$BUCKET_QUARANTINE" "$BUCKET_APPROVED")
    for bucket in "${buckets[@]}"; do
        if gsutil ls "gs://$bucket" &>/dev/null; then
            success "Bucket $bucket exists"
        else
            error "Bucket $bucket not found"
        fi
    done
    
    # Check functions
    local functions=("$FUNCTION_NAME" "$NOTIFICATION_FUNCTION")
    for func in "${functions[@]}"; do
        if gcloud functions describe "$func" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
            success "Function $func deployed"
        else
            error "Function $func not found"
        fi
    done
    
    # Check service account
    local service_account_email="$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe "$service_account_email" --project="$PROJECT_ID" &>/dev/null; then
        success "Service account $service_account_email exists"
    else
        error "Service account $service_account_email not found"
    fi
    
    # Check Pub/Sub topic
    if gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" &>/dev/null; then
        success "Pub/Sub topic $TOPIC_NAME exists"
    else
        error "Pub/Sub topic $TOPIC_NAME not found"
    fi
    
    success "Deployment validation completed"
}

# Create test content
create_test_content() {
    log "Creating test content for validation..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Skipping test content creation in dry-run mode"
        return 0
    fi
    
    # Create safe test content
    echo "This is a perfectly normal and safe text message about technology and innovation." > /tmp/safe-text.txt
    
    # Upload test content
    execute_command "gsutil cp /tmp/safe-text.txt gs://$BUCKET_INCOMING/" \
        "Uploading test content"
    
    # Clean up local test file
    rm -f /tmp/safe-text.txt
    
    log "Test content uploaded. Monitor function logs to see processing results:"
    echo "  gcloud functions logs read $FUNCTION_NAME --region=$REGION --project=$PROJECT_ID"
    
    success "Test content created"
}

# Save deployment configuration
save_deployment_config() {
    log "Saving deployment configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Skipping configuration save in dry-run mode"
        return 0
    fi
    
    local config_file="$(dirname "$0")/deployment.config"
    
    cat > "$config_file" << EOF
# Content Moderation Deployment Configuration
# Generated on $(date)

PROJECT_ID="$PROJECT_ID"
REGION="$REGION"
ZONE="$ZONE"
BUCKET_INCOMING="$BUCKET_INCOMING"
BUCKET_QUARANTINE="$BUCKET_QUARANTINE"
BUCKET_APPROVED="$BUCKET_APPROVED"
TOPIC_NAME="$TOPIC_NAME"
FUNCTION_NAME="$FUNCTION_NAME"
NOTIFICATION_FUNCTION="$NOTIFICATION_FUNCTION"
SERVICE_ACCOUNT_NAME="$SERVICE_ACCOUNT_NAME"
RANDOM_SUFFIX="$RANDOM_SUFFIX"
EOF
    
    success "Deployment configuration saved to $config_file"
}

# Main deployment function
main() {
    log "Starting Content Moderation with Vertex AI and Cloud Storage deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Initialize environment
    initialize_environment
    
    # Confirm deployment
    if [[ "$DRY_RUN" == "false" ]]; then
        echo
        warning "This will create resources in Google Cloud Project: $PROJECT_ID"
        warning "Estimated cost: \$10-20 for initial setup and testing"
        echo
        read -p "Do you want to continue? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Deployment cancelled"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    enable_apis
    create_storage_buckets
    create_pubsub_resources
    create_service_account
    deploy_content_moderation_function
    deploy_notification_function
    validate_deployment
    create_test_content
    save_deployment_config
    
    echo
    success "Content Moderation deployment completed successfully!"
    echo
    log "Next steps:"
    echo "  1. Upload content to gs://$BUCKET_INCOMING to test the moderation pipeline"
    echo "  2. Monitor function logs: gcloud functions logs read $FUNCTION_NAME --region=$REGION"
    echo "  3. Check quarantined content: gsutil ls gs://$BUCKET_QUARANTINE"
    echo "  4. Check approved content: gsutil ls gs://$BUCKET_APPROVED"
    echo
    log "To clean up resources, run: ./destroy.sh"
}

# Run main function
main "$@"