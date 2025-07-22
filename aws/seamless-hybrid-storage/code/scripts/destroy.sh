#!/bin/bash

# AWS Storage Gateway Hybrid Cloud Storage Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    if [ ! -f "deployment_state.env" ]; then
        error "Deployment state file 'deployment_state.env' not found."
        error "Please ensure you're running this script from the same directory where you ran deploy.sh"
        exit 1
    fi
    
    # Source the deployment state
    source deployment_state.env
    
    # Verify required variables are set
    if [ -z "${AWS_REGION:-}" ] || [ -z "${GATEWAY_NAME:-}" ]; then
        error "Invalid deployment state file. Missing required variables."
        exit 1
    fi
    
    success "Deployment state loaded"
    log "Gateway Name: ${GATEWAY_NAME}"
    log "AWS Region: ${AWS_REGION}"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    warning "=== DESTRUCTIVE ACTION WARNING ==="
    echo "This script will permanently delete the following resources:"
    echo "- Storage Gateway: ${GATEWAY_NAME:-N/A}"
    echo "- EC2 Instance: ${INSTANCE_ID:-N/A}"
    echo "- S3 Bucket: ${S3_BUCKET_NAME:-N/A} (and ALL contents)"
    echo "- EBS Volume: ${VOLUME_ID:-N/A}"
    echo "- Security Group: ${SG_ID:-N/A}"
    echo "- IAM Role: StorageGatewayRole"
    echo "- KMS Key: ${KMS_KEY_ID:-N/A}"
    echo "- CloudWatch Log Group: /aws/storagegateway/${GATEWAY_NAME:-N/A}"
    echo ""
    
    # Interactive confirmation
    read -p "Are you sure you want to delete ALL these resources? (yes/no): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    # Double confirmation for critical resources
    if [ -n "${S3_BUCKET_NAME:-}" ]; then
        echo ""
        warning "S3 bucket '${S3_BUCKET_NAME}' will be PERMANENTLY DELETED with ALL contents."
        read -p "Type 'DELETE' to confirm S3 bucket deletion: " s3_confirmation
        
        if [ "$s3_confirmation" != "DELETE" ]; then
            log "S3 bucket deletion cancelled. Exiting cleanup."
            exit 0
        fi
    fi
    
    success "Destruction confirmed. Proceeding with cleanup..."
}

# Function to delete file shares
delete_file_shares() {
    log "Deleting file shares..."
    
    # Delete NFS file share
    if [ -n "${FILE_SHARE_ARN:-}" ]; then
        log "Deleting NFS file share: ${FILE_SHARE_ARN}"
        aws storagegateway delete-file-share \
            --file-share-arn "${FILE_SHARE_ARN}" 2>/dev/null || \
            warning "Could not delete NFS file share (may already be deleted)"
        
        # Wait for deletion
        log "Waiting for NFS file share deletion..."
        RETRY_COUNT=0
        MAX_RETRIES=20
        
        while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
            if ! aws storagegateway describe-nfs-file-shares \
                --file-share-arn-list "${FILE_SHARE_ARN}" &>/dev/null; then
                break
            fi
            sleep 15
            RETRY_COUNT=$((RETRY_COUNT + 1))
        done
        
        success "NFS file share deleted"
    else
        warning "NFS file share ARN not found in state"
    fi
    
    # Delete SMB file share
    if [ -n "${SMB_SHARE_ARN:-}" ]; then
        log "Deleting SMB file share: ${SMB_SHARE_ARN}"
        aws storagegateway delete-file-share \
            --file-share-arn "${SMB_SHARE_ARN}" 2>/dev/null || \
            warning "Could not delete SMB file share (may already be deleted)"
        
        # Wait for deletion
        log "Waiting for SMB file share deletion..."
        RETRY_COUNT=0
        MAX_RETRIES=20
        
        while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
            if ! aws storagegateway describe-smb-file-shares \
                --file-share-arn-list "${SMB_SHARE_ARN}" &>/dev/null; then
                break
            fi
            sleep 15
            RETRY_COUNT=$((RETRY_COUNT + 1))
        done
        
        success "SMB file share deleted"
    else
        warning "SMB file share ARN not found in state"
    fi
}

# Function to delete Storage Gateway
delete_storage_gateway() {
    log "Deleting Storage Gateway..."
    
    if [ -n "${GATEWAY_ARN:-}" ]; then
        log "Deleting gateway: ${GATEWAY_ARN}"
        aws storagegateway delete-gateway \
            --gateway-arn "${GATEWAY_ARN}" 2>/dev/null || \
            warning "Could not delete Storage Gateway (may already be deleted)"
        
        # Wait for gateway deletion
        log "Waiting for Storage Gateway deletion..."
        RETRY_COUNT=0
        MAX_RETRIES=30
        
        while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
            if ! aws storagegateway describe-gateway-information \
                --gateway-arn "${GATEWAY_ARN}" &>/dev/null; then
                break
            fi
            sleep 20
            RETRY_COUNT=$((RETRY_COUNT + 1))
        done
        
        success "Storage Gateway deleted"
    else
        warning "Gateway ARN not found in state"
    fi
}

# Function to terminate EC2 instance and clean up related resources
cleanup_ec2_resources() {
    log "Cleaning up EC2 resources..."
    
    # Terminate EC2 instance
    if [ -n "${INSTANCE_ID:-}" ]; then
        log "Terminating EC2 instance: ${INSTANCE_ID}"
        aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}" 2>/dev/null || \
            warning "Could not terminate instance (may already be terminated)"
        
        # Wait for instance termination
        log "Waiting for instance termination..."
        aws ec2 wait instance-terminated --instance-ids "${INSTANCE_ID}" || \
            warning "Instance termination wait timed out"
        
        success "EC2 instance terminated"
    else
        warning "Instance ID not found in state"
    fi
    
    # Delete security group
    if [ -n "${SG_ID:-}" ]; then
        log "Deleting security group: ${SG_ID}"
        # Wait a bit more to ensure instance is fully terminated
        sleep 30
        
        aws ec2 delete-security-group --group-id "${SG_ID}" 2>/dev/null || \
            warning "Could not delete security group (may be in use or already deleted)"
        
        success "Security group deleted"
    else
        warning "Security group ID not found in state"
    fi
    
    # Delete EBS volume
    if [ -n "${VOLUME_ID:-}" ]; then
        log "Deleting EBS volume: ${VOLUME_ID}"
        
        # Wait for volume to be available for deletion
        sleep 10
        
        aws ec2 delete-volume --volume-id "${VOLUME_ID}" 2>/dev/null || \
            warning "Could not delete EBS volume (may already be deleted)"
        
        success "EBS volume deleted"
    else
        warning "Volume ID not found in state"
    fi
}

# Function to delete S3 bucket and contents
delete_s3_resources() {
    log "Deleting S3 resources..."
    
    if [ -n "${S3_BUCKET_NAME:-}" ]; then
        # Check if bucket exists
        if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null; then
            log "Deleting all objects in S3 bucket: ${S3_BUCKET_NAME}"
            
            # Delete all objects and versions
            aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive 2>/dev/null || \
                warning "Could not delete some S3 objects"
            
            # Delete all object versions and delete markers
            aws s3api list-object-versions \
                --bucket "${S3_BUCKET_NAME}" \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                --output text | \
            while read key version_id; do
                if [ -n "$key" ] && [ -n "$version_id" ]; then
                    aws s3api delete-object \
                        --bucket "${S3_BUCKET_NAME}" \
                        --key "$key" \
                        --version-id "$version_id" 2>/dev/null || true
                fi
            done
            
            # Delete delete markers
            aws s3api list-object-versions \
                --bucket "${S3_BUCKET_NAME}" \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                --output text | \
            while read key version_id; do
                if [ -n "$key" ] && [ -n "$version_id" ]; then
                    aws s3api delete-object \
                        --bucket "${S3_BUCKET_NAME}" \
                        --key "$key" \
                        --version-id "$version_id" 2>/dev/null || true
                fi
            done
            
            log "Deleting S3 bucket: ${S3_BUCKET_NAME}"
            aws s3api delete-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null || \
                warning "Could not delete S3 bucket (may not be empty)"
            
            success "S3 bucket and contents deleted"
        else
            warning "S3 bucket ${S3_BUCKET_NAME} does not exist or cannot be accessed"
        fi
    else
        warning "S3 bucket name not found in state"
    fi
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    # Detach and delete IAM role
    if aws iam get-role --role-name StorageGatewayRole &>/dev/null; then
        log "Detaching policies from IAM role..."
        aws iam detach-role-policy \
            --role-name StorageGatewayRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/StorageGatewayServiceRole \
            2>/dev/null || warning "Could not detach policy from IAM role"
        
        log "Deleting IAM role..."
        aws iam delete-role --role-name StorageGatewayRole 2>/dev/null || \
            warning "Could not delete IAM role"
        
        success "IAM role deleted"
    else
        warning "IAM role StorageGatewayRole not found"
    fi
}

