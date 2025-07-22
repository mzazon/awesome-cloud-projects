#!/bin/bash

################################################################################
# Multi-Language Customer Support Automation - Cleanup Script
# 
# This script safely removes all resources created by the deployment script,
# including Cloud Functions, Workflows, Firestore database, Cloud Storage
# buckets, and associated monitoring configurations.
################################################################################

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly MAX_WAIT_TIME=300  # 5 minutes

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

################################################################################
# Utility Functions
################################################################################

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $*${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $*${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $*${NC}"
}

cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Cleanup failed with exit code $exit_code"
        log "Check the log file at: ${LOG_FILE}"
    fi
    exit $exit_code
}

confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        log_warning "Force deletion enabled - skipping confirmation"
        return 0
    fi
    
    echo -n -e "${YELLOW}$message${NC} "
    if [[ "$default" == "y" ]]; then
        echo -n "[Y/n]: "
    else
        echo -n "[y/N]: "
    fi
    
    read -r response
    response=${response:-$default}
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local check_command="$3"
    local max_wait="${4:-$MAX_WAIT_TIME}"
    local wait_time=0
    local sleep_interval=5

    log "Waiting for $resource_type deletion: $resource_name"
    
    while [[ $wait_time -lt $max_wait ]]; do
        if ! eval "$check_command" &> /dev/null; then
            log_success "$resource_type deleted: $resource_name"
            return 0
        fi
        
        if [[ $((wait_time % 30)) -eq 0 ]] && [[ $wait_time -gt 0 ]]; then
            log "Still waiting for $resource_type deletion... (${wait_time}s elapsed)"
        fi
        
        sleep $sleep_interval
        wait_time=$((wait_time + sleep_interval))
    done
    
    log_warning "$resource_type deletion may still be in progress: $resource_name"
    return 0  # Don't fail the entire script
}

################################################################################
# Prerequisites Validation
################################################################################

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

################################################################################
# Resource Discovery
################################################################################

discover_resources() {
    log "Discovering deployed resources..."
    
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
    export REGION="${REGION:-us-central1}"
    
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "No project configured. Please set PROJECT_ID or run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    log "Project ID: $PROJECT_ID"
    log "Region: $REGION"
    
    # Discover Cloud Functions
    log "Discovering Cloud Functions..."
    CLOUD_FUNCTIONS=($(gcloud functions list --project="$PROJECT_ID" --regions="$REGION" \
        --filter="name:multilang-processor" --format="value(name)" 2>/dev/null || true))
    
    # Discover Workflows
    log "Discovering Workflows..."
    WORKFLOWS=($(gcloud workflows list --project="$PROJECT_ID" --location="$REGION" \
        --filter="name:support-workflow" --format="value(name)" 2>/dev/null || true))
    
    # Discover Storage Buckets
    log "Discovering Storage Buckets..."
    STORAGE_BUCKETS=($(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "customer-support-audio" | sed 's|gs://||g; s|/||g' || true))
    
    # Discover Log Metrics
    log "Discovering Log-based Metrics..."
    LOG_METRICS=($(gcloud logging metrics list --project="$PROJECT_ID" \
        --filter="name:sentiment_score" --format="value(name)" 2>/dev/null || true))
    
    # Summary
    echo
    echo "📋 Resources discovered:"
    echo "  • Cloud Functions: ${#CLOUD_FUNCTIONS[@]}"
    echo "  • Workflows: ${#WORKFLOWS[@]}"
    echo "  • Storage Buckets: ${#STORAGE_BUCKETS[@]}"
    echo "  • Log Metrics: ${#LOG_METRICS[@]}"
    echo
}

################################################################################
# Cloud Functions Cleanup
################################################################################

cleanup_cloud_functions() {
    if [[ ${#CLOUD_FUNCTIONS[@]} -eq 0 ]]; then
        log "No Cloud Functions to delete"
        return 0
    fi
    
    log "Cleaning up Cloud Functions..."
    
    for function in "${CLOUD_FUNCTIONS[@]}"; do
        if confirm_action "Delete Cloud Function '$function'?" "y"; then
            log "Deleting Cloud Function: $function"
            if gcloud functions delete "$function" \
                --region="$REGION" \
                --project="$PROJECT_ID" \
                --quiet; then
                log_success "Deleted Cloud Function: $function"
            else
                log_error "Failed to delete Cloud Function: $function"
            fi
        else
            log "Skipped Cloud Function: $function"
        fi
    done
}

################################################################################
# Workflows Cleanup
################################################################################

cleanup_workflows() {
    if [[ ${#WORKFLOWS[@]} -eq 0 ]]; then
        log "No Workflows to delete"
        return 0
    fi
    
    log "Cleaning up Workflows..."
    
    for workflow in "${WORKFLOWS[@]}"; do
        if confirm_action "Delete Workflow '$workflow'?" "y"; then
            log "Deleting Workflow: $workflow"
            if gcloud workflows delete "$workflow" \
                --location="$REGION" \
                --project="$PROJECT_ID" \
                --quiet; then
                log_success "Deleted Workflow: $workflow"
            else
                log_error "Failed to delete Workflow: $workflow"
            fi
        else
            log "Skipped Workflow: $workflow"
        fi
    done
}

################################################################################
# Firestore Cleanup
################################################################################

cleanup_firestore() {
    log "Checking Firestore database..."
    
    # Check if Firestore database exists
    if gcloud firestore databases describe --project="$PROJECT_ID" &> /dev/null; then
        echo
        log_warning "Firestore database found"
        log_warning "Firestore databases cannot be deleted automatically"
        log_warning "Data will remain unless manually deleted from the console"
        echo
        log "To manually delete Firestore data:"
        echo "  1. Visit: https://console.cloud.google.com/firestore/data?project=$PROJECT_ID"
        echo "  2. Select the 'conversations' collection"
        echo "  3. Delete documents or the entire collection"
        echo
        
        if confirm_action "Would you like to delete Firestore indexes?" "y"; then
            log "Attempting to clean up Firestore indexes..."
            # List and delete composite indexes (if any)
            local indexes
            indexes=$(gcloud firestore indexes composite list --project="$PROJECT_ID" \
                --format="value(name)" 2>/dev/null || true)
            
            if [[ -n "$indexes" ]]; then
                while IFS= read -r index; do
                    if [[ -n "$index" ]]; then
                        log "Deleting Firestore index: $index"
                        gcloud firestore indexes composite delete "$index" \
                            --project="$PROJECT_ID" --quiet 2>/dev/null || true
                    fi
                done <<< "$indexes"
                log_success "Firestore indexes cleanup completed"
            else
                log "No custom Firestore indexes to delete"
            fi
        fi
    else
        log "No Firestore database found"
    fi
}

################################################################################
# Storage Cleanup
################################################################################

cleanup_storage() {
    if [[ ${#STORAGE_BUCKETS[@]} -eq 0 ]]; then
        log "No Storage Buckets to delete"
        return 0
    fi
    
    log "Cleaning up Storage Buckets..."
    
    for bucket in "${STORAGE_BUCKETS[@]}"; do
        if confirm_action "Delete Storage Bucket 'gs://$bucket' and all its contents?" "y"; then
            log "Deleting Storage Bucket: gs://$bucket"
            
            # Delete all objects in the bucket first
            if gsutil -m rm -r "gs://$bucket/**" 2>/dev/null || true; then
                log "Deleted all objects in bucket"
            fi
            
            # Delete the bucket
            if gsutil rb "gs://$bucket" 2>/dev/null; then
                log_success "Deleted Storage Bucket: gs://$bucket"
            else
                log_error "Failed to delete Storage Bucket: gs://$bucket"
            fi
        else
            log "Skipped Storage Bucket: gs://$bucket"
        fi
    done
}

################################################################################
# Monitoring Cleanup
################################################################################

cleanup_monitoring() {
    if [[ ${#LOG_METRICS[@]} -eq 0 ]]; then
        log "No Log-based Metrics to delete"
        return 0
    fi
    
    log "Cleaning up Monitoring resources..."
    
    for metric in "${LOG_METRICS[@]}"; do
        if confirm_action "Delete Log-based Metric '$metric'?" "y"; then
            log "Deleting Log-based Metric: $metric"
            if gcloud logging metrics delete "$metric" \
                --project="$PROJECT_ID" \
                --quiet; then
                log_success "Deleted Log-based Metric: $metric"
            else
                log_error "Failed to delete Log-based Metric: $metric"
            fi
        else
            log "Skipped Log-based Metric: $metric"
        fi
    done
}

################################################################################
# Local Files Cleanup
################################################################################

cleanup_local_files() {
    log "Cleaning up local temporary files..."
    
    # Remove any leftover configuration files
    local files_to_remove=(
        "${SCRIPT_DIR}/../speech-config.json"
        "${SCRIPT_DIR}/../translation-config.json"
        "${SCRIPT_DIR}/../sentiment-config.json"
        "${SCRIPT_DIR}/../tts-config.json"
        "${SCRIPT_DIR}/../workflow-definition.yaml"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "Removed local file: $(basename "$file")"
        fi
    done
    
    log_success "Local files cleaned up"
}

################################################################################
# Cost Estimation
################################################################################

estimate_cost_savings() {
    log "Estimating cost savings..."
    
    local total_functions=${#CLOUD_FUNCTIONS[@]}
    local total_workflows=${#WORKFLOWS[@]}
    local total_buckets=${#STORAGE_BUCKETS[@]}
    
    if [[ $total_functions -eq 0 && $total_workflows -eq 0 && $total_buckets -eq 0 ]]; then
        log "No billable resources were found to delete"
        return 0
    fi
    
    echo
    echo "💰 Estimated monthly cost savings:"
    
    if [[ $total_functions -gt 0 ]]; then
        echo "  • Cloud Functions ($total_functions): \$5-15/month (depends on usage)"
    fi
    
    if [[ $total_workflows -gt 0 ]]; then
        echo "  • Workflows ($total_workflows): \$1-5/month (depends on executions)"
    fi
    
    if [[ $total_buckets -gt 0 ]]; then
        echo "  • Storage Buckets ($total_buckets): \$1-10/month (depends on size)"
    fi
    
    echo "  • AI API calls: \$10-30/month (depends on usage)"
    echo
    echo "  📊 Total estimated savings: \$17-60/month"
    echo "     (Actual costs depend on usage patterns)"
    echo
}

################################################################################
# Verification
################################################################################

verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check Cloud Functions
    local remaining_functions
    remaining_functions=$(gcloud functions list --project="$PROJECT_ID" --regions="$REGION" \
        --filter="name:multilang-processor" --format="value(name)" 2>/dev/null | wc -l)
    if [[ $remaining_functions -gt 0 ]]; then
        log_warning "$remaining_functions Cloud Functions still exist"
        ((cleanup_issues++))
    fi
    
    # Check Workflows
    local remaining_workflows
    remaining_workflows=$(gcloud workflows list --project="$PROJECT_ID" --location="$REGION" \
        --filter="name:support-workflow" --format="value(name)" 2>/dev/null | wc -l)
    if [[ $remaining_workflows -gt 0 ]]; then
        log_warning "$remaining_workflows Workflows still exist"
        ((cleanup_issues++))
    fi
    
    # Check Storage Buckets
    local remaining_buckets
    remaining_buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -c "customer-support-audio" || true)
    if [[ $remaining_buckets -gt 0 ]]; then
        log_warning "$remaining_buckets Storage Buckets still exist"
        ((cleanup_issues++))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "Cleanup verification passed - all resources removed"
    else
        log_warning "Cleanup verification found $cleanup_issues issues"
        log "Some resources may still be in the process of deletion"
        log "Re-run this script later to verify complete cleanup"
    fi
}

################################################################################
# Usage Information
################################################################################

show_usage() {
    cat << 'EOF'
Multi-Language Customer Support Automation - Cleanup Script

USAGE:
    ./destroy.sh [OPTIONS]

OPTIONS:
    -f, --force     Skip confirmation prompts (use with caution)
    -h, --help      Show this help message
    
ENVIRONMENT VARIABLES:
    PROJECT_ID      GCP Project ID (overrides gcloud default)
    REGION          GCP Region (default: us-central1)
    FORCE_DELETE    Skip confirmations when set to 'true'

EXAMPLES:
    # Interactive cleanup with confirmations
    ./destroy.sh
    
    # Force cleanup without prompts (dangerous!)
    ./destroy.sh --force
    
    # Cleanup specific project
    PROJECT_ID=my-project ./destroy.sh

SAFETY NOTES:
    • This script will delete ALL matching resources
    • Firestore data must be manually deleted
    • Use --force only when you're absolutely sure
    • Always verify the project ID before running

EOF
}

################################################################################
# Main Cleanup Function
################################################################################

main() {
    trap cleanup_on_exit EXIT
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                export FORCE_DELETE="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    log "Starting Multi-Language Customer Support Automation cleanup..."
    echo "=================================================================="
    
    # Show warning for destructive operation
    if [[ "${FORCE_DELETE:-false}" != "true" ]]; then
        echo
        log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
        echo
        echo "This script will permanently delete:"
        echo "  • Cloud Functions and their code"
        echo "  • Cloud Workflows and their executions"
        echo "  • Cloud Storage buckets and all contents"
        echo "  • Log-based metrics and monitoring configs"
        echo
        echo "Firestore database will NOT be automatically deleted"
        echo "but you'll receive instructions for manual cleanup."
        echo
        
        if ! confirm_action "Are you sure you want to continue?" "n"; then
            log "Cleanup cancelled by user"
            exit 0
        fi
        echo
    fi
    
    # Run cleanup steps
    check_prerequisites
    discover_resources
    estimate_cost_savings
    
    # Perform cleanup in reverse order of deployment
    cleanup_monitoring
    cleanup_workflows
    cleanup_cloud_functions
    cleanup_firestore
    cleanup_storage
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    echo "=================================================================="
    log_success "Cleanup completed!"
    echo
    echo "📋 Cleanup Summary:"
    echo "  • Removed Cloud Functions: ${#CLOUD_FUNCTIONS[@]}"
    echo "  • Removed Workflows: ${#WORKFLOWS[@]}"
    echo "  • Removed Storage Buckets: ${#STORAGE_BUCKETS[@]}"
    echo "  • Removed Log Metrics: ${#LOG_METRICS[@]}"
    echo
    echo "📝 Manual cleanup still required:"
    echo "  • Firestore database data (if any)"
    echo "  • Review billing dashboard for any remaining charges"
    echo
    echo "🔍 Verify cleanup:"
    echo "   gcloud functions list --project=$PROJECT_ID"
    echo "   gcloud workflows list --project=$PROJECT_ID"
    echo "   gsutil ls -p $PROJECT_ID"
    echo
    echo "📊 Check your bill: https://console.cloud.google.com/billing"
}

# Check if script is being run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi