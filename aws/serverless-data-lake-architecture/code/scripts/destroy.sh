#!/bin/bash

# Advanced Serverless Data Lake Architecture Cleanup Script
# This script removes all resources created by the deploy.sh script
# Recipe: Implementing Advanced Serverless Data Lake Architecture with Lambda Layers, Glue, and EventBridge

set -e

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    log_success "Prerequisites check completed"
}

# Load configuration from deployment
load_configuration() {
    log "Loading deployment configuration..."
    
    if [ ! -f "deployment-config.json" ]; then
        log_warning "deployment-config.json not found. Attempting to discover resources..."
        
        # Try to get some basic info from AWS
        export AWS_REGION=$(aws configure get region)
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            log_warning "No default region configured, using us-east-1"
        fi
        
        # Prompt user for project name if config is missing
        if [ -z "$1" ]; then
            echo ""
            echo "⚠️  Configuration file not found. Please provide the project name to clean up resources."
            echo "You can find this in the deployment output or by checking your AWS resources."
            echo ""
            read -p "Enter the project name (e.g., advanced-serverless-datalake-abc123): " PROJECT_INPUT
            if [ -z "$PROJECT_INPUT" ]; then
                error_exit "Project name is required for cleanup"
            fi
            export PROJECT_NAME="$PROJECT_INPUT"
        else
            export PROJECT_NAME="$1"
        fi
        
        # Set resource names based on project name
        export LAMBDA_LAYER_NAME="${PROJECT_NAME}-shared-layer"
        export CUSTOM_EVENT_BUS="${PROJECT_NAME}-event-bus"
        export S3_BUCKET_RAW="${PROJECT_NAME}-raw-data"
        export S3_BUCKET_PROCESSED="${PROJECT_NAME}-processed-data"
        export S3_BUCKET_QUARANTINE="${PROJECT_NAME}-quarantine-data"
        export DYNAMODB_METADATA_TABLE="${PROJECT_NAME}-metadata"
        export GLUE_DATABASE="${PROJECT_NAME}_catalog"
        
    else
        # Load from configuration file
        export PROJECT_NAME=$(jq -r '.projectName' deployment-config.json)
        export AWS_REGION=$(jq -r '.awsRegion' deployment-config.json)
        export AWS_ACCOUNT_ID=$(jq -r '.awsAccountId' deployment-config.json)
        export S3_BUCKET_RAW=$(jq -r '.resources.s3Buckets.raw' deployment-config.json)
        export S3_BUCKET_PROCESSED=$(jq -r '.resources.s3Buckets.processed' deployment-config.json)
        export S3_BUCKET_QUARANTINE=$(jq -r '.resources.s3Buckets.quarantine' deployment-config.json)
        export DYNAMODB_METADATA_TABLE=$(jq -r '.resources.dynamoDbTable' deployment-config.json)
        export LAMBDA_LAYER_NAME=$(jq -r '.resources.lambdaLayer' deployment-config.json)
        export CUSTOM_EVENT_BUS=$(jq -r '.resources.eventBus' deployment-config.json)
        export GLUE_DATABASE=$(jq -r '.resources.glueDatabase' deployment-config.json)
    fi
    
    log_success "Configuration loaded:"
    log "  Project Name: $PROJECT_NAME"
    log "  AWS Region: $AWS_REGION"
    log "  AWS Account ID: $AWS_ACCOUNT_ID"
}

# Confirm destruction with user
confirm_destruction() {
    echo ""
    echo "🚨 DANGER: This will permanently delete ALL resources for project: ${PROJECT_NAME}"
    echo ""
    echo "Resources to be deleted:"
    echo "  • 3 S3 buckets and all their contents"
    echo "  • DynamoDB table and all data"
    echo "  • 3 Lambda functions"
    echo "  • 1 Lambda layer"
    echo "  • EventBridge custom bus and rules"
    echo "  • Glue database and crawler"
    echo "  • IAM roles and policies"
    echo ""
    echo "⚠️  This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        log_warning "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    log "Starting cleanup process..."
}

