#!/bin/bash

# Destroy script for API Schema Generation with Gemini Code Assist and Cloud Build
# This script safely removes all infrastructure created by the deployment recipe

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script metadata
readonly SCRIPT_NAME="destroy.sh"
readonly SCRIPT_VERSION="1.0"
readonly RECIPE_NAME="API Schema Generation with Gemini Code Assist and Cloud Build"

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

log_separator() {
    echo -e "${BLUE}================================================${NC}" >&2
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Check logs above for details."
    exit 1
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy infrastructure for $RECIPE_NAME

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required)
    -r, --region REGION           GCP region (default: us-central1)
    -b, --bucket-name BUCKET       Specific bucket name to delete
    -f, --force                   Skip confirmation prompts
    -h, --help                    Show this help message
    -v, --version                 Show script version
    --dry-run                     Show what would be deleted without executing
    --preserve-data               Keep Cloud Storage bucket and data
    --delete-apis                 Also disable APIs (use with caution)

EXAMPLES:
    $0 --project-id my-gcp-project
    $0 --project-id my-gcp-project --force
    $0 --project-id my-gcp-project --dry-run
    $0 --project-id my-gcp-project --preserve-data

SAFETY FEATURES:
    - Confirmation prompts for destructive operations
    - Dry-run mode to preview deletions
    - Option to preserve data in Cloud Storage
    - Detailed logging of all operations

EOF
}

