#!/bin/bash

# Destroy script for Video Conferencing Solutions with Amazon Chime SDK
# This script safely removes all infrastructure created by the deploy script
# Author: AWS Recipes Project
# Version: 1.0

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE_DELETE=false
DRY_RUN=false
SKIP_CONFIRMATION=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --yes|-y)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force                Force deletion without safety checks"
            echo "  --dry-run              Show what would be deleted without executing"
            echo "  --yes, -y              Skip confirmation prompts"
            echo "  --project-name NAME    Specify project name to delete"
            echo "  --region REGION        Specify AWS region"
            echo "  --help, -h             Show this help message"
            echo ""
            echo "If no project name is specified, the script will attempt to load"
            echo "deployment state from the .deployment_state file."
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Get account information
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not set. Please specify with --region or configure default region."
        exit 1
    fi
    
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "AWS Region: $AWS_REGION"
    
    success "Prerequisites check completed successfully"
}

# Function to load deployment state
load_deployment_state() {
    local state_file="${SCRIPT_DIR}/../.deployment_state"
    
    if [ -f "$state_file" ]; then
        log "Loading deployment state from: $state_file"
        
        # Source the state file to load variables
        source "$state_file"
        
        log "Loaded deployment state:"
        log "  Project Name: ${PROJECT_NAME:-Not set}"
        log "  AWS Region: ${AWS_REGION:-Not set}"
        log "  S3 Bucket: ${BUCKET_NAME:-Not set}"
        log "  DynamoDB Table: ${TABLE_NAME:-Not set}"
        log "  API Gateway ID: ${API_ID:-Not set}"
        
        return 0
    else
        warn "Deployment state file not found: $state_file"
        return 1
    fi
}

# Function to prompt for confirmation
confirm_destruction() {
    if $SKIP_CONFIRMATION; then
        return 0
    fi
    
    echo ""
    warn "WARNING: This will permanently delete the following resources:"
    echo "  - S3 Bucket: ${BUCKET_NAME:-Unknown}"
    echo "  - DynamoDB Table: ${TABLE_NAME:-Unknown}"
    echo "  - Lambda Functions: ${MEETING_LAMBDA_NAME:-Unknown}, ${ATTENDEE_LAMBDA_NAME:-Unknown}"
    echo "  - API Gateway: ${API_ID:-Unknown}"
    echo "  - IAM Role: ${LAMBDA_ROLE_NAME:-Unknown}"
    echo "  - SNS Topic: ${SNS_TOPIC_NAME:-Unknown}"
    echo ""
    
    if $DRY_RUN; then
        warn "DRY RUN mode - no resources will actually be deleted"
        return 0
    fi
    
    read -p "Are you sure you want to delete these resources? (type 'DELETE' to confirm): " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed by user"
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case $resource_type in
        "s3-bucket")
            aws s3api head-bucket --bucket "$resource_name" 2>/dev/null
            ;;
        "dynamodb-table")
            aws dynamodb describe-table --table-name "$resource_name" --region "$AWS_REGION" &>/dev/null
            ;;
        "lambda-function")
            aws lambda get-function --function-name "$resource_name" --region "$AWS_REGION" &>/dev/null
            ;;
        "api-gateway")
            aws apigateway get-rest-api --rest-api-id "$resource_name" --region "$AWS_REGION" &>/dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_name" &>/dev/null
            ;;
        "sns-topic")
            aws sns get-topic-attributes --topic-arn "$resource_name" --region "$AWS_REGION" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to delete API Gateway
delete_api_gateway() {
    if [ -z "${API_ID:-}" ]; then
        warn "API Gateway ID not set, skipping deletion"
        return 0
    fi
    
    log "Deleting API Gateway: $API_ID"
    
    if $DRY_RUN; then
        log "DRY RUN: Would delete API Gateway $API_ID"
        return 0
    fi
    
    if resource_exists "api-gateway" "$API_ID"; then
        if aws apigateway delete-rest-api \
            --rest-api-id "$API_ID" \
            --region "$AWS_REGION"; then
            success "API Gateway deleted: $API_ID"
        else
            error "Failed to delete API Gateway: $API_ID"
            if ! $FORCE_DELETE; then
                exit 1
            fi
        fi
    else
        warn "API Gateway not found: $API_ID"
    fi
}

