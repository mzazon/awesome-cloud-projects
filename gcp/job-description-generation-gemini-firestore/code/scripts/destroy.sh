#!/bin/bash

# GCP Job Description Generation with Gemini and Firestore - Cleanup Script
# This script removes all infrastructure created for the job description generation system

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Help function
show_help() {
    cat << EOF
GCP Job Description Generation Cleanup Script

USAGE:
    ./destroy.sh [OPTIONS]

OPTIONS:
    -p, --project-id PROJECT_ID     Set GCP project ID to clean up
    -r, --region REGION            Set region for cleanup (default: us-central1)
    -f, --force                    Skip confirmation prompts
    --delete-project               Delete the entire project (DESTRUCTIVE)
    --preserve-data                Keep Firestore data (only remove functions)
    -h, --help                     Show this help message
    --dry-run                      Show what would be deleted without executing

EXAMPLES:
    ./destroy.sh                                    # Clean up with prompts
    ./destroy.sh -p my-project                     # Clean up specific project
    ./destroy.sh --force                           # Clean up without prompts
    ./destroy.sh --delete-project --force          # Delete entire project
    ./destroy.sh --preserve-data                   # Keep Firestore data
    ./destroy.sh --dry-run                         # Preview cleanup

SAFETY:
    This script will permanently delete cloud resources and data.
    Always review what will be deleted before confirming.

EOF
}

# Default configuration
DEFAULT_REGION="us-central1"
FORCE_MODE=false
DELETE_PROJECT=false
PRESERVE_DATA=false
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse command line arguments
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
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        --delete-project)
            DELETE_PROJECT=true
            shift
            ;;
        --preserve-data)
            PRESERVE_DATA=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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

# Set defaults if not provided
REGION=${REGION:-$DEFAULT_REGION}

# Try to load from deployment environment if project not specified
if [[ -z "${PROJECT_ID:-}" ]] && [[ -f "$SCRIPT_DIR/deployment.env" ]]; then
    source "$SCRIPT_DIR/deployment.env"
    log "Loaded project ID from deployment.env: $PROJECT_ID"
fi

# Validate project ID
if [[ -z "${PROJECT_ID:-}" ]]; then
    error "Project ID not specified and not found in deployment.env"
    echo "Use -p/--project-id to specify the project to clean up"
    exit 1
fi

log "=== GCP Job Description Generation Cleanup ==="
log "Project ID: $PROJECT_ID"
log "Region: $REGION"

if [[ "$DELETE_PROJECT" == "true" ]]; then
    warning "DELETE PROJECT MODE - The entire project will be deleted!"
fi

if [[ "$PRESERVE_DATA" == "true" ]]; then
    log "PRESERVE DATA MODE - Firestore data will be kept"
fi

if [[ "$DRY_RUN" == "true" ]]; then
    warning "DRY RUN MODE - No resources will be deleted"
fi

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed"
        exit 1
    fi
    
    # Check if Python 3 is available
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed"
        exit 1
    fi
    
    # Check if authenticated with gcloud
    if [[ "$DRY_RUN" == "false" ]]; then
        if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
            error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
            exit 1
        fi
    fi
    
    # Check if project exists
    if [[ "$DRY_RUN" == "false" ]]; then
        if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
            error "Project $PROJECT_ID does not exist or you don't have access"
            exit 1
        fi
    fi
    
    success "Prerequisites check completed"
}

