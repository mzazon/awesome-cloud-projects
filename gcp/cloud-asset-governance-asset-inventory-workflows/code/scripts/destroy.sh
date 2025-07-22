#!/bin/bash
#
# Cloud Asset Governance Cleanup Script
# Safely removes all resources created by the governance system deployment
#
# Prerequisites:
# - gcloud CLI installed and authenticated
# - Access to the project and organization where resources were deployed
#
# Usage: ./destroy.sh [OPTIONS]
# Options:
#   -p, --project PROJECT_ID    Target project ID (required)
#   -o, --org ORG_ID           Organization ID (required for asset feed cleanup)
#   --deployment-info FILE     Use specific deployment info file
#   --force                    Skip confirmation prompts
#   --no-confirm               Skip all confirmations (use with caution)
#   --keep-project            Don't delete the project, only cleanup resources
#   --dry-run                 Show what would be deleted without making changes
#   -h, --help                Show this help message
#

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Default values
DRY_RUN=false
FORCE=false
NO_CONFIRM=false
KEEP_PROJECT=false
DELETE_PROJECT=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}ℹ️  INFO:${NC} $*"
}

log_success() {
    log "${GREEN}✅ SUCCESS:${NC} $*"
}

log_warning() {
    log "${YELLOW}⚠️  WARNING:${NC} $*"
}

log_error() {
    log "${RED}❌ ERROR:${NC} $*"
}

# Help function
show_help() {
    cat << EOF
Cloud Asset Governance Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -p, --project PROJECT_ID    Target project ID (required)
    -o, --org ORG_ID           Organization ID (required for asset feed cleanup)
    --deployment-info FILE     Use specific deployment info file
    --force                    Skip confirmation prompts
    --no-confirm               Skip all confirmations (use with caution)
    --keep-project            Don't delete the project, only cleanup resources
    --dry-run                 Show what would be deleted without making changes
    -h, --help                Show this help message

DESCRIPTION:
    This script safely removes all resources created by the governance system
    deployment. It follows a specific order to avoid dependency issues:
    
    1. Asset feed deletion
    2. Cloud Functions deletion
    3. Cloud Workflow deletion
    4. Pub/Sub resources cleanup
    5. BigQuery dataset removal
    6. Storage bucket cleanup
    7. Service account deletion
    8. Project deletion (optional)

SAFETY FEATURES:
    - Multiple confirmation prompts by default
    - Dry run mode to preview deletions
    - Detailed logging of all operations
    - Graceful handling of missing resources
    - Option to keep project while cleaning resources

EXAMPLES:
    # Standard cleanup with confirmations
    $0 --project my-governance-project --org 123456789012

    # Forced cleanup without prompts
    $0 --project my-governance-project --org 123456789012 --force

    # Preview what would be deleted
    $0 --project my-governance-project --org 123456789012 --dry-run

    # Keep project, only delete resources
    $0 --project my-governance-project --org 123456789012 --keep-project

    # Use specific deployment info file
    $0 --deployment-info deployment-info-20240101_120000.json

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -o|--org)
                ORGANIZATION_ID="$2"
                shift 2
                ;;
            --deployment-info)
                DEPLOYMENT_INFO_FILE="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --no-confirm)
                NO_CONFIRM=true
                FORCE=true
                shift
                ;;
            --keep-project)
                KEEP_PROJECT=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
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

    # Validate required parameters
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "Project ID is required. Use --project PROJECT_ID"
        show_help
        exit 1
    fi
}

