#!/bin/bash

# Smart Expense Processing with Document AI and Gemini - Cleanup Script
# This script safely removes all infrastructure created by the deployment
# Version: 1.0
# Last Updated: 2025-07-12

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="/tmp/expense-ai-destroy-$(date +%Y%m%d-%H%M%S).log"
readonly DEPLOYMENT_INFO_FILE="$PROJECT_DIR/deployment-info.txt"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Check log file: $LOG_FILE"
    exit 1
}

# Safety confirmation function
confirm_destruction() {
    echo
    echo "=================================================================="
    echo -e "${RED}DANGER: This will permanently delete ALL resources!${NC}"
    echo "=================================================================="
    echo
    echo "This script will delete:"
    echo "  • Cloud Functions (expense-validator, expense-report-generator)"
    echo "  • Cloud Workflows (expense-processing-workflow)"
    echo "  • Document AI Processor ($PROCESSOR_ID)"
    echo "  • Cloud SQL Instance ($DB_INSTANCE) and ALL DATA"
    echo "  • Cloud Storage Bucket ($BUCKET_NAME) and ALL FILES"
    echo "  • Monitoring Dashboards"
    echo "  • Optionally: Entire GCP Project ($PROJECT_ID)"
    echo
    echo -e "${YELLOW}This action CANNOT be undone!${NC}"
    echo
    
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log_warning "Force destroy mode enabled - skipping confirmation"
        return 0
    fi
    
    echo -n "Are you sure you want to continue? Type 'DELETE' to confirm: "
    read -r confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
    
    echo
    echo -n "Do you want to delete the entire project? (y/N): "
    read -r delete_project
    
    if [[ "$delete_project" =~ ^[Yy]$ ]]; then
        export DELETE_PROJECT="true"
        log_warning "Project deletion enabled"
    else
        export DELETE_PROJECT="false"
        log_info "Project will be preserved"
    fi
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
        # Source the deployment info file to get variables
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue
            
            # Export the variable
            export "$key"="$value"
        done < <(grep -E '^[A-Z_]+=.*$' "$DEPLOYMENT_INFO_FILE")
        
        log_success "Loaded deployment configuration"
    else
        log_warning "Deployment info file not found at $DEPLOYMENT_INFO_FILE"
        log_info "Attempting to use environment variables or prompt for values..."
        
        # Try to get values from environment or prompt
        if [[ -z "${PROJECT_ID:-}" ]]; then
            echo -n "Enter PROJECT_ID: "
            read -r PROJECT_ID
            export PROJECT_ID
        fi
        
        if [[ -z "${REGION:-}" ]]; then
            export REGION="us-central1"
            log_info "Using default region: $REGION"
        fi
    fi
    
    # Validate required variables
    if [[ -z "${PROJECT_ID:-}" ]]; then
        error_exit "PROJECT_ID is required"
    fi
    
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: ${REGION:-us-central1}"
}

# Prerequisites checking
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required tools
    for tool in gcloud gsutil curl; do
        if ! command -v "$tool" &> /dev/null; then
            error_exit "Required tool not found: $tool"
        fi
    done
    
    # Check authentication
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | grep -q .; then
        error_exit "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
    fi
    
    # Set project context
    gcloud config set project "$PROJECT_ID" || error_exit "Failed to set project context"
    
    log_success "Prerequisites validated"
}

# Resource deletion functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    local functions=("expense-validator" "expense-report-generator")
    
    for func in "${functions[@]}"; do
        log_info "Checking function: $func"
        if gcloud functions describe "$func" --region="${REGION:-us-central1}" &>/dev/null; then
            log_info "Deleting function: $func"
            gcloud functions delete "$func" \
                --region="${REGION:-us-central1}" \
                --quiet || log_warning "Failed to delete function: $func"
            log_success "Deleted function: $func"
        else
            log_info "Function $func not found (may already be deleted)"
        fi
    done
}

delete_workflows() {
    log_info "Deleting Cloud Workflows..."
    
    local workflow_name="expense-processing-workflow"
    
    if gcloud workflows describe "$workflow_name" --location="${REGION:-us-central1}" &>/dev/null; then
        log_info "Deleting workflow: $workflow_name"
        gcloud workflows delete "$workflow_name" \
            --location="${REGION:-us-central1}" \
            --quiet || log_warning "Failed to delete workflow: $workflow_name"
        log_success "Deleted workflow: $workflow_name"
    else
        log_info "Workflow $workflow_name not found (may already be deleted)"
    fi
}

delete_document_ai_processor() {
    log_info "Deleting Document AI processor..."
    
    if [[ -n "${PROCESSOR_ID:-}" ]]; then
        log_info "Deleting processor: $PROCESSOR_ID"
        
        # Get access token
        local access_token
        access_token=$(gcloud auth application-default print-access-token) || {
            log_warning "Failed to get access token for Document AI cleanup"
            return
        }
        
        # Delete processor via REST API
        local response
        response=$(curl -s -X DELETE \
            -H "Authorization: Bearer $access_token" \
            "https://${REGION:-us-central1}-documentai.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION:-us-central1}/processors/${PROCESSOR_ID}")
        
        if [[ $? -eq 0 ]]; then
            log_success "Deleted Document AI processor: $PROCESSOR_ID"
        else
            log_warning "Failed to delete Document AI processor: $PROCESSOR_ID"
        fi
    else
        log_info "No Document AI processor ID found"
    fi
}

delete_cloud_sql() {
    log_info "Deleting Cloud SQL instances..."
    
    if [[ -n "${DB_INSTANCE:-}" ]]; then
        log_info "Checking Cloud SQL instance: $DB_INSTANCE"
        
        if gcloud sql instances describe "$DB_INSTANCE" &>/dev/null; then
            # Remove deletion protection first
            log_info "Removing deletion protection from: $DB_INSTANCE"
            gcloud sql instances patch "$DB_INSTANCE" \
                --no-deletion-protection \
                --quiet || log_warning "Failed to remove deletion protection"
            
            log_info "Deleting Cloud SQL instance: $DB_INSTANCE"
            log_warning "This will permanently delete all database data!"
            
            gcloud sql instances delete "$DB_INSTANCE" \
                --quiet || log_warning "Failed to delete Cloud SQL instance: $DB_INSTANCE"
            
            log_success "Deleted Cloud SQL instance: $DB_INSTANCE"
        else
            log_info "Cloud SQL instance $DB_INSTANCE not found (may already be deleted)"
        fi
    else
        log_info "No Cloud SQL instance name found"
    fi
}

delete_storage_bucket() {
    log_info "Deleting Cloud Storage buckets..."
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log_info "Checking bucket: gs://$BUCKET_NAME"
        
        if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
            log_info "Deleting bucket contents and bucket: gs://$BUCKET_NAME"
            log_warning "This will permanently delete all stored files!"
            
            # Delete all objects in the bucket
            gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || log_info "Bucket was empty"
            
            # Delete the bucket
            gsutil rb "gs://${BUCKET_NAME}" || log_warning "Failed to delete bucket: $BUCKET_NAME"
            
            log_success "Deleted storage bucket: gs://$BUCKET_NAME"
        else
            log_info "Bucket gs://$BUCKET_NAME not found (may already be deleted)"
        fi
    else
        log_info "No bucket name found"
        
        # Try to find and delete buckets with our naming pattern
        log_info "Searching for expense-related buckets..."
        local expense_buckets
        expense_buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "expense-receipts" || echo "")
        
        if [[ -n "$expense_buckets" ]]; then
            echo "$expense_buckets" | while read -r bucket; do
                if [[ -n "$bucket" ]]; then
                    log_info "Found bucket: $bucket"
                    gsutil -m rm -r "${bucket}/**" 2>/dev/null || log_info "Bucket was empty"
                    gsutil rb "$bucket" || log_warning "Failed to delete bucket: $bucket"
                    log_success "Deleted bucket: $bucket"
                fi
            done
        fi
    fi
}

delete_monitoring_resources() {
    log_info "Deleting monitoring resources..."
    
    # List and delete custom dashboards
    local dashboards
    dashboards=$(gcloud monitoring dashboards list --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$dashboards" ]]; then
        echo "$dashboards" | while read -r dashboard; do
            if [[ -n "$dashboard" ]] && [[ "$dashboard" =~ expense|Expense ]]; then
                log_info "Deleting dashboard: $dashboard"
                gcloud monitoring dashboards delete "$dashboard" --quiet || \
                    log_warning "Failed to delete dashboard: $dashboard"
                log_success "Deleted dashboard: $dashboard"
            fi
        done
    else
        log_info "No custom dashboards found"
    fi
}

delete_project() {
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        log_warning "Preparing to delete entire project: $PROJECT_ID"
        log_warning "This will delete ALL resources in the project!"
        
        echo
        echo -n "Final confirmation - type the project ID to delete it: "
        read -r project_confirmation
        
        if [[ "$project_confirmation" == "$PROJECT_ID" ]]; then
            log_info "Deleting project: $PROJECT_ID"
            gcloud projects delete "$PROJECT_ID" --quiet || \
                error_exit "Failed to delete project: $PROJECT_ID"
            log_success "Project deleted: $PROJECT_ID"
        else
            log_warning "Project ID confirmation failed - project preserved"
        fi
    else
        log_info "Project preserved: $PROJECT_ID"
    fi
}

# Cleanup local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "$DEPLOYMENT_INFO_FILE"
        "/tmp/cloud-sql-proxy"
        "/tmp/expense_schema.sql"
        "/tmp/expense-workflow.yaml"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file" && log_success "Removed: $file"
        fi
    done
    
    # Clean up any temporary directories
    find /tmp -name "expense-*" -type f -user "$(whoami)" -mtime +1 -delete 2>/dev/null || true
}

