#!/bin/bash

# =============================================================================
# Intelligent Resource Optimization with Agent Builder and Asset Inventory
# Cleanup/Destroy Script for GCP
# =============================================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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
}

# Configuration variables with defaults
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../deployment_config.txt"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"
DRY_RUN="${DRY_RUN:-false}"
FORCE_DELETE="${FORCE_DELETE:-false}"

# Default values (will be overridden by config file if it exists)
PROJECT_ID=""
REGION="us-central1"
ZONE="us-central1-a"
DATASET_NAME=""
BUCKET_NAME=""
JOB_NAME=""
FUNCTION_NAME=""
SERVICE_ACCOUNT_NAME="asset-export-scheduler"

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Intelligent Resource Optimization infrastructure

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID
    -r, --region REGION           GCP Region
    -z, --zone ZONE              GCP Zone
    -c, --config-file FILE       Configuration file path (default: ../deployment_config.txt)
    -d, --dry-run                Show what would be destroyed without executing
    -f, --force                  Force deletion without prompts (DANGEROUS)
    -y, --yes                    Skip confirmation prompts
    -h, --help                   Display this help message

ENVIRONMENT VARIABLES:
    PROJECT_ID                   GCP Project ID
    REGION                      GCP Region
    ZONE                        GCP Zone
    SKIP_CONFIRMATION           Skip confirmation prompts (true/false)
    DRY_RUN                     Dry run mode (true/false)
    FORCE_DELETE                Force deletion mode (true/false)

EXAMPLES:
    $0                          # Destroy using saved configuration
    $0 -p my-project -r us-west1 # Destroy specific project resources
    $0 -d                       # Dry run to see what would be destroyed
    $0 -f                       # Force deletion without prompts (DANGEROUS)

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -c|--config-file)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -f|--force)
                FORCE_DELETE="true"
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown argument: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Load configuration from file
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log "Loading configuration from: $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        success "Configuration loaded successfully"
    else
        warning "Configuration file not found: $CONFIG_FILE"
        warning "You must provide project details manually"
        
        if [[ -z "$PROJECT_ID" ]]; then
            error "PROJECT_ID is required. Use -p option or set environment variable."
            exit 1
        fi
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error "bq CLI is not installed. Please install Google Cloud SDK with BigQuery components."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK with Cloud Storage components."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Validate project and set configuration
validate_project() {
    log "Validating project configuration..."
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        error "Project '$PROJECT_ID' does not exist or you don't have access to it."
        exit 1
    fi
    
    # Set default project
    gcloud config set project "$PROJECT_ID" --quiet
    gcloud config set compute/region "$REGION" --quiet
    gcloud config set compute/zone "$ZONE" --quiet
    
    success "Project validation completed"
}

# Display resources to be deleted
display_resources() {
    log "Resources to be deleted:"
    echo "========================"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo ""
    echo "Resources:"
    
    if [[ -n "$DATASET_NAME" ]]; then
        echo "- BigQuery Dataset: $DATASET_NAME"
    fi
    
    if [[ -n "$BUCKET_NAME" ]]; then
        echo "- Storage Bucket: gs://$BUCKET_NAME"
    fi
    
    if [[ -n "$FUNCTION_NAME" ]]; then
        echo "- Cloud Function: $FUNCTION_NAME"
    fi
    
    if [[ -n "$JOB_NAME" ]]; then
        echo "- Cloud Scheduler Job: $JOB_NAME"
    fi
    
    if [[ -n "$SERVICE_ACCOUNT_NAME" ]]; then
        echo "- Service Account: $SERVICE_ACCOUNT_NAME"
    fi
    
    echo "- Vertex AI Agent: resource-optimization-agent (if exists)"
    echo "- Configuration files and local artifacts"
    echo ""
}

# Check if resources exist
check_resource_existence() {
    log "Checking resource existence..."
    
    local resources_found=false
    
    # Check BigQuery dataset
    if [[ -n "$DATASET_NAME" ]] && bq show "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
        log "Found BigQuery dataset: $DATASET_NAME"
        resources_found=true
    fi
    
    # Check storage bucket
    if [[ -n "$BUCKET_NAME" ]] && gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
        log "Found storage bucket: gs://$BUCKET_NAME"
        resources_found=true
    fi
    
    # Check Cloud Function
    if [[ -n "$FUNCTION_NAME" ]] && gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &> /dev/null; then
        log "Found Cloud Function: $FUNCTION_NAME"
        resources_found=true
    fi
    
    # Check Cloud Scheduler job
    if [[ -n "$JOB_NAME" ]] && gcloud scheduler jobs describe "$JOB_NAME" --location="$REGION" &> /dev/null; then
        log "Found Cloud Scheduler job: $JOB_NAME"
        resources_found=true
    fi
    
    # Check service account
    if [[ -n "$SERVICE_ACCOUNT_NAME" ]] && gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" &> /dev/null; then
        log "Found service account: $SERVICE_ACCOUNT_NAME"
        resources_found=true
    fi
    
    if [[ "$resources_found" == "false" ]]; then
        warning "No resources found to delete. This might indicate:"
        warning "1. Resources were already deleted"
        warning "2. Different project or configuration"
        warning "3. Configuration file is missing or incorrect"
    fi
    
    return 0
}