# Remove EventBridge configuration
remove_eventbridge() {
    log "Removing EventBridge configuration..."
    
    # Remove EventBridge targets (ignore errors if targets don't exist)
    aws events remove-targets \
        --rule "${PROJECT_NAME}-data-ingestion-rule" \
        --event-bus-name ${CUSTOM_EVENT_BUS} \
        --ids 1 2>/dev/null || log_warning "Failed to remove ingestion rule targets (may not exist)"
    
    aws events remove-targets \
        --rule "${PROJECT_NAME}-data-validation-rule" \
        --event-bus-name ${CUSTOM_EVENT_BUS} \
        --ids 1 2>/dev/null || log_warning "Failed to remove validation rule targets (may not exist)"
    
    # Delete EventBridge rules
    aws events delete-rule \
        --name "${PROJECT_NAME}-data-ingestion-rule" \
        --event-bus-name ${CUSTOM_EVENT_BUS} 2>/dev/null || log_warning "Failed to delete ingestion rule (may not exist)"
    
    aws events delete-rule \
        --name "${PROJECT_NAME}-data-validation-rule" \
        --event-bus-name ${CUSTOM_EVENT_BUS} 2>/dev/null || log_warning "Failed to delete validation rule (may not exist)"
    
    aws events delete-rule \
        --name "${PROJECT_NAME}-data-quality-rule" \
        --event-bus-name ${CUSTOM_EVENT_BUS} 2>/dev/null || log_warning "Failed to delete quality rule (may not exist)"
    
    # Delete custom event bus
    aws events delete-event-bus --name ${CUSTOM_EVENT_BUS} 2>/dev/null || log_warning "Failed to delete event bus (may not exist)"
    
    log_success "EventBridge configuration removed"
}

# Remove Lambda functions and layer
remove_lambda_functions() {
    log "Removing Lambda functions and layer..."
    
    # Remove Lambda function permissions first
    aws lambda remove-permission \
        --function-name "${PROJECT_NAME}-data-ingestion" \
        --statement-id s3-trigger-permission 2>/dev/null || log_warning "Failed to remove S3 Lambda permission (may not exist)"
    
    aws lambda remove-permission \
        --function-name "${PROJECT_NAME}-data-validation" \
        --statement-id eventbridge-validation-permission 2>/dev/null || log_warning "Failed to remove EventBridge validation permission (may not exist)"
    
    aws lambda remove-permission \
        --function-name "${PROJECT_NAME}-quality-monitoring" \
        --statement-id eventbridge-quality-permission 2>/dev/null || log_warning "Failed to remove EventBridge quality permission (may not exist)"
    
    # Delete Lambda functions
    aws lambda delete-function --function-name "${PROJECT_NAME}-data-ingestion" 2>/dev/null || log_warning "Failed to delete ingestion function (may not exist)"
    aws lambda delete-function --function-name "${PROJECT_NAME}-data-validation" 2>/dev/null || log_warning "Failed to delete validation function (may not exist)"
    aws lambda delete-function --function-name "${PROJECT_NAME}-quality-monitoring" 2>/dev/null || log_warning "Failed to delete quality monitoring function (may not exist)"
    
    # Delete Lambda layer (get the latest version first)
    LAYER_VERSIONS=$(aws lambda list-layer-versions --layer-name ${LAMBDA_LAYER_NAME} --query 'LayerVersions[].Version' --output text 2>/dev/null)
    
    if [ ! -z "$LAYER_VERSIONS" ]; then
        for version in $LAYER_VERSIONS; do
            aws lambda delete-layer-version \
                --layer-name ${LAMBDA_LAYER_NAME} \
                --version-number $version 2>/dev/null || log_warning "Failed to delete layer version $version"
        done
    else
        log_warning "Lambda layer not found or already deleted"
    fi
    
    log_success "Lambda functions and layer removed"
}

# Remove Glue components
remove_glue_components() {
    log "Removing Glue components..."
    
    # Delete Glue crawler
    aws glue delete-crawler --name "${PROJECT_NAME}-crawler" 2>/dev/null || log_warning "Failed to delete Glue crawler (may not exist)"
    
    # Delete tables in Glue database first
    TABLES=$(aws glue get-tables --database-name ${GLUE_DATABASE} --query 'TableList[].Name' --output text 2>/dev/null)
    if [ ! -z "$TABLES" ]; then
        for table in $TABLES; do
            aws glue delete-table --database-name ${GLUE_DATABASE} --name $table 2>/dev/null || log_warning "Failed to delete table $table"
        done
    fi
    
    # Delete Glue database
    aws glue delete-database --name ${GLUE_DATABASE} 2>/dev/null || log_warning "Failed to delete Glue database (may not exist)"
    
    log_success "Glue components removed"
}

# Remove IAM roles and policies
remove_iam_roles() {
    log "Removing IAM roles and policies..."
    
    # Remove Lambda role policies and role
    aws iam delete-role-policy \
        --role-name ${PROJECT_NAME}-lambda-role \
        --policy-name ${PROJECT_NAME}-lambda-policy 2>/dev/null || log_warning "Failed to delete Lambda role policy (may not exist)"
    
    aws iam delete-role --role-name ${PROJECT_NAME}-lambda-role 2>/dev/null || log_warning "Failed to delete Lambda role (may not exist)"
    
    # Remove Glue role policies and role
    aws iam detach-role-policy \
        --role-name ${PROJECT_NAME}-glue-role \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || log_warning "Failed to detach Glue service role policy (may not exist)"
    
    aws iam delete-role-policy \
        --role-name ${PROJECT_NAME}-glue-role \
        --policy-name S3AccessPolicy 2>/dev/null || log_warning "Failed to delete Glue S3 policy (may not exist)"
    
    aws iam delete-role --role-name ${PROJECT_NAME}-glue-role 2>/dev/null || log_warning "Failed to delete Glue role (may not exist)"
    
    log_success "IAM roles and policies removed"
}