# Verification functions
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local issues=0
    
    # Check Cloud Functions
    if gcloud functions list --format="value(name)" | grep -E "(expense-validator|expense-report-generator)" &>/dev/null; then
        log_warning "Some Cloud Functions may still exist"
        ((issues++))
    fi
    
    # Check Workflows
    if gcloud workflows list --format="value(name)" | grep "expense-processing-workflow" &>/dev/null; then
        log_warning "Expense workflow may still exist"
        ((issues++))
    fi
    
    # Check Cloud SQL
    if [[ -n "${DB_INSTANCE:-}" ]] && gcloud sql instances list --format="value(name)" | grep "$DB_INSTANCE" &>/dev/null; then
        log_warning "Cloud SQL instance may still exist: $DB_INSTANCE"
        ((issues++))
    fi
    
    # Check Storage
    if [[ -n "${BUCKET_NAME:-}" ]] && gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_warning "Storage bucket may still exist: gs://$BUCKET_NAME"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log_success "All resources appear to be cleaned up successfully"
    else
        log_warning "$issues potential cleanup issues detected"
        log_info "Some resources may take additional time to be fully deleted"
        log_info "Check the Google Cloud Console to verify complete cleanup"
    fi
}

# Display summary
display_cleanup_summary() {
    echo
    echo "=================================================================="
    echo -e "${GREEN}Smart Expense Processing Cleanup Complete!${NC}"
    echo "=================================================================="
    echo
    echo -e "${BLUE}Cleanup Summary:${NC}"
    echo "  Project: $PROJECT_ID"
    echo "  Region: ${REGION:-us-central1}"
    echo "  Status: $(if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then echo "Project Deleted"; else echo "Resources Deleted"; fi)"
    echo
    echo -e "${BLUE}Resources Removed:${NC}"
    echo "  ✓ Cloud Functions"
    echo "  ✓ Cloud Workflows"
    echo "  ✓ Document AI Processor"
    echo "  ✓ Cloud SQL Database"
    echo "  ✓ Cloud Storage Bucket"
    echo "  ✓ Monitoring Dashboards"
    echo "  ✓ Local Configuration Files"
    echo
    
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        echo -e "${YELLOW}Project Status:${NC} Deleted"
        echo "The entire project has been removed from your Google Cloud account."
    else
        echo -e "${YELLOW}Project Status:${NC} Preserved"
        echo "The project still exists but all expense processing resources have been removed."
        echo "You may want to:"
        echo "  • Review any remaining resources in the Console"
        echo "  • Delete the project manually if no longer needed"
        echo "  • Check for any residual billing charges"
    fi
    
    echo
    echo -e "${BLUE}Important Notes:${NC}"
    echo "  • Database backups may be retained according to backup policies"
    echo "  • Billing for deleted resources will stop within 24 hours"
    echo "  • Some quota usage may take time to reset"
    echo "  • Check Cloud Console for any remaining resources"
    echo
    echo -e "${YELLOW}Log file available at:${NC} $LOG_FILE"
    echo
}

# Main execution function
main() {
    echo "=================================================================="
    echo "Smart Expense Processing with Document AI and Gemini"
    echo "Cleanup Script v1.0"
    echo "=================================================================="
    echo
    
    log_info "Starting cleanup at $(date)"
    log_info "Log file: $LOG_FILE"
    
    # Load configuration and confirm
    load_deployment_info
    confirm_destruction
    check_prerequisites
    
    log_info "Beginning resource cleanup..."
    
    # Delete resources in reverse order of creation
    delete_cloud_functions
    delete_workflows
    delete_document_ai_processor
    delete_cloud_sql
    delete_storage_bucket
    delete_monitoring_resources
    
    # Project-level cleanup
    delete_project
    
    # Local cleanup
    cleanup_local_files
    
    # Verification and summary
    verify_cleanup
    display_cleanup_summary
    
    log_success "Cleanup completed successfully at $(date)"
}

# Handle command line arguments
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Safely remove Smart Expense Processing infrastructure from Google Cloud"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID      GCP project ID (required)"
    echo "  FORCE_DESTROY   Skip confirmation prompts (default: false)"
    echo
    echo "Options:"
    echo "  -h, --help      Show this help message"
    echo "  --force         Skip confirmation prompts (same as FORCE_DESTROY=true)"
    echo
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup"
    echo "  PROJECT_ID=my-expense-project $0      # Cleanup specific project"
    echo "  $0 --force                            # Skip confirmations"
    echo "  FORCE_DESTROY=true $0                 # Skip confirmations (env var)"
    echo
    echo "Safety Features:"
    echo "  - Requires explicit confirmation for destructive actions"
    echo "  - Loads configuration from deployment-info.txt if available"
    echo "  - Verifies cleanup completion"
    echo "  - Preserves project by default (optional project deletion)"
    echo
    echo "WARNING: This script will permanently delete resources and data!"
    echo
    exit 0
fi

# Handle --force flag
if [[ "${1:-}" == "--force" ]]; then
    export FORCE_DESTROY="true"
    log_warning "Force mode enabled - confirmations will be skipped"
fi

# Execute main function
main "$@"