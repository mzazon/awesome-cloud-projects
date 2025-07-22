#!/bin/bash

# Real-time Anomaly Detection CDK Destruction Script
# This script safely destroys the anomaly detection infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to check if stack exists
check_stack_exists() {
    aws cloudformation describe-stacks --stack-name AnomalyDetectionStack &> /dev/null
}

# Function to stop Flink application
stop_flink_application() {
    print_status "Checking Flink application status..."
    
    # Get application name from stack outputs
    if check_stack_exists; then
        APP_NAME=$(aws cloudformation describe-stacks \
            --stack-name AnomalyDetectionStack \
            --query 'Stacks[0].Outputs[?OutputKey==`FlinkApplicationName`].OutputValue' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$APP_NAME" ] && [ "$APP_NAME" != "None" ]; then
            print_status "Found Flink application: $APP_NAME"
            
            # Check application status
            APP_STATUS=$(aws kinesisanalyticsv2 describe-application \
                --application-name "$APP_NAME" \
                --query 'ApplicationDetail.ApplicationStatus' \
                --output text 2>/dev/null || echo "NOT_FOUND")
            
            if [ "$APP_STATUS" = "RUNNING" ]; then
                print_warning "Stopping Flink application: $APP_NAME"
                aws kinesisanalyticsv2 stop-application \
                    --application-name "$APP_NAME" \
                    --force || print_warning "Failed to stop Flink application"
                
                # Wait for application to stop
                print_status "Waiting for application to stop..."
                for i in {1..30}; do
                    STATUS=$(aws kinesisanalyticsv2 describe-application \
                        --application-name "$APP_NAME" \
                        --query 'ApplicationDetail.ApplicationStatus' \
                        --output text 2>/dev/null || echo "STOPPED")
                    
                    if [ "$STATUS" = "READY" ] || [ "$STATUS" = "STOPPED" ]; then
                        print_success "Flink application stopped"
                        break
                    fi
                    
                    echo -n "."
                    sleep 2
                done
                echo ""
            else
                print_status "Flink application is not running (status: $APP_STATUS)"
            fi
        else
            print_status "No Flink application found in stack outputs"
        fi
    fi
}

# Function to empty S3 buckets
empty_s3_buckets() {
    print_status "Emptying S3 buckets..."
    
    if check_stack_exists; then
        # Get bucket name from stack outputs
        BUCKET_NAME=$(aws cloudformation describe-stacks \
            --stack-name AnomalyDetectionStack \
            --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$BUCKET_NAME" ] && [ "$BUCKET_NAME" != "None" ]; then
            print_status "Found S3 bucket: $BUCKET_NAME"
            
            # Check if bucket exists
            if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
                print_status "Emptying S3 bucket: $BUCKET_NAME"
                aws s3 rm "s3://$BUCKET_NAME" --recursive || print_warning "Failed to empty S3 bucket"
                print_success "S3 bucket emptied"
            else
                print_status "S3 bucket does not exist or is not accessible"
            fi
        else
            print_status "No S3 bucket found in stack outputs"
        fi
    fi
}

# Function to delete CloudWatch logs
delete_cloudwatch_logs() {
    print_status "Checking for CloudWatch log groups..."
    
    # Get log groups related to our application
    LOG_GROUPS=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/lambda/anomaly-processor" \
        --query 'logGroups[].logGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$LOG_GROUPS" ]; then
        for LOG_GROUP in $LOG_GROUPS; do
            print_status "Deleting log group: $LOG_GROUP"
            aws logs delete-log-group --log-group-name "$LOG_GROUP" || print_warning "Failed to delete log group: $LOG_GROUP"
        done
    fi
    
    # Check for Flink application logs
    FLINK_LOGS=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/kinesis-analytics" \
        --query 'logGroups[].logGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$FLINK_LOGS" ]; then
        for LOG_GROUP in $FLINK_LOGS; do
            if [[ "$LOG_GROUP" == *"anomaly"* ]]; then
                print_status "Deleting Flink log group: $LOG_GROUP"
                aws logs delete-log-group --log-group-name "$LOG_GROUP" || print_warning "Failed to delete log group: $LOG_GROUP"
            fi
        done
    fi
}

