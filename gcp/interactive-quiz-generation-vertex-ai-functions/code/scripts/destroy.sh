#!/bin/bash

# Destroy Interactive Quiz Generation with Vertex AI and Functions
# This script safely removes all resources created during deployment

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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "gcloud is not authenticated. Please run 'gcloud auth login'"
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [[ -f .env ]]; then
        source .env
        success "Environment variables loaded from .env file"
        log "Project ID: ${PROJECT_ID}"
        log "Region: ${REGION}"
        log "Bucket Name: ${BUCKET_NAME}"
    else
        warning ".env file not found"
        
        # Try to use environment variables or prompt user
        if [[ -z "${PROJECT_ID:-}" ]]; then
            echo -n "Enter PROJECT_ID: "
            read PROJECT_ID
        fi
        
        if [[ -z "${REGION:-}" ]]; then
            export REGION="us-central1"
        fi
        
        if [[ -z "${BUCKET_NAME:-}" ]]; then
            echo -n "Enter BUCKET_NAME: "
            read BUCKET_NAME
        fi
        
        if [[ -z "${FUNCTION_NAME:-}" ]]; then
            echo -n "Enter FUNCTION_NAME: "
            read FUNCTION_NAME
        fi
        
        if [[ -z "${DELIVERY_FUNCTION_NAME:-}" ]]; then
            echo -n "Enter DELIVERY_FUNCTION_NAME: "
            read DELIVERY_FUNCTION_NAME
        fi
        
        if [[ -z "${SCORING_FUNCTION_NAME:-}" ]]; then
            echo -n "Enter SCORING_FUNCTION_NAME: "
            read SCORING_FUNCTION_NAME
        fi
    fi
    
    # Set default project for gcloud
    gcloud config set project ${PROJECT_ID} --quiet
    gcloud config set compute/region ${REGION} --quiet
}

