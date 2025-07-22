#!/bin/bash

# S3 Event Processing CDK Destruction Script
# This script safely destroys the S3 Event Notifications and Automated Processing stack

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if stack exists
check_stack_exists() {
    if aws cloudformation describe-stacks --stack-name S3EventProcessingStack &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to get bucket name from stack
get_bucket_name() {
    aws cloudformation describe-stacks \
        --stack-name S3EventProcessingStack \
        --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' \
        --output text 2>/dev/null || echo ""
}

# Function to empty S3 bucket
empty_s3_bucket() {
    local bucket_name="$1"
    
    if [ -n "$bucket_name" ]; then
        print_status "Checking if S3 bucket exists: $bucket_name"
        
        if aws s3 ls "s3://$bucket_name" &> /dev/null; then
            print_warning "Emptying S3 bucket: $bucket_name"
            
            # Delete all object versions and delete markers
            aws s3api list-object-versions \
                --bucket "$bucket_name" \
                --output json \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                | jq -r '.[]? | .Key + " " + .VersionId' \
                | while read -r key version_id; do
                    if [ -n "$key" ] && [ -n "$version_id" ]; then
                        aws s3api delete-object \
                            --bucket "$bucket_name" \
                            --key "$key" \
                            --version-id "$version_id" &> /dev/null || true
                    fi
                done
            
            # Delete all delete markers
            aws s3api list-object-versions \
                --bucket "$bucket_name" \
                --output json \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                | jq -r '.[]? | .Key + " " + .VersionId' \
                | while read -r key version_id; do
                    if [ -n "$key" ] && [ -n "$version_id" ]; then
                        aws s3api delete-object \
                            --bucket "$bucket_name" \
                            --key "$key" \
                            --version-id "$version_id" &> /dev/null || true
                    fi
                done
            
            # Use simple delete for remaining objects
            aws s3 rm "s3://$bucket_name" --recursive &> /dev/null || true
            
            print_status "S3 bucket emptied successfully"
        else
            print_status "S3 bucket $bucket_name does not exist or is already empty"
        fi
    fi
}

# Function to purge SQS queues
purge_sqs_queues() {
    print_status "Purging SQS queues..."
    
    # Get queue URLs from stack outputs
    local main_queue_url=$(aws cloudformation describe-stacks \
        --stack-name S3EventProcessingStack \
        --query 'Stacks[0].Outputs[?OutputKey==`SqsQueueUrl`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$main_queue_url" ]; then
        print_status "Purging main SQS queue: $main_queue_url"
        aws sqs purge-queue --queue-url "$main_queue_url" &> /dev/null || true
    fi
    
    # Find and purge dead letter queue
    local dlq_url=$(aws sqs list-queues --queue-name-prefix "file-processing-dlq" \
        --query 'QueueUrls[0]' --output text 2>/dev/null || echo "")
    
    if [ -n "$dlq_url" ] && [ "$dlq_url" != "None" ]; then
        print_status "Purging dead letter queue: $dlq_url"
        aws sqs purge-queue --queue-url "$dlq_url" &> /dev/null || true
    fi
    
    print_status "SQS queues purged successfully"
}

# Function to remove SNS subscriptions
remove_sns_subscriptions() {
    print_status "Removing SNS subscriptions..."
    
    local topic_arn=$(aws cloudformation describe-stacks \
        --stack-name S3EventProcessingStack \
        --query 'Stacks[0].Outputs[?OutputKey==`SnsTopicArn`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$topic_arn" ] && [ "$topic_arn" != "None" ]; then
        # List and remove all subscriptions
        aws sns list-subscriptions-by-topic --topic-arn "$topic_arn" \
            --query 'Subscriptions[].SubscriptionArn' --output text \
            | tr '\t' '\n' \
            | while read -r subscription_arn; do
                if [ -n "$subscription_arn" ] && [ "$subscription_arn" != "None" ]; then
                    print_status "Removing subscription: $subscription_arn"
                    aws sns unsubscribe --subscription-arn "$subscription_arn" &> /dev/null || true
                fi
            done
    fi
    
    print_status "SNS subscriptions removed successfully"
}

# Function to destroy the CDK stack
destroy_stack() {
    print_status "Destroying CDK stack..."
    
    if [ "$AUTO_APPROVE" == "true" ]; then
        cdk destroy --force
    else
        cdk destroy
    fi
    
    print_status "CDK stack destroyed successfully!"
}

# Function to clean up local files
cleanup_local() {
    if [ "$CLEAN_LOCAL" == "true" ]; then
        print_status "Cleaning up local build artifacts..."
        
        # Remove build outputs
        rm -rf lib/ cdk.out/ node_modules/.cache/ &> /dev/null || true
        
        # Remove logs
        rm -rf coverage/ *.log &> /dev/null || true
        
        print_status "Local cleanup completed"
    fi
}

# Function to show confirmation
show_confirmation() {
    print_warning "This will destroy the S3 Event Processing stack and all its resources."
    print_warning "This action cannot be undone!"
    print_warning ""
    print_warning "Resources that will be destroyed:"
    print_warning "- S3 Bucket and all its contents"
    print_warning "- Lambda Function and CloudWatch Logs"
    print_warning "- SQS Queues and messages"
    print_warning "- SNS Topic and subscriptions"
    print_warning "- IAM Roles and Policies"
    print_warning ""
    
    if [ "$AUTO_APPROVE" != "true" ]; then
        read -p "Are you sure you want to continue? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_status "Destruction cancelled."
            exit 0
        fi
    else
        print_warning "Auto-approve enabled, proceeding with destruction..."
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "      --auto-approve        Auto-approve destruction without prompts"
    echo "      --clean-local         Clean up local build artifacts"
    echo "      --preserve-data       Skip emptying S3 bucket (for data preservation)"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                        # Interactive destruction"
    echo "  $0 --auto-approve        # Automatic destruction"
    echo "  $0 --preserve-data       # Keep S3 bucket contents"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-approve)
            AUTO_APPROVE="true"
            shift
            ;;
        --clean-local)
            CLEAN_LOCAL="true"
            shift
            ;;
        --preserve-data)
            PRESERVE_DATA="true"
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    print_status "Starting S3 Event Processing stack destruction..."
    
    # Check if stack exists
    if ! check_stack_exists; then
        print_warning "Stack 'S3EventProcessingStack' does not exist."
        exit 0
    fi
    
    show_confirmation
    
    # Get bucket name before destroying stack
    BUCKET_NAME=$(get_bucket_name)
    
    # Clean up resources that might prevent stack deletion
    if [ "$PRESERVE_DATA" != "true" ]; then
        empty_s3_bucket "$BUCKET_NAME"
    else
        print_warning "Preserving S3 bucket data as requested"
    fi
    
    purge_sqs_queues
    remove_sns_subscriptions
    
    # Wait a moment for AWS to process the deletions
    print_status "Waiting for resource cleanup to complete..."
    sleep 10
    
    # Destroy the stack
    destroy_stack
    
    # Local cleanup
    cleanup_local
    
    print_status "Destruction completed successfully!"
    
    if [ "$PRESERVE_DATA" == "true" ] && [ -n "$BUCKET_NAME" ]; then
        print_warning ""
        print_warning "Note: S3 bucket '$BUCKET_NAME' was preserved with its data."
        print_warning "You may want to delete it manually if no longer needed:"
        print_warning "aws s3 rb s3://$BUCKET_NAME --force"
    fi
}

# Run main function
main