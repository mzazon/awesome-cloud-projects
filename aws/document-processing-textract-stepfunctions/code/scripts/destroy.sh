#!/bin/bash
set -e

# AWS Textract and Step Functions Document Processing Pipeline Cleanup Script
# This script safely removes all resources created by the deployment script

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running in force mode (skip confirmations)
FORCE_MODE=${FORCE_MODE:-false}
if [[ "$1" == "--force" ]] || [[ "$FORCE_MODE" == "true" ]]; then
    FORCE_MODE=true
    warning "Running in FORCE mode - skipping confirmation prompts"
fi

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [[ "$1" == "--dry-run" ]] || [[ "$DRY_RUN" == "true" ]]; then
    DRY_RUN=true
    warning "Running in DRY-RUN mode - no resources will be deleted"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: Would execute: $cmd"
        if [[ -n "$description" ]]; then
            log "DRY-RUN: $description"
        fi
        return 0
    else
        log "Executing: $description"
        eval "$cmd"
        return $?
    fi
}

# Function to confirm destructive actions
confirm_action() {
    local message="$1"
    
    if [[ "$FORCE_MODE" == "true" ]]; then
        return 0
    fi
    
    echo -n -e "${YELLOW}[CONFIRM]${NC} $message (y/N): "
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &>/dev/null; then
        error "AWS CLI is not configured or authentication failed"
        error "Please run 'aws configure' or set up your credentials"
        exit 1
    fi
    
    # Check for required tools
    local required_tools=("jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    success "Prerequisites check completed"
}

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    local deployment_file=""
    
    # Check for deployment-info.json in current directory
    if [[ -f "deployment-info.json" ]]; then
        deployment_file="deployment-info.json"
    # Check for deployment-info.json in parent directory
    elif [[ -f "../deployment-info.json" ]]; then
        deployment_file="../deployment-info.json"
    else
        warning "Deployment info file not found. Will attempt to discover resources."
        return 1
    fi
    
    log "Loading deployment info from: $deployment_file"
    
    # Extract values from deployment info
    export PROJECT_NAME=$(jq -r '.projectName' "$deployment_file")
    export AWS_REGION=$(jq -r '.region' "$deployment_file")
    export AWS_ACCOUNT_ID=$(jq -r '.accountId' "$deployment_file")
    export INPUT_BUCKET=$(jq -r '.buckets.input' "$deployment_file")
    export OUTPUT_BUCKET=$(jq -r '.buckets.output' "$deployment_file")
    export ARCHIVE_BUCKET=$(jq -r '.buckets.archive' "$deployment_file")
    export STATE_MACHINE_ARN=$(jq -r '.stepFunctions.stateMachineArn' "$deployment_file")
    
    # Validate extracted values
    if [[ "$PROJECT_NAME" == "null" ]] || [[ -z "$PROJECT_NAME" ]]; then
        error "Invalid deployment info: PROJECT_NAME not found"
        return 1
    fi
    
    log "Project Name: $PROJECT_NAME"
    log "Region: $AWS_REGION"
    log "Account ID: $AWS_ACCOUNT_ID"
    
    success "Deployment information loaded successfully"
    return 0
}

# Discover resources if deployment info is not available
discover_resources() {
    log "Discovering resources..."
    
    if [[ -z "$PROJECT_NAME" ]]; then
        # Try to discover project name from existing resources
        local lambda_functions=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `textract-pipeline`)].FunctionName' --output text)
        
        if [[ -n "$lambda_functions" ]]; then
            # Extract project name from first function
            export PROJECT_NAME=$(echo "$lambda_functions" | head -1 | sed 's/-document-processor.*//')
            log "Discovered project name: $PROJECT_NAME"
        else
            error "Could not discover project name. Please provide PROJECT_NAME environment variable."
            echo "Example: export PROJECT_NAME=textract-pipeline-abc123"
            exit 1
        fi
    fi
    
    # Set default values if not loaded from deployment info
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
    export INPUT_BUCKET=${INPUT_BUCKET:-"${PROJECT_NAME}-input"}
    export OUTPUT_BUCKET=${OUTPUT_BUCKET:-"${PROJECT_NAME}-output"}
    export ARCHIVE_BUCKET=${ARCHIVE_BUCKET:-"${PROJECT_NAME}-archive"}
    export STATE_MACHINE_ARN=${STATE_MACHINE_ARN:-"arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${PROJECT_NAME}-document-pipeline"}
    
    success "Resource discovery completed"
}

