#!/bin/bash

# User Lifecycle Management with Firebase Authentication and Cloud Tasks - Cleanup Script
# This script removes all infrastructure created by the deployment script

set -euo pipefail  # Exit on any error, undefined variables, or pipe failures

# Color codes for output formatting
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

# Error handling function
handle_error() {
    log_error "Cleanup failed at line $1. Some resources may not have been deleted."
    log_warning "Please check the Google Cloud Console for any remaining resources."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Banner
echo -e "${RED}"
echo "=================================================="
echo "      User Lifecycle Management Cleanup"
echo "       ⚠️  DESTRUCTIVE OPERATION ⚠️"
echo "=================================================="
echo -e "${NC}"

# Configuration
DEFAULT_REGION="us-central1"

# Check if running in non-interactive mode
if [[ "${1:-}" == "--non-interactive" ]]; then
    NON_INTERACTIVE=true
    shift
else
    NON_INTERACTIVE=false
fi

# Parse command line arguments
DRY_RUN=false
FORCE_DELETE=false
KEEP_PROJECT=false
DELETE_PROJECT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --keep-project)
            KEEP_PROJECT=true
            shift
            ;;
        --delete-project)
            DELETE_PROJECT=true
            shift
            ;;
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run              Show what would be deleted without making changes"
            echo "  --force                Skip confirmation prompts"
            echo "  --keep-project         Keep the project but delete all resources"
            echo "  --delete-project       Delete the entire project (irreversible)"
            echo "  --project-id PROJECT   Target specific project ID"
            echo "  --region REGION        Target specific region (default: us-central1)"
            echo "  --non-interactive      Run without prompts"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Get current project if not specified
if [[ -z "${PROJECT_ID:-}" ]]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "No project ID specified and no default project configured"
        log_error "Use --project-id PROJECT_ID or set default project with 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
fi

REGION="${REGION:-$DEFAULT_REGION}"

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed"
        exit 1
    fi
    
    # Check if firebase CLI is installed
    if ! command -v firebase &> /dev/null; then
        log_warning "Firebase CLI is not installed. Some cleanup operations may be skipped."
    fi
    
    # Check if authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_error "Project $PROJECT_ID does not exist or you don't have access"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Get user confirmation
