#!/bin/bash

# Resource Tagging and Cost Allocation Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

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

# Function to confirm destructive operations
confirm_destruction() {
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo "This script will permanently delete the following resources:"
    echo "  - Cloud Functions (tag compliance and reporting)"
    echo "  - BigQuery dataset and all tables"
    echo "  - Cloud Storage bucket and contents"
    echo "  - Pub/Sub topics and subscriptions"
    echo "  - Cloud Asset Inventory feeds"
    echo "  - Organization policy constraints (optional)"
    echo ""
    
    # Check if running in non-interactive mode
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        log_warning "Force delete mode enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    case $confirmation in
        [Yy][Ee][Ss])
            log_info "Proceeding with resource deletion..."
            ;;
        *)
            log_info "Cleanup cancelled by user"
            exit 0
            ;;
    esac
}

# Function to validate environment and discover resources
validate_environment() {
    log_info "Validating environment and discovering resources..."
    
    # Get project ID
    export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "No default project set. Run 'gcloud config set project YOUR_PROJECT_ID'"
        exit 1
    fi
    
    # Get organization ID
    export ORGANIZATION_ID=$(gcloud organizations list --format="value(name)" --limit=1 2>/dev/null)
    if [[ -z "${ORGANIZATION_ID}" ]]; then
        log_warning "No organization found. Will skip organization-level cleanup."
    fi
    
    # Set defaults
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Organization ID: ${ORGANIZATION_ID}"
    log_success "Environment validation completed"
}

# Function to discover and list resources to be deleted
discover_resources() {
    log_info "Discovering resources to be deleted..."
    
    # Find Cloud Functions
    log_info "Scanning for Cloud Functions..."
    FUNCTIONS=$(gcloud functions list --region="${REGION}" --format="value(name)" --filter="name~tag-compliance OR name~cost-allocation-reporter" 2>/dev/null || echo "")
    if [[ -n "${FUNCTIONS}" ]]; then
        log_info "Found Cloud Functions: ${FUNCTIONS}"
    else
        log_info "No matching Cloud Functions found"
    fi
    
    # Find BigQuery datasets
    log_info "Scanning for BigQuery datasets..."
    DATASETS=$(bq ls --format=csv --max_results=1000 | grep "cost_allocation_" | cut -d',' -f1 2>/dev/null || echo "")
    if [[ -n "${DATASETS}" ]]; then
        log_info "Found BigQuery datasets: ${DATASETS}"
    else
        log_info "No matching BigQuery datasets found"
    fi
    
    # Find Cloud Storage buckets
    log_info "Scanning for Cloud Storage buckets..."
    BUCKETS=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "billing-export" || echo "")
    if [[ -n "${BUCKETS}" ]]; then
        log_info "Found Storage buckets: ${BUCKETS}"
    else
        log_info "No matching Storage buckets found"
    fi
    
    # Find Pub/Sub topics
    log_info "Scanning for Pub/Sub topics..."
    TOPICS=$(gcloud pubsub topics list --format="value(name)" --filter="name~asset-changes" 2>/dev/null || echo "")
    if [[ -n "${TOPICS}" ]]; then
        log_info "Found Pub/Sub topics: ${TOPICS}"
    else
        log_info "No matching Pub/Sub topics found"
    fi
    
    # Find Asset Inventory feeds
    log_info "Scanning for Asset Inventory feeds..."
    if [[ -n "${ORGANIZATION_ID}" ]]; then
        FEEDS=$(gcloud asset feeds list --organization="${ORGANIZATION_ID}" --format="value(name)" --filter="name~resource-compliance-feed" 2>/dev/null || echo "")
        if [[ -n "${FEEDS}" ]]; then
            log_info "Found Asset feeds: ${FEEDS}"
        else
            log_info "No matching Asset feeds found"
        fi
    fi
}

# Function to delete Cloud Functions
delete_functions() {
    log_info "Deleting Cloud Functions..."
    
    # Get all functions in the region
    local functions=$(gcloud functions list --region="${REGION}" --format="value(name)" 2>/dev/null || echo "")
    
    for function_name in $functions; do
        if [[ "$function_name" =~ tag-compliance|cost-allocation-reporter ]]; then
            log_info "Deleting function: $function_name"
            if gcloud functions delete "$function_name" --region="${REGION}" --quiet 2>/dev/null; then
                log_success "Deleted function: $function_name"
            else
                log_warning "Failed to delete function: $function_name (may not exist)"
            fi
        fi
    done
    
    log_success "Cloud Functions cleanup completed"
}

