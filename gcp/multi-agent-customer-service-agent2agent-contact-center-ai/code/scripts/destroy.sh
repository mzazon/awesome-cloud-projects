#!/bin/bash

# Multi-Agent Customer Service Cleanup Script
# Recipe: Multi-Agent Customer Service with Agent2Agent and Contact Center AI
# Provider: Google Cloud Platform (GCP)
# Version: 1.0

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
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

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ID=""
REGION=""
ZONE=""
FUNCTION_PREFIX=""
CCAI_INSTANCE=""
RANDOM_SUFFIX=""
DRY_RUN=false
SKIP_CONFIRMATION=false
FORCE_DELETE=false

# Deployment state tracking
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Multi-Agent Customer Service infrastructure

OPTIONS:
    -p, --project-id PROJECT_ID    GCP project ID (required if state file not found)
    -r, --region REGION           GCP region (auto-detected from state file)
    -s, --suffix SUFFIX          Resource suffix (auto-detected from state file)
    -d, --dry-run                Show what would be destroyed without making changes
    -y, --yes                    Skip confirmation prompts
    -f, --force                  Force deletion even if some resources fail
    -h, --help                   Display this help message

EXAMPLES:
    $0                                    # Use state file for all parameters
    $0 --project-id my-gcp-project        # Specify project if state file missing
    $0 --dry-run                          # Show what would be deleted
    $0 --force --yes                      # Force deletion without confirmation

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
            -s|--suffix)
                RANDOM_SUFFIX="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -f|--force)
                FORCE_DELETE=true
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
}

# Load deployment state
load_state() {
    log_info "Loading deployment state..."

    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        source "$DEPLOYMENT_STATE_FILE"
        log_success "Loaded state from: $DEPLOYMENT_STATE_FILE"
        
        # Override with command line arguments if provided
        [[ -n "${PROJECT_ID:-}" ]] || PROJECT_ID="${PROJECT_ID:-}"
        [[ -n "${REGION:-}" ]] || REGION="${REGION:-us-central1}"
        [[ -n "${ZONE:-}" ]] || ZONE="${ZONE:-us-central1-a}"
        [[ -n "${FUNCTION_PREFIX:-}" ]] || FUNCTION_PREFIX="${FUNCTION_PREFIX:-agent}"
        [[ -n "${RANDOM_SUFFIX:-}" ]] || RANDOM_SUFFIX="${RANDOM_SUFFIX:-}"
        
    else
        log_warning "State file not found: $DEPLOYMENT_STATE_FILE"
        
        # Validate required parameters if no state file
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "Project ID is required when state file is missing. Use --project-id or -p to specify."
            usage
            exit 1
        fi
        
        # Set defaults
        REGION="${REGION:-us-central1}"
        ZONE="${ZONE:-us-central1-a}"
        
        if [[ -z "$RANDOM_SUFFIX" ]]; then
            log_warning "No suffix provided. Will attempt to find resources with common patterns."
            FUNCTION_PREFIX="agent"
        else
            FUNCTION_PREFIX="agent-${RANDOM_SUFFIX}"
        fi
    fi

    log_info "Configuration loaded:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Zone: $ZONE"
    log_info "  Function Prefix: $FUNCTION_PREFIX"
}

# Verify prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it first."
    fi

    # Verify gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "Not authenticated with gcloud. Run 'gcloud auth login' first."
    fi

    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        error_exit "Project '$PROJECT_ID' does not exist or is not accessible."
    fi

    # Set project for subsequent commands
    gcloud config set project "$PROJECT_ID" >/dev/null 2>&1

    log_success "Prerequisites check completed"
}

