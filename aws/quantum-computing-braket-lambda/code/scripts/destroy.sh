#!/bin/bash

# Cleanup script for Hybrid Quantum-Classical Computing Pipeline
# This script removes all resources created by the deployment script

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Check if .env file exists
    if [ ! -f ".env" ]; then
        error "Environment file .env not found. Please ensure you're running from the deployment directory."
    fi
    
    # Load environment variables from .env file
    set -a
    source .env
    set +a
    
    # Verify required variables are set
    if [ -z "${PROJECT_NAME:-}" ] || [ -z "${AWS_REGION:-}" ] || [ -z "${AWS_ACCOUNT_ID:-}" ]; then
        error "Required environment variables not found. Please check .env file."
    fi
    
    log "Environment variables loaded successfully"
    info "Project: ${PROJECT_NAME}"
    info "Region: ${AWS_REGION}"
}

# Function to confirm cleanup
confirm_cleanup() {
    echo -e "\n${YELLOW}WARNING: This will permanently delete all quantum computing pipeline resources!${NC}"
    echo -e "${YELLOW}Project: ${PROJECT_NAME}${NC}"
    echo -e "${YELLOW}Region: ${AWS_REGION}${NC}"
    echo -e "\n${YELLOW}Resources to be deleted:${NC}"
    echo -e "- 4 Lambda functions"
    echo -e "- 3 S3 buckets (with all contents)"
    echo -e "- 1 IAM role and policies"
    echo -e "- CloudWatch dashboard and alarms"
    echo -e "- All quantum job results and logs"
    echo -e "\n${RED}This action cannot be undone!${NC}"
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm
    if [ "$confirm" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Cleanup confirmed. Starting resource deletion..."
}

# Function to cancel running quantum jobs
cancel_quantum_jobs() {
    log "Cancelling any running quantum jobs..."
    
    # List and cancel running Braket jobs
    running_jobs=$(aws braket search-jobs \
        --filter "jobName:${PROJECT_NAME}*" \
        --query "jobs[?status=='RUNNING' || status=='QUEUED'].jobArn" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$running_jobs" ]; then
        for job_arn in $running_jobs; do
            if [ -n "$job_arn" ]; then
                log "Cancelling quantum job: $job_arn"
                aws braket cancel-job --job-arn "$job_arn" 2>/dev/null || warn "Failed to cancel job: $job_arn"
            fi
        done
        
        # Wait for jobs to be cancelled
        log "Waiting for quantum jobs to be cancelled..."
        sleep 30
    else
        log "No running quantum jobs found"
    fi
}

# Function to delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    lambda_functions=(
        "data-preparation"
        "job-submission"
        "job-monitoring"
        "post-processing"
    )
    
    for function in "${lambda_functions[@]}"; do
        function_name="${PROJECT_NAME}-${function}"
        
        # Check if function exists
        if aws lambda get-function --function-name "$function_name" &>/dev/null; then
            log "Deleting Lambda function: $function_name"
            aws lambda delete-function --function-name "$function_name"
            log "✅ Deleted Lambda function: $function_name"
        else
            warn "Lambda function not found: $function_name"
        fi
    done
}

# Function to delete S3 buckets
delete_s3_buckets() {
    log "Deleting S3 buckets and contents..."
    
    buckets=(
        "${S3_INPUT_BUCKET}"
        "${S3_OUTPUT_BUCKET}"
        "${S3_CODE_BUCKET}"
    )
    
    for bucket in "${buckets[@]}"; do
        if [ -n "$bucket" ]; then
            # Check if bucket exists
            if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
                log "Emptying S3 bucket: $bucket"
                
                # Delete all object versions and delete markers
                aws s3api list-object-versions --bucket "$bucket" \
                    --output text --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                    | while read -r key version_id; do
                        if [ -n "$key" ] && [ -n "$version_id" ]; then
                            aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" 2>/dev/null || true
                        fi
                    done
                
                # Delete all object versions
                aws s3api list-object-versions --bucket "$bucket" \
                    --output text --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                    | while read -r key version_id; do
                        if [ -n "$key" ] && [ -n "$version_id" ]; then
                            aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" 2>/dev/null || true
                        fi
                    done
                
                # Remove all remaining objects
                aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
                
                # Delete the bucket
                log "Deleting S3 bucket: $bucket"
                aws s3 rb "s3://$bucket" --force
                log "✅ Deleted S3 bucket: $bucket"
            else
                warn "S3 bucket not found: $bucket"
            fi
        fi
    done
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Deleting IAM role and policies..."
    
    role_name="${PROJECT_NAME}-execution-role"
    
    # Check if role exists
    if aws iam get-role --role-name "$role_name" &>/dev/null; then
        log "Deleting IAM role: $role_name"
        
        # Detach managed policies
        managed_policies=(
            "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
            "arn:aws:iam::aws:policy/AmazonBraketFullAccess"
        )
        
        for policy_arn in "${managed_policies[@]}"; do
            if aws iam list-attached-role-policies --role-name "$role_name" --query "AttachedPolicies[?PolicyArn=='$policy_arn']" --output text | grep -q "$policy_arn"; then
                log "Detaching policy: $policy_arn"
                aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn"
            fi
        done
        
        # Delete inline policies
        inline_policies=$(aws iam list-role-policies --role-name "$role_name" --query "PolicyNames" --output text 2>/dev/null || echo "")
        if [ -n "$inline_policies" ]; then
            for policy_name in $inline_policies; do
                if [ -n "$policy_name" ]; then
                    log "Deleting inline policy: $policy_name"
                    aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name"
                fi
            done
        fi
        
        # Delete the role
        aws iam delete-role --role-name "$role_name"
        log "✅ Deleted IAM role: $role_name"
    else
        warn "IAM role not found: $role_name"
    fi
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete CloudWatch dashboard
    dashboard_name="${PROJECT_NAME}-quantum-pipeline"
    if aws cloudwatch get-dashboard --dashboard-name "$dashboard_name" &>/dev/null; then
        log "Deleting CloudWatch dashboard: $dashboard_name"
        aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name"
        log "✅ Deleted CloudWatch dashboard: $dashboard_name"
    else
        warn "CloudWatch dashboard not found: $dashboard_name"
    fi
    
    # Delete CloudWatch alarms
    alarms=(
        "${PROJECT_NAME}-job-failure-rate"
        "${PROJECT_NAME}-low-efficiency"
    )
    
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --query "MetricAlarms[0].AlarmName" --output text 2>/dev/null | grep -q "$alarm"; then
            log "Deleting CloudWatch alarm: $alarm"
            aws cloudwatch delete-alarms --alarm-names "$alarm"
            log "✅ Deleted CloudWatch alarm: $alarm"
        else
            warn "CloudWatch alarm not found: $alarm"
        fi
    done
}

# Function to delete CloudWatch log groups
delete_cloudwatch_logs() {
    log "Deleting CloudWatch log groups..."
    
    log_groups=(
        "/aws/lambda/${PROJECT_NAME}-data-preparation"
        "/aws/lambda/${PROJECT_NAME}-job-submission"
        "/aws/lambda/${PROJECT_NAME}-job-monitoring"
        "/aws/lambda/${PROJECT_NAME}-post-processing"
    )
    
    for log_group in "${log_groups[@]}"; do
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query "logGroups[0].logGroupName" --output text 2>/dev/null | grep -q "$log_group"; then
            log "Deleting CloudWatch log group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group"
            log "✅ Deleted CloudWatch log group: $log_group"
        else
            warn "CloudWatch log group not found: $log_group"
        fi
    done
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # List of files and directories to remove
    local_items=(
        "quantum-code/"
        "lambda-functions/"
        "cloudwatch-dashboard.json"
        "test-response.json"
        ".env"
    )
    
    for item in "${local_items[@]}"; do
        if [ -e "$item" ]; then
            log "Removing local item: $item"
            rm -rf "$item"
            log "✅ Removed local item: $item"
        else
            warn "Local item not found: $item"
        fi
    done
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    # Check Lambda functions
    remaining_functions=$(aws lambda list-functions \
        --query "Functions[?starts_with(FunctionName, '${PROJECT_NAME}')].FunctionName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$remaining_functions" ]; then
        warn "Some Lambda functions may still exist: $remaining_functions"
    else
        log "✅ All Lambda functions cleaned up"
    fi
    
    # Check S3 buckets
    remaining_buckets=""
    for bucket in "${S3_INPUT_BUCKET}" "${S3_OUTPUT_BUCKET}" "${S3_CODE_BUCKET}"; do
        if [ -n "$bucket" ] && aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
            remaining_buckets="$remaining_buckets $bucket"
        fi
    done
    
    if [ -n "$remaining_buckets" ]; then
        warn "Some S3 buckets may still exist: $remaining_buckets"
    else
        log "✅ All S3 buckets cleaned up"
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${PROJECT_NAME}-execution-role" &>/dev/null; then
        warn "IAM role may still exist: ${PROJECT_NAME}-execution-role"
    else
        log "✅ IAM role cleaned up"
    fi
    
    # Check CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name "${PROJECT_NAME}-quantum-pipeline" &>/dev/null; then
        warn "CloudWatch dashboard may still exist: ${PROJECT_NAME}-quantum-pipeline"
    else
        log "✅ CloudWatch dashboard cleaned up"
    fi
    
    log "Cleanup verification completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup completed successfully!"
    
    echo -e "\n${GREEN}=== Quantum Computing Pipeline Cleanup Summary ===${NC}"
    echo -e "${BLUE}Project Name:${NC} ${PROJECT_NAME}"
    echo -e "${BLUE}AWS Region:${NC} ${AWS_REGION}"
    echo -e "\n${GREEN}Resources Removed:${NC}"
    echo -e "✅ Lambda functions (4 functions)"
    echo -e "✅ S3 buckets (3 buckets with all contents)"
    echo -e "✅ IAM role and policies"
    echo -e "✅ CloudWatch dashboard and alarms"
    echo -e "✅ CloudWatch log groups"
    echo -e "✅ Local files and directories"
    echo -e "✅ Quantum job cancellations"
    echo -e "\n${YELLOW}Important Notes:${NC}"
    echo -e "- All quantum computing pipeline resources have been removed"
    echo -e "- Any running quantum jobs have been cancelled"
    echo -e "- All data and results have been permanently deleted"
    echo -e "- CloudWatch logs may take time to fully disappear"
    echo -e "- Check AWS billing to ensure no unexpected charges"
    echo -e "\n${GREEN}Cleanup completed successfully!${NC}"
}

# Function to handle cleanup errors
handle_cleanup_error() {
    local exit_code=$?
    error "Cleanup failed with exit code: $exit_code"
    error "Some resources may not have been cleaned up properly"
    echo -e "\n${YELLOW}Manual cleanup may be required for:${NC}"
    echo -e "- Lambda functions starting with: ${PROJECT_NAME}-"
    echo -e "- S3 buckets: ${S3_INPUT_BUCKET:-}, ${S3_OUTPUT_BUCKET:-}, ${S3_CODE_BUCKET:-}"
    echo -e "- IAM role: ${PROJECT_NAME}-execution-role"
    echo -e "- CloudWatch dashboard: ${PROJECT_NAME}-quantum-pipeline"
    echo -e "- CloudWatch alarms: ${PROJECT_NAME}-*"
    echo -e "\n${YELLOW}Please check the AWS console to manually remove any remaining resources.${NC}"
    exit $exit_code
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -f, --force    Skip confirmation prompt"
    echo "  -v, --verbose  Enable verbose logging"
    echo ""
    echo "Description:"
    echo "  This script removes all resources created by the quantum computing pipeline"
    echo "  deployment script. It reads configuration from the .env file created during"
    echo "  deployment."
    echo ""
    echo "Examples:"
    echo "  $0                    # Interactive cleanup with confirmation"
    echo "  $0 --force           # Skip confirmation prompt"
    echo "  $0 --verbose         # Enable verbose logging"
}

# Parse command line arguments
FORCE_CLEANUP=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -f|--force)
            FORCE_CLEANUP=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Enable verbose logging if requested
if [ "$VERBOSE" = true ]; then
    set -x
fi

# Main execution
main() {
    log "Starting Quantum Computing Pipeline cleanup..."
    
    # Set up error handling
    trap handle_cleanup_error ERR
    
    # Load environment and confirm cleanup
    load_environment
    
    if [ "$FORCE_CLEANUP" = false ]; then
        confirm_cleanup
    else
        log "Force cleanup enabled - skipping confirmation"
    fi
    
    # Execute cleanup steps
    cancel_quantum_jobs
    delete_lambda_functions
    delete_s3_buckets
    delete_iam_resources
    delete_cloudwatch_resources
    delete_cloudwatch_logs
    cleanup_local_files
    
    # Verify cleanup and display summary
    verify_cleanup
    display_cleanup_summary
    
    log "Cleanup process completed successfully"
}

# Execute main function
main "$@"