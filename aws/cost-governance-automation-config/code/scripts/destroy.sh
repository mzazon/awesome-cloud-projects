#!/bin/bash

# Automated Cost Governance with AWS Config and Lambda Remediation - Cleanup Script
# This script removes all resources created for the cost governance infrastructure
# Based on recipe: Cost Governance Automation with Config

set -e  # Exit on any error

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if .env file exists
    if [[ ! -f .env ]]; then
        error "Environment file .env not found. This file should have been created during deployment."
        error "Without this file, we cannot safely identify which resources to delete."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Load environment variables
load_environment() {
    log "Loading environment variables from .env file..."
    
    # Source the environment file
    source .env
    
    # Verify required variables are set
    local required_vars=(
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
        "COST_GOVERNANCE_BUCKET"
        "CONFIG_BUCKET"
        "LAMBDA_ROLE_NAME"
        "CONFIG_ROLE_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            error "Required environment variable $var is not set in .env file"
            exit 1
        fi
    done
    
    success "Environment variables loaded successfully"
    log "AWS Region: $AWS_REGION"
    log "AWS Account: $AWS_ACCOUNT_ID"
}

# Confirm deletion
confirm_deletion() {
    echo
    warning "=========================================="
    warning "            DESTRUCTIVE ACTION           "
    warning "=========================================="
    echo
    warning "This script will DELETE the following resources:"
    warning "• Lambda functions (IdleInstanceDetector, VolumeCleanup, CostReporter)"
    warning "• EventBridge rules (ConfigComplianceChanges, WeeklyCostOptimizationScan)"
    warning "• AWS Config rules (idle-ec2-instances, unattached-ebs-volumes, unused-load-balancers)"
    warning "• AWS Config recorder and delivery channel"
    warning "• SNS topics (CostGovernanceAlerts, CriticalCostActions)"
    warning "• SQS queues (CostGovernanceQueue, CostGovernanceDLQ)"
    warning "• IAM roles and policies (CostGovernanceLambdaRole, AWSConfigRole, CostGovernancePolicy)"
    warning "• S3 buckets and all contents (${CONFIG_BUCKET}, ${COST_GOVERNANCE_BUCKET})"
    echo
    warning "THIS ACTION CANNOT BE UNDONE!"
    echo
    
    read -p "Are you sure you want to delete all these resources? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Cleanup confirmed by user"
}

# Remove Lambda functions and EventBridge rules
cleanup_lambda_eventbridge() {
    log "Removing Lambda functions and EventBridge rules..."
    
    # Remove EventBridge rule targets first
    if aws events list-targets-by-rule --rule "ConfigComplianceChanges" --query 'Targets[].Id' --output text 2>/dev/null | grep -q .; then
        local target_ids=$(aws events list-targets-by-rule --rule "ConfigComplianceChanges" --query 'Targets[].Id' --output text)
        if [[ -n "$target_ids" ]]; then
            aws events remove-targets --rule "ConfigComplianceChanges" --ids $target_ids
            success "Removed targets from ConfigComplianceChanges rule"
        fi
    fi
    
    if aws events list-targets-by-rule --rule "WeeklyCostOptimizationScan" --query 'Targets[].Id' --output text 2>/dev/null | grep -q .; then
        local target_ids=$(aws events list-targets-by-rule --rule "WeeklyCostOptimizationScan" --query 'Targets[].Id' --output text)
        if [[ -n "$target_ids" ]]; then
            aws events remove-targets --rule "WeeklyCostOptimizationScan" --ids $target_ids
            success "Removed targets from WeeklyCostOptimizationScan rule"
        fi
    fi
    
    # Delete EventBridge rules
    aws events delete-rule --name "ConfigComplianceChanges" 2>/dev/null || warning "ConfigComplianceChanges rule not found"
    aws events delete-rule --name "WeeklyCostOptimizationScan" 2>/dev/null || warning "WeeklyCostOptimizationScan rule not found"
    success "Removed EventBridge rules"
    
    # Delete Lambda functions
    local lambda_functions=("IdleInstanceDetector" "VolumeCleanup" "CostReporter")
    for func in "${lambda_functions[@]}"; do
        if aws lambda get-function --function-name "$func" &>/dev/null; then
            aws lambda delete-function --function-name "$func"
            success "Deleted Lambda function: $func"
        else
            warning "Lambda function $func not found"
        fi
    done
}

# Delete Config rules and configuration
cleanup_config() {
    log "Removing AWS Config rules and configuration..."
    
    # Delete Config rules
    local config_rules=("idle-ec2-instances" "unattached-ebs-volumes" "unused-load-balancers")
    for rule in "${config_rules[@]}"; do
        if aws configservice describe-config-rules --config-rule-names "$rule" &>/dev/null; then
            aws configservice delete-config-rule --config-rule-name "$rule"
            success "Deleted Config rule: $rule"
        else
            warning "Config rule $rule not found"
        fi
    done
    
    # Stop configuration recorder
    if aws configservice describe-configuration-recorders --query 'ConfigurationRecorders[?Name==`default`]' --output text | grep -q .; then
        aws configservice stop-configuration-recorder --configuration-recorder-name default
        log "Stopped configuration recorder"
        
        # Wait a bit for it to stop
        sleep 5
        
        # Delete configuration recorder and delivery channel
        aws configservice delete-configuration-recorder --configuration-recorder-name default
        aws configservice delete-delivery-channel --delivery-channel-name default
        success "Deleted Config recorder and delivery channel"
    else
        warning "Config recorder 'default' not found"
    fi
}

# Clean up SNS and SQS resources
cleanup_messaging() {
    log "Removing SNS topics and SQS queues..."
    
    # Delete SNS topics
    if [[ -n "${COST_TOPIC_ARN:-}" ]]; then
        aws sns delete-topic --topic-arn "$COST_TOPIC_ARN" 2>/dev/null || warning "Cost topic not found"
        success "Deleted SNS topic: CostGovernanceAlerts"
    fi
    
    if [[ -n "${CRITICAL_TOPIC_ARN:-}" ]]; then
        aws sns delete-topic --topic-arn "$CRITICAL_TOPIC_ARN" 2>/dev/null || warning "Critical topic not found"
        success "Deleted SNS topic: CriticalCostActions"
    fi
    
    # Delete SQS queues
    if [[ -n "${COST_QUEUE_URL:-}" ]]; then
        aws sqs delete-queue --queue-url "$COST_QUEUE_URL" 2>/dev/null || warning "Cost queue not found"
        success "Deleted SQS queue: CostGovernanceQueue"
    fi
    
    if [[ -n "${DLQ_URL:-}" ]]; then
        aws sqs delete-queue --queue-url "$DLQ_URL" 2>/dev/null || warning "DLQ queue not found"
        success "Deleted SQS queue: CostGovernanceDLQ"
    fi
}

# Remove IAM roles and policies
cleanup_iam() {
    log "Removing IAM roles and policies..."
    
    # Detach and delete Lambda role policy
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
        # Detach the custom policy
        aws iam detach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CostGovernancePolicy" \
            2>/dev/null || warning "Policy may not be attached"
        
        # Delete the role
        aws iam delete-role --role-name "$LAMBDA_ROLE_NAME"
        success "Deleted IAM role: $LAMBDA_ROLE_NAME"
    else
        warning "Lambda role $LAMBDA_ROLE_NAME not found"
    fi
    
    # Delete the custom policy
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CostGovernancePolicy" &>/dev/null; then
        aws iam delete-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CostGovernancePolicy"
        success "Deleted IAM policy: CostGovernancePolicy"
    else
        warning "Custom policy CostGovernancePolicy not found"
    fi
    
    # Remove Config role
    if aws iam get-role --role-name "$CONFIG_ROLE_NAME" &>/dev/null; then
        # Detach AWS managed policy
        aws iam detach-role-policy \
            --role-name "$CONFIG_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole \
            2>/dev/null || warning "Config policy may not be attached"
        
        # Delete the role
        aws iam delete-role --role-name "$CONFIG_ROLE_NAME"
        success "Deleted IAM role: $CONFIG_ROLE_NAME"
    else
        warning "Config role $CONFIG_ROLE_NAME not found"
    fi
}

# Empty and delete S3 buckets
cleanup_s3() {
    log "Emptying and deleting S3 buckets..."
    
    # Function to empty and delete a bucket
    delete_bucket() {
        local bucket_name=$1
        
        if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
            log "Emptying bucket: $bucket_name"
            
            # Delete all object versions and delete markers
            aws s3api list-object-versions --bucket "$bucket_name" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text | \
            while read key version_id; do
                if [[ -n "$key" && -n "$version_id" ]]; then
                    aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" 2>/dev/null || true
                fi
            done
            
            # Delete delete markers
            aws s3api list-object-versions --bucket "$bucket_name" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text | \
            while read key version_id; do
                if [[ -n "$key" && -n "$version_id" ]]; then
                    aws s3api delete-object --bucket "$bucket_name" --key "$key" --version-id "$version_id" 2>/dev/null || true
                fi
            done
            
            # Use s3 rb to force delete bucket
            aws s3 rb "s3://$bucket_name" --force
            success "Deleted S3 bucket: $bucket_name"
        else
            warning "S3 bucket $bucket_name not found"
        fi
    }
    
    # Delete both buckets
    delete_bucket "$CONFIG_BUCKET"
    delete_bucket "$COST_GOVERNANCE_BUCKET"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove any temporary files that might exist
    rm -f *.py *.zip *.json
    
    # Ask user if they want to remove the .env file
    echo
    read -p "Remove the .env file as well? (y/n): " remove_env
    if [[ "$remove_env" =~ ^[Yy]$ ]]; then
        rm -f .env
        success "Removed .env file"
    else
        log "Keeping .env file for reference"
    fi
    
    success "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local issues_found=false
    
    # Check Lambda functions
    local lambda_functions=("IdleInstanceDetector" "VolumeCleanup" "CostReporter")
    for func in "${lambda_functions[@]}"; do
        if aws lambda get-function --function-name "$func" &>/dev/null; then
            warning "Lambda function $func still exists"
            issues_found=true
        fi
    done
    
    # Check EventBridge rules
    local rules=("ConfigComplianceChanges" "WeeklyCostOptimizationScan")
    for rule in "${rules[@]}"; do
        if aws events describe-rule --name "$rule" &>/dev/null; then
            warning "EventBridge rule $rule still exists"
            issues_found=true
        fi
    done
    
    # Check Config rules
    local config_rules=("idle-ec2-instances" "unattached-ebs-volumes" "unused-load-balancers")
    for rule in "${config_rules[@]}"; do
        if aws configservice describe-config-rules --config-rule-names "$rule" &>/dev/null; then
            warning "Config rule $rule still exists"
            issues_found=true
        fi
    done
    
    # Check IAM roles
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
        warning "IAM role $LAMBDA_ROLE_NAME still exists"
        issues_found=true
    fi
    
    if aws iam get-role --role-name "$CONFIG_ROLE_NAME" &>/dev/null; then
        warning "IAM role $CONFIG_ROLE_NAME still exists"
        issues_found=true
    fi
    
    # Check S3 buckets
    if aws s3api head-bucket --bucket "$CONFIG_BUCKET" 2>/dev/null; then
        warning "S3 bucket $CONFIG_BUCKET still exists"
        issues_found=true
    fi
    
    if aws s3api head-bucket --bucket "$COST_GOVERNANCE_BUCKET" 2>/dev/null; then
        warning "S3 bucket $COST_GOVERNANCE_BUCKET still exists"
        issues_found=true
    fi
    
    if [[ "$issues_found" == true ]]; then
        warning "Some resources may not have been deleted completely"
        warning "Please check the AWS console and manually delete any remaining resources"
    else
        success "All resources have been successfully deleted"
    fi
}

# Main cleanup function
main() {
    echo "=========================================="
    echo "  AWS Cost Governance Cleanup Script     "
    echo "=========================================="
    echo
    
    check_prerequisites
    load_environment
    confirm_deletion
    
    log "Starting cleanup process..."
    echo
    
    cleanup_lambda_eventbridge
    cleanup_config
    cleanup_messaging
    cleanup_iam
    cleanup_s3
    cleanup_local_files
    
    echo
    log "Verifying cleanup..."
    verify_cleanup
    
    echo
    success "=========================================="
    success "     CLEANUP COMPLETED SUCCESSFULLY      "
    success "=========================================="
    echo
    log "All cost governance infrastructure has been removed:"
    log "• Lambda functions deleted"
    log "• EventBridge rules removed"
    log "• AWS Config rules and recorder deleted"
    log "• SNS topics and SQS queues removed"
    log "• IAM roles and policies deleted"
    log "• S3 buckets and contents removed"
    echo
    warning "Note: Any EC2 instances tagged with cost optimization tags will retain those tags."
    warning "Any snapshots created during volume cleanup operations will remain in your account."
    echo
    success "Cleanup complete!"
}

# Trap to handle script interruption
trap 'echo -e "\n${RED}Cleanup interrupted by user${NC}"; exit 1' INT

# Run main function
main "$@"