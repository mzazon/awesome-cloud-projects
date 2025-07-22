#!/bin/bash

# Real-Time Analytics Automation with BigQuery Continuous Queries and Agentspace
# Destruction Script for GCP Recipe
# 
# This script safely removes all resources created by the real-time analytics
# automation deployment, including BigQuery continuous queries, Pub/Sub topics,
# Cloud Workflows, and associated service accounts.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
}

# Function to check if project is set
check_project() {
    if [ -z "${PROJECT_ID:-}" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo '')
        if [ -z "${PROJECT_ID}" ]; then
            log_error "No project ID set. Please run 'gcloud config set project YOUR_PROJECT_ID'"
            exit 1
        fi
    fi
}

# Function to prompt for confirmation
confirm_destruction() {
    local resource_type="$1"
    if [ "${FORCE_DESTROY:-}" != "true" ]; then
        echo ""
        log_warning "This will permanently delete ${resource_type} in project: ${PROJECT_ID}"
        read -p "Are you sure you want to continue? (yes/no): " confirmation
        case $confirmation in
            [Yy]es|[Yy])
                log_info "Proceeding with ${resource_type} deletion..."
                ;;
            *)
                log_info "Destruction cancelled by user"
                exit 0
                ;;
        esac
    fi
}

# Function to list and cancel continuous query jobs
cancel_continuous_queries() {
    log_info "Cancelling BigQuery continuous query jobs..."
    
    # List all continuous query jobs with our naming pattern
    local job_pattern="continuous-analytics-"
    local jobs_found=false
    
    # Get list of running jobs
    local running_jobs
    running_jobs=$(bq ls -j --max_results=100 --format="value(jobId)" \
        --project_id="${PROJECT_ID}" 2>/dev/null | grep "${job_pattern}" || true)
    
    if [ -n "${running_jobs}" ]; then
        jobs_found=true
        echo "${running_jobs}" | while IFS= read -r job_id; do
            if [ -n "${job_id}" ]; then
                log_info "Cancelling continuous query job: ${job_id}"
                if bq cancel "${job_id}" --project_id="${PROJECT_ID}" 2>/dev/null; then
                    log_success "Cancelled job: ${job_id}"
                else
                    log_warning "Failed to cancel job: ${job_id} (may have already completed)"
                fi
                
                # Wait a moment for the job to be cancelled
                sleep 2
                
                # Verify cancellation
                local job_state
                job_state=$(bq show -j "${job_id}" --format="value(status.state)" \
                    --project_id="${PROJECT_ID}" 2>/dev/null || echo "NOT_FOUND")
                
                if [ "${job_state}" = "DONE" ] || [ "${job_state}" = "NOT_FOUND" ]; then
                    log_success "Job ${job_id} successfully stopped"
                else
                    log_warning "Job ${job_id} may still be running (state: ${job_state})"
                fi
            fi
        done
    fi
    
    # If specific job ID is provided via environment variable
    if [ -n "${CONTINUOUS_QUERY_JOB_ID:-}" ]; then
        log_info "Cancelling specific continuous query job: ${CONTINUOUS_QUERY_JOB_ID}"
        if bq cancel "${CONTINUOUS_QUERY_JOB_ID}" --project_id="${PROJECT_ID}" 2>/dev/null; then
            log_success "Cancelled job: ${CONTINUOUS_QUERY_JOB_ID}"
        else
            log_warning "Failed to cancel job: ${CONTINUOUS_QUERY_JOB_ID}"
        fi
        jobs_found=true
    fi
    
    if [ "${jobs_found}" = false ]; then
        log_info "No continuous query jobs found to cancel"
    fi
    
    # Wait for jobs to fully terminate
    log_info "Waiting for continuous query jobs to terminate..."
    sleep 10
}

# Function to delete Cloud Workflows
delete_workflows() {
    log_info "Deleting Cloud Workflows..."
    
    # If specific workflow name is provided
    if [ -n "${WORKFLOW_NAME:-}" ]; then
        if gcloud workflows describe "${WORKFLOW_NAME}" \
            --location="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
            log_info "Deleting workflow: ${WORKFLOW_NAME}"
            gcloud workflows delete "${WORKFLOW_NAME}" \
                --location="${REGION}" \
                --project="${PROJECT_ID}" \
                --quiet
            log_success "Deleted workflow: ${WORKFLOW_NAME}"
        else
            log_warning "Workflow ${WORKFLOW_NAME} not found"
        fi
    else
        # Find and delete workflows with our naming pattern
        local workflow_pattern="analytics-automation-"
        local workflows
        workflows=$(gcloud workflows list \
            --filter="name:${workflow_pattern}" \
            --format="value(name)" \
            --location="${REGION}" \
            --project="${PROJECT_ID}" 2>/dev/null || true)
        
        if [ -n "${workflows}" ]; then
            echo "${workflows}" | while IFS= read -r workflow_name; do
                if [ -n "${workflow_name}" ]; then
                    log_info "Deleting workflow: ${workflow_name}"
                    gcloud workflows delete "${workflow_name}" \
                        --location="${REGION}" \
                        --project="${PROJECT_ID}" \
                        --quiet
                    log_success "Deleted workflow: ${workflow_name}"
                fi
            done
        else
            log_info "No workflows found to delete"
        fi
    fi
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub subscriptions and topics..."
    
    # Define topics to clean up
    local topics_to_delete=()
    if [ -n "${PUBSUB_TOPIC_RAW:-}" ]; then
        topics_to_delete+=("${PUBSUB_TOPIC_RAW}")
    fi
    if [ -n "${PUBSUB_TOPIC_INSIGHTS:-}" ]; then
        topics_to_delete+=("${PUBSUB_TOPIC_INSIGHTS}")
    fi
    
    # If no specific topics provided, find topics with our naming pattern
    if [ ${#topics_to_delete[@]} -eq 0 ]; then
        local topic_patterns=("raw-events-" "insights-")
        for pattern in "${topic_patterns[@]}"; do
            local found_topics
            found_topics=$(gcloud pubsub topics list \
                --filter="name:${pattern}" \
                --format="value(name)" \
                --project="${PROJECT_ID}" 2>/dev/null || true)
            
            if [ -n "${found_topics}" ]; then
                echo "${found_topics}" | while IFS= read -r topic_path; do
                    if [ -n "${topic_path}" ]; then
                        # Extract topic name from full path
                        local topic_name
                        topic_name=$(basename "${topic_path}")
                        topics_to_delete+=("${topic_name}")
                    fi
                done
            fi
        done
    fi
    
    # Delete subscriptions first, then topics
    for topic in "${topics_to_delete[@]}"; do
        if [ -n "${topic}" ]; then
            # Delete associated subscriptions
            local subscriptions
            subscriptions=$(gcloud pubsub subscriptions list \
                --filter="topic:${topic}" \
                --format="value(name)" \
                --project="${PROJECT_ID}" 2>/dev/null || true)
            
            if [ -n "${subscriptions}" ]; then
                echo "${subscriptions}" | while IFS= read -r sub_path; do
                    if [ -n "${sub_path}" ]; then
                        local sub_name
                        sub_name=$(basename "${sub_path}")
                        log_info "Deleting subscription: ${sub_name}"
                        gcloud pubsub subscriptions delete "${sub_name}" \
                            --project="${PROJECT_ID}" --quiet 2>/dev/null || \
                            log_warning "Failed to delete subscription: ${sub_name}"
                    fi
                done
            fi
            
            # Delete the topic
            if gcloud pubsub topics describe "${topic}" \
                --project="${PROJECT_ID}" >/dev/null 2>&1; then
                log_info "Deleting topic: ${topic}"
                gcloud pubsub topics delete "${topic}" \
                    --project="${PROJECT_ID}" --quiet
                log_success "Deleted topic: ${topic}"
            else
                log_warning "Topic ${topic} not found"
            fi
        fi
    done
    
    # Clean up any remaining subscriptions that follow our naming patterns
    local sub_patterns=("${PUBSUB_TOPIC_RAW:-raw-events}-" "${PUBSUB_TOPIC_INSIGHTS:-insights}-")
    for pattern in "${sub_patterns[@]}"; do
        if [ -n "${pattern}" ] && [ "${pattern}" != "-" ]; then
            local remaining_subs
            remaining_subs=$(gcloud pubsub subscriptions list \
                --filter="name:${pattern}" \
                --format="value(name)" \
                --project="${PROJECT_ID}" 2>/dev/null || true)
            
            if [ -n "${remaining_subs}" ]; then
                echo "${remaining_subs}" | while IFS= read -r sub_path; do
                    if [ -n "${sub_path}" ]; then
                        local sub_name
                        sub_name=$(basename "${sub_path}")
                        log_info "Deleting remaining subscription: ${sub_name}"
                        gcloud pubsub subscriptions delete "${sub_name}" \
                            --project="${PROJECT_ID}" --quiet 2>/dev/null || true
                    fi
                done
            fi
        fi
    done
}

# Function to delete BigQuery resources
delete_bigquery_resources() {
    log_info "Deleting BigQuery tables and dataset..."
    
    local dataset="${DATASET_NAME:-realtime_analytics}"
    
    # Check if dataset exists
    if ! bq ls -d "${PROJECT_ID}:${dataset}" >/dev/null 2>&1; then
        log_info "Dataset ${dataset} not found, skipping BigQuery cleanup"
        return 0
    fi
    
    # List and delete all tables in the dataset
    local tables
    tables=$(bq ls --format="value(tableId)" "${PROJECT_ID}:${dataset}" 2>/dev/null || true)
    
    if [ -n "${tables}" ]; then
        echo "${tables}" | while IFS= read -r table_name; do
            if [ -n "${table_name}" ]; then
                log_info "Deleting table: ${dataset}.${table_name}"
                bq rm -t "${PROJECT_ID}:${dataset}.${table_name}" --quiet
                log_success "Deleted table: ${table_name}"
            fi
        done
    fi
    
    # Delete the dataset
    log_info "Deleting dataset: ${dataset}"
    bq rm -d "${PROJECT_ID}:${dataset}" --quiet
    log_success "Deleted dataset: ${dataset}"
}

# Function to delete service accounts
delete_service_accounts() {
    log_info "Deleting service accounts..."
    
    local sa_name="agentspace-analytics"
    local sa_email="${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "${sa_email}" \
        --project="${PROJECT_ID}" >/dev/null 2>&1; then
        
        # Remove IAM policy bindings first
        local roles=(
            "roles/pubsub.subscriber"
            "roles/bigquery.dataViewer"
            "roles/logging.logWriter"
        )
        
        for role in "${roles[@]}"; do
            log_info "Removing IAM binding: ${role} from ${sa_email}"
            gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${sa_email}" \
                --role="${role}" \
                --quiet 2>/dev/null || \
                log_warning "Failed to remove binding for ${role}"
        done
        
        # Delete the service account
        log_info "Deleting service account: ${sa_email}"
        gcloud iam service-accounts delete "${sa_email}" \
            --project="${PROJECT_ID}" --quiet
        log_success "Deleted service account: ${sa_email}"
    else
        log_warning "Service account ${sa_email} not found"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local script_dir="$(dirname "$0")"
    local files_to_remove=(
        "${script_dir}/simulate_data.py"
        "${script_dir}/continuous_query.sql"
        "${script_dir}/analytics_workflow.yaml"
        "${script_dir}/agentspace_config.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "${file}" ]; then
            log_info "Removing local file: $(basename "${file}")"
            rm -f "${file}"
            log_success "Removed: $(basename "${file}")"
        fi
    done
}

# Function to display destruction summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "   DESTRUCTION SUMMARY"
    echo "=========================================="
    echo ""
    echo "The following resources have been removed:"
    echo "• BigQuery continuous query jobs"
    echo "• Cloud Workflows for automation"
    echo "• Pub/Sub topics and subscriptions"
    echo "• BigQuery dataset and tables"
    echo "• Service accounts and IAM bindings"
    echo "• Local configuration files"
    echo ""
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    echo "=========================================="
    echo "   CLEANUP COMPLETE"
    echo "=========================================="
    echo ""
    echo "All real-time analytics automation resources"
    echo "have been successfully removed."
    echo ""
    echo "Note: Some API usage charges may still apply"
    echo "for resources used during the deployment period."
    echo ""
}

# Function to handle partial cleanup
handle_cleanup_errors() {
    log_warning "Some resources may not have been fully cleaned up."
    echo ""
    echo "Manual cleanup may be required for:"
    echo "1. Check for remaining BigQuery jobs: bq ls -j --max_results=50"
    echo "2. List remaining Pub/Sub topics: gcloud pubsub topics list"
    echo "3. Check for workflows: gcloud workflows list --location=${REGION}"
    echo "4. Verify service accounts: gcloud iam service-accounts list"
    echo ""
    echo "You can also re-run this script with FORCE_DESTROY=true to skip confirmations:"
    echo "FORCE_DESTROY=true ./destroy.sh"
}

# Main destruction function
main() {
    echo "=========================================="
    echo "   Real-Time Analytics Automation"
    echo "   RESOURCE DESTRUCTION"
    echo "=========================================="
    echo ""
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    
    if ! command_exists gcloud; then
        log_error "gcloud CLI not found. Please install Google Cloud SDK."
        exit 1
    fi
    
    if ! command_exists bq; then
        log_error "bq CLI not found. Please install Google Cloud SDK with BigQuery component."
        exit 1
    fi
    
    check_gcloud_auth
    check_project
    
    # Set environment variables if not already set
    export REGION="${REGION:-us-central1}"
    export DATASET_NAME="${DATASET_NAME:-realtime_analytics}"
    
    # Try to determine resource names from deployment environment or common patterns
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        log_info "RANDOM_SUFFIX not provided, will search for resources by pattern"
    else
        export PUBSUB_TOPIC_RAW="${PUBSUB_TOPIC_RAW:-raw-events-${RANDOM_SUFFIX}}"
        export PUBSUB_TOPIC_INSIGHTS="${PUBSUB_TOPIC_INSIGHTS:-insights-${RANDOM_SUFFIX}}"
        export WORKFLOW_NAME="${WORKFLOW_NAME:-analytics-automation-${RANDOM_SUFFIX}}"
        export CONTINUOUS_QUERY_JOB_ID="continuous-analytics-${RANDOM_SUFFIX}"
    fi
    
    log_success "Prerequisites check passed"
    log_info "Using project: ${PROJECT_ID}"
    log_info "Using region: ${REGION}"
    
    # Confirm destruction
    confirm_destruction "all real-time analytics automation resources"
    
    # Perform cleanup in reverse order of creation
    local cleanup_failed=false
    
    # Stop continuous queries first (most critical to stop ongoing costs)
    if ! cancel_continuous_queries; then
        log_error "Failed to cancel continuous queries"
        cleanup_failed=true
    fi
    
    # Delete automation workflows
    if ! delete_workflows; then
        log_error "Failed to delete workflows"
        cleanup_failed=true
    fi
    
    # Remove Pub/Sub resources
    if ! delete_pubsub_resources; then
        log_error "Failed to delete Pub/Sub resources"
        cleanup_failed=true
    fi
    
    # Clean up BigQuery resources
    if ! delete_bigquery_resources; then
        log_error "Failed to delete BigQuery resources"
        cleanup_failed=true
    fi
    
    # Remove service accounts
    if ! delete_service_accounts; then
        log_error "Failed to delete service accounts"
        cleanup_failed=true
    fi
    
    # Clean up local files
    cleanup_local_files
    
    if [ "$cleanup_failed" = true ]; then
        log_error "Some cleanup operations failed"
        handle_cleanup_errors
        exit 1
    else
        log_success "Real-time analytics automation destruction completed successfully!"
        display_summary
    fi
}

# Handle script interruption
trap 'log_error "Destruction interrupted"; exit 1' INT TERM

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY=true
            shift
            ;;
        --random-suffix)
            export RANDOM_SUFFIX="$2"
            shift 2
            ;;
        --project)
            export PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            export REGION="$2"
            shift 2
            ;;
        --dataset)
            export DATASET_NAME="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force              Skip confirmation prompts"
            echo "  --random-suffix STR  Specify the random suffix used during deployment"
            echo "  --project ID         Specify the GCP project ID"
            echo "  --region REGION      Specify the GCP region"
            echo "  --dataset NAME       Specify the BigQuery dataset name"
            echo "  --help               Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  FORCE_DESTROY=true   Same as --force"
            echo "  PROJECT_ID           GCP project ID"
            echo "  REGION               GCP region (default: us-central1)"
            echo "  RANDOM_SUFFIX        Random suffix from deployment"
            echo ""
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"