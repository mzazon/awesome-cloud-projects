#!/bin/bash

# Destroy script for Computer Vision Applications with Amazon Rekognition
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Required command '$1' not found. Please install it before running this script."
        exit 1
    fi
}

# Function to check AWS credentials
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid. Please configure AWS CLI first."
        exit 1
    fi
}

# Function to load deployment state
load_deployment_state() {
    local state_file="$HOME/computer-vision-demo/deployment-state.json"
    
    if [ ! -f "$state_file" ]; then
        warn "Deployment state file not found at $state_file"
        warn "You may need to manually specify resource names or clean up resources manually"
        return 1
    fi
    
    # Extract values from state file
    export AWS_REGION=$(jq -r '.aws_region' "$state_file")
    export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$state_file")
    export S3_BUCKET_NAME=$(jq -r '.s3_bucket_name' "$state_file")
    export FACE_COLLECTION_NAME=$(jq -r '.face_collection_name' "$state_file")
    export KVS_STREAM_NAME=$(jq -r '.kvs_stream_name' "$state_file")
    export KDS_STREAM_NAME=$(jq -r '.kds_stream_name' "$state_file")
    export RANDOM_SUFFIX=$(jq -r '.random_suffix' "$state_file")
    
    log "Loaded deployment state from $state_file"
    return 0
}

# Function to prompt for user confirmation
confirm_destruction() {
    echo ""
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo ""
    echo "  • S3 Bucket: ${S3_BUCKET_NAME} (and all contents)"
    echo "  • Face Collection: ${FACE_COLLECTION_NAME}"
    echo "  • Kinesis Video Stream: ${KVS_STREAM_NAME}"
    echo "  • Kinesis Data Stream: ${KDS_STREAM_NAME}"
    echo "  • IAM Role: RekognitionVideoAnalysisRole"
    echo "  • Stream Processor: face-search-processor-${RANDOM_SUFFIX}"
    echo "  • Local directory: $HOME/computer-vision-demo"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    if [ "${FORCE_DESTROY:-false}" = "true" ]; then
        log "Force destroy mode enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        echo "Destruction cancelled by user"
        exit 0
    fi
}

# Function to delete stream processor
delete_stream_processor() {
    log "Deleting Rekognition stream processor..."
    
    local processor_name="face-search-processor-${RANDOM_SUFFIX}"
    
    # Check if stream processor exists
    if ! aws rekognition list-stream-processors --query "StreamProcessors[?Name=='${processor_name}']" --output text | grep -q "${processor_name}"; then
        warn "Stream processor '${processor_name}' not found. Skipping deletion."
        return 0
    fi
    
    # Stop stream processor if running
    local processor_status
    processor_status=$(aws rekognition describe-stream-processor \
        --name "${processor_name}" \
        --query 'Status' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$processor_status" = "RUNNING" ]; then
        log "Stopping stream processor..."
        aws rekognition stop-stream-processor --name "${processor_name}" --region "$AWS_REGION"
        
        # Wait for processor to stop
        local max_wait=60
        local wait_count=0
        while [ $wait_count -lt $max_wait ]; do
            processor_status=$(aws rekognition describe-stream-processor \
                --name "${processor_name}" \
                --query 'Status' --output text 2>/dev/null || echo "STOPPED")
            
            if [ "$processor_status" = "STOPPED" ]; then
                break
            fi
            
            sleep 2
            ((wait_count++))
        done
    fi
    
    # Delete stream processor
    aws rekognition delete-stream-processor \
        --name "${processor_name}" \
        --region "$AWS_REGION" 2>/dev/null || \
        warn "Failed to delete stream processor '${processor_name}'"
    
    success "Stream processor deleted"
}

# Function to delete Kinesis streams
delete_kinesis_streams() {
    log "Deleting Kinesis streams..."
    
    # Delete Kinesis Video Stream
    if aws kinesisvideo describe-stream --stream-name "${KVS_STREAM_NAME}" &> /dev/null; then
        local kvs_arn
        kvs_arn=$(aws kinesisvideo describe-stream \
            --stream-name "${KVS_STREAM_NAME}" \
            --query 'StreamInfo.StreamARN' --output text 2>/dev/null || echo "")
        
        if [ -n "$kvs_arn" ]; then
            aws kinesisvideo delete-stream \
                --stream-arn "$kvs_arn" \
                --region "$AWS_REGION" 2>/dev/null || \
                warn "Failed to delete Kinesis Video Stream '${KVS_STREAM_NAME}'"
            success "Kinesis Video Stream deleted: ${KVS_STREAM_NAME}"
        fi
    else
        warn "Kinesis Video Stream '${KVS_STREAM_NAME}' not found. Skipping deletion."
    fi
    
    # Delete Kinesis Data Stream
    if aws kinesis describe-stream --stream-name "${KDS_STREAM_NAME}" &> /dev/null; then
        aws kinesis delete-stream \
            --stream-name "${KDS_STREAM_NAME}" \
            --region "$AWS_REGION" 2>/dev/null || \
            warn "Failed to delete Kinesis Data Stream '${KDS_STREAM_NAME}'"
        success "Kinesis Data Stream deleted: ${KDS_STREAM_NAME}"
    else
        warn "Kinesis Data Stream '${KDS_STREAM_NAME}' not found. Skipping deletion."
    fi
}

# Function to delete face collection
delete_face_collection() {
    log "Deleting Rekognition face collection..."
    
    # Check if collection exists
    if ! aws rekognition describe-collection --collection-id "${FACE_COLLECTION_NAME}" &> /dev/null; then
        warn "Face collection '${FACE_COLLECTION_NAME}' not found. Skipping deletion."
        return 0
    fi
    
    # Delete the face collection
    aws rekognition delete-collection \
        --collection-id "${FACE_COLLECTION_NAME}" \
        --region "$AWS_REGION" 2>/dev/null || \
        warn "Failed to delete face collection '${FACE_COLLECTION_NAME}'"
    
    success "Face collection deleted: ${FACE_COLLECTION_NAME}"
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log "Deleting S3 bucket and all contents..."
    
    # Check if bucket exists
    if ! aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
        warn "S3 bucket '${S3_BUCKET_NAME}' not found. Skipping deletion."
        return 0
    fi
    
    # Delete all objects in the bucket (including versioned objects)
    log "Removing all objects from S3 bucket..."
    aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive 2>/dev/null || \
        warn "Some objects may not have been deleted from S3 bucket"
    
    # Delete any incomplete multipart uploads
    aws s3api list-multipart-uploads --bucket "${S3_BUCKET_NAME}" \
        --query 'Uploads[].{Key:Key,UploadId:UploadId}' --output text 2>/dev/null | \
        while read -r key upload_id; do
            if [ -n "$key" ] && [ -n "$upload_id" ]; then
                aws s3api abort-multipart-upload \
                    --bucket "${S3_BUCKET_NAME}" \
                    --key "$key" \
                    --upload-id "$upload_id" 2>/dev/null || true
            fi
        done
    
    # Delete the bucket
    aws s3 rb "s3://${S3_BUCKET_NAME}" --force 2>/dev/null || \
        warn "Failed to delete S3 bucket '${S3_BUCKET_NAME}'"
    
    success "S3 bucket deleted: ${S3_BUCKET_NAME}"
}

# Function to delete IAM role
delete_iam_role() {
    log "Deleting IAM role..."
    
    local role_name="RekognitionVideoAnalysisRole"
    
    # Check if role exists
    if ! aws iam get-role --role-name "$role_name" &> /dev/null; then
        warn "IAM role '$role_name' not found. Skipping deletion."
        return 0
    fi
    
    # Detach all managed policies from the role
    local attached_policies
    attached_policies=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    
    for policy_arn in $attached_policies; do
        if [ -n "$policy_arn" ]; then
            aws iam detach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$policy_arn" 2>/dev/null || \
                warn "Failed to detach policy '$policy_arn' from role '$role_name'"
        fi
    done
    
    # Delete any inline policies
    local inline_policies
    inline_policies=$(aws iam list-role-policies \
        --role-name "$role_name" \
        --query 'PolicyNames' --output text 2>/dev/null || echo "")
    
    for policy_name in $inline_policies; do
        if [ -n "$policy_name" ]; then
            aws iam delete-role-policy \
                --role-name "$role_name" \
                --policy-name "$policy_name" 2>/dev/null || \
                warn "Failed to delete inline policy '$policy_name' from role '$role_name'"
        fi
    done
    
    # Delete the role
    aws iam delete-role --role-name "$role_name" 2>/dev/null || \
        warn "Failed to delete IAM role '$role_name'"
    
    success "IAM role deleted: $role_name"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local demo_dir="$HOME/computer-vision-demo"
    
    if [ -d "$demo_dir" ]; then
        rm -rf "$demo_dir"
        success "Local directory removed: $demo_dir"
    else
        warn "Local directory not found: $demo_dir"
    fi
    
    # Clean up any temporary files
    rm -f /tmp/trust-policy.json 2>/dev/null || true
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_issues=0
    
    # Check S3 bucket
    if aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
        warn "S3 bucket still exists: ${S3_BUCKET_NAME}"
        ((cleanup_issues++))
    fi
    
    # Check face collection
    if aws rekognition describe-collection --collection-id "${FACE_COLLECTION_NAME}" &> /dev/null; then
        warn "Face collection still exists: ${FACE_COLLECTION_NAME}"
        ((cleanup_issues++))
    fi
    
    # Check Kinesis streams
    if aws kinesis describe-stream --stream-name "${KDS_STREAM_NAME}" &> /dev/null; then
        warn "Kinesis Data Stream still exists: ${KDS_STREAM_NAME}"
        ((cleanup_issues++))
    fi
    
    if aws kinesisvideo describe-stream --stream-name "${KVS_STREAM_NAME}" &> /dev/null; then
        warn "Kinesis Video Stream still exists: ${KVS_STREAM_NAME}"
        ((cleanup_issues++))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "RekognitionVideoAnalysisRole" &> /dev/null; then
        warn "IAM role still exists: RekognitionVideoAnalysisRole"
        ((cleanup_issues++))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        success "All resources have been successfully cleaned up"
    else
        warn "$cleanup_issues resources may require manual cleanup"
    fi
    
    return $cleanup_issues
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "================================================"
    echo "🧹 CLEANUP COMPLETED"
    echo "================================================"
    echo ""
    echo "Resources removed:"
    echo "  • S3 Bucket: ${S3_BUCKET_NAME}"
    echo "  • Face Collection: ${FACE_COLLECTION_NAME}"
    echo "  • Kinesis Video Stream: ${KVS_STREAM_NAME}"
    echo "  • Kinesis Data Stream: ${KDS_STREAM_NAME}"
    echo "  • IAM Role: RekognitionVideoAnalysisRole"
    echo "  • Stream Processor: face-search-processor-${RANDOM_SUFFIX}"
    echo "  • Local directory: $HOME/computer-vision-demo"
    echo ""
    echo "All resources have been removed from your AWS account."
    echo "No further charges should be incurred from this recipe."
    echo ""
}

# Main cleanup function
main() {
    echo "🧹 Starting cleanup of Computer Vision Applications with Amazon Rekognition"
    echo ""
    
    # Prerequisites check
    log "Checking prerequisites..."
    check_command "aws"
    check_command "jq"
    check_aws_credentials
    
    # Load deployment state or set defaults
    if ! load_deployment_state; then
        error "Unable to load deployment state. Please ensure you have the deployment state file or manually specify resource names."
        echo ""
        echo "If you know the resource names, you can set them manually:"
        echo "  export S3_BUCKET_NAME=\"your-bucket-name\""
        echo "  export FACE_COLLECTION_NAME=\"your-collection-name\""
        echo "  export KVS_STREAM_NAME=\"your-kvs-stream-name\""
        echo "  export KDS_STREAM_NAME=\"your-kds-stream-name\""
        echo "  export RANDOM_SUFFIX=\"your-suffix\""
        echo "  export AWS_REGION=\"your-region\""
        echo ""
        exit 1
    fi
    
    log "Using AWS Region: ${AWS_REGION}"
    log "Using AWS Account: ${AWS_ACCOUNT_ID}"
    log "Random Suffix: ${RANDOM_SUFFIX}"
    
    # Confirm destruction
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_stream_processor
    delete_kinesis_streams
    delete_face_collection
    delete_s3_bucket
    delete_iam_role
    cleanup_local_files
    
    # Verify cleanup
    if verify_cleanup; then
        display_cleanup_summary
    else
        echo ""
        echo "⚠️  Some resources may require manual cleanup."
        echo "Please check the AWS console to ensure all resources are removed."
        echo ""
    fi
}

# Error handler
error_handler() {
    error "Cleanup failed on line $1"
    echo ""
    echo "Some resources may not have been cleaned up properly."
    echo "Please check the AWS console and remove any remaining resources manually."
    echo ""
    exit 1
}

# Set up error handling
trap 'error_handler $LINENO' ERR

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--force] [--help]"
            echo ""
            echo "Options:"
            echo "  --force    Skip confirmation prompt"
            echo "  --help     Show this help message"
            echo ""
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"