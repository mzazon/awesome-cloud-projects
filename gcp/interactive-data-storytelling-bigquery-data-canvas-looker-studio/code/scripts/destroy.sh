#!/bin/bash

# Interactive Data Storytelling with BigQuery Data Canvas and Looker Studio - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ID=""
REGION="us-central1"
FORCE_DELETE=false
DRY_RUN=false
CONFIRM_DELETE=false

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleanup Interactive Data Storytelling infrastructure on GCP

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required)
    -r, --region REGION           GCP region (default: us-central1)
    -f, --force                   Skip confirmation prompts
    -y, --yes                     Confirm deletion without prompting
    --dry-run                     Show what would be deleted without executing
    -h, --help                    Display this help message

EXAMPLES:
    $0 --project-id my-gcp-project
    $0 --project-id my-project --force
    $0 --project-id my-project --dry-run

WARNING: This script will permanently delete all resources created by the
         data storytelling deployment. This action cannot be undone.

EOF
}

# Function to parse command line arguments
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
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            -y|--yes)
                CONFIRM_DELETE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use --project-id or set PROJECT_ID environment variable."
        usage
        exit 1
    fi
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not installed. Please install Google Cloud SDK."
        exit 1
    fi

    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi

    # Verify gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi

    # Verify project access
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Cannot access project '$PROJECT_ID'. Please check project ID and permissions."
        exit 1
    fi

    # Set the project
    gcloud config set project "$PROJECT_ID" || {
        log_error "Failed to set project '$PROJECT_ID'"
        exit 1
    }

    log_success "Prerequisites validated successfully"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$CONFIRM_DELETE" == "true" || "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi

    echo ""
    log_warning "This will permanently delete ALL resources created by the data storytelling deployment:"
    echo "  - BigQuery datasets and tables (including all data)"
    echo "  - Cloud Functions"
    echo "  - Cloud Scheduler jobs"
    echo "  - Cloud Storage buckets and contents"
    echo "  - Service accounts and IAM bindings"
    echo ""
    log_warning "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to discover resources
discover_resources() {
    log_info "Discovering resources to cleanup..."

    # Arrays to store discovered resources
    DATASETS=()
    FUNCTIONS=()
    SCHEDULER_JOBS=()
    BUCKETS=()
    SERVICE_ACCOUNTS=()

    # Discover BigQuery datasets with storytelling pattern
    while IFS= read -r dataset; do
        if [[ "$dataset" =~ retail_analytics_ ]]; then
            DATASETS+=("$dataset")
        fi
    done < <(bq ls --format="value(datasetId)" --filter="datasetId:retail_analytics" 2>/dev/null || true)

    # Discover Cloud Functions with storytelling pattern
    while IFS= read -r function; do
        if [[ "$function" =~ data-storytelling-automation ]]; then
            FUNCTIONS+=("$function")
        fi
    done < <(gcloud functions list --regions="$REGION" --format="value(name)" --filter="name:data-storytelling-automation" 2>/dev/null || true)

    # Discover Cloud Scheduler jobs with storytelling pattern
    while IFS= read -r job; do
        if [[ "$job" =~ storytelling-job ]]; then
            SCHEDULER_JOBS+=("$job")
        fi
    done < <(gcloud scheduler jobs list --location="$REGION" --format="value(name)" --filter="name:storytelling-job" 2>/dev/null || true)

    # Discover Cloud Storage buckets with storytelling pattern
    while IFS= read -r bucket; do
        if [[ "$bucket" =~ storytelling ]]; then
            BUCKETS+=("$bucket")
        fi
    done < <(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -E "storytelling" | sed 's|gs://||' | sed 's|/||' || true)

    # Discover service accounts with storytelling pattern
    while IFS= read -r sa; do
        if [[ "$sa" =~ vertex-ai-storytelling ]]; then
            SERVICE_ACCOUNTS+=("$sa")
        fi
    done < <(gcloud iam service-accounts list --format="value(email)" --filter="email:vertex-ai-storytelling" 2>/dev/null || true)

    # Display discovered resources
    log_info "Discovered resources for cleanup:"
    echo "  BigQuery Datasets: ${#DATASETS[@]}"
    echo "  Cloud Functions: ${#FUNCTIONS[@]}"
    echo "  Scheduler Jobs: ${#SCHEDULER_JOBS[@]}"
    echo "  Storage Buckets: ${#BUCKETS[@]}"
    echo "  Service Accounts: ${#SERVICE_ACCOUNTS[@]}"
    
    if [[ ${#DATASETS[@]} -eq 0 && ${#FUNCTIONS[@]} -eq 0 && ${#SCHEDULER_JOBS[@]} -eq 0 && ${#BUCKETS[@]} -eq 0 && ${#SERVICE_ACCOUNTS[@]} -eq 0 ]]; then
        log_warning "No resources found matching the data storytelling pattern"
        log_info "This may indicate:"
        echo "  - Resources were already deleted"
        echo "  - Resources were created with different names"
        echo "  - Resources are in a different project or region"
        exit 0
    fi
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    if [[ ${#SCHEDULER_JOBS[@]} -eq 0 ]]; then
        log_info "No Cloud Scheduler jobs to delete"
        return 0
    fi

    log_info "Deleting Cloud Scheduler jobs..."

    for job in "${SCHEDULER_JOBS[@]}"; do
        log_info "Deleting scheduler job: $job"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete scheduler job: $job"
            continue
        fi

        if gcloud scheduler jobs delete "$job" \
            --location="$REGION" \
            --quiet 2>/dev/null; then
            log_success "Deleted scheduler job: $job"
        else
            log_warning "Failed to delete scheduler job: $job (may not exist)"
        fi
    done
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    if [[ ${#FUNCTIONS[@]} -eq 0 ]]; then
        log_info "No Cloud Functions to delete"
        return 0
    fi

    log_info "Deleting Cloud Functions..."

    for function in "${FUNCTIONS[@]}"; do
        log_info "Deleting Cloud Function: $function"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete Cloud Function: $function"
            continue
        fi

        if gcloud functions delete "$function" \
            --region="$REGION" \
            --quiet 2>/dev/null; then
            log_success "Deleted Cloud Function: $function"
        else
            log_warning "Failed to delete Cloud Function: $function (may not exist)"
        fi
    done
}

# Function to delete BigQuery datasets
delete_bigquery_datasets() {
    if [[ ${#DATASETS[@]} -eq 0 ]]; then
        log_info "No BigQuery datasets to delete"
        return 0
    fi

    log_info "Deleting BigQuery datasets..."

    for dataset in "${DATASETS[@]}"; do
        log_info "Deleting BigQuery dataset: $dataset"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete BigQuery dataset: $dataset"
            continue
        fi

        # List tables in dataset for confirmation
        local table_count
        table_count=$(bq ls --format="value(tableId)" "$PROJECT_ID:$dataset" 2>/dev/null | wc -l || echo "0")
        
        if [[ "$table_count" -gt 0 ]]; then
            log_warning "Dataset $dataset contains $table_count tables - all data will be permanently lost"
        fi

        if bq rm -r -f "$PROJECT_ID:$dataset" 2>/dev/null; then
            log_success "Deleted BigQuery dataset: $dataset"
        else
            log_warning "Failed to delete BigQuery dataset: $dataset (may not exist)"
        fi
    done
}

# Function to delete Cloud Storage buckets
delete_storage_buckets() {
    if [[ ${#BUCKETS[@]} -eq 0 ]]; then
        log_info "No Cloud Storage buckets to delete"
        return 0
    fi

    log_info "Deleting Cloud Storage buckets..."

    for bucket in "${BUCKETS[@]}"; do
        log_info "Deleting Cloud Storage bucket: $bucket"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete Cloud Storage bucket: $bucket"
            continue
        fi

        # Check if bucket exists and get object count
        if gsutil ls "gs://$bucket" &>/dev/null; then
            local object_count
            object_count=$(gsutil ls -r "gs://$bucket" 2>/dev/null | wc -l || echo "0")
            
            if [[ "$object_count" -gt 1 ]]; then  # Subtract 1 for the bucket line itself
                log_warning "Bucket $bucket contains objects - all will be permanently deleted"
            fi

            # Delete all objects and then the bucket
            if gsutil -m rm -r "gs://$bucket" 2>/dev/null; then
                log_success "Deleted Cloud Storage bucket: $bucket"
            else
                log_warning "Failed to delete Cloud Storage bucket: $bucket"
            fi
        else
            log_warning "Cloud Storage bucket does not exist: $bucket"
        fi
    done
}

# Function to delete service accounts
delete_service_accounts() {
    if [[ ${#SERVICE_ACCOUNTS[@]} -eq 0 ]]; then
        log_info "No service accounts to delete"
        return 0
    fi

    log_info "Deleting service accounts..."

    for sa in "${SERVICE_ACCOUNTS[@]}"; do
        log_info "Deleting service account: $sa"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete service account: $sa"
            continue
        fi

        # Remove IAM policy bindings first
        local roles=(
            "roles/bigquery.dataViewer"
            "roles/bigquery.jobUser"
            "roles/aiplatform.user"
            "roles/storage.objectViewer"
        )

        for role in "${roles[@]}"; do
            gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$sa" \
                --role="$role" \
                --quiet 2>/dev/null || true
        done

        # Delete the service account
        if gcloud iam service-accounts delete "$sa" \
            --quiet 2>/dev/null; then
            log_success "Deleted service account: $sa"
        else
            log_warning "Failed to delete service account: $sa (may not exist)"
        fi
    done
}

# Function to clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up temporary files"
        return 0
    fi

    # Clean up any remaining temporary files
    local temp_patterns=(
        "/tmp/sample_sales_data_*.csv"
        "/tmp/storytelling-function-*"
        "/tmp/lifecycle.json"
        "/tmp/analytics_query.sql"
        "/tmp/final_query.sql"
    )

    for pattern in "${temp_patterns[@]}"; do
        # Use find to safely handle glob patterns
        find /tmp -name "$(basename "$pattern")" -type f -delete 2>/dev/null || true
        find /tmp -name "$(basename "$pattern")" -type d -exec rm -rf {} + 2>/dev/null || true
    done

    log_success "Temporary files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup completion..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify cleanup completion"
        return 0
    fi

    local cleanup_errors=0

    # Check BigQuery datasets
    for dataset in "${DATASETS[@]}"; do
        if bq show "$PROJECT_ID:$dataset" &>/dev/null; then
            log_error "BigQuery dataset still exists: $dataset"
            ((cleanup_errors++))
        fi
    done

    # Check Cloud Functions
    for function in "${FUNCTIONS[@]}"; do
        if gcloud functions describe "$function" --region="$REGION" &>/dev/null; then
            log_error "Cloud Function still exists: $function"
            ((cleanup_errors++))
        fi
    done

    # Check Scheduler jobs
    for job in "${SCHEDULER_JOBS[@]}"; do
        if gcloud scheduler jobs describe "$job" --location="$REGION" &>/dev/null; then
            log_error "Scheduler job still exists: $job"
            ((cleanup_errors++))
        fi
    done

    # Check Storage buckets
    for bucket in "${BUCKETS[@]}"; do
        if gsutil ls "gs://$bucket" &>/dev/null; then
            log_error "Storage bucket still exists: $bucket"
            ((cleanup_errors++))
        fi
    done

    # Check service accounts
    for sa in "${SERVICE_ACCOUNTS[@]}"; do
        if gcloud iam service-accounts describe "$sa" &>/dev/null; then
            log_error "Service account still exists: $sa"
            ((cleanup_errors++))
        fi
    done

    if [[ $cleanup_errors -eq 0 ]]; then
        log_success "Cleanup verification completed successfully"
    else
        log_warning "$cleanup_errors resources may still exist - manual cleanup may be required"
    fi
}

# Function to display cleanup summary
display_summary() {
    log_info "Cleanup Summary"
    echo "=================================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo ""
    echo "Resources processed:"
    echo "  BigQuery Datasets: ${#DATASETS[@]}"
    echo "  Cloud Functions: ${#FUNCTIONS[@]}"
    echo "  Scheduler Jobs: ${#SCHEDULER_JOBS[@]}"
    echo "  Storage Buckets: ${#BUCKETS[@]}"
    echo "  Service Accounts: ${#SERVICE_ACCOUNTS[@]}"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN - No resources were actually deleted"
    else
        echo "All data storytelling resources have been removed"
        echo ""
        echo "Note: Some API usage charges may still apply for:"
        echo "  - BigQuery queries executed during deployment"
        echo "  - Vertex AI model calls"
        echo "  - Cloud Function invocations"
        echo "  - Cloud Storage operations"
    fi
    echo "=================================="
}

# Main cleanup function
main() {
    log_info "Starting Interactive Data Storytelling cleanup..."
    
    parse_args "$@"
    validate_prerequisites
    discover_resources
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be deleted"
    else
        confirm_deletion
    fi
    
    # Delete resources in reverse order of dependencies
    delete_scheduler_jobs
    delete_cloud_functions
    delete_bigquery_datasets
    delete_storage_buckets
    delete_service_accounts
    cleanup_temp_files
    verify_cleanup
    
    log_success "Cleanup completed successfully!"
    display_summary
}

# Trap errors
trap 'log_error "Cleanup failed. Some resources may still exist and require manual cleanup."' ERR

# Run main function with all arguments
main "$@"