#!/bin/bash

# Destroy script for Automated Report Generation with EventBridge Scheduler and S3
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI to proceed with cleanup."
        exit 1
    fi
    
    # Check if authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or not authenticated."
        error "Please run 'aws configure' or set up your credentials."
        exit 1
    fi
    
    success "Prerequisites check completed successfully"
}

# Function to discover resources to delete
discover_resources() {
    log "Discovering resources to delete..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No default region found. Using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Discover Lambda functions with our naming pattern
    LAMBDA_FUNCTIONS=$(aws lambda list-functions \
        --query 'Functions[?starts_with(FunctionName, `report-generator-`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    # Discover EventBridge schedules with our naming pattern
    SCHEDULES=$(aws scheduler list-schedules \
        --query 'Schedules[?starts_with(Name, `daily-reports-`)].Name' \
        --output text 2>/dev/null || echo "")
    
    # Discover S3 buckets with our naming patterns
    DATA_BUCKETS=$(aws s3api list-buckets \
        --query 'Buckets[?starts_with(Name, `report-data-`)].Name' \
        --output text 2>/dev/null || echo "")
    
    REPORT_BUCKETS=$(aws s3api list-buckets \
        --query 'Buckets[?starts_with(Name, `report-output-`)].Name' \
        --output text 2>/dev/null || echo "")
    
    # Check for IAM roles
    LAMBDA_ROLE_EXISTS=$(aws iam get-role --role-name ReportGeneratorRole 2>/dev/null && echo "true" || echo "false")
    SCHEDULER_ROLE_EXISTS=$(aws iam get-role --role-name EventBridgeSchedulerRole 2>/dev/null && echo "true" || echo "false")
    
    # Check for IAM policies
    LAMBDA_POLICY_EXISTS=$(aws iam get-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/ReportGeneratorPolicy 2>/dev/null && echo "true" || echo "false")
    SCHEDULER_POLICY_EXISTS=$(aws iam get-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/EventBridgeSchedulerPolicy 2>/dev/null && echo "true" || echo "false")
    
    log "Discovery completed"
    log "Lambda functions: ${LAMBDA_FUNCTIONS:-None}"
    log "EventBridge schedules: ${SCHEDULES:-None}"
    log "Data buckets: ${DATA_BUCKETS:-None}"
    log "Report buckets: ${REPORT_BUCKETS:-None}"
    log "Lambda IAM role exists: ${LAMBDA_ROLE_EXISTS}"
    log "Scheduler IAM role exists: ${SCHEDULER_ROLE_EXISTS}"
    log "Lambda IAM policy exists: ${LAMBDA_POLICY_EXISTS}"
    log "Scheduler IAM policy exists: ${SCHEDULER_POLICY_EXISTS}"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    warning "This script will delete the following resources:"
    echo ""
    
    if [ -n "${LAMBDA_FUNCTIONS}" ]; then
        echo "Lambda Functions:"
        for func in ${LAMBDA_FUNCTIONS}; do
            echo "  - ${func}"
        done
    fi
    
    if [ -n "${SCHEDULES}" ]; then
        echo "EventBridge Schedules:"
        for schedule in ${SCHEDULES}; do
            echo "  - ${schedule}"
        done
    fi
    
    if [ -n "${DATA_BUCKETS}" ]; then
        echo "Data S3 Buckets:"
        for bucket in ${DATA_BUCKETS}; do
            echo "  - ${bucket}"
        done
    fi
    
    if [ -n "${REPORT_BUCKETS}" ]; then
        echo "Report S3 Buckets:"
        for bucket in ${REPORT_BUCKETS}; do
            echo "  - ${bucket}"
        done
    fi
    
    if [ "${LAMBDA_ROLE_EXISTS}" = "true" ]; then
        echo "IAM Roles:"
        echo "  - ReportGeneratorRole"
    fi
    
    if [ "${SCHEDULER_ROLE_EXISTS}" = "true" ]; then
        echo "  - EventBridgeSchedulerRole"
    fi
    
    if [ "${LAMBDA_POLICY_EXISTS}" = "true" ]; then
        echo "IAM Policies:"
        echo "  - ReportGeneratorPolicy"
    fi
    
    if [ "${SCHEDULER_POLICY_EXISTS}" = "true" ]; then
        echo "  - EventBridgeSchedulerPolicy"
    fi
    
    echo ""
    warning "This action cannot be undone!"
    echo ""
    
    # Check if running in non-interactive mode
    if [ "${FORCE_DELETE:-false}" = "true" ]; then
        log "Force delete mode enabled, skipping confirmation"
        return 0
    fi
    
    echo -n "Are you sure you want to proceed? (yes/no): "
    read -r response
    
    case $response in
        [yY][eE][sS]|[yY])
            log "Proceeding with resource deletion..."
            ;;
        *)
            log "Deletion cancelled by user"
            exit 0
            ;;
    esac
}