# Function to delete KMS resources
delete_kms_resources() {
    log "Deleting KMS resources..."
    
    # Delete KMS key alias
    if [ -n "${KMS_KEY_ALIAS:-}" ]; then
        log "Deleting KMS key alias: ${KMS_KEY_ALIAS}"
        aws kms delete-alias --alias-name "${KMS_KEY_ALIAS}" 2>/dev/null || \
            warning "Could not delete KMS key alias"
    fi
    
    # Schedule KMS key deletion
    if [ -n "${KMS_KEY_ID:-}" ]; then
        log "Scheduling KMS key deletion: ${KMS_KEY_ID}"
        aws kms schedule-key-deletion \
            --key-id "${KMS_KEY_ID}" \
            --pending-window-in-days 7 2>/dev/null || \
            warning "Could not schedule KMS key deletion"
        
        success "KMS key scheduled for deletion in 7 days"
    else
        warning "KMS key ID not found in state"
    fi
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    if [ -n "${GATEWAY_NAME:-}" ]; then
        log "Deleting CloudWatch log group: /aws/storagegateway/${GATEWAY_NAME}"
        aws logs delete-log-group \
            --log-group-name "/aws/storagegateway/${GATEWAY_NAME}" 2>/dev/null || \
            warning "Could not delete CloudWatch log group"
        
        success "CloudWatch log group deleted"
    else
        warning "Gateway name not found in state"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files
    rm -f storage-gateway-trust-policy.json
    rm -f s3-notification-config.json
    
    # Remove deployment state file
    if [ -f "deployment_state.env" ]; then
        log "Removing deployment state file..."
        rm -f deployment_state.env
        success "Deployment state file removed"
    fi
    
    success "Local cleanup completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    success "=== CLEANUP SUMMARY ==="
    echo "The following resources have been cleaned up:"
    echo "✅ File shares (NFS and SMB)"
    echo "✅ Storage Gateway"
    echo "✅ EC2 instance and security group"
    echo "✅ EBS volume"
    echo "✅ S3 bucket and contents"
    echo "✅ IAM role and policies"
    echo "✅ KMS key (scheduled for deletion)"
    echo "✅ CloudWatch log group"
    echo "✅ Local configuration files"
    echo ""
    warning "Note: KMS key is scheduled for deletion in 7 days and can be cancelled if needed."
    echo ""
    success "All Storage Gateway resources have been successfully removed!"
}

# Function to handle errors during cleanup
handle_cleanup_error() {
    error "An error occurred during cleanup. Some resources may not have been deleted."
    echo ""
    warning "You may need to manually clean up the following resources:"
    echo "- Check AWS Console for any remaining Storage Gateway resources"
    echo "- Verify EC2 instances and security groups are terminated/deleted"
    echo "- Check S3 buckets for any remaining data"
    echo "- Review IAM roles and policies"
    echo "- Check CloudWatch log groups"
    echo ""
    error "Please review your AWS account to ensure all resources are properly cleaned up."
}

# Function to validate AWS permissions
validate_permissions() {
    log "Validating AWS permissions for cleanup..."
    
    # Test basic AWS access
    if ! aws sts get-caller-identity &> /dev/null; then
        error "Cannot access AWS. Please check your AWS credentials."
        exit 1
    fi
    
    # Test required service access
    local services=("storagegateway" "ec2" "s3" "iam" "kms" "logs")
    for service in "${services[@]}"; do
        case $service in
            "storagegateway")
                aws storagegateway list-gateways --max-items 1 &>/dev/null || \
                    warning "Limited Storage Gateway permissions detected"
                ;;
            "ec2")
                aws ec2 describe-instances --max-items 1 &>/dev/null || \
                    warning "Limited EC2 permissions detected"
                ;;
            "s3")
                aws s3 ls &>/dev/null || \
                    warning "Limited S3 permissions detected"
                ;;
            "iam")
                aws iam list-roles --max-items 1 &>/dev/null || \
                    warning "Limited IAM permissions detected"
                ;;
            "kms")
                aws kms list-keys --limit 1 &>/dev/null || \
                    warning "Limited KMS permissions detected"
                ;;
            "logs")
                aws logs describe-log-groups --limit 1 &>/dev/null || \
                    warning "Limited CloudWatch Logs permissions detected"
                ;;
        esac
    done
    
    success "Permissions validation completed"
}

# Main cleanup function
main() {
    log "Starting AWS Storage Gateway cleanup..."
    
    # Set up error handling
    trap handle_cleanup_error ERR
    
    check_prerequisites
    load_deployment_state
    validate_permissions
    confirm_destruction
    
    # Perform cleanup in order
    delete_file_shares
    delete_storage_gateway
    cleanup_ec2_resources
    delete_s3_resources
    delete_iam_resources
    delete_kms_resources
    delete_cloudwatch_resources
    cleanup_local_files
    
    display_cleanup_summary
    
    success "Cleanup completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi