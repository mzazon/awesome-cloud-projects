#!/bin/bash
set -e

# Real-Time IoT Analytics Cleanup Script
# This script removes all resources created by the IoT analytics pipeline

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
DRY_RUN=false
VERBOSE=false
SKIP_CONFIRMATION=false
FORCE=false
PROJECT_NAME=""

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

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleanup Real-Time IoT Analytics Pipeline Resources

Options:
    -p, --project-name NAME Project name prefix for resources to delete (required)
    -d, --dry-run          Show what would be deleted without actually deleting
    -v, --verbose          Enable verbose output
    -y, --yes              Skip confirmation prompts
    -f, --force            Force deletion even if some resources fail
    -h, --help             Show this help message

Examples:
    $0 --project-name iot-analytics-abc123
    $0 --project-name iot-analytics-abc123 --dry-run
    $0 --project-name iot-analytics-abc123 --force --yes

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$PROJECT_NAME" ]]; then
    log_error "Project name is required"
    usage
    exit 1
fi

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is required but not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get AWS account details
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region not configured"
        exit 1
    fi
    
    # Set resource names based on project name
    export KINESIS_STREAM_NAME="${PROJECT_NAME}-stream"
    export FLINK_APP_NAME="${PROJECT_NAME}-flink-app"
    export LAMBDA_FUNCTION_NAME="${PROJECT_NAME}-processor"
    export S3_BUCKET_NAME="${PROJECT_NAME}-data-${AWS_ACCOUNT_ID}"
    export SNS_TOPIC_NAME="${PROJECT_NAME}-alerts"
    
    log_success "Environment variables configured"
    log_info "Project Name: $PROJECT_NAME"
    log_info "Region: $AWS_REGION"
    log_info "Account ID: $AWS_ACCOUNT_ID"
}

# Function to find and list resources
find_resources() {
    log_info "Scanning for resources to delete..."
    
    local resources_found=false
    
    # Check Kinesis stream
    if aws kinesis describe-stream --stream-name "$KINESIS_STREAM_NAME" &> /dev/null; then
        log_info "Found Kinesis stream: $KINESIS_STREAM_NAME"
        resources_found=true
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        log_info "Found Lambda function: $LAMBDA_FUNCTION_NAME"
        resources_found=true
    fi
    
    # Check Flink application
    if aws kinesisanalyticsv2 describe-application --application-name "$FLINK_APP_NAME" &> /dev/null; then
        log_info "Found Flink application: $FLINK_APP_NAME"
        resources_found=true
    fi
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" &> /dev/null; then
        log_info "Found S3 bucket: $S3_BUCKET_NAME"
        resources_found=true
    fi
    
    # Check SNS topic
    local topic_arn=$(aws sns list-topics --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text)
    if [[ -n "$topic_arn" ]]; then
        log_info "Found SNS topic: $topic_arn"
        export TOPIC_ARN="$topic_arn"
        resources_found=true
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name "${PROJECT_NAME}-lambda-role" &> /dev/null; then
        log_info "Found Lambda IAM role: ${PROJECT_NAME}-lambda-role"
        resources_found=true
    fi
    
    if aws iam get-role --role-name "${PROJECT_NAME}-flink-role" &> /dev/null; then
        log_info "Found Flink IAM role: ${PROJECT_NAME}-flink-role"
        resources_found=true
    fi
    
    # Check CloudWatch alarms
    local alarms=$(aws cloudwatch describe-alarms --alarm-names "${PROJECT_NAME}-kinesis-records" "${PROJECT_NAME}-lambda-errors" --query "MetricAlarms[].AlarmName" --output text 2>/dev/null)
    if [[ -n "$alarms" ]]; then
        log_info "Found CloudWatch alarms: $alarms"
        resources_found=true
    fi
    
    # Check CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name "${PROJECT_NAME}-analytics" &> /dev/null; then
        log_info "Found CloudWatch dashboard: ${PROJECT_NAME}-analytics"
        resources_found=true
    fi
    
    if [[ "$resources_found" != "true" ]]; then
        log_warning "No resources found with project name: $PROJECT_NAME"
        exit 0
    fi
    
    log_success "Resource discovery completed"
}

# Function to stop Flink application
stop_flink_application() {
    log_info "Stopping Flink application..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would stop Flink application: $FLINK_APP_NAME"
        return 0
    fi
    
    # Check if application exists
    if ! aws kinesisanalyticsv2 describe-application --application-name "$FLINK_APP_NAME" &> /dev/null; then
        log_warning "Flink application not found: $FLINK_APP_NAME"
        return 0
    fi
    
    # Get application status
    local app_status=$(aws kinesisanalyticsv2 describe-application \
        --application-name "$FLINK_APP_NAME" \
        --query 'ApplicationDetail.ApplicationStatus' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$app_status" == "RUNNING" ]]; then
        log_info "Stopping Flink application..."
        if aws kinesisanalyticsv2 stop-application --application-name "$FLINK_APP_NAME"; then
            log_success "Flink application stop initiated"
            
            # Wait for application to stop
            log_info "Waiting for application to stop..."
            local attempts=0
            while [[ $attempts -lt 30 ]]; do
                app_status=$(aws kinesisanalyticsv2 describe-application \
                    --application-name "$FLINK_APP_NAME" \
                    --query 'ApplicationDetail.ApplicationStatus' \
                    --output text 2>/dev/null || echo "STOPPED")
                
                if [[ "$app_status" == "READY" ]]; then
                    log_success "Flink application stopped"
                    break
                fi
                
                sleep 10
                ((attempts++))
            done
            
            if [[ $attempts -ge 30 ]]; then
                log_warning "Timeout waiting for Flink application to stop"
                if [[ "$FORCE" != "true" ]]; then
                    return 1
                fi
            fi
        else
            log_error "Failed to stop Flink application"
            if [[ "$FORCE" != "true" ]]; then
                return 1
            fi
        fi
    else
        log_info "Flink application is not running (status: $app_status)"
    fi
    
    # Delete the application
    log_info "Deleting Flink application..."
    if aws kinesisanalyticsv2 delete-application \
        --application-name "$FLINK_APP_NAME" \
        --create-timestamp "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"; then
        log_success "Flink application deleted"
    else
        log_error "Failed to delete Flink application"
        if [[ "$FORCE" != "true" ]]; then
            return 1
        fi
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    log_info "Deleting Lambda function and event source mapping..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Lambda function: $LAMBDA_FUNCTION_NAME"
        return 0
    fi
    
    # Check if function exists
    if ! aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        log_warning "Lambda function not found: $LAMBDA_FUNCTION_NAME"
        return 0
    fi
    
    # Get and delete event source mappings
    local mappings=$(aws lambda list-event-source-mappings \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'EventSourceMappings[].UUID' \
        --output text 2>/dev/null)
    
    if [[ -n "$mappings" ]]; then
        for mapping_uuid in $mappings; do
            log_info "Deleting event source mapping: $mapping_uuid"
            if aws lambda delete-event-source-mapping --uuid "$mapping_uuid"; then
                log_success "Event source mapping deleted"
            else
                log_error "Failed to delete event source mapping"
                if [[ "$FORCE" != "true" ]]; then
                    return 1
                fi
            fi
        done
    fi
    
    # Delete Lambda function
    if aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"; then
        log_success "Lambda function deleted"
    else
        log_error "Failed to delete Lambda function"
        if [[ "$FORCE" != "true" ]]; then
            return 1
        fi
    fi
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log_info "Deleting CloudWatch resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete CloudWatch alarms and dashboard"
        return 0
    fi
    
    # Delete CloudWatch alarms
    local alarms=("${PROJECT_NAME}-kinesis-records" "${PROJECT_NAME}-lambda-errors")
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" &> /dev/null; then
            log_info "Deleting CloudWatch alarm: $alarm"
            if aws cloudwatch delete-alarms --alarm-names "$alarm"; then
                log_success "CloudWatch alarm deleted: $alarm"
            else
                log_error "Failed to delete CloudWatch alarm: $alarm"
                if [[ "$FORCE" != "true" ]]; then
                    return 1
                fi
            fi
        fi
    done
    
    # Delete CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name "${PROJECT_NAME}-analytics" &> /dev/null; then
        log_info "Deleting CloudWatch dashboard: ${PROJECT_NAME}-analytics"
        if aws cloudwatch delete-dashboards --dashboard-names "${PROJECT_NAME}-analytics"; then
            log_success "CloudWatch dashboard deleted"
        else
            log_error "Failed to delete CloudWatch dashboard"
            if [[ "$FORCE" != "true" ]]; then
                return 1
            fi
        fi
    fi
    
    log_success "CloudWatch resources cleaned up"
}

# Function to delete Kinesis stream
delete_kinesis_stream() {
    log_info "Deleting Kinesis stream..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Kinesis stream: $KINESIS_STREAM_NAME"
        return 0
    fi
    
    # Check if stream exists
    if ! aws kinesis describe-stream --stream-name "$KINESIS_STREAM_NAME" &> /dev/null; then
        log_warning "Kinesis stream not found: $KINESIS_STREAM_NAME"
        return 0
    fi
    
    # Delete stream
    if aws kinesis delete-stream --stream-name "$KINESIS_STREAM_NAME"; then
        log_success "Kinesis stream deletion initiated"
        
        # Wait for stream to be deleted
        log_info "Waiting for stream to be deleted..."
        local attempts=0
        while [[ $attempts -lt 30 ]]; do
            if ! aws kinesis describe-stream --stream-name "$KINESIS_STREAM_NAME" &> /dev/null; then
                log_success "Kinesis stream deleted"
                break
            fi
            sleep 10
            ((attempts++))
        done
        
        if [[ $attempts -ge 30 ]]; then
            log_warning "Timeout waiting for Kinesis stream deletion"
            if [[ "$FORCE" != "true" ]]; then
                return 1
            fi
        fi
    else
        log_error "Failed to delete Kinesis stream"
        if [[ "$FORCE" != "true" ]]; then
            return 1
        fi
    fi
}

# Function to delete SNS topic
delete_sns_topic() {
    log_info "Deleting SNS topic..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete SNS topic: $SNS_TOPIC_NAME"
        return 0
    fi
    
    # Find topic ARN
    local topic_arn=$(aws sns list-topics --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text)
    
    if [[ -z "$topic_arn" ]]; then
        log_warning "SNS topic not found: $SNS_TOPIC_NAME"
        return 0
    fi
    
    # Delete topic
    if aws sns delete-topic --topic-arn "$topic_arn"; then
        log_success "SNS topic deleted"
    else
        log_error "Failed to delete SNS topic"
        if [[ "$FORCE" != "true" ]]; then
            return 1
        fi
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log_info "Deleting S3 bucket..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete S3 bucket: $S3_BUCKET_NAME"
        return 0
    fi
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$S3_BUCKET_NAME" &> /dev/null; then
        log_warning "S3 bucket not found: $S3_BUCKET_NAME"
        return 0
    fi
    
    # Delete all objects in bucket
    log_info "Deleting all objects in S3 bucket..."
    if aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive; then
        log_success "S3 bucket objects deleted"
    else
        log_error "Failed to delete S3 bucket objects"
        if [[ "$FORCE" != "true" ]]; then
            return 1
        fi
    fi
    
    # Delete bucket
    if aws s3 rb "s3://${S3_BUCKET_NAME}"; then
        log_success "S3 bucket deleted"
    else
        log_error "Failed to delete S3 bucket"
        if [[ "$FORCE" != "true" ]]; then
            return 1
        fi
    fi
}

# Function to delete IAM roles
delete_iam_roles() {
    log_info "Deleting IAM roles..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete IAM roles: ${PROJECT_NAME}-lambda-role, ${PROJECT_NAME}-flink-role"
        return 0
    fi
    
    # Delete Lambda IAM role
    if aws iam get-role --role-name "${PROJECT_NAME}-lambda-role" &> /dev/null; then
        log_info "Deleting Lambda IAM role policies..."
        
        # Delete inline policies
        local policies=$(aws iam list-role-policies --role-name "${PROJECT_NAME}-lambda-role" --query 'PolicyNames[]' --output text)
        for policy in $policies; do
            if aws iam delete-role-policy --role-name "${PROJECT_NAME}-lambda-role" --policy-name "$policy"; then
                log_success "Deleted policy: $policy"
            else
                log_error "Failed to delete policy: $policy"
                if [[ "$FORCE" != "true" ]]; then
                    return 1
                fi
            fi
        done
        
        # Delete role
        if aws iam delete-role --role-name "${PROJECT_NAME}-lambda-role"; then
            log_success "Lambda IAM role deleted"
        else
            log_error "Failed to delete Lambda IAM role"
            if [[ "$FORCE" != "true" ]]; then
                return 1
            fi
        fi
    else
        log_warning "Lambda IAM role not found: ${PROJECT_NAME}-lambda-role"
    fi
    
    # Delete Flink IAM role
    if aws iam get-role --role-name "${PROJECT_NAME}-flink-role" &> /dev/null; then
        log_info "Deleting Flink IAM role policies..."
        
        # Delete inline policies
        local policies=$(aws iam list-role-policies --role-name "${PROJECT_NAME}-flink-role" --query 'PolicyNames[]' --output text)
        for policy in $policies; do
            if aws iam delete-role-policy --role-name "${PROJECT_NAME}-flink-role" --policy-name "$policy"; then
                log_success "Deleted policy: $policy"
            else
                log_error "Failed to delete policy: $policy"
                if [[ "$FORCE" != "true" ]]; then
                    return 1
                fi
            fi
        done
        
        # Delete role
        if aws iam delete-role --role-name "${PROJECT_NAME}-flink-role"; then
            log_success "Flink IAM role deleted"
        else
            log_error "Failed to delete Flink IAM role"
            if [[ "$FORCE" != "true" ]]; then
                return 1
            fi
        fi
    else
        log_warning "Flink IAM role not found: ${PROJECT_NAME}-flink-role"
    fi
    
    log_success "IAM roles cleaned up"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up temporary files"
        return 0
    fi
    
    # Common temp file locations
    local temp_files=(
        "/tmp/lambda-trust-policy.json"
        "/tmp/lambda-policy.json"
        "/tmp/flink-trust-policy.json"
        "/tmp/flink-policy.json"
        "/tmp/iot-processor.py"
        "/tmp/iot-processor.zip"
        "/tmp/flink-app.py"
        "/tmp/flink-app.zip"
        "/tmp/iot-simulator.py"
        "/tmp/dashboard.json"
        "/tmp/iot-analytics-deployment"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -e "$file" ]]; then
            rm -rf "$file"
            log_success "Removed: $file"
        fi
    done
    
    log_success "Temporary files cleaned up"
}

