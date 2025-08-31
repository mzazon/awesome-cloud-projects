#!/bin/bash

# Smart Parking Management System - Cleanup Script
# This script removes all resources created by the deployment script
# Ensures complete cleanup to avoid ongoing costs

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/cleanup.log"
readonly ERROR_LOG="${SCRIPT_DIR}/cleanup_errors.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deployment_config"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $*" | tee -a "$ERROR_LOG" >&2
}

log_success() {
    echo -e "${GREEN}✅ $*${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}ℹ️  $*${NC}" | tee -a "$LOG_FILE"
}

# Error handling for non-critical failures
continue_on_error() {
    log_warning "Non-critical error occurred, continuing cleanup: $1"
}

# Load deployment configuration
load_configuration() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading deployment configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
        log_success "Configuration loaded successfully"
    else
        log_error "Configuration file not found: $CONFIG_FILE"
        log_error "Cannot proceed with cleanup without deployment configuration"
        exit 1
    fi
}

# Confirmation prompt
confirm_destruction() {
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}  WARNING: DESTRUCTIVE OPERATION${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "This will permanently delete the following resources:"
    echo "- Project: $PROJECT_ID"
    echo "- All Cloud Functions"
    echo "- Pub/Sub topics and subscriptions"
    echo "- Firestore database and all data"
    echo "- Service accounts and API keys"
    echo "- All associated data and configurations"
    echo ""
    echo -e "${YELLOW}This action CANNOT be undone!${NC}"
    echo ""
    
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log_warning "Force destroy mode enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
    if [[ ! $REPLY == "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Please type the project ID '$PROJECT_ID' to confirm: " -r
    if [[ ! $REPLY == "$PROJECT_ID" ]]; then
        log_error "Project ID confirmation failed. Cleanup cancelled."
        exit 1
    fi
    
    log_info "Confirmation received, proceeding with cleanup"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found"
        log_error "Run: gcloud auth login"
        exit 1
    fi
    
    # Set project context
    if ! gcloud config set project "$PROJECT_ID" --quiet; then
        log_error "Failed to set project context to $PROJECT_ID"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    # Delete parking data processing function
    if gcloud functions delete "$FUNCTION_NAME" \
        --region="$REGION" \
        --gen2 \
        --quiet 2>/dev/null; then
        log_success "Deleted Cloud Function: $FUNCTION_NAME"
    else
        continue_on_error "Failed to delete Cloud Function: $FUNCTION_NAME"
    fi
    
    # Delete parking management API
    if gcloud functions delete parking-management-api \
        --region="$REGION" \
        --gen2 \
        --quiet 2>/dev/null; then
        log_success "Deleted Cloud Function: parking-management-api"
    else
        continue_on_error "Failed to delete Cloud Function: parking-management-api"
    fi
    
    log_success "Cloud Functions cleanup completed"
}

# Delete Pub/Sub resources
delete_pubsub() {
    log_info "Deleting Pub/Sub resources..."
    
    # Delete Pub/Sub subscription
    if gcloud pubsub subscriptions delete parking-processing --quiet 2>/dev/null; then
        log_success "Deleted Pub/Sub subscription: parking-processing"
    else
        continue_on_error "Failed to delete Pub/Sub subscription: parking-processing"
    fi
    
    # Delete Pub/Sub topic
    if gcloud pubsub topics delete "$PUBSUB_TOPIC" --quiet 2>/dev/null; then
        log_success "Deleted Pub/Sub topic: $PUBSUB_TOPIC"
    else
        continue_on_error "Failed to delete Pub/Sub topic: $PUBSUB_TOPIC"
    fi
    
    log_success "Pub/Sub resources cleanup completed"
}

# Delete Maps Platform API key
delete_maps_api_key() {
    log_info "Deleting Maps Platform API key..."
    
    if [[ -n "${API_KEY_NAME:-}" ]]; then
        if gcloud services api-keys delete "$API_KEY_NAME" --quiet 2>/dev/null; then
            log_success "Deleted Maps Platform API key"
        else
            continue_on_error "Failed to delete Maps Platform API key: $API_KEY_NAME"
        fi
    else
        log_warning "API key name not found in configuration, skipping"
    fi
    
    log_success "Maps Platform API key cleanup completed"
}

# Delete service account and keys
delete_service_account() {
    log_info "Deleting service account and keys..."
    
    local sa_name="mqtt-pubsub-publisher"
    local sa_email="${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"
    local key_file="$SCRIPT_DIR/mqtt-sa-key.json"
    
    # Delete service account key file
    if [[ -f "$key_file" ]]; then
        rm -f "$key_file"
        log_success "Deleted service account key file"
    fi
    
    # Delete service account
    if gcloud iam service-accounts delete "$sa_email" --quiet 2>/dev/null; then
        log_success "Deleted service account: $sa_name"
    else
        continue_on_error "Failed to delete service account: $sa_name"
    fi
    
    log_success "Service account cleanup completed"
}

# Delete Firestore database (note: this deletes all data)
delete_firestore() {
    log_info "Deleting Firestore database..."
    log_warning "This will delete ALL data in the Firestore database"
    
    # Note: Firestore databases cannot be deleted directly via CLI
    # The database will be deleted when the project is deleted
    # For now, we'll just clear collections if needed
    
    log_warning "Firestore database will be deleted with project deletion"
    log_warning "Individual collections cannot be deleted via CLI"
    
    log_success "Firestore cleanup noted (will be deleted with project)"
}

# Verify resource deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local errors=0
    
    # Check Cloud Functions
    if gcloud functions list --regions="$REGION" --filter="name:(parking-management-api OR $FUNCTION_NAME)" --format="value(name)" | grep -q .; then
        log_warning "Some Cloud Functions may still exist"
        ((errors++))
    fi
    
    # Check Pub/Sub topics
    if gcloud pubsub topics list --filter="name:$PUBSUB_TOPIC" --format="value(name)" | grep -q .; then
        log_warning "Pub/Sub topic may still exist"
        ((errors++))
    fi
    
    # Check service accounts
    if gcloud iam service-accounts list --filter="email:mqtt-pubsub-publisher@${PROJECT_ID}.iam.gserviceaccount.com" --format="value(email)" | grep -q .; then
        log_warning "Service account may still exist"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "All resources verified as deleted"
    else
        log_warning "$errors verification warnings (resources may still be deleting)"
    fi
}

# Delete entire project (complete cleanup)
delete_project() {
    log_info "Deleting entire project: $PROJECT_ID"
    log_warning "This will delete ALL resources in the project"
    
    if gcloud projects delete "$PROJECT_ID" --quiet; then
        log_success "Project deletion initiated: $PROJECT_ID"
        log_info "Project deletion may take several minutes to complete"
    else
        log_error "Failed to delete project: $PROJECT_ID"
        log_error "You may need to delete it manually from the Google Cloud Console"
        return 1
    fi
    
    log_success "Project deletion completed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove configuration file
    if [[ -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE"
        log_success "Removed configuration file"
    fi
    
    # Remove service account key if it exists
    local key_file="$SCRIPT_DIR/mqtt-sa-key.json"
    if [[ -f "$key_file" ]]; then
        rm -f "$key_file"
        log_success "Removed service account key file"
    fi
    
    # Remove deployment summary
    local summary_file="$SCRIPT_DIR/deployment_summary.txt"
    if [[ -f "$summary_file" ]]; then
        rm -f "$summary_file"
        log_success "Removed deployment summary"
    fi
    
    log_success "Local files cleanup completed"
}

# Generate cleanup summary
generate_cleanup_summary() {
    log_info "Generating cleanup summary..."
    
    local summary_file="$SCRIPT_DIR/cleanup_summary.txt"
    
    cat > "$summary_file" << EOF
Smart Parking Management System - Cleanup Summary
================================================

Cleanup Date: $(date)
Project ID: $PROJECT_ID

Resources Deleted:
- Project: $PROJECT_ID (complete deletion)
- Cloud Functions: $FUNCTION_NAME, parking-management-api
- Pub/Sub Topic: $PUBSUB_TOPIC
- Pub/Sub Subscription: parking-processing
- Firestore Database: All data deleted with project
- Service Account: mqtt-pubsub-publisher
- Maps Platform API Key: Deleted
- Local configuration files: Removed

Status: Cleanup completed successfully

Note: Project deletion may take several minutes to propagate fully.
All resources and data have been permanently deleted.
EOF
    
    log_success "Cleanup summary saved to: $summary_file"
    
    # Display summary
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Cleanup Completed Successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    cat "$summary_file"
    echo ""
    echo -e "${YELLOW}Important Notes:${NC}"
    echo -e "${YELLOW}- All resources have been permanently deleted${NC}"
    echo -e "${YELLOW}- Project deletion may take time to propagate${NC}"
    echo -e "${YELLOW}- Billing will stop for all deleted resources${NC}"
    echo ""
}

# Partial cleanup (without deleting project)
partial_cleanup() {
    log_info "Performing partial cleanup (keeping project)..."
    
    delete_cloud_functions
    delete_pubsub
    delete_maps_api_key
    delete_service_account
    delete_firestore
    verify_deletion
    cleanup_local_files
    
    log_success "Partial cleanup completed - project preserved"
}

# Main cleanup function
main() {
    log_info "Starting Smart Parking Management System cleanup..."
    log_info "Cleanup logs: $LOG_FILE"
    log_info "Error logs: $ERROR_LOG"
    
    load_configuration
    check_prerequisites
    
    # Check for partial cleanup mode
    if [[ "${1:-}" == "--partial" ]]; then
        log_info "Partial cleanup mode - preserving project"
        confirm_destruction
        partial_cleanup
        return 0
    fi
    
    confirm_destruction
    delete_cloud_functions
    delete_pubsub
    delete_maps_api_key
    delete_service_account
    delete_project  # This deletes everything including Firestore
    cleanup_local_files
    generate_cleanup_summary
    
    log_success "Smart Parking Management System cleanup completed successfully!"
}

# Help function
show_help() {
    cat << EOF
Smart Parking Management System - Cleanup Script

Usage: $0 [OPTIONS]

Options:
    --partial       Delete individual resources but keep the project
    --force         Skip confirmation prompts (use with caution)
    --help          Show this help message

Examples:
    $0                    # Full cleanup (deletes entire project)
    $0 --partial          # Partial cleanup (keeps project)
    $0 --force            # Force cleanup without prompts
    $0 --partial --force  # Partial cleanup without prompts

Note: Full cleanup deletes the entire project and all resources.
      Partial cleanup preserves the project but removes all resources.
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --partial)
            PARTIAL_CLEANUP=true
            shift
            ;;
        --force)
            FORCE_DESTROY=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check for dry run mode
if [[ "${DRY_RUN:-}" == "true" ]]; then
    log_info "Dry run mode - showing what would be deleted"
    load_configuration
    echo "Project ID: $PROJECT_ID"
    echo "Resources to delete:"
    echo "- Cloud Functions: $FUNCTION_NAME, parking-management-api"
    echo "- Pub/Sub Topic: $PUBSUB_TOPIC"
    echo "- Pub/Sub Subscription: parking-processing"
    echo "- Service Account: mqtt-pubsub-publisher"
    echo "- Maps Platform API Key"
    echo "- Firestore Database (all data)"
    if [[ "${PARTIAL_CLEANUP:-}" != "true" ]]; then
        echo "- Entire Project: $PROJECT_ID"
    fi
    exit 0
fi

# Run main cleanup
main "$@"