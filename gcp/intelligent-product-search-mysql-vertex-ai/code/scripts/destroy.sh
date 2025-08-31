#!/bin/bash

# Intelligent Product Search with Cloud SQL and Vertex AI - Cleanup Script
# This script safely removes all infrastructure created for semantic product search
# Recipe: intelligent-product-search-mysql-vertex-ai

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "Running in DRY-RUN mode - no resources will be deleted"
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    log "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
    else
        eval "$cmd"
    fi
}

# Function to prompt for confirmation
confirm_action() {
    local message="$1"
    local skip_confirmation="${SKIP_CONFIRMATION:-false}"
    
    if [[ "$skip_confirmation" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}$message${NC}"
    read -p "Are you sure? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
}

# Function to load configuration
load_config() {
    log "Loading deployment configuration..."
    
    if [[ -f "deployment_config.env" ]]; then
        source deployment_config.env
        log_success "Configuration loaded from deployment_config.env"
    else
        log_warning "deployment_config.env not found. Using environment variables or defaults."
        
        # Set default values if not provided
        export PROJECT_ID="${PROJECT_ID:-}"
        export REGION="${REGION:-us-central1}"
        export ZONE="${ZONE:-us-central1-a}"
        export INSTANCE_NAME="${INSTANCE_NAME:-}"
        export BUCKET_NAME="${BUCKET_NAME:-}"
        export FUNCTION_NAME="${FUNCTION_NAME:-}"
    fi
    
    # Validate required variables
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID is required. Set it as environment variable or use deployment_config.env"
        exit 1
    fi
    
    log "Configuration:"
    echo "  PROJECT_ID: $PROJECT_ID"
    echo "  REGION: $REGION"
    echo "  ZONE: $ZONE"
    echo "  INSTANCE_NAME: ${INSTANCE_NAME:-not set}"
    echo "  BUCKET_NAME: ${BUCKET_NAME:-not set}"
    echo "  FUNCTION_NAME: ${FUNCTION_NAME:-not set}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 &> /dev/null; then
        log_error "You are not authenticated with gcloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Set project context
    execute_cmd "gcloud config set project ${PROJECT_ID}" "Setting project context"
    
    log_success "Prerequisites validated"
}

# Function to delete Cloud Functions
delete_functions() {
    log "Removing Cloud Functions..."
    
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        # Check if search function exists
        if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
            execute_cmd "gcloud functions delete ${FUNCTION_NAME} \
                --region=${REGION} \
                --quiet" \
                "Deleting search function: ${FUNCTION_NAME}"
        else
            log_warning "Search function ${FUNCTION_NAME} not found"
        fi
        
        # Check if add function exists
        if gcloud functions describe "${FUNCTION_NAME}-add" --region="${REGION}" &> /dev/null; then
            execute_cmd "gcloud functions delete ${FUNCTION_NAME}-add \
                --region=${REGION} \
                --quiet" \
                "Deleting add product function: ${FUNCTION_NAME}-add"
        else
            log_warning "Add product function ${FUNCTION_NAME}-add not found"
        fi
    else
        log_warning "FUNCTION_NAME not set, checking for common function names..."
        
        # List all functions in the region and look for product-search patterns
        local functions
        functions=$(gcloud functions list --regions="${REGION}" --format="value(name)" 2>/dev/null | grep -i "product-search" || true)
        
        if [[ -n "$functions" ]]; then
            log "Found potential functions to delete:"
            echo "$functions"
            confirm_action "Delete these functions?"
            
            while IFS= read -r func_name; do
                if [[ -n "$func_name" ]]; then
                    execute_cmd "gcloud functions delete $func_name --region=${REGION} --quiet" \
                               "Deleting function: $func_name"
                fi
            done <<< "$functions"
        fi
    fi
    
    log_success "Cloud Functions cleanup completed"
}

# Function to delete Cloud SQL instance
delete_sql_instance() {
    log "Removing Cloud SQL instance..."
    
    if [[ -n "${INSTANCE_NAME:-}" ]]; then
        # Check if instance exists
        if gcloud sql instances describe "${INSTANCE_NAME}" &> /dev/null; then
            confirm_action "This will permanently delete Cloud SQL instance '${INSTANCE_NAME}' and all its data!"
            
            execute_cmd "gcloud sql instances delete ${INSTANCE_NAME} --quiet" \
                       "Deleting Cloud SQL instance: ${INSTANCE_NAME}"
        else
            log_warning "Cloud SQL instance ${INSTANCE_NAME} not found"
        fi
    else
        log_warning "INSTANCE_NAME not set, checking for instances with product-db pattern..."
        
        # List all SQL instances and look for product-db patterns
        local instances
        instances=$(gcloud sql instances list --format="value(name)" 2>/dev/null | grep -i "product-db" || true)
        
        if [[ -n "$instances" ]]; then
            log "Found potential Cloud SQL instances to delete:"
            echo "$instances"
            confirm_action "Delete these Cloud SQL instances? This will permanently delete all data!"
            
            while IFS= read -r instance_name; do
                if [[ -n "$instance_name" ]]; then
                    execute_cmd "gcloud sql instances delete $instance_name --quiet" \
                               "Deleting Cloud SQL instance: $instance_name"
                fi
            done <<< "$instances"
        fi
    fi
    
    log_success "Cloud SQL cleanup completed"
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log "Removing Cloud Storage bucket..."
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        # Check if bucket exists
        if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
            confirm_action "This will permanently delete storage bucket 'gs://${BUCKET_NAME}' and all its contents!"
            
            execute_cmd "gsutil -m rm -r gs://${BUCKET_NAME}" \
                       "Deleting storage bucket: gs://${BUCKET_NAME}"
        else
            log_warning "Storage bucket gs://${BUCKET_NAME} not found"
        fi
    else
        log_warning "BUCKET_NAME not set, checking for buckets with products pattern..."
        
        # List buckets in the project and look for product patterns
        local buckets
        buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -i "products" || true)
        
        if [[ -n "$buckets" ]]; then
            log "Found potential storage buckets to delete:"
            echo "$buckets"
            confirm_action "Delete these storage buckets? This will permanently delete all contents!"
            
            while IFS= read -r bucket_url; do
                if [[ -n "$bucket_url" ]]; then
                    execute_cmd "gsutil -m rm -r $bucket_url" \
                               "Deleting storage bucket: $bucket_url"
                fi
            done <<< "$buckets"
        fi
    fi
    
    log_success "Cloud Storage cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files and directories..."
    
    local files_to_remove=(
        "product-search-function"
        "schema.sql"
        "sample_products.json"
        "test_search.sh"
        "deployment_config.env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                echo "DRY-RUN: Would remove $file"
            else
                rm -rf "$file"
                log "Removed: $file"
            fi
        fi
    done
    
    # Clear environment variables
    if [[ "$DRY_RUN" != "true" ]]; then
        unset PROJECT_ID REGION ZONE INSTANCE_NAME BUCKET_NAME FUNCTION_NAME
        unset DB_PASSWORD DB_IP SEARCH_URL ADD_URL RANDOM_SUFFIX
    fi
    
    log_success "Local cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_errors=0
    
    # Check Cloud Functions
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
            log_error "Cloud Function ${FUNCTION_NAME} still exists"
            ((cleanup_errors++))
        fi
        if gcloud functions describe "${FUNCTION_NAME}-add" --region="${REGION}" &> /dev/null; then
            log_error "Cloud Function ${FUNCTION_NAME}-add still exists"
            ((cleanup_errors++))
        fi
    fi
    
    # Check Cloud SQL instance
    if [[ -n "${INSTANCE_NAME:-}" ]]; then
        if gcloud sql instances describe "${INSTANCE_NAME}" &> /dev/null; then
            log_error "Cloud SQL instance ${INSTANCE_NAME} still exists"
            ((cleanup_errors++))
        fi
    fi
    
    # Check Cloud Storage bucket
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
            log_error "Storage bucket gs://${BUCKET_NAME} still exists"
            ((cleanup_errors++))
        fi
    fi
    
    if [[ $cleanup_errors -eq 0 ]]; then
        log_success "All resources successfully cleaned up"
    else
        log_warning "$cleanup_errors resources may still exist. Check manually if needed."
    fi
}

# Function to display cost savings information
show_cost_savings() {
    log "Cost savings information:"
    echo "By deleting these resources, you've stopped the following charges:"
    echo "  • Cloud SQL instance: ~\$50-100/month (depending on usage)"
    echo "  • Cloud Functions: Pay-per-use (no ongoing charges when not used)"
    echo "  • Cloud Storage: ~\$0.02-0.04/month per GB stored"
    echo "  • Vertex AI API calls: Pay-per-use (no ongoing charges)"
    echo
    echo "Total estimated monthly savings: \$50-150 depending on usage patterns"
}

# Function to handle project deletion
handle_project_deletion() {
    local delete_project="${DELETE_PROJECT:-false}"
    
    if [[ "$delete_project" == "true" ]]; then
        confirm_action "This will permanently delete the entire project '${PROJECT_ID}' and ALL resources within it!"
        
        execute_cmd "gcloud projects delete ${PROJECT_ID} --quiet" \
                   "Deleting entire project: ${PROJECT_ID}"
        
        log_success "Project deletion initiated. It may take a few minutes to complete."
        return 0
    else
        echo
        log_warning "Project '${PROJECT_ID}' was not deleted."
        echo "To delete the entire project and all remaining resources, run:"
        echo "  DELETE_PROJECT=true $0"
        echo
        echo "Or manually delete it with:"
        echo "  gcloud projects delete ${PROJECT_ID}"
    fi
}

# Main cleanup function
main() {
    echo "================================================================"
    echo "Intelligent Product Search with Cloud SQL and Vertex AI"
    echo "Resource Cleanup Script"
    echo "================================================================"
    echo
    
    load_config
    check_prerequisites
    
    echo
    log_warning "This script will delete the following resources:"
    echo "  • Cloud Functions (search and add product functions)"
    echo "  • Cloud SQL MySQL instance and all databases"
    echo "  • Cloud Storage bucket and all contents"
    echo "  • Local files and directories"
    echo
    
    confirm_action "Proceed with resource cleanup?"
    
    delete_functions
    delete_sql_instance
    delete_storage_bucket
    cleanup_local_files
    verify_cleanup
    show_cost_savings
    handle_project_deletion
    
    echo
    echo "================================================================"
    log_success "Cleanup completed successfully!"
    echo "================================================================"
    echo
    echo "Summary:"
    echo "• All infrastructure resources have been removed"
    echo "• Local files and configuration have been cleaned up"
    echo "• Monthly cloud costs have been eliminated"
    echo
    echo "If you need to redeploy, run the deploy.sh script again."
    echo
}

# Print usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --dry-run              Show what would be deleted without actually deleting
  --skip-confirmation    Skip confirmation prompts (use with caution)
  --delete-project       Delete the entire GCP project and all resources
  --help                 Show this help message

Environment Variables:
  PROJECT_ID             GCP project ID (required)
  REGION                 GCP region (default: us-central1)
  INSTANCE_NAME          Cloud SQL instance name
  BUCKET_NAME            Storage bucket name
  FUNCTION_NAME          Cloud Function name prefix

Examples:
  # Interactive cleanup with confirmations
  ./destroy.sh

  # Dry run to see what would be deleted
  DRY_RUN=true ./destroy.sh

  # Skip confirmations (automated cleanup)
  SKIP_CONFIRMATION=true ./destroy.sh

  # Delete entire project
  DELETE_PROJECT=true ./destroy.sh

  # Use specific project ID
  PROJECT_ID=my-project-id ./destroy.sh
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            export DRY_RUN=true
            shift
            ;;
        --skip-confirmation)
            export SKIP_CONFIRMATION=true
            shift
            ;;
        --delete-project)
            export DELETE_PROJECT=true
            shift
            ;;
        --help)
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

# Handle script interruption
trap 'log_error "Script interrupted"; exit 130' INT

# Run main function
main "$@"