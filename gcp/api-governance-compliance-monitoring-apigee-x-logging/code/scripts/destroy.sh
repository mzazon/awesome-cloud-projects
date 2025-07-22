#!/bin/bash

# API Governance and Compliance Monitoring with Apigee X and Cloud Logging - Cleanup Script
# This script destroys all resources created by the deployment script
# Recipe: api-governance-compliance-monitoring-apigee-x-logging

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
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

# Error handling
handle_error() {
    log_error "Cleanup failed at line $1"
    log_error "Command: $2"
    log_error "Exit code: $3"
    log_warning "Some resources may still exist. Please check the Google Cloud Console."
    exit 1
}

trap 'handle_error $LINENO "$BASH_COMMAND" $?' ERR

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    log_info "Running in dry-run mode - no resources will be deleted"
fi

# Force deletion without prompts
FORCE=${FORCE:-false}
if [[ "$1" == "--force" ]] || [[ "$2" == "--force" ]]; then
    FORCE=true
    log_info "Force mode enabled - no confirmation prompts"
fi

log_info "Starting API Governance and Compliance Monitoring cleanup..."

# Prerequisites check
log_info "Checking prerequisites..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI is not installed. Please install it first."
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
    log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
    exit 1
fi

# Check if bq is installed
if ! command -v bq &> /dev/null; then
    log_error "BigQuery CLI (bq) is not installed. Please install it first."
    exit 1
fi

# Check if gsutil is installed
if ! command -v gsutil &> /dev/null; then
    log_error "gsutil is not installed. Please install it first."
    exit 1
fi

log_success "Prerequisites check passed"

# Load deployment state if available
if [[ -f "deployment_state.json" ]]; then
    log_info "Loading deployment state from deployment_state.json..."
    
    # Extract values from deployment state
    PROJECT_ID=$(jq -r '.project_id' deployment_state.json 2>/dev/null || echo "")
    REGION=$(jq -r '.region' deployment_state.json 2>/dev/null || echo "")
    ZONE=$(jq -r '.zone' deployment_state.json 2>/dev/null || echo "")
    APIGEE_ORG=$(jq -r '.apigee_org' deployment_state.json 2>/dev/null || echo "")
    ENV_NAME=$(jq -r '.env_name' deployment_state.json 2>/dev/null || echo "")
    STORAGE_BUCKET=$(jq -r '.storage_bucket' deployment_state.json 2>/dev/null || echo "")
    
    log_info "Loaded deployment state:"
    log_info "  PROJECT_ID: ${PROJECT_ID}"
    log_info "  REGION: ${REGION}"
    log_info "  ENV_NAME: ${ENV_NAME}"
    log_info "  STORAGE_BUCKET: ${STORAGE_BUCKET}"
else
    log_warning "No deployment_state.json found. Using environment variables or defaults."
    
    # Use environment variables or prompt for required values
    if [[ -z "${PROJECT_ID:-}" ]]; then
        if [[ "$FORCE" == "false" ]]; then
            read -p "Enter PROJECT_ID to clean up: " PROJECT_ID
        else
            log_error "PROJECT_ID is required for cleanup"
            exit 1
        fi
    fi
    
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export APIGEE_ORG="${APIGEE_ORG:-$PROJECT_ID}"
    
    # Try to determine ENV_NAME and STORAGE_BUCKET if not provided
    if [[ -z "${ENV_NAME:-}" ]]; then
        log_warning "ENV_NAME not provided. Will attempt to find and delete all environments."
    fi
    
    if [[ -z "${STORAGE_BUCKET:-}" ]]; then
        log_warning "STORAGE_BUCKET not provided. Will attempt to find governance-related buckets."
    fi
fi

# Confirmation prompt
if [[ "$FORCE" == "false" ]] && [[ "$DRY_RUN" == "false" ]]; then
    log_warning "This will delete ALL resources for the API Governance solution in project: ${PROJECT_ID}"
    log_warning "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
fi

# Set default project
if [[ "$DRY_RUN" == "false" ]]; then
    gcloud config set project "${PROJECT_ID}"
    log_success "Default project set to: ${PROJECT_ID}"
fi

# 1. Delete Cloud Functions and Eventarc Triggers
log_info "Deleting Cloud Functions and Eventarc triggers..."

