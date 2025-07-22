#!/bin/bash

# =============================================================================
# AWS Comprehend NLP Pipeline Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deployment script,
# including S3 buckets, Lambda functions, IAM roles, and Comprehend models.
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# =============================================================================
# Configuration and Variables
# =============================================================================

# Script metadata
SCRIPT_NAME="comprehend-nlp-destroy"
SCRIPT_VERSION="1.0"
LOG_FILE="/tmp/${SCRIPT_NAME}-$(date +%Y%m%d-%H%M%S).log"

# Configuration file from deployment
CONFIG_FILE="deployment-config.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
INTERACTIVE=true
FORCE_DELETE=false
DRY_RUN=false

# =============================================================================
# Logging Functions
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

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
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# =============================================================================
# Utility Functions
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or you don't have valid credentials."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

load_deployment_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log_info "Loading deployment configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
        
        log_info "Loaded configuration:"
        log_info "  AWS Region: ${AWS_REGION:-not set}"
        log_info "  AWS Account ID: ${AWS_ACCOUNT_ID:-not set}"
        log_info "  S3 Bucket: ${COMPREHEND_BUCKET:-not set}"
        log_info "  Lambda Function: ${LAMBDA_FUNCTION_NAME:-not set}"
        log_info "  IAM Role: ${IAM_ROLE_NAME:-not set}"
        log_info "  Random Suffix: ${RANDOM_SUFFIX:-not set}"
        log_info "  Deployment Date: ${DEPLOYMENT_DATE:-not set}"
        
        return 0
    else
        log_warning "Configuration file $CONFIG_FILE not found"
        return 1
    fi
}

prompt_for_confirmation() {
    local resource_type="$1"
    local resource_name="$2"
    
    if [ "$INTERACTIVE" = true ] && [ "$FORCE_DELETE" = false ]; then
        echo -e "${YELLOW}[CONFIRM]${NC} Delete $resource_type '$resource_name'? (y/N): "
        read -r response
        case "$response" in
            [yY][eS]|[yY])
                return 0
                ;;
            *)
                log_info "Skipped deletion of $resource_type '$resource_name'"
                return 1
                ;;
        esac
    fi
    return 0
}

wait_for_deletion() {
    local resource_type=$1
    local resource_identifier=$2
    local max_attempts=${3:-30}
    local sleep_time=${4:-10}
    
    log_info "Waiting for $resource_type '$resource_identifier' to be deleted..."
    
    for ((i=1; i<=max_attempts; i++)); do
        case $resource_type in
            "s3-bucket")
                if ! aws s3 ls "s3://$resource_identifier" &> /dev/null; then
                    log_success "$resource_type '$resource_identifier' has been deleted"
                    return 0
                fi
                ;;
            "lambda-function")
                if ! aws lambda get-function --function-name "$resource_identifier" &> /dev/null; then
                    log_success "$resource_type '$resource_identifier' has been deleted"
                    return 0
                fi
                ;;
            "iam-role")
                if ! aws iam get-role --role-name "$resource_identifier" &> /dev/null; then
                    log_success "$resource_type '$resource_identifier' has been deleted"
                    return 0
                fi
                ;;
            "comprehend-classifier")
                local status=$(aws comprehend describe-document-classifier \
                    --document-classifier-arn "$resource_identifier" \
                    --query 'DocumentClassifierProperties.Status' \
                    --output text 2>/dev/null || echo "DELETED")
                if [ "$status" = "DELETED" ] || [ "$status" = "DELETE_FAILED" ]; then
                    log_success "$resource_type has been deleted"
                    return 0
                fi
                ;;
        esac
        
        if [ $i -eq $max_attempts ]; then
            log_error "Timeout waiting for $resource_type '$resource_identifier' to be deleted"
            return 1
        fi
        
        log_info "Attempt $i/$max_attempts: $resource_type still exists, waiting ${sleep_time}s..."
        sleep $sleep_time
    done
}