# Function to delete BigQuery resources
delete_bigquery() {
    log_info "Deleting BigQuery resources..."
    
    # List datasets and find matching ones
    local datasets=$(bq ls --format=csv --max_results=1000 2>/dev/null | tail -n +2 | cut -d',' -f1 || echo "")
    
    for dataset in $datasets; do
        if [[ "$dataset" =~ cost_allocation_ ]]; then
            log_info "Deleting BigQuery dataset: $dataset"
            if bq rm -r -f "${PROJECT_ID}:${dataset}" 2>/dev/null; then
                log_success "Deleted dataset: $dataset"
            else
                log_warning "Failed to delete dataset: $dataset"
            fi
        fi
    done
    
    log_success "BigQuery cleanup completed"
}

# Function to delete Cloud Storage resources
delete_storage() {
    log_info "Deleting Cloud Storage resources..."
    
    # List buckets and find matching ones
    local buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "billing-export" || echo "")
    
    for bucket in $buckets; do
        log_info "Deleting Storage bucket: $bucket"
        # Remove all objects first, then the bucket
        if gsutil -m rm -r "$bucket" 2>/dev/null; then
            log_success "Deleted bucket: $bucket"
        else
            log_warning "Failed to delete bucket: $bucket (may not exist or have contents)"
        fi
    done
    
    log_success "Cloud Storage cleanup completed"
}

# Function to delete Pub/Sub resources
delete_pubsub() {
    log_info "Deleting Pub/Sub resources..."
    
    # Delete subscriptions first
    local subscriptions=$(gcloud pubsub subscriptions list --format="value(name)" 2>/dev/null || echo "")
    for subscription in $subscriptions; do
        if [[ "$subscription" =~ asset-changes ]]; then
            log_info "Deleting subscription: $subscription"
            if gcloud pubsub subscriptions delete "$subscription" --quiet 2>/dev/null; then
                log_success "Deleted subscription: $subscription"
            else
                log_warning "Failed to delete subscription: $subscription"
            fi
        fi
    done
    
    # Delete topics
    local topics=$(gcloud pubsub topics list --format="value(name)" 2>/dev/null || echo "")
    for topic in $topics; do
        if [[ "$topic" =~ asset-changes ]]; then
            log_info "Deleting topic: $topic"
            if gcloud pubsub topics delete "$topic" --quiet 2>/dev/null; then
                log_success "Deleted topic: $topic"
            else
                log_warning "Failed to delete topic: $topic"
            fi
        fi
    done
    
    log_success "Pub/Sub cleanup completed"
}

# Function to delete Asset Inventory feeds
delete_asset_feeds() {
    if [[ -z "${ORGANIZATION_ID}" ]]; then
        log_warning "No organization ID available, skipping asset feed cleanup"
        return 0
    fi
    
    log_info "Deleting Asset Inventory feeds..."
    
    # List and delete asset feeds
    local feeds=$(gcloud asset feeds list --organization="${ORGANIZATION_ID}" --format="value(name)" 2>/dev/null || echo "")
    
    for feed in $feeds; do
        if [[ "$feed" =~ resource-compliance-feed ]]; then
            log_info "Deleting asset feed: $feed"
            if gcloud asset feeds delete "$(basename "$feed")" --organization="${ORGANIZATION_ID}" --quiet 2>/dev/null; then
                log_success "Deleted asset feed: $feed"
            else
                log_warning "Failed to delete asset feed: $feed"
            fi
        fi
    done
    
    log_success "Asset Inventory cleanup completed"
}

# Function to delete organization policies (optional)
delete_org_policies() {
    if [[ -z "${ORGANIZATION_ID}" ]]; then
        log_warning "No organization ID available, skipping organization policy cleanup"
        return 0
    fi
    
    log_info "Organization policy cleanup..."
    echo ""
    log_warning "⚠️  Organization Policy Constraint Removal ⚠️"
    echo "Removing organization policy constraints can affect production workloads."
    echo "This will remove the mandatory tagging constraint for your entire organization."
    echo ""
    
    # Check if running in force mode or ask for confirmation
    if [[ "${FORCE_DELETE:-false}" != "true" ]]; then
        read -p "Do you want to remove organization policy constraints? (yes/no): " org_policy_confirmation
        case $org_policy_confirmation in
            [Yy][Ee][Ss])
                ;;
            *)
                log_info "Skipping organization policy cleanup"
                return 0
                ;;
        esac
    fi
    
    # Remove custom constraint
    log_info "Removing custom organization policy constraint..."
    if gcloud org-policies delete-custom-constraint \
        "organizations/${ORGANIZATION_ID}/customConstraints/custom.mandatoryResourceTags" \
        --quiet 2>/dev/null; then
        log_success "Deleted organization policy constraint"
    else
        log_warning "Failed to delete organization policy constraint (may not exist)"
    fi
}