# Parse command line arguments
parse_arguments() {
    local force=false
    local dry_run=false
    local preserve_data=false
    local delete_apis=false
    local region="us-central1"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                region="$2"
                shift 2
                ;;
            -b|--bucket-name)
                BUCKET_NAME="$2"
                shift 2
                ;;
            -f|--force)
                force=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --preserve-data)
                preserve_data=true
                shift
                ;;
            --delete-apis)
                delete_apis=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                echo "$SCRIPT_NAME version $SCRIPT_VERSION"
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
    
    # Check required parameters
    if [[ -z "${PROJECT_ID:-}" ]]; then
        error_exit "Project ID is required. Use --project-id option or set PROJECT_ID environment variable"
    fi
    
    # Export for use in functions
    export PROJECT_ID REGION BUCKET_NAME
    export FORCE=$force
    export DRY_RUN=$dry_run
    export PRESERVE_DATA=$preserve_data
    export DELETE_APIS=$delete_apis
    REGION="$region"
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk"
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "No active gcloud authentication found. Run 'gcloud auth login'"
    fi
    
    # Validate project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        error_exit "Project '$PROJECT_ID' not found or not accessible"
    fi
    
    # Set project context
    gcloud config set project "$PROJECT_ID" --quiet
    
    log_success "Prerequisites validation completed"
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ -f "deployment-info.json" ]]; then
        # Extract information from deployment file
        if command -v jq &> /dev/null; then
            BUCKET_NAME="${BUCKET_NAME:-$(jq -r '.bucket_name // empty' deployment-info.json)}"
            REGION="${REGION:-$(jq -r '.region // "us-central1"' deployment-info.json)}"
            log_info "Loaded deployment info from deployment-info.json"
        else
            log_warning "jq not found - cannot parse deployment-info.json automatically"
        fi
    else
        log_warning "deployment-info.json not found - will discover resources automatically"
    fi
    
    # Auto-discover bucket if not specified
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_info "Auto-discovering Cloud Storage buckets..."
        local buckets
        buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "api-schemas-" | head -5)
        
        if [[ -n "$buckets" ]]; then
            log_info "Found potential buckets:"
            echo "$buckets" | sed 's/gs:\/\//  - /' | sed 's/\///'
            
            if [[ "$FORCE" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
                echo
                read -p "Enter bucket name (without gs://): " -r
                if [[ -n "$REPLY" ]]; then
                    BUCKET_NAME="$REPLY"
                    log_info "Using bucket: $BUCKET_NAME"
                fi
            fi
        fi
    fi
}

# Confirm destruction
confirm_destruction() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log_separator
    log_warning "This will permanently delete the following resources:"
    echo "  - Project: $PROJECT_ID"
    echo "  - Cloud Functions: schema-generator, schema-validator"
    if [[ -n "${BUCKET_NAME:-}" ]] && [[ "$PRESERVE_DATA" != "true" ]]; then
        echo "  - Cloud Storage Bucket: $BUCKET_NAME (and all contents)"
    fi
    echo "  - Cloud Build configurations"
    echo "  - Build triggers"
    echo "  - Local project files"
    
    if [[ "$DELETE_APIS" == "true" ]]; then
        echo "  - Enabled APIs (Warning: May affect other resources)"
    fi
    
    echo
    log_warning "This action cannot be undone!"
    echo
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " -r
    
    if [[ ! "$REPLY" == "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
}

# Delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    local functions=("schema-generator" "schema-validator")
    
    for func in "${functions[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete Cloud Function: $func"
            continue
        fi
        
        log_info "Checking if function '$func' exists..."
        if gcloud functions describe "$func" --region="$REGION" &> /dev/null; then
            log_info "Deleting Cloud Function: $func"
            if gcloud functions delete "$func" --region="$REGION" --quiet; then
                log_success "Deleted Cloud Function: $func"
            else
                log_error "Failed to delete Cloud Function: $func"
            fi
        else
            log_info "Cloud Function '$func' not found (may already be deleted)"
        fi
    done
}

# Delete Cloud Storage bucket
delete_storage_bucket() {
    if [[ "$PRESERVE_DATA" == "true" ]]; then
        log_info "Preserving Cloud Storage bucket and data as requested"
        return 0
    fi
    
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_warning "No bucket name specified - skipping bucket deletion"
        return 0
    fi
    
    log_info "Deleting Cloud Storage bucket: $BUCKET_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete bucket: gs://$BUCKET_NAME and all contents"
        return 0
    fi
    
    # Check if bucket exists
    if gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
        # Show bucket contents before deletion
        log_info "Bucket contents:"
        gsutil ls -l "gs://$BUCKET_NAME/**" 2>/dev/null | head -10 || true
        
        # Delete bucket and all contents
        log_info "Deleting bucket and all contents..."
        if gsutil -m rm -r "gs://$BUCKET_NAME"; then
            log_success "Deleted Cloud Storage bucket: $BUCKET_NAME"
        else
            log_error "Failed to delete Cloud Storage bucket: $BUCKET_NAME"
        fi
    else
        log_info "Bucket 'gs://$BUCKET_NAME' not found (may already be deleted)"
    fi
}

# Delete Cloud Build triggers
delete_build_triggers() {
    log_info "Deleting Cloud Build triggers..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Cloud Build triggers matching: api-schema-generation"
        return 0
    fi
    
    # Find and delete relevant build triggers
    local trigger_ids
    trigger_ids=$(gcloud builds triggers list \
        --format="value(id)" \
        --filter="name:api-schema-generation" 2>/dev/null || true)
    
    if [[ -n "$trigger_ids" ]]; then
        for trigger_id in $trigger_ids; do
            log_info "Deleting build trigger: $trigger_id"
            if gcloud builds triggers delete "$trigger_id" --quiet; then
                log_success "Deleted build trigger: $trigger_id"
            else
                log_error "Failed to delete build trigger: $trigger_id"
            fi
        done
    else
        log_info "No Cloud Build triggers found for this recipe"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_delete=(
        "api-schema-project"
        "schema-generator"
        "schema-validator"
        "cloudbuild.yaml"
        "monitoring-dashboard.json"
        "deployment-info.json"
        "lifecycle.json"
    )
    
    for item in "${files_to_delete[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            if [[ -e "$item" ]]; then
                log_info "[DRY RUN] Would delete: $item"
            fi
            continue
        fi
        
        if [[ -f "$item" ]]; then
            log_info "Deleting file: $item"
            rm -f "$item"
            log_success "Deleted file: $item"
        elif [[ -d "$item" ]]; then
            log_info "Deleting directory: $item"
            rm -rf "$item"
            log_success "Deleted directory: $item"
        fi
    done
}

# Disable APIs (optional)
disable_apis() {
    if [[ "$DELETE_APIS" != "true" ]]; then
        log_info "Skipping API disabling (use --delete-apis to disable)"
        return 0
    fi
    
    log_warning "Disabling APIs - this may affect other resources in the project!"
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "artifactregistry.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would disable API: $api"
            continue
        fi
        
        log_info "Disabling API: $api"
        if gcloud services disable "$api" --quiet --force; then
            log_success "Disabled API: $api"
        else
            log_warning "Failed to disable API: $api (may still be in use)"
        fi
    done
    
    log_warning "Core APIs (cloudbuild, storage) were not disabled to preserve project functionality"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=()
    
    # Check Cloud Functions
    local remaining_functions
    remaining_functions=$(gcloud functions list \
        --format="value(name)" \
        --filter="name:(schema-generator OR schema-validator)" 2>/dev/null || true)
    
    if [[ -n "$remaining_functions" ]]; then
        cleanup_issues+=("Cloud Functions still exist: $remaining_functions")
    fi
    
    # Check Cloud Storage bucket
    if [[ -n "${BUCKET_NAME:-}" ]] && [[ "$PRESERVE_DATA" != "true" ]]; then
        if gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
            cleanup_issues+=("Cloud Storage bucket still exists: $BUCKET_NAME")
        fi
    fi
    
    # Check local files
    for item in "api-schema-project" "schema-generator" "schema-validator"; do
        if [[ -e "$item" ]]; then
            cleanup_issues+=("Local file/directory still exists: $item")
        fi
    done
    
    # Report results
    if [[ ${#cleanup_issues[@]} -eq 0 ]]; then
        log_success "Cleanup verification completed - all resources removed"
    else
        log_warning "Cleanup verification found remaining items:"
        for issue in "${cleanup_issues[@]}"; do
            log_warning "  - $issue"
        done
        
        if [[ "$DRY_RUN" != "true" ]]; then
            log_info "You may need to manually remove these items"
        fi
    fi
}

# Generate cleanup report
generate_cleanup_report() {
    log_info "Generating cleanup report..."
    
    local report_file="cleanup-report-$(date +%Y%m%d-%H%M%S).json"
    
    cat > "$report_file" << EOF
{
  "cleanup_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project_id": "$PROJECT_ID",
  "region": "$REGION",
  "script_version": "$SCRIPT_VERSION",
  "dry_run": $DRY_RUN,
  "preserved_data": $PRESERVE_DATA,
  "deleted_resources": {
    "cloud_functions": ["schema-generator", "schema-validator"],
    "storage_bucket": "${BUCKET_NAME:-'not specified'}",
    "build_triggers": "auto-discovered",
    "local_files": ["api-schema-project", "schema-generator", "schema-validator", "cloudbuild.yaml"]
  },
  "preserved_resources": {
    "enabled_apis": ["cloudbuild.googleapis.com", "storage.googleapis.com"],
    "project": "$PROJECT_ID"
  },
  "cleanup_options": {
    "force_mode": $FORCE,
    "apis_disabled": $DELETE_APIS,
    "data_preserved": $PRESERVE_DATA
  }
}
EOF
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log_success "Cleanup report saved to: $report_file"
    else
        rm -f "$report_file"
        log_info "[DRY RUN] Cleanup report would be saved"
    fi
}

# Display cleanup summary
display_summary() {
    log_separator
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN SUMMARY - No resources were actually deleted"
    else
        log_success "Cleanup completed successfully!"
    fi
    log_separator
    
    echo -e "${GREEN}CLEANUP SUMMARY${NC}"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Mode: DRY RUN (no actual deletions)"
    else
        echo "Mode: DESTRUCTIVE (resources deleted)"
    fi
    
    echo ""
    echo -e "${BLUE}RESOURCES PROCESSED:${NC}"
    echo "✓ Cloud Functions: schema-generator, schema-validator"
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if [[ "$PRESERVE_DATA" == "true" ]]; then
            echo "✓ Cloud Storage Bucket: $BUCKET_NAME (preserved)"
        else
            echo "✓ Cloud Storage Bucket: $BUCKET_NAME (deleted)"
        fi
    fi
    
    echo "✓ Cloud Build triggers"
    echo "✓ Local project files"
    
    if [[ "$DELETE_APIS" == "true" ]]; then
        echo "✓ APIs disabled"
    else
        echo "✓ APIs preserved"
    fi
    
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}TO EXECUTE CLEANUP:${NC}"
        echo "Run this script without --dry-run flag"
    else
        echo -e "${GREEN}CLEANUP COMPLETED${NC}"
        echo "All specified resources have been removed"
    fi
    
    log_separator
}

# Main cleanup function
main() {
    log_separator
    log_info "Starting cleanup of $RECIPE_NAME"
    log_info "Script version: $SCRIPT_VERSION"
    log_separator
    
    # Parse arguments and validate
    parse_arguments "$@"
    validate_prerequisites
    load_deployment_info
    
    # Confirmation
    confirm_destruction
    
    # Cleanup phase
    delete_cloud_functions
    delete_build_triggers
    delete_storage_bucket
    cleanup_local_files
    disable_apis
    
    # Verification and reporting
    verify_cleanup
    generate_cleanup_report
    display_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run completed - no resources were actually deleted"
    else
        log_success "Cleanup completed successfully!"
    fi
}

# Execute main function with all arguments
main "$@"