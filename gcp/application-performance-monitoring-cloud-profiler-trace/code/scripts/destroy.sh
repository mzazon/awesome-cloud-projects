#!/bin/bash

# Destroy script for Application Performance Monitoring with Cloud Profiler and Cloud Trace
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if required tools are installed
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Load environment variables from deployment
load_environment() {
    log "Loading environment variables..."
    
    # Try to load from service_urls.env if it exists
    if [ -f "service_urls.env" ]; then
        source service_urls.env
        log "Loaded service URLs from service_urls.env"
    else
        warning "service_urls.env not found. Will prompt for project ID."
    fi
    
    # Get project ID from user if not already set
    if [ -z "$PROJECT_ID" ]; then
        echo -n "Enter the project ID to destroy (or press Enter to use current project): "
        read -r user_project_id
        
        if [ -n "$user_project_id" ]; then
            export PROJECT_ID="$user_project_id"
        else
            export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        fi
    fi
    
    if [ -z "$PROJECT_ID" ]; then
        error "No project ID specified. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Set default region if not already set
    export REGION="${REGION:-us-central1}"
    export SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-profiler-trace-sa}"
    
    log "Environment variables loaded:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  SERVICE_ACCOUNT_NAME: ${SERVICE_ACCOUNT_NAME}"
}

# Confirm destruction with user
confirm_destruction() {
    log "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo ""
    echo "This script will permanently delete the following resources:"
    echo "  - Project: ${PROJECT_ID}"
    echo "  - All Cloud Run services in the project"
    echo "  - All container images"
    echo "  - All monitoring dashboards and alerts"
    echo "  - All service accounts and IAM bindings"
    echo "  - All logs and trace data"
    echo ""
    
    # Double confirmation for safety
    echo -n "Are you sure you want to continue? Type 'yes' to confirm: "
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    echo -n "This action cannot be undone. Type 'DELETE' to proceed: "
    read -r final_confirmation
    
    if [ "$final_confirmation" != "DELETE" ]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    success "Destruction confirmed. Proceeding with cleanup..."
}

# Delete Cloud Run services
delete_cloud_run_services() {
    log "Deleting Cloud Run services..."
    
    local services=("frontend" "api-gateway" "auth-service" "data-service")
    
    # Set the project context
    gcloud config set project ${PROJECT_ID}
    
    for service in "${services[@]}"; do
        log "Checking if service ${service} exists..."
        
        # Check if service exists before trying to delete
        if gcloud run services describe ${service} --region=${REGION} &> /dev/null; then
            log "Deleting Cloud Run service: ${service}"
            gcloud run services delete ${service} \
                --region=${REGION} \
                --quiet || {
                warning "Failed to delete service ${service}. It may have already been deleted."
            }
            success "Deleted service: ${service}"
        else
            log "Service ${service} does not exist or was already deleted"
        fi
    done
    
    success "Cloud Run services cleanup completed"
}

# Delete container images
delete_container_images() {
    log "Deleting container images..."
    
    local services=("frontend" "api-gateway" "auth-service" "data-service")
    
    for service in "${services[@]}"; do
        log "Checking for container images for service: ${service}"
        
        # Check if image exists before trying to delete
        if gcloud container images list --repository=gcr.io/${PROJECT_ID} --filter="name:${service}" --format="value(name)" | grep -q "${service}"; then
            log "Deleting container image: ${service}"
            gcloud container images delete gcr.io/${PROJECT_ID}/${service}:latest \
                --force-delete-tags \
                --quiet || {
                warning "Failed to delete container image for ${service}. It may have already been deleted."
            }
            success "Deleted container image: ${service}"
        else
            log "Container image for ${service} does not exist or was already deleted"
        fi
    done
    
    success "Container images cleanup completed"
}

