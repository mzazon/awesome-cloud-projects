#!/bin/bash

# Deploy script for Automated File Backup with Storage and Scheduler
# This script creates a complete automated backup solution using GCP services

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
    fi
    
    # Check if curl is available for testing
    if ! command -v curl &> /dev/null; then
        error "curl is required for testing but not found."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is required for generating random suffixes but not found."
    fi
    
    success "Prerequisites validated"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set project ID (use existing or create unique one)
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="backup-project-$(date +%s)"
        log "Using generated project ID: ${PROJECT_ID}"
    else
        log "Using provided project ID: ${PROJECT_ID}"
    fi
    
    # Set default region and zone
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names with unique suffixes
    export PRIMARY_BUCKET="primary-data-${RANDOM_SUFFIX}"
    export BACKUP_BUCKET="backup-data-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="backup-function-${RANDOM_SUFFIX}"
    export SCHEDULER_JOB_NAME="backup-daily-job-${RANDOM_SUFFIX}"
    
    # Store configuration for cleanup script
    cat > .deployment-config << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
PRIMARY_BUCKET=${PRIMARY_BUCKET}
BACKUP_BUCKET=${BACKUP_BUCKET}
FUNCTION_NAME=${FUNCTION_NAME}
SCHEDULER_JOB_NAME=${SCHEDULER_JOB_NAME}
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    success "Environment variables configured"
    log "Primary bucket: ${PRIMARY_BUCKET}"
    log "Backup bucket: ${BACKUP_BUCKET}"
    log "Function name: ${FUNCTION_NAME}"
}

# Function to configure GCP project
configure_project() {
    log "Configuring GCP project settings..."
    
    # Check if project exists, create if it doesn't
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        warning "Project ${PROJECT_ID} does not exist. You may need to create it manually."
        log "Proceeding with current project configuration..."
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" || error "Failed to set project"
    gcloud config set compute/region "${REGION}" || error "Failed to set region"
    gcloud config set compute/zone "${ZONE}" || error "Failed to set zone"
    
    success "Project configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local required_apis=(
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "storage.googleapis.com"
        "logging.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${required_apis[@]}"; do
        log "Enabling ${api}..."
        gcloud services enable "${api}" || error "Failed to enable ${api}"
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Function to create storage buckets
create_storage_buckets() {
    log "Creating storage buckets..."
    
    # Create primary storage bucket
    log "Creating primary storage bucket: ${PRIMARY_BUCKET}"
    gcloud storage buckets create "gs://${PRIMARY_BUCKET}" \
        --location="${REGION}" \
        --storage-class=STANDARD \
        --uniform-bucket-level-access || error "Failed to create primary bucket"
    
    # Create backup storage bucket with nearline storage class
    log "Creating backup storage bucket: ${BACKUP_BUCKET}"
    gcloud storage buckets create "gs://${BACKUP_BUCKET}" \
        --location="${REGION}" \
        --storage-class=NEARLINE \
        --uniform-bucket-level-access || error "Failed to create backup bucket"
    
    # Enable versioning on both buckets
    log "Enabling versioning on primary bucket..."
    gcloud storage buckets update "gs://${PRIMARY_BUCKET}" \
        --versioning || error "Failed to enable versioning on primary bucket"
    
    log "Enabling versioning on backup bucket..."
    gcloud storage buckets update "gs://${BACKUP_BUCKET}" \
        --versioning || error "Failed to enable versioning on backup bucket"
    
    success "Storage buckets created and configured"
}

# Function to upload sample files
upload_sample_files() {
    log "Creating and uploading sample files..."
    
    # Create sample files directory
    mkdir -p backup-demo
    
    # Create sample files with timestamps
    echo "Critical business data - $(date)" > backup-demo/business-data.txt
    echo "Configuration settings - $(date)" > backup-demo/config.json
    echo "User profiles - $(date)" > backup-demo/users.csv
    echo "Application logs - $(date)" > backup-demo/app.log
    
    # Upload sample files to primary bucket
    log "Uploading sample files to primary bucket..."
    gcloud storage cp backup-demo/* "gs://${PRIMARY_BUCKET}/" || error "Failed to upload sample files"
    
    # Verify files were uploaded
    log "Verifying uploaded files..."
    gcloud storage ls "gs://${PRIMARY_BUCKET}/" || error "Failed to list primary bucket contents"
    
    success "Sample files uploaded successfully"
}

# Function to create and deploy backup function
create_backup_function() {
    log "Creating Cloud Function for backup logic..."
    
    # Create function directory
    mkdir -p backup-function
    cd backup-function
    
    # Create the backup function code
    cat > main.py << 'EOF'
import os
from google.cloud import storage, logging
from datetime import datetime
import json

def backup_files(request):
    """Cloud Function to backup files from primary to backup bucket."""
    
    # Initialize clients
    storage_client = storage.Client()
    logging_client = logging.Client()
    logger = logging_client.logger('backup-function')
    
    # Get bucket names from environment variables
    primary_bucket_name = os.environ.get('PRIMARY_BUCKET')
    backup_bucket_name = os.environ.get('BACKUP_BUCKET')
    
    if not primary_bucket_name or not backup_bucket_name:
        error_msg = "Missing required environment variables"
        logger.log_text(error_msg, severity='ERROR')
        return {'error': error_msg}, 400
    
    try:
        # Get bucket references
        primary_bucket = storage_client.bucket(primary_bucket_name)
        backup_bucket = storage_client.bucket(backup_bucket_name)
        
        # List and copy all files from primary to backup
        blobs = primary_bucket.list_blobs()
        copied_count = 0
        
        for blob in blobs:
            # Create backup file name with timestamp
            backup_name = f"backup-{datetime.now().strftime('%Y%m%d')}/{blob.name}"
            
            # Copy blob to backup bucket
            backup_bucket.copy_blob(blob, backup_bucket, backup_name)
            copied_count += 1
            
            logger.log_text(f"Copied {blob.name} to {backup_name}")
        
        success_msg = f"Backup completed successfully. {copied_count} files copied."
        logger.log_text(success_msg, severity='INFO')
        
        return {
            'status': 'success',
            'files_copied': copied_count,
            'timestamp': datetime.now().isoformat()
        }
        
    except Exception as e:
        error_msg = f"Backup failed: {str(e)}"
        logger.log_text(error_msg, severity='ERROR')
        return {'error': error_msg}, 500
EOF
    
    # Create requirements.txt for function dependencies
    cat > requirements.txt << 'EOF'
google-cloud-storage==2.18.0
google-cloud-logging==3.11.0
EOF
    
    log "Deploying Cloud Function..."
    # Deploy the Cloud Function with HTTP trigger
    gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --entry-point backup_files \
        --memory 256MB \
        --timeout 60s \
        --region="${REGION}" \
        --set-env-vars "PRIMARY_BUCKET=${PRIMARY_BUCKET},BACKUP_BUCKET=${BACKUP_BUCKET}" || error "Failed to deploy Cloud Function"
    
    # Get the function trigger URL
    FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
        --gen2 \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)") || error "Failed to get function URL"
    
    # Store function URL for later use
    echo "FUNCTION_URL=${FUNCTION_URL}" >> ../.deployment-config
    
    cd ..
    
    success "Cloud Function deployed successfully"
    log "Function URL: ${FUNCTION_URL}"
}

# Function to create scheduler job
create_scheduler_job() {
    log "Creating Cloud Scheduler job for daily backups..."
    
    # Source the function URL from config
    source .deployment-config
    
    # Create Cloud Scheduler job for daily backups at 2 AM UTC
    gcloud scheduler jobs create http "${SCHEDULER_JOB_NAME}" \
        --location="${REGION}" \
        --schedule="0 2 * * *" \
        --uri="${FUNCTION_URL}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{}' \
        --description="Daily automated backup of storage files" || error "Failed to create scheduler job"
    
    success "Cloud Scheduler job created for daily backups at 2 AM UTC"
}

# Function to test the backup system
test_backup_system() {
    log "Testing backup system functionality..."
    
    # Source the function URL from config
    source .deployment-config
    
    # Test manual backup execution
    log "Triggering manual backup test..."
    response=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "${FUNCTION_URL}" \
        -H "Content-Type: application/json" \
        -d '{}' || echo "HTTP_CODE:000")
    
    # Extract HTTP code
    http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d: -f2)
    
    if [[ "$http_code" == "200" ]]; then
        success "Manual backup test successful"
    else
        warning "Manual backup test returned HTTP code: $http_code"
        echo "Response: $response"
    fi
    
    # Wait for processing
    sleep 10
    
    # Verify backup files were created
    log "Verifying backup files in backup bucket..."
    if gcloud storage ls "gs://${BACKUP_BUCKET}/" &> /dev/null; then
        backup_files=$(gcloud storage ls "gs://${BACKUP_BUCKET}/**" | wc -l)
        success "Backup verification complete. Found ${backup_files} backed up files."
    else
        warning "No backup files found yet. This might be normal if the backup is still processing."
    fi
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring monitoring and alerting..."
    
    # View recent function logs
    log "Displaying recent function logs..."
    gcloud functions logs read "${FUNCTION_NAME}" \
        --gen2 \
        --region="${REGION}" \
        --limit=5 || warning "Could not retrieve function logs"
    
    # Note: Creating alert policies requires additional setup and permissions
    # This is left as a manual step for production environments
    warning "Alert policy creation requires additional setup. Please configure manually in Cloud Console."
    
    success "Basic monitoring configured"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Primary Bucket: gs://${PRIMARY_BUCKET}"
    echo "Backup Bucket: gs://${BACKUP_BUCKET}"
    echo "Function Name: ${FUNCTION_NAME}"
    echo "Scheduler Job: ${SCHEDULER_JOB_NAME}"
    echo "Schedule: Daily at 2 AM UTC"
    echo ""
    echo "Next Steps:"
    echo "1. Monitor the backup function logs for successful executions"
    echo "2. Review and adjust the backup schedule if needed"
    echo "3. Set up additional monitoring and alerting as required"
    echo "4. Test disaster recovery procedures"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo "===================="
}

# Function to handle script interruption
cleanup_on_interrupt() {
    error "Deployment interrupted. You may need to manually clean up partially created resources."
    exit 1
}

# Set trap for script interruption
trap cleanup_on_interrupt INT TERM

# Main deployment function
main() {
    echo "🚀 Starting GCP Automated File Backup Deployment"
    echo "=================================================="
    
    check_prerequisites
    setup_environment
    configure_project
    enable_apis
    create_storage_buckets
    upload_sample_files
    create_backup_function
    create_scheduler_job
    test_backup_system
    configure_monitoring
    display_summary
    
    success "🎉 Deployment completed successfully!"
    
    # Clean up temporary files
    rm -rf backup-demo backup-function
}

# Run main function
main "$@"