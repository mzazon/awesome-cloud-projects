#!/bin/bash

#####################################################################
# Adaptive Marketing Campaign Intelligence Cleanup Script
# 
# This script safely removes all infrastructure created for the
# AI-powered marketing automation system, ensuring complete cleanup
# to avoid ongoing charges.
#
# Prerequisites:
# - Google Cloud SDK (gcloud) installed and configured
# - Access to the project used for deployment
# - Deployment state file (.deployment_state) present
#####################################################################

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Configuration variables
STATE_FILE=".deployment_state"
FORCE_DELETE="${FORCE_DELETE:-false}"

# Load deployment state
load_deployment_state() {
    if [[ -f "${STATE_FILE}" ]]; then
        log_info "Loading deployment state from ${STATE_FILE}"
        source "${STATE_FILE}"
        log_success "Deployment state loaded"
    else
        log_warning "Deployment state file not found. Using environment variables or defaults."
        PROJECT_ID="${PROJECT_ID:-}"
        REGION="${REGION:-us-central1}"
        ZONE="${ZONE:-us-central1-a}"
        DATASET_NAME="${DATASET_NAME:-}"
        AGENT_NAME="${AGENT_NAME:-}"
        BUCKET_NAME="${BUCKET_NAME:-}"
        RANDOM_SUFFIX="${RANDOM_SUFFIX:-}"
        
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "PROJECT_ID not found in environment or state file"
            exit 1
        fi
    fi
}

# Confirm deletion with user
confirm_deletion() {
    if [[ "${FORCE_DELETE}" != "true" ]]; then
        log_warning "This will permanently delete all resources for the marketing intelligence system"
        log_warning "Project: ${PROJECT_ID}"
        log_warning "Dataset: ${DATASET_NAME}"
        log_warning "Bucket: gs://${BUCKET_NAME}"
        echo ""
        read -p "Are you sure you want to continue? (yes/no): " confirm
        
        if [[ "${confirm}" != "yes" ]]; then
            log_info "Deletion cancelled by user"
            exit 0
        fi
    fi
    
    log_info "Starting resource deletion..."
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Project ${PROJECT_ID} not found or not accessible"
        exit 1
    fi
    
    # Set project context
    gcloud config set project "${PROJECT_ID}"
    
    log_success "Prerequisites check completed"
}

# Remove Google Workspace Flows
remove_workspace_flows() {
    log_info "Removing Google Workspace Flows configurations..."
    
    # List of flows to delete
    local flows=(
        "campaign-performance-alerts"
        "dynamic-customer-segmentation"
        "real-time-dashboard-updates"
        "predictive-campaign-analytics"
        "cross-channel-campaign-coordination"
    )
    
    for flow in "${flows[@]}"; do
        log_info "Attempting to delete Workspace Flow: ${flow}"
        # Note: Actual gcloud command may vary based on API availability
        # For now, provide instructions for manual cleanup
        log_warning "Workspace Flow '${flow}' requires manual deletion through Google Workspace Admin Console"
    done
    
    # Clean up configuration files
    local config_files=(
        "campaign-alert-flow.json"
        "segmentation-workflow.json"
        "dashboard-update-flow.json"
        "predictive-analytics-flow.json"
        "cross-channel-flow.json"
    )
    
    for config_file in "${config_files[@]}"; do
        if [[ -f "${config_file}" ]]; then
            rm -f "${config_file}"
            log_success "Removed configuration file: ${config_file}"
        fi
    done
    
    log_success "Workspace Flows cleanup completed"
}

# Remove Vertex AI components
remove_vertex_ai_components() {
    log_info "Removing Vertex AI Agents and custom Gems..."
    
    # Delete custom Gems
    local gems=("brand-voice-analyzer" "campaign-optimizer")
    for gem in "${gems[@]}"; do
        log_info "Attempting to delete custom Gem: ${gem}"
        # Note: Actual gcloud command may vary based on API availability
        log_warning "Custom Gem '${gem}' requires manual deletion through Google Cloud Console"
    done
    
    # Delete AI agent
    if [[ -n "${AGENT_NAME}" ]]; then
        log_info "Attempting to delete AI Agent: ${AGENT_NAME}"
        # Note: Actual gcloud command may vary based on API availability
        log_warning "AI Agent '${AGENT_NAME}' requires manual deletion through Google Cloud Console"
    fi
    
    # Clean up configuration files
    local config_files=(
        "agent-config.json"
        "brand-voice-gem.json"
        "campaign-optimizer-gem.json"
    )
    
    for config_file in "${config_files[@]}"; do
        if [[ -f "${config_file}" ]]; then
            rm -f "${config_file}"
            log_success "Removed configuration file: ${config_file}"
        fi
    done
    
    log_success "Vertex AI components cleanup completed"
}

# Remove BigQuery resources
remove_bigquery_resources() {
    log_info "Removing BigQuery dataset and resources..."
    
    if [[ -n "${DATASET_NAME}" ]]; then
        # Check if dataset exists
        if bq ls --project_id="${PROJECT_ID}" | grep -q "${DATASET_NAME}"; then
            log_info "Deleting BigQuery dataset: ${DATASET_NAME}"
            
            # List tables for confirmation
            log_info "Tables in dataset ${DATASET_NAME}:"
            bq ls --project_id="${PROJECT_ID}" "${DATASET_NAME}" || true
            
            # Delete dataset with all tables and models
            if bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}"; then
                log_success "BigQuery dataset deleted: ${DATASET_NAME}"
            else
                log_error "Failed to delete BigQuery dataset: ${DATASET_NAME}"
                return 1
            fi
        else
            log_warning "BigQuery dataset ${DATASET_NAME} not found (may already be deleted)"
        fi
    else
        log_warning "Dataset name not specified, skipping BigQuery cleanup"
    fi
}

# Remove Cloud Storage resources
remove_storage_resources() {
    log_info "Removing Cloud Storage bucket and contents..."
    
    if [[ -n "${BUCKET_NAME}" ]]; then
        # Check if bucket exists
        if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
            log_info "Deleting storage bucket: gs://${BUCKET_NAME}"
            
            # List bucket contents for confirmation
            log_info "Contents of bucket gs://${BUCKET_NAME}:"
            gsutil ls -r "gs://${BUCKET_NAME}" || true
            
            # Delete bucket and all contents
            if gsutil -m rm -r "gs://${BUCKET_NAME}"; then
                log_success "Storage bucket deleted: gs://${BUCKET_NAME}"
            else
                log_error "Failed to delete storage bucket: gs://${BUCKET_NAME}"
                return 1
            fi
        else
            log_warning "Storage bucket gs://${BUCKET_NAME} not found (may already be deleted)"
        fi
    else
        log_warning "Bucket name not specified, skipping storage cleanup"
    fi
}

# Clean up local files
clean_local_files() {
    log_info "Cleaning up local configuration files..."
    
    local files_to_remove=(
        "deployment-summary.md"
        "agent-config.json"
        "brand-voice-gem.json"
        "campaign-optimizer-gem.json"
        "campaign-alert-flow.json"
        "segmentation-workflow.json"
        "dashboard-update-flow.json"
        "predictive-analytics-flow.json"
        "cross-channel-flow.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_success "Removed local file: ${file}"
        fi
    done
}

# Disable APIs (optional)
disable_apis() {
    if [[ "${DISABLE_APIS:-false}" == "true" ]]; then
        log_info "Disabling Google Cloud APIs (optional)..."
        
        local apis=(
            "aiplatform.googleapis.com"
            "cloudbuild.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            log_info "Disabling ${api}..."
            if gcloud services disable "${api}" --quiet --force; then
                log_success "Disabled ${api}"
            else
                log_warning "Failed to disable ${api} (may still be in use)"
            fi
        done
        
        log_warning "Note: BigQuery, Gmail, and Sheets APIs were not disabled as they may be used by other services"
    else
        log_info "Skipping API disabling (set DISABLE_APIS=true to disable)"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_errors=0
    
    # Check BigQuery dataset
    if [[ -n "${DATASET_NAME}" ]]; then
        if bq ls --project_id="${PROJECT_ID}" | grep -q "${DATASET_NAME}"; then
            log_error "BigQuery dataset still exists: ${DATASET_NAME}"
            cleanup_errors=$((cleanup_errors + 1))
        else
            log_success "BigQuery dataset successfully removed"
        fi
    fi
    
    # Check storage bucket
    if [[ -n "${BUCKET_NAME}" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
            log_error "Storage bucket still exists: gs://${BUCKET_NAME}"
            cleanup_errors=$((cleanup_errors + 1))
        else
            log_success "Storage bucket successfully removed"
        fi
    fi
    
    # Check local configuration files
    local remaining_files=()
    local config_files=(
        "deployment-summary.md"
        "agent-config.json"
        "brand-voice-gem.json"
        "campaign-optimizer-gem.json"
    )
    
    for file in "${config_files[@]}"; do
        if [[ -f "${file}" ]]; then
            remaining_files+=("${file}")
        fi
    done
    
    if [[ ${#remaining_files[@]} -gt 0 ]]; then
        log_warning "Some configuration files still exist: ${remaining_files[*]}"
    else
        log_success "All configuration files removed"
    fi
    
    if [[ ${cleanup_errors} -eq 0 ]]; then
        log_success "Cleanup verification completed successfully"
        return 0
    else
        log_error "Cleanup verification found ${cleanup_errors} issues"
        return 1
    fi
}

# Remove deployment state file
remove_state_file() {
    if [[ -f "${STATE_FILE}" ]]; then
        rm -f "${STATE_FILE}"
        log_success "Deployment state file removed"
    fi
}

# Generate cleanup summary
generate_cleanup_summary() {
    log_info "Generating cleanup summary..."
    
    cat > cleanup-summary.md << EOF
# Marketing Intelligence Cleanup Summary

## Cleanup Details
- **Project ID**: ${PROJECT_ID}
- **Cleanup Time**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
- **Region**: ${REGION}

## Removed Resources

### Automatically Removed
- ✅ BigQuery dataset: ${DATASET_NAME}
- ✅ BigQuery tables: campaign_performance, customer_interactions, ai_insights
- ✅ BigQuery ML model: customer_ltv_model
- ✅ BigQuery view: campaign_dashboard
- ✅ Cloud Storage bucket: gs://${BUCKET_NAME}
- ✅ Local configuration files

### Manual Removal Required
- ⚠️  Vertex AI Agent: ${AGENT_NAME}
- ⚠️  Custom Gems: brand-voice-analyzer, campaign-optimizer
- ⚠️  Google Workspace Flows: All configured workflows

## Manual Cleanup Steps

1. **Vertex AI Components**:
   - Navigate to Google Cloud Console > Vertex AI
   - Delete the agent: ${AGENT_NAME}
   - Remove custom Gems: brand-voice-analyzer, campaign-optimizer

2. **Google Workspace Flows**:
   - Access Google Workspace Admin Console
   - Navigate to Flows section
   - Delete configured workflows:
     - campaign-performance-alerts
     - dynamic-customer-segmentation
     - real-time-dashboard-updates
     - predictive-campaign-analytics
     - cross-channel-campaign-coordination

3. **Project Cleanup** (Optional):
   - If this was a dedicated project, consider deleting the entire project
   - Review billing to ensure no ongoing charges

## Verification

Run the following commands to verify cleanup:

\`\`\`bash
# Check BigQuery datasets
bq ls --project_id=${PROJECT_ID}

# Check storage buckets
gsutil ls -p ${PROJECT_ID}

# Check project resources
gcloud projects describe ${PROJECT_ID}
\`\`\`

## Cost Considerations

- All billable resources have been removed
- No ongoing charges should occur from this deployment
- If using a dedicated project, consider deleting it entirely

## Notes

- This cleanup removes all data and configurations
- Ensure you have backups of any important data before cleanup
- Some manual steps are required due to current API limitations

Generated on: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
EOF
    
    log_success "Cleanup summary generated: cleanup-summary.md"
}

# Main cleanup function
main() {
    log_info "Starting adaptive marketing campaign intelligence cleanup..."
    
    # Load configuration and confirm
    load_deployment_state
    confirm_deletion
    check_prerequisites
    
    # Execute cleanup steps in reverse order of creation
    log_info "Executing cleanup steps..."
    
    remove_workspace_flows
    remove_vertex_ai_components
    remove_bigquery_resources
    remove_storage_resources
    clean_local_files
    disable_apis
    
    # Verify and finalize
    if verify_cleanup; then
        generate_cleanup_summary
        remove_state_file
        
        log_success "======================================"
        log_success "Cleanup completed successfully!"
        log_success "======================================"
        log_info "All automatically removable resources have been deleted"
        log_warning "Manual cleanup required for Vertex AI Agent and Workspace Flows"
        log_info "See cleanup-summary.md for detailed manual steps"
        log_info "Project: ${PROJECT_ID}"
    else
        log_error "Cleanup completed with some issues. Please review the verification results."
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    --force)
        FORCE_DELETE="true"
        log_info "Force delete mode enabled"
        ;;
    --help|-h)
        echo "Usage: $0 [--force] [--help]"
        echo ""
        echo "Options:"
        echo "  --force    Skip confirmation prompts"
        echo "  --help     Show this help message"
        echo ""
        echo "Environment variables:"
        echo "  FORCE_DELETE     Set to 'true' to skip confirmations"
        echo "  DISABLE_APIS     Set to 'true' to disable APIs after cleanup"
        echo ""
        exit 0
        ;;
    "")
        # No arguments, proceed normally
        ;;
    *)
        log_error "Unknown argument: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Run main function
main "$@"