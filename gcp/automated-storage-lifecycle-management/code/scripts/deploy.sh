#!/bin/bash

# Deploy script for Automated Storage Lifecycle Management with Cloud Storage
# This script implements automated storage lifecycle policies and scheduled cleanup jobs

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | grep -q "."; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if billing is enabled (if project is set)
    if [[ -n "${PROJECT_ID:-}" ]]; then
        if ! gcloud beta billing projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
            log_warning "Unable to verify billing status for project ${PROJECT_ID}"
        fi
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-lifecycle-demo-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    fi
    export RANDOM_SUFFIX
    
    export BUCKET_NAME="${BUCKET_NAME:-storage-lifecycle-demo-${RANDOM_SUFFIX}}"
    export JOB_NAME="${JOB_NAME:-lifecycle-cleanup-job-${RANDOM_SUFFIX}}"
    
    log_info "Environment variables configured:"
    log_info "  PROJECT_ID: ${PROJECT_ID}"
    log_info "  REGION: ${REGION}"
    log_info "  BUCKET_NAME: ${BUCKET_NAME}"
    log_info "  JOB_NAME: ${JOB_NAME}"
}

# Function to create or set project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log_info "Project ${PROJECT_ID} already exists"
    else
        log_info "Creating new project: ${PROJECT_ID}"
        if ! gcloud projects create "${PROJECT_ID}" --name="Storage Lifecycle Demo"; then
            log_error "Failed to create project ${PROJECT_ID}"
            exit 1
        fi
        log_success "Project created successfully"
    fi
    
    # Set current project
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Project configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "storage.googleapis.com"
        "cloudscheduler.googleapis.com"
        "cloudfunctions.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}"; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
}

# Function to create storage bucket with lifecycle configuration
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket with lifecycle configuration..."
    
    # Check if bucket already exists
    if gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "Bucket gs://${BUCKET_NAME} already exists, skipping creation"
    else
        # Create the storage bucket
        if gcloud storage buckets create "gs://${BUCKET_NAME}" \
            --location="${REGION}" \
            --default-storage-class=STANDARD \
            --uniform-bucket-level-access; then
            log_success "Storage bucket created: gs://${BUCKET_NAME}"
        else
            log_error "Failed to create storage bucket"
            exit 1
        fi
    fi
}

# Function to configure lifecycle policies
configure_lifecycle_policies() {
    log_info "Configuring automated lifecycle policy rules..."
    
    # Create lifecycle configuration file
    cat > lifecycle-config.json << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {
          "type": "SetStorageClass",
          "storageClass": "NEARLINE"
        },
        "condition": {
          "age": 30,
          "matchesStorageClass": ["STANDARD"]
        }
      },
      {
        "action": {
          "type": "SetStorageClass", 
          "storageClass": "COLDLINE"
        },
        "condition": {
          "age": 90,
          "matchesStorageClass": ["NEARLINE"]
        }
      },
      {
        "action": {
          "type": "SetStorageClass",
          "storageClass": "ARCHIVE"
        },
        "condition": {
          "age": 365,
          "matchesStorageClass": ["COLDLINE"]
        }
      },
      {
        "action": {
          "type": "Delete"
        },
        "condition": {
          "age": 2555
        }
      }
    ]
  }
}
EOF
    
    # Apply lifecycle configuration to bucket
    if gcloud storage buckets update "gs://${BUCKET_NAME}" \
        --lifecycle-file=lifecycle-config.json; then
        log_success "Lifecycle policies configured for automated storage transitions"
    else
        log_error "Failed to configure lifecycle policies"
        exit 1
    fi
    
    # Clean up temporary file
    rm -f lifecycle-config.json
}

# Function to upload sample data
upload_sample_data() {
    log_info "Uploading sample data with different ages..."
    
    # Create sample files with different content types
    echo "Critical business data - frequent access" > critical-data.txt
    echo "Monthly reports - moderate access" > monthly-report.txt  
    echo "Archived logs - rare access" > archived-logs.txt
    echo "Backup files - emergency access only" > backup-data.txt
    
    # Upload files to Cloud Storage
    local files=("critical-data.txt" "monthly-report.txt" "archived-logs.txt" "backup-data.txt")
    
    for file in "${files[@]}"; do
        if gcloud storage cp "${file}" "gs://${BUCKET_NAME}/"; then
            log_success "Uploaded ${file}"
        else
            log_error "Failed to upload ${file}"
            exit 1
        fi
    done
    
    # Set custom timestamps to simulate aged data (optional - for testing)
    if gcloud storage objects update "gs://${BUCKET_NAME}/archived-logs.txt" \
        --custom-time="2024-01-01T00:00:00Z" 2>/dev/null; then
        log_success "Set custom timestamp for archived-logs.txt"
    else
        log_warning "Could not set custom timestamp (feature may not be available)"
    fi
    
    # Clean up local files
    rm -f critical-data.txt monthly-report.txt archived-logs.txt backup-data.txt
    
    log_success "Sample data uploaded with varying access patterns"
}