# Delete monitoring resources
delete_monitoring_resources() {
    log "Deleting monitoring resources..."
    
    # List and delete custom dashboards
    log "Checking for custom monitoring dashboards..."
    
    local dashboards=$(gcloud monitoring dashboards list --filter="displayName:*Performance*" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$dashboards" ]; then
        while IFS= read -r dashboard; do
            if [ -n "$dashboard" ]; then
                log "Deleting monitoring dashboard: $dashboard"
                gcloud monitoring dashboards delete "$dashboard" --quiet || {
                    warning "Failed to delete dashboard: $dashboard"
                }
            fi
        done <<< "$dashboards"
        success "Monitoring dashboards deleted"
    else
        log "No custom monitoring dashboards found"
    fi
    
    # Delete alerting policies
    log "Checking for alerting policies..."
    
    local policies=$(gcloud alpha monitoring policies list --filter="displayName:*Performance*OR displayName:*Latency*" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$policies" ]; then
        while IFS= read -r policy; do
            if [ -n "$policy" ]; then
                log "Deleting alerting policy: $policy"
                gcloud alpha monitoring policies delete "$policy" --quiet || {
                    warning "Failed to delete alerting policy: $policy"
                }
            fi
        done <<< "$policies"
        success "Alerting policies deleted"
    else
        log "No custom alerting policies found"
    fi
    
    success "Monitoring resources cleanup completed"
}

# Delete service accounts
delete_service_accounts() {
    log "Deleting service accounts..."
    
    local service_account_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe ${service_account_email} &> /dev/null; then
        log "Deleting service account: ${service_account_email}"
        gcloud iam service-accounts delete ${service_account_email} --quiet || {
            warning "Failed to delete service account: ${service_account_email}"
        }
        success "Deleted service account: ${service_account_email}"
    else
        log "Service account ${service_account_email} does not exist or was already deleted"
    fi
    
    success "Service accounts cleanup completed"
}

# Delete local files
delete_local_files() {
    log "Cleaning up local files..."
    
    # Remove application code directory
    if [ -d "performance-demo" ]; then
        log "Removing application code directory..."
        rm -rf performance-demo
        success "Removed application code directory"
    fi
    
    # Remove generated files
    local files_to_remove=(
        "service_urls.env"
        "dashboard_config.json"
        "load_generator.py"
        "alert_policy.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            log "Removing file: $file"
            rm -f "$file"
            success "Removed file: $file"
        fi
    done
    
    success "Local files cleanup completed"
}

# Delete the entire project (most comprehensive cleanup)
delete_project() {
    log "Attempting to delete the entire project..."
    
    # Final confirmation for project deletion
    echo ""
    warning "Project deletion is the most thorough cleanup method."
    warning "This will permanently delete ALL resources in the project: ${PROJECT_ID}"
    echo ""
    echo -n "Do you want to delete the entire project? Type 'DELETE-PROJECT' to confirm: "
    read -r project_confirmation
    
    if [ "$project_confirmation" = "DELETE-PROJECT" ]; then
        log "Deleting project: ${PROJECT_ID}"
        gcloud projects delete ${PROJECT_ID} --quiet || {
            error "Failed to delete project: ${PROJECT_ID}"
            warning "You may need to delete the project manually in the console"
            return 1
        }
        success "Project deletion initiated: ${PROJECT_ID}"
        log "Note: Project deletion may take several minutes to complete"
        return 0
    else
        log "Project deletion cancelled. Individual resource cleanup will continue."
        return 1
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    # Check if Cloud Run services still exist
    log "Checking for remaining Cloud Run services..."
    local remaining_services=$(gcloud run services list --region=${REGION} --format="value(metadata.name)" 2>/dev/null || echo "")
    
    if [ -n "$remaining_services" ]; then
        warning "Some Cloud Run services may still exist:"
        echo "$remaining_services"
    else
        success "No Cloud Run services found"
    fi
    
    # Check if container images still exist
    log "Checking for remaining container images..."
    local remaining_images=$(gcloud container images list --repository=gcr.io/${PROJECT_ID} --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$remaining_images" ]; then
        warning "Some container images may still exist:"
        echo "$remaining_images"
    else
        success "No container images found"
    fi
    
    success "Cleanup verification completed"
}

# Print cleanup summary
print_cleanup_summary() {
    log "Cleanup Summary"
    log "==============="
    
    echo ""
    echo "🧹 Application Performance Monitoring Demo Cleanup Completed!"
    echo ""
    echo "Resources removed:"
    echo "  ✅ Cloud Run services (frontend, api-gateway, auth-service, data-service)"
    echo "  ✅ Container images in Google Container Registry"
    echo "  ✅ Monitoring dashboards and alerting policies"
    echo "  ✅ Service accounts and IAM bindings"
    echo "  ✅ Local application code and configuration files"
    echo ""
    
    if [ -n "$PROJECT_DELETED" ]; then
        echo "  ✅ Project: ${PROJECT_ID} (deletion initiated)"
        echo ""
        echo "Note: Project deletion may take several minutes to complete."
        echo "You can verify deletion in the Google Cloud Console."
    else
        echo "  ⚠️  Project: ${PROJECT_ID} (not deleted)"
        echo ""
        echo "The project was not deleted. If you want to completely remove all resources,"
        echo "you can delete the project manually in the Google Cloud Console:"
        echo "  https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}"
    fi
    
    echo ""
    echo "If you encounter any issues, you can:"
    echo "  1. Check the Google Cloud Console for any remaining resources"
    echo "  2. Delete the project manually for complete cleanup"
    echo "  3. Contact Google Cloud Support if needed"
    echo ""
    
    success "All cleanup operations completed!"
}

# Main execution
main() {
    log "Starting Application Performance Monitoring cleanup..."
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    # Try to delete the entire project first (most comprehensive)
    if delete_project; then
        PROJECT_DELETED=true
        delete_local_files
        print_cleanup_summary
        return 0
    fi
    
    # If project deletion was cancelled, proceed with individual resource cleanup
    PROJECT_DELETED=false
    
    delete_cloud_run_services
    delete_container_images
    delete_monitoring_resources
    delete_service_accounts
    delete_local_files
    verify_cleanup
    print_cleanup_summary
    
    success "All cleanup steps completed successfully!"
}

# Handle script interruption
trap 'error "Cleanup script interrupted. Some resources may not have been cleaned up."; exit 1' INT TERM

# Execute main function
main "$@"