#!/bin/bash

# Destroy script for Amazon Polly Text-to-Speech Solutions
# This script removes all infrastructure and resources created by the deploy script

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Amazon Polly Text-to-Speech Solutions infrastructure

OPTIONS:
    -h, --help          Show this help message
    -r, --region        AWS region (default: from AWS config or .env file)
    -f, --force         Skip confirmation prompts
    -d, --dry-run       Show what would be deleted without removing resources
    -v, --verbose       Enable verbose output

EXAMPLES:
    $0                  Destroy with confirmation prompts
    $0 --force          Destroy without confirmation
    $0 --dry-run        Show destruction plan without removing resources

EOF
}

# Parse command line arguments
DRY_RUN=false
FORCE=false
VERBOSE=false
AWS_REGION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Enable verbose output if requested
if [[ "$VERBOSE" == "true" ]]; then
    set -x
fi

# Load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Try to load from .env file first
    if [[ -f ".env" ]]; then
        log "Loading variables from .env file..."
        source .env
    else
        warning ".env file not found. You may need to provide values manually."
    fi
    
    # Set region
    if [[ -z "$AWS_REGION" ]]; then
        AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        if [[ -z "$AWS_REGION" ]]; then
            AWS_REGION="us-east-1"
            warning "No region configured, using default: $AWS_REGION"
        fi
    fi
    export AWS_REGION
    
    # Get account ID
    AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null)}
    export AWS_ACCOUNT_ID
    
    # Check if we have the required variables
    if [[ -z "${BUCKET_NAME:-}" || -z "${LAMBDA_FUNCTION_NAME:-}" || -z "${IAM_ROLE_NAME:-}" ]]; then
        error "Required environment variables not found."
        error "Please ensure the following variables are set:"
        error "  BUCKET_NAME"
        error "  LAMBDA_FUNCTION_NAME"
        error "  IAM_ROLE_NAME"
        
        if [[ "$FORCE" == "false" ]]; then
            read -p "Do you want to continue with manual cleanup? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
            manual_cleanup_mode=true
        else
            exit 1
        fi
    fi
    
    log "Environment variables loaded:"
    log "  AWS_REGION: ${AWS_REGION}"
    log "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
    log "  BUCKET_NAME: ${BUCKET_NAME:-'NOT SET'}"
    log "  LAMBDA_FUNCTION_NAME: ${LAMBDA_FUNCTION_NAME:-'NOT SET'}"
    log "  IAM_ROLE_NAME: ${IAM_ROLE_NAME:-'NOT SET'}"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    warning "This will permanently delete the following resources:"
    echo "  • S3 Bucket: ${BUCKET_NAME:-'Unknown'}"
    echo "  • Lambda Function: ${LAMBDA_FUNCTION_NAME:-'Unknown'}"
    echo "  • IAM Role: ${IAM_ROLE_NAME:-'Unknown'}"
    echo "  • Custom Polly Lexicon: CustomPronunciations"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    if [[ ! $REPLY == "yes" ]]; then
        log "Destruction cancelled by user."
        exit 0
    fi
}

# Execute command with dry-run support
execute_command() {
    local description="$1"
    local command="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] $description"
        log "[DRY-RUN] Command: $command"
    else
        log "$description"
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$command" || warning "Command failed but continuing: $command"
        else
            eval "$command"
        fi
    fi
}

# Delete Lambda function
delete_lambda_function() {
    log "Deleting Lambda function..."
    
    if [[ -z "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        warning "Lambda function name not set, skipping..."
        return 0
    fi
    
    # Check if function exists
    if ! aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" --region "${AWS_REGION}" &> /dev/null; then
        warning "Lambda function ${LAMBDA_FUNCTION_NAME} not found, skipping..."
        return 0
    fi
    
    execute_command "Deleting Lambda function ${LAMBDA_FUNCTION_NAME}" \
        "aws lambda delete-function --function-name ${LAMBDA_FUNCTION_NAME} --region ${AWS_REGION}" \
        "true"
    
    success "Lambda function deleted successfully"
}

# Delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    if [[ -z "${IAM_ROLE_NAME:-}" ]]; then
        warning "IAM role name not set, skipping..."
        return 0
    fi
    
    # Check if role exists
    if ! aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        warning "IAM role ${IAM_ROLE_NAME} not found, skipping..."
        return 0
    fi
    
    # Detach managed policies
    execute_command "Detaching Lambda basic execution policy" \
        "aws iam detach-role-policy --role-name ${IAM_ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        "true"
    
    execute_command "Detaching Polly full access policy" \
        "aws iam detach-role-policy --role-name ${IAM_ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonPollyFullAccess" \
        "true"
    
    # Delete custom S3 policy
    local custom_policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_ROLE_NAME}-S3Policy"
    execute_command "Detaching custom S3 policy" \
        "aws iam detach-role-policy --role-name ${IAM_ROLE_NAME} --policy-arn ${custom_policy_arn}" \
        "true"
    
    execute_command "Deleting custom S3 policy" \
        "aws iam delete-policy --policy-arn ${custom_policy_arn}" \
        "true"
    
    # Delete IAM role
    execute_command "Deleting IAM role ${IAM_ROLE_NAME}" \
        "aws iam delete-role --role-name ${IAM_ROLE_NAME}" \
        "true"
    
    success "IAM resources deleted successfully"
}

# Delete S3 bucket and contents
delete_s3_bucket() {
    log "Deleting S3 bucket and contents..."
    
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        warning "S3 bucket name not set, skipping..."
        return 0
    fi
    
    # Check if bucket exists
    if ! aws s3 ls "s3://${BUCKET_NAME}" &> /dev/null; then
        warning "S3 bucket ${BUCKET_NAME} not found, skipping..."
        return 0
    fi
    
    # List bucket contents for confirmation
    if [[ "$DRY_RUN" == "false" && "$VERBOSE" == "true" ]]; then
        log "Bucket contents to be deleted:"
        aws s3 ls "s3://${BUCKET_NAME}" --recursive || true
    fi
    
    # Delete all objects and versions
    execute_command "Deleting all objects in bucket ${BUCKET_NAME}" \
        "aws s3 rm s3://${BUCKET_NAME} --recursive" \
        "true"
    
    # Delete all object versions (in case versioning was enabled)
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Checking for object versions to delete..."
        aws s3api list-object-versions --bucket "${BUCKET_NAME}" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text | while read key version_id; do
            if [[ -n "$key" && -n "$version_id" && "$version_id" != "None" ]]; then
                aws s3api delete-object --bucket "${BUCKET_NAME}" --key "$key" --version-id "$version_id" || true
            fi
        done 2>/dev/null || true
        
        # Delete delete markers
        aws s3api list-object-versions --bucket "${BUCKET_NAME}" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text | while read key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object --bucket "${BUCKET_NAME}" --key "$key" --version-id "$version_id" || true
            fi
        done 2>/dev/null || true
    fi
    
    # Delete bucket
    execute_command "Deleting S3 bucket ${BUCKET_NAME}" \
        "aws s3 rb s3://${BUCKET_NAME}" \
        "true"
    
    success "S3 bucket deleted successfully"
}

# Delete Polly lexicon
delete_polly_lexicon() {
    log "Deleting Polly lexicon..."
    
    # Check if lexicon exists
    if ! aws polly get-lexicon --name CustomPronunciations --region "${AWS_REGION}" &> /dev/null; then
        warning "Custom lexicon not found, skipping..."
        return 0
    fi
    
    execute_command "Deleting custom lexicon CustomPronunciations" \
        "aws polly delete-lexicon --name CustomPronunciations --region ${AWS_REGION}" \
        "true"
    
    success "Custom lexicon deleted successfully"
}

# Clean up any remaining speech synthesis tasks
cleanup_polly_tasks() {
    log "Checking for running speech synthesis tasks..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # List any running tasks (for informational purposes)
        local running_tasks=$(aws polly list-speech-synthesis-tasks \
            --region "${AWS_REGION}" \
            --task-status InProgress \
            --query 'SynthesisTasks[].TaskId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$running_tasks" && "$running_tasks" != "None" ]]; then
            warning "Found running speech synthesis tasks:"
            for task_id in $running_tasks; do
                log "  Task ID: $task_id"
            done
            warning "These tasks will complete on their own. Monitor in the Polly console if needed."
        else
            log "No running speech synthesis tasks found."
        fi
    else
        log "[DRY-RUN] Would check for running speech synthesis tasks"
    fi
}

# Manual cleanup mode for when .env is missing
manual_cleanup() {
    log "Starting manual cleanup mode..."
    
    # Try to find resources by common patterns
    log "Searching for Polly-related resources..."
    
    # Find S3 buckets with polly in the name
    log "Looking for S3 buckets with 'polly' in the name:"
    aws s3 ls | grep polly || log "No S3 buckets found with 'polly' in the name"
    
    # Find Lambda functions with polly in the name
    log "Looking for Lambda functions with 'polly' in the name:"
    aws lambda list-functions --region "${AWS_REGION}" \
        --query 'Functions[?contains(FunctionName, `polly`)].FunctionName' \
        --output table 2>/dev/null || log "No Lambda functions found with 'polly' in the name"
    
    # Find IAM roles with polly in the name
    log "Looking for IAM roles with 'polly' in the name:"
    aws iam list-roles --query 'Roles[?contains(RoleName, `Polly`)].RoleName' \
        --output table 2>/dev/null || log "No IAM roles found with 'Polly' in the name"
    
    # Check for custom lexicons
    log "Looking for custom lexicons:"
    aws polly list-lexicons --region "${AWS_REGION}" \
        --query 'Lexicons[].Name' --output table 2>/dev/null || log "No custom lexicons found"
    
    warning "Manual cleanup required. Please review the resources above and delete them manually through the AWS console or CLI."
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(".env" "bucket-policy.json" "trust-policy.json" "s3-policy.json" 
                          "lambda_function.py" "lambda_function.zip" "custom_lexicon.xml" 
                          "test_response.json" "sample_text.txt" "ssml_example.xml" "long_content.txt")
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            execute_command "Removing local file: $file" "rm -f $file" "true"
        fi
    done
    
    success "Local cleanup completed"
}

# Verify deletion
verify_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would verify resource deletion"
        return 0
    fi
    
    log "Verifying resource deletion..."
    
    local errors=0
    
    # Check S3 bucket
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if aws s3 ls "s3://${BUCKET_NAME}" &> /dev/null; then
            error "S3 bucket ${BUCKET_NAME} still exists"
            ((errors++))
        else
            success "S3 bucket ${BUCKET_NAME} successfully deleted"
        fi
    fi
    
    # Check Lambda function
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" --region "${AWS_REGION}" &> /dev/null; then
            error "Lambda function ${LAMBDA_FUNCTION_NAME} still exists"
            ((errors++))
        else
            success "Lambda function ${LAMBDA_FUNCTION_NAME} successfully deleted"
        fi
    fi
    
    # Check IAM role
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
            error "IAM role ${IAM_ROLE_NAME} still exists"
            ((errors++))
        else
            success "IAM role ${IAM_ROLE_NAME} successfully deleted"
        fi
    fi
    
    # Check custom lexicon
    if aws polly get-lexicon --name CustomPronunciations --region "${AWS_REGION}" &> /dev/null; then
        error "Custom lexicon CustomPronunciations still exists"
        ((errors++))
    else
        success "Custom lexicon CustomPronunciations successfully deleted"
    fi
    
    if [[ $errors -eq 0 ]]; then
        success "All resources verified as deleted"
    else
        warning "$errors resources may still exist. Please check manually."
    fi
}

# Main destruction function
main() {
    log "Starting Amazon Polly Text-to-Speech Solutions destruction..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY-RUN mode enabled - no resources will be deleted"
    fi
    
    load_environment
    
    # Check if we're in manual cleanup mode
    if [[ "${manual_cleanup_mode:-false}" == "true" ]]; then
        manual_cleanup
        return 0
    fi
    
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_lambda_function
    delete_iam_resources
    delete_s3_bucket
    delete_polly_lexicon
    cleanup_polly_tasks
    cleanup_local_files
    
    verify_deletion
    
    success "Destruction completed successfully!"
    
    log "Cleanup Summary:"
    log "================"
    log "✓ Lambda function deleted"
    log "✓ IAM resources deleted"
    log "✓ S3 bucket and contents deleted"
    log "✓ Custom lexicon deleted"
    log "✓ Local files cleaned up"
    log ""
    log "All Amazon Polly Text-to-Speech Solutions resources have been removed."
}

# Trap to ensure cleanup on script exit
cleanup_on_exit() {
    # No additional cleanup needed for destroy script
    :
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"