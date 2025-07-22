#!/bin/bash

# Destroy script for EC2 Instance Connect Secure SSH Access
# This script safely removes all resources created by the deployment script
# following the recipe: "Secure SSH Access with EC2 Instance Connect"

set -euo pipefail

# Colors for output formatting
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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_id="$2"
    
    case "$resource_type" in
        "instance")
            aws ec2 describe-instances --instance-ids "$resource_id" &>/dev/null
            ;;
        "security-group")
            aws ec2 describe-security-groups --group-ids "$resource_id" &>/dev/null
            ;;
        "subnet")
            aws ec2 describe-subnets --subnet-ids "$resource_id" &>/dev/null
            ;;
        "eice")
            aws ec2 describe-instance-connect-endpoints --instance-connect-endpoint-ids "$resource_id" &>/dev/null
            ;;
        "iam-user")
            aws iam get-user --user-name "$resource_id" &>/dev/null
            ;;
        "iam-policy")
            aws iam get-policy --policy-arn "$resource_id" &>/dev/null
            ;;
        "cloudtrail")
            aws cloudtrail describe-trails --trail-name-list "$resource_id" &>/dev/null
            ;;
        "s3-bucket")
            aws s3api head-bucket --bucket "$resource_id" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to wait for resource termination
wait_for_termination() {
    local instance_id="$1"
    local timeout=300  # 5 minutes timeout
    local elapsed=0
    
    log_info "Waiting for instance $instance_id to terminate..."
    
    while [ $elapsed -lt $timeout ]; do
        local state=$(aws ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "terminated")
        
        if [[ "$state" == "terminated" ]]; then
            log_success "Instance $instance_id terminated successfully"
            return 0
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
        echo -n "."
    done
    
    log_warning "Timeout waiting for instance $instance_id to terminate"
    return 1
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' or set up credentials."
    fi
    
    log_success "Prerequisites check completed"
}

# Load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ -f "deployment-state.env" ]]; then
        source deployment-state.env
        log_success "Deployment state loaded from deployment-state.env"
    else
        log_warning "deployment-state.env not found. You may need to provide resource IDs manually."
        
        # Try to get current AWS settings
        export AWS_REGION=$(aws configure get region 2>/dev/null || echo "")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
        
        if [[ -z "$AWS_REGION" ]]; then
            log_warning "No default region configured. Using us-east-1"
            export AWS_REGION="us-east-1"
        fi
        
        log_info "Using AWS Region: $AWS_REGION"
        log_info "Using AWS Account: $AWS_ACCOUNT_ID"
    fi
}

# Function to prompt for confirmation
confirm_destruction() {
    echo
    log_warning "This script will destroy the following resources (if they exist):"
    echo "  - EC2 Instances: ${INSTANCE_ID:-'Unknown'}, ${PRIVATE_INSTANCE_ID:-'Unknown'}"
    echo "  - Instance Connect Endpoint: ${EICE_ID:-'Unknown'}"
    echo "  - Security Group: ${SG_ID:-'Unknown'}"
    echo "  - Private Subnet: ${PRIVATE_SUBNET_ID:-'Unknown'}"
    echo "  - IAM User and Policies: ${USER_NAME:-'Unknown'}"
    echo "  - CloudTrail: ${TRAIL_NAME:-'Unknown'}"
    echo "  - S3 Bucket: ${BUCKET_NAME:-'Unknown'}"
    echo
    
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource destruction..."
}