# Load deployment information
load_deployment_info() {
    local info_file

    # Determine which deployment info file to use
    if [[ -n "${DEPLOYMENT_INFO_FILE:-}" ]]; then
        info_file="${SCRIPT_DIR}/${DEPLOYMENT_INFO_FILE}"
    elif [[ -f "${SCRIPT_DIR}/deployment-info-latest.json" ]]; then
        info_file="${SCRIPT_DIR}/deployment-info-latest.json"
    else
        log_warning "No deployment info file found. Will attempt to discover resources."
        return 0
    fi

    if [[ ! -f "${info_file}" ]]; then
        log_warning "Deployment info file not found: ${info_file}"
        return 0
    fi

    log_info "Loading deployment info from: ${info_file}"
    
    # Parse JSON deployment info
    if command -v jq &> /dev/null; then
        ORGANIZATION_ID="${ORGANIZATION_ID:-$(jq -r '.organization_id // empty' "${info_file}")}"
        REGION="$(jq -r '.region // "us-central1"' "${info_file}")"
        GOVERNANCE_SUFFIX="$(jq -r '.governance_suffix // empty' "${info_file}")"
        GOVERNANCE_BUCKET="$(jq -r '.resources.storage_bucket // empty' "${info_file}")"
        BQ_DATASET="$(jq -r '.resources.bigquery_dataset // empty' "${info_file}")"
        ASSET_TOPIC="$(jq -r '.resources.pubsub_topic // empty' "${info_file}")"
        WORKFLOW_SUBSCRIPTION="$(jq -r '.resources.pubsub_subscription // empty' "${info_file}")"
        GOVERNANCE_SA="$(jq -r '.resources.service_account // empty' "${info_file}" | cut -d'@' -f1)"
        FEED_NAME="$(jq -r '.resources.asset_feed // empty' "${info_file}")"
    else
        log_warning "jq not found. Cannot parse deployment info file automatically."
    fi

    log_success "Deployment info loaded"
}

# Discover resources if deployment info is not available
discover_resources() {
    log_info "Discovering governance resources in project ${PROJECT_ID}..."

    # Try to discover resources based on naming patterns
    if [[ -z "${GOVERNANCE_SUFFIX:-}" ]]; then
        # Look for governance buckets
        local buckets
        buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "governance" | head -1 || echo "")
        if [[ -n "${buckets}" ]]; then
            GOVERNANCE_BUCKET=$(basename "${buckets%/}")
            GOVERNANCE_SUFFIX="${GOVERNANCE_BUCKET##*-}"
            log_info "Discovered governance suffix: ${GOVERNANCE_SUFFIX}"
        fi
    fi

    # Set derived resource names if suffix is available
    if [[ -n "${GOVERNANCE_SUFFIX:-}" ]]; then
        GOVERNANCE_BUCKET="${GOVERNANCE_BUCKET:-${PROJECT_ID}-governance-${GOVERNANCE_SUFFIX}}"
        BQ_DATASET="${BQ_DATASET:-asset_governance_${GOVERNANCE_SUFFIX//-/_}}"
        ASSET_TOPIC="${ASSET_TOPIC:-asset-changes-${GOVERNANCE_SUFFIX}}"
        WORKFLOW_SUBSCRIPTION="${WORKFLOW_SUBSCRIPTION:-workflow-processor-${GOVERNANCE_SUFFIX}}"
        GOVERNANCE_SA="${GOVERNANCE_SA:-governance-engine-${GOVERNANCE_SUFFIX}}"
        FEED_NAME="${FEED_NAME:-governance-feed-${GOVERNANCE_SUFFIX}}"
    fi

    REGION="${REGION:-us-central1}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 &> /dev/null; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi

    # Check project access
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Cannot access project ${PROJECT_ID}. Check permissions."
        exit 1
    fi

    # Check organization access if provided
    if [[ -n "${ORGANIZATION_ID:-}" ]] && ! gcloud organizations describe "${ORGANIZATION_ID}" &> /dev/null; then
        log_warning "Cannot access organization ${ORGANIZATION_ID}. Asset feed cleanup may fail."
    fi

    log_success "Prerequisites check passed"
}