# Remove storage resources
remove_storage_resources() {
    log "Removing storage resources..."
    
    # Empty and delete S3 buckets
    log "Emptying S3 buckets..."
    aws s3 rm s3://${S3_BUCKET_RAW} --recursive 2>/dev/null || log_warning "Failed to empty raw data bucket (may not exist)"
    aws s3 rm s3://${S3_BUCKET_PROCESSED} --recursive 2>/dev/null || log_warning "Failed to empty processed data bucket (may not exist)"
    aws s3 rm s3://${S3_BUCKET_QUARANTINE} --recursive 2>/dev/null || log_warning "Failed to empty quarantine bucket (may not exist)"
    
    log "Deleting S3 buckets..."
    aws s3 rb s3://${S3_BUCKET_RAW} 2>/dev/null || log_warning "Failed to delete raw data bucket (may not exist)"
    aws s3 rb s3://${S3_BUCKET_PROCESSED} 2>/dev/null || log_warning "Failed to delete processed data bucket (may not exist)"
    aws s3 rb s3://${S3_BUCKET_QUARANTINE} 2>/dev/null || log_warning "Failed to delete quarantine bucket (may not exist)"
    
    # Delete DynamoDB table
    log "Deleting DynamoDB table..."
    aws dynamodb delete-table --table-name ${DYNAMODB_METADATA_TABLE} 2>/dev/null || log_warning "Failed to delete DynamoDB table (may not exist)"
    
    # Wait for DynamoDB table deletion to complete
    log "Waiting for DynamoDB table deletion to complete..."
    aws dynamodb wait table-not-exists --table-name ${DYNAMODB_METADATA_TABLE} 2>/dev/null || log_warning "DynamoDB table may not have existed"
    
    log_success "Storage resources removed"
}

# Remove S3 bucket notifications
remove_s3_notifications() {
    log "Removing S3 bucket notifications..."
    
    # Remove S3 bucket notification configuration
    aws s3api put-bucket-notification-configuration \
        --bucket ${S3_BUCKET_RAW} \
        --notification-configuration '{}' 2>/dev/null || log_warning "Failed to remove S3 notifications (bucket may not exist)"
    
    log_success "S3 bucket notifications removed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files that might be left over
    rm -f lambda-trust-policy.json lambda-policy.json glue-trust-policy.json glue-s3-policy.json
    rm -f s3-notification-config.json test-data.json invalid-data.json
    rm -f *.zip *.py
    rm -rf lambda-layer/
    
    # Ask user if they want to remove the deployment config
    if [ -f "deployment-config.json" ]; then
        echo ""
        read -p "Remove deployment-config.json? (y/n): " REMOVE_CONFIG
        if [ "$REMOVE_CONFIG" = "y" ] || [ "$REMOVE_CONFIG" = "Y" ]; then
            rm -f deployment-config.json
            log_success "Deployment configuration file removed"
        else
            log_warning "Deployment configuration file preserved"
        fi
    fi
    
    log_success "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    # Check if any resources still exist
    REMAINING_RESOURCES=0
    
    # Check S3 buckets
    if aws s3 ls s3://${S3_BUCKET_RAW} &>/dev/null; then
        log_warning "S3 bucket ${S3_BUCKET_RAW} still exists"
        ((REMAINING_RESOURCES++))
    fi
    
    if aws s3 ls s3://${S3_BUCKET_PROCESSED} &>/dev/null; then
        log_warning "S3 bucket ${S3_BUCKET_PROCESSED} still exists"
        ((REMAINING_RESOURCES++))
    fi
    
    if aws s3 ls s3://${S3_BUCKET_QUARANTINE} &>/dev/null; then
        log_warning "S3 bucket ${S3_BUCKET_QUARANTINE} still exists"
        ((REMAINING_RESOURCES++))
    fi
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name ${DYNAMODB_METADATA_TABLE} &>/dev/null; then
        log_warning "DynamoDB table ${DYNAMODB_METADATA_TABLE} still exists"
        ((REMAINING_RESOURCES++))
    fi
    
    # Check Lambda functions
    if aws lambda get-function --function-name "${PROJECT_NAME}-data-ingestion" &>/dev/null; then
        log_warning "Lambda function ${PROJECT_NAME}-data-ingestion still exists"
        ((REMAINING_RESOURCES++))
    fi
    
    if aws lambda get-function --function-name "${PROJECT_NAME}-data-validation" &>/dev/null; then
        log_warning "Lambda function ${PROJECT_NAME}-data-validation still exists"
        ((REMAINING_RESOURCES++))
    fi
    
    if aws lambda get-function --function-name "${PROJECT_NAME}-quality-monitoring" &>/dev/null; then
        log_warning "Lambda function ${PROJECT_NAME}-quality-monitoring still exists"
        ((REMAINING_RESOURCES++))
    fi
    
    # Check EventBridge bus
    if aws events describe-event-bus --name ${CUSTOM_EVENT_BUS} &>/dev/null; then
        log_warning "EventBridge bus ${CUSTOM_EVENT_BUS} still exists"
        ((REMAINING_RESOURCES++))
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name ${PROJECT_NAME}-lambda-role &>/dev/null; then
        log_warning "IAM role ${PROJECT_NAME}-lambda-role still exists"
        ((REMAINING_RESOURCES++))
    fi
    
    if aws iam get-role --role-name ${PROJECT_NAME}-glue-role &>/dev/null; then
        log_warning "IAM role ${PROJECT_NAME}-glue-role still exists"
        ((REMAINING_RESOURCES++))
    fi
    
    if [ $REMAINING_RESOURCES -eq 0 ]; then
        log_success "All resources successfully removed"
    else
        log_warning "$REMAINING_RESOURCES resources may still exist. Manual cleanup may be required."
        echo ""
        echo "You may need to:"
        echo "1. Check the AWS Console for any remaining resources"
        echo "2. Wait a few minutes for eventual consistency"
        echo "3. Manually delete any stubborn resources"
    fi
}