get_user_confirmation() {
    if [[ "$NON_INTERACTIVE" == "true" ]] || [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "This will delete the following resources from project: $PROJECT_ID"
    echo "  🗄️  Cloud SQL instances"
    echo "  📋 Cloud Tasks queues"
    echo "  🏃 Cloud Run services"
    echo "  ⏰ Cloud Scheduler jobs"
    echo "  🔥 Firebase Functions"
    echo "  📊 App Engine application (if no other apps exist)"
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo ""
        log_error "⚠️  ENTIRE PROJECT WILL BE DELETED ⚠️"
        echo "This action is IRREVERSIBLE and will delete ALL resources in the project!"
    fi
    
    echo ""
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo ""
        log_error "FINAL WARNING: About to delete entire project $PROJECT_ID"
        read -p "Type the project ID to confirm deletion: " project_confirmation
        
        if [[ "$project_confirmation" != "$PROJECT_ID" ]]; then
            log_error "Project ID confirmation failed. Cleanup cancelled."
            exit 1
        fi
    fi
}

# Discover resources to clean up
discover_resources() {
    log_info "Discovering resources to clean up..."
    
    # Set project context
    gcloud config set project "$PROJECT_ID" --quiet
    
    # Discover Cloud SQL instances
    CLOUD_SQL_INSTANCES=($(gcloud sql instances list --format="value(name)" --filter="name~user-analytics" 2>/dev/null || echo ""))
    
    # Discover Cloud Tasks queues
    CLOUD_TASKS_QUEUES=($(gcloud tasks queues list --location="$REGION" --format="value(name)" --filter="name~user-lifecycle" 2>/dev/null || echo ""))
    
    # Discover Cloud Run services
    CLOUD_RUN_SERVICES=($(gcloud run services list --region="$REGION" --format="value(metadata.name)" --filter="metadata.name~lifecycle-worker" 2>/dev/null || echo ""))
    
    # Discover Cloud Scheduler jobs
    SCHEDULER_JOBS=($(gcloud scheduler jobs list --location="$REGION" --format="value(name)" --filter="name~engagement OR name~retention OR name~lifecycle" 2>/dev/null || echo ""))
    
    # Check for Firebase Functions
    FIREBASE_FUNCTIONS_EXIST=false
    if command -v firebase &> /dev/null; then
        if firebase functions:list --project="$PROJECT_ID" 2>/dev/null | grep -q "onUser"; then
            FIREBASE_FUNCTIONS_EXIST=true
        fi
    fi
    
    log_info "Resource discovery completed:"
    echo "  Cloud SQL instances: ${#CLOUD_SQL_INSTANCES[@]}"
    echo "  Cloud Tasks queues: ${#CLOUD_TASKS_QUEUES[@]}"
    echo "  Cloud Run services: ${#CLOUD_RUN_SERVICES[@]}"
    echo "  Scheduler jobs: ${#SCHEDULER_JOBS[@]}"
    echo "  Firebase Functions: $([ "$FIREBASE_FUNCTIONS_EXIST" = true ] && echo "Found" || echo "None")"
}

# Delete Firebase Functions
delete_firebase_functions() {
    if [[ "$FIREBASE_FUNCTIONS_EXIST" != "true" ]]; then
        log_info "No Firebase Functions to delete"
        return 0
    fi
    
    log_info "Deleting Firebase Functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Firebase Functions"
        return 0
    fi
    
    if command -v firebase &> /dev/null; then
        local functions=("onUserCreate" "onUserSignIn" "onUserDelete")
        
        for func in "${functions[@]}"; do
            log_info "Deleting function: $func"
            firebase functions:delete "$func" --project="$PROJECT_ID" --force 2>/dev/null || log_warning "Function $func may not exist"
        done
        
        log_success "Firebase Functions deleted"
    else
        log_warning "Firebase CLI not available, skipping function deletion"
    fi
}

# Delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    if [[ ${#SCHEDULER_JOBS[@]} -eq 0 ]]; then
        log_info "No Cloud Scheduler jobs to delete"
        return 0
    fi
    
    log_info "Deleting Cloud Scheduler jobs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete ${#SCHEDULER_JOBS[@]} scheduler jobs"
        return 0
    fi
    
    for job in "${SCHEDULER_JOBS[@]}"; do
        if [[ -n "$job" ]]; then
            log_info "Deleting scheduler job: $job"
            gcloud scheduler jobs delete "$job" --location="$REGION" --quiet || log_warning "Failed to delete job $job"
        fi
    done
    
    log_success "Cloud Scheduler jobs deleted"
}