# Delete Cloud Scheduler job
delete_scheduler_job() {
    log "Deleting Cloud Scheduler job..."
    
    if [[ -z "$JOB_NAME" ]]; then
        warning "No job name specified, skipping scheduler job deletion"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete Cloud Scheduler job: $JOB_NAME"
        return 0
    fi
    
    if gcloud scheduler jobs describe "$JOB_NAME" --location="$REGION" &> /dev/null; then
        log "Deleting Cloud Scheduler job: $JOB_NAME"
        gcloud scheduler jobs delete "$JOB_NAME" \
            --location="$REGION" \
            --quiet || warning "Failed to delete scheduler job"
        success "Cloud Scheduler job deleted"
    else
        warning "Cloud Scheduler job not found: $JOB_NAME"
    fi
}

# Delete Vertex AI Agent
delete_vertex_ai_agent() {
    log "Deleting Vertex AI Agent..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete Vertex AI Agent"
        return 0
    fi
    
    # Check if agent resource name file exists
    local agent_file="${SCRIPT_DIR}/../agent_resource_name.txt"
    if [[ -f "$agent_file" ]]; then
        local agent_resource_name
        agent_resource_name=$(cat "$agent_file")
        
        log "Deleting Vertex AI Agent: $agent_resource_name"
        
        # Create temporary Python script to delete agent
        local temp_file
        temp_file=$(mktemp)
        
        cat > "$temp_file" << EOF
import vertexai
from vertexai import agent_engines
import sys

try:
    vertexai.init(project="$PROJECT_ID", location="$REGION")
    agent = agent_engines.get("$agent_resource_name")
    agent.delete(force=True)
    print("Agent deleted successfully")
except Exception as e:
    print(f"Error deleting agent: {str(e)}")
    sys.exit(1)
EOF
        
        if python3 "$temp_file"; then
            success "Vertex AI Agent deleted"
            rm -f "$agent_file"
        else
            warning "Failed to delete Vertex AI Agent"
        fi
        
        rm -f "$temp_file"
    else
        warning "Agent resource name file not found, checking for agents by name"
        
        # Try to find and delete agents by display name
        python3 -c "
import vertexai
from vertexai import agent_engines
try:
    vertexai.init(project='$PROJECT_ID', location='$REGION')
    # List agents and delete those with our display name
    print('Checking for agents with display_name: resource-optimization-agent')
    # Note: The agent_engines API may not support listing agents by name
    # This is a best-effort attempt
except Exception as e:
    print(f'Could not check for agents: {str(e)}')
" || warning "Could not check for Vertex AI Agents"
    fi
}

# Delete Cloud Function
delete_cloud_function() {
    log "Deleting Cloud Function..."
    
    if [[ -z "$FUNCTION_NAME" ]]; then
        warning "No function name specified, skipping Cloud Function deletion"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete Cloud Function: $FUNCTION_NAME"
        return 0
    fi
    
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &> /dev/null; then
        log "Deleting Cloud Function: $FUNCTION_NAME"
        gcloud functions delete "$FUNCTION_NAME" \
            --region="$REGION" \
            --quiet || warning "Failed to delete Cloud Function"
        success "Cloud Function deleted"
    else
        warning "Cloud Function not found: $FUNCTION_NAME"
    fi
}

# Delete BigQuery resources
delete_bigquery_resources() {
    log "Deleting BigQuery resources..."
    
    if [[ -z "$DATASET_NAME" ]]; then
        warning "No dataset name specified, skipping BigQuery deletion"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete BigQuery dataset: $DATASET_NAME"
        return 0
    fi
    
    if bq show "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
        log "Deleting BigQuery dataset: $DATASET_NAME"
        bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" || warning "Failed to delete BigQuery dataset"
        success "BigQuery dataset deleted"
    else
        warning "BigQuery dataset not found: $DATASET_NAME"
    fi
}

# Delete storage bucket
delete_storage_bucket() {
    log "Deleting storage bucket..."
    
    if [[ -z "$BUCKET_NAME" ]]; then
        warning "No bucket name specified, skipping storage bucket deletion"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete storage bucket: gs://$BUCKET_NAME"
        return 0
    fi
    
    if gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
        log "Deleting storage bucket: gs://$BUCKET_NAME"
        
        # Delete all objects first
        log "Deleting all objects in bucket..."
        gsutil -m rm -r "gs://$BUCKET_NAME/**" 2>/dev/null || true
        
        # Delete the bucket
        gsutil rb "gs://$BUCKET_NAME" || warning "Failed to delete storage bucket"
        success "Storage bucket deleted"
    else
        warning "Storage bucket not found: gs://$BUCKET_NAME"
    fi
}

