#!/bin/bash

# Destroy script for GCP Security Compliance Monitoring with Security Command Center and Cloud Workflows
# This script removes all infrastructure created by the deploy.sh script
# WARNING: This will permanently delete all resources and data

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REGION="${REGION:-us-central1}"

# Check if running in dry-run mode
DRY_RUN="${DRY_RUN:-false}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_info "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Google Cloud CLI is not authenticated"
        log_info "Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to get project information
get_project_info() {
    log_info "Getting project information..."
    
    # Check if PROJECT_ID is provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID environment variable is not set"
        log_info "Usage: PROJECT_ID=your-project-id $0"
        log_info "Or run with interactive mode to select from available projects"
        
        # Interactive mode - list available projects
        local projects
        mapfile -t projects < <(gcloud projects list --filter="name~security-compliance" --format="value(projectId)" 2>/dev/null || true)
        
        if [[ ${#projects[@]} -eq 0 ]]; then
            log_error "No security compliance projects found"
            exit 1
        fi
        
        echo "Available security compliance projects:"
        for i in "${!projects[@]}"; do
            echo "$((i+1)). ${projects[i]}"
        done
        
        read -p "Select project number (1-${#projects[@]}): " selection
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#projects[@]} ]]; then
            export PROJECT_ID="${projects[$((selection-1))]}"
        else
            log_error "Invalid selection"
            exit 1
        fi
    fi
    
    # Verify project exists and we have access
    if ! gcloud projects describe "$PROJECT_ID" > /dev/null 2>&1; then
        log_error "Project $PROJECT_ID not found or no access"
        exit 1
    fi
    
    # Set project
    gcloud config set project "$PROJECT_ID"
    
    log_info "Project: $PROJECT_ID"
    log_success "Project information retrieved"
}

# Function to confirm destruction
confirm_destruction() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "Running in DRY RUN mode - no resources will be deleted"
        return 0
    fi
    
    log_warning "This will permanently delete ALL resources in project: $PROJECT_ID"
    log_warning "This action is IRREVERSIBLE and will result in DATA LOSS"
    
    echo "Resources that will be deleted:"
    echo "- Cloud Functions"
    echo "- Cloud Workflows"
    echo "- Pub/Sub topics and subscriptions"
    echo "- Security Command Center notifications"
    echo "- Log-based metrics"
    echo "- Monitoring dashboards"
    echo "- Entire Google Cloud project (if confirmed)"
    echo ""
    
    read -p "Are you sure you want to continue? (Type 'YES' to confirm): " confirmation
    
    if [[ "$confirmation" != "YES" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource destruction..."
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Cloud Functions"
        return 0
    fi
    
    # List and delete all Cloud Functions in the project
    local functions
    mapfile -t functions < <(gcloud functions list --gen2 --regions="$REGION" --format="value(name)" --project="$PROJECT_ID" 2>/dev/null || true)
    
    if [[ ${#functions[@]} -eq 0 ]]; then
        log_info "No Cloud Functions found to delete"
    else
        for function in "${functions[@]}"; do
            log_info "Deleting function: $function"
            if gcloud functions delete "$function" --gen2 --region="$REGION" --quiet --project="$PROJECT_ID"; then
                log_success "Deleted function: $function"
            else
                log_warning "Failed to delete function: $function"
            fi
        done
    fi
    
    log_success "Cloud Functions deletion completed"
}

# Function to delete Cloud Workflows
delete_workflows() {
    log_info "Deleting Cloud Workflows..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Cloud Workflows"
        return 0
    fi
    
    # List and delete all workflows
    local workflows
    mapfile -t workflows < <(gcloud workflows list --location="$REGION" --format="value(name)" --project="$PROJECT_ID" 2>/dev/null || true)
    
    if [[ ${#workflows[@]} -eq 0 ]]; then
        log_info "No workflows found to delete"
    else
        for workflow in "${workflows[@]}"; do
            # Extract just the workflow name from the full resource path
            local workflow_name
            workflow_name=$(basename "$workflow")
            
            log_info "Deleting workflow: $workflow_name"
            if gcloud workflows delete "$workflow_name" --location="$REGION" --quiet --project="$PROJECT_ID"; then
                log_success "Deleted workflow: $workflow_name"
            else
                log_warning "Failed to delete workflow: $workflow_name"
            fi
        done
    fi
    
    log_success "Workflows deletion completed"
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Pub/Sub resources"
        return 0
    fi
    
    # Delete subscriptions first (they depend on topics)
    local subscriptions
    mapfile -t subscriptions < <(gcloud pubsub subscriptions list --format="value(name)" --project="$PROJECT_ID" 2>/dev/null || true)
    
    for subscription in "${subscriptions[@]}"; do
        local subscription_name
        subscription_name=$(basename "$subscription")
        
        log_info "Deleting subscription: $subscription_name"
        if gcloud pubsub subscriptions delete "$subscription_name" --quiet --project="$PROJECT_ID"; then
            log_success "Deleted subscription: $subscription_name"
        else
            log_warning "Failed to delete subscription: $subscription_name"
        fi
    done
    
    # Delete topics
    local topics
    mapfile -t topics < <(gcloud pubsub topics list --format="value(name)" --project="$PROJECT_ID" 2>/dev/null || true)
    
    for topic in "${topics[@]}"; do
        local topic_name
        topic_name=$(basename "$topic")
        
        log_info "Deleting topic: $topic_name"
        if gcloud pubsub topics delete "$topic_name" --quiet --project="$PROJECT_ID"; then
            log_success "Deleted topic: $topic_name"
        else
            log_warning "Failed to delete topic: $topic_name"
        fi
    done
    
    log_success "Pub/Sub resources deletion completed"
}

# Function to delete Security Command Center notifications
delete_scc_notifications() {
    log_info "Deleting Security Command Center notifications..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete SCC notifications"
        return 0
    fi
    
    # Get organization ID
    local organization_id
    organization_id=$(gcloud organizations list --format="value(name)" --limit=1 2>/dev/null || echo "")
    
    if [[ -z "$organization_id" ]]; then
        log_info "No organization found, skipping SCC notification deletion"
        return 0
    fi
    
    # List and delete SCC notifications
    local notifications
    mapfile -t notifications < <(gcloud scc notifications list --organization="$organization_id" --format="value(name)" 2>/dev/null || true)
    
    for notification in "${notifications[@]}"; do
        if [[ "$notification" == *"security-findings"* ]]; then
            local notification_name
            notification_name=$(basename "$notification")
            
            log_info "Deleting SCC notification: $notification_name"
            if gcloud scc notifications delete "$notification_name" --organization="$organization_id" --quiet; then
                log_success "Deleted SCC notification: $notification_name"
            else
                log_warning "Failed to delete SCC notification: $notification_name"
            fi
        fi
    done
    
    log_success "SCC notifications deletion completed"
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log_info "Deleting monitoring resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete monitoring resources"
        return 0
    fi
    
    # Delete log-based metrics
    local metrics=("security_findings_processed" "workflow_executions")
    
    for metric in "${metrics[@]}"; do
        log_info "Deleting log-based metric: $metric"
        if gcloud logging metrics delete "$metric" --quiet --project="$PROJECT_ID" 2>/dev/null; then
            log_success "Deleted metric: $metric"
        else
            log_info "Metric $metric not found or already deleted"
        fi
    done
    
    # Delete dashboards (they'll be deleted with the project, but we can try to clean them up)
    local dashboards
    mapfile -t dashboards < <(gcloud monitoring dashboards list --format="value(name)" --project="$PROJECT_ID" 2>/dev/null || true)
    
    for dashboard in "${dashboards[@]}"; do
        if [[ "$dashboard" == *"Security Compliance Dashboard"* ]]; then
            local dashboard_name
            dashboard_name=$(basename "$dashboard")
            
            log_info "Deleting dashboard: $dashboard_name"
            if gcloud monitoring dashboards delete "$dashboard_name" --quiet --project="$PROJECT_ID" 2>/dev/null; then
                log_success "Deleted dashboard: $dashboard_name"
            else
                log_info "Dashboard not found or already deleted"
            fi
        fi
    done
    
    log_success "Monitoring resources deletion completed"
}

# Function to delete IAM resources
delete_iam_resources() {
    log_info "Deleting custom IAM resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete custom IAM resources"
        return 0
    fi
    
    # Custom IAM roles and service accounts will be deleted with the project
    # This function is a placeholder for any specific IAM cleanup needed
    
    log_success "IAM resources cleanup completed"
}

# Function to wait for resource deletion
wait_for_deletion() {
    log_info "Waiting for resources to be fully deleted..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would wait for resource deletion"
        return 0
    fi
    
    # Wait a bit for resources to be fully deleted
    sleep 30
    
    log_success "Resource deletion wait completed"
}

# Function to delete the entire project
delete_project() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete project: $PROJECT_ID"
        return 0
    fi
    
    log_warning "Final step: Deleting the entire project"
    log_warning "This will permanently delete ALL data and cannot be undone"
    
    read -p "Delete the entire project '$PROJECT_ID'? (Type 'DELETE-PROJECT' to confirm): " final_confirmation
    
    if [[ "$final_confirmation" != "DELETE-PROJECT" ]]; then
        log_info "Project deletion cancelled. Resources have been deleted but project remains."
        log_info "You can manually delete the project later if needed:"
        log_info "gcloud projects delete $PROJECT_ID"
        return 0
    fi
    
    log_info "Deleting project: $PROJECT_ID"
    
    if gcloud projects delete "$PROJECT_ID" --quiet; then
        log_success "Project deleted successfully: $PROJECT_ID"
        log_info "Note: Project deletion may take several minutes to complete fully"
    else
        log_error "Failed to delete project: $PROJECT_ID"
        log_info "You may need to delete it manually through the console"
        return 1
    fi
}

# Function to verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify deletion"
        return 0
    fi
    
    # Check if project still exists
    if gcloud projects describe "$PROJECT_ID" > /dev/null 2>&1; then
        log_info "Project still exists (resources deleted but project preserved)"
        
        # Verify individual resources are deleted
        local remaining_functions
        remaining_functions=$(gcloud functions list --gen2 --regions="$REGION" --format="value(name)" --project="$PROJECT_ID" 2>/dev/null | wc -l)
        
        local remaining_workflows
        remaining_workflows=$(gcloud workflows list --location="$REGION" --format="value(name)" --project="$PROJECT_ID" 2>/dev/null | wc -l)
        
        local remaining_topics
        remaining_topics=$(gcloud pubsub topics list --format="value(name)" --project="$PROJECT_ID" 2>/dev/null | wc -l)
        
        log_info "Remaining resources:"
        log_info "- Functions: $remaining_functions"
        log_info "- Workflows: $remaining_workflows"
        log_info "- Pub/Sub topics: $remaining_topics"
        
        if [[ $remaining_functions -eq 0 && $remaining_workflows -eq 0 && $remaining_topics -eq 0 ]]; then
            log_success "All main resources successfully deleted"
        else
            log_warning "Some resources may still exist"
        fi
    else
        log_success "Project completely deleted"
    fi
    
    log_success "Deletion verification completed"
}

# Function to display destruction summary
display_destruction_summary() {
    log_info "Destruction Summary"
    echo "=================================="
    echo "Project ID: $PROJECT_ID"
    echo "Timestamp: $(date)"
    echo "=================================="
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN completed - no actual resources were deleted"
    else
        log_info "Resources deleted:"
        echo "- Cloud Functions"
        echo "- Cloud Workflows"
        echo "- Pub/Sub topics and subscriptions"
        echo "- Security Command Center notifications"
        echo "- Log-based metrics"
        echo "- Monitoring dashboards"
        echo ""
        
        if gcloud projects describe "$PROJECT_ID" > /dev/null 2>&1; then
            log_info "Project $PROJECT_ID still exists (manual deletion required if desired)"
            echo "To delete the project manually:"
            echo "gcloud projects delete $PROJECT_ID"
        else
            log_info "Project $PROJECT_ID was completely deleted"
        fi
    fi
    
    echo ""
    log_success "Destruction process completed!"
}

# Function to handle cleanup errors
handle_cleanup_errors() {
    local exit_code=$?
    log_warning "Some cleanup operations may have failed (exit code: $exit_code)"
    log_info "This is often normal - some resources may not exist or may already be deleted"
    log_info "Please check the logs above for specific error details"
    return 0  # Don't exit with error for cleanup failures
}

# Main destruction function
main() {
    # Set up error handling for cleanup operations
    trap handle_cleanup_errors ERR
    
    log_info "Starting GCP Security Compliance Monitoring destruction"
    log_info "Script version: 1.0"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "Running in DRY RUN mode - no resources will be deleted"
    fi
    
    check_prerequisites
    get_project_info
    confirm_destruction
    
    # Delete resources in reverse dependency order
    delete_cloud_functions
    delete_workflows
    delete_pubsub_resources
    delete_scc_notifications
    delete_monitoring_resources
    delete_iam_resources
    
    wait_for_deletion
    verify_deletion
    
    # Optionally delete the entire project
    if [[ "${DELETE_PROJECT:-}" == "true" ]]; then
        delete_project
    fi
    
    display_destruction_summary
}

# Helper function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID          The Google Cloud project ID to destroy"
    echo "  DRY_RUN            Set to 'true' to preview actions without executing (default: false)"
    echo "  DELETE_PROJECT     Set to 'true' to delete the entire project (default: prompt)"
    echo "  REGION             The region where resources are deployed (default: us-central1)"
    echo ""
    echo "Examples:"
    echo "  PROJECT_ID=my-security-project $0"
    echo "  DRY_RUN=true PROJECT_ID=my-security-project $0"
    echo "  DELETE_PROJECT=true PROJECT_ID=my-security-project $0"
    echo ""
    echo "Interactive mode (will prompt for project selection):"
    echo "  $0"
}

# Check for help flag
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    show_usage
    exit 0
fi

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi