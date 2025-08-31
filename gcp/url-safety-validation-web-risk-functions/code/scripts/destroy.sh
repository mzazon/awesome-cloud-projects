#!/bin/bash

# URL Safety Validation with Web Risk API - Cleanup Script
# This script safely removes all resources created by the deployment script
# 
# Resources removed:
# - Cloud Functions (URL validation endpoint)
# - Cloud Storage buckets (audit logs and caching)
# - IAM permissions (service account bindings)
# - Local files (test scripts, deployment info)

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
DEPLOYMENT_INFO="${SCRIPT_DIR}/deployment_info.json"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$ERROR_LOG"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Help function
show_help() {
    cat << EOF
URL Safety Validation Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required if no deployment info)
    -r, --region REGION           Deployment region (required if no deployment info)
    -n, --function-name NAME      Function name to delete (required if no deployment info)
    -b, --bucket-pattern PATTERN  Bucket name pattern for cleanup (optional)
    -d, --dry-run                 Show what would be deleted without executing
    -f, --force                   Skip confirmation prompts
    -k, --keep-buckets            Keep storage buckets and their contents
    -a, --aggressive              Remove all matching resources (use with caution)
    -h, --help                    Show this help message

EXAMPLES:
    $0                                              # Use deployment_info.json
    $0 --project-id my-project --function-name my-validator
    $0 --dry-run                                    # Preview what would be deleted
    $0 --force --keep-buckets                       # Skip prompts, keep storage

DEPLOYMENT INFO:
    If deployment_info.json exists, it will be used automatically.
    Manual parameters override deployment info values.

SAFETY FEATURES:
    - Confirmation prompts before destructive actions
    - Dry run mode to preview deletions
    - Selective deletion options
    - Comprehensive logging of all actions

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
            -n|--function-name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            -b|--bucket-pattern)
                BUCKET_PATTERN="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -k|--keep-buckets)
                KEEP_BUCKETS=true
                shift
                ;;
            -a|--aggressive)
                AGGRESSIVE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Load deployment information from file
load_deployment_info() {
    if [[ -f "$DEPLOYMENT_INFO" ]]; then
        log "Loading deployment information from $DEPLOYMENT_INFO"
        
        # Extract values from JSON using basic parsing
        if command -v jq &> /dev/null; then
            # Use jq if available
            PROJECT_ID_FROM_FILE=$(jq -r '.project_id // empty' "$DEPLOYMENT_INFO")
            REGION_FROM_FILE=$(jq -r '.region // empty' "$DEPLOYMENT_INFO")
            FUNCTION_NAME_FROM_FILE=$(jq -r '.function_name // empty' "$DEPLOYMENT_INFO")
            AUDIT_BUCKET_FROM_FILE=$(jq -r '.audit_bucket // empty' "$DEPLOYMENT_INFO")
            CACHE_BUCKET_FROM_FILE=$(jq -r '.cache_bucket // empty' "$DEPLOYMENT_INFO")
            RANDOM_SUFFIX_FROM_FILE=$(jq -r '.random_suffix // empty' "$DEPLOYMENT_INFO")
        else
            # Fallback to grep/sed parsing
            PROJECT_ID_FROM_FILE=$(grep '"project_id"' "$DEPLOYMENT_INFO" | sed 's/.*": "\([^"]*\)".*/\1/')
            REGION_FROM_FILE=$(grep '"region"' "$DEPLOYMENT_INFO" | sed 's/.*": "\([^"]*\)".*/\1/')
            FUNCTION_NAME_FROM_FILE=$(grep '"function_name"' "$DEPLOYMENT_INFO" | sed 's/.*": "\([^"]*\)".*/\1/')
            AUDIT_BUCKET_FROM_FILE=$(grep '"audit_bucket"' "$DEPLOYMENT_INFO" | sed 's/.*": "\([^"]*\)".*/\1/')
            CACHE_BUCKET_FROM_FILE=$(grep '"cache_bucket"' "$DEPLOYMENT_INFO" | sed 's/.*": "\([^"]*\)".*/\1/')
            RANDOM_SUFFIX_FROM_FILE=$(grep '"random_suffix"' "$DEPLOYMENT_INFO" | sed 's/.*": "\([^"]*\)".*/\1/')
        fi
        
        # Use file values if not provided via command line
        PROJECT_ID="${PROJECT_ID:-$PROJECT_ID_FROM_FILE}"
        REGION="${REGION:-$REGION_FROM_FILE}"
        FUNCTION_NAME="${FUNCTION_NAME:-$FUNCTION_NAME_FROM_FILE}"
        AUDIT_BUCKET="${AUDIT_BUCKET:-$AUDIT_BUCKET_FROM_FILE}"
        CACHE_BUCKET="${CACHE_BUCKET:-$CACHE_BUCKET_FROM_FILE}"
        RANDOM_SUFFIX="${RANDOM_SUFFIX:-$RANDOM_SUFFIX_FROM_FILE}"
        
        success "Deployment information loaded successfully"
    else
        warn "Deployment info file not found: $DEPLOYMENT_INFO"
        info "Manual parameters required or use aggressive mode to find resources"
    fi
}

# Initialize variables with defaults
init_variables() {
    # Set defaults
    PROJECT_ID="${PROJECT_ID:-${GOOGLE_CLOUD_PROJECT:-}}"
    REGION="${REGION:-${GCP_REGION:-us-central1}}"
    DRY_RUN="${DRY_RUN:-false}"
    FORCE="${FORCE:-false}"
    KEEP_BUCKETS="${KEEP_BUCKETS:-false}"
    AGGRESSIVE="${AGGRESSIVE:-false}"
    
    # Generate bucket names if not provided
    if [[ -z "${AUDIT_BUCKET:-}" && -n "$PROJECT_ID" ]]; then
        if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
            AUDIT_BUCKET="url-validation-logs-${PROJECT_ID}-${RANDOM_SUFFIX}"
            CACHE_BUCKET="url-validation-cache-${PROJECT_ID}-${RANDOM_SUFFIX}"
        elif [[ -n "${BUCKET_PATTERN:-}" ]]; then
            AUDIT_BUCKET_PATTERN="${BUCKET_PATTERN}"
            CACHE_BUCKET_PATTERN="${BUCKET_PATTERN}"
        fi
    fi
    
    # Validate required parameters for non-aggressive mode
    if [[ "$AGGRESSIVE" == "false" ]]; then
        if [[ -z "$PROJECT_ID" ]]; then
            error "Project ID is required. Use --project-id or set GOOGLE_CLOUD_PROJECT environment variable."
            show_help
            exit 1
        fi
        
        if [[ -z "$FUNCTION_NAME" && -z "${BUCKET_PATTERN:-}" ]]; then
            error "Function name or bucket pattern is required when deployment info is not available."
            show_help
            exit 1
        fi
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if project exists (if provided)
    if [[ -n "$PROJECT_ID" ]]; then
        if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
            error "Project $PROJECT_ID does not exist or you don't have access."
            exit 1
        fi
        
        # Set project context
        gcloud config set project "$PROJECT_ID" 2>/dev/null || true
    fi
    
    success "Prerequisites check completed"
}

# Discover resources in aggressive mode
discover_resources() {
    if [[ "$AGGRESSIVE" == "false" ]]; then
        return 0
    fi
    
    log "Discovering URL validation resources across all projects..."
    
    # Find all accessible projects
    local projects
    projects=$(gcloud projects list --format="value(projectId)" 2>/dev/null || echo "")
    
    if [[ -z "$projects" ]]; then
        warn "No accessible projects found"
        return 0
    fi
    
    # Arrays to store discovered resources
    declare -a discovered_functions=()
    declare -a discovered_buckets=()
    
    # Search each project
    while IFS= read -r project; do
        [[ -z "$project" ]] && continue
        
        log "Searching project: $project"
        
        # Find Cloud Functions
        local functions
        functions=$(gcloud functions list --project="$project" \
            --format="value(name)" \
            --filter="name~url-validator" 2>/dev/null || echo "")
        
        while IFS= read -r function; do
            [[ -z "$function" ]] && continue
            discovered_functions+=("$project:$function")
        done <<< "$functions"
        
        # Find Storage buckets
        local buckets
        buckets=$(gsutil ls -p "$project" 2>/dev/null | grep -E "(url-validation-|url-validator-)" || echo "")
        
        while IFS= read -r bucket; do
            [[ -z "$bucket" ]] && continue
            discovered_buckets+=("$bucket")
        done <<< "$buckets"
        
    done <<< "$projects"
    
    # Display discovered resources
    if [[ ${#discovered_functions[@]} -gt 0 || ${#discovered_buckets[@]} -gt 0 ]]; then
        cat << EOF

${BLUE}═══════════════════════════════════════════════════════════════${NC}
${BLUE}                    DISCOVERED RESOURCES                       ${NC}
${BLUE}═══════════════════════════════════════════════════════════════${NC}

Functions found:
EOF
        for func in "${discovered_functions[@]}"; do
            echo "  - $func"
        done
        
        echo
        echo "Buckets found:"
        for bucket in "${discovered_buckets[@]}"; do
            echo "  - $bucket"
        done
        
        cat << EOF

${BLUE}═══════════════════════════════════════════════════════════════${NC}

EOF
        
        # Store for later use
        DISCOVERED_FUNCTIONS=("${discovered_functions[@]}")
        DISCOVERED_BUCKETS=("${discovered_buckets[@]}")
    else
        info "No URL validation resources discovered"
    fi
}

# Show cleanup plan
show_cleanup_plan() {
    cat << EOF

${BLUE}═══════════════════════════════════════════════════════════════${NC}
${BLUE}                      CLEANUP PLAN                            ${NC}
${BLUE}═══════════════════════════════════════════════════════════════${NC}

EOF

    if [[ "$AGGRESSIVE" == "true" ]]; then
        echo "Mode: Aggressive (will search and delete all matching resources)"
        echo
        
        if [[ ${#DISCOVERED_FUNCTIONS[@]:-0} -gt 0 ]]; then
            echo "Functions to delete:"
            for func in "${DISCOVERED_FUNCTIONS[@]}"; do
                echo "  ${RED}✗${NC} $func"
            done
            echo
        fi
        
        if [[ ${#DISCOVERED_BUCKETS[@]:-0} -gt 0 ]]; then
            echo "Buckets to delete:"
            for bucket in "${DISCOVERED_BUCKETS[@]}"; do
                echo "  ${RED}✗${NC} $bucket"
            done
            echo
        fi
    else
        echo "Project ID:           ${PROJECT_ID:-Not specified}"
        echo "Region:               ${REGION:-Not specified}"
        echo
        echo "Resources to be deleted:"
        
        if [[ -n "${FUNCTION_NAME:-}" ]]; then
            echo "  ${RED}✗${NC} Cloud Function:      ${FUNCTION_NAME}"
        fi
        
        if [[ "$KEEP_BUCKETS" == "false" ]]; then
            if [[ -n "${AUDIT_BUCKET:-}" ]]; then
                echo "  ${RED}✗${NC} Audit Bucket:       gs://${AUDIT_BUCKET}"
            fi
            if [[ -n "${CACHE_BUCKET:-}" ]]; then
                echo "  ${RED}✗${NC} Cache Bucket:       gs://${CACHE_BUCKET}"
            fi
            if [[ -n "${AUDIT_BUCKET_PATTERN:-}" ]]; then
                echo "  ${RED}✗${NC} Buckets matching:   ${AUDIT_BUCKET_PATTERN}"
            fi
        else
            echo "  ${YELLOW}⚠${NC} Storage buckets will be preserved"
        fi
        
        echo "  ${RED}✗${NC} IAM bindings:       Web Risk API & Storage access"
        echo "  ${RED}✗${NC} Local files:        Test scripts and deployment info"
    fi

    cat << EOF

${YELLOW}⚠ WARNING: This action cannot be undone!${NC}
${YELLOW}⚠ All data in deleted buckets will be permanently lost!${NC}

${BLUE}═══════════════════════════════════════════════════════════════${NC}

EOF
}

# Confirm cleanup
confirm_cleanup() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo -n "Are you sure you want to delete these resources? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo -n "This will permanently delete all data. Type 'DELETE' to confirm: "
    read -r confirmation
    if [[ "$confirmation" != "DELETE" ]]; then
        info "Cleanup cancelled - confirmation not received"
        exit 0
    fi
}

# Remove Cloud Function
remove_cloud_function() {
    if [[ -z "${FUNCTION_NAME:-}" && ${#DISCOVERED_FUNCTIONS[@]:-0} -eq 0 ]]; then
        info "No Cloud Function specified for deletion"
        return 0
    fi
    
    log "Removing Cloud Function(s)..."
    
    # Handle specific function
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            log "Deleting Cloud Function: $FUNCTION_NAME"
            
            # Get service account before deleting function
            local function_sa=""
            function_sa=$(gcloud functions describe "$FUNCTION_NAME" \
                --region="$REGION" \
                --format="value(serviceAccountEmail)" 2>/dev/null || echo "")
            
            if gcloud functions delete "$FUNCTION_NAME" \
                --region="$REGION" \
                --quiet 2>/dev/null; then
                success "Deleted Cloud Function: $FUNCTION_NAME"
                
                # Remove IAM bindings if service account was found
                if [[ -n "$function_sa" && "$function_sa" != "null" ]]; then
                    remove_iam_bindings "$function_sa"
                fi
            else
                warn "Failed to delete Cloud Function: $FUNCTION_NAME (may not exist)"
            fi
        else
            info "Would delete Cloud Function: $FUNCTION_NAME"
        fi
    fi
    
    # Handle discovered functions in aggressive mode
    if [[ "$AGGRESSIVE" == "true" && ${#DISCOVERED_FUNCTIONS[@]:-0} -gt 0 ]]; then
        for func_info in "${DISCOVERED_FUNCTIONS[@]}"; do
            local project="${func_info%%:*}"
            local func_name="${func_info##*:}"
            
            if [[ "$DRY_RUN" == "false" ]]; then
                log "Deleting discovered function: $func_name in project $project"
                
                # Get service account before deleting
                local function_sa=""
                function_sa=$(gcloud functions describe "$func_name" \
                    --project="$project" \
                    --format="value(serviceAccountEmail)" 2>/dev/null || echo "")
                
                if gcloud functions delete "$func_name" \
                    --project="$project" \
                    --quiet 2>/dev/null; then
                    success "Deleted function: $func_name from project $project"
                    
                    # Remove IAM bindings
                    if [[ -n "$function_sa" && "$function_sa" != "null" ]]; then
                        remove_iam_bindings "$function_sa" "$project"
                    fi
                else
                    warn "Failed to delete function: $func_name from project $project"
                fi
            else
                info "Would delete function: $func_name from project $project"
            fi
        done
    fi
    
    success "Cloud Function removal completed"
}

# Remove IAM bindings
remove_iam_bindings() {
    local service_account="$1"
    local target_project="${2:-$PROJECT_ID}"
    
    if [[ -z "$service_account" || "$service_account" == "null" ]]; then
        info "No service account specified for IAM cleanup"
        return 0
    fi
    
    log "Removing IAM bindings for service account: $service_account"
    
    local roles=(
        "roles/webrisk.user"
        "roles/storage.objectAdmin"
    )
    
    for role in "${roles[@]}"; do
        if [[ "$DRY_RUN" == "false" ]]; then
            if gcloud projects remove-iam-policy-binding "$target_project" \
                --member="serviceAccount:$service_account" \
                --role="$role" \
                --quiet 2>/dev/null; then
                success "Removed IAM binding: $role for $service_account"
            else
                warn "Failed to remove IAM binding: $role for $service_account (may not exist)"
            fi
        else
            info "Would remove IAM binding: $role for $service_account"
        fi
    done
}

# Remove Cloud Storage buckets
remove_storage_buckets() {
    if [[ "$KEEP_BUCKETS" == "true" ]]; then
        info "Skipping bucket deletion (--keep-buckets specified)"
        return 0
    fi
    
    log "Removing Cloud Storage buckets..."
    
    # Handle specific buckets
    local buckets_to_delete=()
    
    if [[ -n "${AUDIT_BUCKET:-}" ]]; then
        buckets_to_delete+=("gs://$AUDIT_BUCKET")
    fi
    
    if [[ -n "${CACHE_BUCKET:-}" ]]; then
        buckets_to_delete+=("gs://$CACHE_BUCKET")
    fi
    
    # Handle pattern-based buckets
    if [[ -n "${AUDIT_BUCKET_PATTERN:-}" ]]; then
        local pattern_buckets
        pattern_buckets=$(gsutil ls 2>/dev/null | grep -E "$AUDIT_BUCKET_PATTERN" || echo "")
        while IFS= read -r bucket; do
            [[ -z "$bucket" ]] && continue
            buckets_to_delete+=("$bucket")
        done <<< "$pattern_buckets"
    fi
    
    # Handle discovered buckets
    if [[ "$AGGRESSIVE" == "true" && ${#DISCOVERED_BUCKETS[@]:-0} -gt 0 ]]; then
        buckets_to_delete+=("${DISCOVERED_BUCKETS[@]}")
    fi
    
    # Remove duplicates
    local unique_buckets=($(printf '%s\n' "${buckets_to_delete[@]}" | sort -u))
    
    # Delete each bucket
    for bucket in "${unique_buckets[@]}"; do
        if [[ "$DRY_RUN" == "false" ]]; then
            log "Deleting bucket: $bucket"
            
            # Check if bucket exists
            if gsutil ls "$bucket" &> /dev/null; then
                # Remove all objects first
                if gsutil -m rm -r "${bucket}/**" 2>/dev/null; then
                    log "Removed all objects from: $bucket"
                fi
                
                # Remove bucket
                if gsutil rb "$bucket" 2>/dev/null; then
                    success "Deleted bucket: $bucket"
                else
                    warn "Failed to delete bucket: $bucket"
                fi
            else
                warn "Bucket does not exist: $bucket"
            fi
        else
            info "Would delete bucket: $bucket"
        fi
    done
    
    success "Storage bucket removal completed"
}

# Remove local files
remove_local_files() {
    log "Removing local files..."
    
    local files_to_remove=(
        "$DEPLOYMENT_INFO"
        "${SCRIPT_DIR}/test_validation.py"
        "$LOG_FILE"
        "$ERROR_LOG"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "false" ]]; then
                rm -f "$file"
                success "Removed file: $file"
            else
                info "Would remove file: $file"
            fi
        fi
    done
    
    success "Local file cleanup completed"
}

# Show cleanup summary
show_cleanup_summary() {
    cat << EOF

${GREEN}═══════════════════════════════════════════════════════════════${NC}
${GREEN}                    CLEANUP COMPLETED                         ${NC}
${GREEN}═══════════════════════════════════════════════════════════════${NC}

EOF

    if [[ "$DRY_RUN" == "false" ]]; then
        cat << EOF
${GREEN}Resources Removed:${NC}
✅ Cloud Function(s) deleted
✅ IAM bindings removed
EOF
        if [[ "$KEEP_BUCKETS" == "false" ]]; then
            echo "✅ Storage buckets deleted"
        else
            echo "⚠️  Storage buckets preserved"
        fi
        
        cat << EOF
✅ Local files cleaned up

${GREEN}Verification:${NC}
You can verify the cleanup by running:
- gcloud functions list --filter="name~url-validator"
- gsutil ls | grep -E "(url-validation|url-validator)"

${GREEN}Cost Impact:${NC}
- All ongoing charges should be stopped
- Storage charges eliminated (if buckets were deleted)
- Function compute charges eliminated

EOF
    else
        cat << EOF
${YELLOW}DRY RUN COMPLETED${NC}
No resources were actually deleted.
Run without --dry-run to perform the actual cleanup.

EOF
    fi

    cat << EOF
${GREEN}Cleanup Log:${NC} $LOG_FILE
${GREEN}Error Log:${NC} $ERROR_LOG

${GREEN}═══════════════════════════════════════════════════════════════${NC}

EOF
}

# Main cleanup function
main() {
    # Initialize log files
    echo "URL Safety Validation Cleanup Log - $(date)" > "$LOG_FILE"
    echo "URL Safety Validation Cleanup Errors - $(date)" > "$ERROR_LOG"
    
    log "Starting URL Safety Validation cleanup..."
    
    # Parse arguments and initialize
    parse_args "$@"
    load_deployment_info
    init_variables
    
    # Check prerequisites
    check_prerequisites
    
    # Discover resources if in aggressive mode
    discover_resources
    
    # Show cleanup plan
    show_cleanup_plan
    
    # Confirm cleanup unless forced or dry run
    if [[ "$DRY_RUN" == "false" ]]; then
        confirm_cleanup
    fi
    
    # Execute cleanup steps
    remove_cloud_function
    remove_storage_buckets
    remove_local_files
    
    # Show summary
    show_cleanup_summary
    
    success "URL Safety Validation cleanup completed successfully!"
}

# Run main function with all arguments
main "$@"