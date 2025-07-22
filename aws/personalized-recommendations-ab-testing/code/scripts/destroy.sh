#!/bin/bash

# Cleanup script for Real-Time Recommendations with Personalize and A/B Testing
# This script removes all infrastructure created by the deployment script

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
CONFIG_FILE="${SCRIPT_DIR}/deployment_config.env"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$ERROR_LOG"
}

# Error handling for cleanup
cleanup_on_error() {
    log_error "Cleanup failed. Check $ERROR_LOG for details."
    log_warning "Some resources may still exist. Manual cleanup may be required."
    exit 1
}

# Set trap to handle errors (but don't exit on error during cleanup)
set +e

# Function to safely run commands and log results
safe_run() {
    local cmd="$1"
    local description="$2"
    
    if eval "$cmd" &>> "$LOG_FILE"; then
        log_success "$description"
        return 0
    else
        log_warning "Failed: $description"
        return 1
    fi
}

# Load configuration
load_configuration() {
    log_info "Loading deployment configuration..."
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        log_error "Cannot proceed with cleanup. Run this script from the same directory as deploy.sh"
        exit 1
    fi
    
    # Source the configuration
    source "$CONFIG_FILE"
    
    # Verify required variables
    if [ -z "$PROJECT_NAME" ] || [ -z "$AWS_REGION" ] || [ -z "$AWS_ACCOUNT_ID" ]; then
        log_error "Required configuration variables not found"
        exit 1
    fi
    
    log_success "Configuration loaded for project: $PROJECT_NAME"
}

# Confirmation prompt
confirm_destruction() {
    log_warning "This will delete ALL resources for project: $PROJECT_NAME"
    log_warning "This action is IRREVERSIBLE!"
    
    if [ "$1" = "--force" ] || [ "$1" = "-f" ]; then
        log_info "Force flag detected, skipping confirmation"
        return 0
    fi
    
    echo -n "Are you sure you want to continue? Type 'yes' to confirm: "
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "User confirmed destruction"
}

# Delete API Gateway
delete_api_gateway() {
    log_info "Deleting API Gateway..."
    
    if [ -n "$API_ID" ]; then
        # Remove Lambda permissions first
        safe_run "aws lambda remove-permission \
            --function-name '${PROJECT_NAME}-ab-test-router' \
            --statement-id api-gateway-invoke-1 2>/dev/null" \
            "Removed Lambda permission for A/B router"
        
        safe_run "aws lambda remove-permission \
            --function-name '${PROJECT_NAME}-event-tracker' \
            --statement-id api-gateway-invoke-2 2>/dev/null" \
            "Removed Lambda permission for event tracker"
        
        # Delete API Gateway
        safe_run "aws apigatewayv2 delete-api --api-id '$API_ID'" \
            "Deleted API Gateway: $API_ID"
    else
        log_warning "API_ID not found in configuration"
    fi
}

# Delete Lambda functions
delete_lambda_functions() {
    log_info "Deleting Lambda functions..."
    
    local functions=(
        "${PROJECT_NAME}-ab-test-router"
        "${PROJECT_NAME}-recommendation-engine"
        "${PROJECT_NAME}-event-tracker"
        "${PROJECT_NAME}-personalize-manager"
    )
    
    for func in "${functions[@]}"; do
        safe_run "aws lambda delete-function --function-name '$func'" \
            "Deleted Lambda function: $func"
    done
}

# Delete DynamoDB tables
delete_dynamodb_tables() {
    log_info "Deleting DynamoDB tables..."
    
    local tables=(
        "${PROJECT_NAME}-users"
        "${PROJECT_NAME}-items"
        "${PROJECT_NAME}-ab-assignments"
        "${PROJECT_NAME}-events"
    )
    
    for table in "${tables[@]}"; do
        safe_run "aws dynamodb delete-table --table-name '$table'" \
            "Deleted DynamoDB table: $table"
    done
    
    # Wait for tables to be deleted
    log_info "Waiting for DynamoDB tables to be deleted..."
    for table in "${tables[@]}"; do
        aws dynamodb wait table-not-exists --table-name "$table" 2>/dev/null || true
    done
    
    log_success "All DynamoDB tables deleted"
}