# Function to delete Lambda functions
delete_lambda_functions() {
    local lambda_functions=("${MEETING_LAMBDA_NAME:-}" "${ATTENDEE_LAMBDA_NAME:-}")
    
    for function_name in "${lambda_functions[@]}"; do
        if [ -z "$function_name" ]; then
            continue
        fi
        
        log "Deleting Lambda function: $function_name"
        
        if $DRY_RUN; then
            log "DRY RUN: Would delete Lambda function $function_name"
            continue
        fi
        
        if resource_exists "lambda-function" "$function_name"; then
            # Remove API Gateway permissions first
            aws lambda remove-permission \
                --function-name "$function_name" \
                --statement-id "apigateway-invoke-${function_name##*-}" \
                --region "$AWS_REGION" 2>/dev/null || true
            
            if aws lambda delete-function \
                --function-name "$function_name" \
                --region "$AWS_REGION"; then
                success "Lambda function deleted: $function_name"
            else
                error "Failed to delete Lambda function: $function_name"
                if ! $FORCE_DELETE; then
                    exit 1
                fi
            fi
        else
            warn "Lambda function not found: $function_name"
        fi
    done
}

# Function to delete IAM role
delete_iam_role() {
    if [ -z "${LAMBDA_ROLE_NAME:-}" ]; then
        warn "IAM role name not set, skipping deletion"
        return 0
    fi
    
    log "Deleting IAM role: $LAMBDA_ROLE_NAME"
    
    if $DRY_RUN; then
        log "DRY RUN: Would delete IAM role $LAMBDA_ROLE_NAME"
        return 0
    fi
    
    if resource_exists "iam-role" "$LAMBDA_ROLE_NAME"; then
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-name ChimeSDKPolicy 2>/dev/null || true
        
        # Delete role
        if aws iam delete-role --role-name "$LAMBDA_ROLE_NAME"; then
            success "IAM role deleted: $LAMBDA_ROLE_NAME"
        else
            error "Failed to delete IAM role: $LAMBDA_ROLE_NAME"
            if ! $FORCE_DELETE; then
                exit 1
            fi
        fi
    else
        warn "IAM role not found: $LAMBDA_ROLE_NAME"
    fi
}

# Function to delete DynamoDB table
delete_dynamodb_table() {
    if [ -z "${TABLE_NAME:-}" ]; then
        warn "DynamoDB table name not set, skipping deletion"
        return 0
    fi
    
    log "Deleting DynamoDB table: $TABLE_NAME"
    
    if $DRY_RUN; then
        log "DRY RUN: Would delete DynamoDB table $TABLE_NAME"
        return 0
    fi
    
    if resource_exists "dynamodb-table" "$TABLE_NAME"; then
        if aws dynamodb delete-table \
            --table-name "$TABLE_NAME" \
            --region "$AWS_REGION" > /dev/null; then
            
            log "Waiting for DynamoDB table deletion to complete..."
            aws dynamodb wait table-not-exists \
                --table-name "$TABLE_NAME" \
                --region "$AWS_REGION" 2>/dev/null || true
            
            success "DynamoDB table deleted: $TABLE_NAME"
        else
            error "Failed to delete DynamoDB table: $TABLE_NAME"
            if ! $FORCE_DELETE; then
                exit 1
            fi
        fi
    else
        warn "DynamoDB table not found: $TABLE_NAME"
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    if [ -z "${BUCKET_NAME:-}" ]; then
        warn "S3 bucket name not set, skipping deletion"
        return 0
    fi
    
    log "Deleting S3 bucket: $BUCKET_NAME"
    
    if $DRY_RUN; then
        log "DRY RUN: Would delete S3 bucket $BUCKET_NAME and all contents"
        return 0
    fi
    
    if resource_exists "s3-bucket" "$BUCKET_NAME"; then
        # Delete all objects and versions
        log "Removing all objects from S3 bucket..."
        aws s3 rm "s3://${BUCKET_NAME}" --recursive 2>/dev/null || true
        
        # Delete all object versions (if versioning is enabled)
        aws s3api delete-objects \
            --bucket "$BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --output json \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true
        
        # Delete all delete markers
        aws s3api delete-objects \
            --bucket "$BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --output json \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true
        
        # Delete bucket
        if aws s3 rb "s3://${BUCKET_NAME}" --force; then
            success "S3 bucket deleted: $BUCKET_NAME"
        else
            error "Failed to delete S3 bucket: $BUCKET_NAME"
            if ! $FORCE_DELETE; then
                exit 1
            fi
        fi
    else
        warn "S3 bucket not found: $BUCKET_NAME"
    fi
}

