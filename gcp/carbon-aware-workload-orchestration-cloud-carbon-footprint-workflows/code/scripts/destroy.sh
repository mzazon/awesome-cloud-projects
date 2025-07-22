#!/bin/bash

# Destroy script for Carbon-Aware Workload Orchestration with Cloud Carbon Footprint and Cloud Workflows
# This script safely removes all infrastructure created by the deployment script

set -euo pipefail

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
error_exit() {
    log_error "$1"
    exit 1
}

# Default values
DRY_RUN=false
FORCE=false
INTERACTIVE=true
DELETE_PROJECT=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            INTERACTIVE=false
            shift
            ;;
        --yes)
            INTERACTIVE=false
            shift
            ;;
        --delete-project)
            DELETE_PROJECT=true
            shift
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run                 Show what would be deleted without making changes"
            echo "  --force                   Force deletion without confirmation prompts"
            echo "  --yes                     Answer yes to all prompts"
            echo "  --delete-project          Delete the entire GCP project (use with caution)"
            echo "  --config FILE             Load configuration from specific file"
            echo "  --help                    Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                        Interactive cleanup with confirmation prompts"
            echo "  $0 --dry-run              Show what would be deleted"
            echo "  $0 --force                Delete all resources without prompts"
            echo "  $0 --config deploy.env    Use specific configuration file"
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

# Load configuration from file
load_config() {
    local config_file="${CONFIG_FILE:-deployment-config.env}"
    
    if [[ -f "$config_file" ]]; then
        log_info "Loading configuration from $config_file"
        set -a  # Enable automatic export of variables
        source "$config_file"
        set +a  # Disable automatic export of variables
        log_success "Configuration loaded successfully"
    else
        log_warning "Configuration file $config_file not found"
        log_info "Will attempt to discover resources automatically"
        
        # Set basic defaults for discovery
        PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
        REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null)}"
        ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null)}"
        
        if [[ -z "$PROJECT_ID" ]]; then
            error_exit "No project ID found. Please set PROJECT_ID environment variable or provide config file."
        fi
    fi
}

# Confirm destructive action
confirm_action() {
    local action="$1"
    local resource="$2"
    
    if [[ "$INTERACTIVE" == "true" && "$DRY_RUN" == "false" ]]; then
        echo -e "${YELLOW}[CONFIRM]${NC} About to $action: $resource"
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping $action for $resource"
            return 1
        fi
    elif [[ "$DRY_RUN" == "true" ]]; then
        log_info "Would $action: $resource"
        return 1
    fi
    return 0
}

# Discover resources automatically
discover_resources() {
    log_info "Discovering Carbon-Aware Workload Orchestration resources..."
    
    # Discover Cloud Functions
    DISCOVERED_FUNCTIONS=($(gcloud functions list --regions="$REGION" --filter="name~workload-scheduler" --format="value(name)" 2>/dev/null || echo ""))
    
    # Discover Cloud Workflows
    DISCOVERED_WORKFLOWS=($(gcloud workflows list --location="$REGION" --filter="name~carbon-aware-orchestrator" --format="value(name)" 2>/dev/null || echo ""))
    
    # Discover BigQuery datasets
    DISCOVERED_DATASETS=($(bq ls --format="value(datasetId)" 2>/dev/null | grep "carbon_footprint" || echo ""))
    
    # Discover Cloud Scheduler jobs
    DISCOVERED_JOBS=($(gcloud scheduler jobs list --location="$REGION" --filter="name~carbon" --format="value(name)" 2>/dev/null || echo ""))
    
    # Discover Pub/Sub topics
    DISCOVERED_TOPICS=($(gcloud pubsub topics list --filter="name~carbon" --format="value(name)" 2>/dev/null || echo ""))
    
    # Discover Pub/Sub subscriptions
    DISCOVERED_SUBSCRIPTIONS=($(gcloud pubsub subscriptions list --filter="name~carbon OR name~workload" --format="value(name)" 2>/dev/null || echo ""))
    
    # Discover service accounts
    DISCOVERED_SERVICE_ACCOUNTS=($(gcloud iam service-accounts list --filter="email~carbon-footprint" --format="value(email)" 2>/dev/null || echo ""))
    
    log_info "Discovery completed:"
    log_info "- Functions: ${#DISCOVERED_FUNCTIONS[@]} found"
    log_info "- Workflows: ${#DISCOVERED_WORKFLOWS[@]} found"
    log_info "- Datasets: ${#DISCOVERED_DATASETS[@]} found"
    log_info "- Scheduler Jobs: ${#DISCOVERED_JOBS[@]} found"
    log_info "- Pub/Sub Topics: ${#DISCOVERED_TOPICS[@]} found"
    log_info "- Pub/Sub Subscriptions: ${#DISCOVERED_SUBSCRIPTIONS[@]} found"
    log_info "- Service Accounts: ${#DISCOVERED_SERVICE_ACCOUNTS[@]} found"
}

# Remove Cloud Scheduler jobs
remove_scheduler_jobs() {
    log_info "Removing Cloud Scheduler jobs..."
    
    local jobs_to_remove=()
    
    # Use configured job names if available, otherwise use discovered resources
    if [[ -n "${WORKFLOW_NAME:-}" ]]; then
        jobs_to_remove+=("daily-batch-carbon-aware" "weekly-analytics-carbon-aware" "carbon-monitoring")
    else
        jobs_to_remove=("${DISCOVERED_JOBS[@]}")
    fi
    
    for job in "${jobs_to_remove[@]}"; do
        if [[ -n "$job" ]]; then
            if confirm_action "delete scheduler job" "$job"; then
                if gcloud scheduler jobs delete "$job" --location="$REGION" --quiet 2>/dev/null; then
                    log_success "Deleted scheduler job: $job"
                else
                    log_warning "Failed to delete scheduler job: $job (may not exist)"
                fi
            fi
        fi
    done
}

# Remove Cloud Workflows
remove_workflows() {
    log_info "Removing Cloud Workflows..."
    
    local workflows_to_remove=()
    
    # Use configured workflow names if available, otherwise use discovered resources
    if [[ -n "${WORKFLOW_NAME:-}" ]]; then
        workflows_to_remove+=("$WORKFLOW_NAME")
    else
        workflows_to_remove=("${DISCOVERED_WORKFLOWS[@]}")
    fi
    
    for workflow in "${workflows_to_remove[@]}"; do
        if [[ -n "$workflow" ]]; then
            if confirm_action "delete workflow" "$workflow"; then
                if gcloud workflows delete "$workflow" --location="$REGION" --quiet 2>/dev/null; then
                    log_success "Deleted workflow: $workflow"
                else
                    log_warning "Failed to delete workflow: $workflow (may not exist)"
                fi
            fi
        fi
    done
}

# Remove Cloud Functions
remove_functions() {
    log_info "Removing Cloud Functions..."
    
    local functions_to_remove=()
    
    # Use configured function names if available, otherwise use discovered resources
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        functions_to_remove+=("$FUNCTION_NAME")
    else
        functions_to_remove=("${DISCOVERED_FUNCTIONS[@]}")
    fi
    
    for function in "${functions_to_remove[@]}"; do
        if [[ -n "$function" ]]; then
            if confirm_action "delete function" "$function"; then
                if gcloud functions delete "$function" --region="$REGION" --quiet 2>/dev/null; then
                    log_success "Deleted function: $function"
                else
                    log_warning "Failed to delete function: $function (may not exist)"
                fi
            fi
        fi
    done
}

# Remove Pub/Sub resources
remove_pubsub_resources() {
    log_info "Removing Pub/Sub subscriptions and topics..."
    
    local subscriptions_to_remove=()
    local topics_to_remove=()
    
    # Use configured names if available, otherwise use discovered resources
    if [[ -n "${WORKFLOW_NAME:-}" ]]; then
        subscriptions_to_remove+=("carbon-aware-workflow-sub" "workload-status-monitoring")
        topics_to_remove+=("carbon-aware-decisions" "workload-execution-status")
    else
        subscriptions_to_remove=("${DISCOVERED_SUBSCRIPTIONS[@]}")
        topics_to_remove=("${DISCOVERED_TOPICS[@]}")
    fi
    
    # Delete subscriptions first (they depend on topics)
    for subscription in "${subscriptions_to_remove[@]}"; do
        if [[ -n "$subscription" ]]; then
            # Extract just the subscription name from full path if needed
            local sub_name=$(basename "$subscription")
            if confirm_action "delete subscription" "$sub_name"; then
                if gcloud pubsub subscriptions delete "$sub_name" --quiet 2>/dev/null; then
                    log_success "Deleted subscription: $sub_name"
                else
                    log_warning "Failed to delete subscription: $sub_name (may not exist)"
                fi
            fi
        fi
    done
    
    # Delete topics after subscriptions
    for topic in "${topics_to_remove[@]}"; do
        if [[ -n "$topic" ]]; then
            # Extract just the topic name from full path if needed
            local topic_name=$(basename "$topic")
            if confirm_action "delete topic" "$topic_name"; then
                if gcloud pubsub topics delete "$topic_name" --quiet 2>/dev/null; then
                    log_success "Deleted topic: $topic_name"
                else
                    log_warning "Failed to delete topic: $topic_name (may not exist)"
                fi
            fi
        fi
    done
}

# Remove BigQuery datasets
remove_bigquery_datasets() {
    log_info "Removing BigQuery datasets..."
    
    local datasets_to_remove=()
    
    # Use configured dataset names if available, otherwise use discovered resources
    if [[ -n "${DATASET_NAME:-}" ]]; then
        datasets_to_remove+=("$DATASET_NAME")
    else
        datasets_to_remove=("${DISCOVERED_DATASETS[@]}")
    fi
    
    for dataset in "${datasets_to_remove[@]}"; do
        if [[ -n "$dataset" ]]; then
            if confirm_action "delete BigQuery dataset" "$dataset"; then
                if bq rm -r -f "${PROJECT_ID}:${dataset}" 2>/dev/null; then
                    log_success "Deleted BigQuery dataset: $dataset"
                else
                    log_warning "Failed to delete BigQuery dataset: $dataset (may not exist)"
                fi
            fi
        fi
    done
}

# Remove service accounts
remove_service_accounts() {
    log_info "Removing service accounts..."
    
    local service_accounts_to_remove=()
    
    # Use configured service account names if available, otherwise use discovered resources
    if [[ -n "${PROJECT_ID:-}" ]]; then
        service_accounts_to_remove+=("carbon-footprint-sa@${PROJECT_ID}.iam.gserviceaccount.com")
    else
        service_accounts_to_remove=("${DISCOVERED_SERVICE_ACCOUNTS[@]}")
    fi
    
    for service_account in "${service_accounts_to_remove[@]}"; do
        if [[ -n "$service_account" ]]; then
            if confirm_action "delete service account" "$service_account"; then
                if gcloud iam service-accounts delete "$service_account" --quiet 2>/dev/null; then
                    log_success "Deleted service account: $service_account"
                else
                    log_warning "Failed to delete service account: $service_account (may not exist)"
                fi
            fi
        fi
    done
}

# Remove monitoring resources
remove_monitoring_resources() {
    log_info "Removing monitoring policies and dashboards..."
    
    if confirm_action "delete monitoring policies" "all carbon-related policies"; then
        # Get all monitoring policies and filter for carbon-related ones
        local policies=$(gcloud alpha monitoring policies list --format="value(name)" 2>/dev/null | grep -i carbon || echo "")
        
        for policy in $policies; do
            if [[ -n "$policy" ]]; then
                if gcloud alpha monitoring policies delete "$policy" --quiet 2>/dev/null; then
                    log_success "Deleted monitoring policy: $(basename $policy)"
                else
                    log_warning "Failed to delete monitoring policy: $(basename $policy)"
                fi
            fi
        done
    fi
    
    if confirm_action "delete monitoring dashboards" "all carbon-related dashboards"; then
        # Get all dashboards and filter for carbon-related ones
        local dashboards=$(gcloud alpha monitoring dashboards list --format="value(name)" 2>/dev/null | grep -i carbon || echo "")
        
        for dashboard in $dashboards; do
            if [[ -n "$dashboard" ]]; then
                if gcloud alpha monitoring dashboards delete "$dashboard" --quiet 2>/dev/null; then
                    log_success "Deleted monitoring dashboard: $(basename $dashboard)"
                else
                    log_warning "Failed to delete monitoring dashboard: $(basename $dashboard)"
                fi
            fi
        done
    fi
}