# Delete service account
delete_service_account() {
    log "Deleting service account..."
    
    if [[ -z "$SERVICE_ACCOUNT_NAME" ]]; then
        warning "No service account name specified, skipping service account deletion"
        return 0
    fi
    
    local sa_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete service account: $sa_email"
        return 0
    fi
    
    if gcloud iam service-accounts describe "$sa_email" &> /dev/null; then
        log "Deleting service account: $sa_email"
        
        # Remove IAM policy bindings first
        log "Removing IAM policy bindings..."
        gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$sa_email" \
            --role="roles/cloudasset.viewer" \
            --quiet 2>/dev/null || true
        
        gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$sa_email" \
            --role="roles/bigquery.dataEditor" \
            --quiet 2>/dev/null || true
        
        gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$sa_email" \
            --role="roles/cloudfunctions.invoker" \
            --quiet 2>/dev/null || true
        
        # Delete the service account
        gcloud iam service-accounts delete "$sa_email" \
            --quiet || warning "Failed to delete service account"
        success "Service account deleted"
    else
        warning "Service account not found: $sa_email"
    fi
}

# Clean up configuration files and local artifacts
cleanup_local_files() {
    log "Cleaning up local files and artifacts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would clean up local configuration files"
        return 0
    fi
    
    # List of files to clean up
    local files_to_remove=(
        "${SCRIPT_DIR}/../agent_resource_name.txt"
        "${SCRIPT_DIR}/../deployment_config.txt"
        "${SCRIPT_DIR}/../monitoring-policy.yaml"
        "${SCRIPT_DIR}/../export_function.py"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            log "Removing file: $(basename "$file")"
            rm -f "$file"
        fi
    done
    
    # Clean up any temporary directories
    if [[ -d "${SCRIPT_DIR}/../agent-workspace" ]]; then
        log "Removing agent workspace directory"
        rm -rf "${SCRIPT_DIR}/../agent-workspace"
    fi
    
    success "Local file cleanup completed"
}

# Display destruction summary
display_summary() {
    log "Destruction Summary"
    echo "==================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo ""
    echo "Deleted Resources:"
    echo "- Cloud Scheduler Job: ${JOB_NAME:-N/A}"
    echo "- Vertex AI Agent: resource-optimization-agent"
    echo "- Cloud Function: ${FUNCTION_NAME:-N/A}"
    echo "- BigQuery Dataset: ${DATASET_NAME:-N/A}"
    echo "- Storage Bucket: ${BUCKET_NAME:-N/A}"
    echo "- Service Account: ${SERVICE_ACCOUNT_NAME:-N/A}"
    echo "- Local configuration files"
    echo ""
    echo "Note: Some resources may not have existed or failed to delete."
    echo "Check the logs above for any warnings or errors."
    echo ""
}

# Confirmation prompt with safety checks
confirm_destruction() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        warning "FORCE_DELETE mode enabled - skipping confirmation prompts"
        return 0
    fi
    
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "========================================"
    echo "WARNING: DESTRUCTIVE OPERATION"
    echo "========================================"
    echo ""
    echo "This will permanently delete the following resources:"
    display_resources
    echo ""
    echo "This action CANNOT be undone!"
    echo ""
    
    # First confirmation
    read -p "Are you sure you want to delete these resources? (type 'yes' to confirm): " -r
    if [[ "$REPLY" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    # Second confirmation for extra safety
    echo ""
    read -p "This will permanently delete data and resources. Type 'DELETE' to confirm: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    echo ""
    log "Destruction confirmed. Proceeding..."
}

# Main destruction function
main() {
    echo "================================================"
    echo "Intelligent Resource Optimization Cleanup"
    echo "================================================"
    echo ""
    
    parse_args "$@"
    load_config
    
    # Display configuration
    log "Cleanup Configuration:"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo "Dry Run: $DRY_RUN"
    echo "Force Delete: $FORCE_DELETE"
    echo ""
    
    check_prerequisites
    validate_project
    check_resource_existence
    
    if [[ "$DRY_RUN" == "false" ]]; then
        confirm_destruction
    fi
    
    # Execute destruction steps in reverse order of creation
    delete_scheduler_job
    delete_vertex_ai_agent
    delete_cloud_function
    delete_bigquery_resources
    delete_storage_bucket
    delete_service_account
    cleanup_local_files
    
    if [[ "$DRY_RUN" == "false" ]]; then
        display_summary
        success "Cleanup completed successfully!"
    else
        log "Dry run completed. No resources were deleted."
    fi
}

# Cleanup on script exit
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        error "Cleanup script failed. Some resources may remain."
        error "Check the logs above and manually clean up any remaining resources."
    fi
}

trap cleanup_on_exit EXIT

# Execute main function
main "$@"