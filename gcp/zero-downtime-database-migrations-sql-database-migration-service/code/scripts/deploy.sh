#!/bin/bash

# Zero-Downtime Database Migration Deployment Script for GCP
# Description: Deploys Database Migration Service infrastructure for MySQL to Cloud SQL migration
# Prerequisites: gcloud CLI configured, appropriate IAM permissions

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message function
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Warning message function
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Info message function
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Zero-Downtime Database Migration infrastructure on GCP

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be deployed without making changes
    -r, --region REGION    GCP region (default: us-central1)
    -p, --project PROJECT  GCP project ID (uses current gcloud config if not specified)
    --source-host HOST     Source MySQL host (required for actual migration)
    --source-user USER     Source MySQL username (default: migration_user)
    --source-password PASS Source MySQL password (default: SecurePassword123!)
    --db-name NAME         Database name (default: production_db)

EXAMPLES:
    $0 --dry-run
    $0 --region us-west1 --project my-project
    $0 --source-host 10.1.1.100 --source-user admin --source-password mypass

EOF
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk"
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "gcloud is not authenticated. Please run 'gcloud auth login'"
    fi
    
    # Check if a project is configured
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            error_exit "No GCP project configured. Use --project flag or run 'gcloud config set project PROJECT_ID'"
        fi
    fi
    
    # Verify project exists and user has access
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        error_exit "Cannot access project '${PROJECT_ID}'. Check project ID and permissions."
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
set_environment_variables() {
    info "Setting up environment variables..."
    
    # Project and region configuration
    export PROJECT_ID="${PROJECT_ID}"
    export REGION="${REGION}"
    export ZONE="${REGION}-a"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export MIGRATION_JOB_ID="mysql-migration-${RANDOM_SUFFIX}"
    export SOURCE_PROFILE_ID="source-mysql-${RANDOM_SUFFIX}"
    export CLOUDSQL_INSTANCE_ID="target-mysql-${RANDOM_SUFFIX}"
    
    # Database configuration
    export DB_NAME="${DB_NAME}"
    export DB_USER="${DB_USER}"
    export DB_PASSWORD="${DB_PASSWORD}"
    export SOURCE_HOST="${SOURCE_HOST:-}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
    gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
    gcloud config set compute/zone "${ZONE}" || error_exit "Failed to set zone"
    
    success "Environment variables configured"
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Migration Job ID: ${MIGRATION_JOB_ID}"
    log "Cloud SQL Instance ID: ${CLOUDSQL_INSTANCE_ID}"
}

# Enable required APIs
enable_apis() {
    info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "datamigration.googleapis.com"
        "sqladmin.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "compute.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            info "[DRY RUN] Would enable API: ${api}"
        else
            info "Enabling API: ${api}"
            if ! gcloud services enable "${api}"; then
                error_exit "Failed to enable API: ${api}"
            fi
        fi
    done
    
    # Wait for APIs to be fully enabled
    if [[ "${DRY_RUN}" != "true" ]]; then
        info "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    success "APIs enabled successfully"
}

# Create source connection profile
create_source_connection_profile() {
    info "Creating source database connection profile..."
    
    if [[ -z "${SOURCE_HOST}" ]]; then
        warning "Source host not provided. Creating placeholder connection profile."
        warning "You'll need to update this manually before starting migration."
        SOURCE_HOST="YOUR_MYSQL_HOST"
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create connection profile: ${SOURCE_PROFILE_ID}"
        info "[DRY RUN] Source host: ${SOURCE_HOST}"
        info "[DRY RUN] Source user: ${DB_USER}"
        return
    fi
    
    # Check if connection profile already exists
    if gcloud datamigration connection-profiles describe "${SOURCE_PROFILE_ID}" \
        --region="${REGION}" &>/dev/null; then
        warning "Connection profile ${SOURCE_PROFILE_ID} already exists. Skipping creation."
        return
    fi
    
    # Create connection profile for source MySQL database
    if ! gcloud datamigration connection-profiles create mysql \
        "${SOURCE_PROFILE_ID}" \
        --region="${REGION}" \
        --host="${SOURCE_HOST}" \
        --port=3306 \
        --username="${DB_USER}" \
        --password="${DB_PASSWORD}" \
        --display-name="Source MySQL Database"; then
        error_exit "Failed to create source connection profile"
    fi
    
    success "Source connection profile created: ${SOURCE_PROFILE_ID}"
}

# Create Cloud SQL instance
create_cloudsql_instance() {
    info "Creating Cloud SQL for MySQL instance..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create Cloud SQL instance: ${CLOUDSQL_INSTANCE_ID}"
        info "[DRY RUN] Instance configuration: MySQL 8.0, db-n1-standard-2, 100GB SSD"
        return
    fi
    
    # Check if Cloud SQL instance already exists
    if gcloud sql instances describe "${CLOUDSQL_INSTANCE_ID}" &>/dev/null; then
        warning "Cloud SQL instance ${CLOUDSQL_INSTANCE_ID} already exists. Skipping creation."
        return
    fi
    
    # Create Cloud SQL for MySQL instance
    info "Creating Cloud SQL instance (this may take several minutes)..."
    if ! gcloud sql instances create "${CLOUDSQL_INSTANCE_ID}" \
        --database-version=MYSQL_8_0 \
        --tier=db-n1-standard-2 \
        --region="${REGION}" \
        --storage-type=SSD \
        --storage-size=100GB \
        --storage-auto-increase \
        --backup-start-time=03:00 \
        --enable-bin-log \
        --maintenance-window-day=SUN \
        --maintenance-window-hour=04 \
        --maintenance-release-channel=production; then
        error_exit "Failed to create Cloud SQL instance"
    fi
    
    # Wait for instance to be ready
    info "Waiting for Cloud SQL instance to be ready..."
    local timeout=300  # 5 minutes
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        local state=$(gcloud sql instances describe "${CLOUDSQL_INSTANCE_ID}" \
            --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        if [[ "$state" == "RUNNABLE" ]]; then
            break
        fi
        
        info "Instance state: $state (waiting...)"
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        error_exit "Timeout waiting for Cloud SQL instance to be ready"
    fi
    
    # Set root password for Cloud SQL instance
    info "Setting root password..."
    if ! gcloud sql users set-password root \
        --host=% \
        --instance="${CLOUDSQL_INSTANCE_ID}" \
        --password="${DB_PASSWORD}"; then
        error_exit "Failed to set root password"
    fi
    
    # Create migration user with appropriate permissions
    info "Creating migration user..."
    if ! gcloud sql users create "${DB_USER}" \
        --instance="${CLOUDSQL_INSTANCE_ID}" \
        --password="${DB_PASSWORD}" \
        --host=%; then
        error_exit "Failed to create migration user"
    fi
    
    success "Cloud SQL instance created and configured: ${CLOUDSQL_INSTANCE_ID}"
}

# Create migration job
create_migration_job() {
    info "Creating Database Migration Service job..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create migration job: ${MIGRATION_JOB_ID}"
        info "[DRY RUN] Source: ${SOURCE_PROFILE_ID}"
        info "[DRY RUN] Destination: ${CLOUDSQL_INSTANCE_ID}"
        return
    fi
    
    # Check if migration job already exists
    if gcloud datamigration migration-jobs describe "${MIGRATION_JOB_ID}" \
        --region="${REGION}" &>/dev/null; then
        warning "Migration job ${MIGRATION_JOB_ID} already exists. Skipping creation."
        return
    fi
    
    # Create storage bucket for migration dumps if it doesn't exist
    local bucket_name="${PROJECT_ID}-migration-dump"
    if ! gsutil ls "gs://${bucket_name}" &>/dev/null; then
        info "Creating storage bucket for migration dumps..."
        if ! gsutil mb -l "${REGION}" "gs://${bucket_name}"; then
            error_exit "Failed to create storage bucket"
        fi
    fi
    
    # Create migration job for MySQL to Cloud SQL
    if ! gcloud datamigration migration-jobs create "${MIGRATION_JOB_ID}" \
        --region="${REGION}" \
        --type=CONTINUOUS \
        --source="${SOURCE_PROFILE_ID}" \
        --destination-instance="${CLOUDSQL_INSTANCE_ID}" \
        --display-name="Production MySQL Migration" \
        --dump-path="gs://${bucket_name}" \
        --vpc-peering-connectivity; then
        error_exit "Failed to create migration job"
    fi
    
    success "Migration job created: ${MIGRATION_JOB_ID}"
}

# Setup monitoring and alerting
setup_monitoring() {
    info "Setting up monitoring and alerting..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create log-based metrics and alert policies"
        return
    fi
    
    # Create log-based metric for migration errors
    info "Creating log-based metric for migration errors..."
    if ! gcloud logging metrics create migration_errors \
        --description="Count of migration errors" \
        --log-filter='resource.type="gce_instance" AND jsonPayload.message:"ERROR"' \
        --value-extractor='EXTRACT(jsonPayload.error_count)' 2>/dev/null; then
        warning "Failed to create log-based metric (may already exist)"
    fi
    
    # Create alert policy configuration
    cat > "${SCRIPT_DIR}/alert-policy.json" << EOF
{
  "displayName": "Database Migration Alert",
  "conditions": [
    {
      "displayName": "Migration job failure",
      "conditionThreshold": {
        "filter": "resource.type=\\\"datamigration.googleapis.com/MigrationJob\\\"",
        "comparison": "COMPARISON_EQUAL",
        "thresholdValue": 1,
        "duration": "60s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ]
      }
    }
  ],
  "notificationChannels": [],
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF
    
    # Create alert policy
    info "Creating alert policy..."
    if ! gcloud alpha monitoring policies create --policy-from-file="${SCRIPT_DIR}/alert-policy.json"; then
        warning "Failed to create alert policy (alpha command may not be available)"
    fi
    
    success "Monitoring and alerting configured"
}

# Create validation script
create_validation_script() {
    info "Creating data validation script..."
    
    cat > "${SCRIPT_DIR}/validate_migration.sql" << EOF
-- Compare row counts between source and target
SELECT 'users' as table_name, COUNT(*) as row_count FROM users
UNION ALL
SELECT 'orders' as table_name, COUNT(*) as row_count FROM orders
UNION ALL
SELECT 'products' as table_name, COUNT(*) as row_count FROM products;

-- Validate data checksums for critical tables
SELECT table_name, 
       CHECKSUM TABLE table_name as checksum
FROM information_schema.tables 
WHERE table_schema = '${DB_NAME}';
EOF
    
    success "Validation script created: ${SCRIPT_DIR}/validate_migration.sql"
}

# Display deployment summary
display_summary() {
    info "Deployment Summary"
    echo "===================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Migration Job ID: ${MIGRATION_JOB_ID}"
    echo "Source Profile ID: ${SOURCE_PROFILE_ID}"
    echo "Cloud SQL Instance ID: ${CLOUDSQL_INSTANCE_ID}"
    echo "Database Name: ${DB_NAME}"
    echo "Database User: ${DB_USER}"
    
    if [[ -n "${SOURCE_HOST}" && "${SOURCE_HOST}" != "YOUR_MYSQL_HOST" ]]; then
        echo "Source Host: ${SOURCE_HOST}"
    else
        echo ""
        warning "Source host not configured. Update connection profile before starting migration:"
        echo "gcloud datamigration connection-profiles update mysql ${SOURCE_PROFILE_ID} \\"
        echo "    --region=${REGION} --host=YOUR_ACTUAL_MYSQL_HOST"
    fi
    
    echo ""
    info "Next Steps:"
    echo "1. Configure source MySQL database with binary logging enabled"
    echo "2. Update source connection profile with actual MySQL host if needed"
    echo "3. Start the migration job:"
    echo "   gcloud datamigration migration-jobs start ${MIGRATION_JOB_ID} --region=${REGION}"
    echo "4. Monitor migration progress in the Google Cloud Console"
    echo "5. Perform data validation using ${SCRIPT_DIR}/validate_migration.sql"
    echo "6. Execute production cutover when ready"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo ""
        warning "This was a dry run. No resources were actually created."
        echo "Run without --dry-run to deploy the infrastructure."
    fi
}

# Main deployment function
main() {
    # Initialize log file
    echo "Starting deployment at $(date)" > "${LOG_FILE}"
    
    info "Starting Zero-Downtime Database Migration deployment"
    
    check_prerequisites
    set_environment_variables
    enable_apis
    create_source_connection_profile
    create_cloudsql_instance
    create_migration_job
    setup_monitoring
    create_validation_script
    
    success "Deployment completed successfully!"
    display_summary
}

# Parse command line arguments
REGION="us-central1"
DB_NAME="production_db"
DB_USER="migration_user"
DB_PASSWORD="SecurePassword123!"
SOURCE_HOST=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -p|--project)
            PROJECT_ID="$2"
            shift 2
            ;;
        --source-host)
            SOURCE_HOST="$2"
            shift 2
            ;;
        --source-user)
            DB_USER="$2"
            shift 2
            ;;
        --source-password)
            DB_PASSWORD="$2"
            shift 2
            ;;
        --db-name)
            DB_NAME="$2"
            shift 2
            ;;
        *)
            error_exit "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Execute main function
main

exit 0