# Delete S3 bucket and contents
delete_s3_bucket() {
    log_info "Deleting S3 bucket and contents..."
    
    if [ -n "$BUCKET_NAME" ]; then
        # Remove all objects from bucket
        safe_run "aws s3 rm 's3://${BUCKET_NAME}' --recursive" \
            "Removed all objects from S3 bucket"
        
        # Delete bucket
        safe_run "aws s3 rb 's3://${BUCKET_NAME}'" \
            "Deleted S3 bucket: $BUCKET_NAME"
    else
        log_warning "BUCKET_NAME not found in configuration"
    fi
}

# Delete IAM role and policies
delete_iam_resources() {
    log_info "Deleting IAM resources..."
    
    if [ -n "$ROLE_NAME" ]; then
        # Detach policies
        local policies=(
            "arn:aws:iam::aws:policy/service-role/AmazonPersonalizeFullAccess"
            "arn:aws:iam::aws:policy/AmazonS3FullAccess"
            "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
            "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
            "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
        )
        
        for policy in "${policies[@]}"; do
            safe_run "aws iam detach-role-policy \
                --role-name '$ROLE_NAME' \
                --policy-arn '$policy'" \
                "Detached policy: $(basename $policy)"
        done
        
        # Delete role
        safe_run "aws iam delete-role --role-name '$ROLE_NAME'" \
            "Deleted IAM role: $ROLE_NAME"
    else
        log_warning "ROLE_NAME not found in configuration"
    fi
}

# Delete Personalize resources
delete_personalize_resources() {
    log_info "Checking for Personalize resources to delete..."
    
    # Note: Personalize resources are not automatically created by the deploy script
    # This is a placeholder for manual cleanup guidance
    
    log_warning "Personalize resources (if any) must be manually deleted:"
    log_warning "1. Campaigns created for this project"
    log_warning "2. Solutions and solution versions"
    log_warning "3. Datasets and dataset groups"
    log_warning "4. Event trackers"
    log_warning "Use the AWS Console or CLI to delete these resources"
    
    # Try to list any resources that might exist
    log_info "Listing potential Personalize resources..."
    
    # List dataset groups
    if aws personalize list-dataset-groups --query "datasetGroups[?contains(name, '${PROJECT_NAME}')].{Name:name,Arn:datasetGroupArn}" --output table 2>/dev/null; then
        log_warning "Found Personalize dataset groups. Please delete manually."
    fi
    
    # List campaigns
    if aws personalize list-campaigns --query "campaigns[?contains(name, '${PROJECT_NAME}')].{Name:name,Arn:campaignArn}" --output table 2>/dev/null; then
        log_warning "Found Personalize campaigns. Please delete manually."
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files=(
        "trust-policy.json"
        "ab_test_router.py"
        "ab_test_router.zip"
        "recommendation_engine.py"
        "recommendation_engine.zip"
        "event_tracker.py"
        "event_tracker.zip"
        "personalize_manager.py"
        "personalize_manager.zip"
        "generate_sample_data.py"
        "load_dynamodb_data.py"
    )
    
    for file in "${files[@]}"; do
        if [ -f "${SCRIPT_DIR}/$file" ]; then
            safe_run "rm -f '${SCRIPT_DIR}/$file'" \
                "Removed local file: $file"
        fi
    done
    
    # Remove sample data directory
    if [ -d "${SCRIPT_DIR}/sample-data" ]; then
        safe_run "rm -rf '${SCRIPT_DIR}/sample-data'" \
            "Removed sample data directory"
    fi
    
    # Ask user if they want to remove logs and config
    echo -n "Remove log files and deployment configuration? (y/N): "
    read -r remove_logs
    
    if [ "$remove_logs" = "y" ] || [ "$remove_logs" = "Y" ]; then
        safe_run "rm -f '$LOG_FILE' '$ERROR_LOG' '$CONFIG_FILE'" \
            "Removed log files and configuration"
    else
        log_info "Keeping log files and configuration for reference"
    fi
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local remaining_resources=0
    
    # Check Lambda functions
    if aws lambda list-functions --query "Functions[?contains(FunctionName, '${PROJECT_NAME}')].FunctionName" --output text 2>/dev/null | grep -q "${PROJECT_NAME}"; then
        log_warning "Some Lambda functions may still exist"
        remaining_resources=$((remaining_resources + 1))
    fi
    
    # Check DynamoDB tables
    if aws dynamodb list-tables --query "TableNames[?contains(@, '${PROJECT_NAME}')]" --output text 2>/dev/null | grep -q "${PROJECT_NAME}"; then
        log_warning "Some DynamoDB tables may still exist"
        remaining_resources=$((remaining_resources + 1))
    fi
    
    # Check S3 bucket
    if [ -n "$BUCKET_NAME" ] && aws s3 ls "s3://${BUCKET_NAME}" &>/dev/null; then
        log_warning "S3 bucket may still exist: $BUCKET_NAME"
        remaining_resources=$((remaining_resources + 1))
    fi
    
    # Check IAM role
    if [ -n "$ROLE_NAME" ] && aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        log_warning "IAM role may still exist: $ROLE_NAME"
        remaining_resources=$((remaining_resources + 1))
    fi
    
    if [ $remaining_resources -eq 0 ]; then
        log_success "All tracked resources have been cleaned up"
    else
        log_warning "Some resources may still exist. Check the warnings above."
        log_warning "You may need to manually delete remaining resources to avoid charges."
    fi
}

# Generate cleanup report
generate_cleanup_report() {
    local report_file="${SCRIPT_DIR}/cleanup_report.txt"
    
    cat > "$report_file" << EOF
Cleanup Report for Real-Time Recommendations with Personalize and A/B Testing
============================================================================

Project Name: ${PROJECT_NAME}
AWS Region: ${AWS_REGION}
AWS Account: ${AWS_ACCOUNT_ID}
Cleanup Date: $(date)

Resources that were attempted to be deleted:
- API Gateway: ${API_ID:-"Not found"}
- Lambda Functions:
  * ${PROJECT_NAME}-ab-test-router
  * ${PROJECT_NAME}-recommendation-engine
  * ${PROJECT_NAME}-event-tracker
  * ${PROJECT_NAME}-personalize-manager
- DynamoDB Tables:
  * ${PROJECT_NAME}-users
  * ${PROJECT_NAME}-items
  * ${PROJECT_NAME}-ab-assignments
  * ${PROJECT_NAME}-events
- S3 Bucket: ${BUCKET_NAME:-"Not found"}
- IAM Role: ${ROLE_NAME:-"Not found"}

Manual cleanup required for:
- Amazon Personalize resources (campaigns, solutions, datasets, dataset groups)
- Any custom CloudWatch alarms or dashboards
- Any custom IAM policies created for this project

For detailed cleanup status, check the log files:
- Main log: ${LOG_FILE}
- Error log: ${ERROR_LOG}

Note: This report was generated automatically and may not reflect the actual
state of all resources. Please verify in the AWS Console.
EOF
    
    log_info "Cleanup report generated: $report_file"
}

# Cost estimation warning
show_cost_warning() {
    log_warning "IMPORTANT: Cost Management Reminder"
    log_warning "=========================================="
    log_warning "Even after running this cleanup script, you may still incur charges for:"
    log_warning "1. Amazon Personalize models and campaigns (if created manually)"
    log_warning "2. CloudWatch Logs retention"
    log_warning "3. Any data stored in other AWS services"
    log_warning "4. Network transfer costs"
    log_warning ""
    log_warning "Please check your AWS billing dashboard to ensure all charges have stopped."
    log_warning "Consider setting up billing alerts if you haven't already."
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Real-Time Recommendations with Personalize and A/B Testing"
    log_info "Cleanup started at $(date)"
    
    # Initialize logging
    : > "$LOG_FILE"
    : > "$ERROR_LOG"
    
    # Load configuration and confirm
    load_configuration
    confirm_destruction "$1"
    
    # Show cost warning
    show_cost_warning
    
    # Run cleanup steps (order matters - reverse of deployment)
    delete_api_gateway
    delete_lambda_functions
    delete_dynamodb_tables
    delete_s3_bucket
    delete_iam_resources
    delete_personalize_resources
    cleanup_local_files
    
    # Verification and reporting
    verify_cleanup
    generate_cleanup_report
    
    log_success "Cleanup completed at $(date)"
    log_info "Please review the cleanup report and verify no unexpected charges occur."
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up all resources created by the Real-Time Recommendations deployment.

OPTIONS:
    -f, --force     Skip confirmation prompt
    -h, --help      Show this help message

EXAMPLES:
    $0              # Interactive cleanup with confirmation
    $0 --force      # Automatic cleanup without confirmation
    $0 -h           # Show help

NOTES:
    - This script must be run from the same directory as deploy.sh
    - Some Personalize resources may require manual deletion
    - Review the cleanup report after completion
    - Check your AWS billing dashboard to verify no unexpected charges

EOF
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -f|--force)
        main "$1"
        ;;
    "")
        main
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
esac