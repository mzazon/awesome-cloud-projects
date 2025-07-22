#!/bin/bash

# Destroy script for Continuous Performance Optimization with Cloud Build Triggers and Cloud Monitoring
# This script removes all resources created by the deployment script
# Version: 1.0
# Last Updated: 2025-01-28

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

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

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
FORCE_DESTROY=${FORCE_DESTROY:-false}

# Configuration variables
PROJECT_ID=${PROJECT_ID:-}
REGION=${REGION:-"us-central1"}
ZONE=${ZONE:-"us-central1-a"}
REPO_NAME=${REPO_NAME:-"app-performance-repo"}
BUILD_TRIGGER_NAME=${BUILD_TRIGGER_NAME:-"perf-optimization-trigger"}
MONITORING_POLICY_NAME=${MONITORING_POLICY_NAME:-"performance-threshold-policy"}
SERVICE_NAME=${SERVICE_NAME:-}
CHANNEL_ID=${CHANNEL_ID:-}

# Try to load configuration from deployment files
load_deployment_config() {
    local config_loaded=false
    
    # Try to load from deployment environment file
    if [ -f "deployment.env" ]; then
        log_info "Loading configuration from deployment.env..."
        source deployment.env
        config_loaded=true
    fi
    
    # Try to load from deployment summary
    if [ -f "deployment-summary.json" ] && command -v jq &> /dev/null; then
        log_info "Loading configuration from deployment-summary.json..."
        PROJECT_ID=$(jq -r '.project_id // empty' deployment-summary.json)
        REGION=$(jq -r '.region // empty' deployment-summary.json)
        ZONE=$(jq -r '.zone // empty' deployment-summary.json)
        REPO_NAME=$(jq -r '.resources.repository // empty' deployment-summary.json)
        SERVICE_NAME=$(jq -r '.resources.service // empty' deployment-summary.json)
        BUILD_TRIGGER_NAME=$(jq -r '.resources.build_trigger // empty' deployment-summary.json)
        MONITORING_POLICY_NAME=$(jq -r '.resources.monitoring_policy // empty' deployment-summary.json)
        config_loaded=true
    fi
    
    # If no config found, try to detect from gcloud
    if [ "$config_loaded" = false ]; then
        log_info "Attempting to detect configuration from gcloud..."
        if command -v gcloud &> /dev/null; then
            local current_project
            current_project=$(gcloud config get-value project 2>/dev/null || echo "")
            if [ -n "$current_project" ]; then
                PROJECT_ID="$current_project"
                log_info "Using current gcloud project: $PROJECT_ID"
            fi
        fi
    fi
    
    # Generate service name if not found
    if [ -z "$SERVICE_NAME" ]; then
        log_warning "Service name not found in configuration. Using pattern matching..."
        if [ -n "$PROJECT_ID" ] && command -v gcloud &> /dev/null; then
            SERVICE_NAME=$(gcloud run services list \
                --project="$PROJECT_ID" \
                --region="$REGION" \
                --filter="metadata.name~performance-app" \
                --format="value(metadata.name)" \
                --limit=1 2>/dev/null || echo "")
        fi
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found. Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if project is set
    if [ -z "$PROJECT_ID" ]; then
        log_error "PROJECT_ID is not set. Please set it or run from deployment directory."
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project $PROJECT_ID does not exist or is not accessible."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to display configuration
display_configuration() {
    log_info "Destruction Configuration:"
    echo "  Project ID: ${PROJECT_ID:-'Not set'}"
    echo "  Region: $REGION"
    echo "  Zone: $ZONE"
    echo "  Repository Name: $REPO_NAME"
    echo "  Service Name: ${SERVICE_NAME:-'Not set'}"
    echo "  Build Trigger: $BUILD_TRIGGER_NAME"
    echo "  Monitoring Policy: $MONITORING_POLICY_NAME"
    echo "  Channel ID: ${CHANNEL_ID:-'Not set'}"
    echo ""
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN MODE - No resources will be destroyed"
        return 0
    fi
    
    log_warning "This will permanently delete all resources associated with this deployment!"
    log_warning "This action cannot be undone!"
    echo ""
    
    if [ "$FORCE_DESTROY" != "true" ]; then
        read -p "Are you sure you want to continue? (yes/no): " -r
        echo
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Destruction cancelled by user."
            exit 0
        fi
        
        log_warning "Final confirmation required!"
        read -p "Type 'DESTROY' to confirm: " -r
        echo
        if [[ $REPLY != "DESTROY" ]]; then
            log_info "Destruction cancelled by user."
            exit 0
        fi
    fi
}

# Function to set up GCP configuration
setup_gcp_configuration() {
    log_info "Configuring Google Cloud settings..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would set project to $PROJECT_ID"
        return 0
    fi
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log_success "GCP configuration completed"
}

# Function to remove Cloud Run service
remove_cloud_run_service() {
    log_info "Removing Cloud Run service..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would remove Cloud Run service: $SERVICE_NAME"
        return 0
    fi
    
    if [ -z "$SERVICE_NAME" ]; then
        log_warning "Service name not set. Attempting to find performance-app services..."
        
        # List all services with performance-app pattern
        local services
        services=$(gcloud run services list \
            --project="$PROJECT_ID" \
            --region="$REGION" \
            --filter="metadata.name~performance-app" \
            --format="value(metadata.name)" 2>/dev/null || echo "")
        
        if [ -n "$services" ]; then
            log_info "Found services to remove:"
            echo "$services" | while read -r service; do
                echo "  - $service"
            done
            
            if [ "$FORCE_DESTROY" != "true" ]; then
                read -p "Remove these services? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Skipping Cloud Run service removal"
                    return 0
                fi
            fi
            
            # Remove each service
            echo "$services" | while read -r service; do
                if [ -n "$service" ]; then
                    log_info "Removing service: $service"
                    if gcloud run services delete "$service" \
                        --region="$REGION" \
                        --project="$PROJECT_ID" \
                        --quiet; then
                        log_success "Removed service: $service"
                    else
                        log_warning "Failed to remove service: $service"
                    fi
                fi
            done
        else
            log_warning "No Cloud Run services found to remove"
        fi
    else
        # Remove specific service
        if gcloud run services describe "$SERVICE_NAME" \
            --region="$REGION" \
            --project="$PROJECT_ID" &> /dev/null; then
            
            if gcloud run services delete "$SERVICE_NAME" \
                --region="$REGION" \
                --project="$PROJECT_ID" \
                --quiet; then
                log_success "Removed Cloud Run service: $SERVICE_NAME"
            else
                log_error "Failed to remove Cloud Run service: $SERVICE_NAME"
            fi
        else
            log_warning "Cloud Run service $SERVICE_NAME not found"
        fi
    fi
}

# Function to remove monitoring resources
remove_monitoring_resources() {
    log_info "Removing monitoring and alerting resources..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would remove monitoring resources"
        return 0
    fi
    
    # Remove alerting policies
    log_info "Removing alerting policies..."
    local policy_ids
    policy_ids=$(gcloud alpha monitoring policies list \
        --filter="displayName:($MONITORING_POLICY_NAME OR 'Performance Optimization')" \
        --format="value(name.split('/').slice(-1)[0])" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [ -n "$policy_ids" ]; then
        echo "$policy_ids" | while read -r policy_id; do
            if [ -n "$policy_id" ]; then
                log_info "Removing alerting policy: $policy_id"
                if gcloud alpha monitoring policies delete "$policy_id" \
                    --project="$PROJECT_ID" \
                    --quiet; then
                    log_success "Removed alerting policy: $policy_id"
                else
                    log_warning "Failed to remove alerting policy: $policy_id"
                fi
            fi
        done
    else
        log_warning "No alerting policies found to remove"
    fi
    
    # Remove notification channels
    log_info "Removing notification channels..."
    local channel_ids
    channel_ids=$(gcloud alpha monitoring channels list \
        --filter="displayName:('Performance Optimization' OR 'Webhook')" \
        --format="value(name.split('/').slice(-1)[0])" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [ -n "$channel_ids" ]; then
        echo "$channel_ids" | while read -r channel_id; do
            if [ -n "$channel_id" ]; then
                log_info "Removing notification channel: $channel_id"
                if gcloud alpha monitoring channels delete \
                    "projects/$PROJECT_ID/notificationChannels/$channel_id" \
                    --project="$PROJECT_ID" \
                    --quiet; then
                    log_success "Removed notification channel: $channel_id"
                else
                    log_warning "Failed to remove notification channel: $channel_id"
                fi
            fi
        done
    else
        log_warning "No notification channels found to remove"
    fi
}

# Function to remove Cloud Build trigger
remove_build_trigger() {
    log_info "Removing Cloud Build trigger..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would remove build trigger: $BUILD_TRIGGER_NAME"
        return 0
    fi
    
    # Check if trigger exists
    if gcloud builds triggers describe "$BUILD_TRIGGER_NAME" \
        --project="$PROJECT_ID" &> /dev/null; then
        
        if gcloud builds triggers delete "$BUILD_TRIGGER_NAME" \
            --project="$PROJECT_ID" \
            --quiet; then
            log_success "Removed build trigger: $BUILD_TRIGGER_NAME"
        else
            log_error "Failed to remove build trigger: $BUILD_TRIGGER_NAME"
        fi
    else
        log_warning "Build trigger $BUILD_TRIGGER_NAME not found"
    fi
}

# Function to remove container images
remove_container_images() {
    log_info "Removing container images..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would remove container images"
        return 0
    fi
    
    # Find and remove images
    local image_repos
    image_repos=$(gcloud container images list \
        --project="$PROJECT_ID" \
        --filter="name~performance-app" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$image_repos" ]; then
        echo "$image_repos" | while read -r image_repo; do
            if [ -n "$image_repo" ]; then
                log_info "Removing container images from: $image_repo"
                if gcloud container images delete "$image_repo" \
                    --force-delete-tags \
                    --project="$PROJECT_ID" \
                    --quiet; then
                    log_success "Removed container images from: $image_repo"
                else
                    log_warning "Failed to remove container images from: $image_repo"
                fi
            fi
        done
    else
        log_warning "No container images found to remove"
    fi
}

# Function to remove Cloud Source Repository
remove_source_repository() {
    log_info "Removing Cloud Source Repository..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would remove repository: $REPO_NAME"
        return 0
    fi
    
    # Check if repository exists
    if gcloud source repos describe "$REPO_NAME" \
        --project="$PROJECT_ID" &> /dev/null; then
        
        log_warning "This will permanently delete the repository and all its history!"
        if [ "$FORCE_DESTROY" != "true" ]; then
            read -p "Continue with repository deletion? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Skipping repository deletion"
                return 0
            fi
        fi
        
        if gcloud source repos delete "$REPO_NAME" \
            --project="$PROJECT_ID" \
            --quiet; then
            log_success "Removed repository: $REPO_NAME"
        else
            log_error "Failed to remove repository: $REPO_NAME"
        fi
    else
        log_warning "Repository $REPO_NAME not found"
    fi
}

# Function to clean up Cloud Logging entries
cleanup_logging_entries() {
    log_info "Cleaning up Cloud Logging entries..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would clean up logging entries"
        return 0
    fi
    
    # Note: Cloud Logging entries are automatically cleaned up based on retention policies
    # We can delete custom log sinks if any were created
    
    log_info "Checking for custom log sinks..."
    local log_sinks
    log_sinks=$(gcloud logging sinks list \
        --project="$PROJECT_ID" \
        --filter="name~performance" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$log_sinks" ]; then
        echo "$log_sinks" | while read -r sink_name; do
            if [ -n "$sink_name" ]; then
                log_info "Removing log sink: $sink_name"
                if gcloud logging sinks delete "$sink_name" \
                    --project="$PROJECT_ID" \
                    --quiet; then
                    log_success "Removed log sink: $sink_name"
                else
                    log_warning "Failed to remove log sink: $sink_name"
                fi
            fi
        done
    else
        log_info "No custom log sinks found"
    fi
}

# Function to remove local files
remove_local_files() {
    log_info "Cleaning up local files..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would remove local files"
        return 0
    fi
    
    # List of files to remove
    local files_to_remove=(
        "deployment.env"
        "deployment-summary.json"
        "alerting-policy.yaml"
        "notification-channel.yaml"
        "performance-results-*.json"
        "baseline-performance.json"
    )
    
    for file_pattern in "${files_to_remove[@]}"; do
        if ls $file_pattern 1> /dev/null 2>&1; then
            log_info "Removing: $file_pattern"
            rm -f $file_pattern
        fi
    done
    
    # Remove repository directory if it exists
    if [ -d "$REPO_NAME" ]; then
        log_info "Removing local repository directory: $REPO_NAME"
        if [ "$FORCE_DESTROY" != "true" ]; then
            read -p "Remove local repository directory? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf "$REPO_NAME"
                log_success "Removed local repository directory"
            else
                log_info "Keeping local repository directory"
            fi
        else
            rm -rf "$REPO_NAME"
            log_success "Removed local repository directory"
        fi
    fi
    
    log_success "Local cleanup completed"
}

# Function to verify resource removal
verify_resource_removal() {
    log_info "Verifying resource removal..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would verify resource removal"
        return 0
    fi
    
    local resources_remaining=false
    
    # Check Cloud Run services
    if [ -n "$SERVICE_NAME" ]; then
        if gcloud run services describe "$SERVICE_NAME" \
            --region="$REGION" \
            --project="$PROJECT_ID" &> /dev/null; then
            log_warning "Cloud Run service $SERVICE_NAME still exists"
            resources_remaining=true
        fi
    fi
    
    # Check build trigger
    if gcloud builds triggers describe "$BUILD_TRIGGER_NAME" \
        --project="$PROJECT_ID" &> /dev/null; then
        log_warning "Build trigger $BUILD_TRIGGER_NAME still exists"
        resources_remaining=true
    fi
    
    # Check repository
    if gcloud source repos describe "$REPO_NAME" \
        --project="$PROJECT_ID" &> /dev/null; then
        log_warning "Repository $REPO_NAME still exists"
        resources_remaining=true
    fi
    
    if [ "$resources_remaining" = false ]; then
        log_success "All resources have been successfully removed"
    else
        log_warning "Some resources may still exist. Please check manually."
    fi
}

# Function to handle project deletion
handle_project_deletion() {
    log_info "Project deletion options..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would offer project deletion"
        return 0
    fi
    
    log_warning "Do you want to delete the entire project?"
    log_warning "This will permanently delete ALL resources in the project!"
    echo ""
    
    if [ "$FORCE_DESTROY" != "true" ]; then
        read -p "Delete entire project $PROJECT_ID? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_warning "Final confirmation for project deletion!"
            read -p "Type the project ID to confirm: " -r
            echo
            if [[ $REPLY == "$PROJECT_ID" ]]; then
                log_info "Deleting project: $PROJECT_ID"
                if gcloud projects delete "$PROJECT_ID" --quiet; then
                    log_success "Project deleted successfully"
                else
                    log_error "Failed to delete project"
                fi
            else
                log_info "Project ID mismatch. Skipping project deletion."
            fi
        else
            log_info "Skipping project deletion"
        fi
    else
        log_info "Skipping project deletion (not forced)"
    fi
}

# Function to display destruction summary
display_destruction_summary() {
    log_success "Resource destruction completed!"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "                   DESTRUCTION SUMMARY"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo ""
    echo "Resources processed:"
    echo "  ✓ Cloud Run services"
    echo "  ✓ Cloud Build triggers"
    echo "  ✓ Container images"
    echo "  ✓ Cloud Source Repository"
    echo "  ✓ Monitoring alerting policies"
    echo "  ✓ Notification channels"
    echo "  ✓ Local files"
    echo ""
    echo "Note: Some resources may have retention policies that prevent"
    echo "immediate deletion (e.g., Cloud Logging entries)."
    echo ""
    echo "To verify all resources are removed, check the Google Cloud Console:"
    echo "  https://console.cloud.google.com/home/dashboard?project=$PROJECT_ID"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
}

# Function to handle cleanup on error
cleanup_on_error() {
    log_error "Destruction process encountered an error."
    log_info "Some resources may not have been removed."
    log_info "Please check the Google Cloud Console and remove resources manually if needed."
    exit 1
}

# Main destruction function
main() {
    log_info "Starting destruction of Continuous Performance Optimization solution..."
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Execute destruction steps
    load_deployment_config
    check_prerequisites
    display_configuration
    setup_gcp_configuration
    remove_cloud_run_service
    remove_monitoring_resources
    remove_build_trigger
    remove_container_images
    remove_source_repository
    cleanup_logging_entries
    remove_local_files
    verify_resource_removal
    handle_project_deletion
    display_destruction_summary
    
    log_success "Destruction completed successfully!"
}

# Script usage information
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -d, --dry-run           Run in dry-run mode (no resources destroyed)"
    echo "  -f, --force             Force destruction without prompts"
    echo "  -p, --project PROJECT   Set project ID"
    echo "  -r, --region REGION     Set region (default: us-central1)"
    echo "  -z, --zone ZONE         Set zone (default: us-central1-a)"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID              Google Cloud project ID"
    echo "  REGION                  Google Cloud region"
    echo "  ZONE                    Google Cloud zone"
    echo "  REPO_NAME               Cloud Source Repository name"
    echo "  SERVICE_NAME            Cloud Run service name"
    echo "  BUILD_TRIGGER_NAME      Cloud Build trigger name"
    echo "  MONITORING_POLICY_NAME  Monitoring policy name"
    echo "  CHANNEL_ID              Notification channel ID"
    echo "  DRY_RUN                 Run in dry-run mode (true/false)"
    echo "  FORCE_DESTROY           Force destruction (true/false)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive destruction"
    echo "  $0 --dry-run                          # Dry run mode"
    echo "  $0 --force --project my-project       # Force destruction"
    echo "  DRY_RUN=true $0                       # Dry run via environment"
    echo ""
    echo "Note: This script will attempt to load configuration from:"
    echo "  - deployment.env (if present)"
    echo "  - deployment-summary.json (if present)"
    echo "  - Current gcloud configuration"
    echo ""
}

# Parse command line arguments
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
        -f|--force)
            FORCE_DESTROY=true
            shift
            ;;
        -p|--project)
            PROJECT_ID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -z|--zone)
            ZONE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run main function
main "$@"