# =============================================================================
# Resource Deletion Functions
# =============================================================================

delete_comprehend_resources() {
    log_info "Cleaning up Amazon Comprehend resources..."
    
    if [ -n "${RANDOM_SUFFIX:-}" ]; then
        local classifier_name="feedback-classifier-${RANDOM_SUFFIX}"
        local classifier_arn="arn:aws:comprehend:${AWS_REGION}:${AWS_ACCOUNT_ID}:document-classifier/${classifier_name}"
        
        # Check if classifier exists and delete it
        if aws comprehend describe-document-classifier \
            --document-classifier-arn "$classifier_arn" &> /dev/null; then
            
            if prompt_for_confirmation "Comprehend document classifier" "$classifier_name"; then
                log_info "Deleting document classifier: $classifier_name"
                aws comprehend delete-document-classifier \
                    --document-classifier-arn "$classifier_arn"
                log_success "Initiated deletion of document classifier"
                
                # Wait for deletion to complete
                wait_for_deletion "comprehend-classifier" "$classifier_arn" 60 30
            fi
        else
            log_info "Document classifier $classifier_name not found or already deleted"
        fi
        
        # Check for any running Comprehend jobs and list them
        log_info "Checking for running Comprehend jobs..."
        
        # List sentiment detection jobs
        local jobs=$(aws comprehend list-sentiment-detection-jobs \
            --filter "JobName=batch-job-${RANDOM_SUFFIX},JobStatus=IN_PROGRESS" \
            --query 'SentimentDetectionJobPropertiesList[].JobId' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$jobs" ]; then
            log_warning "Found running sentiment detection jobs: $jobs"
            log_warning "These jobs will continue running and incur charges until completed"
            log_warning "Consider stopping them manually if needed"
        fi
    else
        log_warning "Random suffix not available, skipping Comprehend resource cleanup"
    fi
}

delete_lambda_function() {
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
            if prompt_for_confirmation "Lambda function" "$LAMBDA_FUNCTION_NAME"; then
                log_info "Deleting Lambda function: $LAMBDA_FUNCTION_NAME"
                aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
                log_success "Deleted Lambda function: $LAMBDA_FUNCTION_NAME"
                
                # Wait for deletion
                wait_for_deletion "lambda-function" "$LAMBDA_FUNCTION_NAME" 20 5
            fi
        else
            log_info "Lambda function $LAMBDA_FUNCTION_NAME not found or already deleted"
        fi
    else
        log_warning "Lambda function name not available, skipping Lambda cleanup"
    fi
}

delete_iam_resources() {
    log_info "Cleaning up IAM resources..."
    
    if [ -n "${IAM_ROLE_NAME:-}" ] && [ -n "${RANDOM_SUFFIX:-}" ]; then
        # Delete Lambda execution role and policies
        if aws iam get-role --role-name "$IAM_ROLE_NAME" &> /dev/null; then
            if prompt_for_confirmation "IAM role" "$IAM_ROLE_NAME"; then
                log_info "Detaching policies from role: $IAM_ROLE_NAME"
                
                # Detach AWS managed policy
                aws iam detach-role-policy \
                    --role-name "$IAM_ROLE_NAME" \
                    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
                    2>/dev/null || log_warning "Failed to detach basic execution policy"
                
                # Detach custom policy
                local custom_policy_name="ComprehendLambdaPolicy-${RANDOM_SUFFIX}"
                aws iam detach-role-policy \
                    --role-name "$IAM_ROLE_NAME" \
                    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${custom_policy_name}" \
                    2>/dev/null || log_warning "Failed to detach custom policy"
                
                # Delete custom policy
                aws iam delete-policy \
                    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${custom_policy_name}" \
                    2>/dev/null && log_success "Deleted custom policy: $custom_policy_name" || log_warning "Custom policy not found"
                
                # Delete role
                aws iam delete-role --role-name "$IAM_ROLE_NAME"
                log_success "Deleted IAM role: $IAM_ROLE_NAME"
            fi
        else
            log_info "IAM role $IAM_ROLE_NAME not found or already deleted"
        fi
        
        # Delete Comprehend service role
        local comprehend_role_name="ComprehendServiceRole-${RANDOM_SUFFIX}"
        if aws iam get-role --role-name "$comprehend_role_name" &> /dev/null; then
            if prompt_for_confirmation "Comprehend service role" "$comprehend_role_name"; then
                log_info "Cleaning up Comprehend service role: $comprehend_role_name"
                
                # Detach S3 policy
                local comprehend_s3_policy_name="ComprehendS3Policy-${RANDOM_SUFFIX}"
                aws iam detach-role-policy \
                    --role-name "$comprehend_role_name" \
                    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${comprehend_s3_policy_name}" \
                    2>/dev/null || log_warning "Failed to detach Comprehend S3 policy"
                
                # Delete S3 policy
                aws iam delete-policy \
                    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${comprehend_s3_policy_name}" \
                    2>/dev/null && log_success "Deleted Comprehend S3 policy: $comprehend_s3_policy_name" || log_warning "Comprehend S3 policy not found"
                
                # Delete role
                aws iam delete-role --role-name "$comprehend_role_name"
                log_success "Deleted Comprehend service role: $comprehend_role_name"
            fi
        else
            log_info "Comprehend service role $comprehend_role_name not found or already deleted"
        fi
    else
        log_warning "IAM role information not available, skipping IAM cleanup"
    fi
}

delete_s3_resources() {
    log_info "Cleaning up S3 resources..."
    
    if [ -n "${COMPREHEND_BUCKET:-}" ]; then
        # Delete input bucket
        if aws s3 ls "s3://${COMPREHEND_BUCKET}" &> /dev/null; then
            if prompt_for_confirmation "S3 bucket and all contents" "$COMPREHEND_BUCKET"; then
                log_info "Emptying and deleting S3 bucket: $COMPREHEND_BUCKET"
                aws s3 rm "s3://${COMPREHEND_BUCKET}" --recursive
                aws s3 rb "s3://${COMPREHEND_BUCKET}"
                log_success "Deleted S3 bucket: $COMPREHEND_BUCKET"
            fi
        else
            log_info "S3 bucket $COMPREHEND_BUCKET not found or already deleted"
        fi
        
        # Delete output bucket
        local output_bucket="${COMPREHEND_BUCKET}-output"
        if aws s3 ls "s3://${output_bucket}" &> /dev/null; then
            if prompt_for_confirmation "S3 output bucket and all contents" "$output_bucket"; then
                log_info "Emptying and deleting S3 output bucket: $output_bucket"
                aws s3 rm "s3://${output_bucket}" --recursive
                aws s3 rb "s3://${output_bucket}"
                log_success "Deleted S3 output bucket: $output_bucket"
            fi
        else
            log_info "S3 output bucket $output_bucket not found or already deleted"
        fi
    else
        log_warning "S3 bucket name not available, skipping S3 cleanup"
    fi
}

clean_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_clean=(
        "lambda-trust-policy.json"
        "comprehend-policy.json"
        "comprehend-service-role-policy.json"
        "comprehend-s3-policy.json"
        "lambda_function.py"
        "lambda-function.zip"
        "sample-reviews.txt"
        "batch-input.txt"
        "training-manifest.csv"
        "batch-analysis.py"
        "analyze-results.py"
        "response.json"
        "negative-test.json"
    )
    
    local cleaned_count=0
    for file in "${files_to_clean[@]}"; do
        if [ -f "$file" ]; then
            if prompt_for_confirmation "local file" "$file"; then
                rm -f "$file"
                log_success "Removed local file: $file"
                ((cleaned_count++))
            fi
        fi
    done
    
    # Clean up training data directory
    if [ -d "training-data" ]; then
        if prompt_for_confirmation "training data directory" "training-data/"; then
            rm -rf "training-data/"
            log_success "Removed training-data directory"
            ((cleaned_count++))
        fi
    fi
    
    if [ $cleaned_count -eq 0 ]; then
        log_info "No local files found to clean up"
    else
        log_success "Cleaned up $cleaned_count local files/directories"
    fi
}

# =============================================================================
# Main Cleanup Functions
# =============================================================================

cleanup_all_resources() {
    log_info "Starting comprehensive cleanup of AWS Comprehend NLP Pipeline..."
    
    # Set AWS region if available
    if [ -n "${AWS_REGION:-}" ]; then
        export AWS_REGION
    fi
    
    # Clean up resources in reverse order of creation
    delete_comprehend_resources
    delete_lambda_function
    delete_iam_resources
    delete_s3_resources
    clean_local_files
    
    # Remove deployment config file
    if [ -f "$CONFIG_FILE" ]; then
        if prompt_for_confirmation "deployment configuration file" "$CONFIG_FILE"; then
            rm -f "$CONFIG_FILE"
            log_success "Removed deployment configuration file: $CONFIG_FILE"
        fi
    fi
    
    log_success "Cleanup completed successfully!"
}

interactive_cleanup() {
    echo "=== AWS Comprehend NLP Pipeline Cleanup ==="
    echo ""
    
    if load_deployment_config; then
        echo ""
        echo "Found deployment configuration. The following resources will be cleaned up:"
        echo ""
        echo "📊 Amazon Comprehend:"
        echo "   - Document classifier (if created)"
        echo "   - Running analysis jobs (listed for manual cleanup)"
        echo ""
        echo "⚡ AWS Lambda:"
        echo "   - Function: ${LAMBDA_FUNCTION_NAME:-unknown}"
        echo ""
        echo "🔐 IAM Resources:"
        echo "   - Role: ${IAM_ROLE_NAME:-unknown}"
        echo "   - Custom policies for Comprehend and S3 access"
        echo "   - Comprehend service role and policies"
        echo ""
        echo "🗄️  S3 Storage:"
        echo "   - Input bucket: ${COMPREHEND_BUCKET:-unknown}"
        echo "   - Output bucket: ${COMPREHEND_BUCKET:-unknown}-output"
        echo "   - All bucket contents"
        echo ""
        echo "📁 Local Files:"
        echo "   - Temporary files created during deployment"
        echo "   - Configuration and policy files"
        echo ""
        
        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN MODE - No resources will be deleted"
            exit 0
        fi
        
        echo -e "${YELLOW}[WARNING]${NC} This will permanently delete ALL resources and data!"
        echo -e "${YELLOW}[WARNING]${NC} This action cannot be undone!"
        echo ""
        echo -n "Do you want to continue with the cleanup? (y/N): "
        read -r response
        case "$response" in
            [yY][eS]|[yY])
                cleanup_all_resources
                ;;
            *)
                log_info "Cleanup cancelled by user"
                exit 0
                ;;
        esac
    else
        echo ""
        echo "No deployment configuration found. You can still clean up resources manually."
        echo ""
        echo "Would you like to:"
        echo "1. Specify resource names manually"
        echo "2. Exit and locate deployment-config.env file"
        echo ""
        echo -n "Choose option (1/2): "
        read -r choice
        case "$choice" in
            1)
                manual_cleanup
                ;;
            *)
                log_info "Please locate the deployment-config.env file and run this script from the same directory"
                exit 1
                ;;
        esac
    fi
}

manual_cleanup() {
    echo ""
    echo "=== Manual Resource Cleanup ==="
    echo ""
    echo "Please provide the following information (or press Enter to skip):"
    echo ""
    
    echo -n "AWS Region: "
    read -r AWS_REGION
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    
    echo -n "AWS Account ID: "
    read -r AWS_ACCOUNT_ID
    export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
    
    echo -n "S3 Bucket name (without -output suffix): "
    read -r COMPREHEND_BUCKET
    export COMPREHEND_BUCKET
    
    echo -n "Lambda function name: "
    read -r LAMBDA_FUNCTION_NAME
    export LAMBDA_FUNCTION_NAME
    
    echo -n "IAM role name: "
    read -r IAM_ROLE_NAME
    export IAM_ROLE_NAME
    
    echo -n "Random suffix used in deployment: "
    read -r RANDOM_SUFFIX
    export RANDOM_SUFFIX
    
    if [ -n "$COMPREHEND_BUCKET" ] || [ -n "$LAMBDA_FUNCTION_NAME" ] || [ -n "$IAM_ROLE_NAME" ]; then
        cleanup_all_resources
    else
        log_error "Insufficient information provided for cleanup"
        exit 1
    fi
}

# =============================================================================
# Help and Usage
# =============================================================================

show_help() {
    cat << EOF
AWS Comprehend NLP Pipeline Cleanup Script

USAGE:
    $0 [OPTIONS]

DESCRIPTION:
    Safely removes all resources created by the Comprehend NLP Pipeline deployment,
    including S3 buckets, Lambda functions, IAM roles, and Comprehend models.

OPTIONS:
    -f, --force                 Force deletion without confirmation prompts
    -y, --yes                  Answer yes to all prompts (same as --force)
    -n, --non-interactive      Run in non-interactive mode
    -c, --config FILE          Use specific configuration file (default: deployment-config.env)
    -h, --help                 Show this help message
    -v, --version              Show script version
    --dry-run                  Show what would be deleted without making changes

EXAMPLES:
    $0                         # Interactive cleanup with confirmations
    $0 --force                 # Automatic cleanup without prompts
    $0 --dry-run               # Preview what would be deleted
    $0 --config my-deploy.env  # Use custom configuration file

SAFETY FEATURES:
    - Confirmation prompts for each resource type
    - Dry-run mode to preview deletions
    - Detailed logging of all operations
    - Graceful handling of missing resources

REQUIREMENTS:
    - AWS CLI v2 installed and configured
    - Appropriate AWS permissions for resource deletion
    - deployment-config.env file (or manual resource specification)

For more information, see the recipe documentation.
EOF
}