# Function to delete EventBridge schedules
delete_eventbridge_schedules() {
    if [ -n "${SCHEDULES}" ]; then
        log "Deleting EventBridge schedules..."
        
        for schedule in ${SCHEDULES}; do
            log "Deleting schedule: ${schedule}"
            if aws scheduler delete-schedule --name "${schedule}"; then
                success "Deleted schedule: ${schedule}"
            else
                error "Failed to delete schedule: ${schedule}"
            fi
        done
        
        success "EventBridge schedules deletion completed"
    else
        log "No EventBridge schedules found to delete"
    fi
}

# Function to delete Lambda functions
delete_lambda_functions() {
    if [ -n "${LAMBDA_FUNCTIONS}" ]; then
        log "Deleting Lambda functions..."
        
        for func in ${LAMBDA_FUNCTIONS}; do
            log "Deleting Lambda function: ${func}"
            if aws lambda delete-function --function-name "${func}"; then
                success "Deleted Lambda function: ${func}"
            else
                error "Failed to delete Lambda function: ${func}"
            fi
        done
        
        success "Lambda functions deletion completed"
    else
        log "No Lambda functions found to delete"
    fi
}

# Function to delete S3 buckets and their contents
delete_s3_buckets() {
    # Delete data buckets
    if [ -n "${DATA_BUCKETS}" ]; then
        log "Deleting S3 data buckets..."
        
        for bucket in ${DATA_BUCKETS}; do
            log "Emptying and deleting bucket: ${bucket}"
            
            # Check if bucket exists
            if aws s3api head-bucket --bucket "${bucket}" 2>/dev/null; then
                # Empty bucket first (including all versions)
                log "Emptying bucket: ${bucket}"
                aws s3 rm s3://${bucket} --recursive 2>/dev/null || true
                
                # Delete all object versions and delete markers
                aws s3api delete-objects --bucket "${bucket}" \
                    --delete "$(aws s3api list-object-versions --bucket "${bucket}" \
                    --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' 2>/dev/null || echo '{\"Objects\": []}')" 2>/dev/null || true
                
                aws s3api delete-objects --bucket "${bucket}" \
                    --delete "$(aws s3api list-object-versions --bucket "${bucket}" \
                    --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' 2>/dev/null || echo '{\"Objects\": []}')" 2>/dev/null || true
                
                # Delete bucket
                if aws s3 rb s3://${bucket}; then
                    success "Deleted data bucket: ${bucket}"
                else
                    error "Failed to delete data bucket: ${bucket}"
                fi
            else
                warning "Data bucket ${bucket} does not exist or is inaccessible"
            fi
        done
    else
        log "No data buckets found to delete"
    fi
    
    # Delete report buckets
    if [ -n "${REPORT_BUCKETS}" ]; then
        log "Deleting S3 report buckets..."
        
        for bucket in ${REPORT_BUCKETS}; do
            log "Emptying and deleting bucket: ${bucket}"
            
            # Check if bucket exists
            if aws s3api head-bucket --bucket "${bucket}" 2>/dev/null; then
                # Empty bucket first (including all versions)
                log "Emptying bucket: ${bucket}"
                aws s3 rm s3://${bucket} --recursive 2>/dev/null || true
                
                # Delete all object versions and delete markers
                aws s3api delete-objects --bucket "${bucket}" \
                    --delete "$(aws s3api list-object-versions --bucket "${bucket}" \
                    --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' 2>/dev/null || echo '{\"Objects\": []}')" 2>/dev/null || true
                
                aws s3api delete-objects --bucket "${bucket}" \
                    --delete "$(aws s3api list-object-versions --bucket "${bucket}" \
                    --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' 2>/dev/null || echo '{\"Objects\": []}')" 2>/dev/null || true
                
                # Delete bucket
                if aws s3 rb s3://${bucket}; then
                    success "Deleted report bucket: ${bucket}"
                else
                    error "Failed to delete report bucket: ${bucket}"
                fi
            else
                warning "Report bucket ${bucket} does not exist or is inaccessible"
            fi
        done
    else
        log "No report buckets found to delete"
    fi
    
    success "S3 buckets deletion completed"
}

# Function to delete IAM roles and policies
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    # Delete Lambda IAM role and policy
    if [ "${LAMBDA_ROLE_EXISTS}" = "true" ]; then
        log "Deleting Lambda IAM role and attached policies..."
        
        # Detach AWS managed policy
        aws iam detach-role-policy \
            --role-name ReportGeneratorRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        
        # Detach custom policy
        aws iam detach-role-policy \
            --role-name ReportGeneratorRole \
            --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/ReportGeneratorPolicy 2>/dev/null || true
        
        # Delete the role
        if aws iam delete-role --role-name ReportGeneratorRole; then
            success "Deleted Lambda IAM role: ReportGeneratorRole"
        else
            error "Failed to delete Lambda IAM role: ReportGeneratorRole"
        fi
    fi
    
    # Delete Lambda custom policy
    if [ "${LAMBDA_POLICY_EXISTS}" = "true" ]; then
        if aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/ReportGeneratorPolicy; then
            success "Deleted Lambda IAM policy: ReportGeneratorPolicy"
        else
            error "Failed to delete Lambda IAM policy: ReportGeneratorPolicy"
        fi
    fi
    
    # Delete EventBridge Scheduler IAM role and policy
    if [ "${SCHEDULER_ROLE_EXISTS}" = "true" ]; then
        log "Deleting EventBridge Scheduler IAM role and attached policies..."
        
        # Detach custom policy
        aws iam detach-role-policy \
            --role-name EventBridgeSchedulerRole \
            --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/EventBridgeSchedulerPolicy 2>/dev/null || true
        
        # Delete the role
        if aws iam delete-role --role-name EventBridgeSchedulerRole; then
            success "Deleted EventBridge Scheduler IAM role: EventBridgeSchedulerRole"
        else
            error "Failed to delete EventBridge Scheduler IAM role: EventBridgeSchedulerRole"
        fi
    fi
    
    # Delete EventBridge Scheduler custom policy
    if [ "${SCHEDULER_POLICY_EXISTS}" = "true" ]; then
        if aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/EventBridgeSchedulerPolicy; then
            success "Deleted EventBridge Scheduler IAM policy: EventBridgeSchedulerPolicy"
        else
            error "Failed to delete EventBridge Scheduler IAM policy: EventBridgeSchedulerPolicy"
        fi
    fi
    
    success "IAM resources deletion completed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local temporary files..."
    
    # Remove any temporary files that might exist
    rm -f lambda-trust-policy.json lambda-permissions-policy.json 2>/dev/null || true
    rm -f scheduler-trust-policy.json scheduler-permissions-policy.json 2>/dev/null || true
    rm -f sample_sales.csv sample_inventory.csv 2>/dev/null || true
    rm -f report_generator.py function.zip response.json 2>/dev/null || true
    rm -f latest_report.csv 2>/dev/null || true
    
    success "Local cleanup completed"
}

# Function to verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    # Verify Lambda functions are deleted
    REMAINING_LAMBDA_FUNCTIONS=$(aws lambda list-functions \
        --query 'Functions[?starts_with(FunctionName, `report-generator-`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    # Verify EventBridge schedules are deleted
    REMAINING_SCHEDULES=$(aws scheduler list-schedules \
        --query 'Schedules[?starts_with(Name, `daily-reports-`)].Name' \
        --output text 2>/dev/null || echo "")
    
    # Verify S3 buckets are deleted
    REMAINING_DATA_BUCKETS=$(aws s3api list-buckets \
        --query 'Buckets[?starts_with(Name, `report-data-`)].Name' \
        --output text 2>/dev/null || echo "")
    
    REMAINING_REPORT_BUCKETS=$(aws s3api list-buckets \
        --query 'Buckets[?starts_with(Name, `report-output-`)].Name' \
        --output text 2>/dev/null || echo "")
    
    # Verify IAM roles are deleted
    REMAINING_LAMBDA_ROLE=$(aws iam get-role --role-name ReportGeneratorRole 2>/dev/null && echo "true" || echo "false")
    REMAINING_SCHEDULER_ROLE=$(aws iam get-role --role-name EventBridgeSchedulerRole 2>/dev/null && echo "true" || echo "false")
    
    # Report verification results
    if [ -n "${REMAINING_LAMBDA_FUNCTIONS}" ]; then
        warning "Some Lambda functions still exist: ${REMAINING_LAMBDA_FUNCTIONS}"
    fi
    
    if [ -n "${REMAINING_SCHEDULES}" ]; then
        warning "Some EventBridge schedules still exist: ${REMAINING_SCHEDULES}"
    fi
    
    if [ -n "${REMAINING_DATA_BUCKETS}" ]; then
        warning "Some data buckets still exist: ${REMAINING_DATA_BUCKETS}"
    fi
    
    if [ -n "${REMAINING_REPORT_BUCKETS}" ]; then
        warning "Some report buckets still exist: ${REMAINING_REPORT_BUCKETS}"
    fi
    
    if [ "${REMAINING_LAMBDA_ROLE}" = "true" ]; then
        warning "Lambda IAM role still exists: ReportGeneratorRole"
    fi
    
    if [ "${REMAINING_SCHEDULER_ROLE}" = "true" ]; then
        warning "Scheduler IAM role still exists: EventBridgeSchedulerRole"
    fi
    
    # Check if all resources are deleted
    if [ -z "${REMAINING_LAMBDA_FUNCTIONS}" ] && [ -z "${REMAINING_SCHEDULES}" ] && \
       [ -z "${REMAINING_DATA_BUCKETS}" ] && [ -z "${REMAINING_REPORT_BUCKETS}" ] && \
       [ "${REMAINING_LAMBDA_ROLE}" = "false" ] && [ "${REMAINING_SCHEDULER_ROLE}" = "false" ]; then
        success "All resources have been successfully deleted"
    else
        warning "Some resources may still exist. Please check manually if needed."
    fi
}

# Function to display deletion summary
display_summary() {
    echo ""
    echo "======================================"
    success "DESTRUCTION COMPLETED"
    echo "======================================"
    echo ""
    echo "The following actions were performed:"
    echo "  ✅ EventBridge schedules deleted"
    echo "  ✅ Lambda functions deleted"
    echo "  ✅ S3 buckets emptied and deleted"
    echo "  ✅ IAM roles and policies deleted"
    echo "  ✅ Local temporary files cleaned up"
    echo ""
    echo "Note: SES email verification status is preserved"
    echo "      (email addresses remain verified for future use)"
    echo ""
    echo "All automated report generation resources have been removed."
    echo "Your AWS account should no longer incur charges for these resources."
    echo ""
}

# Main destruction function
main() {
    echo "======================================"
    echo "AWS Automated Report Generation Cleanup"
    echo "======================================"
    echo ""
    
    check_prerequisites
    discover_resources
    confirm_deletion
    delete_eventbridge_schedules
    delete_lambda_functions
    delete_s3_buckets
    delete_iam_resources
    cleanup_local_files
    verify_deletion
    display_summary
}

# Handle command line arguments
case "${1:-}" in
    --force)
        export FORCE_DELETE=true
        log "Force delete mode enabled"
        ;;
    --help)
        echo "Usage: $0 [--force] [--help]"
        echo ""
        echo "Options:"
        echo "  --force    Skip confirmation prompts"
        echo "  --help     Show this help message"
        echo ""
        exit 0
        ;;
    "")
        # No arguments, proceed normally
        ;;
    *)
        error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Run main function
main "$@"