#!/bin/bash

# Interview Practice Assistant using Gemini and Speech-to-Text - Cleanup Script
# This script safely removes all infrastructure created for the interview practice assistant
# on Google Cloud Platform, including Cloud Functions, Storage, IAM resources, and projects

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Configuration variables (can be overridden by environment variables)
DRY_RUN="${DRY_RUN:-false}"
FORCE_DELETE="${FORCE_DELETE:-false}"
KEEP_PROJECT="${KEEP_PROJECT:-false}"
INTERACTIVE="${INTERACTIVE:-true}"

# Default resource patterns
DEFAULT_FUNCTION_PREFIX="interview-assistant"
DEFAULT_BUCKET_PATTERN="interview-audio-*"
DEFAULT_SERVICE_ACCOUNT_NAME="interview-assistant"

# Override patterns if provided
FUNCTION_PREFIX="${FUNCTION_PREFIX:-$DEFAULT_FUNCTION_PREFIX}"
BUCKET_PATTERN="${BUCKET_PATTERN:-$DEFAULT_BUCKET_PATTERN}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-$DEFAULT_SERVICE_ACCOUNT_NAME}"

# Function to display help
show_help() {
    cat << EOF
Interview Practice Assistant Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run           Show what would be deleted without making changes
    -f, --force             Skip confirmation prompts (dangerous!)
    -k, --keep-project      Keep the project but delete all resources within it
    -n, --non-interactive   Run without interactive prompts
    -p, --project-id        Specific project ID to clean up
    -r, --region            Region to search for resources (default: current gcloud config)

ENVIRONMENT VARIABLES:
    PROJECT_ID              Specific project to clean up
    REGION                  Region to search for resources
    DRY_RUN                 Set to 'true' for dry run
    FORCE_DELETE            Set to 'true' to skip confirmations
    KEEP_PROJECT            Set to 'true' to preserve project
    INTERACTIVE             Set to 'false' for non-interactive mode
    FUNCTION_PREFIX         Function name prefix pattern
    BUCKET_PATTERN          Storage bucket name pattern
    SERVICE_ACCOUNT_NAME    Service account name pattern

EXAMPLES:
    $0                                          # Interactive cleanup
    $0 --dry-run                               # Show what would be deleted
    $0 --force --keep-project                  # Delete resources but keep project
    PROJECT_ID=my-project-123 $0               # Clean specific project
    $0 --non-interactive --force               # Automated cleanup (dangerous!)

WARNING:
    This script will permanently delete cloud resources and data.
    Always run with --dry-run first to review what will be deleted.

EOF
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not available."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log "Prerequisites check completed"
}

# Function to get current project info
get_project_info() {
    # Get current project if not specified
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$PROJECT_ID" ]]; then
            error "No project specified and no active project configured"
            error "Set PROJECT_ID environment variable or run: gcloud config set project YOUR_PROJECT_ID"
            exit 1
        fi
    fi
    
    # Get current region if not specified
    if [[ -z "${REGION:-}" ]]; then
        REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
    fi
    
    # Verify project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        error "Project '$PROJECT_ID' not found or not accessible"
        exit 1
    fi
    
    info "Target project: $PROJECT_ID"
    info "Target region: $REGION"
}

# Function to discover resources
discover_resources() {
    log "Discovering Interview Practice Assistant resources..."
    
    # Discover Cloud Functions
    FUNCTIONS=($(gcloud functions list \
        --filter="name:${FUNCTION_PREFIX}" \
        --format="value(name)" 2>/dev/null || true))
    
    # Discover Storage Buckets
    BUCKETS=($(gsutil ls -p "$PROJECT_ID" 2>/dev/null | \
        grep -E "gs://${BUCKET_PATTERN}/" | \
        sed 's|gs://||' | sed 's|/$||' || true))
    
    # Discover Service Accounts
    SERVICE_ACCOUNTS=($(gcloud iam service-accounts list \
        --filter="displayName:${SERVICE_ACCOUNT_NAME}" \
        --format="value(email)" 2>/dev/null || true))
    
    # Also try to find by email pattern
    if [[ ${#SERVICE_ACCOUNTS[@]} -eq 0 ]]; then
        SERVICE_ACCOUNTS=($(gcloud iam service-accounts list \
            --filter="email:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --format="value(email)" 2>/dev/null || true))
    fi
    
    # Display discovered resources
    info "Discovered resources in project '$PROJECT_ID':"
    echo ""
    
    if [[ ${#FUNCTIONS[@]} -gt 0 ]]; then
        info "Cloud Functions (${#FUNCTIONS[@]}):"
        for func in "${FUNCTIONS[@]}"; do
            echo "  • $func"
        done
        echo ""
    fi
    
    if [[ ${#BUCKETS[@]} -gt 0 ]]; then
        info "Storage Buckets (${#BUCKETS[@]}):"
        for bucket in "${BUCKETS[@]}"; do
            echo "  • gs://$bucket"
        done
        echo ""
    fi
    
    if [[ ${#SERVICE_ACCOUNTS[@]} -gt 0 ]]; then
        info "Service Accounts (${#SERVICE_ACCOUNTS[@]}):"
        for sa in "${SERVICE_ACCOUNTS[@]}"; do
            echo "  • $sa"
        done
        echo ""
    fi
    
    local total_resources=$((${#FUNCTIONS[@]} + ${#BUCKETS[@]} + ${#SERVICE_ACCOUNTS[@]}))
    
    if [[ $total_resources -eq 0 ]]; then
        warn "No Interview Practice Assistant resources found in project '$PROJECT_ID'"
        warn "This could mean:"
        warn "  • Resources were already deleted"
        warn "  • Resources were created with different naming patterns"
        warn "  • You're targeting the wrong project"
        return 1
    fi
    
    info "Total resources found: $total_resources"
    return 0
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$INTERACTIVE" == "false" ]] || [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    warn "This will permanently delete the following resources:"
    echo ""
    
    # Show what will be deleted
    if [[ ${#FUNCTIONS[@]} -gt 0 ]]; then
        echo "  🔧 Cloud Functions:"
        for func in "${FUNCTIONS[@]}"; do
            echo "     • $func"
        done
        echo ""
    fi
    
    if [[ ${#BUCKETS[@]} -gt 0 ]]; then
        echo "  🗄️  Storage Buckets (including all data):"
        for bucket in "${BUCKETS[@]}"; do
            echo "     • gs://$bucket"
        done
        echo ""
    fi
    
    if [[ ${#SERVICE_ACCOUNTS[@]} -gt 0 ]]; then
        echo "  🔐 Service Accounts:"
        for sa in "${SERVICE_ACCOUNTS[@]}"; do
            echo "     • $sa"
        done
        echo ""
    fi
    
    if [[ "$KEEP_PROJECT" == "false" ]]; then
        echo "  🏗️  Project:"
        echo "     • $PROJECT_ID (ENTIRE PROJECT WILL BE DELETED)"
        echo ""
    fi
    
    echo "💰 This will stop all billing for these resources."
    echo "📝 This action cannot be undone!"
    echo ""
    
    read -p "Are you absolutely sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
    
    echo ""
    log "Confirmation received. Proceeding with deletion..."
}

# Function to delete Cloud Functions
delete_functions() {
    if [[ ${#FUNCTIONS[@]} -eq 0 ]]; then
        info "No Cloud Functions to delete"
        return 0
    fi
    
    log "Deleting Cloud Functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        for func in "${FUNCTIONS[@]}"; do
            info "[DRY RUN] Would delete function: $func"
        done
        return 0
    fi
    
    local success_count=0
    for func in "${FUNCTIONS[@]}"; do
        log "Deleting function: $func"
        if gcloud functions delete "$func" \
            --region="$REGION" \
            --quiet 2>/dev/null; then
            log "✅ Deleted function: $func"
            ((success_count++))
        else
            error "Failed to delete function: $func"
        fi
    done
    
    log "Deleted $success_count of ${#FUNCTIONS[@]} functions"
    
    # Wait for functions to be fully deleted
    if [[ $success_count -gt 0 ]]; then
        log "Waiting for function deletion to complete..."
        sleep 10
    fi
}

# Function to delete Storage Buckets
delete_buckets() {
    if [[ ${#BUCKETS[@]} -eq 0 ]]; then
        info "No Storage Buckets to delete"
        return 0
    fi
    
    log "Deleting Storage Buckets..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        for bucket in "${BUCKETS[@]}"; do
            info "[DRY RUN] Would delete bucket and all contents: gs://$bucket"
        done
        return 0
    fi
    
    local success_count=0
    for bucket in "${BUCKETS[@]}"; do
        log "Deleting bucket and all contents: gs://$bucket"
        
        # First, delete all objects in the bucket (including versions)
        if gsutil -m rm -r "gs://$bucket/**" 2>/dev/null || true; then
            log "Deleted all objects from bucket: $bucket"
        fi
        
        # Then delete the bucket itself
        if gsutil rb "gs://$bucket" 2>/dev/null; then
            log "✅ Deleted bucket: gs://$bucket"
            ((success_count++))
        else
            error "Failed to delete bucket: gs://$bucket"
        fi
    done
    
    log "Deleted $success_count of ${#BUCKETS[@]} buckets"
}

# Function to delete Service Accounts
delete_service_accounts() {
    if [[ ${#SERVICE_ACCOUNTS[@]} -eq 0 ]]; then
        info "No Service Accounts to delete"
        return 0
    fi
    
    log "Deleting Service Accounts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        for sa in "${SERVICE_ACCOUNTS[@]}"; do
            info "[DRY RUN] Would delete service account: $sa"
        done
        return 0
    fi
    
    local success_count=0
    for sa in "${SERVICE_ACCOUNTS[@]}"; do
        log "Deleting service account: $sa"
        if gcloud iam service-accounts delete "$sa" \
            --quiet 2>/dev/null; then
            log "✅ Deleted service account: $sa"
            ((success_count++))
        else
            error "Failed to delete service account: $sa"
        fi
    done
    
    log "Deleted $success_count of ${#SERVICE_ACCOUNTS[@]} service accounts"
}

# Function to delete project
delete_project() {
    if [[ "$KEEP_PROJECT" == "true" ]]; then
        info "Keeping project as requested: $PROJECT_ID"
        return 0
    fi
    
    log "Deleting project: $PROJECT_ID"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete entire project: $PROJECT_ID"
        return 0
    fi
    
    # Additional confirmation for project deletion
    if [[ "$INTERACTIVE" == "true" ]] && [[ "$FORCE_DELETE" == "false" ]]; then
        echo ""
        warn "🚨 FINAL WARNING: About to delete ENTIRE PROJECT 🚨"
        warn "Project: $PROJECT_ID"
        warn "This will delete ALL resources in the project, not just Interview Practice Assistant resources!"
        echo ""
        read -p "Type the project ID to confirm deletion: " project_confirmation
        
        if [[ "$project_confirmation" != "$PROJECT_ID" ]]; then
            log "Project ID confirmation failed. Keeping project."
            return 0
        fi
    fi
    
    if gcloud projects delete "$PROJECT_ID" --quiet 2>/dev/null; then
        log "✅ Project deletion initiated: $PROJECT_ID"
        log "Project deletion may take several minutes to complete"
    else
        error "Failed to delete project: $PROJECT_ID"
        error "You may need to delete it manually from the Cloud Console"
    fi
}

# Function to clean up local artifacts
cleanup_local_artifacts() {
    log "Cleaning up local artifacts..."
    
    local cleanup_items=(
        "/tmp/lifecycle.json"
        "/tmp/interview_questions.json"
        "/tmp/interview-functions-*"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would clean up temporary files and directories"
        return 0
    fi
    
    for item in "${cleanup_items[@]}"; do
        if [[ -e "$item" ]]; then
            rm -rf "$item" 2>/dev/null || true
            log "Cleaned up: $item"
        fi
    done
    
    log "Local cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]] || [[ "$KEEP_PROJECT" == "false" ]]; then
        info "Skipping cleanup verification (dry run or project deleted)"
        return 0
    fi
    
    log "Verifying cleanup completion..."
    
    # Check if any functions remain
    local remaining_functions
    remaining_functions=$(gcloud functions list \
        --filter="name:${FUNCTION_PREFIX}" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    # Check if any buckets remain
    local remaining_buckets
    remaining_buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | \
        grep -E "gs://${BUCKET_PATTERN}/" | wc -l || echo "0")
    
    # Check if any service accounts remain
    local remaining_service_accounts
    remaining_service_accounts=$(gcloud iam service-accounts list \
        --filter="displayName:${SERVICE_ACCOUNT_NAME}" \
        --format="value(email)" 2>/dev/null | wc -l)
    
    local total_remaining=$((remaining_functions + remaining_buckets + remaining_service_accounts))
    
    if [[ $total_remaining -eq 0 ]]; then
        log "✅ Cleanup verification successful - no resources remaining"
        return 0
    else
        warn "Some resources may still exist:"
        [[ $remaining_functions -gt 0 ]] && warn "  • Functions: $remaining_functions"
        [[ $remaining_buckets -gt 0 ]] && warn "  • Buckets: $remaining_buckets"
        [[ $remaining_service_accounts -gt 0 ]] && warn "  • Service Accounts: $remaining_service_accounts"
        warn "These may be deleted eventually due to eventual consistency"
        return 1
    fi
}

# Function to display cleanup summary
show_summary() {
    log "Cleanup Summary"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "This was a DRY RUN - no actual resources were deleted"
        warn "Run without --dry-run to perform actual cleanup"
    else
        info "Cleanup completed for project: $PROJECT_ID"
        
        if [[ "$KEEP_PROJECT" == "false" ]]; then
            info "Project deletion initiated - may take several minutes to complete"
        else
            info "Project preserved, only Interview Practice Assistant resources deleted"
        fi
        
        info "All associated billing has been stopped"
    fi
    
    echo ""
    info "What was processed:"
    info "  • Cloud Functions: ${#FUNCTIONS[@]} found"
    info "  • Storage Buckets: ${#BUCKETS[@]} found"
    info "  • Service Accounts: ${#SERVICE_ACCOUNTS[@]} found"
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        info "💰 Cost Impact: All Interview Practice Assistant charges have stopped"
        info "🔒 Security: All related IAM permissions have been removed"
        info "📊 Data: All stored interview data has been permanently deleted"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to handle script interruption
cleanup_on_interrupt() {
    error "Cleanup interrupted by user"
    warn "Some resources may have been partially deleted"
    warn "Re-run the script to complete cleanup"
    exit 130
}

# Main cleanup function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -f|--force)
                FORCE_DELETE="true"
                shift
                ;;
            -k|--keep-project)
                KEEP_PROJECT="true"
                shift
                ;;
            -n|--non-interactive)
                INTERACTIVE="false"
                shift
                ;;
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Set up interrupt handler
    trap cleanup_on_interrupt SIGINT SIGTERM
    
    # Display banner
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│                     Interview Practice Assistant Cleanup                    │"
    echo "│                           Google Cloud Platform                             │"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN MODE - No resources will be deleted"
    fi
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        warn "FORCE MODE - Skipping confirmation prompts"
    fi
    echo ""
    
    # Execute cleanup steps
    check_prerequisites
    get_project_info
    
    if discover_resources; then
        confirm_deletion
        delete_functions
        delete_buckets
        delete_service_accounts
        cleanup_local_artifacts
        delete_project
        
        if verify_cleanup; then
            show_summary
            log "🎉 Interview Practice Assistant cleanup completed successfully!"
        else
            show_summary
            warn "Cleanup completed with some remaining resources (may be eventual consistency)"
        fi
    else
        show_summary
        log "No Interview Practice Assistant resources found to clean up"
    fi
}

# Run main function
main "$@"