# Function to clean up any remaining test resources
cleanup_test_resources() {
    log_info "Cleaning up any remaining test resources..."
    
    # Find and delete test instances
    local test_instances=$(gcloud compute instances list --format="value(name)" --filter="name~test-instance-compliant" 2>/dev/null || echo "")
    
    for instance in $test_instances; do
        log_info "Deleting test instance: $instance"
        if gcloud compute instances delete "$instance" --zone="${ZONE}" --quiet 2>/dev/null; then
            log_success "Deleted test instance: $instance"
        else
            log_warning "Failed to delete test instance: $instance"
        fi
    done
    
    log_success "Test resource cleanup completed"
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check for remaining functions
    local remaining_functions=$(gcloud functions list --region="${REGION}" --format="value(name)" --filter="name~tag-compliance OR name~cost-allocation-reporter" 2>/dev/null || echo "")
    if [[ -n "$remaining_functions" ]]; then
        log_warning "Remaining functions found: $remaining_functions"
        ((cleanup_issues++))
    fi
    
    # Check for remaining datasets
    local remaining_datasets=$(bq ls --format=csv 2>/dev/null | grep "cost_allocation_" || echo "")
    if [[ -n "$remaining_datasets" ]]; then
        log_warning "Remaining datasets found: $remaining_datasets"
        ((cleanup_issues++))
    fi
    
    # Check for remaining buckets
    local remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "billing-export" || echo "")
    if [[ -n "$remaining_buckets" ]]; then
        log_warning "Remaining buckets found: $remaining_buckets"
        ((cleanup_issues++))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "✅ Cleanup verification passed - no remaining resources found"
    else
        log_warning "⚠️  Cleanup verification found $cleanup_issues potential issues"
        log_info "Some resources may need manual cleanup or may not belong to this deployment"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary:"
    echo "================"
    echo "Project ID: ${PROJECT_ID}"
    echo "Organization ID: ${ORGANIZATION_ID:-N/A}"
    echo "Region: ${REGION}"
    echo ""
    log_info "Resources cleaned up:"
    echo "  ✅ Cloud Functions"
    echo "  ✅ BigQuery datasets and tables"
    echo "  ✅ Cloud Storage buckets"
    echo "  ✅ Pub/Sub topics and subscriptions"
    echo "  ✅ Asset Inventory feeds"
    echo "  ✅ Test resources"
    if [[ "${SKIP_ORG_POLICY:-false}" != "true" ]]; then
        echo "  ⚠️  Organization policies (if confirmed)"
    else
        echo "  ⏭️  Organization policies (skipped)"
    fi
    echo ""
    log_info "Manual cleanup may be required for:"
    echo "  - Billing export configuration"
    echo "  - IAM roles and permissions"
    echo "  - Audit logs and monitoring"
}

# Main cleanup function
main() {
    log_info "Starting Resource Tagging and Cost Allocation cleanup..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                export FORCE_DELETE="true"
                log_info "Force mode enabled"
                shift
                ;;
            --skip-org-policy)
                export SKIP_ORG_POLICY="true"
                log_info "Skipping organization policy cleanup"
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --force              Skip confirmation prompts"
                echo "  --skip-org-policy    Skip organization policy cleanup"
                echo "  --help               Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Run cleanup steps
    validate_environment
    discover_resources
    confirm_destruction
    delete_functions
    delete_bigquery
    delete_storage
    delete_pubsub
    delete_asset_feeds
    cleanup_test_resources
    
    # Optionally delete organization policies
    if [[ "${SKIP_ORG_POLICY:-false}" != "true" ]]; then
        delete_org_policies
    fi
    
    verify_cleanup
    display_cleanup_summary
    
    log_success "🎉 Cleanup completed successfully!"
}

# Handle script interruption
trap 'log_error "Cleanup interrupted - some resources may remain"; exit 1' INT TERM

# Run main function
main "$@"