# Display cleanup summary
display_summary() {
    echo ""
    log_success "🎉 Advanced Serverless Data Lake Architecture cleanup completed!"
    echo ""
    echo "=== CLEANUP SUMMARY ==="
    echo "Project: ${PROJECT_NAME}"
    echo "Region: ${AWS_REGION}"
    echo ""
    echo "=== REMOVED RESOURCES ==="
    echo "✅ S3 Buckets (3)"
    echo "✅ DynamoDB Table"
    echo "✅ Lambda Functions (3)"
    echo "✅ Lambda Layer"
    echo "✅ EventBridge Bus and Rules"
    echo "✅ Glue Database and Crawler"
    echo "✅ IAM Roles and Policies (2)"
    echo ""
    echo "=== COST IMPACT ==="
    echo "• All ongoing costs for this project have been eliminated"
    echo "• No further charges will be incurred"
    echo ""
    if [ $REMAINING_RESOURCES -gt 0 ]; then
        echo "⚠️  Some resources may still exist. Please check the AWS Console."
        echo ""
    fi
    echo "Thank you for using the Advanced Serverless Data Lake Architecture!"
}

# Force cleanup mode (for CI/CD or automated scenarios)
force_cleanup() {
    log "Force cleanup mode enabled - skipping confirmations"
    
    remove_s3_notifications
    remove_eventbridge
    remove_lambda_functions
    remove_glue_components
    remove_iam_roles
    remove_storage_resources
    cleanup_local_files
    verify_cleanup
    display_summary
}

# Show help information
show_help() {
    echo "Usage: $0 [OPTIONS] [PROJECT_NAME]"
    echo ""
    echo "This script removes all AWS resources created by the deploy.sh script."
    echo ""
    echo "OPTIONS:"
    echo "  -f, --force     Skip confirmation prompts (use with caution)"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "ARGUMENTS:"
    echo "  PROJECT_NAME    Optional project name if deployment-config.json is missing"
    echo ""
    echo "EXAMPLES:"
    echo "  $0                                    # Interactive cleanup with config file"
    echo "  $0 my-datalake-project               # Cleanup specific project"
    echo "  $0 --force                           # Non-interactive cleanup"
    echo "  $0 --force my-datalake-project       # Non-interactive cleanup for specific project"
    echo ""
    echo "SAFETY:"
    echo "  • This script will permanently delete ALL project resources"
    echo "  • Data deletion cannot be undone"
    echo "  • Use --force only in automated environments"
    echo ""
}

# Main cleanup flow
main() {
    # Parse command line arguments
    FORCE_MODE=false
    PROJECT_ARG=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_MODE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                PROJECT_ARG="$1"
                shift
                ;;
        esac
    done
    
    echo "🧹 Starting Advanced Serverless Data Lake Architecture Cleanup"
    echo "=============================================================="
    
    check_prerequisites
    load_configuration "$PROJECT_ARG"
    
    if [ "$FORCE_MODE" = true ]; then
        force_cleanup
    else
        confirm_destruction
        
        remove_s3_notifications
        remove_eventbridge
        remove_lambda_functions
        remove_glue_components
        remove_iam_roles
        remove_storage_resources
        cleanup_local_files
        verify_cleanup
        display_summary
    fi
    
    log_success "Cleanup completed! 🎉"
}

# Execute main function with all arguments
main "$@"