#!/bin/bash

# Destroy script for Secure Database Modernization Workflows with Cloud Workstations and Database Migration Service
# This script safely removes all infrastructure components created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "gcloud is not authenticated. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Use existing environment variables or prompt for required ones
    if [ -z "$PROJECT_ID" ]; then
        read -p "Enter Project ID: " PROJECT_ID
        export PROJECT_ID
    fi
    
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export WORKSTATION_CLUSTER_NAME="${WORKSTATION_CLUSTER_NAME:-db-migration-cluster}"
    export WORKSTATION_CONFIG_NAME="${WORKSTATION_CONFIG_NAME:-db-migration-config}"
    
    # Set default values for resource names if not provided
    export DB_MIGRATION_JOB_NAME="${DB_MIGRATION_JOB_NAME:-migration-job}"
    export SECRET_NAME="${SECRET_NAME:-db-credentials}"
    
    # Get project number for service account references
    export PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)" 2>/dev/null || echo "")
    
    log "Environment variables set:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  ZONE: ${ZONE}"
    log "  WORKSTATION_CLUSTER_NAME: ${WORKSTATION_CLUSTER_NAME}"
    log "  WORKSTATION_CONFIG_NAME: ${WORKSTATION_CONFIG_NAME}"
}

# Function to configure gcloud
configure_gcloud() {
    log "Configuring gcloud settings..."
    
    # Set default project and region
    gcloud config set project ${PROJECT_ID}
    gcloud config set compute/region ${REGION}
    gcloud config set compute/zone ${ZONE}
    
    log "gcloud configuration completed"
}

# Function to confirm destruction
confirm_destruction() {
    echo -e "${RED}WARNING: This will destroy all resources created by the deployment script.${NC}"
    echo -e "${RED}This action cannot be undone.${NC}"
    echo
    echo "Resources to be destroyed:"
    echo "  - Cloud Workstations cluster and instances"
    echo "  - Database Migration Service connection profiles"
    echo "  - Cloud SQL instances"
    echo "  - Artifact Registry repositories"
    echo "  - Secret Manager secrets"
    echo "  - Custom IAM roles"
    echo
    
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed, proceeding..."
}

