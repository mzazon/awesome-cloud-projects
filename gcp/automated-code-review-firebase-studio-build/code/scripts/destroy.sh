#!/bin/bash

# Automated Code Review Pipeline Cleanup Script
# This script removes all resources created by the automated code review pipeline
# WARNING: This script will permanently delete all resources and data

set -euo pipefail

# Color codes for output formatting
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

# Check if script is run with -h or --help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<EOF
Automated Code Review Pipeline Cleanup Script

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deleted without making changes
    -p, --project       Specify GCP project ID (overrides current project)
    -f, --force         Skip confirmation prompts (USE WITH CAUTION)
    --keep-storage      Keep storage buckets and their contents
    --keep-repos        Keep source repositories
    --resources-only    Delete only cloud resources, keep source code

Environment Variables:
    PROJECT_ID          GCP Project ID (required if not set via gcloud config)

Examples:
    $0                              # Interactive cleanup with confirmations
    $0 --dry-run                    # Preview what would be deleted
    $0 --force                      # Delete everything without prompts
    $0 --keep-storage --keep-repos  # Delete only compute resources
    $0 --resources-only             # Keep repositories but delete cloud resources

WARNING: This script will permanently delete resources and data.
         Use --dry-run first to preview changes.
EOF
    exit 0
fi

# Parse command line arguments
DRY_RUN=false
FORCE=false
KEEP_STORAGE=false
KEEP_REPOS=false
RESOURCES_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -p|--project)
            PROJECT_ID="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        --keep-storage)
            KEEP_STORAGE=true
            shift
            ;;
        --keep-repos)
            KEEP_REPOS=true
            shift
            ;;
        --resources-only)
            RESOURCES_ONLY=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set default values
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo '')}"

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
    log_error "PROJECT_ID must be set via environment variable, --project flag, or gcloud config"
    exit 1
fi

log_info "Starting cleanup for project: $PROJECT_ID"

if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY RUN MODE - No changes will be made"
fi

if [[ "$FORCE" == "true" ]]; then
    log_warning "FORCE MODE - Skipping confirmation prompts"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    log_info "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "    Would execute: $cmd"
    else
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" 2>/dev/null || log_warning "Command failed (ignoring): $cmd"
        else
            eval "$cmd"
        fi
    fi
}

# Function to confirm destructive actions
confirm_action() {
    local message="$1"
    
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}$message${NC}"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled"
        return 1
    fi
    return 0
}

# Function to discover resources by pattern matching
discover_resources() {
    log_info "Discovering automated code review resources..."
    
    # Discover Cloud Build triggers
    TRIGGERS=$(gcloud builds triggers list --format="value(name)" --filter="name~'code-review.*trigger'" 2>/dev/null || echo "")
    
    # Discover Cloud Functions
    FUNCTIONS=$(gcloud functions list --format="csv[no-heading](name,region)" --filter="name~'code-review'" 2>/dev/null | tr ',' ' ' || echo "")
    
    # Discover Cloud Tasks queues
    QUEUES=$(gcloud tasks queues list --format="csv[no-heading](name)" --filter="name~'code-review'" 2>/dev/null || echo "")
    
    # Discover Cloud Source Repositories
    REPOSITORIES=$(gcloud source repos list --format="value(name)" --filter="name~'code-review'" 2>/dev/null || echo "")
    
    # Discover Cloud Storage buckets
    BUCKETS=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -E "(code-review|build-artifacts)" | sed 's/gs:\/\///g' | sed 's/\///g' || echo "")
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Discovered resources:"
        echo "  Triggers: ${TRIGGERS:-none}"
        echo "  Functions: ${FUNCTIONS:-none}"
        echo "  Queues: ${QUEUES:-none}"
        echo "  Repositories: ${REPOSITORIES:-none}"
        echo "  Buckets: ${BUCKETS:-none}"
    fi
}

# Function to delete Cloud Build triggers
delete_build_triggers() {
    if [[ -z "$TRIGGERS" ]]; then
        log_info "No Cloud Build triggers found"
        return 0
    fi
    
    if ! confirm_action "This will delete Cloud Build triggers: $TRIGGERS"; then
        return 0
    fi
    
    log_info "Deleting Cloud Build triggers..."
    
    for trigger in $TRIGGERS; do
        execute_command "gcloud builds triggers delete $trigger --quiet" "Deleting trigger: $trigger" true
    done
    
    # Verify deletion
    if [[ "$DRY_RUN" == "false" ]]; then
        local remaining_triggers
        remaining_triggers=$(gcloud builds triggers list --format="value(name)" --filter="name~'code-review.*trigger'" 2>/dev/null || echo "")
        if [[ -z "$remaining_triggers" ]]; then
            log_success "All Cloud Build triggers deleted"
        else
            log_warning "Some triggers may still exist: $remaining_triggers"
        fi
    fi
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    if [[ -z "$FUNCTIONS" ]]; then
        log_info "No Cloud Functions found"
        return 0
    fi
    
    if ! confirm_action "This will delete Cloud Functions: $FUNCTIONS"; then
        return 0
    fi
    
    log_info "Deleting Cloud Functions..."
    
    echo "$FUNCTIONS" | while read -r function_name region; do
        if [[ -n "$function_name" && -n "$region" ]]; then
            execute_command "gcloud functions delete $function_name --region=$region --quiet" "Deleting function: $function_name in $region" true
        fi
    done
    
    # Verify deletion
    if [[ "$DRY_RUN" == "false" ]]; then
        sleep 5  # Allow time for deletion to propagate
        local remaining_functions
        remaining_functions=$(gcloud functions list --format="value(name)" --filter="name~'code-review'" 2>/dev/null || echo "")
        if [[ -z "$remaining_functions" ]]; then
            log_success "All Cloud Functions deleted"
        else
            log_warning "Some functions may still exist: $remaining_functions"
        fi
    fi
}

# Function to delete Cloud Tasks queues
delete_cloud_tasks_queues() {
    if [[ -z "$QUEUES" ]]; then
        log_info "No Cloud Tasks queues found"
        return 0
    fi
    
    if ! confirm_action "This will delete Cloud Tasks queues: $QUEUES"; then
        return 0
    fi
    
    log_info "Deleting Cloud Tasks queues..."
    
    for queue in $QUEUES; do
        # Extract location from queue name (format: projects/PROJECT/locations/LOCATION/queues/NAME)
        local location
        location=$(echo "$queue" | sed -n 's/.*\/locations\/\([^\/]*\)\/.*/\1/p')
        local queue_name
        queue_name=$(echo "$queue" | sed -n 's/.*\/queues\/\(.*\)/\1/p')
        
        if [[ -n "$location" && -n "$queue_name" ]]; then
            execute_command "gcloud tasks queues delete $queue_name --location=$location --quiet" "Deleting queue: $queue_name in $location" true
        else
            log_warning "Could not parse queue name: $queue"
        fi
    done
    
    # Verify deletion
    if [[ "$DRY_RUN" == "false" ]]; then
        local remaining_queues
        remaining_queues=$(gcloud tasks queues list --format="value(name)" --filter="name~'code-review'" 2>/dev/null || echo "")
        if [[ -z "$remaining_queues" ]]; then
            log_success "All Cloud Tasks queues deleted"
        else
            log_warning "Some queues may still exist: $remaining_queues"
        fi
    fi
}

# Function to delete Cloud Source Repositories
delete_source_repositories() {
    if [[ "$KEEP_REPOS" == "true" ]]; then
        log_info "Skipping source repository deletion (--keep-repos specified)"
        return 0
    fi
    
    if [[ -z "$REPOSITORIES" ]]; then
        log_info "No Cloud Source Repositories found"
        return 0
    fi
    
    if ! confirm_action "This will permanently delete source repositories and all code: $REPOSITORIES"; then
        return 0
    fi
    
    log_info "Deleting Cloud Source Repositories..."
    
    for repo in $REPOSITORIES; do
        execute_command "gcloud source repos delete $repo --quiet" "Deleting repository: $repo" true
    done
    
    # Verify deletion
    if [[ "$DRY_RUN" == "false" ]]; then
        local remaining_repos
        remaining_repos=$(gcloud source repos list --format="value(name)" --filter="name~'code-review'" 2>/dev/null || echo "")
        if [[ -z "$remaining_repos" ]]; then
            log_success "All source repositories deleted"
        else
            log_warning "Some repositories may still exist: $remaining_repos"
        fi
    fi
}

# Function to delete Cloud Storage buckets
delete_storage_buckets() {
    if [[ "$KEEP_STORAGE" == "true" ]]; then
        log_info "Skipping storage bucket deletion (--keep-storage specified)"
        return 0
    fi
    
    if [[ -z "$BUCKETS" ]]; then
        log_info "No Cloud Storage buckets found"
        return 0
    fi
    
    if ! confirm_action "This will permanently delete storage buckets and all data: $BUCKETS"; then
        return 0
    fi
    
    log_info "Deleting Cloud Storage buckets..."
    
    for bucket in $BUCKETS; do
        # First, try to remove bucket contents
        execute_command "gsutil -m rm -r gs://$bucket/**" "Removing contents from bucket: $bucket" true
        
        # Then delete the bucket
        execute_command "gsutil rb gs://$bucket" "Deleting bucket: $bucket" true
    done
    
    # Verify deletion
    if [[ "$DRY_RUN" == "false" ]]; then
        local remaining_buckets
        remaining_buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -E "(code-review|build-artifacts)" | sed 's/gs:\/\///g' | sed 's/\///g' || echo "")
        if [[ -z "$remaining_buckets" ]]; then
            log_success "All storage buckets deleted"
        else
            log_warning "Some buckets may still exist: $remaining_buckets"
        fi
    fi
}

# Function to clean up IAM roles and permissions
cleanup_iam_permissions() {
    log_info "Cleaning up IAM permissions..."
    
    # Note: This function would clean up any custom IAM roles or service accounts
    # created specifically for the code review pipeline. Since the recipe uses
    # default service accounts, we'll just log this as a placeholder.
    
    log_info "No custom IAM resources to clean up (using default service accounts)"
}

# Function to clean up local temporary files
cleanup_local_files() {
    log_info "Cleaning up local temporary files..."
    
    # Remove any temporary files that might have been created
    local temp_patterns=(
        "/tmp/code-review-*"
        "/tmp/lifecycle.json"
        "./code-review-repo-*"
    )
    
    for pattern in "${temp_patterns[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "    Would remove: $pattern"
        else
            rm -rf $pattern 2>/dev/null || true
        fi
    done
    
    log_success "Local cleanup completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary"
    echo "==============="
    echo "Project ID: $PROJECT_ID"
    echo ""
    
    local resources_deleted=0
    
    if [[ -n "$TRIGGERS" ]]; then
        echo "✓ Cloud Build Triggers: $(echo "$TRIGGERS" | wc -w)"
        ((resources_deleted++))
    fi
    
    if [[ -n "$FUNCTIONS" ]]; then
        echo "✓ Cloud Functions: $(echo "$FUNCTIONS" | wc -l)"
        ((resources_deleted++))
    fi
    
    if [[ -n "$QUEUES" ]]; then
        echo "✓ Cloud Tasks Queues: $(echo "$QUEUES" | wc -w)"
        ((resources_deleted++))
    fi
    
    if [[ -n "$REPOSITORIES" && "$KEEP_REPOS" == "false" ]]; then
        echo "✓ Source Repositories: $(echo "$REPOSITORIES" | wc -w)"
        ((resources_deleted++))
    elif [[ "$KEEP_REPOS" == "true" ]]; then
        echo "- Source Repositories: Kept (--keep-repos)"
    fi
    
    if [[ -n "$BUCKETS" && "$KEEP_STORAGE" == "false" ]]; then
        echo "✓ Storage Buckets: $(echo "$BUCKETS" | wc -w)"
        ((resources_deleted++))
    elif [[ "$KEEP_STORAGE" == "true" ]]; then
        echo "- Storage Buckets: Kept (--keep-storage)"
    fi
    
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN completed - no changes were made"
        log_info "Run without --dry-run to execute the cleanup"
    else
        log_success "Cleanup completed! $resources_deleted resource types processed"
        
        if [[ "$KEEP_REPOS" == "true" || "$KEEP_STORAGE" == "true" ]]; then
            log_info "Some resources were preserved as requested"
        fi
        
        log_info "Billing Impact:"
        echo "- Compute resources (Functions, Tasks): Stopped billing immediately"
        echo "- Storage resources: Billing stopped after deletion propagates"
        echo "- Build history: Retained in Cloud Build console"
    fi
}

# Function to check for remaining resources
check_remaining_resources() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log_info "Checking for any remaining resources..."
    
    # Check for any remaining code-review related resources
    local remaining_triggers remaining_functions remaining_queues remaining_repos remaining_buckets
    
    remaining_triggers=$(gcloud builds triggers list --format="value(name)" --filter="name~'code-review'" 2>/dev/null || echo "")
    remaining_functions=$(gcloud functions list --format="value(name)" --filter="name~'code-review'" 2>/dev/null || echo "")
    remaining_queues=$(gcloud tasks queues list --format="value(name)" --filter="name~'code-review'" 2>/dev/null || echo "")
    remaining_repos=$(gcloud source repos list --format="value(name)" --filter="name~'code-review'" 2>/dev/null || echo "")
    remaining_buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -E "(code-review|build-artifacts)" || echo "")
    
    local has_remaining=false
    
    if [[ -n "$remaining_triggers" ]]; then
        log_warning "Remaining triggers: $remaining_triggers"
        has_remaining=true
    fi
    
    if [[ -n "$remaining_functions" ]]; then
        log_warning "Remaining functions: $remaining_functions"
        has_remaining=true
    fi
    
    if [[ -n "$remaining_queues" ]]; then
        log_warning "Remaining queues: $remaining_queues"
        has_remaining=true
    fi
    
    if [[ -n "$remaining_repos" ]]; then
        if [[ "$KEEP_REPOS" == "false" ]]; then
            log_warning "Remaining repositories: $remaining_repos"
            has_remaining=true
        else
            log_info "Repositories preserved as requested: $remaining_repos"
        fi
    fi
    
    if [[ -n "$remaining_buckets" ]]; then
        if [[ "$KEEP_STORAGE" == "false" ]]; then
            log_warning "Remaining buckets: $remaining_buckets"
            has_remaining=true
        else
            log_info "Buckets preserved as requested: $remaining_buckets"
        fi
    fi
    
    if [[ "$has_remaining" == "true" ]]; then
        log_warning "Some resources may require manual cleanup"
        log_info "You can run this script again or clean up manually using the gcloud/gsutil commands"
    else
        log_success "No remaining resources detected"
    fi
}

# Main execution flow
main() {
    log_info "Starting automated code review pipeline cleanup"
    
    # Show warning about destructive operation
    if [[ "$DRY_RUN" == "false" && "$FORCE" == "false" ]]; then
        echo ""
        log_warning "⚠️  WARNING: This will permanently delete cloud resources and data"
        log_warning "⚠️  Make sure you have backups of any important code or data"
        echo ""
        if ! confirm_action "Continue with cleanup?"; then
            log_info "Cleanup cancelled"
            exit 0
        fi
    fi
    
    # Discover all resources
    discover_resources
    
    # Delete resources in reverse order of creation
    delete_build_triggers
    delete_cloud_functions
    delete_cloud_tasks_queues
    
    if [[ "$RESOURCES_ONLY" == "false" ]]; then
        delete_source_repositories
        delete_storage_buckets
    else
        log_info "Skipping source code and storage deletion (--resources-only specified)"
    fi
    
    cleanup_iam_permissions
    cleanup_local_files
    check_remaining_resources
    display_cleanup_summary
}

# Execute main function with error handling
if main; then
    log_success "Cleanup process completed"
    exit 0
else
    log_error "Cleanup failed. Check the logs above for details."
    log_info "You may need to manually clean up some resources"
    exit 1
fi