#!/bin/bash

# GCP Personal Productivity Assistant with Gemini and Functions - Cleanup Script
# This script safely removes all resources created for the personal productivity assistant,
# including Cloud Functions, Pub/Sub resources, Firestore database, and optional project deletion.

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values (can be overridden via environment variables)
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
DELETE_PROJECT="${DELETE_PROJECT:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

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

# Function to check if required commands exist
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_commands=()
    
    # Check for required CLI tools
    for cmd in gcloud; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_error "Please install the missing commands and run this script again."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found."
        log_error "Please run 'gcloud auth login' to authenticate."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Function to detect project ID if not provided
detect_project_id() {
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)
        
        if [ -z "$PROJECT_ID" ]; then
            log_error "Project ID not provided and cannot be detected from gcloud config."
            log_error "Please provide PROJECT_ID environment variable or use --project-id flag."
            exit 1
        fi
        
        log_info "Using detected project ID: $PROJECT_ID"
    fi
}

# Function to validate project and resources
validate_project() {
    log_info "Validating project and resources..."
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_error "Project $PROJECT_ID does not exist or is not accessible."
        exit 1
    fi
    
    # Set project context
    gcloud config set project "$PROJECT_ID"
    
    log_success "Project validation completed"
}

# Function to list resources that will be deleted
list_resources_to_delete() {
    log_info "Scanning for resources to delete in project: $PROJECT_ID"
    echo
    
    local resources_found=false
    
    # Check Cloud Functions
    echo "Cloud Functions:"
    local functions
    functions=$(gcloud functions list --region="$REGION" --format="value(name)" 2>/dev/null | grep -E "(email-processor|scheduled-email-processor)" || true)
    if [ -n "$functions" ]; then
        while IFS= read -r func; do
            echo "  - $func (region: $REGION)"
            resources_found=true
        done <<< "$functions"
    else
        echo "  - None found"
    fi
    
    # Check Cloud Scheduler jobs
    echo "Cloud Scheduler Jobs:"
    local scheduler_jobs
    scheduler_jobs=$(gcloud scheduler jobs list --location="$REGION" --format="value(name)" 2>/dev/null | grep "email-processing-schedule" || true)
    if [ -n "$scheduler_jobs" ]; then
        while IFS= read -r job; do
            echo "  - $job (location: $REGION)"
            resources_found=true
        done <<< "$scheduler_jobs"
    else
        echo "  - None found"
    fi
    
    # Check Pub/Sub resources
    echo "Pub/Sub Resources:"
    local pubsub_subscriptions
    pubsub_subscriptions=$(gcloud pubsub subscriptions list --format="value(name)" 2>/dev/null | grep "email-processing-sub" || true)
    if [ -n "$pubsub_subscriptions" ]; then
        while IFS= read -r sub; do
            echo "  - Subscription: $(basename "$sub")"
            resources_found=true
        done <<< "$pubsub_subscriptions"
    fi
    
    local pubsub_topics
    pubsub_topics=$(gcloud pubsub topics list --format="value(name)" 2>/dev/null | grep "email-processing-topic" || true)
    if [ -n "$pubsub_topics" ]; then
        while IFS= read -r topic; do
            echo "  - Topic: $(basename "$topic")"
            resources_found=true
        done <<< "$pubsub_topics"
    fi
    
    if [ -z "$pubsub_subscriptions" ] && [ -z "$pubsub_topics" ]; then
        echo "  - None found"
    fi
    
    # Check Firestore database
    echo "Firestore Database:"
    if gcloud firestore databases describe --database="(default)" &>/dev/null; then
        echo "  - Default database (WARNING: This will delete ALL data)"
        resources_found=true
    else
        echo "  - None found"
    fi
    
    # Check local files
    echo "Local Files:"
    local credentials_dir="$HOME/productivity-assistant"
    if [ -d "$credentials_dir" ]; then
        echo "  - $credentials_dir (OAuth credentials and local files)"
        resources_found=true
    else
        echo "  - None found"
    fi
    
    if [ "$DELETE_PROJECT" = "true" ]; then
        echo "Project:"
        echo "  - $PROJECT_ID (COMPLETE PROJECT DELETION)"
        resources_found=true
    fi
    
    echo
    
    if [ "$resources_found" = "false" ]; then
        log_warning "No productivity assistant resources found to delete."
        return 1
    fi
    
    return 0
}