# Remove compute instances created by workflows
remove_compute_instances() {
    log_info "Checking for running compute instances created by workflows..."
    
    # Find instances with carbon-aware labels
    local carbon_instances=$(gcloud compute instances list --filter="labels.carbon-aware=true" --format="value(name,zone)" 2>/dev/null || echo "")
    
    if [[ -n "$carbon_instances" ]]; then
        log_warning "Found running carbon-aware compute instances:"
        echo "$carbon_instances"
        
        if confirm_action "delete all carbon-aware compute instances" "instances created by workflows"; then
            while IFS=$'\t' read -r instance_name instance_zone; do
                if [[ -n "$instance_name" && -n "$instance_zone" ]]; then
                    if gcloud compute instances delete "$instance_name" --zone="$instance_zone" --quiet 2>/dev/null; then
                        log_success "Deleted compute instance: $instance_name"
                    else
                        log_warning "Failed to delete compute instance: $instance_name"
                    fi
                fi
            done <<< "$carbon_instances"
        fi
    else
        log_info "No carbon-aware compute instances found"
    fi
}

# Clean up local files
clean_local_files() {
    log_info "Cleaning up local configuration files..."
    
    local files_to_remove=(
        "deployment-config.env"
        "carbon-aware-workflow.yaml"
        "carbon-alerting-policy.json"
        "carbon-dashboard.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if confirm_action "delete local file" "$file"; then
                rm -f "$file"
                log_success "Deleted local file: $file"
            fi
        fi
    done
}

# Delete entire project (use with extreme caution)
delete_project() {
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        log_warning "PROJECT DELETION REQUESTED - THIS IS IRREVERSIBLE!"
        log_warning "Project: $PROJECT_ID"
        
        if [[ "$INTERACTIVE" == "true" ]]; then
            echo -e "${RED}[DANGER]${NC} You are about to delete the entire project: $PROJECT_ID"
            echo -e "${RED}[DANGER]${NC} This action is IRREVERSIBLE and will delete ALL resources in the project!"
            echo -e "${RED}[DANGER]${NC} Type the project ID to confirm: "
            read -r confirmation
            
            if [[ "$confirmation" != "$PROJECT_ID" ]]; then
                log_info "Project deletion cancelled (confirmation did not match)"
                return 0
            fi
        fi
        
        if [[ "$DRY_RUN" == "false" ]]; then
            log_info "Deleting project: $PROJECT_ID"
            if gcloud projects delete "$PROJECT_ID" --quiet 2>/dev/null; then
                log_success "Project deleted: $PROJECT_ID"
            else
                log_error "Failed to delete project: $PROJECT_ID"
            fi
        else
            log_info "Would delete project: $PROJECT_ID"
        fi
    fi
}

# Verify prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install Google Cloud SDK."
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error_exit "bq CLI is not installed. Please install Google Cloud SDK with BigQuery components."
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q '@'; then
        error_exit "No active gcloud authentication found. Please run 'gcloud auth login'."
    fi
    
    log_success "Prerequisites check completed"
}

# Display cleanup summary
display_cleanup_summary() {
    log_info ""
    log_info "=== Cleanup Summary ==="
    log_info "Project: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Mode: DRY RUN (no actual changes made)"
    else
        log_info "Mode: EXECUTION (resources were actually deleted)"
    fi
    
    log_info ""
    log_info "Resources processed:"
    log_info "- Cloud Scheduler jobs"
    log_info "- Cloud Workflows"
    log_info "- Cloud Functions"
    log_info "- Pub/Sub topics and subscriptions"
    log_info "- BigQuery datasets"
    log_info "- Service accounts"
    log_info "- Monitoring policies and dashboards"
    log_info "- Compute instances (if any)"
    log_info "- Local configuration files"
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        log_info "- Entire project (DELETED)"
    fi
    
    log_info ""
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "Cleanup completed!"
        log_info "Note: Some resources may take a few minutes to be fully removed."
    else
        log_info "To actually perform the cleanup, run without --dry-run flag"
    fi
}

# Main cleanup function
main() {
    log_info "=== Carbon-Aware Workload Orchestration Cleanup ==="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No actual resources will be deleted"
    fi
    
    check_prerequisites
    load_config
    
    # Discover resources if configuration is incomplete
    if [[ -z "${WORKFLOW_NAME:-}" || -z "${FUNCTION_NAME:-}" ]]; then
        discover_resources
    fi
    
    # Perform cleanup in reverse order of creation
    remove_scheduler_jobs
    remove_workflows
    remove_functions
    remove_pubsub_resources
    remove_bigquery_datasets
    remove_service_accounts
    remove_monitoring_resources
    remove_compute_instances
    clean_local_files
    
    # Delete project if requested (this should be last)
    delete_project
    
    display_cleanup_summary
}

# Run main function
main "$@"