#!/bin/bash

# AWS Text-to-Speech Applications with Amazon Polly - Cleanup Script
# This script removes all resources created by the Amazon Polly text-to-speech recipe

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false
INTERACTIVE=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            warning "Running in DRY-RUN mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            INTERACTIVE=false
            warning "Running in FORCE mode - resources will be deleted without confirmation"
            shift
            ;;
        --yes)
            INTERACTIVE=false
            shift
            ;;
        *)
            error "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--force] [--yes]"
            echo "  --dry-run: Show what would be deleted without actually deleting"
            echo "  --force:   Delete all resources without confirmation"
            echo "  --yes:     Proceed with deletion without confirmation prompts"
            exit 1
            ;;
    esac
done

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    if [[ -f "polly-deployment-state.env" ]]; then
        source polly-deployment-state.env
        success "Loaded deployment state from polly-deployment-state.env"
        log "Bucket: $POLLY_BUCKET_NAME"
        log "Region: $AWS_REGION"
    else
        warning "No deployment state file found. Will attempt to discover resources."
        
        # Try to discover resources
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            error "Could not determine AWS region. Please set AWS_REGION environment variable."
            exit 1
        fi
        
        # Try to find Polly bucket
        log "Searching for Polly buckets in region $AWS_REGION..."
        POLLY_BUCKETS=$(aws s3 ls | grep "polly-audio-output" | awk '{print $3}' || echo "")
        
        if [[ -n "$POLLY_BUCKETS" ]]; then
            log "Found potential Polly buckets:"
            echo "$POLLY_BUCKETS"
            
            if [[ "$INTERACTIVE" == "true" ]]; then
                echo ""
                read -p "Enter the bucket name to delete (or press Enter to skip): " POLLY_BUCKET_NAME
                if [[ -z "$POLLY_BUCKET_NAME" ]]; then
                    warning "No bucket specified. Skipping S3 cleanup."
                fi
            else
                # In non-interactive mode, can't determine which bucket to delete
                warning "Multiple Polly buckets found but running in non-interactive mode. Skipping S3 cleanup."
                POLLY_BUCKET_NAME=""
            fi
        else
            warning "No Polly buckets found."
            POLLY_BUCKET_NAME=""
        fi
    fi
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    if [[ "$INTERACTIVE" == "false" ]]; then
        return 0
    fi
    
    echo ""
    warning "This will permanently delete the following resources:"
    echo "- S3 bucket: $POLLY_BUCKET_NAME (if exists)"
    echo "- Pronunciation lexicon: tech-terminology (if exists)"
    echo "- Local sample files"
    echo "- Deployment state file"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to delete S3 bucket and contents
delete_s3_bucket() {
    if [[ -z "${POLLY_BUCKET_NAME:-}" ]]; then
        warning "No S3 bucket specified. Skipping S3 cleanup."
        return 0
    fi
    
    log "Deleting S3 bucket and contents: $POLLY_BUCKET_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would delete S3 bucket: $POLLY_BUCKET_NAME"
        return 0
    fi
    
    # Check if bucket exists
    if ! aws s3 ls "s3://$POLLY_BUCKET_NAME" &> /dev/null; then
        warning "S3 bucket $POLLY_BUCKET_NAME does not exist or is not accessible"
        return 0
    fi
    
    # Delete all objects in bucket (including versions)
    log "Deleting all objects in bucket..."
    aws s3 rm "s3://$POLLY_BUCKET_NAME" --recursive
    
    # Delete all object versions if versioning is enabled
    log "Deleting all object versions..."
    aws s3api delete-objects \
        --bucket "$POLLY_BUCKET_NAME" \
        --delete "$(aws s3api list-object-versions \
            --bucket "$POLLY_BUCKET_NAME" \
            --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
            --output json)" 2>/dev/null || true
    
    # Delete delete markers
    aws s3api delete-objects \
        --bucket "$POLLY_BUCKET_NAME" \
        --delete "$(aws s3api list-object-versions \
            --bucket "$POLLY_BUCKET_NAME" \
            --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
            --output json)" 2>/dev/null || true
    
    # Delete bucket
    log "Deleting bucket..."
    aws s3 rb "s3://$POLLY_BUCKET_NAME" --force
    
    success "S3 bucket deleted: $POLLY_BUCKET_NAME"
}