# Check for existing resources
check_existing_resources() {
    log "Checking for existing resources..."
    
    local resources_found=0
    
    # Check Lambda functions
    local lambda_functions=("document-processor" "results-processor" "s3-trigger")
    for func in "${lambda_functions[@]}"; do
        if aws lambda get-function --function-name "${PROJECT_NAME}-${func}" &>/dev/null; then
            log "Found Lambda function: ${PROJECT_NAME}-${func}"
            ((resources_found++))
        fi
    done
    
    # Check Step Functions state machine
    if aws stepfunctions describe-state-machine --state-machine-arn "$STATE_MACHINE_ARN" &>/dev/null; then
        log "Found Step Functions state machine: $STATE_MACHINE_ARN"
        ((resources_found++))
    fi
    
    # Check S3 buckets
    for bucket in "$INPUT_BUCKET" "$OUTPUT_BUCKET" "$ARCHIVE_BUCKET"; do
        if aws s3api head-bucket --bucket "$bucket" &>/dev/null; then
            log "Found S3 bucket: $bucket"
            ((resources_found++))
        fi
    done
    
    # Check IAM roles
    for role in "${PROJECT_NAME}-lambda-role" "${PROJECT_NAME}-stepfunctions-role"; do
        if aws iam get-role --role-name "$role" &>/dev/null; then
            log "Found IAM role: $role"
            ((resources_found++))
        fi
    done
    
    if [[ $resources_found -eq 0 ]]; then
        warning "No resources found for project: $PROJECT_NAME"
        log "Nothing to clean up."
        exit 0
    else
        log "Found $resources_found resources to clean up"
    fi
    
    success "Resource check completed"
}

# Stop running Step Functions executions
stop_executions() {
    log "Stopping running Step Functions executions..."
    
    # Get running executions
    local running_executions=$(aws stepfunctions list-executions \
        --state-machine-arn "$STATE_MACHINE_ARN" \
        --status-filter RUNNING \
        --query 'executions[].executionArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$running_executions" ]]; then
        log "Found running executions, stopping them..."
        
        for execution in $running_executions; do
            if [[ "$execution" != "None" ]]; then
                execute_command "aws stepfunctions stop-execution --execution-arn $execution" \
                    "Stopping execution: $execution"
            fi
        done
        
        # Wait for executions to stop
        sleep 10
    else
        log "No running executions found"
    fi
    
    success "Step Functions executions stopped"
}

# Remove Step Functions state machine
remove_state_machine() {
    log "Removing Step Functions state machine..."
    
    if aws stepfunctions describe-state-machine --state-machine-arn "$STATE_MACHINE_ARN" &>/dev/null; then
        if confirm_action "Delete Step Functions state machine: $STATE_MACHINE_ARN?"; then
            execute_command "aws stepfunctions delete-state-machine --state-machine-arn $STATE_MACHINE_ARN" \
                "Deleting Step Functions state machine"
            success "Step Functions state machine deleted"
        else
            warning "Skipping Step Functions state machine deletion"
        fi
    else
        log "Step Functions state machine not found"
    fi
}

# Remove Lambda functions
remove_lambda_functions() {
    log "Removing Lambda functions..."
    
    local lambda_functions=("document-processor" "results-processor" "s3-trigger")
    
    for func in "${lambda_functions[@]}"; do
        local function_name="${PROJECT_NAME}-${func}"
        
        if aws lambda get-function --function-name "$function_name" &>/dev/null; then
            if confirm_action "Delete Lambda function: $function_name?"; then
                execute_command "aws lambda delete-function --function-name $function_name" \
                    "Deleting Lambda function: $function_name"
                success "Lambda function deleted: $function_name"
            else
                warning "Skipping Lambda function deletion: $function_name"
            fi
        else
            log "Lambda function not found: $function_name"
        fi
    done
}

# Remove CloudWatch resources
remove_cloudwatch_resources() {
    log "Removing CloudWatch resources..."
    
    # Remove CloudWatch dashboard
    local dashboard_name="${PROJECT_NAME}-pipeline-monitoring"
    if aws cloudwatch get-dashboard --dashboard-name "$dashboard_name" &>/dev/null; then
        if confirm_action "Delete CloudWatch dashboard: $dashboard_name?"; then
            execute_command "aws cloudwatch delete-dashboards --dashboard-names $dashboard_name" \
                "Deleting CloudWatch dashboard"
            success "CloudWatch dashboard deleted"
        else
            warning "Skipping CloudWatch dashboard deletion"
        fi
    else
        log "CloudWatch dashboard not found"
    fi
    
    # Remove log groups
    local log_groups=(
        "/aws/lambda/${PROJECT_NAME}-document-processor"
        "/aws/lambda/${PROJECT_NAME}-results-processor"
        "/aws/lambda/${PROJECT_NAME}-s3-trigger"
        "/aws/stepfunctions/${PROJECT_NAME}-document-pipeline"
    )
    
    for log_group in "${log_groups[@]}"; do
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group"; then
            if confirm_action "Delete CloudWatch log group: $log_group?"; then
                execute_command "aws logs delete-log-group --log-group-name $log_group" \
                    "Deleting log group: $log_group"
                success "Log group deleted: $log_group"
            else
                warning "Skipping log group deletion: $log_group"
            fi
        else
            log "Log group not found: $log_group"
        fi
    done
}

# Remove IAM roles and policies
remove_iam_roles() {
    log "Removing IAM roles and policies..."
    
    # Remove Lambda role
    local lambda_role="${PROJECT_NAME}-lambda-role"
    if aws iam get-role --role-name "$lambda_role" &>/dev/null; then
        if confirm_action "Delete IAM role: $lambda_role?"; then
            # Detach managed policies
            local managed_policies=(
                "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
                "arn:aws:iam::aws:policy/AmazonTextractFullAccess"
                "arn:aws:iam::aws:policy/AmazonS3FullAccess"
                "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
            )
            
            for policy in "${managed_policies[@]}"; do
                execute_command "aws iam detach-role-policy --role-name $lambda_role --policy-arn $policy" \
                    "Detaching policy: $policy" || true
            done
            
            # Delete inline policies
            local inline_policies=$(aws iam list-role-policies --role-name "$lambda_role" --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
            for policy in $inline_policies; do
                if [[ "$policy" != "None" ]]; then
                    execute_command "aws iam delete-role-policy --role-name $lambda_role --policy-name $policy" \
                        "Deleting inline policy: $policy"
                fi
            done
            
            execute_command "aws iam delete-role --role-name $lambda_role" \
                "Deleting IAM role: $lambda_role"
            success "IAM role deleted: $lambda_role"
        else
            warning "Skipping IAM role deletion: $lambda_role"
        fi
    else
        log "IAM role not found: $lambda_role"
    fi
    
    # Remove Step Functions role
    local stepfunctions_role="${PROJECT_NAME}-stepfunctions-role"
    if aws iam get-role --role-name "$stepfunctions_role" &>/dev/null; then
        if confirm_action "Delete IAM role: $stepfunctions_role?"; then
            # Delete inline policies
            local inline_policies=$(aws iam list-role-policies --role-name "$stepfunctions_role" --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
            for policy in $inline_policies; do
                if [[ "$policy" != "None" ]]; then
                    execute_command "aws iam delete-role-policy --role-name $stepfunctions_role --policy-name $policy" \
                        "Deleting inline policy: $policy"
                fi
            done
            
            execute_command "aws iam delete-role --role-name $stepfunctions_role" \
                "Deleting IAM role: $stepfunctions_role"
            success "IAM role deleted: $stepfunctions_role"
        else
            warning "Skipping IAM role deletion: $stepfunctions_role"
        fi
    else
        log "IAM role not found: $stepfunctions_role"
    fi
}

# Remove S3 buckets and contents
remove_s3_buckets() {
    log "Removing S3 buckets and contents..."
    
    for bucket in "$INPUT_BUCKET" "$OUTPUT_BUCKET" "$ARCHIVE_BUCKET"; do
        if aws s3api head-bucket --bucket "$bucket" &>/dev/null; then
            # Check if bucket has contents
            local object_count=$(aws s3api list-objects-v2 --bucket "$bucket" --query 'KeyCount' --output text 2>/dev/null || echo "0")
            
            if [[ "$object_count" -gt 0 ]]; then
                warning "Bucket $bucket contains $object_count objects"
                if confirm_action "Delete all objects in bucket $bucket and then delete the bucket?"; then
                    execute_command "aws s3 rm s3://$bucket --recursive" \
                        "Removing all objects from bucket: $bucket"
                    execute_command "aws s3 rb s3://$bucket" \
                        "Deleting bucket: $bucket"
                    success "S3 bucket deleted: $bucket"
                else
                    warning "Skipping S3 bucket deletion: $bucket"
                fi
            else
                if confirm_action "Delete empty bucket: $bucket?"; then
                    execute_command "aws s3 rb s3://$bucket" \
                        "Deleting bucket: $bucket"
                    success "S3 bucket deleted: $bucket"
                else
                    warning "Skipping S3 bucket deletion: $bucket"
                fi
            fi
        else
            log "S3 bucket not found: $bucket"
        fi
    done
}

# Remove temporary files
remove_temp_files() {
    log "Removing temporary files..."
    
    local temp_files=(
        "deployment-info.json"
        "*.json"
        "*.py"
        "*.zip"
        "*.txt"
    )
    
    for pattern in "${temp_files[@]}"; do
        if ls $pattern &>/dev/null; then
            execute_command "rm -f $pattern" \
                "Removing temporary files: $pattern"
        fi
    done
    
    success "Temporary files cleaned up"
}

# Verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local remaining_resources=0
    
    # Check Lambda functions
    local lambda_functions=("document-processor" "results-processor" "s3-trigger")
    for func in "${lambda_functions[@]}"; do
        if aws lambda get-function --function-name "${PROJECT_NAME}-${func}" &>/dev/null; then
            warning "Lambda function still exists: ${PROJECT_NAME}-${func}"
            ((remaining_resources++))
        fi
    done
    
    # Check Step Functions state machine
    if aws stepfunctions describe-state-machine --state-machine-arn "$STATE_MACHINE_ARN" &>/dev/null; then
        warning "Step Functions state machine still exists: $STATE_MACHINE_ARN"
        ((remaining_resources++))
    fi
    
    # Check S3 buckets
    for bucket in "$INPUT_BUCKET" "$OUTPUT_BUCKET" "$ARCHIVE_BUCKET"; do
        if aws s3api head-bucket --bucket "$bucket" &>/dev/null; then
            warning "S3 bucket still exists: $bucket"
            ((remaining_resources++))
        fi
    done
    
    # Check IAM roles
    for role in "${PROJECT_NAME}-lambda-role" "${PROJECT_NAME}-stepfunctions-role"; do
        if aws iam get-role --role-name "$role" &>/dev/null; then
            warning "IAM role still exists: $role"
            ((remaining_resources++))
        fi
    done
    
    if [[ $remaining_resources -eq 0 ]]; then
        success "All resources have been successfully cleaned up"
        return 0
    else
        warning "Cleanup completed with $remaining_resources resources remaining"
        warning "Some resources may have been skipped due to user choice or deletion restrictions"
        return 1
    fi
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be deleted without actually deleting"
    echo "  --force      Skip confirmation prompts and delete all resources"
    echo "  --help       Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_NAME    Override project name for resource discovery"
    echo "  FORCE_MODE      Set to 'true' to skip confirmations"
    echo "  DRY_RUN         Set to 'true' to run in dry-run mode"
    echo ""
    echo "Examples:"
    echo "  $0                          # Interactive cleanup"
    echo "  $0 --dry-run                # Preview what would be deleted"
    echo "  $0 --force                  # Delete all resources without confirmation"
    echo "  PROJECT_NAME=my-project $0  # Override project name"
}

# Main cleanup function
main() {
    # Handle help option
    if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        show_usage
        exit 0
    fi
    
    log "Starting AWS Textract and Step Functions Document Processing Pipeline cleanup..."
    
    # Show warning about destructive operation
    if [[ "$DRY_RUN" != "true" ]]; then
        echo -e "${RED}WARNING: This script will delete AWS resources and may result in data loss!${NC}"
        echo -e "${RED}Make sure you have backed up any important data before proceeding.${NC}"
        echo ""
        
        if [[ "$FORCE_MODE" != "true" ]]; then
            if ! confirm_action "Are you sure you want to proceed with the cleanup?"; then
                log "Cleanup cancelled by user"
                exit 0
            fi
        fi
    fi
    
    # Run cleanup steps
    check_prerequisites
    
    # Try to load deployment info, fall back to discovery if not available
    if ! load_deployment_info; then
        discover_resources
    fi
    
    check_existing_resources
    stop_executions
    remove_state_machine
    remove_lambda_functions
    remove_cloudwatch_resources
    remove_iam_roles
    remove_s3_buckets
    remove_temp_files
    
    # Verify cleanup
    if verify_cleanup; then
        success "Cleanup completed successfully!"
        echo ""
        echo "========================================="
        echo "CLEANUP SUMMARY"
        echo "========================================="
        echo "Project Name: $PROJECT_NAME"
        echo "Region: $AWS_REGION"
        echo ""
        echo "All resources for the document processing pipeline have been removed."
        echo "Please verify in the AWS Console that no unexpected charges occur."
        echo "========================================="
    else
        warning "Cleanup completed with some resources remaining"
        echo ""
        echo "Please check the AWS Console for any remaining resources that may need manual cleanup."
        echo "This may include resources that were created outside of this script or have deletion protection enabled."
    fi
}

# Run main function
main "$@"