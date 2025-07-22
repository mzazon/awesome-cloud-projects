#!/bin/bash

# Blockchain Voting System Cleanup Script
# This script safely removes all resources created by the voting system
# with proper validation and confirmation

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="dev"
REGION="us-east-1"
PROFILE="default"
FORCE_CLEANUP=false
SKIP_CONFIRMATION=false

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print usage
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --environment    Environment (dev, staging, prod) [default: dev]"
    echo "  -r, --region         AWS region [default: us-east-1]"
    echo "  -p, --profile        AWS profile [default: default]"
    echo "  -f, --force          Force cleanup without detailed confirmation"
    echo "  -y, --yes            Skip confirmation prompts"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -e dev -r us-west-2"
    echo "  $0 --force --environment staging"
    echo "  $0 --yes"
}

# Function to validate prerequisites
validate_prerequisites() {
    print_message $BLUE "🔍 Validating prerequisites..."
    
    # Check if required tools are installed
    if ! command -v aws &> /dev/null; then
        print_message $RED "❌ AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v cdk &> /dev/null; then
        print_message $RED "❌ CDK is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity --profile $PROFILE &> /dev/null; then
        print_message $RED "❌ AWS credentials not configured for profile: $PROFILE"
        exit 1
    fi
    
    print_message $GREEN "✅ Prerequisites validated successfully"
}

# Function to setup environment
setup_environment() {
    print_message $BLUE "🔧 Setting up environment..."
    
    # Export AWS profile
    export AWS_PROFILE=$PROFILE
    
    # Get AWS account ID and region
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile $PROFILE)
    AWS_REGION=$REGION
    
    # Export CDK environment variables
    export CDK_DEFAULT_ACCOUNT=$AWS_ACCOUNT_ID
    export CDK_DEFAULT_REGION=$AWS_REGION
    export AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
    export AWS_REGION=$AWS_REGION
    
    print_message $GREEN "✅ Environment configured:"
    print_message $GREEN "   Account ID: $AWS_ACCOUNT_ID"
    print_message $GREEN "   Region: $AWS_REGION"
    print_message $GREEN "   Profile: $PROFILE"
    print_message $GREEN "   Environment: $ENVIRONMENT"
}

# Function to check if stacks exist
check_stacks() {
    print_message $BLUE "🔍 Checking existing stacks..."
    
    SECURITY_STACK="blockchain-voting-system-Security-$ENVIRONMENT"
    CORE_STACK="blockchain-voting-system-Core-$ENVIRONMENT"
    MONITORING_STACK="blockchain-voting-system-Monitoring-$ENVIRONMENT"
    
    # Check if stacks exist
    SECURITY_EXISTS=$(aws cloudformation describe-stacks --stack-name $SECURITY_STACK --profile $PROFILE 2>/dev/null || echo "false")
    CORE_EXISTS=$(aws cloudformation describe-stacks --stack-name $CORE_STACK --profile $PROFILE 2>/dev/null || echo "false")
    MONITORING_EXISTS=$(aws cloudformation describe-stacks --stack-name $MONITORING_STACK --profile $PROFILE 2>/dev/null || echo "false")
    
    if [[ "$SECURITY_EXISTS" == "false" && "$CORE_EXISTS" == "false" && "$MONITORING_EXISTS" == "false" ]]; then
        print_message $YELLOW "⚠️  No voting system stacks found for environment: $ENVIRONMENT"
        exit 0
    fi
    
    print_message $GREEN "✅ Found existing stacks to cleanup"
}

# Function to show resources to be deleted
show_resources() {
    print_message $BLUE "📋 Resources to be deleted:"
    echo ""
    
    # Show stack resources
    for stack in "blockchain-voting-system-Security-$ENVIRONMENT" "blockchain-voting-system-Core-$ENVIRONMENT" "blockchain-voting-system-Monitoring-$ENVIRONMENT"; do
        if aws cloudformation describe-stacks --stack-name $stack --profile $PROFILE &> /dev/null; then
            print_message $YELLOW "Stack: $stack"
            aws cloudformation list-stack-resources \
                --stack-name $stack \
                --query 'StackResourceSummaries[].{Type:ResourceType,Status:ResourceStatus,LogicalId:LogicalResourceId}' \
                --output table \
                --profile $PROFILE || true
            echo ""
        fi
    done
}

# Function to empty S3 buckets
empty_s3_buckets() {
    print_message $BLUE "🗑️  Emptying S3 buckets..."
    
    # List of bucket patterns to empty
    BUCKET_PATTERNS=(
        "blockchain-voting-system-voting-data-$ENVIRONMENT-$AWS_ACCOUNT_ID"
        "blockchain-voting-system-dapp-$ENVIRONMENT-$AWS_ACCOUNT_ID"
        "blockchain-voting-system-audit-logs-$ENVIRONMENT-$AWS_ACCOUNT_ID"
        "blockchain-voting-system-config-$ENVIRONMENT-$AWS_ACCOUNT_ID"
    )
    
    for pattern in "${BUCKET_PATTERNS[@]}"; do
        # Check if bucket exists
        if aws s3api head-bucket --bucket "$pattern" --profile $PROFILE 2>/dev/null; then
            print_message $YELLOW "   Emptying bucket: $pattern"
            
            # Empty bucket (including versioned objects)
            aws s3 rm "s3://$pattern" --recursive --profile $PROFILE || true
            
            # Delete versioned objects
            aws s3api list-object-versions \
                --bucket "$pattern" \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                --output text \
                --profile $PROFILE | while read key version; do
                if [ -n "$key" ] && [ -n "$version" ]; then
                    aws s3api delete-object \
                        --bucket "$pattern" \
                        --key "$key" \
                        --version-id "$version" \
                        --profile $PROFILE || true
                fi
            done
            
            # Delete delete markers
            aws s3api list-object-versions \
                --bucket "$pattern" \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                --output text \
                --profile $PROFILE | while read key version; do
                if [ -n "$key" ] && [ -n "$version" ]; then
                    aws s3api delete-object \
                        --bucket "$pattern" \
                        --key "$key" \
                        --version-id "$version" \
                        --profile $PROFILE || true
                fi
            done
            
            print_message $GREEN "   ✅ Emptied bucket: $pattern"
        fi
    done
}

# Function to disable CloudTrail
disable_cloudtrail() {
    print_message $BLUE "🔒 Disabling CloudTrail..."
    
    TRAIL_NAME="blockchain-voting-system-audit-trail-$ENVIRONMENT"
    
    # Check if trail exists and stop it
    if aws cloudtrail describe-trails --trail-name-list "$TRAIL_NAME" --profile $PROFILE &> /dev/null; then
        print_message $YELLOW "   Stopping CloudTrail: $TRAIL_NAME"
        aws cloudtrail stop-logging --name "$TRAIL_NAME" --profile $PROFILE || true
        print_message $GREEN "   ✅ CloudTrail disabled"
    fi
}

# Function to delete KMS keys
schedule_kms_deletion() {
    print_message $BLUE "🔑 Scheduling KMS key deletion..."
    
    # Find KMS key by alias
    KEY_ALIAS="alias/blockchain-voting-system-$ENVIRONMENT"
    
    KEY_ID=$(aws kms describe-key --key-id "$KEY_ALIAS" --query 'KeyMetadata.KeyId' --output text --profile $PROFILE 2>/dev/null || echo "")
    
    if [ -n "$KEY_ID" ] && [ "$KEY_ID" != "None" ]; then
        print_message $YELLOW "   Scheduling deletion for KMS key: $KEY_ID"
        aws kms schedule-key-deletion \
            --key-id "$KEY_ID" \
            --pending-window-in-days 7 \
            --profile $PROFILE || true
        print_message $GREEN "   ✅ KMS key scheduled for deletion in 7 days"
    fi
}

# Function to destroy CDK stacks
destroy_stacks() {
    print_message $BLUE "🗑️  Destroying CDK stacks..."
    
    # Destroy stacks in reverse order
    STACKS=(
        "blockchain-voting-system-Monitoring-$ENVIRONMENT"
        "blockchain-voting-system-Core-$ENVIRONMENT"
        "blockchain-voting-system-Security-$ENVIRONMENT"
    )
    
    for stack in "${STACKS[@]}"; do
        if aws cloudformation describe-stacks --stack-name $stack --profile $PROFILE &> /dev/null; then
            print_message $YELLOW "   Destroying stack: $stack"
            
            cdk destroy $stack \
                --context environment=$ENVIRONMENT \
                --profile $PROFILE \
                --force \
                --progress events || true
            
            print_message $GREEN "   ✅ Stack destroyed: $stack"
        else
            print_message $YELLOW "   ⚠️  Stack not found: $stack"
        fi
    done
}

# Function to cleanup remaining resources
cleanup_remaining_resources() {
    print_message $BLUE "🧹 Cleaning up remaining resources..."
    
    # Delete any remaining Lambda functions
    print_message $YELLOW "   Checking for Lambda functions..."
    aws lambda list-functions \
        --query "Functions[?starts_with(FunctionName, 'blockchain-voting-system-$ENVIRONMENT')].FunctionName" \
        --output text \
        --profile $PROFILE | tr '\t' '\n' | while read function; do
        if [ -n "$function" ]; then
            print_message $YELLOW "   Deleting Lambda function: $function"
            aws lambda delete-function --function-name "$function" --profile $PROFILE || true
        fi
    done
    
    # Delete any remaining DynamoDB tables
    print_message $YELLOW "   Checking for DynamoDB tables..."
    aws dynamodb list-tables \
        --query "TableNames[?starts_with(@, 'blockchain-voting-system-$ENVIRONMENT')]" \
        --output text \
        --profile $PROFILE | tr '\t' '\n' | while read table; do
        if [ -n "$table" ]; then
            print_message $YELLOW "   Deleting DynamoDB table: $table"
            aws dynamodb delete-table --table-name "$table" --profile $PROFILE || true
        fi
    done
    
    # Delete any remaining EventBridge rules
    print_message $YELLOW "   Checking for EventBridge rules..."
    aws events list-rules \
        --name-prefix "blockchain-voting-system-$ENVIRONMENT" \
        --query "Rules[].Name" \
        --output text \
        --profile $PROFILE | tr '\t' '\n' | while read rule; do
        if [ -n "$rule" ]; then
            print_message $YELLOW "   Deleting EventBridge rule: $rule"
            
            # Remove targets first
            aws events list-targets-by-rule --rule "$rule" --profile $PROFILE \
                --query "Targets[].Id" --output text | tr '\t' '\n' | while read target; do
                if [ -n "$target" ]; then
                    aws events remove-targets --rule "$rule" --ids "$target" --profile $PROFILE || true
                fi
            done
            
            # Delete rule
            aws events delete-rule --name "$rule" --profile $PROFILE || true
        fi
    done
    
    # Delete any remaining SNS topics
    print_message $YELLOW "   Checking for SNS topics..."
    aws sns list-topics \
        --query "Topics[?contains(TopicArn, 'blockchain-voting-system-$ENVIRONMENT')].TopicArn" \
        --output text \
        --profile $PROFILE | tr '\t' '\n' | while read topic; do
        if [ -n "$topic" ]; then
            print_message $YELLOW "   Deleting SNS topic: $topic"
            aws sns delete-topic --topic-arn "$topic" --profile $PROFILE || true
        fi
    done
    
    print_message $GREEN "   ✅ Remaining resources cleaned up"
}

# Function to confirm cleanup
confirm_cleanup() {
    if [ "$SKIP_CONFIRMATION" = true ]; then
        return 0
    fi
    
    print_message $RED "⚠️  WARNING: This will permanently delete all voting system resources!"
    print_message $RED "   Environment: $ENVIRONMENT"
    print_message $RED "   Region: $REGION"
    print_message $RED "   Account: $AWS_ACCOUNT_ID"
    print_message $RED "   This action cannot be undone!"
    echo ""
    
    if [ "$FORCE_CLEANUP" = false ]; then
        read -p "Are you absolutely sure you want to continue? Type 'DELETE' to confirm: " -r
        echo ""
        
        if [ "$REPLY" != "DELETE" ]; then
            print_message $RED "❌ Cleanup cancelled"
            exit 1
        fi
    else
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_message $RED "❌ Cleanup cancelled"
            exit 1
        fi
    fi
}

# Main execution
main() {
    print_message $RED "🗑️  Blockchain Voting System Cleanup"
    print_message $RED "===================================="
    
    # Validate prerequisites
    validate_prerequisites
    
    # Setup environment
    setup_environment
    
    # Check if stacks exist
    check_stacks
    
    # Show resources to be deleted
    if [ "$FORCE_CLEANUP" = false ]; then
        show_resources
    fi
    
    # Confirm cleanup
    confirm_cleanup
    
    # Empty S3 buckets first
    empty_s3_buckets
    
    # Disable CloudTrail
    disable_cloudtrail
    
    # Destroy CDK stacks
    destroy_stacks
    
    # Schedule KMS key deletion
    schedule_kms_deletion
    
    # Cleanup remaining resources
    cleanup_remaining_resources
    
    print_message $GREEN "🎉 Cleanup completed successfully!"
    print_message $GREEN "   Environment: $ENVIRONMENT"
    print_message $GREEN "   Region: $REGION"
    print_message $GREEN "   Account: $AWS_ACCOUNT_ID"
    print_message $YELLOW "   Note: KMS keys are scheduled for deletion in 7 days"
    print_message $YELLOW "   You can cancel KMS key deletion if needed using AWS Console"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -p|--profile)
            PROFILE="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_CLEANUP=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            print_message $RED "❌ Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    print_message $RED "❌ Invalid environment: $ENVIRONMENT. Must be dev, staging, or prod"
    exit 1
fi

# Run main function
main