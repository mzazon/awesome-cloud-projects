#!/bin/bash

# Smart Form Processing with Document AI and Gemini - Cleanup Script
# This script safely removes all resources created by the deployment script
# with proper dependency handling and confirmation prompts

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Script metadata
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CLEANUP_LOG="$PROJECT_ROOT/cleanup.log"

# Initialize logging
exec 1> >(tee -a "$CLEANUP_LOG")
exec 2>&1

log "Starting Smart Form Processing cleanup..."

# Configuration variables
DRY_RUN=${DRY_RUN:-false}
FORCE=${FORCE:-false}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}

# Resource tracking
CLEANUP_ERRORS=()

# Load deployment info if available
load_deployment_info() {
    local deployment_info="$PROJECT_ROOT/deployment-info.json"
    
    if [[ -f "$deployment_info" ]]; then
        log "Loading deployment information from: $deployment_info"
        
        # Extract values using jq if available, otherwise use grep/sed
        if command -v jq &> /dev/null; then
            PROJECT_ID=$(jq -r '.project_id // empty' "$deployment_info")
            REGION=$(jq -r '.region // empty' "$deployment_info")
            PROCESSOR_ID=$(jq -r '.processor_id // empty' "$deployment_info")
            BUCKET_INPUT=$(jq -r '.input_bucket // empty' "$deployment_info")
            BUCKET_OUTPUT=$(jq -r '.output_bucket // empty' "$deployment_info")
            RANDOM_SUFFIX=$(jq -r '.random_suffix // empty' "$deployment_info")
        else
            PROJECT_ID=$(grep -o '"project_id": "[^"]*"' "$deployment_info" | cut -d'"' -f4)
            REGION=$(grep -o '"region": "[^"]*"' "$deployment_info" | cut -d'"' -f4)
            PROCESSOR_ID=$(grep -o '"processor_id": "[^"]*"' "$deployment_info" | cut -d'"' -f4)
            BUCKET_INPUT=$(grep -o '"input_bucket": "[^"]*"' "$deployment_info" | cut -d'"' -f4)
            BUCKET_OUTPUT=$(grep -o '"output_bucket": "[^"]*"' "$deployment_info" | cut -d'"' -f4)
            RANDOM_SUFFIX=$(grep -o '"random_suffix": "[^"]*"' "$deployment_info" | cut -d'"' -f4)
        fi
        
        success "Loaded deployment information"
    else
        warning "No deployment-info.json found. Will attempt to discover resources."
    fi
    
    # Load from environment file if available
    local env_file="$PROJECT_ROOT/.env"
    if [[ -f "$env_file" ]]; then
        source "$env_file"
        log "Loaded environment variables from: $env_file"
    fi
}

# Discover resources function
discover_resources() {
    log "Discovering deployed resources..."
    
    # Set defaults if not loaded from deployment info
    PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"
    REGION="${REGION:-us-central1}"
    
    if [[ -z "$PROJECT_ID" ]]; then
        error "No project ID found. Please set PROJECT_ID environment variable or use --project-id"
    fi
    
    # Set project context
    gcloud config set project "$PROJECT_ID" --quiet
    
    # Discover buckets with smart-forms pattern
    if [[ -z "$BUCKET_INPUT" ]] || [[ -z "$BUCKET_OUTPUT" ]]; then
        log "Discovering storage buckets..."
        local buckets
        buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -E "(forms-input|forms-output)" || true)
        
        if [[ -n "$buckets" ]]; then
            BUCKET_INPUT=$(echo "$buckets" | grep "forms-input" | head -n1 | sed 's|gs://||' | sed 's|/||' || echo "")
            BUCKET_OUTPUT=$(echo "$buckets" | grep "forms-output" | head -n1 | sed 's|gs://||' | sed 's|/||' || echo "")
        fi
    fi
    
    # Discover Document AI processor
    if [[ -z "$PROCESSOR_ID" ]]; then
        log "Discovering Document AI processors..."
        PROCESSOR_ID=$(gcloud documentai processors list \
            --location="$REGION" \
            --filter="displayName:smart-form-processor*" \
            --format="value(name.segment(-1))" \
            --quiet 2>/dev/null | head -n1 || echo "")
    fi
    
    success "Resource discovery completed"
}

# Safety check function
safety_check() {
    log "Performing safety checks..."
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Run 'gcloud auth login' first."
    fi
    
    # Verify project access
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        error "Cannot access project: $PROJECT_ID. Check permissions."
    fi
    
    # Check for important resources that shouldn't be deleted
    local important_patterns=(
        "production"
        "prod"
        "critical"
        "backup"
    )
    
    for pattern in "${important_patterns[@]}"; do
        if [[ "$PROJECT_ID" =~ $pattern ]]; then
            warning "Project ID contains '$pattern' - extra caution required"
            if [[ "$FORCE" != "true" && "$SKIP_CONFIRMATION" != "true" ]]; then
                read -p "Are you ABSOLUTELY sure you want to delete resources in this project? (type 'DELETE' to confirm): " -r
                if [[ "$REPLY" != "DELETE" ]]; then
                    log "Cleanup cancelled for safety"
                    exit 0
                fi
            fi
            break
        fi
    done
    
    success "Safety checks completed"
}

# Delete Cloud Function
delete_cloud_function() {
    log "Deleting Cloud Function..."
    
    local function_name="process-form"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete Cloud Function: $function_name"
        return
    fi
    
    # Check if function exists
    if gcloud functions describe "$function_name" --region="$REGION" &>/dev/null; then
        log "Deleting Cloud Function: $function_name"
        if gcloud functions delete "$function_name" --region="$REGION" --quiet; then
            success "Cloud Function deleted: $function_name"
        else
            error_msg="Failed to delete Cloud Function: $function_name"
            error "$error_msg"
            CLEANUP_ERRORS+=("$error_msg")
        fi
    else
        log "Cloud Function not found: $function_name (may already be deleted)"
    fi
    
    # Clean up function source directory
    local function_dir="$PROJECT_ROOT/function-source"
    if [[ -d "$function_dir" ]]; then
        log "Removing function source directory..."
        rm -rf "$function_dir"
        success "Function source directory removed"
    fi
}

# Delete Document AI processor
delete_documentai_processor() {
    log "Deleting Document AI processor..."
    
    if [[ -z "$PROCESSOR_ID" ]]; then
        log "No Document AI processor ID found - skipping"
        return
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete Document AI processor: $PROCESSOR_ID"
        return
    fi
    
    # Check if processor exists
    if gcloud documentai processors describe "$PROCESSOR_ID" --location="$REGION" &>/dev/null; then
        log "Deleting Document AI processor: $PROCESSOR_ID"
        if gcloud documentai processors delete "$PROCESSOR_ID" --location="$REGION" --quiet; then
            success "Document AI processor deleted: $PROCESSOR_ID"
        else
            error_msg="Failed to delete Document AI processor: $PROCESSOR_ID"
            error "$error_msg"
            CLEANUP_ERRORS+=("$error_msg")
        fi
    else
        log "Document AI processor not found: $PROCESSOR_ID (may already be deleted)"
    fi
}

# Delete storage buckets
delete_storage_buckets() {
    log "Deleting Cloud Storage buckets..."
    
    local buckets_to_delete=()
    
    if [[ -n "$BUCKET_INPUT" ]]; then
        buckets_to_delete+=("$BUCKET_INPUT")
    fi
    
    if [[ -n "$BUCKET_OUTPUT" ]]; then
        buckets_to_delete+=("$BUCKET_OUTPUT")
    fi
    
    if [[ ${#buckets_to_delete[@]} -eq 0 ]]; then
        log "No storage buckets found - skipping"
        return
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete buckets: ${buckets_to_delete[*]}"
        return
    fi
    
    for bucket in "${buckets_to_delete[@]}"; do
        if gsutil ls "gs://$bucket" &>/dev/null; then
            log "Deleting bucket and contents: $bucket"
            
            # Force delete bucket and all contents
            if gsutil -m rm -rf "gs://$bucket"; then
                success "Bucket deleted: $bucket"
            else
                error_msg="Failed to delete bucket: $bucket"
                error "$error_msg"
                CLEANUP_ERRORS+=("$error_msg")
            fi
        else
            log "Bucket not found: $bucket (may already be deleted)"
        fi
    done
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "$PROJECT_ROOT/deployment-info.json"
        "$PROJECT_ROOT/.env"
        "$PROJECT_ROOT/sample_form.txt"
        "$PROJECT_ROOT/sample_employee_form_results.json"
        "$PROJECT_ROOT/deployment.log"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove local files: ${files_to_remove[*]}"
        return
    fi
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            log "Removing file: $file"
            rm -f "$file"
        fi
    done
    
    success "Local files cleaned up"
}

# List remaining resources
list_remaining_resources() {
    log "Checking for remaining resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would check for remaining resources"
        return
    fi
    
    local remaining_found=false
    
    # Check for remaining functions
    local functions
    functions=$(gcloud functions list --regions="$REGION" --filter="name:*process-form*" --format="value(name)" 2>/dev/null || true)
    if [[ -n "$functions" ]]; then
        warning "Remaining Cloud Functions found: $functions"
        remaining_found=true
    fi
    
    # Check for remaining processors
    local processors
    processors=$(gcloud documentai processors list --location="$REGION" --filter="displayName:*smart-form-processor*" --format="value(name)" 2>/dev/null || true)
    if [[ -n "$processors" ]]; then
        warning "Remaining Document AI processors found: $processors"
        remaining_found=true
    fi
    
    # Check for remaining buckets
    local buckets
    buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -E "(forms-input|forms-output)" || true)
    if [[ -n "$buckets" ]]; then
        warning "Remaining storage buckets found: $buckets"
        remaining_found=true
    fi
    
    if [[ "$remaining_found" == "false" ]]; then
        success "No remaining resources found"
    else
        warning "Some resources may require manual cleanup"
    fi
}

# Generate cleanup report
generate_cleanup_report() {
    log "Generating cleanup report..."
    
    local report_file="$PROJECT_ROOT/cleanup-report.txt"
    
    cat > "$report_file" << EOF
Smart Form Processing Cleanup Report
Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

Project: $PROJECT_ID
Region: $REGION

Resources Processed:
- Cloud Function: process-form
- Document AI Processor: ${PROCESSOR_ID:-"Not found"}
- Input Bucket: ${BUCKET_INPUT:-"Not found"}  
- Output Bucket: ${BUCKET_OUTPUT:-"Not found"}

Cleanup Status: $([[ ${#CLEANUP_ERRORS[@]} -eq 0 ]] && echo "SUCCESS" || echo "PARTIAL")

EOF

    if [[ ${#CLEANUP_ERRORS[@]} -gt 0 ]]; then
        echo "Errors Encountered:" >> "$report_file"
        for error in "${CLEANUP_ERRORS[@]}"; do
            echo "- $error" >> "$report_file"
        done
        echo >> "$report_file"
    fi
    
    echo "Manual Cleanup Steps (if needed):" >> "$report_file"
    echo "1. Check Google Cloud Console for any remaining resources" >> "$report_file"
    echo "2. Verify billing is disabled if project is no longer needed" >> "$report_file"
    echo "3. Review IAM permissions and service accounts" >> "$report_file"
    echo "4. Check Cloud Logging for any remaining log entries" >> "$report_file"
    
    success "Cleanup report saved to: $report_file"
}

# Main cleanup function
main() {
    log "Smart Form Processing Cleanup Started"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN MODE - No resources will be deleted"
    fi
    
    # Load deployment information
    load_deployment_info
    discover_resources
    
    # Display what will be cleaned up
    echo
    log "Resources to be cleaned up:"
    log "  Project ID: ${PROJECT_ID:-"Not found"}"
    log "  Region: ${REGION:-"Not found"}"
    log "  Cloud Function: process-form"
    log "  Document AI Processor: ${PROCESSOR_ID:-"Not found"}"
    log "  Input Bucket: ${BUCKET_INPUT:-"Not found"}"
    log "  Output Bucket: ${BUCKET_OUTPUT:-"Not found"}"
    echo
    
    # Confirmation prompt
    if [[ "$SKIP_CONFIRMATION" != "true" && "$FORCE" != "true" && "$DRY_RUN" != "true" ]]; then
        warning "This will permanently delete the resources listed above."
        warning "This action cannot be undone!"
        echo
        read -p "Do you want to continue? Type 'DELETE' to confirm: " -r
        if [[ "$REPLY" != "DELETE" ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Perform safety checks
    safety_check
    
    # Execute cleanup steps (in reverse order of creation)
    delete_cloud_function
    delete_documentai_processor
    delete_storage_buckets
    cleanup_local_files
    
    # Check for remaining resources
    list_remaining_resources
    
    # Generate cleanup report
    generate_cleanup_report
    
    echo
    if [[ ${#CLEANUP_ERRORS[@]} -eq 0 ]]; then
        success "🎉 Smart Form Processing cleanup completed successfully!"
    else
        warning "⚠️  Cleanup completed with ${#CLEANUP_ERRORS[@]} errors"
        echo
        log "Errors encountered:"
        for error in "${CLEANUP_ERRORS[@]}"; do
            log "  - $error"
        done
        echo
        log "Please review the cleanup report and manually address any remaining resources"
    fi
    
    echo
    log "Cleanup Summary:"
    log "  Cloud Function: Deleted"
    log "  Document AI Processor: ${PROCESSOR_ID:+Deleted}"
    log "  Storage Buckets: ${BUCKET_INPUT:+Deleted} ${BUCKET_OUTPUT:+Deleted}"
    log "  Local Files: Cleaned"
    echo
    log "Note: Some resources may take a few minutes to be fully removed"
    log "Check the cleanup report at: $PROJECT_ROOT/cleanup-report.txt"
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            SKIP_CONFIRMATION=true
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --dry-run                    Show what would be deleted without removing resources"
            echo "  --force                      Skip all confirmation prompts and delete everything"
            echo "  --skip-confirmation          Skip confirmation prompt but still perform safety checks"
            echo "  --project-id PROJECT_ID      Override project ID"
            echo "  --region REGION              Override region (default: us-central1)"
            echo "  --help                       Show this help message"
            echo
            echo "Environment Variables:"
            echo "  PROJECT_ID                   Google Cloud Project ID"
            echo "  REGION                       Deployment region"
            echo "  FORCE                        Set to 'true' to skip confirmations"
            echo "  DRY_RUN                      Set to 'true' for dry run mode"
            echo
            echo "Safety Features:"
            echo "  - Automatic discovery of deployed resources"
            echo "  - Safety checks for production environments"
            echo "  - Confirmation prompts for destructive actions"
            echo "  - Comprehensive cleanup reporting"
            echo "  - Dry run mode for testing"
            exit 0
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Run main function
main