#!/bin/bash

# Cross-Platform Mobile Development Workflows Cleanup Script
# This script removes Firebase App Distribution, Cloud Build, Firebase Test Lab, 
# and Cloud Source Repositories resources created by the deployment script

set -euo pipefail

# Colors for output
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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Script variables
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly CLEANUP_LOG="${PROJECT_DIR}/cleanup.log"

# Configuration variables
PROJECT_ID=""
REGION=""
FIREBASE_PROJECT_ID=""
APP_NAME=""
REPO_NAME=""
ANDROID_APP_ID=""
DRY_RUN=false
FORCE=false
SKIP_CONFIRMATION=false

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Cleanup encountered errors. Check ${CLEANUP_LOG} for details"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Usage function
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Remove Cross-Platform Mobile Development Workflows resources

OPTIONS:
    -p, --project-id ID         Google Cloud Project ID (required if no .env file)
    -r, --repo-name NAME        Source repository name (auto-detected from .env)
    -a, --app-name NAME         Mobile app name (auto-detected from .env)
    -d, --dry-run              Show what would be removed without making changes
    -f, --force                Skip confirmation prompts (dangerous)
    -y, --yes                  Skip confirmation prompts (same as --force)
    --delete-project           Delete the entire Google Cloud project (DANGEROUS)
    -h, --help                 Show this help message

EXAMPLES:
    $SCRIPT_NAME                                    # Use values from .env file
    $SCRIPT_NAME --project-id my-mobile-project     # Specify project explicitly
    $SCRIPT_NAME --dry-run                          # Preview what would be deleted
    $SCRIPT_NAME --force                            # Skip confirmations
    $SCRIPT_NAME --delete-project --force           # Delete entire project

SAFETY FEATURES:
    - Confirmation prompts for destructive operations
    - Dry-run mode to preview changes
    - Detailed logging of all operations
    - Graceful handling of missing resources

EOF
}

# Parse command line arguments
parse_args() {
    local delete_project=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--repo-name)
                REPO_NAME="$2"
                shift 2
                ;;
            -a|--app-name)
                APP_NAME="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force|-y|--yes)
                FORCE=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            --delete-project)
                delete_project=true
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

    # Load values from .env file if it exists
    local env_file="$PROJECT_DIR/.env"
    if [[ -f "$env_file" ]]; then
        log_info "Loading configuration from .env file"
        # shellcheck source=/dev/null
        source "$env_file"
        
        # Override with any explicitly provided values
        PROJECT_ID="${PROJECT_ID:-$project_id}"
        REGION="${REGION:-$region}"
        FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-$firebase_project_id}"
        APP_NAME="${APP_NAME:-$app_name}"
        REPO_NAME="${REPO_NAME:-$repo_name}"
        ANDROID_APP_ID="${ANDROID_APP_ID:-$android_app_id}"
    fi

    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use --project-id flag or ensure .env file exists."
        usage
        exit 1
    fi

    # Set Firebase project ID if not set
    FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-$PROJECT_ID}"

    # Handle project deletion flag
    if [[ "$delete_project" == "true" ]]; then
        if [[ "$FORCE" != "true" ]]; then
            log_warning "Project deletion requested. This will DELETE THE ENTIRE PROJECT and all its resources!"
            read -p "Are you absolutely sure you want to delete project '$PROJECT_ID'? Type 'DELETE' to confirm: " confirmation
            if [[ "$confirmation" != "DELETE" ]]; then
                log_info "Project deletion cancelled"
                exit 0
            fi
        fi
        delete_entire_project
        exit 0
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if running in dry-run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No actual resources will be removed"
        return 0
    fi

    # Check gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed or not in PATH"
        exit 1
    fi

    # Check firebase CLI
    if ! command -v firebase &> /dev/null; then
        log_error "firebase CLI is not installed or not in PATH"
        exit 1
    fi

    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with gcloud. Run 'gcloud auth login'"
        exit 1
    fi

    # Check project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project '$PROJECT_ID' not found or not accessible"
        exit 1
    fi

    log_success "Prerequisites check completed"
}

# Execute command with logging
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    log_info "$description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: $cmd"
        return 0
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') - $description: $cmd" >> "$CLEANUP_LOG"
    
    if ! eval "$cmd" >> "$CLEANUP_LOG" 2>&1; then
        if [[ "$ignore_errors" == "true" ]]; then
            log_warning "Failed (ignored): $description"
            echo "Command failed (ignored): $cmd" >> "$CLEANUP_LOG"
            return 0
        else
            log_error "Failed: $description"
            echo "Command: $cmd" >> "$CLEANUP_LOG"
            return 1
        fi
    fi
    
    log_success "$description"
    return 0
}

# Confirm destructive operation
confirm_operation() {
    if [[ "$FORCE" == "true" || "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    local message="$1"
    log_warning "$message"
    read -p "Continue? [y/N]: " confirmation
    
    case "$confirmation" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            log_info "Operation cancelled by user"
            exit 0
            ;;
    esac
}

# Delete Firebase App Distribution tester groups
delete_tester_groups() {
    log_info "Removing Firebase App Distribution tester groups..."

    local groups=("qa-team" "stakeholders" "beta-users")
    
    for group in "${groups[@]}"; do
        execute_command "firebase appdistribution:group:delete '$group' --project='$FIREBASE_PROJECT_ID' --force" \
            "Deleting tester group: $group" true
    done

    log_success "Tester groups cleanup completed"
}

# Delete Cloud Build triggers
delete_build_triggers() {
    log_info "Removing Cloud Build triggers..."

    if [[ "$DRY_RUN" != "true" ]]; then
        # Get trigger IDs for this repository
        local trigger_ids
        trigger_ids=$(gcloud builds triggers list \
            --format="value(id)" \
            --filter="github.name:'$REPO_NAME' OR cloudSourceRepo.repoName:'$REPO_NAME'" \
            --project="$PROJECT_ID" 2>/dev/null || echo "")
        
        if [[ -n "$trigger_ids" ]]; then
            while IFS= read -r trigger_id; do
                if [[ -n "$trigger_id" ]]; then
                    execute_command "gcloud builds triggers delete '$trigger_id' --project='$PROJECT_ID' --quiet" \
                        "Deleting build trigger: $trigger_id" true
                fi
            done <<< "$trigger_ids"
        else
            log_info "No build triggers found for repository: $REPO_NAME"
        fi
    else
        log_info "DRY RUN: Would delete build triggers for repository: $REPO_NAME"
    fi

    log_success "Build triggers cleanup completed"
}

# Delete source repository
delete_source_repository() {
    log_info "Removing Cloud Source Repository..."

    if [[ -n "$REPO_NAME" ]]; then
        execute_command "gcloud source repos delete '$REPO_NAME' --project='$PROJECT_ID' --quiet" \
            "Deleting source repository: $REPO_NAME" true
    else
        log_warning "Repository name not specified, skipping repository deletion"
    fi

    log_success "Source repository cleanup completed"
}

# Delete Firebase apps
delete_firebase_apps() {
    log_info "Removing Firebase applications..."

    if [[ "$DRY_RUN" != "true" ]]; then
        # List and delete Android apps with matching display name
        if [[ -n "$APP_NAME" ]]; then
            local app_ids
            app_ids=$(gcloud firebase apps list \
                --format="value(appId)" \
                --filter="displayName:'$APP_NAME Android'" \
                --project="$PROJECT_ID" 2>/dev/null || echo "")
            
            if [[ -n "$app_ids" ]]; then
                while IFS= read -r app_id; do
                    if [[ -n "$app_id" ]]; then
                        log_warning "Firebase apps cannot be deleted directly through CLI"
                        log_info "Please manually delete app '$app_id' in Firebase console: https://console.firebase.google.com/project/$FIREBASE_PROJECT_ID/settings/general"
                    fi
                done <<< "$app_ids"
            else
                log_info "No Firebase apps found with name: $APP_NAME Android"
            fi
        else
            log_info "App name not specified, skipping Firebase app deletion"
        fi
    else
        log_info "DRY RUN: Would attempt to delete Firebase apps for: $APP_NAME"
    fi

    log_success "Firebase apps cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."

    local files_to_remove=(
        "$PROJECT_DIR/.env"
        "$PROJECT_DIR/deployment-info.txt"
        "$PROJECT_DIR/mobile-app"
    )

    if [[ "$DRY_RUN" == "true" ]]; then
        for file in "${files_to_remove[@]}"; do
            if [[ -e "$file" ]]; then
                log_info "DRY RUN: Would remove $file"
            fi
        done
        return 0
    fi

    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            if [[ -d "$file" ]]; then
                rm -rf "$file"
                log_success "Removed directory: $file"
            else
                rm -f "$file"
                log_success "Removed file: $file"
            fi
        fi
    done

    log_success "Local files cleanup completed"
}

# Delete entire project (dangerous operation)
delete_entire_project() {
    log_warning "DELETING ENTIRE PROJECT: $PROJECT_ID"
    log_warning "This will remove ALL resources in the project, not just recipe resources!"
    
    confirm_operation "This will PERMANENTLY DELETE the project '$PROJECT_ID' and ALL its resources!"

    execute_command "gcloud projects delete '$PROJECT_ID' --quiet" \
        "Deleting project: $PROJECT_ID"

    log_warning "Project deletion initiated. It may take several minutes to complete."
    log_info "All local configuration files will also be removed."
    
    cleanup_local_files
    
    log_success "Project deletion completed!"
    exit 0
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Skipping verification"
        return 0
    fi

    local verification_failed=false

    # Check for remaining build triggers
    local remaining_triggers
    remaining_triggers=$(gcloud builds triggers list \
        --format="value(id)" \
        --filter="github.name:'$REPO_NAME' OR cloudSourceRepo.repoName:'$REPO_NAME'" \
        --project="$PROJECT_ID" 2>/dev/null | wc -l || echo "0")
    
    if [[ "$remaining_triggers" -gt 0 ]]; then
        log_warning "$remaining_triggers build trigger(s) still exist"
        verification_failed=true
    fi

    # Check for remaining source repositories
    if [[ -n "$REPO_NAME" ]]; then
        if gcloud source repos describe "$REPO_NAME" --project="$PROJECT_ID" &>/dev/null; then
            log_warning "Source repository '$REPO_NAME' still exists"
            verification_failed=true
        fi
    fi

    if [[ "$verification_failed" == "true" ]]; then
        log_warning "Some resources may still exist. Check the Firebase and Cloud consoles manually."
    else
        log_success "Cleanup verification completed successfully"
    fi
}

# Print cleanup summary
print_summary() {
    log_success "Cross-Platform Mobile Development Workflows cleanup completed!"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        log_info "DRY RUN SUMMARY - No actual resources were removed"
        echo ""
        echo "Resources that would be removed:"
        echo "  ✓ Build triggers for repository: ${REPO_NAME:-'unknown'}"
        echo "  ✓ Source repository: ${REPO_NAME:-'unknown'}"
        echo "  ✓ Firebase App Distribution tester groups"
        echo "  ✓ Local configuration files"
        echo ""
        log_info "Firebase apps would need manual deletion from console"
        log_info "Run without --dry-run to actually remove resources"
        return 0
    fi

    echo ""
    echo "Cleanup Summary:"
    echo "================"
    echo "Project ID: $PROJECT_ID"
    echo "Repository: ${REPO_NAME:-'not specified'}"
    echo "App Name: ${APP_NAME:-'not specified'}"
    echo ""
    echo "Removed Resources:"
    echo "✓ Cloud Build triggers"
    echo "✓ Cloud Source Repository"
    echo "✓ Firebase App Distribution tester groups"
    echo "✓ Local configuration files"
    echo ""
    echo "Manual Cleanup Required:"
    echo "- Firebase apps (delete from console if needed)"
    echo "- Firebase project (delete from console if desired)"
    echo ""
    echo "Consoles:"
    echo "- Google Cloud: https://console.cloud.google.com/home/dashboard?project=$PROJECT_ID"
    echo "- Firebase: https://console.firebase.google.com/project/$FIREBASE_PROJECT_ID"
    echo ""
    log_success "Cleanup completed successfully!"
}

# Main cleanup function
main() {
    log_info "Starting Cross-Platform Mobile Development Workflows cleanup..."
    
    # Initialize log file
    echo "Cross-Platform Mobile Development Workflows Cleanup Log" > "$CLEANUP_LOG"
    echo "Started: $(date)" >> "$CLEANUP_LOG"
    echo "Project: $PROJECT_ID" >> "$CLEANUP_LOG"
    echo "========================================" >> "$CLEANUP_LOG"

    parse_args "$@"
    check_prerequisites

    # Show what will be removed
    echo ""
    log_info "Cleanup Plan:"
    echo "=============="
    echo "Project: $PROJECT_ID"
    echo "Repository: ${REPO_NAME:-'not specified'}"
    echo "App Name: ${APP_NAME:-'not specified'}"
    echo "Firebase Project: $FIREBASE_PROJECT_ID"
    echo ""
    echo "Resources to remove:"
    echo "- Cloud Build triggers"
    echo "- Cloud Source Repository"
    echo "- Firebase App Distribution tester groups"
    echo "- Local configuration files"
    echo ""

    confirm_operation "This will remove the Cross-Platform Mobile Development Workflows resources listed above."

    # Perform cleanup operations
    delete_tester_groups
    delete_build_triggers
    delete_source_repository
    delete_firebase_apps
    cleanup_local_files
    verify_cleanup
    print_summary

    log_success "Cleanup completed successfully!"
}

# Run main function with all arguments
main "$@"