# Function to delete SNS topic
delete_sns_topic() {
    if [ -z "${SNS_TOPIC_ARN:-}" ]; then
        warn "SNS topic ARN not set, skipping deletion"
        return 0
    fi
    
    log "Deleting SNS topic: $SNS_TOPIC_ARN"
    
    if $DRY_RUN; then
        log "DRY RUN: Would delete SNS topic $SNS_TOPIC_ARN"
        return 0
    fi
    
    if resource_exists "sns-topic" "$SNS_TOPIC_ARN"; then
        if aws sns delete-topic \
            --topic-arn "$SNS_TOPIC_ARN" \
            --region "$AWS_REGION"; then
            success "SNS topic deleted: $SNS_TOPIC_ARN"
        else
            error "Failed to delete SNS topic: $SNS_TOPIC_ARN"
            if ! $FORCE_DELETE; then
                exit 1
            fi
        fi
    else
        warn "SNS topic not found: $SNS_TOPIC_ARN"
    fi
}

# Function to delete active meetings (cleanup)
cleanup_active_meetings() {
    log "Checking for active Chime SDK meetings..."
    
    if $DRY_RUN; then
        log "DRY RUN: Would check and cleanup active meetings"
        return 0
    fi
    
    # List and delete any active meetings (requires special permissions)
    # Note: This is best effort cleanup - meetings may not be visible due to permissions
    if aws chime list-meetings --region us-east-1 &>/dev/null; then
        local meetings=$(aws chime list-meetings --region us-east-1 --output json --query 'Meetings[].MeetingId' 2>/dev/null || echo '[]')
        
        if [ "$meetings" != "[]" ] && [ "${meetings}" != "" ]; then
            warn "Found active meetings. Attempting cleanup..."
            echo "$meetings" | jq -r '.[]' 2>/dev/null | while read -r meeting_id; do
                if [ -n "$meeting_id" ] && [ "$meeting_id" != "null" ]; then
                    log "Deleting meeting: $meeting_id"
                    aws chime delete-meeting --meeting-id "$meeting_id" --region us-east-1 2>/dev/null || true
                fi
            done
        fi
    else
        warn "Cannot list Chime meetings - may require additional permissions"
    fi
}

# Function to remove deployment state file
remove_deployment_state() {
    local state_file="${SCRIPT_DIR}/../.deployment_state"
    
    if [ -f "$state_file" ]; then
        log "Removing deployment state file..."
        
        if $DRY_RUN; then
            log "DRY RUN: Would remove deployment state file"
            return 0
        fi
        
        if rm "$state_file"; then
            success "Deployment state file removed"
        else
            warn "Failed to remove deployment state file: $state_file"
        fi
    fi
}

# Function to display destruction summary
display_summary() {
    log "Destruction Summary"
    echo "=================================="
    
    if $DRY_RUN; then
        echo "DRY RUN - The following would have been deleted:"
    else
        echo "The following resources were processed for deletion:"
    fi
    
    echo "Project Name: ${PROJECT_NAME:-Not set}"
    echo "AWS Region: ${AWS_REGION:-Not set}"
    echo "S3 Bucket: ${BUCKET_NAME:-Not set}"
    echo "DynamoDB Table: ${TABLE_NAME:-Not set}"
    echo "SNS Topic: ${SNS_TOPIC_ARN:-Not set}"
    echo "Lambda Role: ${LAMBDA_ROLE_NAME:-Not set}"
    echo "Meeting Lambda: ${MEETING_LAMBDA_NAME:-Not set}"
    echo "Attendee Lambda: ${ATTENDEE_LAMBDA_NAME:-Not set}"
    echo "API Gateway: ${API_ID:-Not set}"
    echo "=================================="
    
    if ! $DRY_RUN; then
        echo ""
        echo "Cleanup Notes:"
        echo "1. All AWS resources have been removed"
        echo "2. Check AWS Console to verify complete cleanup"
        echo "3. Any remaining charges should stop within 24 hours"
        echo "4. CloudWatch logs will be retained per AWS default retention"
    fi
}

# Function to validate state before destruction
validate_state() {
    local missing_vars=()
    
    if [ -z "${PROJECT_NAME:-}" ]; then missing_vars+=("PROJECT_NAME"); fi
    if [ -z "${AWS_REGION:-}" ]; then missing_vars+=("AWS_REGION"); fi
    
    if [ ${#missing_vars[@]} -gt 0 ] && [ -z "${PROJECT_NAME:-}" ]; then
        error "Critical deployment variables missing: ${missing_vars[*]}"
        error "Cannot proceed with cleanup. Please specify --project-name or ensure .deployment_state file exists."
        exit 1
    fi
    
    # If PROJECT_NAME is specified but other variables are missing, try to derive them
    if [ -n "${PROJECT_NAME:-}" ] && [ ${#missing_vars[@]} -gt 1 ]; then
        warn "Some deployment variables missing. Attempting to derive from project name..."
        
        # Set derived names if not already set
        export BUCKET_NAME="${BUCKET_NAME:-${PROJECT_NAME}-recordings}"
        export TABLE_NAME="${TABLE_NAME:-${PROJECT_NAME}-meetings}"
        export SNS_TOPIC_NAME="${SNS_TOPIC_NAME:-${PROJECT_NAME}-events}"
        export SNS_TOPIC_ARN="${SNS_TOPIC_ARN:-arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}}"
        export LAMBDA_ROLE_NAME="${LAMBDA_ROLE_NAME:-${PROJECT_NAME}-lambda-role}"
        export MEETING_LAMBDA_NAME="${MEETING_LAMBDA_NAME:-${PROJECT_NAME}-meeting-handler}"
        export ATTENDEE_LAMBDA_NAME="${ATTENDEE_LAMBDA_NAME:-${PROJECT_NAME}-attendee-handler}"
        export API_NAME="${API_NAME:-${PROJECT_NAME}-api}"
    fi
}

# Main destruction function
main() {
    log "Starting destruction of Video Conferencing with Amazon Chime SDK"
    
    if $DRY_RUN; then
        warn "Running in DRY RUN mode - no resources will be deleted"
    fi
    
    check_prerequisites
    
    # Try to load deployment state, but don't fail if missing
    if [ -z "${PROJECT_NAME:-}" ]; then
        if ! load_deployment_state; then
            error "No deployment state found and no project name specified"
            error "Please specify --project-name or ensure .deployment_state file exists"
            exit 1
        fi
    fi
    
    validate_state
    confirm_destruction
    
    # Delete resources in reverse order of creation
    cleanup_active_meetings
    delete_api_gateway
    delete_lambda_functions
    delete_iam_role
    delete_dynamodb_table
    delete_sns_topic
    delete_s3_bucket
    
    if ! $DRY_RUN; then
        remove_deployment_state
    fi
    
    display_summary
    
    if $DRY_RUN; then
        warn "This was a DRY RUN - no actual resources were deleted"
    else
        success "Destruction completed successfully!"
    fi
}

# Error handling
trap 'error "Destruction failed at line $LINENO. Exit code: $?" >&2' ERR

# Run main function
main "$@"