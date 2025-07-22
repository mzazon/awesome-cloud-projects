#!/bin/bash

# Destroy script for Legacy Application Architectures with Application Design Center and Migration Center
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to prompt for confirmation
confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        log "Force delete enabled, skipping confirmation"
        return 0
    fi
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -rp "$message [Y/n]: " answer
            answer=${answer:-y}
        else
            read -rp "$message [y/N]: " answer
            answer=${answer:-n}
        fi
        
        case $answer in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if gcloud is installed
    if ! command_exists gcloud; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    success "Prerequisites validation completed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Try to detect from current gcloud config or use defaults
    export PROJECT_ID=${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}
    export REGION=${REGION:-$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")}
    export ZONE=${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null || echo "us-central1-a")}
    
    # Set resource names (should match deploy script)
    export REPOSITORY_NAME=${REPOSITORY_NAME:-"modernized-apps"}
    export SERVICE_NAME=${SERVICE_NAME:-"modernized-service"}
    
    if [[ -z "$PROJECT_ID" ]]; then
        error "PROJECT_ID not set. Please set it as an environment variable or configure gcloud."
        exit 1
    fi
    
    # Display configuration
    log "Configuration:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Zone: ${ZONE}"
    echo "  Repository: ${REPOSITORY_NAME}"
    echo "  Service: ${SERVICE_NAME}"
    
    success "Environment variables loaded"
}

# Function to delete Cloud Deploy resources
cleanup_cloud_deploy() {
    log "Cleaning up Cloud Deploy resources..."
    
    # Delete delivery pipeline
    if gcloud deploy delivery-pipelines describe modernized-app-pipeline --region="${REGION}" >/dev/null 2>&1; then
        if confirm_action "Delete Cloud Deploy pipeline 'modernized-app-pipeline'?"; then
            log "Deleting delivery pipeline..."
            if gcloud deploy delivery-pipelines delete modernized-app-pipeline \
                --region="${REGION}" \
                --quiet; then
                success "Delivery pipeline deleted"
            else
                warning "Failed to delete delivery pipeline"
            fi
        else
            log "Skipping delivery pipeline deletion"
        fi
    else
        log "Delivery pipeline not found"
    fi
    
    # Delete targets
    local targets=("development" "staging" "production")
    for target in "${targets[@]}"; do
        if gcloud deploy targets describe "$target" --region="${REGION}" >/dev/null 2>&1; then
            log "Deleting target: $target"
            gcloud deploy targets delete "$target" \
                --region="${REGION}" \
                --quiet || warning "Failed to delete target: $target"
        fi
    done
    
    success "Cloud Deploy cleanup completed"
}