# Function to confirm deletion
confirm_deletion() {
    if [ "$SKIP_CONFIRMATION" = "true" ]; then
        return 0
    fi
    
    echo
    log_warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo
    echo "This script will permanently delete the resources listed above."
    
    if [ "$DELETE_PROJECT" = "true" ]; then
        echo
        log_error "🚨 PROJECT DELETION ENABLED 🚨"
        echo "The ENTIRE project '$PROJECT_ID' will be PERMANENTLY DELETED."
        echo "This action CANNOT be undone and will delete ALL resources in the project."
    fi
    
    echo
    echo "Firestore database deletion will remove ALL stored data including:"
    echo "  - Email analysis results"
    echo "  - Action items and tasks"
    echo "  - User preferences and settings"
    echo "  - All collections and documents"
    
    echo
    read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    echo
    read -p "Last chance! Type 'CONFIRM' to proceed with deletion: " final_confirmation
    
    if [ "$final_confirmation" != "CONFIRM" ]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_warning "Proceeding with resource deletion..."
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    local functions_to_delete=("email-processor" "scheduled-email-processor")
    
    for func in "${functions_to_delete[@]}"; do
        if gcloud functions describe "$func" --region="$REGION" &>/dev/null; then
            log_info "Deleting function: $func"
            gcloud functions delete "$func" \
                --region="$REGION" \
                --quiet
            log_success "Deleted function: $func"
        else
            log_info "Function $func not found, skipping"
        fi
    done
    
    log_success "Cloud Functions cleanup completed"
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log_info "Deleting Cloud Scheduler jobs..."
    
    local job_name="email-processing-schedule"
    
    if gcloud scheduler jobs describe "$job_name" --location="$REGION" &>/dev/null; then
        log_info "Deleting scheduler job: $job_name"
        gcloud scheduler jobs delete "$job_name" \
            --location="$REGION" \
            --quiet
        log_success "Deleted scheduler job: $job_name"
    else
        log_info "Scheduler job $job_name not found, skipping"
    fi
    
    log_success "Cloud Scheduler cleanup completed"
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."
    
    local subscription_name="email-processing-sub"
    local topic_name="email-processing-topic"
    
    # Delete subscription first
    if gcloud pubsub subscriptions describe "$subscription_name" &>/dev/null; then
        log_info "Deleting Pub/Sub subscription: $subscription_name"
        gcloud pubsub subscriptions delete "$subscription_name" --quiet
        log_success "Deleted subscription: $subscription_name"
    else
        log_info "Subscription $subscription_name not found, skipping"
    fi
    
    # Delete topic
    if gcloud pubsub topics describe "$topic_name" &>/dev/null; then
        log_info "Deleting Pub/Sub topic: $topic_name"
        gcloud pubsub topics delete "$topic_name" --quiet
        log_success "Deleted topic: $topic_name"
    else
        log_info "Topic $topic_name not found, skipping"
    fi
    
    log_success "Pub/Sub resources cleanup completed"
}

# Function to delete Firestore database
delete_firestore_database() {
    log_info "Deleting Firestore database..."
    
    if gcloud firestore databases describe --database="(default)" &>/dev/null; then
        log_warning "Deleting Firestore database - this will remove ALL data!"
        
        # Note: Firestore database deletion is not directly supported via CLI
        # We'll delete collections instead or inform user about manual deletion
        log_warning "Firestore database deletion requires manual action:"
        log_warning "1. Go to: https://console.cloud.google.com/firestore/data?project=$PROJECT_ID"
        log_warning "2. Delete all collections manually, or"
        log_warning "3. Delete the entire project to remove the database"
        
        # Attempt to delete known collections
        local collections=("email_analysis" "scheduled_runs")
        for collection in "${collections[@]}"; do
            log_info "Attempting to clear collection: $collection"
            # This would require additional tooling to properly delete collections
            # For now, we'll just inform the user
        done
        
        log_warning "Firestore database requires manual cleanup or project deletion"
    else
        log_info "Firestore database not found, skipping"
    fi
}

# Function to clean up local files
delete_local_files() {
    log_info "Cleaning up local files..."
    
    local credentials_dir="$HOME/productivity-assistant"
    
    if [ -d "$credentials_dir" ]; then
        log_info "Deleting local directory: $credentials_dir"
        rm -rf "$credentials_dir"
        log_success "Deleted local directory: $credentials_dir"
    else
        log_info "Local directory $credentials_dir not found, skipping"
    fi
    
    log_success "Local files cleanup completed"
}

# Function to delete the entire project
delete_project() {
    if [ "$DELETE_PROJECT" != "true" ]; then
        return 0
    fi
    
    log_warning "Deleting entire project: $PROJECT_ID"
    
    # Final confirmation for project deletion
    echo
    log_error "🚨 FINAL PROJECT DELETION WARNING 🚨"
    echo "You are about to delete the ENTIRE project: $PROJECT_ID"
    echo "This will delete ALL resources, data, and configuration."
    echo "This action CANNOT be undone."
    echo
    read -p "Type the project ID '$PROJECT_ID' to confirm project deletion: " project_confirmation
    
    if [ "$project_confirmation" != "$PROJECT_ID" ]; then
        log_error "Project ID confirmation failed. Project deletion cancelled."
        return 1
    fi
    
    log_info "Deleting project: $PROJECT_ID"
    gcloud projects delete "$PROJECT_ID" --quiet
    
    log_success "Project deletion initiated: $PROJECT_ID"
    log_warning "Project deletion may take several minutes to complete."
}