# Function to destroy the CDK stack
destroy_stack() {
    print_status "Destroying CDK stack..."
    
    if check_stack_exists; then
        # Use CDK destroy command
        cdk destroy --force || {
            print_error "CDK destroy failed. Attempting CloudFormation deletion..."
            aws cloudformation delete-stack --stack-name AnomalyDetectionStack
            
            print_status "Waiting for stack deletion to complete..."
            aws cloudformation wait stack-delete-complete --stack-name AnomalyDetectionStack || {
                print_error "Stack deletion failed or timed out"
                return 1
            }
        }
        
        print_success "Stack destroyed successfully!"
    else
        print_warning "Stack AnomalyDetectionStack does not exist"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    print_status "Verifying cleanup..."
    
    # Check if stack still exists
    if check_stack_exists; then
        print_warning "Stack still exists - deletion may still be in progress"
        return 1
    fi
    
    print_success "Stack successfully deleted"
    return 0
}

# Function to show cleanup summary
show_cleanup_summary() {
    echo ""
    echo "=================================================="
    echo "Cleanup Summary"
    echo "=================================================="
    print_success "Anomaly detection infrastructure has been destroyed"
    echo ""
    print_status "What was cleaned up:"
    echo "  ✓ Kinesis Data Stream"
    echo "  ✓ Managed Service for Apache Flink Application" 
    echo "  ✓ Lambda Functions"
    echo "  ✓ SNS Topic and Subscriptions"
    echo "  ✓ CloudWatch Alarms and Anomaly Detectors"
    echo "  ✓ S3 Bucket and Contents"
    echo "  ✓ IAM Roles and Policies"
    echo "  ✓ CloudWatch Log Groups (if requested)"
    echo ""
    print_status "Note: Some CloudWatch logs may be retained based on their retention settings"
    print_success "Cleanup completed successfully!"
}

# Function to confirm destruction
confirm_destruction() {
    echo "=================================================="
    echo "Real-time Anomaly Detection Infrastructure Cleanup"
    echo "=================================================="
    echo ""
    print_warning "This will permanently delete the following resources:"
    echo "  • Kinesis Data Stream and all data"
    echo "  • Managed Service for Apache Flink Application"
    echo "  • Lambda Functions"
    echo "  • SNS Topic and Email Subscriptions"
    echo "  • CloudWatch Alarms and Metrics"
    echo "  • S3 Bucket and all stored artifacts"
    echo "  • IAM Roles and Policies"
    echo "  • CloudWatch Log Groups (optional)"
    echo ""
    print_error "This action cannot be undone!"
    echo ""
    
    if [ "$FORCE_DESTROY" = "true" ]; then
        print_warning "Force destroy enabled - skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to destroy the anomaly detection infrastructure? (yes/no): " confirm
    case $confirm in
        [Yy][Ee][Ss]|[Yy])
            return 0
            ;;
        *)
            print_status "Destruction cancelled"
            exit 0
            ;;
    esac
}

# Main execution
main() {
    confirm_destruction
    
    echo ""
    print_status "Starting cleanup process..."
    
    # Stop Flink application first
    stop_flink_application
    
    # Empty S3 buckets to allow deletion
    empty_s3_buckets
    
    # Destroy the main stack
    destroy_stack
    
    # Optionally delete CloudWatch logs
    if [ "$DELETE_LOGS" = "true" ]; then
        delete_cloudwatch_logs
    fi
    
    # Verify cleanup completed
    if verify_cleanup; then
        show_cleanup_summary
    else
        print_error "Cleanup verification failed - some resources may still exist"
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h         Show this help message"
        echo "  --force            Skip confirmation prompt"
        echo "  --delete-logs      Also delete CloudWatch log groups"
        echo "  --check-only       Only check what would be deleted"
        echo ""
        echo "Environment variables:"
        echo "  FORCE_DESTROY=true    Skip confirmation (use with caution)"
        echo "  DELETE_LOGS=true      Delete CloudWatch logs"
        echo ""
        echo "Example:"
        echo "  ./destroy.sh --force --delete-logs"
        exit 0
        ;;
    --force)
        FORCE_DESTROY=true
        main
        ;;
    --delete-logs)
        DELETE_LOGS=true
        main
        ;;
    --check-only)
        print_status "Resources that would be deleted:"
        if check_stack_exists; then
            aws cloudformation list-stack-resources --stack-name AnomalyDetectionStack \
                --query 'StackResourceSummaries[].{Type:ResourceType,Name:LogicalResourceId}' \
                --output table
        else
            print_status "No stack found to delete"
        fi
        exit 0
        ;;
    "")
        main
        ;;
    *)
        if [ "$1" = "--force" ] && [ "$2" = "--delete-logs" ]; then
            FORCE_DESTROY=true
            DELETE_LOGS=true
            main
        elif [ "$1" = "--delete-logs" ] && [ "$2" = "--force" ]; then
            FORCE_DESTROY=true
            DELETE_LOGS=true
            main
        else
            print_error "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
        fi
        ;;
esac