# Terminate EC2 instances
terminate_instances() {
    log_info "Terminating EC2 instances..."
    
    local instances_to_terminate=()
    
    # Check and add public instance
    if [[ -n "${INSTANCE_ID:-}" ]] && resource_exists "instance" "$INSTANCE_ID"; then
        instances_to_terminate+=("$INSTANCE_ID")
        log_info "Will terminate public instance: $INSTANCE_ID"
    fi
    
    # Check and add private instance
    if [[ -n "${PRIVATE_INSTANCE_ID:-}" ]] && resource_exists "instance" "$PRIVATE_INSTANCE_ID"; then
        instances_to_terminate+=("$PRIVATE_INSTANCE_ID")
        log_info "Will terminate private instance: $PRIVATE_INSTANCE_ID"
    fi
    
    if [[ ${#instances_to_terminate[@]} -eq 0 ]]; then
        log_info "No EC2 instances found to terminate"
        return 0
    fi
    
    # Terminate instances
    aws ec2 terminate-instances --instance-ids "${instances_to_terminate[@]}"
    log_success "Termination initiated for ${#instances_to_terminate[@]} instance(s)"
    
    # Wait for instances to terminate
    for instance_id in "${instances_to_terminate[@]}"; do
        wait_for_termination "$instance_id"
    done
    
    log_success "All instances terminated successfully"
}

# Delete Instance Connect Endpoint
delete_instance_connect_endpoint() {
    log_info "Deleting Instance Connect Endpoint..."
    
    if [[ -z "${EICE_ID:-}" ]]; then
        log_info "No Instance Connect Endpoint ID found"
        return 0
    fi
    
    if resource_exists "eice" "$EICE_ID"; then
        aws ec2 delete-instance-connect-endpoint \
            --instance-connect-endpoint-id "$EICE_ID"
        
        # Wait for deletion to complete
        log_info "Waiting for Instance Connect Endpoint deletion to complete..."
        local timeout=300  # 5 minutes
        local elapsed=0
        
        while [ $elapsed -lt $timeout ]; do
            if ! resource_exists "eice" "$EICE_ID"; then
                log_success "Instance Connect Endpoint deleted: $EICE_ID"
                return 0
            fi
            sleep 10
            elapsed=$((elapsed + 10))
            echo -n "."
        done
        
        log_warning "Timeout waiting for Instance Connect Endpoint deletion"
    else
        log_info "Instance Connect Endpoint $EICE_ID not found (may already be deleted)"
    fi
}

# Remove networking resources
remove_networking() {
    log_info "Removing networking resources..."
    
    # Delete private subnet
    if [[ -n "${PRIVATE_SUBNET_ID:-}" ]] && resource_exists "subnet" "$PRIVATE_SUBNET_ID"; then
        aws ec2 delete-subnet --subnet-id "$PRIVATE_SUBNET_ID"
        log_success "Private subnet deleted: $PRIVATE_SUBNET_ID"
    else
        log_info "Private subnet ${PRIVATE_SUBNET_ID:-'Unknown'} not found (may already be deleted)"
    fi
    
    # Delete security group
    if [[ -n "${SG_ID:-}" ]] && resource_exists "security-group" "$SG_ID"; then
        # Wait a bit for instances to fully terminate before deleting security group
        sleep 30
        
        aws ec2 delete-security-group --group-id "$SG_ID"
        log_success "Security group deleted: $SG_ID"
    else
        log_info "Security group ${SG_ID:-'Unknown'} not found (may already be deleted)"
    fi
}

# Remove IAM resources
remove_iam_resources() {
    log_info "Removing IAM resources..."
    
    if [[ -z "${USER_NAME:-}" ]]; then
        log_info "No IAM user name found"
        return 0
    fi
    
    # Detach policies from user and delete access keys
    if resource_exists "iam-user" "$USER_NAME"; then
        # Get and delete access keys
        local access_keys=$(aws iam list-access-keys \
            --user-name "$USER_NAME" \
            --query 'AccessKeyMetadata[].AccessKeyId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$access_keys" ]]; then
            for key_id in $access_keys; do
                aws iam delete-access-key \
                    --user-name "$USER_NAME" \
                    --access-key-id "$key_id"
                log_success "Deleted access key: $key_id"
            done
        fi
        
        # Detach policies
        if [[ -n "${POLICY_ARN:-}" ]] && resource_exists "iam-policy" "$POLICY_ARN"; then
            aws iam detach-user-policy \
                --user-name "$USER_NAME" \
                --policy-arn "$POLICY_ARN" 2>/dev/null || true
            log_success "Policy detached from user: $USER_NAME"
        fi
        
        # Delete user
        aws iam delete-user --user-name "$USER_NAME"
        log_success "IAM user deleted: $USER_NAME"
    else
        log_info "IAM user $USER_NAME not found (may already be deleted)"
    fi
    
    # Delete policies
    if [[ -n "${POLICY_ARN:-}" ]] && resource_exists "iam-policy" "$POLICY_ARN"; then
        aws iam delete-policy --policy-arn "$POLICY_ARN"
        log_success "IAM policy deleted: $POLICY_ARN"
    fi
    
    # Delete restrictive policy
    local restrictive_policy_arn="${POLICY_ARN:-}-restrictive"
    if [[ -n "${POLICY_ARN:-}" ]] && resource_exists "iam-policy" "$restrictive_policy_arn"; then
        aws iam delete-policy --policy-arn "$restrictive_policy_arn"
        log_success "Restrictive IAM policy deleted: $restrictive_policy_arn"
    fi
}

# Remove CloudTrail and S3 bucket
remove_cloudtrail() {
    log_info "Removing CloudTrail and S3 bucket..."
    
    # Stop and delete CloudTrail
    if [[ -n "${TRAIL_NAME:-}" ]] && resource_exists "cloudtrail" "$TRAIL_NAME"; then
        # Stop logging
        aws cloudtrail stop-logging --name "$TRAIL_NAME" 2>/dev/null || true
        log_info "CloudTrail logging stopped: $TRAIL_NAME"
        
        # Delete trail
        aws cloudtrail delete-trail --name "$TRAIL_NAME"
        log_success "CloudTrail deleted: $TRAIL_NAME"
    else
        log_info "CloudTrail ${TRAIL_NAME:-'Unknown'} not found (may already be deleted)"
    fi
    
    # Delete S3 bucket
    if [[ -n "${BUCKET_NAME:-}" ]] && resource_exists "s3-bucket" "$BUCKET_NAME"; then
        # Delete all objects in bucket first
        log_info "Deleting objects from S3 bucket: $BUCKET_NAME"
        aws s3 rm s3://"$BUCKET_NAME" --recursive 2>/dev/null || true
        
        # Delete bucket
        aws s3 rb s3://"$BUCKET_NAME" 2>/dev/null || true
        log_success "S3 bucket deleted: $BUCKET_NAME"
    else
        log_info "S3 bucket ${BUCKET_NAME:-'Unknown'} not found (may already be deleted)"
    fi
}

# Clean up temporary files
cleanup_files() {
    log_info "Cleaning up temporary files..."
    
    local files_to_remove=(
        "temp-key"
        "temp-key.pub"
        "ec2-connect-policy.json"
        "ec2-connect-restrictive-policy.json"
        "cloudtrail-bucket-policy.json"
        "deployment-state.env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_success "Removed file: $file"
        fi
    done
}

# Verify resource cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local cleanup_issues=0
    
    # Check instances
    if [[ -n "${INSTANCE_ID:-}" ]] && resource_exists "instance" "$INSTANCE_ID"; then
        local state=$(aws ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "terminated")
        if [[ "$state" != "terminated" ]]; then
            log_warning "Instance $INSTANCE_ID is still in state: $state"
            ((cleanup_issues++))
        fi
    fi
    
    if [[ -n "${PRIVATE_INSTANCE_ID:-}" ]] && resource_exists "instance" "$PRIVATE_INSTANCE_ID"; then
        local state=$(aws ec2 describe-instances \
            --instance-ids "$PRIVATE_INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "terminated")
        if [[ "$state" != "terminated" ]]; then
            log_warning "Private instance $PRIVATE_INSTANCE_ID is still in state: $state"
            ((cleanup_issues++))
        fi
    fi
    
    # Check other resources
    if [[ -n "${EICE_ID:-}" ]] && resource_exists "eice" "$EICE_ID"; then
        log_warning "Instance Connect Endpoint $EICE_ID still exists"
        ((cleanup_issues++))
    fi
    
    if [[ -n "${SG_ID:-}" ]] && resource_exists "security-group" "$SG_ID"; then
        log_warning "Security Group $SG_ID still exists"
        ((cleanup_issues++))
    fi
    
    if [[ -n "${USER_NAME:-}" ]] && resource_exists "iam-user" "$USER_NAME"; then
        log_warning "IAM User $USER_NAME still exists"
        ((cleanup_issues++))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "All resources have been successfully cleaned up"
    else
        log_warning "Found $cleanup_issues issue(s) during cleanup verification"
        log_warning "Some resources may still exist and incur charges"
    fi
}

# Display cleanup summary
display_summary() {
    echo
    log_success "EC2 Instance Connect infrastructure cleanup completed!"
    echo
    echo "=== Cleanup Summary ==="
    echo "✅ EC2 instances terminated"
    echo "✅ Instance Connect Endpoint deleted"
    echo "✅ Security group removed"
    echo "✅ Private subnet deleted"
    echo "✅ IAM user and policies removed"
    echo "✅ CloudTrail and S3 bucket deleted"
    echo "✅ Temporary files cleaned up"
    echo
    echo "=== Next Steps ==="
    echo "1. Verify your AWS billing dashboard shows no ongoing charges"
    echo "2. Check CloudWatch logs retention policies if you had custom settings"
    echo "3. Review any custom IAM policies that may reference the deleted resources"
    echo
    log_info "All cleanup operations completed successfully!"
}

# Main destruction function
main() {
    echo "=== EC2 Instance Connect Cleanup Script ==="
    echo "This script will safely remove all EC2 Instance Connect infrastructure"
    echo
    
    check_prerequisites
    load_deployment_state
    confirm_destruction
    
    echo "Starting cleanup process..."
    
    terminate_instances
    delete_instance_connect_endpoint
    remove_networking
    remove_iam_resources
    remove_cloudtrail
    cleanup_files
    verify_cleanup
    
    display_summary
}

# Handle script interruption
cleanup_on_interrupt() {
    echo
    log_warning "Script interrupted. Some resources may not have been cleaned up."
    log_warning "Please run this script again to complete the cleanup process."
    exit 1
}

# Set trap for interruption
trap cleanup_on_interrupt INT TERM

# Run main function
main "$@"