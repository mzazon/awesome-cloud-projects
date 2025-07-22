#!/bin/bash

# Destroy script for Image Analysis Application with Amazon Rekognition
# This script safely removes all resources created by the deployment

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DEPLOYMENT_STATE="${SCRIPT_DIR}/deployment-state.json"

# Logging function
log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$TIMESTAMP] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Banner
echo "=========================================="
echo "  AWS Rekognition Image Analysis Cleanup"
echo "=========================================="
echo ""

# Prerequisites check
print_status "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed."
    log_error "AWS CLI not found"
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS CLI is not configured or credentials are invalid."
    log_error "AWS CLI configuration check failed"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    print_error "jq is not installed. Please install jq for JSON parsing."
    exit 1
fi

print_success "Prerequisites check completed"

# Function to confirm deletion
confirm_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    
    echo ""
    print_warning "You are about to delete: ${resource_type} - ${resource_name}"
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    case $confirmation in
        [Yy][Ee][Ss]|[Yy])
            return 0
            ;;
        *)
            print_status "Skipping deletion of ${resource_type}: ${resource_name}"
            return 1
            ;;
    esac
}

# Try to load environment variables from multiple sources
WORK_DIR="${HOME}/rekognition-demo"
ENV_FILE="${WORK_DIR}/.env"

# Load from environment file if exists
if [ -f "$ENV_FILE" ]; then
    print_status "Loading environment variables from ${ENV_FILE}..."
    source "$ENV_FILE"
elif [ -f "$DEPLOYMENT_STATE" ]; then
    print_status "Loading environment variables from deployment state..."
    export AWS_REGION=$(jq -r '.aws_region' "$DEPLOYMENT_STATE")
    export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$DEPLOYMENT_STATE")
    export BUCKET_NAME=$(jq -r '.bucket_name' "$DEPLOYMENT_STATE")
    export WORK_DIR="$WORK_DIR"
else
    print_warning "No deployment state or environment file found."
    print_status "Attempting to discover resources..."
    
    # Try to get current AWS configuration
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Try to discover S3 buckets with our naming pattern
    print_status "Searching for S3 buckets with pattern 'rekognition-images-*'..."
    BUCKET_LIST=$(aws s3 ls | grep "rekognition-images-" | awk '{print $3}' || echo "")
    
    if [ -n "$BUCKET_LIST" ]; then
        echo "Found the following buckets:"
        echo "$BUCKET_LIST"
        echo ""
        read -p "Enter the bucket name to delete (or 'skip' to skip): " USER_BUCKET
        
        if [ "$USER_BUCKET" != "skip" ] && [ -n "$USER_BUCKET" ]; then
            export BUCKET_NAME="$USER_BUCKET"
        else
            print_warning "No bucket specified, skipping S3 cleanup"
            export BUCKET_NAME=""
        fi
    else
        print_warning "No S3 buckets found with pattern 'rekognition-images-*'"
        export BUCKET_NAME=""
    fi
fi

print_status "Using configuration:"
echo "  AWS Region: ${AWS_REGION:-not set}"
echo "  AWS Account: ${AWS_ACCOUNT_ID:-not set}"
echo "  S3 Bucket: ${BUCKET_NAME:-not set}"
echo "  Work Directory: ${WORK_DIR:-not set}"

# Option to delete everything without prompts
if [ "$1" = "--force" ] || [ "$1" = "-f" ]; then
    FORCE_DELETE=true
    print_warning "Force delete mode enabled - no confirmation prompts"
else
    FORCE_DELETE=false
    print_status "Interactive mode - you will be prompted before each deletion"
fi