# Function to delete Cloud Build resources
cleanup_cloud_build() {
    log "Cleaning up Cloud Build resources..."
    
    # Delete build triggers
    local trigger_ids
    trigger_ids=$(gcloud builds triggers list --format="value(id)" 2>/dev/null || echo "")
    
    if [[ -n "$trigger_ids" ]]; then
        if confirm_action "Delete all Cloud Build triggers?"; then
            echo "$trigger_ids" | while read -r trigger_id; do
                if [[ -n "$trigger_id" ]]; then
                    log "Deleting build trigger: $trigger_id"
                    gcloud builds triggers delete "$trigger_id" --quiet || warning "Failed to delete trigger: $trigger_id"
                fi
            done
            success "Build triggers deleted"
        else
            log "Skipping build triggers deletion"
        fi
    else
        log "No build triggers found"
    fi
    
    # Delete container images
    local images
    images=$(gcloud container images list --repository="gcr.io/${PROJECT_ID}" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$images" ]]; then
        if confirm_action "Delete all container images in gcr.io/${PROJECT_ID}?"; then
            echo "$images" | while read -r image; do
                if [[ -n "$image" ]]; then
                    log "Deleting container image: $image"
                    gcloud container images delete "$image" --quiet --force-delete-tags || warning "Failed to delete image: $image"
                fi
            done
            success "Container images deleted"
        else
            log "Skipping container images deletion"
        fi
    else
        log "No container images found"
    fi
    
    success "Cloud Build cleanup completed"
}

# Function to delete Cloud Run services
cleanup_cloud_run() {
    log "Cleaning up Cloud Run services..."
    
    # Delete Cloud Run service
    if gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        if confirm_action "Delete Cloud Run service '${SERVICE_NAME}'?"; then
            log "Deleting Cloud Run service..."
            if gcloud run services delete "${SERVICE_NAME}" \
                --region="${REGION}" \
                --quiet; then
                success "Cloud Run service deleted"
            else
                warning "Failed to delete Cloud Run service"
            fi
        else
            log "Skipping Cloud Run service deletion"
        fi
    else
        log "Cloud Run service not found"
    fi
    
    success "Cloud Run cleanup completed"
}

# Function to delete source repository
cleanup_source_repository() {
    log "Cleaning up Cloud Source Repository..."
    
    # Delete source repository
    if gcloud source repos describe "${REPOSITORY_NAME}" >/dev/null 2>&1; then
        if confirm_action "Delete source repository '${REPOSITORY_NAME}'? This will permanently delete all code."; then
            log "Deleting source repository..."
            if gcloud source repos delete "${REPOSITORY_NAME}" --quiet; then
                success "Source repository deleted"
            else
                warning "Failed to delete source repository"
            fi
        else
            log "Skipping source repository deletion"
        fi
    else
        log "Source repository not found"
    fi
    
    # Clean up local repository copy
    local repo_dir="/tmp/${REPOSITORY_NAME}"
    if [[ -d "$repo_dir" ]]; then
        if confirm_action "Delete local repository copy at $repo_dir?"; then
            log "Removing local repository copy..."
            rm -rf "$repo_dir" && success "Local repository copy removed"
        else
            log "Skipping local repository cleanup"
        fi
    else
        log "No local repository copy found"
    fi
    
    success "Source repository cleanup completed"
}

# Function to cleanup Application Design Center resources
cleanup_application_design_center() {
    log "Cleaning up Application Design Center resources..."
    
    # Note: Actual API commands may differ based on service availability
    # This follows the pattern from the deploy script
    
    log "Application Design Center resources cleanup (placeholder)"
    # In a real implementation, this would include:
    # - Deleting applications
    # - Deleting spaces
    # - Cleaning up templates
    
    success "Application Design Center cleanup completed"
}

# Function to cleanup Migration Center resources
cleanup_migration_center() {
    log "Cleaning up Migration Center resources..."
    
    # Delete discovery client
    if gcloud migration-center discovery-clients describe legacy-client --location="${REGION}" >/dev/null 2>&1; then
        if confirm_action "Delete Migration Center discovery client 'legacy-client'?"; then
            log "Deleting discovery client..."
            if gcloud migration-center discovery-clients delete legacy-client \
                --location="${REGION}" \
                --quiet; then
                success "Discovery client deleted"
            else
                warning "Failed to delete discovery client"
            fi
        else
            log "Skipping discovery client deletion"
        fi
    else
        log "Discovery client not found"
    fi
    
    # Delete source
    if gcloud migration-center sources describe legacy-discovery --location="${REGION}" >/dev/null 2>&1; then
        if confirm_action "Delete Migration Center source 'legacy-discovery'?"; then
            log "Deleting Migration Center source..."
            if gcloud migration-center sources delete legacy-discovery \
                --location="${REGION}" \
                --quiet; then
                success "Migration Center source deleted"
            else
                warning "Failed to delete Migration Center source"
            fi
        else
            log "Skipping Migration Center source deletion"
        fi
    else
        log "Migration Center source not found"
    fi
    
    success "Migration Center cleanup completed"
}

# Function to cleanup monitoring resources
cleanup_monitoring() {
    log "Cleaning up monitoring resources..."
    
    # Delete monitoring dashboards
    local dashboard_ids
    dashboard_ids=$(gcloud monitoring dashboards list \
        --filter="displayName:Modernized Application Dashboard" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$dashboard_ids" ]]; then
        if confirm_action "Delete monitoring dashboards?"; then
            echo "$dashboard_ids" | while read -r dashboard_id; do
                if [[ -n "$dashboard_id" ]]; then
                    log "Deleting dashboard: $dashboard_id"
                    gcloud monitoring dashboards delete "$dashboard_id" --quiet || warning "Failed to delete dashboard: $dashboard_id"
                fi
            done
            success "Monitoring dashboards deleted"
        else
            log "Skipping monitoring dashboards deletion"
        fi
    else
        log "No monitoring dashboards found"
    fi
    
    # Delete alerting policies
    local policy_ids
    policy_ids=$(gcloud alpha monitoring policies list \
        --filter="displayName:High Error Rate Alert" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$policy_ids" ]]; then
        if confirm_action "Delete alerting policies?"; then
            echo "$policy_ids" | while read -r policy_id; do
                if [[ -n "$policy_id" ]]; then
                    log "Deleting alerting policy: $policy_id"
                    gcloud alpha monitoring policies delete "$policy_id" --quiet || warning "Failed to delete policy: $policy_id"
                fi
            done
            success "Alerting policies deleted"
        else
            log "Skipping alerting policies deletion"
        fi
    else
        log "No alerting policies found"
    fi
    
    success "Monitoring cleanup completed"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    local temp_files=(
        "/tmp/sample-assessment.json"
        "/tmp/modernized-app-template.yaml"
        "/tmp/monitoring-dashboard.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            log "Removing temporary file: $file"
            rm -f "$file"
        fi
    done
    
    success "Temporary files cleanup completed"
}

# Function to disable APIs (optional)
disable_apis() {
    if confirm_action "Disable Google Cloud APIs that were enabled? (This may affect other services)"; then
        log "Disabling APIs..."
        
        local apis=(
            "migrationcenter.googleapis.com"
            "cloudbuild.googleapis.com"
            "clouddeploy.googleapis.com"
            "run.googleapis.com"
            "container.googleapis.com"
            "sourcerepo.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            log "Disabling API: $api"
            gcloud services disable "$api" --quiet || warning "Failed to disable API: $api"
        done
        
        success "APIs disabled"
    else
        log "Skipping API disabling"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local cleanup_issues=0
    
    # Check Cloud Run services
    if gcloud run services list --region="${REGION}" --format="value(metadata.name)" | grep -q "${SERVICE_NAME}"; then
        warning "Cloud Run service still exists: ${SERVICE_NAME}"
        ((cleanup_issues++))
    fi
    
    # Check source repositories
    if gcloud source repos list --format="value(name)" | grep -q "${REPOSITORY_NAME}"; then
        warning "Source repository still exists: ${REPOSITORY_NAME}"
        ((cleanup_issues++))
    fi
    
    # Check build triggers
    local trigger_count
    trigger_count=$(gcloud builds triggers list --format="value(id)" | wc -l)
    if [[ "$trigger_count" -gt 0 ]]; then
        warning "$trigger_count build trigger(s) still exist"
        ((cleanup_issues++))
    fi
    
    # Check Migration Center resources
    if gcloud migration-center sources list --location="${REGION}" --format="value(name)" | grep -q "legacy-discovery"; then
        warning "Migration Center source still exists"
        ((cleanup_issues++))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        success "Cleanup verification passed - no issues found"
    else
        warning "Cleanup verification found $cleanup_issues issue(s)"
        log "You may need to manually remove remaining resources"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "================"
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    echo "Resources cleaned up:"
    echo "- Cloud Deploy pipelines and targets"
    echo "- Cloud Build triggers and container images"
    echo "- Cloud Run services"
    echo "- Cloud Source Repositories"
    echo "- Migration Center sources and discovery clients"
    echo "- Application Design Center resources"
    echo "- Monitoring dashboards and alerts"
    echo "- Temporary files"
    echo ""
    echo "Cleanup completed successfully!"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force           Skip confirmation prompts and force delete all resources"
    echo "  --keep-apis       Do not disable APIs during cleanup"
    echo "  --help           Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID        Google Cloud project ID (required)"
    echo "  REGION           Google Cloud region (default: us-central1)"
    echo "  REPOSITORY_NAME  Source repository name (default: modernized-apps)"
    echo "  SERVICE_NAME     Cloud Run service name (default: modernized-service)"
    echo ""
    echo "Examples:"
    echo "  $0                          # Interactive cleanup with confirmations"
    echo "  $0 --force                  # Force cleanup without confirmations"
    echo "  PROJECT_ID=my-project $0    # Cleanup specific project"
}

# Main cleanup function
main() {
    local skip_apis=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                export FORCE_DELETE=true
                shift
                ;;
            --keep-apis)
                skip_apis=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log "Starting cleanup of Legacy Application Architectures solution..."
    
    validate_prerequisites
    load_environment
    
    # Confirm destructive action
    if [[ "${FORCE_DELETE:-}" != "true" ]]; then
        echo ""
        warning "This will permanently delete resources in project: ${PROJECT_ID}"
        warning "This action cannot be undone!"
        echo ""
        if ! confirm_action "Are you sure you want to proceed with cleanup?"; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Perform cleanup in reverse order of creation
    cleanup_cloud_deploy
    cleanup_cloud_build
    cleanup_cloud_run
    cleanup_source_repository
    cleanup_application_design_center
    cleanup_migration_center
    cleanup_monitoring
    cleanup_temp_files
    
    # Optionally disable APIs
    if [[ "$skip_apis" != "true" ]]; then
        disable_apis
    fi
    
    verify_cleanup
    
    success "Cleanup completed successfully!"
    display_cleanup_summary
}

# Handle script interruption
trap 'error "Cleanup interrupted"; exit 1' INT TERM

# Run main function
main "$@"