# Show resources to be deleted
show_resources() {
    log "Scanning for resources to delete..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Set project context
        gcloud config set project "$PROJECT_ID" --quiet >/dev/null 2>&1
    fi
    
    echo
    echo "📋 Resources that will be affected:"
    echo
    
    # Cloud Functions
    echo "🔧 Cloud Functions:"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  - generate-job-description (Generation 2)"
        echo "  - validate-compliance (Generation 2)"
    else
        local functions
        functions=$(gcloud functions list --regions="$REGION" --format="value(name)" 2>/dev/null || echo "")
        if [[ -n "$functions" ]]; then
            echo "$functions" | while read -r func; do
                if [[ "$func" == *"generate-job-description"* ]] || [[ "$func" == *"validate-compliance"* ]]; then
                    echo "  - $func"
                fi
            done
        else
            echo "  - No Cloud Functions found"
        fi
    fi
    echo
    
    # Firestore
    if [[ "$PRESERVE_DATA" == "false" ]]; then
        echo "🔥 Firestore Collections:"
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  - company_culture"
            echo "  - job_templates"
            echo "  - generated_jobs"
        else
            # Check Firestore collections
            python3 -c "
from google.cloud import firestore
import os
try:
    db = firestore.Client(project='$PROJECT_ID')
    collections = db.collections()
    found_collections = []
    for collection in collections:
        if collection.id in ['company_culture', 'job_templates', 'generated_jobs']:
            found_collections.append(collection.id)
    if found_collections:
        for col in found_collections:
            print(f'  - {col}')
    else:
        print('  - No target collections found')
except Exception as e:
    print('  - Unable to scan collections (may not exist)')
" 2>/dev/null || echo "  - Unable to scan Firestore collections"
        fi
        echo
    else
        echo "🔥 Firestore Collections: PRESERVED (--preserve-data flag used)"
        echo
    fi
    
    # Project deletion
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo "💥 Project Deletion:"
        echo "  - Entire project '$PROJECT_ID' will be PERMANENTLY DELETED"
        echo "  - ALL resources, data, and configurations will be lost"
        echo "  - This action is IRREVERSIBLE"
        echo
    fi
    
    # Local files
    echo "📁 Local Files:"
    if [[ -f "$SCRIPT_DIR/deployment.env" ]]; then
        echo "  - deployment.env (deployment configuration)"
    else
        echo "  - No deployment configuration found"
    fi
    echo
}

# Confirmation function
confirm_deletion() {
    if [[ "$FORCE_MODE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo "⚠️  WARNING: This will permanently delete cloud resources and may result in data loss!"
    echo
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo "🚨 PROJECT DELETION MODE ACTIVE 🚨"
        echo "The ENTIRE PROJECT '$PROJECT_ID' will be PERMANENTLY DELETED!"
        echo "This includes ALL resources, data, billing history, and configurations."
        echo "This action is IRREVERSIBLE and cannot be undone."
        echo
        read -p "Type 'DELETE PROJECT' to confirm project deletion: " confirmation
        if [[ "$confirmation" != "DELETE PROJECT" ]]; then
            log "Project deletion cancelled"
            exit 0
        fi
    else
        read -p "Type 'DELETE' to confirm resource deletion: " confirmation
        if [[ "$confirmation" != "DELETE" ]]; then
            log "Cleanup cancelled"
            exit 0
        fi
    fi
    
    echo
    log "Proceeding with cleanup..."
    echo
}

# Delete Cloud Functions
delete_functions() {
    log "Deleting Cloud Functions..."
    
    local functions_to_delete=(
        "generate-job-description"
        "validate-compliance"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        for func in "${functions_to_delete[@]}"; do
            log "[DRY RUN] Would delete function: $func"
        done
        return 0
    fi
    
    for func in "${functions_to_delete[@]}"; do
        log "Deleting function: $func"
        if gcloud functions delete "$func" \
            --gen2 \
            --region="$REGION" \
            --quiet 2>/dev/null; then
            success "Deleted function: $func"
        else
            warning "Function $func not found or already deleted"
        fi
    done
    
    success "Cloud Functions cleanup completed"
}

# Clear Firestore data
clear_firestore_data() {
    if [[ "$PRESERVE_DATA" == "true" ]]; then
        log "Skipping Firestore data deletion (--preserve-data flag)"
        return 0
    fi
    
    log "Clearing Firestore data..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete collections: company_culture, job_templates, generated_jobs"
        return 0
    fi
    
    # Create Python script for Firestore cleanup
    cat > /tmp/cleanup_firestore.py << 'EOF'
import sys
import os
from google.cloud import firestore

def cleanup_firestore_data(project_id):
    """Clean up Firestore collections for the HR automation system."""
    try:
        # Initialize Firestore client
        db = firestore.Client(project=project_id)
        
        # Collections to delete
        collections = ['company_culture', 'job_templates', 'generated_jobs']
        
        for collection_name in collections:
            collection_ref = db.collection(collection_name)
            docs = collection_ref.stream()
            
            deleted_count = 0
            for doc in docs:
                doc.reference.delete()
                deleted_count += 1
            
            if deleted_count > 0:
                print(f"✅ Deleted {deleted_count} documents from {collection_name}")
            else:
                print(f"⚠️  Collection {collection_name} was empty or not found")
        
        print(f"✅ Firestore cleanup completed for project: {project_id}")
        
    except Exception as e:
        print(f"❌ Error cleaning up Firestore data: {e}")
        # Don't exit with error for cleanup script
        print(f"⚠️  Continuing with other cleanup tasks...")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 cleanup_firestore.py <project_id>")
        sys.exit(1)
    
    project_id = sys.argv[1]
    cleanup_firestore_data(project_id)
EOF
    
    # Install Google Cloud Firestore client if not already installed
    pip3 install google-cloud-firestore >/dev/null 2>&1 || {
        warning "Could not install Google Cloud Firestore client. Skipping Firestore cleanup."
        return 0
    }
    
    # Run the Firestore cleanup script
    python3 /tmp/cleanup_firestore.py "$PROJECT_ID"
    
    # Clean up temporary file
    rm -f /tmp/cleanup_firestore.py
    
    success "Firestore data cleanup completed"
}

# Delete project entirely
delete_project() {
    if [[ "$DELETE_PROJECT" != "true" ]]; then
        return 0
    fi
    
    log "Deleting entire project: $PROJECT_ID"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete project: $PROJECT_ID"
        return 0
    fi
    
    # Final confirmation for project deletion
    echo
    warning "FINAL WARNING: About to delete project '$PROJECT_ID'"
    warning "This will permanently delete ALL resources, data, and configurations"
    warning "This action is IRREVERSIBLE"
    echo
    
    if [[ "$FORCE_MODE" == "false" ]]; then
        read -p "Type the project ID '$PROJECT_ID' to confirm: " project_confirmation
        if [[ "$project_confirmation" != "$PROJECT_ID" ]]; then
            error "Project ID confirmation failed. Cleanup cancelled."
            exit 1
        fi
    fi
    
    log "Deleting project $PROJECT_ID..."
    if gcloud projects delete "$PROJECT_ID" --quiet; then
        success "Project $PROJECT_ID has been scheduled for deletion"
        log "Note: Project deletion may take several minutes to complete"
    else
        error "Failed to delete project $PROJECT_ID"
        exit 1
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ -f "$SCRIPT_DIR/deployment.env" ]]; then
            log "[DRY RUN] Would delete: deployment.env"
        fi
        return 0
    fi
    
    # Remove deployment environment file
    if [[ -f "$SCRIPT_DIR/deployment.env" ]]; then
        rm -f "$SCRIPT_DIR/deployment.env"
        success "Deleted deployment.env"
    else
        log "No deployment.env file to delete"
    fi
    
    success "Local files cleanup completed"
}

# Display cleanup summary
show_summary() {
    log "=== Cleanup Summary ==="
    echo
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "📋 Would delete entire project: $PROJECT_ID"
        else
            echo "📋 Project '$PROJECT_ID' has been scheduled for deletion"
            echo "   Note: Complete deletion may take several minutes"
        fi
    else
        echo "📋 Cleanup completed for project: $PROJECT_ID"
        echo
        echo "🗑️  Deleted Resources:"
        echo "   - Cloud Functions (generate-job-description, validate-compliance)"
        
        if [[ "$PRESERVE_DATA" == "false" ]]; then
            echo "   - Firestore collections (company_culture, job_templates, generated_jobs)"
        else
            echo "   - Firestore data preserved (--preserve-data flag used)"
        fi
        
        echo "   - Local configuration files"
        echo
        echo "💰 Cost Impact:"
        echo "   - Cloud Functions billing stopped"
        echo "   - Firestore operations billing stopped"
        echo "   - Vertex AI usage billing stopped"
        echo
        echo "🔧 Remaining Resources:"
        echo "   - Project '$PROJECT_ID' (use --delete-project to remove)"
        echo "   - Enabled APIs (will not incur charges without active resources)"
    fi
    
    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        success "Dry run completed - no actual resources were deleted"
    else
        success "Cleanup completed successfully! 🎉"
    fi
    
    if [[ "$DELETE_PROJECT" == "false" ]] && [[ "$DRY_RUN" == "false" ]]; then
        echo
        log "To completely remove all traces of this deployment:"
        log "Run: ./destroy.sh --delete-project --force"
    fi
}

# Main cleanup flow
main() {
    log "Starting GCP Job Description Generation cleanup..."
    
    check_prerequisites
    show_resources
    confirm_deletion
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        delete_project
    else
        delete_functions
        clear_firestore_data
        cleanup_local_files
    fi
    
    show_summary
    
    success "All cleanup steps completed!"
}

# Error handling
trap 'error "Cleanup failed at line $LINENO. Some resources may still exist."' ERR

# Run main function
main "$@"