if [[ "$DRY_RUN" == "false" ]]; then
    # Delete Cloud Functions
    FUNCTIONS=("api-compliance-monitor" "api-policy-enforcer")
    for func in "${FUNCTIONS[@]}"; do
        if gcloud functions describe "$func" --region="${REGION}" --project="${PROJECT_ID}" &> /dev/null; then
            log_info "Deleting Cloud Function: $func"
            gcloud functions delete "$func" \
                --region="${REGION}" \
                --project="${PROJECT_ID}" \
                --quiet
            log_success "Cloud Function deleted: $func"
        else
            log_info "Cloud Function not found: $func"
        fi
    done
    
    # Delete Eventarc triggers
    TRIGGERS=("api-security-violations" "api-quota-violations")
    for trigger in "${TRIGGERS[@]}"; do
        if gcloud eventarc triggers describe "$trigger" --location="${REGION}" --project="${PROJECT_ID}" &> /dev/null; then
            log_info "Deleting Eventarc trigger: $trigger"
            gcloud eventarc triggers delete "$trigger" \
                --location="${REGION}" \
                --project="${PROJECT_ID}" \
                --quiet
            log_success "Eventarc trigger deleted: $trigger"
        else
            log_info "Eventarc trigger not found: $trigger"
        fi
    done
else
    log_info "[DRY-RUN] Would delete Cloud Functions: api-compliance-monitor, api-policy-enforcer"
    log_info "[DRY-RUN] Would delete Eventarc triggers: api-security-violations, api-quota-violations"
fi

# 2. Delete Monitoring and Alerting Resources
log_info "Deleting monitoring and alerting resources..."

if [[ "$DRY_RUN" == "false" ]]; then
    # Delete alert policies
    log_info "Deleting alert policies..."
    ALERT_POLICIES=$(gcloud alpha monitoring policies list --project="${PROJECT_ID}" --format="value(name)" --filter="displayName:('API Governance Violations')" 2>/dev/null || echo "")
    
    if [[ -n "$ALERT_POLICIES" ]]; then
        echo "$ALERT_POLICIES" | while read -r policy; do
            if [[ -n "$policy" ]]; then
                log_info "Deleting alert policy: $policy"
                gcloud alpha monitoring policies delete "$policy" --project="${PROJECT_ID}" --quiet
                log_success "Alert policy deleted: $policy"
            fi
        done
    else
        log_info "No matching alert policies found"
    fi
    
    # Delete monitoring dashboards
    log_info "Deleting monitoring dashboards..."
    DASHBOARDS=$(gcloud monitoring dashboards list --project="${PROJECT_ID}" --format="value(name)" --filter="displayName:('API Governance Dashboard')" 2>/dev/null || echo "")
    
    if [[ -n "$DASHBOARDS" ]]; then
        echo "$DASHBOARDS" | while read -r dashboard; do
            if [[ -n "$dashboard" ]]; then
                log_info "Deleting dashboard: $dashboard"
                gcloud monitoring dashboards delete "$dashboard" --project="${PROJECT_ID}" --quiet
                log_success "Dashboard deleted: $dashboard"
            fi
        done
    else
        log_info "No matching dashboards found"
    fi
else
    log_info "[DRY-RUN] Would delete monitoring alert policies and dashboards"
fi

# 3. Delete Log Sinks
log_info "Deleting Cloud Logging sinks..."

if [[ "$DRY_RUN" == "false" ]]; then
    LOG_SINKS=("apigee-governance-sink" "apigee-realtime-sink")
    for sink in "${LOG_SINKS[@]}"; do
        if gcloud logging sinks describe "$sink" --project="${PROJECT_ID}" &> /dev/null; then
            log_info "Deleting log sink: $sink"
            gcloud logging sinks delete "$sink" --project="${PROJECT_ID}" --quiet
            log_success "Log sink deleted: $sink"
        else
            log_info "Log sink not found: $sink"
        fi
    done
else
    log_info "[DRY-RUN] Would delete log sinks: apigee-governance-sink, apigee-realtime-sink"
fi

# 4. Delete Pub/Sub Topic
log_info "Deleting Pub/Sub topic..."