# Function to stop and delete workstation instances
destroy_workstation_instances() {
    log "Destroying workstation instances..."
    
    # List all workstation instances in the cluster
    local instances=$(gcloud workstations list \
        --location=${REGION} \
        --cluster=${WORKSTATION_CLUSTER_NAME} \
        --config=${WORKSTATION_CONFIG_NAME} \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$instances" ]; then
        for instance in $instances; do
            log "Stopping workstation instance: $instance"
            gcloud workstations stop "$instance" \
                --location=${REGION} \
                --cluster=${WORKSTATION_CLUSTER_NAME} \
                --config=${WORKSTATION_CONFIG_NAME} \
                --quiet || warn "Failed to stop workstation instance: $instance"
            
            log "Deleting workstation instance: $instance"
            gcloud workstations delete "$instance" \
                --location=${REGION} \
                --cluster=${WORKSTATION_CLUSTER_NAME} \
                --config=${WORKSTATION_CONFIG_NAME} \
                --quiet || warn "Failed to delete workstation instance: $instance"
        done
    else
        log "No workstation instances found to delete"
    fi
    
    log "Workstation instances destruction completed"
}

# Function to delete workstation configuration
destroy_workstation_config() {
    log "Destroying workstation configuration..."
    
    # Check if configuration exists
    if gcloud workstations configs describe ${WORKSTATION_CONFIG_NAME} \
        --location=${REGION} \
        --cluster=${WORKSTATION_CLUSTER_NAME} &> /dev/null; then
        
        gcloud workstations configs delete ${WORKSTATION_CONFIG_NAME} \
            --location=${REGION} \
            --cluster=${WORKSTATION_CLUSTER_NAME} \
            --quiet || warn "Failed to delete workstation configuration"
        
        log "Workstation configuration deleted successfully"
    else
        log "Workstation configuration not found, skipping deletion"
    fi
}

# Function to delete workstation cluster
destroy_workstation_cluster() {
    log "Destroying workstation cluster..."
    
    # Check if cluster exists
    if gcloud workstations clusters describe ${WORKSTATION_CLUSTER_NAME} \
        --location=${REGION} &> /dev/null; then
        
        gcloud workstations clusters delete ${WORKSTATION_CLUSTER_NAME} \
            --location=${REGION} \
            --quiet || warn "Failed to delete workstation cluster"
        
        log "Waiting for workstation cluster deletion to complete..."
        
        # Wait for cluster deletion
        local max_attempts=60
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            if ! gcloud workstations clusters describe ${WORKSTATION_CLUSTER_NAME} \
                --location=${REGION} &> /dev/null; then
                log "Workstation cluster deleted successfully"
                break
            fi
            
            attempt=$((attempt + 1))
            sleep 30
        done
        
        if [ $attempt -eq $max_attempts ]; then
            warn "Timeout waiting for workstation cluster deletion"
        fi
    else
        log "Workstation cluster not found, skipping deletion"
    fi
}

# Function to delete database migration resources
destroy_migration_resources() {
    log "Destroying database migration resources..."
    
    # Delete migration jobs first
    local migration_jobs=$(gcloud database-migration migration-jobs list \
        --location=${REGION} \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$migration_jobs" ]; then
        for job in $migration_jobs; do
            log "Deleting migration job: $job"
            gcloud database-migration migration-jobs delete "$job" \
                --location=${REGION} \
                --quiet || warn "Failed to delete migration job: $job"
        done
    fi
    
    # Delete connection profiles
    local profiles=("source-db-profile" "target-db-profile")
    
    for profile in "${profiles[@]}"; do
        if gcloud database-migration connection-profiles describe "$profile" \
            --location=${REGION} &> /dev/null; then
            
            log "Deleting connection profile: $profile"
            gcloud database-migration connection-profiles delete "$profile" \
                --location=${REGION} \
                --quiet || warn "Failed to delete connection profile: $profile"
        else
            log "Connection profile '$profile' not found, skipping deletion"
        fi
    done
    
    log "Database migration resources destruction completed"
}

# Function to delete Cloud SQL instances
destroy_cloud_sql_instances() {
    log "Destroying Cloud SQL instances..."
    
    # Check if target MySQL instance exists
    if gcloud sql instances describe target-mysql-instance &> /dev/null; then
        log "Deleting Cloud SQL instance: target-mysql-instance"
        gcloud sql instances delete target-mysql-instance \
            --quiet || warn "Failed to delete Cloud SQL instance"
        
        log "Waiting for Cloud SQL instance deletion to complete..."
        
        # Wait for instance deletion
        local max_attempts=60
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            if ! gcloud sql instances describe target-mysql-instance &> /dev/null; then
                log "Cloud SQL instance deleted successfully"
                break
            fi
            
            attempt=$((attempt + 1))
            sleep 30
        done
        
        if [ $attempt -eq $max_attempts ]; then
            warn "Timeout waiting for Cloud SQL instance deletion"
        fi
    else
        log "Cloud SQL instance not found, skipping deletion"
    fi
}

# Function to delete Artifact Registry repositories
destroy_artifact_registry() {
    log "Destroying Artifact Registry repositories..."
    
    # Check if repository exists
    if gcloud artifacts repositories describe db-migration-images \
        --location=${REGION} &> /dev/null; then
        
        log "Deleting Artifact Registry repository: db-migration-images"
        gcloud artifacts repositories delete db-migration-images \
            --location=${REGION} \
            --quiet || warn "Failed to delete Artifact Registry repository"
        
        log "Artifact Registry repository deleted successfully"
    else
        log "Artifact Registry repository not found, skipping deletion"
    fi
}

# Function to delete Secret Manager secrets
destroy_secrets() {
    log "Destroying Secret Manager secrets..."
    
    # Find all secrets that might have been created
    local secrets=$(gcloud secrets list --format="value(name)" | grep -E "db-credentials|${SECRET_NAME}" 2>/dev/null || echo "")
    
    if [ -n "$secrets" ]; then
        for secret in $secrets; do
            log "Deleting secret: $secret"
            gcloud secrets delete "$secret" \
                --quiet || warn "Failed to delete secret: $secret"
        done
    else
        log "No secrets found to delete"
    fi
    
    log "Secret Manager secrets destruction completed"
}

# Function to delete custom IAM roles
destroy_custom_iam_roles() {
    log "Destroying custom IAM roles..."
    
    # Check if custom IAM role exists
    if gcloud iam roles describe databaseMigrationDeveloper \
        --project=${PROJECT_ID} &> /dev/null; then
        
        log "Deleting custom IAM role: databaseMigrationDeveloper"
        gcloud iam roles delete databaseMigrationDeveloper \
            --project=${PROJECT_ID} \
            --quiet || warn "Failed to delete custom IAM role"
        
        log "Custom IAM role deleted successfully"
    else
        log "Custom IAM role not found, skipping deletion"
    fi
}

# Function to clean up Cloud Build artifacts
cleanup_cloud_build() {
    log "Cleaning up Cloud Build artifacts..."
    
    # Delete recent builds related to this project
    local builds=$(gcloud builds list --limit=10 --format="value(id)" 2>/dev/null || echo "")
    
    if [ -n "$builds" ]; then
        for build in $builds; do
            log "Cancelling build if still running: $build"
            gcloud builds cancel "$build" &> /dev/null || true
        done
    fi
    
    log "Cloud Build cleanup completed"
}

# Function to clean up environment variables
cleanup_environment() {
    log "Cleaning up environment variables..."
    
    unset PROJECT_ID REGION ZONE WORKSTATION_CLUSTER_NAME WORKSTATION_CONFIG_NAME
    unset DB_MIGRATION_JOB_NAME SECRET_NAME PROJECT_NUMBER
    
    log "Environment variables cleaned up"
}

# Function to display destruction summary
display_summary() {
    log "Destruction completed!"
    echo
    echo -e "${BLUE}=== Destruction Summary ===${NC}"
    echo -e "${GREEN}✅ Workstation instances stopped and deleted${NC}"
    echo -e "${GREEN}✅ Workstation configuration deleted${NC}"
    echo -e "${GREEN}✅ Workstation cluster deleted${NC}"
    echo -e "${GREEN}✅ Database migration resources deleted${NC}"
    echo -e "${GREEN}✅ Cloud SQL instances deleted${NC}"
    echo -e "${GREEN}✅ Artifact Registry repositories deleted${NC}"
    echo -e "${GREEN}✅ Secret Manager secrets deleted${NC}"
    echo -e "${GREEN}✅ Custom IAM roles deleted${NC}"
    echo -e "${GREEN}✅ Cloud Build artifacts cleaned up${NC}"
    echo -e "${GREEN}✅ Environment variables cleaned up${NC}"
    echo
    echo -e "${BLUE}=== Post-Destruction Notes ===${NC}"
    echo "1. Verify all resources have been deleted in the Google Cloud Console"
    echo "2. Check for any remaining resources that might incur charges"
    echo "3. Review Cloud Billing for any ongoing charges"
    echo "4. Consider disabling APIs if no longer needed:"
    echo "   - workstations.googleapis.com"
    echo "   - datamigration.googleapis.com"
    echo "   - artifactregistry.googleapis.com"
    echo
    echo -e "${GREEN}All resources have been successfully destroyed!${NC}"
}

# Function to handle script interruption
cleanup_on_interrupt() {
    error "Script interrupted by user"
    log "Cleaning up any partial operations..."
    exit 1
}

# Set up signal handling
trap cleanup_on_interrupt SIGINT SIGTERM

# Main destruction function
main() {
    log "Starting destruction of Secure Database Modernization Workflows..."
    
    check_prerequisites
    set_environment_variables
    configure_gcloud
    confirm_destruction
    
    # Destroy resources in reverse order of creation to handle dependencies
    destroy_workstation_instances
    destroy_workstation_config
    destroy_workstation_cluster
    destroy_migration_resources
    destroy_cloud_sql_instances
    destroy_artifact_registry
    destroy_secrets
    destroy_custom_iam_roles
    cleanup_cloud_build
    cleanup_environment
    
    display_summary
    
    log "Destruction completed successfully!"
}

# Run main function
main "$@"