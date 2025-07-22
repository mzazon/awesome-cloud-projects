#!/bin/bash

# Compliance Violation Detection with Cloud Audit Logs and Eventarc - Cleanup Script
# This script removes all resources created by the compliance monitoring system

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

# Error handling function
error_exit() {
    log_error "$1"
    exit 1
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to prompt for confirmation
confirm_destruction() {
    echo "=== DANGER: DESTRUCTIVE OPERATION ==="
    echo "This script will permanently delete the following resources:"
    echo "- Cloud Function: ${FUNCTION_NAME:-compliance-detector-*}"
    echo "- Eventarc Trigger: ${TRIGGER_NAME:-audit-log-trigger-*}"
    echo "- Pub/Sub Topic and Subscription: ${TOPIC_NAME:-compliance-alerts-*}"
    echo "- BigQuery Dataset: ${DATASET_NAME:-compliance_logs_*}"
    echo "- Log Sinks and Metrics"
    echo "- Monitoring Resources"
    echo
    
    if [ "${FORCE_DESTROY:-false}" != "true" ]; then
        read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " -r
        if [ "$REPLY" != "DELETE" ]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    echo
    log_warning "Proceeding with resource cleanup..."
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check required commands
    local required_commands=("gcloud" "bq")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            error_exit "Required command '$cmd' is not installed or not in PATH"
        fi
    done
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        error_exit "No active gcloud authentication found. Please run 'gcloud auth login'"
    fi
    
    # Check if project is set
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
        error_exit "No project set in gcloud config. Please run 'gcloud config set project PROJECT_ID'"
    fi
    
    log_success "Prerequisites validation completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID=${PROJECT_ID:-$(gcloud config get-value project)}
    export REGION=${REGION:-"us-central1"}
    
    # If specific resource names are not provided, we'll search for them
    if [ -z "${FUNCTION_NAME:-}" ] || [ -z "${TRIGGER_NAME:-}" ] || [ -z "${TOPIC_NAME:-}" ] || [ -z "${DATASET_NAME:-}" ]; then
        log_info "Resource names not specified. Searching for compliance monitoring resources..."
        discover_resources
    fi
    
    log_success "Environment variables configured:"
    log_info "  PROJECT_ID: ${PROJECT_ID}"
    log_info "  REGION: ${REGION}"
    if [ -n "${FUNCTION_NAME:-}" ]; then
        log_info "  FUNCTION_NAME: ${FUNCTION_NAME}"
    fi
    if [ -n "${TRIGGER_NAME:-}" ]; then
        log_info "  TRIGGER_NAME: ${TRIGGER_NAME}"
    fi
    if [ -n "${TOPIC_NAME:-}" ]; then
        log_info "  TOPIC_NAME: ${TOPIC_NAME}"
    fi
    if [ -n "${DATASET_NAME:-}" ]; then
        log_info "  DATASET_NAME: ${DATASET_NAME}"
    fi
}

# Function to discover resources if names not provided
discover_resources() {
    log_info "Discovering compliance monitoring resources..."
    
    # Discover Cloud Functions
    local functions
    functions=$(gcloud functions list --region="$REGION" --filter="name:compliance-detector-*" --format="value(name)" 2>/dev/null || true)
    if [ -n "$functions" ]; then
        FUNCTION_NAME=$(echo "$functions" | head -n1)
        log_info "Found Cloud Function: $FUNCTION_NAME"
    fi
    
    # Discover Eventarc Triggers
    local triggers
    triggers=$(gcloud eventarc triggers list --location="$REGION" --filter="name:audit-log-trigger-*" --format="value(name)" 2>/dev/null || true)
    if [ -n "$triggers" ]; then
        TRIGGER_NAME=$(echo "$triggers" | head -n1)
        log_info "Found Eventarc Trigger: $TRIGGER_NAME"
    fi
    
    # Discover Pub/Sub Topics
    local topics
    topics=$(gcloud pubsub topics list --filter="name:compliance-alerts-*" --format="value(name)" 2>/dev/null || true)
    if [ -n "$topics" ]; then
        TOPIC_NAME=$(basename "$topics" | head -n1)
        log_info "Found Pub/Sub Topic: $TOPIC_NAME"
    fi
    
    # Discover BigQuery Datasets
    local datasets
    datasets=$(bq ls --filter="datasetId:compliance_logs_*" --format="value(datasetId)" 2>/dev/null || true)
    if [ -n "$datasets" ]; then
        DATASET_NAME=$(echo "$datasets" | head -n1)
        log_info "Found BigQuery Dataset: $DATASET_NAME"
    fi
}

# Function to delete Eventarc trigger
delete_eventarc_trigger() {
    if [ -z "${TRIGGER_NAME:-}" ]; then
        log_info "No Eventarc trigger name specified, skipping..."
        return 0
    fi
    
    log_info "Deleting Eventarc trigger: $TRIGGER_NAME"
    
    if gcloud eventarc triggers describe "$TRIGGER_NAME" --location="$REGION" >/dev/null 2>&1; then
        gcloud eventarc triggers delete "$TRIGGER_NAME" \
            --location="$REGION" \
            --quiet \
            || log_warning "Failed to delete Eventarc trigger: $TRIGGER_NAME"
        log_success "Deleted Eventarc trigger: $TRIGGER_NAME"
    else
        log_info "Eventarc trigger $TRIGGER_NAME not found, skipping..."
    fi
}

# Function to delete Cloud Function
delete_cloud_function() {
    if [ -z "${FUNCTION_NAME:-}" ]; then
        log_info "No Cloud Function name specified, skipping..."
        return 0
    fi
    
    log_info "Deleting Cloud Function: $FUNCTION_NAME"
    
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" >/dev/null 2>&1; then
        gcloud functions delete "$FUNCTION_NAME" \
            --region="$REGION" \
            --quiet \
            || log_warning "Failed to delete Cloud Function: $FUNCTION_NAME"
        log_success "Deleted Cloud Function: $FUNCTION_NAME"
    else
        log_info "Cloud Function $FUNCTION_NAME not found, skipping..."
    fi
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    if [ -z "${TOPIC_NAME:-}" ]; then
        log_info "No Pub/Sub topic name specified, skipping..."
        return 0
    fi
    
    log_info "Deleting Pub/Sub resources for topic: $TOPIC_NAME"
    
    # Delete subscription first
    local subscription_name="${TOPIC_NAME}-subscription"
    if gcloud pubsub subscriptions describe "$subscription_name" >/dev/null 2>&1; then
        gcloud pubsub subscriptions delete "$subscription_name" \
            --quiet \
            || log_warning "Failed to delete Pub/Sub subscription: $subscription_name"
        log_success "Deleted Pub/Sub subscription: $subscription_name"
    else
        log_info "Pub/Sub subscription $subscription_name not found, skipping..."
    fi
    
    # Delete topic
    if gcloud pubsub topics describe "$TOPIC_NAME" >/dev/null 2>&1; then
        gcloud pubsub topics delete "$TOPIC_NAME" \
            --quiet \
            || log_warning "Failed to delete Pub/Sub topic: $TOPIC_NAME"
        log_success "Deleted Pub/Sub topic: $TOPIC_NAME"
    else
        log_info "Pub/Sub topic $TOPIC_NAME not found, skipping..."
    fi
}

# Function to delete BigQuery resources
delete_bigquery_resources() {
    if [ -z "${DATASET_NAME:-}" ]; then
        log_info "No BigQuery dataset name specified, skipping..."
        return 0
    fi
    
    log_info "Deleting BigQuery dataset: $DATASET_NAME"
    
    # Check if dataset exists
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
        bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" \
            || log_warning "Failed to delete BigQuery dataset: $DATASET_NAME"
        log_success "Deleted BigQuery dataset: $DATASET_NAME"
    else
        log_info "BigQuery dataset $DATASET_NAME not found, skipping..."
    fi
}

# Function to delete logging resources
delete_logging_resources() {
    log_info "Deleting logging resources..."
    
    # Delete log sink
    local sink_name="compliance-audit-sink"
    if gcloud logging sinks describe "$sink_name" >/dev/null 2>&1; then
        gcloud logging sinks delete "$sink_name" \
            --quiet \
            || log_warning "Failed to delete logging sink: $sink_name"
        log_success "Deleted logging sink: $sink_name"
    else
        log_info "Logging sink $sink_name not found, skipping..."
    fi
    
    # Delete log-based metric
    local metric_name="compliance_violations"
    if gcloud logging metrics describe "$metric_name" >/dev/null 2>&1; then
        gcloud logging metrics delete "$metric_name" \
            --quiet \
            || log_warning "Failed to delete log-based metric: $metric_name"
        log_success "Deleted log-based metric: $metric_name"
    else
        log_info "Log-based metric $metric_name not found, skipping..."
    fi
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log_info "Deleting monitoring resources..."
    
    # List and delete alert policies related to compliance
    local alert_policies
    alert_policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:'High Severity Compliance Violations'" \
        --format="value(name)" 2>/dev/null || true)
    
    if [ -n "$alert_policies" ]; then
        while IFS= read -r policy; do
            if [ -n "$policy" ]; then
                log_info "Deleting alert policy: $policy"
                gcloud alpha monitoring policies delete "$policy" \
                    --quiet \
                    || log_warning "Failed to delete alert policy: $policy"
                log_success "Deleted alert policy: $policy"
            fi
        done <<< "$alert_policies"
    else
        log_info "No compliance-related alert policies found"
    fi
    
    # List and delete dashboards related to compliance
    local dashboards
    dashboards=$(gcloud monitoring dashboards list \
        --filter="displayName:'Compliance Monitoring Dashboard'" \
        --format="value(name)" 2>/dev/null || true)
    
    if [ -n "$dashboards" ]; then
        while IFS= read -r dashboard; do
            if [ -n "$dashboard" ]; then
                log_info "Deleting dashboard: $dashboard"
                gcloud monitoring dashboards delete "$dashboard" \
                    --quiet \
                    || log_warning "Failed to delete dashboard: $dashboard"
                log_success "Deleted dashboard: $dashboard"
            fi
        done <<< "$dashboards"
    else
        log_info "No compliance-related dashboards found"
    fi
}

# Function to cleanup any remaining resources
cleanup_remaining_resources() {
    log_info "Searching for any remaining compliance monitoring resources..."
    
    # Search for any remaining functions with compliance pattern
    local remaining_functions
    remaining_functions=$(gcloud functions list --region="$REGION" \
        --filter="name:compliance-detector" --format="value(name)" 2>/dev/null || true)
    
    if [ -n "$remaining_functions" ]; then
        log_warning "Found additional compliance functions:"
        echo "$remaining_functions"
        read -p "Delete these functions? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            while IFS= read -r func; do
                if [ -n "$func" ]; then
                    gcloud functions delete "$func" --region="$REGION" --quiet || true
                    log_success "Deleted function: $func"
                fi
            done <<< "$remaining_functions"
        fi
    fi
    
    # Search for any remaining Eventarc triggers
    local remaining_triggers
    remaining_triggers=$(gcloud eventarc triggers list --location="$REGION" \
        --filter="name:audit-log-trigger" --format="value(name)" 2>/dev/null || true)
    
    if [ -n "$remaining_triggers" ]; then
        log_warning "Found additional Eventarc triggers:"
        echo "$remaining_triggers"
        read -p "Delete these triggers? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            while IFS= read -r trigger; do
                if [ -n "$trigger" ]; then
                    gcloud eventarc triggers delete "$trigger" --location="$REGION" --quiet || true
                    log_success "Deleted trigger: $trigger"
                fi
            done <<< "$remaining_triggers"
        fi
    fi
    
    # Search for any remaining Pub/Sub topics
    local remaining_topics
    remaining_topics=$(gcloud pubsub topics list \
        --filter="name:compliance-alerts" --format="value(name)" 2>/dev/null || true)
    
    if [ -n "$remaining_topics" ]; then
        log_warning "Found additional Pub/Sub topics:"
        echo "$remaining_topics"
        read -p "Delete these topics? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            while IFS= read -r topic; do
                if [ -n "$topic" ]; then
                    local topic_name
                    topic_name=$(basename "$topic")
                    # Delete subscription first
                    gcloud pubsub subscriptions delete "${topic_name}-subscription" --quiet 2>/dev/null || true
                    # Delete topic
                    gcloud pubsub topics delete "$topic_name" --quiet || true
                    log_success "Deleted topic: $topic_name"
                fi
            done <<< "$remaining_topics"
        fi
    fi
    
    # Search for any remaining BigQuery datasets
    local remaining_datasets
    remaining_datasets=$(bq ls --filter="datasetId:compliance_logs" --format="value(datasetId)" 2>/dev/null || true)
    
    if [ -n "$remaining_datasets" ]; then
        log_warning "Found additional BigQuery datasets:"
        echo "$remaining_datasets"
        read -p "Delete these datasets? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            while IFS= read -r dataset; do
                if [ -n "$dataset" ]; then
                    bq rm -r -f "${PROJECT_ID}:${dataset}" || true
                    log_success "Deleted dataset: $dataset"
                fi
            done <<< "$remaining_datasets"
        fi
    fi
}

# Function to validate cleanup
validate_cleanup() {
    log_info "Validating cleanup..."
    
    local cleanup_successful=true
    
    # Check Cloud Function
    if [ -n "${FUNCTION_NAME:-}" ] && gcloud functions describe "$FUNCTION_NAME" --region="$REGION" >/dev/null 2>&1; then
        log_warning "Cloud Function still exists: $FUNCTION_NAME"
        cleanup_successful=false
    fi
    
    # Check Eventarc trigger
    if [ -n "${TRIGGER_NAME:-}" ] && gcloud eventarc triggers describe "$TRIGGER_NAME" --location="$REGION" >/dev/null 2>&1; then
        log_warning "Eventarc trigger still exists: $TRIGGER_NAME"
        cleanup_successful=false
    fi
    
    # Check Pub/Sub topic
    if [ -n "${TOPIC_NAME:-}" ] && gcloud pubsub topics describe "$TOPIC_NAME" >/dev/null 2>&1; then
        log_warning "Pub/Sub topic still exists: $TOPIC_NAME"
        cleanup_successful=false
    fi
    
    # Check BigQuery dataset
    if [ -n "${DATASET_NAME:-}" ] && bq ls -d "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
        log_warning "BigQuery dataset still exists: $DATASET_NAME"
        cleanup_successful=false
    fi
    
    if $cleanup_successful; then
        log_success "Cleanup validation passed"
    else
        log_warning "Some resources may still exist. Please check manually."
    fi
}

# Function to display cleanup summary
display_summary() {
    echo
    if [ "${1:-false}" = "true" ]; then
        log_success "🎉 Compliance Violation Detection System cleanup completed successfully!"
        echo
        echo "=== Cleanup Summary ==="
        echo "✅ All compliance monitoring resources have been removed"
        echo "✅ Associated monitoring and logging resources cleaned up"
        echo "✅ No ongoing charges for the compliance system"
    else
        log_warning "⚠️ Compliance Violation Detection System cleanup completed with warnings"
        echo
        echo "=== Cleanup Summary ==="
        echo "⚠️ Some resources may still exist"
        echo "⚠️ Please check the Google Cloud Console manually"
        echo "⚠️ Verify no unexpected charges are occurring"
    fi
    echo
    echo "=== Post-Cleanup Notes ==="
    echo "- Check your Google Cloud Console to verify all resources are removed"
    echo "- Review your billing to ensure no unexpected charges"
    echo "- Any custom audit log configurations remain unchanged"
    echo "- Core Google Cloud APIs remain enabled"
    echo
}

# Main cleanup function
main() {
    echo "=== Compliance Violation Detection Cleanup ==="
    echo "Starting cleanup of automated compliance monitoring system..."
    echo
    
    # Validate prerequisites
    validate_prerequisites
    
    # Setup environment
    setup_environment
    
    # Confirm destruction
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_eventarc_trigger
    delete_cloud_function
    delete_monitoring_resources
    delete_logging_resources
    delete_bigquery_resources
    delete_pubsub_resources
    
    # Cleanup any remaining resources
    cleanup_remaining_resources
    
    # Validate cleanup
    validate_cleanup
    
    # Display summary
    local cleanup_successful=true
    display_summary $cleanup_successful
    
    log_success "Cleanup completed! 🧹"
}

# Handle script interruption
trap 'log_error "Script interrupted. Some resources may still exist. Check your GCP console."; exit 1' INT TERM

# Support command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY=true
            shift
            ;;
        --function-name)
            export FUNCTION_NAME="$2"
            shift 2
            ;;
        --trigger-name)
            export TRIGGER_NAME="$2"
            shift 2
            ;;
        --topic-name)
            export TOPIC_NAME="$2"
            shift 2
            ;;
        --dataset-name)
            export DATASET_NAME="$2"
            shift 2
            ;;
        --region)
            export REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force              Skip confirmation prompt"
            echo "  --function-name      Specify Cloud Function name"
            echo "  --trigger-name       Specify Eventarc trigger name"
            echo "  --topic-name         Specify Pub/Sub topic name"
            echo "  --dataset-name       Specify BigQuery dataset name"
            echo "  --region             Specify GCP region"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi