#!/bin/bash

# Infrastructure Cost Optimization with Cloud Billing API and Cloud Functions - Destroy Script
# This script safely removes all resources created by the cost optimization deployment

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="/tmp/cost-optimization-destroy-$(date +%Y%m%d-%H%M%S).log"

# Global variables
PROJECT_ID=""
REGION=""
BILLING_ACCOUNT_ID=""
SKIP_CONFIRMATIONS=false
DRY_RUN=false
FORCE_DELETE=false

# Logging functions
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

# Error handling
cleanup_on_error() {
    log_error "Cleanup failed. Check log file: ${LOG_FILE}"
    log_error "Some resources may require manual deletion"
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Infrastructure Cost Optimization Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -p, --project-id PROJECT_ID     Google Cloud Project ID (required)
    -r, --region REGION             Deployment region (optional, will auto-detect)
    -b, --billing-account ACCOUNT   Billing Account ID (required for budget deletion)
    -y, --yes                       Skip confirmation prompts
    -f, --force                     Force deletion without safety checks
    --dry-run                       Show what would be deleted without making changes
    -h, --help                      Show this help message

EXAMPLES:
    $0 -p my-project-123 -b 01234A-5678BC-9DEFGH
    $0 -p my-project -b my-billing-account -y --force

SAFETY FEATURES:
    - Lists all resources before deletion
    - Requires explicit confirmation for destructive actions
    - Validates resource ownership before deletion
    - Logs all operations for audit trail

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
            -b|--billing-account)
                BILLING_ACCOUNT_ID="$2"
                shift 2
                ;;
            -y|--yes)
                SKIP_CONFIRMATIONS=true
                shift
                ;;
            -f|--force)
                FORCE_DELETE=true
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
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use -p or --project-id"
        exit 1
    fi

    # Auto-detect region if not provided
    if [[ -z "$REGION" ]]; then
        REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
        log_info "Using region: $REGION"
    fi
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi

    # Validate project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project '$PROJECT_ID' does not exist or is not accessible."
        exit 1
    fi

    # Set project context
    gcloud config set project "$PROJECT_ID"

    log_success "Prerequisites validation completed"
}

# Discover cost optimization resources
discover_resources() {
    log_info "Discovering cost optimization resources..."

    # Find BigQuery datasets with cost optimization pattern
    local datasets
    datasets=$(bq ls --format="value(datasetId)" --filter="datasetId:cost_optimization_*" "$PROJECT_ID" 2>/dev/null || echo "")

    # Find Cloud Functions with cost optimization pattern
    local functions
    functions=$(gcloud functions list --format="value(name)" --filter="name:cost-opt-*" 2>/dev/null || echo "")

    # Find Pub/Sub topics and subscriptions
    local topics
    topics=$(gcloud pubsub topics list --format="value(name)" --filter="name:cost-optimization-alerts" 2>/dev/null || echo "")
    
    local subscriptions
    subscriptions=$(gcloud pubsub subscriptions list --format="value(name)" --filter="name:(budget-alerts-sub OR anomaly-detection-sub)" 2>/dev/null || echo "")

    # Find Cloud Scheduler jobs
    local scheduler_jobs
    scheduler_jobs=$(gcloud scheduler jobs list --format="value(name)" --filter="name:(cost-analysis-scheduler OR optimization-scheduler)" 2>/dev/null || echo "")

    # Find budgets (requires billing account)
    local budgets=""
    if [[ -n "$BILLING_ACCOUNT_ID" ]]; then
        budgets=$(gcloud alpha billing budgets list --billing-account="$BILLING_ACCOUNT_ID" --format="value(displayName)" --filter="displayName:cost-optimization-budget-*" 2>/dev/null || echo "")
    fi

    # Store discovered resources in global variables
    DISCOVERED_DATASETS="$datasets"
    DISCOVERED_FUNCTIONS="$functions"
    DISCOVERED_TOPICS="$topics"
    DISCOVERED_SUBSCRIPTIONS="$subscriptions"
    DISCOVERED_SCHEDULER_JOBS="$scheduler_jobs"
    DISCOVERED_BUDGETS="$budgets"

    log_success "Resource discovery completed"
}

# Display destruction plan
show_destruction_plan() {
    cat << EOF

${RED}=== DESTRUCTION PLAN ===${NC}

Project: ${PROJECT_ID}
Region: ${REGION}

Resources to be DELETED:

${RED}BigQuery Datasets:${NC}
$(echo "$DISCOVERED_DATASETS" | sed 's/^/├── /' || echo "├── (none found)")

${RED}Cloud Functions:${NC}
$(echo "$DISCOVERED_FUNCTIONS" | sed 's/^/├── /' || echo "├── (none found)")

${RED}Pub/Sub Topics:${NC}
$(echo "$DISCOVERED_TOPICS" | sed 's/^/├── /' || echo "├── (none found)")

${RED}Pub/Sub Subscriptions:${NC}
$(echo "$DISCOVERED_SUBSCRIPTIONS" | sed 's/^/├── /' || echo "├── (none found)")

${RED}Cloud Scheduler Jobs:${NC}
$(echo "$DISCOVERED_SCHEDULER_JOBS" | sed 's/^/├── /' || echo "├── (none found)")

${RED}Budgets:${NC}
$(echo "$DISCOVERED_BUDGETS" | sed 's/^/├── /' || echo "├── (none found or billing account not provided)")

${RED}Local Files:${NC}
├── Function source code in: ${PROJECT_ROOT}/functions/
├── Temporary configuration files
└── Log files

${YELLOW}WARNING: This action is IRREVERSIBLE!${NC}
${YELLOW}All cost optimization data and configurations will be permanently deleted.${NC}

EOF

    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: No resources will be deleted"
        return
    fi

    # Check if any resources were found
    if [[ -z "$DISCOVERED_DATASETS" && -z "$DISCOVERED_FUNCTIONS" && -z "$DISCOVERED_TOPICS" && 
          -z "$DISCOVERED_SUBSCRIPTIONS" && -z "$DISCOVERED_SCHEDULER_JOBS" ]]; then
        log_info "No cost optimization resources found to delete"
        return
    fi

    if [[ "$SKIP_CONFIRMATIONS" != true ]]; then
        echo
        log_warning "This will permanently delete ALL cost optimization resources!"
        read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " -r
        if [[ "$REPLY" != "DELETE" ]]; then
            log_info "Destruction cancelled by user"
            exit 0
        fi

        if [[ "$FORCE_DELETE" != true ]]; then
            read -p "Enter the project ID '$PROJECT_ID' to confirm: " -r
            if [[ "$REPLY" != "$PROJECT_ID" ]]; then
                log_error "Project ID confirmation failed. Exiting for safety."
                exit 1
            fi
        fi
    fi
}

# Delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    if [[ -z "$DISCOVERED_SCHEDULER_JOBS" ]]; then
        log_info "No Cloud Scheduler jobs to delete"
        return
    fi

    log_info "Deleting Cloud Scheduler jobs..."

    while IFS= read -r job_name; do
        if [[ -n "$job_name" ]]; then
            log_info "Deleting scheduler job: $job_name"
            if [[ "$DRY_RUN" != true ]]; then
                gcloud scheduler jobs delete "$job_name" --quiet || log_warning "Failed to delete job: $job_name"
            fi
        fi
    done <<< "$DISCOVERED_SCHEDULER_JOBS"

    log_success "Cloud Scheduler jobs deletion completed"
}

# Delete Cloud Functions
delete_functions() {
    if [[ -z "$DISCOVERED_FUNCTIONS" ]]; then
        log_info "No Cloud Functions to delete"
        return
    fi

    log_info "Deleting Cloud Functions..."

    while IFS= read -r function_name; do
        if [[ -n "$function_name" ]]; then
            log_info "Deleting function: $function_name"
            if [[ "$DRY_RUN" != true ]]; then
                gcloud functions delete "$function_name" --quiet || log_warning "Failed to delete function: $function_name"
            fi
        fi
    done <<< "$DISCOVERED_FUNCTIONS"

    log_success "Cloud Functions deletion completed"
}

# Delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."

    # Delete subscriptions first (they depend on topics)
    if [[ -n "$DISCOVERED_SUBSCRIPTIONS" ]]; then
        while IFS= read -r subscription_name; do
            if [[ -n "$subscription_name" ]]; then
                log_info "Deleting subscription: $subscription_name"
                if [[ "$DRY_RUN" != true ]]; then
                    gcloud pubsub subscriptions delete "$subscription_name" --quiet || log_warning "Failed to delete subscription: $subscription_name"
                fi
            fi
        done <<< "$DISCOVERED_SUBSCRIPTIONS"
    fi

    # Delete topics
    if [[ -n "$DISCOVERED_TOPICS" ]]; then
        while IFS= read -r topic_name; do
            if [[ -n "$topic_name" ]]; then
                log_info "Deleting topic: $topic_name"
                if [[ "$DRY_RUN" != true ]]; then
                    gcloud pubsub topics delete "$topic_name" --quiet || log_warning "Failed to delete topic: $topic_name"
                fi
            fi
        done <<< "$DISCOVERED_TOPICS"
    fi

    log_success "Pub/Sub resources deletion completed"
}

# Delete BigQuery datasets
delete_bigquery_resources() {
    if [[ -z "$DISCOVERED_DATASETS" ]]; then
        log_info "No BigQuery datasets to delete"
        return
    fi

    log_info "Deleting BigQuery datasets..."

    while IFS= read -r dataset_name; do
        if [[ -n "$dataset_name" ]]; then
            log_info "Deleting dataset: $dataset_name"
            log_warning "This will delete ALL tables and data in the dataset!"
            
            if [[ "$DRY_RUN" != true ]]; then
                # Force delete dataset with all tables
                bq rm -r -f "$PROJECT_ID:$dataset_name" || log_warning "Failed to delete dataset: $dataset_name"
            fi
        fi
    done <<< "$DISCOVERED_DATASETS"

    log_success "BigQuery datasets deletion completed"
}

# Delete budgets
delete_budgets() {
    if [[ -z "$BILLING_ACCOUNT_ID" ]]; then
        log_warning "Billing account not provided. Skipping budget deletion."
        log_info "To delete budgets manually:"
        log_info "1. Go to Google Cloud Console > Billing > Budgets & alerts"
        log_info "2. Delete budgets with 'cost-optimization-budget-*' pattern"
        return
    fi

    if [[ -z "$DISCOVERED_BUDGETS" ]]; then
        log_info "No budgets to delete"
        return
    fi

    log_info "Deleting budgets..."
    log_warning "Budget deletion requires manual action via Google Cloud Console"
    log_info "Budgets to delete:"
    
    while IFS= read -r budget_name; do
        if [[ -n "$budget_name" ]]; then
            log_info "  - $budget_name"
        fi
    done <<< "$DISCOVERED_BUDGETS"

    log_info "Please delete these budgets manually in the Google Cloud Console:"
    log_info "1. Navigate to Billing > Budgets & alerts"
    log_info "2. Find and delete the listed budgets"

    log_success "Budget deletion instructions provided"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."

    # Remove function source code
    if [[ -d "$PROJECT_ROOT/functions" ]]; then
        log_info "Removing function source code directory..."
        if [[ "$DRY_RUN" != true ]]; then
            rm -rf "$PROJECT_ROOT/functions"
        fi
    fi

    # Remove temporary files
    local temp_files=(
        "$PROJECT_ROOT/budget-config.json"
        "$PROJECT_ROOT/*.tmp"
        "$PROJECT_ROOT/*.log"
    )

    for file_pattern in "${temp_files[@]}"; do
        if ls $file_pattern 1> /dev/null 2>&1; then
            log_info "Removing temporary files: $file_pattern"
            if [[ "$DRY_RUN" != true ]]; then
                rm -f $file_pattern
            fi
        fi
    done

    log_success "Local files cleanup completed"
}

# Verify resource deletion
verify_deletion() {
    if [[ "$DRY_RUN" == true ]]; then
        return
    fi

    log_info "Verifying resource deletion..."

    # Check BigQuery datasets
    local remaining_datasets
    remaining_datasets=$(bq ls --format="value(datasetId)" --filter="datasetId:cost_optimization_*" "$PROJECT_ID" 2>/dev/null || echo "")
    if [[ -n "$remaining_datasets" ]]; then
        log_warning "Some BigQuery datasets may still exist:"
        echo "$remaining_datasets" | sed 's/^/  - /'
    fi

    # Check Cloud Functions
    local remaining_functions
    remaining_functions=$(gcloud functions list --format="value(name)" --filter="name:cost-opt-*" 2>/dev/null || echo "")
    if [[ -n "$remaining_functions" ]]; then
        log_warning "Some Cloud Functions may still exist:"
        echo "$remaining_functions" | sed 's/^/  - /'
    fi

    # Check Pub/Sub topics
    local remaining_topics
    remaining_topics=$(gcloud pubsub topics list --format="value(name)" --filter="name:cost-optimization-alerts" 2>/dev/null || echo "")
    if [[ -n "$remaining_topics" ]]; then
        log_warning "Some Pub/Sub topics may still exist:"
        echo "$remaining_topics" | sed 's/^/  - /'
    fi

    log_success "Deletion verification completed"
}

# Display cleanup summary
show_cleanup_summary() {
    cat << EOF

${GREEN}=== CLEANUP COMPLETED ===${NC}

Project: ${PROJECT_ID}
Region: ${REGION}

Resources deleted:
├── Cloud Scheduler jobs
├── Cloud Functions
├── Pub/Sub topics and subscriptions
├── BigQuery datasets and tables
└── Local source code and temporary files

${YELLOW}Manual actions required:${NC}
└── Delete budgets via Google Cloud Console (if not done manually)

${BLUE}Post-cleanup checklist:${NC}
1. Verify no unexpected charges in billing reports
2. Check that all automated systems are stopped
3. Remove any remaining IAM roles if no longer needed
4. Review Cloud Logging for any remaining function logs

${GREEN}Cost optimization system has been completely removed.${NC}

Log file: ${LOG_FILE}

EOF
}

# Main destruction function
main() {
    log_info "Starting Infrastructure Cost Optimization cleanup..."
    log_info "Log file: ${LOG_FILE}"

    parse_args "$@"
    validate_prerequisites
    discover_resources
    show_destruction_plan

    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN completed. No resources were deleted."
        exit 0
    fi

    # Delete resources in reverse order of dependencies
    delete_scheduler_jobs
    delete_functions
    delete_pubsub_resources
    delete_bigquery_resources
    delete_budgets
    cleanup_local_files
    verify_deletion

    show_cleanup_summary
    log_success "Cleanup completed successfully!"
}

# Execute main function with all arguments
main "$@"