# Delete Cloud Run services
delete_cloud_run_services() {
    if [[ ${#CLOUD_RUN_SERVICES[@]} -eq 0 ]]; then
        log_info "No Cloud Run services to delete"
        return 0
    fi
    
    log_info "Deleting Cloud Run services..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete ${#CLOUD_RUN_SERVICES[@]} Cloud Run services"
        return 0
    fi
    
    for service in "${CLOUD_RUN_SERVICES[@]}"; do
        if [[ -n "$service" ]]; then
            log_info "Deleting Cloud Run service: $service"
            gcloud run services delete "$service" --region="$REGION" --quiet || log_warning "Failed to delete service $service"
        fi
    done
    
    log_success "Cloud Run services deleted"
}

# Delete Cloud Tasks queues
delete_cloud_tasks_queues() {
    if [[ ${#CLOUD_TASKS_QUEUES[@]} -eq 0 ]]; then
        log_info "No Cloud Tasks queues to delete"
        return 0
    fi
    
    log_info "Deleting Cloud Tasks queues..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete ${#CLOUD_TASKS_QUEUES[@]} Cloud Tasks queues"
        return 0
    fi
    
    for queue in "${CLOUD_TASKS_QUEUES[@]}"; do
        if [[ -n "$queue" ]]; then
            # Extract queue name from full path
            local queue_name
            queue_name=$(basename "$queue")
            log_info "Deleting Cloud Tasks queue: $queue_name"
            gcloud tasks queues delete "$queue_name" --location="$REGION" --quiet || log_warning "Failed to delete queue $queue_name"
        fi
    done
    
    log_success "Cloud Tasks queues deleted"
}

# Delete Cloud SQL instances
delete_cloud_sql_instances() {
    if [[ ${#CLOUD_SQL_INSTANCES[@]} -eq 0 ]]; then
        log_info "No Cloud SQL instances to delete"
        return 0
    fi
    
    log_info "Deleting Cloud SQL instances..."
    log_warning "This operation may take several minutes..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete ${#CLOUD_SQL_INSTANCES[@]} Cloud SQL instances"
        return 0
    fi
    
    for instance in "${CLOUD_SQL_INSTANCES[@]}"; do
        if [[ -n "$instance" ]]; then
            log_info "Deleting Cloud SQL instance: $instance"
            
            # First, try to stop the instance to speed up deletion
            gcloud sql instances patch "$instance" --no-backup --quiet 2>/dev/null || true
            
            # Delete the instance
            gcloud sql instances delete "$instance" --quiet || log_warning "Failed to delete instance $instance"
        fi
    done
    
    log_success "Cloud SQL instances deleted"
}

# Delete App Engine application (optional, with warnings)
delete_app_engine() {
    log_info "Checking App Engine application..."
    
    if ! gcloud app describe &>/dev/null; then
        log_info "No App Engine application found"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would consider App Engine application deletion"
        return 0
    fi
    
    log_warning "App Engine application exists but cannot be deleted automatically"
    log_warning "If this App Engine app was created only for Cloud Tasks, you may want to disable it manually:"
    log_warning "https://console.cloud.google.com/appengine/settings?project=$PROJECT_ID"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local temporary files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    # Remove any temporary files that might have been created
    rm -f /tmp/schema.sql 2>/dev/null || true
    rm -rf /tmp/firebase-functions-* 2>/dev/null || true
    
    log_success "Local cleanup completed"
}

# Delete entire project (if requested)
delete_project() {
    if [[ "$DELETE_PROJECT" != "true" ]]; then
        return 0
    fi
    
    log_info "Deleting entire project: $PROJECT_ID"
    log_warning "This operation is IRREVERSIBLE!"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete project: $PROJECT_ID"
        return 0
    fi
    
    # Final safety check
    if [[ "$NON_INTERACTIVE" != "true" ]] && [[ "$FORCE_DELETE" != "true" ]]; then
        echo ""
        log_error "FINAL CONFIRMATION: Delete project $PROJECT_ID permanently?"
        read -p "Type 'DELETE' to confirm: " final_confirmation
        
        if [[ "$final_confirmation" != "DELETE" ]]; then
            log_error "Project deletion cancelled"
            exit 1
        fi
    fi
    
    gcloud projects delete "$PROJECT_ID" --quiet
    log_success "Project $PROJECT_ID has been deleted"
}

# Verify cleanup
verify_cleanup() {
    if [[ "$DELETE_PROJECT" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log_info "Verifying cleanup..."
    
    local remaining_resources=0
    
    # Check for remaining Cloud SQL instances
    local remaining_sql
    remaining_sql=$(gcloud sql instances list --format="value(name)" --filter="name~user-analytics" 2>/dev/null | wc -l)
    if [[ "$remaining_sql" -gt 0 ]]; then
        log_warning "⚠️ $remaining_sql Cloud SQL instances still exist"
        ((remaining_resources++))
    fi
    
    # Check for remaining Cloud Run services
    local remaining_run
    remaining_run=$(gcloud run services list --region="$REGION" --format="value(metadata.name)" --filter="metadata.name~lifecycle-worker" 2>/dev/null | wc -l)
    if [[ "$remaining_run" -gt 0 ]]; then
        log_warning "⚠️ $remaining_run Cloud Run services still exist"
        ((remaining_resources++))
    fi
    
    # Check for remaining Cloud Tasks queues
    local remaining_tasks
    remaining_tasks=$(gcloud tasks queues list --location="$REGION" --format="value(name)" --filter="name~user-lifecycle" 2>/dev/null | wc -l)
    if [[ "$remaining_tasks" -gt 0 ]]; then
        log_warning "⚠️ $remaining_tasks Cloud Tasks queues still exist"
        ((remaining_resources++))
    fi
    
    # Check for remaining Scheduler jobs
    local remaining_scheduler
    remaining_scheduler=$(gcloud scheduler jobs list --location="$REGION" --format="value(name)" --filter="name~engagement OR name~retention OR name~lifecycle" 2>/dev/null | wc -l)
    if [[ "$remaining_scheduler" -gt 0 ]]; then
        log_warning "⚠️ $remaining_scheduler Scheduler jobs still exist"
        ((remaining_resources++))
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
        log_success "✅ Cleanup verification completed - no resources remain"
    else
        log_warning "⚠️ Cleanup verification found $remaining_resources resource types that may need manual deletion"
        log_info "Check the Google Cloud Console for any remaining resources:"
        log_info "https://console.cloud.google.com/home/dashboard?project=$PROJECT_ID"
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    echo ""
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo -e "${GREEN}=================================================="
        echo "         PROJECT DELETION COMPLETED"
        echo "==================================================${NC}"
        echo ""
        echo "Project $PROJECT_ID has been permanently deleted."
        echo ""
        echo "All resources associated with this project have been removed."
        echo "This action cannot be undone."
    else
        echo -e "${GREEN}=================================================="
        echo "            CLEANUP COMPLETED"
        echo "==================================================${NC}"
        echo ""
        echo "Resources Cleaned Up:"
        echo "  🗄️  Cloud SQL instances: ${#CLOUD_SQL_INSTANCES[@]} deleted"
        echo "  📋 Cloud Tasks queues: ${#CLOUD_TASKS_QUEUES[@]} deleted"
        echo "  🏃 Cloud Run services: ${#CLOUD_RUN_SERVICES[@]} deleted"
        echo "  ⏰ Scheduler jobs: ${#SCHEDULER_JOBS[@]} deleted"
        echo "  🔥 Firebase Functions: $([ "$FIREBASE_FUNCTIONS_EXIST" = true ] && echo "Deleted" || echo "None found")"
        echo ""
        echo "Project $PROJECT_ID has been preserved."
        echo ""
        echo "Recommended next steps:"
        echo "  1. Review the Google Cloud Console for any remaining resources"
        echo "  2. Check billing reports to ensure no unexpected charges"
        echo "  3. Consider disabling unused APIs to reduce project clutter"
    fi
    echo ""
}

# Main cleanup workflow
main() {
    # Check prerequisites and get confirmation
    check_prerequisites
    discover_resources
    get_user_confirmation
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        # Delete entire project (includes all resources)
        delete_project
    else
        # Delete individual resources
        delete_firebase_functions
        delete_scheduler_jobs
        delete_cloud_run_services
        delete_cloud_tasks_queues
        delete_cloud_sql_instances
        delete_app_engine
        cleanup_local_files
        
        # Verify cleanup
        verify_cleanup
    fi
    
    # Show summary
    show_cleanup_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run completed - no actual resources were deleted"
    else
        log_success "User lifecycle management system cleanup completed!"
    fi
}

# Run main function with all arguments
main "$@"