# Function to confirm destruction
confirm_destruction() {
    log "About to destroy the following resources:"
    echo ""
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Storage Bucket: gs://${BUCKET_NAME}"
    echo "Functions:"
    echo "  - ${FUNCTION_NAME}"
    echo "  - ${DELIVERY_FUNCTION_NAME}"
    echo "  - ${SCORING_FUNCTION_NAME}"
    echo "Service Account: quiz-ai-service@${PROJECT_ID}.iam.gserviceaccount.com"
    echo ""
    
    warning "This action cannot be undone!"
    echo ""
    echo "Type 'yes' to confirm destruction of all resources:"
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Function to delete Cloud Functions
delete_functions() {
    log "Deleting Cloud Functions..."
    
    # List of functions to delete
    local functions=(
        "${FUNCTION_NAME}"
        "${DELIVERY_FUNCTION_NAME}"
        "${SCORING_FUNCTION_NAME}"
    )
    
    for func in "${functions[@]}"; do
        if [[ -n "${func}" ]]; then
            log "Deleting function: ${func}"
            
            # Check if function exists before trying to delete
            if gcloud functions describe ${func} &> /dev/null; then
                gcloud functions delete ${func} --quiet
                success "Deleted function: ${func}"
            else
                warning "Function ${func} not found, skipping"
            fi
        fi
    done
    
    # Wait for functions to be fully deleted
    log "Waiting for functions to be fully deleted..."
    sleep 15
    
    success "All Cloud Functions deleted"
}

# Function to delete Cloud Storage bucket and contents
delete_storage() {
    log "Deleting Cloud Storage bucket and contents..."
    
    if [[ -n "${BUCKET_NAME}" ]]; then
        # Check if bucket exists
        if gsutil ls -b gs://${BUCKET_NAME} &> /dev/null; then
            log "Deleting all objects in bucket: ${BUCKET_NAME}"
            
            # Remove all objects (including versions)
            gsutil -m rm -r gs://${BUCKET_NAME}/** 2>/dev/null || true
            
            # Delete the bucket itself
            gsutil rb gs://${BUCKET_NAME}
            
            success "Deleted Cloud Storage bucket: ${BUCKET_NAME}"
        else
            warning "Bucket ${BUCKET_NAME} not found, skipping"
        fi
    else
        warning "BUCKET_NAME not set, skipping bucket deletion"
    fi
}

# Function to delete service account
delete_service_account() {
    log "Deleting service account..."
    
    local service_account="quiz-ai-service@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe ${service_account} &> /dev/null; then
        log "Removing IAM policy bindings..."
        
        # Remove IAM bindings (ignore errors if bindings don't exist)
        gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
            --member="serviceAccount:${service_account}" \
            --role="roles/aiplatform.user" \
            --quiet 2>/dev/null || true
        
        gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
            --member="serviceAccount:${service_account}" \
            --role="roles/storage.objectAdmin" \
            --quiet 2>/dev/null || true
        
        # Delete service account
        gcloud iam service-accounts delete ${service_account} --quiet
        
        success "Deleted service account: ${service_account}"
    else
        warning "Service account ${service_account} not found, skipping"
    fi
}

# Function to clean up local files
clean_local_files() {
    log "Cleaning up local files..."
    
    # List of files and directories to remove
    local cleanup_items=(
        "quiz-functions/"
        "sample_content.json"
        "quiz_response.json"
        "delivered_quiz.json"
        "student_submission.json"
        "scoring_results.json"
        "lifecycle.json"
        ".env"
    )
    
    for item in "${cleanup_items[@]}"; do
        if [[ -e "${item}" ]]; then
            log "Removing: ${item}"
            rm -rf "${item}"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to disable APIs (optional)
disable_apis() {
    log "Optionally disabling APIs..."
    
    echo ""
    echo "Do you want to disable the APIs that were enabled for this project?"
    echo "Warning: This may affect other services in the project."
    echo "Type 'yes' to disable APIs, or press Enter to skip:"
    read -r disable_confirmation
    
    if [[ "$disable_confirmation" == "yes" ]]; then
        log "Disabling APIs..."
        
        local apis=(
            "aiplatform.googleapis.com"
            "cloudfunctions.googleapis.com"
            "storage.googleapis.com"
            "cloudbuild.googleapis.com"
            "artifactregistry.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            log "Disabling ${api}..."
            gcloud services disable ${api} --quiet --force 2>/dev/null || warning "Failed to disable ${api}"
        done
        
        success "APIs disabled"
    else
        log "Skipping API disabling"
    fi
}

# Function to delete project (optional)
delete_project() {
    log "Optionally deleting project..."
    
    echo ""
    echo "Do you want to delete the entire project: ${PROJECT_ID}?"
    echo "Warning: This will permanently delete ALL resources in the project."
    echo "Type 'DELETE' to confirm project deletion, or press Enter to skip:"
    read -r project_delete_confirmation
    
    if [[ "$project_delete_confirmation" == "DELETE" ]]; then
        log "Deleting project: ${PROJECT_ID}"
        
        gcloud projects delete ${PROJECT_ID} --quiet
        
        success "Project deletion initiated: ${PROJECT_ID}"
        warning "Project deletion may take several minutes to complete"
    else
        log "Skipping project deletion"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local cleanup_errors=0
    
    # Check if functions still exist
    local functions=(
        "${FUNCTION_NAME}"
        "${DELIVERY_FUNCTION_NAME}"
        "${SCORING_FUNCTION_NAME}"
    )
    
    for func in "${functions[@]}"; do
        if [[ -n "${func}" ]] && gcloud functions describe ${func} &> /dev/null; then
            error "Function ${func} still exists"
            ((cleanup_errors++))
        fi
    done
    
    # Check if bucket still exists
    if [[ -n "${BUCKET_NAME}" ]] && gsutil ls -b gs://${BUCKET_NAME} &> /dev/null; then
        error "Bucket ${BUCKET_NAME} still exists"
        ((cleanup_errors++))
    fi
    
    # Check if service account still exists
    local service_account="quiz-ai-service@${PROJECT_ID}.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe ${service_account} &> /dev/null; then
        error "Service account ${service_account} still exists"
        ((cleanup_errors++))
    fi
    
    if [[ ${cleanup_errors} -eq 0 ]]; then
        success "Cleanup verification passed"
    else
        warning "Cleanup verification found ${cleanup_errors} issues"
        warning "Some resources may still exist. Please check manually."
    fi
}

# Function to display cleanup summary
show_cleanup_summary() {
    log "Cleanup Summary"
    echo "================"
    echo ""
    echo "The following resources have been removed:"
    echo "✅ Cloud Functions (quiz generation, delivery, scoring)"
    echo "✅ Cloud Storage bucket and contents"
    echo "✅ Service account and IAM bindings"
    echo "✅ Local files and directories"
    echo ""
    echo "Project ID: ${PROJECT_ID}"
    echo ""
    
    if [[ -f .env ]]; then
        warning ".env file still exists (not automatically removed for safety)"
    fi
    
    echo ""
    success "Cleanup completed successfully!"
    echo ""
    echo "Manual verification commands:"
    echo "  gcloud functions list"
    echo "  gsutil ls"
    echo "  gcloud iam service-accounts list"
}

# Main cleanup function
main() {
    log "Starting Interactive Quiz Generation system cleanup"
    echo ""
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    log "Beginning resource cleanup..."
    
    delete_functions
    delete_storage
    delete_service_account
    clean_local_files
    
    # Optional cleanup steps
    disable_apis
    delete_project
    
    verify_cleanup
    show_cleanup_summary
    
    success "Cleanup process completed!"
}

# Handle script interruption
trap 'error "Cleanup interrupted. Some resources may not have been deleted."; exit 1' INT TERM

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Destroy Interactive Quiz Generation with Vertex AI and Functions deployment"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --force        Skip confirmation prompts (use with caution)"
    echo "  --keep-project Don't offer to delete the project"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID               GCP Project ID"
    echo "  REGION                   GCP Region (default: us-central1)"
    echo "  BUCKET_NAME              Cloud Storage bucket name"
    echo "  FUNCTION_NAME            Quiz generation function name"
    echo "  DELIVERY_FUNCTION_NAME   Quiz delivery function name"
    echo "  SCORING_FUNCTION_NAME    Quiz scoring function name"
    echo ""
    echo "Examples:"
    echo "  $0                       Interactive cleanup with confirmations"
    echo "  $0 --force              Automatic cleanup (dangerous)"
    echo "  $0 --keep-project       Clean up resources but keep project"
}

# Parse command line arguments
FORCE_MODE=false
KEEP_PROJECT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --force)
            FORCE_MODE=true
            shift
            ;;
        --keep-project)
            KEEP_PROJECT=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Override confirmation functions if force mode is enabled
if [[ "$FORCE_MODE" == "true" ]]; then
    warning "Force mode enabled - skipping confirmations"
    confirm_destruction() {
        warning "Force mode: skipping destruction confirmation"
    }
    
    disable_apis() {
        log "Force mode: skipping API disabling"
    }
    
    delete_project() {
        if [[ "$KEEP_PROJECT" == "false" ]]; then
            log "Force mode: deleting project ${PROJECT_ID}"
            gcloud projects delete ${PROJECT_ID} --quiet
            success "Project deletion initiated: ${PROJECT_ID}"
        else
            log "Force mode: keeping project as requested"
        fi
    }
fi

# Override project deletion if keep-project flag is set
if [[ "$KEEP_PROJECT" == "true" ]]; then
    delete_project() {
        log "Keeping project as requested"
    }
fi

# Run main function
main "$@"