if [[ "$DRY_RUN" == "false" ]]; then
    if gcloud pubsub topics describe api-governance-events --project="${PROJECT_ID}" &> /dev/null; then
        log_info "Deleting Pub/Sub topic: api-governance-events"
        gcloud pubsub topics delete api-governance-events --project="${PROJECT_ID}" --quiet
        log_success "Pub/Sub topic deleted: api-governance-events"
    else
        log_info "Pub/Sub topic not found: api-governance-events"
    fi
else
    log_info "[DRY-RUN] Would delete Pub/Sub topic: api-governance-events"
fi

# 5. Delete Apigee Environment
log_info "Deleting Apigee environment..."

if [[ "$DRY_RUN" == "false" ]]; then
    if [[ -n "${ENV_NAME:-}" ]]; then
        if gcloud alpha apigee environments describe "${ENV_NAME}" --organization="${APIGEE_ORG}" &> /dev/null; then
            log_info "Deleting Apigee environment: ${ENV_NAME}"
            gcloud alpha apigee environments delete "${ENV_NAME}" \
                --organization="${APIGEE_ORG}" \
                --quiet
            log_success "Apigee environment deleted: ${ENV_NAME}"
        else
            log_info "Apigee environment not found: ${ENV_NAME}"
        fi
    else
        log_warning "ENV_NAME not specified. Please manually delete Apigee environments if needed."
    fi
else
    log_info "[DRY-RUN] Would delete Apigee environment: ${ENV_NAME}"
fi

# 6. Delete BigQuery Dataset
log_info "Deleting BigQuery dataset..."

if [[ "$DRY_RUN" == "false" ]]; then
    if bq ls --project_id="${PROJECT_ID}" | grep -q "api_governance"; then
        log_info "Deleting BigQuery dataset: api_governance"
        bq rm -r -f "${PROJECT_ID}:api_governance"
        log_success "BigQuery dataset deleted: api_governance"
    else
        log_info "BigQuery dataset not found: api_governance"
    fi
else
    log_info "[DRY-RUN] Would delete BigQuery dataset: api_governance"
fi

# 7. Delete Cloud Storage Bucket
log_info "Deleting Cloud Storage bucket..."

if [[ "$DRY_RUN" == "false" ]]; then
    if [[ -n "${STORAGE_BUCKET:-}" ]]; then
        if gsutil ls -b "gs://${STORAGE_BUCKET}" &> /dev/null; then
            log_info "Deleting Cloud Storage bucket: ${STORAGE_BUCKET}"
            gsutil -m rm -r "gs://${STORAGE_BUCKET}"
            log_success "Cloud Storage bucket deleted: ${STORAGE_BUCKET}"
        else
            log_info "Cloud Storage bucket not found: ${STORAGE_BUCKET}"
        fi
    else
        # Try to find governance-related buckets
        log_info "Searching for governance-related storage buckets..."
        GOVERNANCE_BUCKETS=$(gsutil ls -p "${PROJECT_ID}" | grep -E "(governance|api-governance)" || echo "")
        
        if [[ -n "$GOVERNANCE_BUCKETS" ]]; then
            echo "$GOVERNANCE_BUCKETS" | while read -r bucket; do
                if [[ -n "$bucket" ]]; then
                    log_info "Found governance bucket: $bucket"
                    if [[ "$FORCE" == "false" ]]; then
                        read -p "Delete this bucket? (yes/no): " confirm_bucket
                        if [[ "$confirm_bucket" == "yes" ]]; then
                            gsutil -m rm -r "$bucket"
                            log_success "Bucket deleted: $bucket"
                        fi
                    else
                        gsutil -m rm -r "$bucket"
                        log_success "Bucket deleted: $bucket"
                    fi
                fi
            done
        else
            log_info "No governance-related storage buckets found"
        fi
    fi
else
    log_info "[DRY-RUN] Would delete Cloud Storage bucket: ${STORAGE_BUCKET}"
fi

# 8. Delete Service Accounts (if any were created)
log_info "Checking for custom service accounts..."

if [[ "$DRY_RUN" == "false" ]]; then
    # Look for any custom service accounts created for the solution
    CUSTOM_SA=$(gcloud iam service-accounts list --project="${PROJECT_ID}" --format="value(email)" --filter="displayName:('API Governance')" 2>/dev/null || echo "")
    
    if [[ -n "$CUSTOM_SA" ]]; then
        echo "$CUSTOM_SA" | while read -r sa; do
            if [[ -n "$sa" ]]; then
                log_info "Deleting service account: $sa"
                gcloud iam service-accounts delete "$sa" --project="${PROJECT_ID}" --quiet
                log_success "Service account deleted: $sa"
            fi
        done
    else
        log_info "No custom service accounts found"
    fi
else
    log_info "[DRY-RUN] Would check for and delete custom service accounts"
fi

# 9. Cleanup deployment state file
log_info "Cleaning up deployment state file..."

if [[ -f "deployment_state.json" ]]; then
    if [[ "$DRY_RUN" == "false" ]]; then
        rm -f deployment_state.json
        log_success "Deployment state file removed"
    else
        log_info "[DRY-RUN] Would remove deployment_state.json"
    fi
else
    log_info "No deployment state file found"
fi

# Final validation
log_info "Running cleanup validation..."

if [[ "$DRY_RUN" == "false" ]]; then
    # Check if resources still exist
    REMAINING_RESOURCES=()
    
    # Check Cloud Functions
    if gcloud functions list --project="${PROJECT_ID}" --format="value(name)" | grep -E "(api-compliance-monitor|api-policy-enforcer)" &> /dev/null; then
        REMAINING_RESOURCES+=("Cloud Functions")
    fi
    
    # Check Pub/Sub topics
    if gcloud pubsub topics list --project="${PROJECT_ID}" --format="value(name)" | grep "api-governance-events" &> /dev/null; then
        REMAINING_RESOURCES+=("Pub/Sub Topics")
    fi
    
    # Check BigQuery datasets
    if bq ls --project_id="${PROJECT_ID}" | grep -q "api_governance"; then
        REMAINING_RESOURCES+=("BigQuery Datasets")
    fi
    
    # Check Storage buckets
    if gsutil ls -p "${PROJECT_ID}" | grep -E "(governance|api-governance)" &> /dev/null; then
        REMAINING_RESOURCES+=("Cloud Storage Buckets")
    fi
    
    if [[ ${#REMAINING_RESOURCES[@]} -gt 0 ]]; then
        log_warning "Some resources may still exist:"
        for resource in "${REMAINING_RESOURCES[@]}"; do
            log_warning "  - $resource"
        done
        log_warning "Please check the Google Cloud Console and manually delete any remaining resources."
    else
        log_success "✅ All resources appear to have been cleaned up successfully"
    fi
fi

# Display cleanup summary
log_success "=== CLEANUP COMPLETE ==="
log_info "Project ID: ${PROJECT_ID}"
log_info ""
log_info "Deleted Resources:"
log_info "  ✅ Cloud Functions: api-compliance-monitor, api-policy-enforcer"
log_info "  ✅ Eventarc Triggers: api-security-violations, api-quota-violations"
log_info "  ✅ Monitoring Resources: Alert policies, dashboards"
log_info "  ✅ Log Sinks: apigee-governance-sink, apigee-realtime-sink"
log_info "  ✅ Pub/Sub Topic: api-governance-events"
log_info "  ✅ BigQuery Dataset: api_governance"
log_info "  ✅ Cloud Storage Bucket: ${STORAGE_BUCKET:-governance-functions-*}"
log_info "  ✅ Apigee Environment: ${ENV_NAME:-dev-*}"
log_info ""
log_info "Important Notes:"
log_info "• Apigee X organization requires manual deletion through the console"
log_info "• Some API permissions may remain active for a few minutes"
log_info "• Check the Google Cloud Console for any remaining resources"
log_info "• Billing may continue for a short period after resource deletion"
log_info ""
log_info "For complete cleanup verification, visit:"
log_info "• Cloud Functions: https://console.cloud.google.com/functions/list"
log_info "• Eventarc: https://console.cloud.google.com/eventarc/triggers"
log_info "• Monitoring: https://console.cloud.google.com/monitoring"
log_info "• Apigee: https://console.cloud.google.com/apigee"

log_success "API Governance and Compliance Monitoring cleanup completed successfully!"

# Exit with success
exit 0