# List resources to be deleted
list_resources() {
    log_info "Discovering resources to delete..."

    echo ""
    echo "=== RESOURCES TO BE DELETED ==="
    echo ""

    # List Cloud Functions
    echo "Cloud Functions:"
    if [[ "$DRY_RUN" == "false" ]]; then
        local functions
        functions=$(gcloud functions list --regions="$REGION" --filter="name:$FUNCTION_PREFIX" --format="value(name)" 2>/dev/null || echo "")
        if [[ -n "$functions" ]]; then
            echo "$functions" | sed 's/^/  - /'
        else
            echo "  - No functions found with prefix: $FUNCTION_PREFIX"
        fi
    else
        echo "  - ${FUNCTION_PREFIX}-router"
        echo "  - ${FUNCTION_PREFIX}-broker"
        echo "  - ${FUNCTION_PREFIX}-billing"
        echo "  - ${FUNCTION_PREFIX}-technical"
    fi

    # List Firestore collections
    echo ""
    echo "Firestore Collections/Documents:"
    if [[ "$DRY_RUN" == "false" ]]; then
        local collections=("knowledge" "routing_logs" "agent_interactions" "conversations" "integration")
        for collection in "${collections[@]}"; do
            local docs
            docs=$(gcloud firestore documents list "$collection" --format="value(name)" --limit=5 2>/dev/null || echo "")
            if [[ -n "$docs" ]]; then
                echo "  - Collection: $collection ($(echo "$docs" | wc -l | tr -d ' ') documents)"
            fi
        done
    else
        echo "  - knowledge/* (agent capabilities)"
        echo "  - routing_logs/* (routing decisions)"
        echo "  - agent_interactions/* (conversation logs)"
        echo "  - conversations/* (session data)"
        echo "  - integration/* (endpoint configurations)"
    fi

    # List Vertex AI resources
    echo ""
    echo "Vertex AI Resources:"
    if [[ "$DRY_RUN" == "false" && -f "$DEPLOYMENT_STATE_FILE" ]]; then
        source "$DEPLOYMENT_STATE_FILE"
        if [[ -n "${DATASET_ID:-}" ]]; then
            echo "  - Dataset: $DATASET_ID"
        fi
    else
        echo "  - Dataset: multi-agent-customer-service (if exists)"
    fi

    # List Storage buckets
    echo ""
    echo "Storage Buckets:"
    if [[ "$DRY_RUN" == "false" ]]; then
        local bucket_name="${PROJECT_ID}-agent-models"
        if gsutil ls -b "gs://$bucket_name" >/dev/null 2>&1; then
            echo "  - gs://$bucket_name"
        fi
    else
        echo "  - gs://${PROJECT_ID}-agent-models (if exists)"
    fi

    echo ""
    echo "Note: Firestore database itself will NOT be deleted (requires manual action)"
    echo "================================"
    echo ""
}

# Delete Cloud Functions
delete_functions() {
    log_info "Deleting Cloud Functions..."

    local functions_to_delete=()
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Get actual function names
        local functions
        functions=$(gcloud functions list --regions="$REGION" --filter="name:$FUNCTION_PREFIX" --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$functions" ]]; then
            while IFS= read -r function_name; do
                functions_to_delete+=("$function_name")
            done <<< "$functions"
        fi
        
        # Also try specific function names from state
        if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
            source "$DEPLOYMENT_STATE_FILE"
            local specific_functions=(
                "${FUNCTION_PREFIX}-router"
                "${FUNCTION_PREFIX}-broker"
                "${FUNCTION_PREFIX}-billing"
                "${FUNCTION_PREFIX}-technical"
            )
            for func in "${specific_functions[@]}"; do
                if gcloud functions describe "$func" --region="$REGION" >/dev/null 2>&1; then
                    functions_to_delete+=("$func")
                fi
            done
        fi
    else
        # Dry run - assume all functions exist
        functions_to_delete=(
            "${FUNCTION_PREFIX}-router"
            "${FUNCTION_PREFIX}-broker"
            "${FUNCTION_PREFIX}-billing"
            "${FUNCTION_PREFIX}-technical"
        )
    fi

    # Remove duplicates
    local unique_functions
    IFS=" " read -r -a unique_functions <<< "$(printf '%s\n' "${functions_to_delete[@]}" | sort -u | tr '\n' ' ')"

    if [[ ${#unique_functions[@]} -eq 0 ]]; then
        log_warning "No Cloud Functions found to delete"
        return 0
    fi

    for function_name in "${unique_functions[@]}"; do
        if [[ -n "$function_name" ]]; then
            log_info "Deleting function: $function_name"
            if [[ "$DRY_RUN" == "false" ]]; then
                if gcloud functions delete "$function_name" --region="$REGION" --quiet; then
                    log_success "Deleted function: $function_name"
                else
                    if [[ "$FORCE_DELETE" == "true" ]]; then
                        log_warning "Failed to delete function: $function_name (continuing due to --force)"
                    else
                        error_exit "Failed to delete function: $function_name"
                    fi
                fi
            else
                log_info "[DRY RUN] Would delete function: $function_name"
            fi
        fi
    done

    log_success "Cloud Functions deletion completed"
}

# Delete Firestore collections and documents
delete_firestore_data() {
    log_info "Deleting Firestore data..."

    local collections=("knowledge" "routing_logs" "agent_interactions" "conversations" "integration")

    for collection in "${collections[@]}"; do
        log_info "Deleting collection: $collection"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            # List and delete documents in batches
            local docs
            docs=$(gcloud firestore documents list "$collection" --format="value(name)" --limit=100 2>/dev/null || echo "")
            
            if [[ -n "$docs" ]]; then
                local doc_count
                doc_count=$(echo "$docs" | wc -l | tr -d ' ')
                log_info "Found $doc_count documents in $collection"
                
                # Delete documents in batches to avoid rate limits
                while IFS= read -r doc_path; do
                    if [[ -n "$doc_path" ]]; then
                        if gcloud firestore documents delete "$doc_path" --quiet 2>/dev/null; then
                            log_info "Deleted document: $doc_path"
                        else
                            if [[ "$FORCE_DELETE" == "true" ]]; then
                                log_warning "Failed to delete document: $doc_path (continuing due to --force)"
                            else
                                log_warning "Failed to delete document: $doc_path"
                            fi
                        fi
                        # Small delay to avoid rate limits
                        sleep 0.1
                    fi
                done <<< "$docs"
            else
                log_info "No documents found in collection: $collection"
            fi
        else
            log_info "[DRY RUN] Would delete all documents in collection: $collection"
        fi
    done

    # Note about database deletion
    log_warning "Firestore database itself was not deleted (requires manual action in Google Cloud Console)"
    log_success "Firestore data deletion completed"
}

# Delete Vertex AI resources
delete_vertex_ai() {
    log_info "Deleting Vertex AI resources..."

    if [[ "$DRY_RUN" == "false" ]]; then
        # Delete dataset if we have the ID
        if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
            source "$DEPLOYMENT_STATE_FILE"
            if [[ -n "${DATASET_ID:-}" ]]; then
                log_info "Deleting Vertex AI dataset: $DATASET_ID"
                if gcloud ai datasets delete "$DATASET_ID" --region="$REGION" --quiet; then
                    log_success "Deleted Vertex AI dataset: $DATASET_ID"
                else
                    if [[ "$FORCE_DELETE" == "true" ]]; then
                        log_warning "Failed to delete dataset: $DATASET_ID (continuing due to --force)"
                    else
                        log_warning "Failed to delete dataset: $DATASET_ID"
                    fi
                fi
            fi
        fi

        # Try to find and delete datasets by name
        local datasets
        datasets=$(gcloud ai datasets list --region="$REGION" --filter="displayName:multi-agent-customer-service" --format="value(name)" 2>/dev/null || echo "")
        
        while IFS= read -r dataset_path; do
            if [[ -n "$dataset_path" ]]; then
                local dataset_id
                dataset_id=$(echo "$dataset_path" | cut -d'/' -f6)
                log_info "Deleting Vertex AI dataset: $dataset_id"
                if gcloud ai datasets delete "$dataset_id" --region="$REGION" --quiet; then
                    log_success "Deleted Vertex AI dataset: $dataset_id"
                else
                    if [[ "$FORCE_DELETE" == "true" ]]; then
                        log_warning "Failed to delete dataset: $dataset_id (continuing due to --force)"
                    else
                        log_warning "Failed to delete dataset: $dataset_id"
                    fi
                fi
            fi
        done <<< "$datasets"
    else
        log_info "[DRY RUN] Would delete Vertex AI datasets"
    fi

    log_success "Vertex AI resources deletion completed"
}

# Delete Storage buckets
delete_storage() {
    log_info "Deleting Storage buckets..."

    local bucket_name="${PROJECT_ID}-agent-models"

    if [[ "$DRY_RUN" == "false" ]]; then
        # Check if bucket exists
        if gsutil ls -b "gs://$bucket_name" >/dev/null 2>&1; then
            log_info "Deleting storage bucket: gs://$bucket_name"
            
            # Delete all objects first
            if gsutil -m rm -r "gs://$bucket_name/**" 2>/dev/null; then
                log_info "Deleted all objects in bucket: $bucket_name"
            else
                log_info "No objects found in bucket or already empty: $bucket_name"
            fi
            
            # Delete the bucket
            if gsutil rb "gs://$bucket_name"; then
                log_success "Deleted storage bucket: gs://$bucket_name"
            else
                if [[ "$FORCE_DELETE" == "true" ]]; then
                    log_warning "Failed to delete bucket: gs://$bucket_name (continuing due to --force)"
                else
                    log_warning "Failed to delete bucket: gs://$bucket_name"
                fi
            fi
        else
            log_info "Storage bucket does not exist: gs://$bucket_name"
        fi
    else
        log_info "[DRY RUN] Would delete storage bucket: gs://$bucket_name"
    fi

    log_success "Storage deletion completed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."

    local files_to_remove=(
        "$DEPLOYMENT_STATE_FILE"
        "${SCRIPT_DIR}/ccai-config.json"
    )

    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "false" ]]; then
                rm -f "$file"
                log_success "Removed local file: $file"
            else
                log_info "[DRY RUN] Would remove local file: $file"
            fi
        fi
    done

    log_success "Local cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Skipping cleanup verification"
        return 0
    fi

    local cleanup_issues=0

    # Check for remaining functions
    local remaining_functions
    remaining_functions=$(gcloud functions list --regions="$REGION" --filter="name:$FUNCTION_PREFIX" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$remaining_functions" ]]; then
        log_warning "Some Cloud Functions still exist:"
        echo "$remaining_functions" | sed 's/^/  - /'
        ((cleanup_issues++))
    fi

    # Check for remaining Firestore documents (sample)
    local sample_docs
    sample_docs=$(gcloud firestore documents list knowledge --limit=1 --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$sample_docs" ]]; then
        log_warning "Some Firestore documents may still exist in knowledge collection"
        ((cleanup_issues++))
    fi

    # Check for storage bucket
    local bucket_name="${PROJECT_ID}-agent-models"
    if gsutil ls -b "gs://$bucket_name" >/dev/null 2>&1; then
        log_warning "Storage bucket still exists: gs://$bucket_name"
        ((cleanup_issues++))
    fi

    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "Cleanup verification passed - all resources appear to be deleted"
    else
        log_warning "Cleanup verification found $cleanup_issues potential issues"
        if [[ "$FORCE_DELETE" == "false" ]]; then
            log_info "Use --force flag to ignore cleanup verification issues"
        fi
    fi
}

# Display cleanup summary
show_summary() {
    echo ""
    log_info "Cleanup Summary"
    echo "==============="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Function Prefix: $FUNCTION_PREFIX"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN MODE - No resources were actually deleted"
        echo ""
        echo "To perform actual cleanup, run:"
        echo "  $0 --project-id $PROJECT_ID"
    else
        echo "Cleanup completed for:"
        echo "- Cloud Functions (agent router, broker, billing, technical)"
        echo "- Firestore documents (knowledge base, logs, interactions)"
        echo "- Vertex AI datasets and models"
        echo "- Storage buckets (model artifacts)"
        echo "- Local state and configuration files"
        echo ""
        echo "Manual cleanup required:"
        echo "- Firestore database (delete in Google Cloud Console if desired)"
        echo "- Any custom IAM roles or service accounts created manually"
        echo "- Contact Center AI Platform configurations (if any)"
    fi
    
    echo ""
    log_success "Multi-Agent Customer Service cleanup completed!"
}

# Main cleanup function
main() {
    echo "Multi-Agent Customer Service Cleanup Script"
    echo "==========================================="
    echo ""

    parse_args "$@"
    load_state
    check_prerequisites

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY RUN mode - no resources will be deleted"
    fi

    # Show what will be deleted
    list_resources

    # Confirmation prompt
    if [[ "$SKIP_CONFIRMATION" == "false" && "$DRY_RUN" == "false" ]]; then
        echo ""
        log_warning "This will permanently delete all multi-agent customer service infrastructure!"
        echo ""
        read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " -r
        echo ""
        if [[ "$REPLY" != "DELETE" ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi

    # Execute cleanup steps
    delete_functions
    delete_firestore_data
    delete_vertex_ai
    delete_storage
    cleanup_local_files
    verify_cleanup
    show_summary
}

# Execute main function with all arguments
main "$@"