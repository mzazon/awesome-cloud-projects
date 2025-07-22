#!/bin/bash

# Route Optimization with Google Maps Routes API and Cloud Optimization AI - Cleanup Script
# This script safely removes all infrastructure created for the route optimization platform

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Confirmation prompt
confirm_destruction() {
    echo
    log_warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo
    log_warning "This script will permanently delete the following resources:"
    echo "  • Cloud Run service: ${SERVICE_NAME:-route-optimizer-*}"
    echo "  • Cloud Function: route-processor-*"
    echo "  • Cloud SQL instance: ${SQL_INSTANCE_NAME:-route-db-*} (with ALL data)"
    echo "  • Pub/Sub topics and subscriptions: ${TOPIC_NAME:-route-events-*}"
    echo "  • All associated data and backups"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to proceed? Type 'yes' to continue: " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    log_warning "Final confirmation required. Type 'DELETE' to proceed with resource destruction:"
    read -p "> " final_confirmation
    
    if [[ "$final_confirmation" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
    fi
    
    log_success "Prerequisites check passed"
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    # Try to load from deployment-info.txt if it exists
    if [[ -f "deployment-info.txt" ]]; then
        log_info "Found deployment-info.txt, extracting resource information..."
        
        export PROJECT_ID=$(grep "Project ID:" deployment-info.txt | cut -d' ' -f3)
        export REGION=$(grep "Region:" deployment-info.txt | cut -d' ' -f2)
        export RANDOM_SUFFIX=$(grep "Random Suffix:" deployment-info.txt | cut -d' ' -f3)
        
        if [[ -n "${RANDOM_SUFFIX}" ]]; then
            export SQL_INSTANCE_NAME="route-db-${RANDOM_SUFFIX}"
            export SERVICE_NAME="route-optimizer-${RANDOM_SUFFIX}"
            export TOPIC_NAME="route-events-${RANDOM_SUFFIX}"
            export FUNCTION_NAME="route-processor-${RANDOM_SUFFIX}"
        fi
        
        log_success "Loaded deployment configuration from file"
    else
        log_warning "No deployment-info.txt found, using environment variables or prompting for input"
        
        # Try to use environment variables or prompt for input
        if [[ -z "${PROJECT_ID:-}" ]]; then
            read -p "Enter Project ID: " PROJECT_ID
        fi
        
        if [[ -z "${REGION:-}" ]]; then
            export REGION="${REGION:-us-central1}"
            log_info "Using default region: ${REGION}"
        fi
        
        # If we don't have specific resource names, we'll try to find them
        if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
            log_warning "No random suffix found. Will attempt to find resources by pattern."
        fi
    fi
    
    # Set default project if specified
    if [[ -n "${PROJECT_ID}" ]]; then
        gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
        log_info "Set project: ${PROJECT_ID}"
    fi
    
    if [[ -n "${REGION}" ]]; then
        gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
        log_info "Set region: ${REGION}"
    fi
}

# Find resources by pattern if specific names aren't available
find_resources_by_pattern() {
    log_info "Searching for route optimization resources..."
    
    # Find Cloud Run services
    if [[ -z "${SERVICE_NAME:-}" ]]; then
        local run_services=$(gcloud run services list --region="${REGION}" --format="value(metadata.name)" --filter="metadata.name~route-optimizer-.*" 2>/dev/null || echo "")
        if [[ -n "${run_services}" ]]; then
            export SERVICE_NAME=$(echo "${run_services}" | head -n1)
            log_info "Found Cloud Run service: ${SERVICE_NAME}"
        fi
    fi
    
    # Find Cloud SQL instances
    if [[ -z "${SQL_INSTANCE_NAME:-}" ]]; then
        local sql_instances=$(gcloud sql instances list --format="value(name)" --filter="name~route-db-.*" 2>/dev/null || echo "")
        if [[ -n "${sql_instances}" ]]; then
            export SQL_INSTANCE_NAME=$(echo "${sql_instances}" | head -n1)
            log_info "Found Cloud SQL instance: ${SQL_INSTANCE_NAME}"
        fi
    fi
    
    # Find Pub/Sub topics
    if [[ -z "${TOPIC_NAME:-}" ]]; then
        local topics=$(gcloud pubsub topics list --format="value(name)" --filter="name~route-events-.*" 2>/dev/null || echo "")
        if [[ -n "${topics}" ]]; then
            # Extract just the topic name from the full path
            export TOPIC_NAME=$(echo "${topics}" | head -n1 | sed 's|.*/||')
            log_info "Found Pub/Sub topic: ${TOPIC_NAME}"
        fi
    fi
    
    # Find Cloud Functions
    if [[ -z "${FUNCTION_NAME:-}" ]]; then
        local functions=$(gcloud functions list --region="${REGION}" --format="value(name)" --filter="name~route-processor-.*" 2>/dev/null || echo "")
        if [[ -n "${functions}" ]]; then
            export FUNCTION_NAME=$(echo "${functions}" | head -n1)
            log_info "Found Cloud Function: ${FUNCTION_NAME}"
        fi
    fi
}

# Delete Cloud Run service
delete_cloud_run() {
    log_info "Deleting Cloud Run service..."
    
    if [[ -n "${SERVICE_NAME:-}" ]]; then
        if gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" &>/dev/null; then
            log_info "Deleting Cloud Run service: ${SERVICE_NAME}"
            gcloud run services delete "${SERVICE_NAME}" \
                --region="${REGION}" \
                --quiet || log_warning "Failed to delete Cloud Run service ${SERVICE_NAME}"
            log_success "Cloud Run service deleted"
        else
            log_warning "Cloud Run service ${SERVICE_NAME} not found"
        fi
    else
        log_warning "No Cloud Run service name specified, skipping"
    fi
}

# Delete Cloud Function
delete_cloud_function() {
    log_info "Deleting Cloud Function..."
    
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
            log_info "Deleting Cloud Function: ${FUNCTION_NAME}"
            gcloud functions delete "${FUNCTION_NAME}" \
                --region="${REGION}" \
                --quiet || log_warning "Failed to delete Cloud Function ${FUNCTION_NAME}"
            log_success "Cloud Function deleted"
        else
            log_warning "Cloud Function ${FUNCTION_NAME} not found"
        fi
    else
        log_warning "No Cloud Function name specified, skipping"
    fi
}

# Delete Pub/Sub resources
delete_pubsub() {
    log_info "Deleting Pub/Sub resources..."
    
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        # Delete subscriptions first (they depend on topics)
        local subscriptions=("${TOPIC_NAME}-sub" "${TOPIC_NAME}-dlq-sub")
        
        for sub in "${subscriptions[@]}"; do
            if gcloud pubsub subscriptions describe "${sub}" &>/dev/null; then
                log_info "Deleting subscription: ${sub}"
                gcloud pubsub subscriptions delete "${sub}" --quiet || log_warning "Failed to delete subscription ${sub}"
            else
                log_warning "Subscription ${sub} not found"
            fi
        done
        
        # Delete topics
        local topics=("${TOPIC_NAME}" "${TOPIC_NAME}-dlq")
        
        for topic in "${topics[@]}"; do
            if gcloud pubsub topics describe "${topic}" &>/dev/null; then
                log_info "Deleting topic: ${topic}"
                gcloud pubsub topics delete "${topic}" --quiet || log_warning "Failed to delete topic ${topic}"
            else
                log_warning "Topic ${topic} not found"
            fi
        done
        
        log_success "Pub/Sub resources deleted"
    else
        log_warning "No Pub/Sub topic name specified, skipping"
    fi
}

# Delete Cloud SQL instance
delete_cloud_sql() {
    log_info "Deleting Cloud SQL instance..."
    
    if [[ -n "${SQL_INSTANCE_NAME:-}" ]]; then
        if gcloud sql instances describe "${SQL_INSTANCE_NAME}" &>/dev/null; then
            log_warning "Deleting Cloud SQL instance: ${SQL_INSTANCE_NAME}"
            log_warning "This will permanently delete all data in the database!"
            
            # Remove deletion protection if enabled
            log_info "Removing deletion protection..."
            gcloud sql instances patch "${SQL_INSTANCE_NAME}" \
                --no-deletion-protection \
                --quiet || log_warning "Failed to remove deletion protection"
            
            # Delete the instance
            log_info "Deleting Cloud SQL instance (this may take several minutes)..."
            gcloud sql instances delete "${SQL_INSTANCE_NAME}" \
                --quiet || log_warning "Failed to delete Cloud SQL instance ${SQL_INSTANCE_NAME}"
            
            # Wait for deletion to complete
            log_info "Waiting for Cloud SQL instance deletion to complete..."
            local max_attempts=30
            local attempt=0
            
            while [[ $attempt -lt $max_attempts ]]; do
                if ! gcloud sql instances describe "${SQL_INSTANCE_NAME}" &>/dev/null; then
                    log_success "Cloud SQL instance deleted successfully"
                    break
                fi
                
                log_info "Instance still deleting... (attempt $((attempt + 1))/$max_attempts)"
                sleep 30
                ((attempt++))
            done
            
            if [[ $attempt -eq $max_attempts ]]; then
                log_warning "Cloud SQL instance deletion timed out. Please check manually."
            fi
        else
            log_warning "Cloud SQL instance ${SQL_INSTANCE_NAME} not found"
        fi
    else
        log_warning "No Cloud SQL instance name specified, skipping"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "route-optimizer"
        "route-processor" 
        "schema.sql"
        "monitoring-config.yaml"
        "deployment-info.txt"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            log_info "Removing: $file"
            rm -rf "$file" || log_warning "Failed to remove $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local issues_found=0
    
    # Check Cloud Run services
    if [[ -n "${SERVICE_NAME:-}" ]]; then
        if gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" &>/dev/null; then
            log_warning "Cloud Run service ${SERVICE_NAME} still exists"
            ((issues_found++))
        fi
    fi
    
    # Check Cloud Functions
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
            log_warning "Cloud Function ${FUNCTION_NAME} still exists"
            ((issues_found++))
        fi
    fi
    
    # Check Cloud SQL instances
    if [[ -n "${SQL_INSTANCE_NAME:-}" ]]; then
        if gcloud sql instances describe "${SQL_INSTANCE_NAME}" &>/dev/null; then
            log_warning "Cloud SQL instance ${SQL_INSTANCE_NAME} still exists"
            ((issues_found++))
        fi
    fi
    
    # Check Pub/Sub topics
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        if gcloud pubsub topics describe "${TOPIC_NAME}" &>/dev/null; then
            log_warning "Pub/Sub topic ${TOPIC_NAME} still exists"
            ((issues_found++))
        fi
    fi
    
    if [[ $issues_found -eq 0 ]]; then
        log_success "✅ All resources have been successfully deleted"
    else
        log_warning "⚠️  ${issues_found} resource(s) may still exist. Please check manually."
    fi
}

# Generate cleanup report
generate_cleanup_report() {
    log_info "Generating cleanup report..."
    
    cat > cleanup-report.txt << EOF
Route Optimization Platform Cleanup Report
==========================================

Cleanup Date: $(date)
Project ID: ${PROJECT_ID}
Region: ${REGION}

Resources Targeted for Deletion:
- Cloud SQL Instance: ${SQL_INSTANCE_NAME:-Not specified}
- Cloud Run Service: ${SERVICE_NAME:-Not specified}
- Cloud Function: ${FUNCTION_NAME:-Not specified}
- Pub/Sub Topic: ${TOPIC_NAME:-Not specified}

Cleanup Actions Performed:
1. Cloud Run service deletion
2. Cloud Function deletion  
3. Pub/Sub topics and subscriptions deletion
4. Cloud SQL instance deletion (with data)
5. Local files cleanup

Important Notes:
- All data in the Cloud SQL database has been permanently deleted
- Pub/Sub message history has been lost
- Application logs may still exist in Cloud Logging
- Any custom monitoring alerts may need manual cleanup

Post-Cleanup Actions:
- Review Cloud Logging for any remaining logs
- Check Cloud Monitoring for leftover custom metrics
- Verify no unexpected charges in Cloud Billing
- Consider disabling unused APIs if no longer needed

If you need to recreate this infrastructure, run the deploy.sh script again.
EOF
    
    log_success "Cleanup report saved to cleanup-report.txt"
}

# Main cleanup function
main() {
    log_info "🗑️  Starting Route Optimization Platform cleanup..."
    echo
    
    check_prerequisites
    load_deployment_info
    find_resources_by_pattern
    confirm_destruction
    
    echo
    log_info "Beginning resource deletion process..."
    
    # Delete resources in dependency order
    delete_cloud_run
    delete_cloud_function
    delete_pubsub
    delete_cloud_sql
    cleanup_local_files
    
    echo
    verify_cleanup
    generate_cleanup_report
    
    echo
    log_success "🎉 Route Optimization Platform cleanup completed!"
    log_info "Cleanup report saved to cleanup-report.txt"
    
    echo
    log_warning "Remember to:"
    log_warning "• Check Cloud Billing for any unexpected charges"
    log_warning "• Review Cloud Logging for remaining logs"
    log_warning "• Disable APIs if no longer needed"
    log_warning "• Remove any custom monitoring alerts"
}

# Handle script interruption
cleanup_on_interrupt() {
    echo
    log_warning "Cleanup interrupted by user"
    log_info "Some resources may have been partially deleted"
    log_info "Run the script again to complete the cleanup"
    exit 1
}

# Set up interrupt trap
trap cleanup_on_interrupt SIGINT SIGTERM

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi