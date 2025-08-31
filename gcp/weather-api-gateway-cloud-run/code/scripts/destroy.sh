#!/bin/bash

# Weather API Gateway with Cloud Run - Cleanup Script  
# This script removes all resources created by the weather API gateway deployment

set -e  # Exit on any error

# Color codes for output
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

# Configuration
DEFAULT_REGION="us-central1"
DEFAULT_SERVICE_NAME="weather-api-gateway"

# Parse command line arguments
DRY_RUN=false
FORCE=false
REGION=""
PROJECT_ID=""
SERVICE_NAME=""
BUCKET_NAME=""
DELETE_PROJECT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --service-name)
            SERVICE_NAME="$2"
            shift 2
            ;;
        --bucket-name)
            BUCKET_NAME="$2"
            shift 2
            ;;
        --delete-project)
            DELETE_PROJECT=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run          Show what would be deleted without making changes"
            echo "  --force            Skip confirmation prompts"
            echo "  --region REGION    GCP region (default: ${DEFAULT_REGION})"
            echo "  --project-id ID    GCP project ID (required)"
            echo "  --service-name     Cloud Run service name (default: ${DEFAULT_SERVICE_NAME})"
            echo "  --bucket-name      Cloud Storage bucket name (optional)"
            echo "  --delete-project   Delete the entire project (destructive)"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set defaults
REGION=${REGION:-$DEFAULT_REGION}
SERVICE_NAME=${SERVICE_NAME:-$DEFAULT_SERVICE_NAME}

log_info "Starting Weather API Gateway cleanup..."

# Load deployment info if available
load_deployment_info() {
    if [[ -f "deployment-info.json" ]] && command -v jq &> /dev/null; then
        log_info "Loading deployment information from deployment-info.json"
        
        if [[ -z "$PROJECT_ID" ]]; then
            PROJECT_ID=$(jq -r '.project_id' deployment-info.json 2>/dev/null || echo "")
        fi
        
        if [[ -z "$BUCKET_NAME" ]]; then
            BUCKET_NAME=$(jq -r '.bucket_name' deployment-info.json 2>/dev/null || echo "")
        fi
        
        if [[ -z "$REGION" ]] || [[ "$REGION" == "$DEFAULT_REGION" ]]; then
            LOADED_REGION=$(jq -r '.region' deployment-info.json 2>/dev/null || echo "")
            if [[ -n "$LOADED_REGION" ]]; then
                REGION="$LOADED_REGION"
            fi
        fi
        
        SERVICE_URL=$(jq -r '.service_url' deployment-info.json 2>/dev/null || echo "")
        
        log_success "Loaded deployment information"
    elif [[ -f "deployment-info.json" ]]; then
        log_warning "deployment-info.json found but jq not available for parsing"
    fi
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud SDK (gcloud) is not installed"
        log_error "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed (part of Google Cloud SDK)"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use --project-id or ensure deployment-info.json exists"
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project $PROJECT_ID does not exist or is not accessible"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Discover resources if not provided
discover_resources() {
    log_info "Discovering deployed resources..."
    
    # Set project context
    if [[ "$DRY_RUN" == "false" ]]; then
        gcloud config set project "$PROJECT_ID" 2>/dev/null || true
    fi
    
    # Try to find Cloud Run service if not specified
    if [[ -z "$SERVICE_NAME" ]] || [[ "$SERVICE_NAME" == "$DEFAULT_SERVICE_NAME" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            DISCOVERED_SERVICES=$(gcloud run services list \
                --region="$REGION" \
                --filter="metadata.name~weather.*gateway" \
                --format="value(metadata.name)" 2>/dev/null || echo "")
            
            if [[ -n "$DISCOVERED_SERVICES" ]]; then
                SERVICE_NAME=$(echo "$DISCOVERED_SERVICES" | head -n1)
                log_info "Discovered Cloud Run service: $SERVICE_NAME"
            fi
        fi
    fi
    
    # Try to find storage bucket if not specified
    if [[ -z "$BUCKET_NAME" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            DISCOVERED_BUCKETS=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | \
                grep -E "gs://weather-cache-[a-f0-9]{6}/" | \
                sed 's|gs://||' | sed 's|/||' || echo "")
            
            if [[ -n "$DISCOVERED_BUCKETS" ]]; then
                BUCKET_NAME=$(echo "$DISCOVERED_BUCKETS" | head -n1)
                log_info "Discovered storage bucket: $BUCKET_NAME"
            fi
        fi
    fi
    
    log_success "Resource discovery completed"
}

# Confirmation prompt
confirm_cleanup() {
    if [[ "$FORCE" == "false" ]]; then
        echo
        log_warning "This will permanently delete the following resources:"
        
        if [[ -n "$SERVICE_NAME" ]]; then
            log_warning "  ❌ Cloud Run service: $SERVICE_NAME"
        fi
        
        if [[ -n "$BUCKET_NAME" ]]; then
            log_warning "  ❌ Storage bucket: $BUCKET_NAME (and all cached data)"
        fi
        
        if [[ "$DELETE_PROJECT" == "true" ]]; then
            log_warning "  ❌ Entire project: $PROJECT_ID (DESTRUCTIVE)"
        fi
        
        echo
        log_warning "Estimated cost savings: $0.01-$0.10 per day"
        echo
        
        if [[ "$DELETE_PROJECT" == "true" ]]; then
            log_error "WARNING: Project deletion is irreversible!"
            read -p "Are you absolutely sure you want to delete the entire project? (type 'DELETE' to confirm): " -r
            if [[ "$REPLY" != "DELETE" ]]; then
                log_info "Cleanup cancelled"
                exit 0
            fi
        else
            read -p "Continue with cleanup? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Cleanup cancelled"
                exit 0
            fi
        fi
    fi
}

# Delete Cloud Run service
delete_cloud_run_service() {
    if [[ -n "$SERVICE_NAME" ]]; then
        log_info "Deleting Cloud Run service: $SERVICE_NAME"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            # Check if service exists
            if gcloud run services describe "$SERVICE_NAME" \
                --region="$REGION" &> /dev/null; then
                
                if gcloud run services delete "$SERVICE_NAME" \
                    --region="$REGION" \
                    --quiet; then
                    log_success "Deleted Cloud Run service: $SERVICE_NAME"
                else
                    log_error "Failed to delete Cloud Run service"
                    return 1
                fi
            else
                log_warning "Cloud Run service $SERVICE_NAME not found"
            fi
        else
            log_info "[DRY RUN] Would delete Cloud Run service: $SERVICE_NAME"
        fi
    else
        log_warning "No Cloud Run service specified for deletion"
    fi
}

# Delete Cloud Storage bucket
delete_storage_bucket() {
    if [[ -n "$BUCKET_NAME" ]]; then
        log_info "Deleting Cloud Storage bucket: $BUCKET_NAME"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            # Check if bucket exists
            if gsutil ls "gs://$BUCKET_NAME/" &> /dev/null; then
                # List objects for user awareness
                OBJECT_COUNT=$(gsutil ls "gs://$BUCKET_NAME/**" 2>/dev/null | wc -l || echo "0")
                if [[ "$OBJECT_COUNT" -gt 0 ]]; then
                    log_info "Bucket contains $OBJECT_COUNT cached objects"
                fi
                
                # Delete all objects and bucket
                if gsutil -m rm -r "gs://$BUCKET_NAME"; then
                    log_success "Deleted storage bucket and all cached data: $BUCKET_NAME"
                else
                    log_error "Failed to delete storage bucket"
                    return 1
                fi
            else
                log_warning "Storage bucket $BUCKET_NAME not found"
            fi
        else
            log_info "[DRY RUN] Would delete storage bucket: $BUCKET_NAME"
        fi
    else
        log_warning "No storage bucket specified for deletion"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=("weather-gateway" "lifecycle.json" "deployment-info.json")
    
    if [[ "$DRY_RUN" == "false" ]]; then
        for file in "${files_to_remove[@]}"; do
            if [[ -e "$file" ]]; then
                rm -rf "$file"
                log_success "Removed local file/directory: $file"
            fi
        done
    else
        for file in "${files_to_remove[@]}"; do
            if [[ -e "$file" ]]; then
                log_info "[DRY RUN] Would remove local file/directory: $file"
            fi
        done
    fi
}

# Remove IAM policy bindings
cleanup_iam_permissions() {
    log_info "Cleaning up IAM permissions..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Get Cloud Run service account (may not exist if service was deleted)
        SERVICE_ACCOUNT=$(gcloud run services describe "$SERVICE_NAME" \
            --region="$REGION" \
            --format='value(spec.template.spec.serviceAccountName)' 2>/dev/null || echo "")
        
        if [[ -n "$SERVICE_ACCOUNT" ]]; then
            # Remove project-level IAM binding
            if gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$SERVICE_ACCOUNT" \
                --role="roles/storage.objectAdmin" 2>/dev/null; then
                log_success "Removed IAM policy binding for service account"
            else
                log_warning "Could not remove IAM policy binding (may not exist)"
            fi
        else
            log_info "No service account found for IAM cleanup"
        fi
    else
        log_info "[DRY RUN] Would clean up IAM permissions"
    fi
}

# Delete entire project
delete_project() {
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        log_info "Deleting entire project: $PROJECT_ID"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            if gcloud projects delete "$PROJECT_ID" --quiet; then
                log_success "Project deletion initiated: $PROJECT_ID"
                log_info "Project deletion may take several minutes to complete"
            else
                log_error "Failed to delete project"
                return 1
            fi
        else
            log_info "[DRY RUN] Would delete entire project: $PROJECT_ID"
        fi
    fi
}

# Verify cleanup completion
verify_cleanup() {
    if [[ "$DRY_RUN" == "false" ]] && [[ "$DELETE_PROJECT" == "false" ]]; then
        log_info "Verifying cleanup completion..."
        
        # Check if Cloud Run service still exists
        if [[ -n "$SERVICE_NAME" ]]; then
            if gcloud run services describe "$SERVICE_NAME" \
                --region="$REGION" &> /dev/null; then
                log_warning "Cloud Run service still exists: $SERVICE_NAME"
            else
                log_success "Cloud Run service successfully deleted"
            fi
        fi
        
        # Check if storage bucket still exists
        if [[ -n "$BUCKET_NAME" ]]; then
            if gsutil ls "gs://$BUCKET_NAME/" &> /dev/null; then
                log_warning "Storage bucket still exists: $BUCKET_NAME"
            else
                log_success "Storage bucket successfully deleted"
            fi
        fi
        
        log_success "Cleanup verification completed"
    fi
}

# Generate cleanup report
generate_cleanup_report() {
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Generating cleanup report..."
        
        cat > cleanup-report.txt << EOF
Weather API Gateway Cleanup Report
Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

Project ID: $PROJECT_ID
Region: $REGION

Deleted Resources:
- Cloud Run Service: ${SERVICE_NAME:-"Not specified"}
- Storage Bucket: ${BUCKET_NAME:-"Not specified"}
- Project Deleted: $DELETE_PROJECT

Local Files Cleaned:
- weather-gateway/ directory
- lifecycle.json
- deployment-info.json

Estimated Cost Savings: $0.01-$0.10 per day

Note: If you created the project specifically for this recipe,
all associated billing will stop once project deletion completes.
EOF
        
        log_success "Cleanup report saved to cleanup-report.txt"
    fi
}

# Error handling for partial cleanup
handle_cleanup_error() {
    log_error "Cleanup encountered an error. Some resources may still exist."
    log_info "You can:"
    log_info "1. Re-run this script to retry cleanup"
    log_info "2. Manually delete resources in Google Cloud Console"
    log_info "3. Use --force flag to skip confirmation prompts"
    
    if [[ -n "$PROJECT_ID" ]]; then
        log_info "4. Delete the entire project: gcloud projects delete $PROJECT_ID"
    fi
}

# Main cleanup flow
main() {
    # Set up error handling
    trap handle_cleanup_error ERR
    
    # Run cleanup steps
    load_deployment_info
    check_prerequisites
    discover_resources
    confirm_cleanup
    
    # If deleting project, skip individual resource cleanup
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        delete_project
    else
        delete_cloud_run_service
        cleanup_iam_permissions
        delete_storage_bucket
    fi
    
    cleanup_local_files
    verify_cleanup
    generate_cleanup_report
    
    # Final success message
    echo
    log_success "Weather API Gateway cleanup completed successfully!"
    echo
    
    if [[ "$DRY_RUN" == "false" ]]; then
        if [[ "$DELETE_PROJECT" == "true" ]]; then
            log_info "Project deletion initiated. All resources will be removed."
            log_info "Billing will stop once deletion completes (may take several minutes)."
        else
            log_info "Cleanup Summary:"
            log_info "  ✅ Cloud Run service deleted"
            log_info "  ✅ Storage bucket and cache data deleted"
            log_info "  ✅ Local files cleaned up"
            log_info "  ✅ IAM permissions cleaned up"
            echo
            log_info "Cost Impact:"
            log_info "  • Eliminated ~$0.01-$0.10 daily costs"
            log_info "  • Stopped all traffic-based charges"
        fi
        
        log_info "Cleanup report available in: cleanup-report.txt"
    else
        log_info "This was a dry run. Use './destroy.sh' to actually delete resources."
    fi
}

# Run main function
main "$@"