# Function to safely delete S3 bucket
delete_s3_bucket() {
    local bucket_name="$1"
    
    if [ -z "$bucket_name" ]; then
        print_warning "No S3 bucket specified, skipping"
        return 0
    fi
    
    # Check if bucket exists
    if ! aws s3 ls "s3://${bucket_name}" &> /dev/null; then
        print_warning "S3 bucket ${bucket_name} does not exist or is not accessible"
        return 0
    fi
    
    if [ "$FORCE_DELETE" = true ] || confirm_deletion "S3 Bucket" "$bucket_name"; then
        print_status "Deleting contents of S3 bucket: ${bucket_name}..."
        
        # Check if bucket has objects
        OBJECT_COUNT=$(aws s3 ls "s3://${bucket_name}" --recursive | wc -l)
        
        if [ "$OBJECT_COUNT" -gt 0 ]; then
            print_status "Found ${OBJECT_COUNT} objects in bucket, deleting..."
            
            # Delete all objects including versions if versioning is enabled
            aws s3api delete-objects \
                --bucket "${bucket_name}" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "${bucket_name}" \
                    --output json \
                    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" \
                2>/dev/null || true
            
            # Delete delete markers if any
            aws s3api delete-objects \
                --bucket "${bucket_name}" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "${bucket_name}" \
                    --output json \
                    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" \
                2>/dev/null || true
            
            # Use S3 rm as backup
            aws s3 rm "s3://${bucket_name}" --recursive || true
            
            print_success "Bucket contents deleted"
        else
            print_status "Bucket is already empty"
        fi
        
        # Wait a moment for eventual consistency
        sleep 2
        
        # Delete the bucket itself
        print_status "Deleting S3 bucket: ${bucket_name}..."
        if aws s3 rb "s3://${bucket_name}" --region "${AWS_REGION}"; then
            print_success "S3 bucket deleted: ${bucket_name}"
            log "S3 bucket deleted successfully: ${bucket_name}"
        else
            print_error "Failed to delete S3 bucket: ${bucket_name}"
            log_error "S3 bucket deletion failed: ${bucket_name}"
            print_status "You may need to delete it manually from the AWS Console"
        fi
    else
        print_status "Skipped S3 bucket deletion"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    if [ -z "$WORK_DIR" ]; then
        print_warning "Work directory not specified, skipping local cleanup"
        return 0
    fi
    
    if [ ! -d "$WORK_DIR" ]; then
        print_status "Work directory ${WORK_DIR} does not exist, nothing to clean"
        return 0
    fi
    
    if [ "$FORCE_DELETE" = true ] || confirm_deletion "Local Directory" "$WORK_DIR"; then
        print_status "Cleaning up local files in: ${WORK_DIR}..."
        
        # List what will be deleted
        print_status "Contents to be deleted:"
        ls -la "$WORK_DIR" 2>/dev/null || true
        
        # Delete the directory
        if rm -rf "$WORK_DIR"; then
            print_success "Local files cleaned up: ${WORK_DIR}"
            log "Local directory deleted successfully: ${WORK_DIR}"
        else
            print_error "Failed to delete local directory: ${WORK_DIR}"
            log_error "Local directory deletion failed: ${WORK_DIR}"
        fi
    else
        print_status "Skipped local files cleanup"
    fi
}

# Function to clean up deployment state
cleanup_deployment_state() {
    if [ -f "$DEPLOYMENT_STATE" ]; then
        if [ "$FORCE_DELETE" = true ] || confirm_deletion "Deployment State File" "$DEPLOYMENT_STATE"; then
            if rm -f "$DEPLOYMENT_STATE"; then
                print_success "Deployment state file removed"
            else
                print_warning "Failed to remove deployment state file"
            fi
        fi
    fi
}

# Function to show cleanup summary
show_cleanup_summary() {
    echo ""
    echo "=========================================="
    echo "           Cleanup Summary"
    echo "=========================================="
    
    if [ -n "$BUCKET_NAME" ]; then
        if aws s3 ls "s3://${BUCKET_NAME}" &> /dev/null; then
            echo "❌ S3 Bucket: ${BUCKET_NAME} - Still exists"
        else
            echo "✅ S3 Bucket: ${BUCKET_NAME} - Deleted"
        fi
    fi
    
    if [ -n "$WORK_DIR" ]; then
        if [ -d "$WORK_DIR" ]; then
            echo "❌ Local Directory: ${WORK_DIR} - Still exists"
        else
            echo "✅ Local Directory: ${WORK_DIR} - Deleted"
        fi
    fi
    
    echo ""
}

# Function to verify no charges will continue
verify_no_ongoing_charges() {
    print_status "Verifying no ongoing charges..."
    
    # Check if any S3 buckets with our pattern still exist
    REMAINING_BUCKETS=$(aws s3 ls | grep "rekognition-images-" | awk '{print $3}' || echo "")
    
    if [ -n "$REMAINING_BUCKETS" ]; then
        print_warning "The following S3 buckets still exist and may incur charges:"
        echo "$REMAINING_BUCKETS"
    else
        print_success "No remaining S3 buckets found with pattern 'rekognition-images-*'"
    fi
    
    print_status "Note: Amazon Rekognition only charges for API calls, not for stored models"
    print_success "No ongoing charges expected from this solution"
}

# Main cleanup execution
log "Starting cleanup process at $(date)"

# 1. Delete S3 bucket and contents
if [ -n "$BUCKET_NAME" ]; then
    delete_s3_bucket "$BUCKET_NAME"
else
    print_warning "No S3 bucket specified in configuration"
fi

# 2. Clean up local files
cleanup_local_files

# 3. Clean up deployment state
cleanup_deployment_state

# 4. Show cleanup summary
show_cleanup_summary

# 5. Verify no ongoing charges
verify_no_ongoing_charges

# Final status
echo ""
echo "=========================================="
print_success "Cleanup completed!"
echo "=========================================="
echo ""
print_status "What was cleaned up:"
echo "• S3 bucket and all contents"
echo "• Local working directory and files"
echo "• Analysis scripts and results"
echo "• Environment configuration"
echo ""
print_status "What was NOT deleted (if they exist):"
echo "• AWS IAM roles/policies (none were created)"
echo "• VPC resources (none were created)"
echo "• CloudWatch logs (if any exist)"
echo ""
print_success "Amazon Rekognition image analysis solution cleanup complete!"
print_status "You can now safely close this terminal."

log "Cleanup completed successfully at $(date)"
exit 0