# Function to display cleanup summary
show_cleanup_summary() {
    log_info "Cleanup Summary:"
    echo "==================="
    echo "Project Name: $PROJECT_NAME"
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account: $AWS_ACCOUNT_ID"
    echo ""
    echo "Resources Cleaned Up:"
    echo "- Flink Application: $FLINK_APP_NAME"
    echo "- Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "- CloudWatch Alarms and Dashboard"
    echo "- Kinesis Stream: $KINESIS_STREAM_NAME"
    echo "- SNS Topic: $SNS_TOPIC_NAME"
    echo "- S3 Bucket: $S3_BUCKET_NAME"
    echo "- IAM Roles: ${PROJECT_NAME}-lambda-role, ${PROJECT_NAME}-flink-role"
    echo "- Temporary Files"
    echo ""
    echo "All resources have been successfully removed."
}

# Function to handle cleanup errors
handle_cleanup_error() {
    local error_step="$1"
    log_error "Error during $error_step"
    
    if [[ "$FORCE" == "true" ]]; then
        log_warning "Continuing cleanup due to --force flag"
        return 0
    else
        log_error "Cleanup aborted. Use --force to continue despite errors."
        exit 1
    fi
}

# Main cleanup function
main() {
    log_info "Starting Real-Time IoT Analytics Pipeline Cleanup"
    
    # Show configuration
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be deleted"
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        set -x
    fi
    
    # Confirm cleanup
    if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
        echo "This will delete the following resources for project: $PROJECT_NAME"
        echo "- Flink Application and all associated state"
        echo "- Lambda Function and event source mappings"
        echo "- CloudWatch alarms and dashboard"
        echo "- Kinesis Data Stream and all retained data"
        echo "- SNS topic and subscriptions"
        echo "- S3 bucket and all stored data"
        echo "- IAM roles and policies"
        echo ""
        log_warning "This action cannot be undone!"
        echo ""
        read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled"
            exit 0
        fi
    fi
    
    # Run cleanup steps
    check_prerequisites
    setup_environment
    find_resources
    
    # Cleanup in reverse order of creation
    stop_flink_application || handle_cleanup_error "Flink application cleanup"
    delete_lambda_function || handle_cleanup_error "Lambda function cleanup"
    delete_cloudwatch_resources || handle_cleanup_error "CloudWatch resources cleanup"
    delete_kinesis_stream || handle_cleanup_error "Kinesis stream cleanup"
    delete_sns_topic || handle_cleanup_error "SNS topic cleanup"
    delete_s3_bucket || handle_cleanup_error "S3 bucket cleanup"
    delete_iam_roles || handle_cleanup_error "IAM roles cleanup"
    cleanup_temp_files || handle_cleanup_error "Temporary files cleanup"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        show_cleanup_summary
        log_success "Cleanup completed successfully!"
    else
        log_info "Dry run completed - no resources were deleted"
    fi
}

# Run main function
main "$@"