# Confirm cleanup
confirm_cleanup() {
    if [[ "${NO_CONFIRM}" == "true" ]]; then
        return 0
    fi

    log_warning "DESTRUCTIVE OPERATION: This will delete governance resources"
    echo
    log_info "Cleanup Configuration:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Organization ID: ${ORGANIZATION_ID:-'Not specified'}"
    echo "  Region: ${REGION:-'us-central1'}"
    echo "  Keep Project: ${KEEP_PROJECT}"
    echo
    
    if [[ -n "${GOVERNANCE_SUFFIX:-}" ]]; then
        echo "  Resources to delete:"
        echo "    - Storage Bucket: ${GOVERNANCE_BUCKET:-'Not found'}"
        echo "    - BigQuery Dataset: ${BQ_DATASET:-'Not found'}"
        echo "    - Pub/Sub Topic: ${ASSET_TOPIC:-'Not found'}"
        echo "    - Service Account: ${GOVERNANCE_SA:-'Not found'}"
        echo "    - Asset Feed: ${FEED_NAME:-'Not found'}"
        echo "    - Cloud Functions: governance-policy-evaluator, governance-workflow-trigger"
        echo "    - Cloud Workflow: governance-orchestrator"
    else
        echo "    - All discoverable governance resources"
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN MODE - No actual resources will be deleted"
        return 0
    fi

    if [[ "${FORCE}" == "false" ]]; then
        echo
        echo "This action cannot be undone!"
        read -p "Type 'DELETE' to confirm resource deletion: " -r
        if [[ $REPLY != "DELETE" ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi

    if [[ "${KEEP_PROJECT}" == "false" ]]; then
        echo
        log_warning "Project deletion is enabled. This will delete the ENTIRE project!"
        if [[ "${FORCE}" == "false" ]]; then
            read -p "Type 'DELETE PROJECT' to confirm project deletion: " -r
            if [[ $REPLY == "DELETE PROJECT" ]]; then
                DELETE_PROJECT=true
            else
                log_info "Project will be kept, only cleaning up governance resources"
                KEEP_PROJECT=true
            fi
        else
            DELETE_PROJECT=true
        fi
    fi
}

# Execute command with dry run support
execute_cmd() {
    local cmd="$*"
    log_info "Executing: ${cmd}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would execute: ${cmd}"
        return 0
    fi
    
    if eval "${cmd}"; then
        return 0
    else
        local exit_code=$?
        log_warning "Command failed with exit code ${exit_code}: ${cmd}"
        return $exit_code
    fi
}

# Delete asset feed
delete_asset_feed() {
    if [[ -z "${ORGANIZATION_ID:-}" ]]; then
        log_warning "Organization ID not provided. Skipping asset feed cleanup."
        return 0
    fi

    if [[ -z "${FEED_NAME:-}" ]]; then
        log_warning "Asset feed name not found. Attempting to discover..."
        # Try to find feeds for the organization
        local feeds
        feeds=$(gcloud asset feeds list --organization="${ORGANIZATION_ID}" --format="value(name)" 2>/dev/null | grep "governance" || echo "")
        if [[ -n "${feeds}" ]]; then
            FEED_NAME=$(basename "${feeds}")
            log_info "Discovered asset feed: ${FEED_NAME}"
        else
            log_warning "No governance asset feeds found"
            return 0
        fi
    fi

    log_info "Deleting asset feed: ${FEED_NAME}"
    execute_cmd "gcloud asset feeds delete \"${FEED_NAME}\" \
        --organization=\"${ORGANIZATION_ID}\" \
        --quiet" || log_warning "Failed to delete asset feed"
    
    log_success "Asset feed cleanup completed"
}

# Delete Cloud Functions
delete_functions() {
    log_info "Deleting Cloud Functions..."

    local functions=("governance-policy-evaluator" "governance-workflow-trigger")
    local region="${REGION:-us-central1}"

    for func in "${functions[@]}"; do
        if gcloud functions describe "${func}" --region="${region}" &>/dev/null; then
            execute_cmd "gcloud functions delete \"${func}\" \
                --region=\"${region}\" \
                --quiet" || log_warning "Failed to delete function: ${func}"
        else
            log_info "Function not found: ${func}"
        fi
    done

    log_success "Cloud Functions cleanup completed"
}

# Delete Cloud Workflow
delete_workflow() {
    log_info "Deleting Cloud Workflow..."

    local workflow="governance-orchestrator"
    local region="${REGION:-us-central1}"

    if gcloud workflows describe "${workflow}" --location="${region}" &>/dev/null; then
        execute_cmd "gcloud workflows delete \"${workflow}\" \
            --location=\"${region}\" \
            --quiet" || log_warning "Failed to delete workflow: ${workflow}"
    else
        log_info "Workflow not found: ${workflow}"
    fi

    log_success "Cloud Workflow cleanup completed"
}

# Delete Pub/Sub resources
delete_pubsub() {
    log_info "Deleting Pub/Sub resources..."

    # Delete subscription first
    if [[ -n "${WORKFLOW_SUBSCRIPTION:-}" ]]; then
        if gcloud pubsub subscriptions describe "${WORKFLOW_SUBSCRIPTION}" &>/dev/null; then
            execute_cmd "gcloud pubsub subscriptions delete \"${WORKFLOW_SUBSCRIPTION}\" --quiet" || \
                log_warning "Failed to delete subscription: ${WORKFLOW_SUBSCRIPTION}"
        else
            log_info "Subscription not found: ${WORKFLOW_SUBSCRIPTION}"
        fi
    fi

    # Delete topic
    if [[ -n "${ASSET_TOPIC:-}" ]]; then
        if gcloud pubsub topics describe "${ASSET_TOPIC}" &>/dev/null; then
            execute_cmd "gcloud pubsub topics delete \"${ASSET_TOPIC}\" --quiet" || \
                log_warning "Failed to delete topic: ${ASSET_TOPIC}"
        else
            log_info "Topic not found: ${ASSET_TOPIC}"
        fi
    fi

    # Clean up any other governance-related Pub/Sub resources
    local topics
    topics=$(gcloud pubsub topics list --format="value(name)" --filter="name:*governance*" 2>/dev/null || echo "")
    for topic in ${topics}; do
        local topic_name
        topic_name=$(basename "${topic}")
        execute_cmd "gcloud pubsub topics delete \"${topic_name}\" --quiet" || \
            log_warning "Failed to delete discovered topic: ${topic_name}"
    done

    log_success "Pub/Sub cleanup completed"
}

# Delete BigQuery dataset
delete_bigquery() {
    log_info "Deleting BigQuery dataset..."

    if [[ -n "${BQ_DATASET:-}" ]]; then
        if bq show "${PROJECT_ID}:${BQ_DATASET}" &>/dev/null; then
            execute_cmd "bq rm -r -f \"${PROJECT_ID}:${BQ_DATASET}\"" || \
                log_warning "Failed to delete dataset: ${BQ_DATASET}"
        else
            log_info "Dataset not found: ${BQ_DATASET}"
        fi
    fi

    # Clean up any other governance-related datasets
    local datasets
    datasets=$(bq ls --format=csv --max_results=1000 | grep "governance" | cut -d',' -f1 || echo "")
    for dataset in ${datasets}; do
        if [[ -n "${dataset}" && "${dataset}" != "datasetId" ]]; then
            execute_cmd "bq rm -r -f \"${PROJECT_ID}:${dataset}\"" || \
                log_warning "Failed to delete discovered dataset: ${dataset}"
        fi
    done

    log_success "BigQuery cleanup completed"
}

# Delete storage bucket
delete_storage() {
    log_info "Deleting Cloud Storage bucket..."

    if [[ -n "${GOVERNANCE_BUCKET:-}" ]]; then
        if gsutil ls "gs://${GOVERNANCE_BUCKET}" &>/dev/null; then
            execute_cmd "gsutil -m rm -r \"gs://${GOVERNANCE_BUCKET}\"" || \
                log_warning "Failed to delete bucket: ${GOVERNANCE_BUCKET}"
        else
            log_info "Bucket not found: ${GOVERNANCE_BUCKET}"
        fi
    fi

    # Clean up any other governance-related buckets
    local buckets
    buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "governance" || echo "")
    for bucket in ${buckets}; do
        local bucket_name
        bucket_name=$(basename "${bucket%/}")
        execute_cmd "gsutil -m rm -r \"${bucket}\"" || \
            log_warning "Failed to delete discovered bucket: ${bucket_name}"
    done

    log_success "Storage cleanup completed"
}

# Delete service account
delete_service_account() {
    log_info "Deleting service account..."

    if [[ -n "${GOVERNANCE_SA:-}" ]]; then
        local sa_email="${GOVERNANCE_SA}@${PROJECT_ID}.iam.gserviceaccount.com"
        if gcloud iam service-accounts describe "${sa_email}" &>/dev/null; then
            execute_cmd "gcloud iam service-accounts delete \"${sa_email}\" --quiet" || \
                log_warning "Failed to delete service account: ${sa_email}"
        else
            log_info "Service account not found: ${sa_email}"
        fi
    fi

    # Clean up any other governance-related service accounts
    local service_accounts
    service_accounts=$(gcloud iam service-accounts list --format="value(email)" --filter="email:*governance*" 2>/dev/null || echo "")
    for sa in ${service_accounts}; do
        execute_cmd "gcloud iam service-accounts delete \"${sa}\" --quiet" || \
            log_warning "Failed to delete discovered service account: ${sa}"
    done

    log_success "Service account cleanup completed"
}

# Delete project
delete_project() {
    if [[ "${DELETE_PROJECT}" != "true" ]]; then
        log_info "Keeping project as requested"
        return 0
    fi

    log_warning "Deleting entire project: ${PROJECT_ID}"
    execute_cmd "gcloud projects delete \"${PROJECT_ID}\" --quiet" || \
        log_error "Failed to delete project: ${PROJECT_ID}"
    
    log_success "Project deletion completed"
}

# Save cleanup log
save_cleanup_log() {
    local cleanup_file="${SCRIPT_DIR}/cleanup-log-${TIMESTAMP}.json"
    
    cat > "${cleanup_file}" << EOF
{
  "timestamp": "${TIMESTAMP}",
  "project_id": "${PROJECT_ID}",
  "organization_id": "${ORGANIZATION_ID:-}",
  "dry_run": ${DRY_RUN},
  "project_deleted": ${DELETE_PROJECT},
  "resources_cleaned": {
    "asset_feed": "${FEED_NAME:-}",
    "storage_bucket": "${GOVERNANCE_BUCKET:-}",
    "bigquery_dataset": "${BQ_DATASET:-}",
    "pubsub_topic": "${ASSET_TOPIC:-}",
    "service_account": "${GOVERNANCE_SA:-}",
    "functions": ["governance-policy-evaluator", "governance-workflow-trigger"],
    "workflow": "governance-orchestrator"
  }
}
EOF

    log_success "Cleanup log saved to: ${cleanup_file}"
}

# Main cleanup function
main() {
    log_info "Starting Cloud Asset Governance cleanup"
    log_info "Log file: ${LOG_FILE}"

    parse_args "$@"
    check_prerequisites
    load_deployment_info
    discover_resources
    confirm_cleanup

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would delete the following resources:"
        echo "  Asset Feed: ${FEED_NAME:-'Unknown'}"
        echo "  Storage Bucket: ${GOVERNANCE_BUCKET:-'Unknown'}"
        echo "  BigQuery Dataset: ${BQ_DATASET:-'Unknown'}"
        echo "  Pub/Sub Topic: ${ASSET_TOPIC:-'Unknown'}"
        echo "  Service Account: ${GOVERNANCE_SA:-'Unknown'}"
        echo "  Cloud Functions: governance-policy-evaluator, governance-workflow-trigger"
        echo "  Cloud Workflow: governance-orchestrator"
        if [[ "${DELETE_PROJECT}" == "true" ]]; then
            echo "  Project: ${PROJECT_ID}"
        fi
        log_success "DRY RUN completed"
        exit 0
    fi

    # Execute cleanup steps in proper order
    delete_asset_feed
    delete_functions
    delete_workflow
    delete_pubsub
    delete_bigquery
    delete_storage
    delete_service_account
    delete_project
    save_cleanup_log

    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        log_success "Cloud Asset Governance project and all resources deleted successfully!"
    else
        log_success "Cloud Asset Governance resources cleaned up successfully!"
        log_info "Project ${PROJECT_ID} has been preserved as requested"
    fi

    echo
    log_info "Cleanup Summary:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Project Deleted: ${DELETE_PROJECT}"
    echo "  Cleanup Log: cleanup-log-${TIMESTAMP}.json"
    echo
    log_info "If you need to redeploy, run: ${SCRIPT_DIR}/deploy.sh"
}

# Run main function
main "$@"