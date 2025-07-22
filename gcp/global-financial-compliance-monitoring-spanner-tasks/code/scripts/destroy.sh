#!/bin/bash

# Global Financial Compliance Monitoring with Cloud Spanner and Cloud Tasks
# Cleanup/Destroy Script for GCP
# 
# This script safely removes all resources created by the financial compliance
# monitoring system deployment, with proper confirmation and error handling.

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Default configuration
DEFAULT_REGION="us-central1"
DRY_RUN=false
FORCE=false
SKIP_CONFIRMATION=false

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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --help)
            cat << EOF
Usage: $0 [OPTIONS]

Safely remove all resources from the financial compliance monitoring system.

OPTIONS:
    --project-id PROJECT_ID     GCP Project ID (required)
    --region REGION            GCP region (default: $DEFAULT_REGION)
    --dry-run                  Show what would be deleted without executing
    --force                    Skip individual resource confirmations
    --skip-confirmation        Skip all confirmation prompts (DANGEROUS)
    --help                     Show this help message

EXAMPLES:
    $0 --project-id my-compliance-project
    $0 --project-id my-project --region us-east1
    $0 --project-id my-project --dry-run
    $0 --project-id my-project --force

SAFETY FEATURES:
    - Displays all resources to be deleted before proceeding
    - Requires explicit confirmation for destructive operations
    - Supports dry-run mode to preview actions
    - Handles resource dependencies and deletion order
    - Provides detailed logging of all operations

EOF
            exit 0
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Validate required parameters
if [[ -z "${PROJECT_ID:-}" ]]; then
    error "Project ID is required. Use --project-id or set PROJECT_ID environment variable."
fi

# Set defaults
REGION=${REGION:-$DEFAULT_REGION}
SPANNER_INSTANCE="compliance-monitor"
SPANNER_DATABASE="financial-compliance"
TASK_QUEUE="compliance-checks"

log "Starting cleanup of Financial Compliance Monitoring System"
log "Project ID: $PROJECT_ID"
log "Region: $REGION"

if [[ "$DRY_RUN" == "true" ]]; then
    warning "DRY RUN MODE - No resources will be deleted"
fi

if [[ "$FORCE" == "true" ]]; then
    warning "FORCE MODE - Individual confirmations will be skipped"
fi

# Function to run commands with dry-run support
run_command() {
    local cmd="$1"
    local description="$2"
    local skip_errors="${3:-false}"
    
    log "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY-RUN] Would execute: $cmd"
        return 0
    else
        echo "  Executing: $cmd"
        if [[ "$skip_errors" == "true" ]]; then
            eval "$cmd" || warning "Command failed but continuing: $cmd"
        else
            eval "$cmd"
        fi
    fi
}

# Function to confirm individual resource deletion
confirm_resource_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    
    if [[ "$FORCE" == "true" || "$SKIP_CONFIRMATION" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    read -p "Delete $resource_type '$resource_name'? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        warning "Skipping deletion of $resource_type '$resource_name'"
        return 1
    fi
    return 0
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Run 'gcloud auth login' first."
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        error "Project '$PROJECT_ID' does not exist or is not accessible"
    fi
    
    # Set project context
    gcloud config set project "$PROJECT_ID" &>/dev/null
    gcloud config set compute/region "$REGION" &>/dev/null
    
    success "Prerequisites check passed"
}

# Discover existing resources
discover_resources() {
    log "Discovering existing resources..."
    
    # Initialize arrays to store discovered resources
    FUNCTIONS=()
    TASK_QUEUES=()
    PUBSUB_TOPICS=()
    PUBSUB_SUBSCRIPTIONS=()
    SERVICE_ACCOUNTS=()
    LOG_SINKS=()
    STORAGE_BUCKETS=()
    
    # Discover Cloud Functions
    while IFS= read -r function_name; do
        if [[ -n "$function_name" ]]; then
            FUNCTIONS+=("$function_name")
        fi
    done < <(gcloud functions list \
        --regions="$REGION" \
        --filter="name:(compliance-processor OR transaction-processor)" \
        --format="value(name.basename())" 2>/dev/null || true)
    
    # Discover Task Queues
    while IFS= read -r queue_name; do
        if [[ -n "$queue_name" ]]; then
            TASK_QUEUES+=("$queue_name")
        fi
    done < <(gcloud tasks queues list \
        --location="$REGION" \
        --filter="name:compliance-checks" \
        --format="value(name.basename())" 2>/dev/null || true)
    
    # Discover Pub/Sub topics
    while IFS= read -r topic_name; do
        if [[ -n "$topic_name" ]]; then
            PUBSUB_TOPICS+=("$topic_name")
        fi
    done < <(gcloud pubsub topics list \
        --filter="name:compliance-events" \
        --format="value(name.basename())" 2>/dev/null || true)
    
    # Discover Pub/Sub subscriptions
    while IFS= read -r subscription_name; do
        if [[ -n "$subscription_name" ]]; then
            PUBSUB_SUBSCRIPTIONS+=("$subscription_name")
        fi
    done < <(gcloud pubsub subscriptions list \
        --filter="name:compliance-events" \
        --format="value(name.basename())" 2>/dev/null || true)
    
    # Discover service accounts
    while IFS= read -r sa_email; do
        if [[ -n "$sa_email" ]]; then
            SERVICE_ACCOUNTS+=("$sa_email")
        fi
    done < <(gcloud iam service-accounts list \
        --filter="email:compliance-monitor-sa-*" \
        --format="value(email)" 2>/dev/null || true)
    
    # Discover log sinks
    while IFS= read -r sink_name; do
        if [[ -n "$sink_name" ]]; then
            LOG_SINKS+=("$sink_name")
        fi
    done < <(gcloud logging sinks list \
        --filter="name:compliance-audit-sink" \
        --format="value(name)" 2>/dev/null || true)
    
    # Discover storage buckets (for audit logs)
    while IFS= read -r bucket_name; do
        if [[ -n "$bucket_name" ]]; then
            STORAGE_BUCKETS+=("$bucket_name")
        fi
    done < <(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "compliance-audit-logs" | sed 's|gs://||g' | sed 's|/||g' || true)
    
    success "Resource discovery completed"
}

# Display resources to be deleted
display_deletion_plan() {
    log "Resources scheduled for deletion:"
    echo "================================="
    
    local total_resources=0
    
    if [[ ${#FUNCTIONS[@]} -gt 0 ]]; then
        echo "Cloud Functions (${#FUNCTIONS[@]}):"
        for func in "${FUNCTIONS[@]}"; do
            echo "  - $func"
            ((total_resources++))
        done
        echo ""
    fi
    
    if [[ ${#TASK_QUEUES[@]} -gt 0 ]]; then
        echo "Cloud Tasks Queues (${#TASK_QUEUES[@]}):"
        for queue in "${TASK_QUEUES[@]}"; do
            echo "  - $queue"
            ((total_resources++))
        done
        echo ""
    fi
    
    if [[ ${#PUBSUB_SUBSCRIPTIONS[@]} -gt 0 ]]; then
        echo "Pub/Sub Subscriptions (${#PUBSUB_SUBSCRIPTIONS[@]}):"
        for subscription in "${PUBSUB_SUBSCRIPTIONS[@]}"; do
            echo "  - $subscription"
            ((total_resources++))
        done
        echo ""
    fi
    
    if [[ ${#PUBSUB_TOPICS[@]} -gt 0 ]]; then
        echo "Pub/Sub Topics (${#PUBSUB_TOPICS[@]}):"
        for topic in "${PUBSUB_TOPICS[@]}"; do
            echo "  - $topic"
            ((total_resources++))
        done
        echo ""
    fi
    
    # Check for Spanner resources
    if gcloud spanner instances describe "$SPANNER_INSTANCE" &>/dev/null; then
        echo "Cloud Spanner Resources:"
        echo "  - Instance: $SPANNER_INSTANCE"
        echo "  - Database: $SPANNER_DATABASE"
        ((total_resources+=2))
        echo ""
    fi
    
    if [[ ${#LOG_SINKS[@]} -gt 0 ]]; then
        echo "Log Sinks (${#LOG_SINKS[@]}):"
        for sink in "${LOG_SINKS[@]}"; do
            echo "  - $sink"
            ((total_resources++))
        done
        echo ""
    fi
    
    if [[ ${#STORAGE_BUCKETS[@]} -gt 0 ]]; then
        echo "Storage Buckets (${#STORAGE_BUCKETS[@]}):"
        for bucket in "${STORAGE_BUCKETS[@]}"; do
            echo "  - $bucket"
            ((total_resources++))
        done
        echo ""
    fi
    
    if [[ ${#SERVICE_ACCOUNTS[@]} -gt 0 ]]; then
        echo "Service Accounts (${#SERVICE_ACCOUNTS[@]}):"
        for sa in "${SERVICE_ACCOUNTS[@]}"; do
            echo "  - $sa"
            ((total_resources++))
        done
        echo ""
    fi
    
    if [[ $total_resources -eq 0 ]]; then
        success "No resources found to delete"
        exit 0
    fi
    
    warning "Total resources to delete: $total_resources"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "This is a dry run. No resources will actually be deleted."
        return 0
    fi
}

# Confirm deletion
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warning "WARNING: This operation will permanently delete all listed resources!"
    warning "This action cannot be undone!"
    echo ""
    read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Last chance! Continue with deletion? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
}

# Delete Cloud Functions
delete_functions() {
    if [[ ${#FUNCTIONS[@]} -eq 0 ]]; then
        return 0
    fi
    
    log "Deleting Cloud Functions..."
    
    for func in "${FUNCTIONS[@]}"; do
        if confirm_resource_deletion "Cloud Function" "$func"; then
            run_command "gcloud functions delete $func \
                --region=$REGION \
                --quiet" \
                "Deleting function $func" \
                "true"
        fi
    done
    
    success "Cloud Functions cleanup completed"
}

# Delete Task Queues
delete_task_queues() {
    if [[ ${#TASK_QUEUES[@]} -eq 0 ]]; then
        return 0
    fi
    
    log "Deleting Cloud Tasks queues..."
    
    for queue in "${TASK_QUEUES[@]}"; do
        if confirm_resource_deletion "Task Queue" "$queue"; then
            run_command "gcloud tasks queues delete $queue \
                --location=$REGION \
                --quiet" \
                "Deleting task queue $queue" \
                "true"
        fi
    done
    
    success "Task queues cleanup completed"
}

# Delete Pub/Sub resources
delete_pubsub_resources() {
    # Delete subscriptions first
    if [[ ${#PUBSUB_SUBSCRIPTIONS[@]} -gt 0 ]]; then
        log "Deleting Pub/Sub subscriptions..."
        
        for subscription in "${PUBSUB_SUBSCRIPTIONS[@]}"; do
            if confirm_resource_deletion "Pub/Sub Subscription" "$subscription"; then
                run_command "gcloud pubsub subscriptions delete $subscription --quiet" \
                    "Deleting subscription $subscription" \
                    "true"
            fi
        done
    fi
    
    # Delete topics
    if [[ ${#PUBSUB_TOPICS[@]} -gt 0 ]]; then
        log "Deleting Pub/Sub topics..."
        
        for topic in "${PUBSUB_TOPICS[@]}"; do
            if confirm_resource_deletion "Pub/Sub Topic" "$topic"; then
                run_command "gcloud pubsub topics delete $topic --quiet" \
                    "Deleting topic $topic" \
                    "true"
            fi
        done
    fi
    
    success "Pub/Sub resources cleanup completed"
}

# Delete Spanner resources
delete_spanner_resources() {
    # Check if Spanner instance exists
    if ! gcloud spanner instances describe "$SPANNER_INSTANCE" &>/dev/null; then
        return 0
    fi
    
    log "Deleting Cloud Spanner resources..."
    
    # Delete database first
    if confirm_resource_deletion "Spanner Database" "$SPANNER_DATABASE"; then
        run_command "gcloud spanner databases delete $SPANNER_DATABASE \
            --instance=$SPANNER_INSTANCE \
            --quiet" \
            "Deleting Spanner database $SPANNER_DATABASE" \
            "true"
    fi
    
    # Delete instance
    if confirm_resource_deletion "Spanner Instance" "$SPANNER_INSTANCE"; then
        run_command "gcloud spanner instances delete $SPANNER_INSTANCE --quiet" \
            "Deleting Spanner instance $SPANNER_INSTANCE" \
            "true"
    fi
    
    success "Spanner resources cleanup completed"
}

# Delete log sinks
delete_log_sinks() {
    if [[ ${#LOG_SINKS[@]} -eq 0 ]]; then
        return 0
    fi
    
    log "Deleting log sinks..."
    
    for sink in "${LOG_SINKS[@]}"; do
        if confirm_resource_deletion "Log Sink" "$sink"; then
            run_command "gcloud logging sinks delete $sink --quiet" \
                "Deleting log sink $sink" \
                "true"
        fi
    done
    
    success "Log sinks cleanup completed"
}

# Delete storage buckets
delete_storage_buckets() {
    if [[ ${#STORAGE_BUCKETS[@]} -eq 0 ]]; then
        return 0
    fi
    
    log "Deleting storage buckets..."
    
    for bucket in "${STORAGE_BUCKETS[@]}"; do
        if confirm_resource_deletion "Storage Bucket" "$bucket"; then
            # Remove all objects first
            run_command "gsutil -m rm -r gs://$bucket/** 2>/dev/null || true" \
                "Emptying bucket $bucket" \
                "true"
            
            # Delete the bucket
            run_command "gsutil rb gs://$bucket" \
                "Deleting bucket $bucket" \
                "true"
        fi
    done
    
    success "Storage buckets cleanup completed"
}

# Delete service accounts
delete_service_accounts() {
    if [[ ${#SERVICE_ACCOUNTS[@]} -eq 0 ]]; then
        return 0
    fi
    
    log "Deleting service accounts..."
    
    for sa in "${SERVICE_ACCOUNTS[@]}"; do
        if confirm_resource_deletion "Service Account" "$sa"; then
            run_command "gcloud iam service-accounts delete $sa --quiet" \
                "Deleting service account $sa" \
                "true"
        fi
    done
    
    success "Service accounts cleanup completed"
}

# Display cleanup summary
cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN COMPLETED - No resources were actually deleted"
    else
        echo "Cleanup completed successfully!"
    fi
    
    echo ""
    echo "Resources processed:"
    echo "  - Cloud Functions: ${#FUNCTIONS[@]}"
    echo "  - Task Queues: ${#TASK_QUEUES[@]}"
    echo "  - Pub/Sub Topics: ${#PUBSUB_TOPICS[@]}"
    echo "  - Pub/Sub Subscriptions: ${#PUBSUB_SUBSCRIPTIONS[@]}"
    echo "  - Log Sinks: ${#LOG_SINKS[@]}"
    echo "  - Storage Buckets: ${#STORAGE_BUCKETS[@]}"
    echo "  - Service Accounts: ${#SERVICE_ACCOUNTS[@]}"
    echo "  - Spanner Instance: $(gcloud spanner instances describe "$SPANNER_INSTANCE" &>/dev/null && echo "1" || echo "0")"
    echo ""
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "Verification commands:"
        echo "  gcloud functions list --regions=$REGION"
        echo "  gcloud spanner instances list"
        echo "  gcloud tasks queues list --location=$REGION"
        echo "  gcloud pubsub topics list"
        echo "  gcloud iam service-accounts list --filter='email:compliance-monitor-sa-*'"
    fi
}

# Main cleanup flow
main() {
    check_prerequisites
    discover_resources
    display_deletion_plan
    confirm_deletion
    
    # Delete resources in proper order (reverse of creation)
    delete_functions
    delete_task_queues
    delete_pubsub_resources
    delete_spanner_resources
    delete_log_sinks
    delete_storage_buckets
    delete_service_accounts
    
    success "Financial Compliance Monitoring System cleanup completed!"
    cleanup_summary
}

# Error handling
trap 'error "Cleanup failed. Check the logs above for details."' ERR

# Run main cleanup
main "$@"