# Function to delete pronunciation lexicon
delete_pronunciation_lexicon() {
    log "Deleting pronunciation lexicon..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would delete pronunciation lexicon: tech-terminology"
        return 0
    fi
    
    # Check if lexicon exists
    if aws polly get-lexicon --name tech-terminology &> /dev/null; then
        aws polly delete-lexicon --name tech-terminology
        success "Pronunciation lexicon deleted: tech-terminology"
    else
        warning "Pronunciation lexicon 'tech-terminology' does not exist"
    fi
}

# Function to delete local files
delete_local_files() {
    log "Deleting local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would delete local files"
        return 0
    fi
    
    # Delete sample files
    local files_to_delete=(
        "sample_text.txt"
        "ssml_sample.xml"
        "custom_pronunciation.xml"
        "long_text.txt"
        "*.mp3"
        "*.ogg"
        "*.pcm"
        "deployment-test.mp3"
        "standard-voice-output.mp3"
        "neural-voice-output.mp3"
        "ssml-enhanced-output.mp3"
        "spanish-voice-output.mp3"
        "french-voice-output.mp3"
        "german-voice-output.mp3"
        "web-audio-output.ogg"
        "telephony-audio-output.pcm"
        "custom-pronunciation-output.mp3"
        "comparison-standard.mp3"
        "comparison-neural.mp3"
        "batch-synthesis-result.mp3"
    )
    
    for file_pattern in "${files_to_delete[@]}"; do
        if ls $file_pattern 1> /dev/null 2>&1; then
            rm -f $file_pattern
            log "Deleted: $file_pattern"
        fi
    done
    
    success "Local files cleanup completed"
}

# Function to delete deployment state
delete_deployment_state() {
    log "Deleting deployment state file..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would delete deployment state file"
        return 0
    fi
    
    if [[ -f "polly-deployment-state.env" ]]; then
        rm -f polly-deployment-state.env
        success "Deployment state file deleted"
    else
        warning "No deployment state file found"
    fi
}

# Function to clean up environment variables
cleanup_environment() {
    log "Cleaning up environment variables..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would clean up environment variables"
        return 0
    fi
    
    # Unset environment variables
    unset POLLY_BUCKET_NAME SAMPLE_TEXT_FILE SSML_TEXT_FILE
    unset SYNTHESIS_TASK_ID
    
    success "Environment variables cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would verify cleanup"
        return 0
    fi
    
    local cleanup_success=true
    
    # Check S3 bucket
    if [[ -n "${POLLY_BUCKET_NAME:-}" ]]; then
        if aws s3 ls "s3://$POLLY_BUCKET_NAME" &> /dev/null; then
            error "S3 bucket still exists: $POLLY_BUCKET_NAME"
            cleanup_success=false
        fi
    fi
    
    # Check pronunciation lexicon
    if aws polly get-lexicon --name tech-terminology &> /dev/null; then
        error "Pronunciation lexicon still exists: tech-terminology"
        cleanup_success=false
    fi
    
    # Check local files
    if [[ -f "polly-deployment-state.env" ]]; then
        error "Deployment state file still exists"
        cleanup_success=false
    fi
    
    if [[ "$cleanup_success" == "true" ]]; then
        success "Cleanup verification passed"
    else
        error "Cleanup verification failed - some resources may still exist"
        exit 1
    fi
}

# Function to display cleanup summary
show_cleanup_summary() {
    log "Cleanup Summary:"
    echo "===================="
    echo "S3 Bucket: ${POLLY_BUCKET_NAME:-'Not specified'}"
    echo "Pronunciation Lexicon: tech-terminology"
    echo "Local Files: Cleaned up"
    echo "Deployment State: Removed"
    echo "===================="
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        echo "All resources have been successfully cleaned up."
        echo "Your AWS account will no longer incur charges for these resources."
        echo ""
        echo "Note: Any ongoing synthesis tasks will continue to run until completion."
    fi
}

# Main cleanup function
main() {
    log "Starting Amazon Polly Text-to-Speech cleanup..."
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_state
    confirm_deletion
    delete_s3_bucket
    delete_pronunciation_lexicon
    delete_local_files
    delete_deployment_state
    cleanup_environment
    verify_cleanup
    show_cleanup_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN completed successfully - no resources were deleted"
    else
        success "Cleanup completed successfully!"
        echo ""
        echo "All Amazon Polly Text-to-Speech resources have been removed."
    fi
}

# Trap errors and cleanup
trap 'error "Cleanup failed! Check the error messages above."' ERR

# Run main function
main "$@"