# Function to create Cloud Scheduler job
create_scheduler_job() {
    log_info "Creating Cloud Scheduler job for additional automation..."
    
    # Create App Engine application (required for Cloud Scheduler)
    if ! gcloud app describe >/dev/null 2>&1; then
        log_info "Creating App Engine application..."
        if gcloud app create --region="${REGION}" --quiet; then
            log_success "App Engine application created"
        else
            log_warning "Failed to create App Engine application, continuing anyway"
        fi
    else
        log_info "App Engine application already exists"
    fi
    
    # Check if scheduler job already exists
    if gcloud scheduler jobs describe "${JOB_NAME}" --location="${REGION}" >/dev/null 2>&1; then
        log_warning "Scheduler job ${JOB_NAME} already exists, skipping creation"
    else
        # Create a simple HTTP endpoint for lifecycle reporting 
        local webhook_url="https://httpbin.org/post"
        
        # Create scheduled job for weekly lifecycle reporting
        if gcloud scheduler jobs create http "${JOB_NAME}" \
            --location="${REGION}" \
            --schedule="0 9 * * 1" \
            --uri="${webhook_url}" \
            --http-method=POST \
            --message-body="{\"bucket\":\"${BUCKET_NAME}\",\"action\":\"lifecycle_report\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" \
            --headers="Content-Type=application/json"; then
            log_success "Cloud Scheduler job created for weekly lifecycle reporting"
        else
            log_error "Failed to create Cloud Scheduler job"
            exit 1
        fi
    fi
}

# Function to configure monitoring and alerting
configure_monitoring() {
    log_info "Configuring monitoring and alerting..."
    
    # Create a dedicated Cloud Storage bucket for logs
    local logs_bucket="${BUCKET_NAME}-logs"
    
    if gcloud storage buckets describe "gs://${logs_bucket}" >/dev/null 2>&1; then
        log_warning "Logs bucket gs://${logs_bucket} already exists, skipping creation"
    else
        if gcloud storage buckets create "gs://${logs_bucket}" \
            --location="${REGION}" \
            --uniform-bucket-level-access; then
            log_success "Logs bucket created: gs://${logs_bucket}"
        else
            log_error "Failed to create logs bucket"
            exit 1
        fi
    fi
    
    # Create logging sink for storage lifecycle events
    local sink_name="storage-lifecycle-sink"
    
    if gcloud logging sinks describe "${sink_name}" >/dev/null 2>&1; then
        log_warning "Logging sink ${sink_name} already exists, skipping creation"
    else
        if gcloud logging sinks create "${sink_name}" \
            "gs://${logs_bucket}" \
            --log-filter="resource.type=\"gcs_bucket\" AND resource.labels.bucket_name=\"${BUCKET_NAME}\""; then
            log_success "Logging sink created for lifecycle policy tracking"
        else
            log_error "Failed to create logging sink"
            exit 1
        fi
    fi
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check bucket configuration
    if gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_success "✓ Storage bucket is accessible"
    else
        log_error "✗ Storage bucket is not accessible"
        return 1
    fi
    
    # Check lifecycle configuration
    if gcloud storage buckets describe "gs://${BUCKET_NAME}" --format="json(lifecycle)" | grep -q "lifecycle"; then
        log_success "✓ Lifecycle policies are configured"
    else
        log_error "✗ Lifecycle policies are not configured"
        return 1
    fi
    
    # Check scheduler job
    if gcloud scheduler jobs describe "${JOB_NAME}" --location="${REGION}" >/dev/null 2>&1; then
        log_success "✓ Scheduler job is created"
    else
        log_error "✗ Scheduler job is not created"
        return 1
    fi
    
    # List current objects and their storage classes
    log_info "Current objects in bucket:"
    gcloud storage ls -L "gs://${BUCKET_NAME}/" \
        --format="table(name,storageClass,timeCreated,size)" 2>/dev/null || true
    
    log_success "Deployment validation completed"
}

# Function to display deployment information
display_deployment_info() {
    log_info "=== Deployment Summary ==="
    echo
    log_info "Resources Created:"
    log_info "  • Storage Bucket: gs://${BUCKET_NAME}"
    log_info "  • Logs Bucket: gs://${BUCKET_NAME}-logs"
    log_info "  • Scheduler Job: ${JOB_NAME}"
    log_info "  • Logging Sink: storage-lifecycle-sink"
    echo
    log_info "Lifecycle Policy:"
    log_info "  • Standard → Nearline: 30 days"
    log_info "  • Nearline → Coldline: 90 days"
    log_info "  • Coldline → Archive: 365 days"
    log_info "  • Delete: 2555 days (7 years)"
    echo
    log_info "Monitoring:"
    log_info "  • View logs: https://console.cloud.google.com/logs/viewer"
    log_info "  • Configure alerts: https://console.cloud.google.com/monitoring"
    echo
    log_info "Next Steps:"
    log_info "  1. Objects will automatically transition based on age"
    log_info "  2. Monitor cost savings in billing console"
    log_info "  3. Customize lifecycle rules as needed"
    log_info "  4. Set up additional monitoring and alerting"
    echo
    log_success "Automated Storage Lifecycle Management deployment completed successfully!"
}

# Main deployment function
main() {
    echo "=== Automated Storage Lifecycle Management Deployment ==="
    echo
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_storage_bucket
    configure_lifecycle_policies
    upload_sample_data
    create_scheduler_job
    configure_monitoring
    validate_deployment
    display_deployment_info
    
    log_success "Deployment completed successfully!"
    
    # Save deployment state for cleanup script
    cat > .deployment_state << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
BUCKET_NAME=${BUCKET_NAME}
JOB_NAME=${JOB_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DEPLOYMENT_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
    
    log_info "Deployment state saved to .deployment_state"
}

# Handle script interruption
cleanup_on_error() {
    log_error "Deployment interrupted. Cleaning up temporary files..."
    rm -f lifecycle-config.json critical-data.txt monthly-report.txt archived-logs.txt backup-data.txt
    exit 1
}

# Set trap for cleanup on script interruption
trap cleanup_on_error INT TERM

# Run main function
main "$@"