# Function to verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local remaining_resources=()
    
    # Check for remaining functions
    local remaining_functions
    remaining_functions=$(gcloud functions list --region="$REGION" --format="value(name)" 2>/dev/null | grep -E "(email-processor|scheduled-email-processor)" || true)
    if [ -n "$remaining_functions" ]; then
        remaining_resources+=("Cloud Functions: $remaining_functions")
    fi
    
    # Check for remaining scheduler jobs
    local remaining_jobs
    remaining_jobs=$(gcloud scheduler jobs list --location="$REGION" --format="value(name)" 2>/dev/null | grep "email-processing-schedule" || true)
    if [ -n "$remaining_jobs" ]; then
        remaining_resources+=("Scheduler Jobs: $remaining_jobs")
    fi
    
    # Check for remaining Pub/Sub resources
    local remaining_subscriptions
    remaining_subscriptions=$(gcloud pubsub subscriptions list --format="value(name)" 2>/dev/null | grep "email-processing-sub" || true)
    if [ -n "$remaining_subscriptions" ]; then
        remaining_resources+=("Pub/Sub Subscriptions: $remaining_subscriptions")
    fi
    
    local remaining_topics
    remaining_topics=$(gcloud pubsub topics list --format="value(name)" 2>/dev/null | grep "email-processing-topic" || true)
    if [ -n "$remaining_topics" ]; then
        remaining_resources+=("Pub/Sub Topics: $remaining_topics")
    fi
    
    if [ ${#remaining_resources[@]} -ne 0 ]; then
        log_warning "Some resources may still exist:"
        for resource in "${remaining_resources[@]}"; do
            log_warning "  - $resource"
        done
        log_warning "These may take a few moments to be fully deleted."
    else
        log_success "All targeted resources have been successfully deleted"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo
    log_success "🧹 Cleanup completed!"
    echo
    echo "Cleanup Summary:"
    echo "================"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo
    echo "Resources Processed:"
    echo "- ✅ Cloud Functions (email-processor, scheduled-email-processor)"
    echo "- ✅ Cloud Scheduler Jobs (email-processing-schedule)"
    echo "- ✅ Pub/Sub Resources (topic, subscription)"
    echo "- ⚠️  Firestore Database (requires manual cleanup)"
    echo "- ✅ Local Files (OAuth credentials)"
    
    if [ "$DELETE_PROJECT" = "true" ]; then
        echo "- 🚨 Project Deletion (initiated)"
        echo
        log_warning "Project deletion is in progress and may take several minutes."
        log_warning "All remaining resources will be automatically deleted with the project."
    else
        echo
        log_info "Project '$PROJECT_ID' was preserved."
        log_info "To delete the project later, run: gcloud projects delete $PROJECT_ID"
    fi
    
    echo
    echo "Manual Actions Required:"
    echo "- Firestore database cleanup (if project not deleted)"
    echo "- Review billing for any remaining charges"
    echo "- Remove OAuth credentials from Google Console (if no longer needed)"
    echo
    echo "For more information:"
    echo "- https://cloud.google.com/resource-manager/docs/creating-managing-projects#shutting_down_projects"
}

# Main cleanup function
main() {
    log_info "Starting GCP Personal Productivity Assistant cleanup..."
    echo
    
    # Run cleanup steps
    check_prerequisites
    detect_project_id
    validate_project
    
    # List resources and confirm deletion
    if ! list_resources_to_delete; then
        log_info "No resources to clean up. Exiting."
        exit 0
    fi
    
    confirm_deletion
    
    # Perform cleanup in reverse order of creation
    delete_cloud_functions
    delete_scheduler_jobs
    delete_pubsub_resources
    delete_firestore_database
    delete_local_files
    delete_project
    
    # Verify and summarize
    if [ "$DELETE_PROJECT" != "true" ]; then
        verify_deletion
    fi
    
    display_cleanup_summary
    
    log_success "Cleanup process completed! 🗑️"
}

# Handle script interruption
trap 'log_error "Cleanup interrupted"; exit 1' INT TERM

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --delete-project)
            DELETE_PROJECT="true"
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --project-id ID          GCP Project ID (default: auto-detect)"
            echo "  --region REGION          GCP Region (default: us-central1)"
            echo "  --delete-project         Delete the entire project (DESTRUCTIVE)"
            echo "  --skip-confirmation      Skip interactive confirmation prompts"
            echo "  --help                   Show this help message"
            echo
            echo "Environment Variables:"
            echo "  PROJECT_ID               GCP Project ID"
            echo "  REGION                   GCP Region"
            echo "  DELETE_PROJECT           Set to 'true' to delete project"
            echo "  SKIP_CONFIRMATION        Set to 'true' to skip prompts"
            echo
            echo "Examples:"
            echo "  $0                                    # Interactive cleanup"
            echo "  $0 --project-id my-project           # Cleanup specific project"
            echo "  $0 --delete-project                  # Delete entire project"
            echo "  $0 --skip-confirmation               # Non-interactive cleanup"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            log_error "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main cleanup
main "$@"