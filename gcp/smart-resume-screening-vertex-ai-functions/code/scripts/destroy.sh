#!/bin/bash

# Smart Resume Screening with Vertex AI and Cloud Functions - Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Parse command line arguments
FORCE_DELETE=false
DRY_RUN=false
PROJECT_ID=""
REGION=""
BUCKET_NAME=""
SKIP_CONFIRMATION=false
DEPLOYMENT_INFO_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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
        --bucket-name)
            BUCKET_NAME="$2"
            shift 2
            ;;
        --deployment-info)
            DEPLOYMENT_INFO_FILE="$2"
            shift 2
            ;;
        --yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force                Force deletion without additional safety checks"
            echo "  --dry-run             Show what would be deleted without making changes"
            echo "  --project-id          Specific project ID to delete resources from"
            echo "  --region              Region where resources are located"
            echo "  --bucket-name         Specific bucket name to delete"
            echo "  --deployment-info     Path to deployment_info.json file"
            echo "  --yes                 Skip confirmation prompts"
            echo "  --help                Show this help message"
            echo ""
            echo "Note: Script will attempt to auto-detect resources if parameters not provided"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log "Starting Smart Resume Screening cleanup..."

# Check prerequisites
log "Checking prerequisites..."

if ! command -v gcloud &> /dev/null; then
    error "gcloud CLI is not installed"
    exit 1
fi

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    error "Not authenticated with gcloud. Please run 'gcloud auth login'"
    exit 1
fi

success "Prerequisites check completed"

# Auto-detect deployment information if not provided
if [[ -z "$PROJECT_ID" ]] || [[ -z "$REGION" ]] || [[ -z "$BUCKET_NAME" ]]; then
    log "Attempting to auto-detect deployment information..."
    
    # Look for deployment_info.json in current directory and common locations
    SEARCH_PATHS=(
        "."
        "./deployment_info.json"
        "../deployment_info.json"
        "/tmp/*/deployment_info.json"
    )
    
    if [[ -n "$DEPLOYMENT_INFO_FILE" ]] && [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
        FOUND_INFO_FILE="$DEPLOYMENT_INFO_FILE"
    else
        FOUND_INFO_FILE=""
        for path in "${SEARCH_PATHS[@]}"; do
            if [[ -f "$path/deployment_info.json" ]]; then
                FOUND_INFO_FILE="$path/deployment_info.json"
                break
            elif [[ -f "$path" ]] && [[ "$path" == *"deployment_info.json" ]]; then
                FOUND_INFO_FILE="$path"
                break
            fi
        done
    fi
    
    if [[ -n "$FOUND_INFO_FILE" ]] && [[ -f "$FOUND_INFO_FILE" ]]; then
        log "Found deployment info file: $FOUND_INFO_FILE"
        
        if command -v jq &> /dev/null; then
            PROJECT_ID=$(jq -r '.project_id // empty' "$FOUND_INFO_FILE")
            REGION=$(jq -r '.region // empty' "$FOUND_INFO_FILE")
            BUCKET_NAME=$(jq -r '.bucket_name // empty' "$FOUND_INFO_FILE")
        else
            # Parse JSON without jq (basic parsing)
            PROJECT_ID=$(grep -o '"project_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$FOUND_INFO_FILE" | cut -d'"' -f4)
            REGION=$(grep -o '"region"[[:space:]]*:[[:space:]]*"[^"]*"' "$FOUND_INFO_FILE" | cut -d'"' -f4)
            BUCKET_NAME=$(grep -o '"bucket_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$FOUND_INFO_FILE" | cut -d'"' -f4)
        fi
        
        success "Auto-detected deployment configuration"
    else
        warning "Could not find deployment_info.json file"
    fi
fi

# If still missing information, try to detect from current gcloud configuration
if [[ -z "$PROJECT_ID" ]]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -n "$PROJECT_ID" ]]; then
        log "Using current gcloud project: $PROJECT_ID"
    fi
fi

if [[ -z "$REGION" ]]; then
    REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
    log "Using region: $REGION"
fi

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
    error "Project ID not specified and could not be auto-detected"
    error "Please provide --project-id parameter or ensure gcloud is configured"
    exit 1
fi

# Try to find bucket if not specified
if [[ -z "$BUCKET_NAME" ]]; then
    log "Attempting to find resume upload bucket..."
    POTENTIAL_BUCKETS=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "resume-uploads" || echo "")
    if [[ -n "$POTENTIAL_BUCKETS" ]]; then
        BUCKET_NAME=$(echo "$POTENTIAL_BUCKETS" | head -n1 | sed 's|gs://||' | sed 's|/||')
        log "Found potential bucket: $BUCKET_NAME"
    fi
fi

log "Configuration:"
log "  Project ID: ${PROJECT_ID:-'Not specified'}"
log "  Region: ${REGION:-'Not specified'}"
log "  Bucket Name: ${BUCKET_NAME:-'Not specified'}"

if [[ "$DRY_RUN" == "true" ]]; then
    warning "DRY RUN MODE - No resources will be deleted"
    log ""
    log "Resources that would be deleted:"
    log "- Cloud Function: process-resume (in region $REGION)"
    log "- Storage Bucket: gs://$BUCKET_NAME (if exists)"
    log "- Firestore data: candidates collection"
    log "- Project: $PROJECT_ID (if --force is used)"
    exit 0
fi

# Safety confirmation
if [[ "$SKIP_CONFIRMATION" == "false" ]]; then
    log ""
    warning "This will permanently delete the following resources:"
    warning "- Cloud Function: process-resume"
    warning "- Storage Bucket: gs://$BUCKET_NAME (and all contents)"
    warning "- Firestore candidates collection data"
    if [[ "$FORCE_DELETE" == "true" ]]; then
        warning "- ENTIRE PROJECT: $PROJECT_ID"
    fi
    log ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
fi

# Set project context
gcloud config set project "$PROJECT_ID" --quiet

log "Starting resource cleanup for project: $PROJECT_ID"

# Function to safely delete resources with retries
safe_delete() {
    local resource_type="$1"
    local delete_command="$2"
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        if eval "$delete_command" 2>/dev/null; then
            success "Deleted $resource_type"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                warning "Failed to delete $resource_type, retrying... ($retry_count/$max_retries)"
                sleep 5
            else
                warning "Failed to delete $resource_type after $max_retries attempts"
                return 1
            fi
        fi
    done
}

# Delete Cloud Function
log "Deleting Cloud Function..."
if gcloud functions describe process-resume --region="$REGION" &>/dev/null; then
    safe_delete "Cloud Function" "gcloud functions delete process-resume --region='$REGION' --quiet"
else
    warning "Cloud Function 'process-resume' not found in region $REGION"
fi

# Delete Storage Bucket
if [[ -n "$BUCKET_NAME" ]]; then
    log "Deleting Storage Bucket..."
    if gsutil ls "gs://$BUCKET_NAME" &>/dev/null; then
        # First remove all objects, then the bucket
        safe_delete "Storage Bucket contents" "gsutil -m rm -r 'gs://$BUCKET_NAME/**' 2>/dev/null || true"
        safe_delete "Storage Bucket" "gsutil rb 'gs://$BUCKET_NAME'"
    else
        warning "Storage bucket 'gs://$BUCKET_NAME' not found"
    fi
else
    warning "No bucket name specified, skipping bucket deletion"
fi

# Delete Firestore data
log "Cleaning up Firestore data..."

# Check if we can install Python dependencies for cleanup
PYTHON_CLEANUP_AVAILABLE=false
if command -v python3 &> /dev/null && command -v pip3 &> /dev/null; then
    log "Installing Firestore client for data cleanup..."
    if pip3 install google-cloud-firestore >/dev/null 2>&1; then
        PYTHON_CLEANUP_AVAILABLE=true
    fi
fi

if [[ "$PYTHON_CLEANUP_AVAILABLE" == "true" ]]; then
    # Create temporary cleanup script
    CLEANUP_SCRIPT=$(mktemp)
    cat << 'EOF' > "$CLEANUP_SCRIPT"
from google.cloud import firestore
import sys

try:
    db = firestore.Client()
    
    # Delete all documents in candidates collection
    candidates_ref = db.collection('candidates')
    docs = candidates_ref.stream()
    
    deleted_count = 0
    for doc in docs:
        doc.reference.delete()
        deleted_count += 1
    
    print(f"Deleted {deleted_count} candidate documents from Firestore")
    
except Exception as e:
    print(f"Error cleaning up Firestore: {e}")
    sys.exit(1)
EOF
    
    if python3 "$CLEANUP_SCRIPT" 2>/dev/null; then
        success "Firestore data cleaned up"
    else
        warning "Could not clean up Firestore data automatically"
        warning "You may need to manually delete the 'candidates' collection"
    fi
    
    rm -f "$CLEANUP_SCRIPT"
else
    warning "Python Firestore client not available"
    warning "Firestore data cleanup skipped - you may need to manually delete the 'candidates' collection"
fi

# Delete project if force delete is enabled
if [[ "$FORCE_DELETE" == "true" ]]; then
    log "Force delete enabled - deleting entire project..."
    
    if [[ "$SKIP_CONFIRMATION" == "false" ]]; then
        warning "This will DELETE THE ENTIRE PROJECT: $PROJECT_ID"
        warning "This action cannot be undone!"
        read -p "Type the project ID to confirm deletion: " -r
        if [[ "$REPLY" != "$PROJECT_ID" ]]; then
            error "Project ID confirmation failed. Project deletion cancelled."
            exit 1
        fi
    fi
    
    safe_delete "Project" "gcloud projects delete '$PROJECT_ID' --quiet"
    success "Project deletion initiated: $PROJECT_ID"
    warning "Project deletion may take several minutes to complete"
else
    log "Project preserved. To delete the entire project, use --force flag"
fi

# Clean up temporary files
log "Cleaning up temporary files..."
find /tmp -name "*resume*" -type d -user "$(whoami)" -exec rm -rf {} + 2>/dev/null || true

# Final summary
success "Cleanup completed successfully!"
log ""
log "Cleanup Summary:"
log "================"
log "✅ Cloud Function 'process-resume' deleted"
if [[ -n "$BUCKET_NAME" ]]; then
    log "✅ Storage bucket 'gs://$BUCKET_NAME' deleted"
fi
log "✅ Firestore data cleaned up"
if [[ "$FORCE_DELETE" == "true" ]]; then
    log "✅ Project '$PROJECT_ID' deletion initiated"
else
    log "⚠️  Project '$PROJECT_ID' preserved"
fi
log ""

if [[ "$FORCE_DELETE" == "false" ]]; then
    log "Note: The following resources may still exist and incur charges:"
    log "- Project: $PROJECT_ID"
    log "- Firestore database (empty)"
    log "- Enabled APIs in the project"
    log ""
    log "To completely remove all resources, run: $0 --force --project-id $PROJECT_ID"
fi

log "Smart Resume Screening cleanup completed!"