show_version() {
    echo "${SCRIPT_NAME} version ${SCRIPT_VERSION}"
}

# =============================================================================
# Argument Parsing
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force|-y|--yes)
            FORCE_DELETE=true
            INTERACTIVE=false
            shift
            ;;
        -n|--non-interactive)
            INTERACTIVE=false
            shift
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            show_version
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

# =============================================================================
# Main Execution
# =============================================================================

main() {
    echo "=== AWS Comprehend NLP Pipeline Cleanup Script ==="
    echo "Version: ${SCRIPT_VERSION}"
    echo "Log file: ${LOG_FILE}"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Execute cleanup
    if [ "$INTERACTIVE" = true ]; then
        interactive_cleanup
    else
        log_info "Running in non-interactive mode"
        if load_deployment_config; then
            if [ "$DRY_RUN" = true ]; then
                log_info "DRY RUN MODE - No resources will be deleted"
                log_info "Resources that would be deleted:"
                log_info "  - S3 buckets: ${COMPREHEND_BUCKET:-unknown}, ${COMPREHEND_BUCKET:-unknown}-output"
                log_info "  - Lambda function: ${LAMBDA_FUNCTION_NAME:-unknown}"
                log_info "  - IAM roles and policies"
                log_info "  - Comprehend models and jobs"
                exit 0
            fi
            cleanup_all_resources
        else
            log_error "No deployment configuration found and running in non-interactive mode"
            log_error "Please provide configuration file or run in interactive mode"
            exit 1
        fi
    fi
    
    echo ""
    log_success "Cleanup completed successfully!"
    echo "Check the log file for detailed information: $LOG_FILE"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi