#!/bin/bash

# Destroy script for SageMaker AutoML for Time Series Forecasting
# This script safely removes all resources created by the deployment

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_ROOT/cleanup.log"
DEPLOYMENT_STATE_FILE="$PROJECT_ROOT/.deployment_state"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

error() {
    log "${RED}ERROR: $1${NC}" >&2
    exit 1
}

warning() {
    log "${YELLOW}WARNING: $1${NC}"
}

info() {
    log "${BLUE}INFO: $1${NC}"
}

success() {
    log "${GREEN}SUCCESS: $1${NC}"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely destroy all resources created by the AutoML Forecasting solution.

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deleted without making changes
    -f, --force         Skip confirmation prompts
    -v, --verbose       Enable verbose logging
    --state-file        Use specific state file (default: .deployment_state)
    --keep-data         Keep S3 bucket and training data
    --parallel          Delete resources in parallel (faster but less safe)

EXAMPLES:
    $0                          # Interactive cleanup with confirmations
    $0 --dry-run               # Preview what would be deleted
    $0 --force                 # Non-interactive cleanup
    $0 --keep-data             # Remove compute resources but keep data

SAFETY FEATURES:
    - Confirmation prompts for destructive actions
    - Dry-run mode to preview changes
    - Resource dependency order handling
    - Partial cleanup recovery

EOF
}

# Parse command line arguments
DRY_RUN=false
FORCE=false
VERBOSE=false
KEEP_DATA=false
PARALLEL=false
CUSTOM_STATE_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --state-file)
            CUSTOM_STATE_FILE="$2"
            shift 2
            ;;
        --keep-data)
            KEEP_DATA=true
            shift
            ;;
        --parallel)
            PARALLEL=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Verbose logging
if [ "$VERBOSE" = true ]; then
    set -x
fi

# Load deployment state
load_deployment_state() {
    local state_file="${CUSTOM_STATE_FILE:-$DEPLOYMENT_STATE_FILE}"
    
    if [ ! -f "$state_file" ]; then
        warning "No deployment state file found at: $state_file"
        warning "You may need to manually clean up resources."
        
        # Try to discover resources by pattern
        info "Attempting to discover resources..."
        discover_resources
        return
    fi
    
    info "Loading deployment state from: $state_file"
    source "$state_file"
    
    # Validate required variables
    local required_vars=(
        "AWS_REGION" "AWS_ACCOUNT_ID" "RANDOM_SUFFIX"
        "FORECAST_BUCKET" "SAGEMAKER_ROLE_NAME" "AUTOML_JOB_NAME"
        "LAMBDA_FUNCTION_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            warning "Missing required variable: $var"
        fi
    done
    
    success "Deployment state loaded successfully"
}

# Discover resources when state file is missing
discover_resources() {
    info "Attempting to discover AutoML Forecasting resources..."
    
    # Get current AWS region and account
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Try to find S3 buckets with our naming pattern
    local buckets=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `automl-forecasting-`)].Name' --output text)
    if [ -n "$buckets" ]; then
        info "Found potential S3 buckets: $buckets"
        # Use the first bucket found
        export FORECAST_BUCKET=$(echo "$buckets" | head -n1)
        export RANDOM_SUFFIX=$(echo "$FORECAST_BUCKET" | sed 's/automl-forecasting-//')
    fi
    
    # Set other resource names based on discovered suffix
    if [ -n "${RANDOM_SUFFIX:-}" ]; then
        export SAGEMAKER_ROLE_NAME="AutoMLForecastingRole-${RANDOM_SUFFIX}"
        export AUTOML_JOB_NAME="retail-demand-forecast-${RANDOM_SUFFIX}"
        export MODEL_NAME="automl-forecast-model-${RANDOM_SUFFIX}"
        export ENDPOINT_CONFIG_NAME="automl-forecast-config-${RANDOM_SUFFIX}"
        export ENDPOINT_NAME="automl-forecast-endpoint-${RANDOM_SUFFIX}"
        export LAMBDA_FUNCTION_NAME="automl-forecast-api-${RANDOM_SUFFIX}"
    fi
}

# Confirmation prompt
confirm_action() {
    local message="$1"
    
    if [ "$FORCE" = true ]; then
        return 0
    fi
    
    echo -e "${YELLOW}$message${NC}"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Operation cancelled by user"
        exit 0
    fi
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case "$resource_type" in
        "s3-bucket")
            aws s3api head-bucket --bucket "$resource_name" 2>/dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_name" 2>/dev/null >/dev/null
            ;;
        "sagemaker-endpoint")
            aws sagemaker describe-endpoint --endpoint-name "$resource_name" 2>/dev/null >/dev/null
            ;;
        "sagemaker-endpoint-config")
            aws sagemaker describe-endpoint-config --endpoint-config-name "$resource_name" 2>/dev/null >/dev/null
            ;;
        "sagemaker-model")
            aws sagemaker describe-model --model-name "$resource_name" 2>/dev/null >/dev/null
            ;;
        "sagemaker-automl-job")
            aws sagemaker describe-auto-ml-job-v2 --auto-ml-job-name "$resource_name" 2>/dev/null >/dev/null
            ;;
        "lambda-function")
            aws lambda get-function --function-name "$resource_name" 2>/dev/null >/dev/null
            ;;
        "cloudwatch-dashboard")
            aws cloudwatch get-dashboard --dashboard-name "$resource_name" 2>/dev/null >/dev/null
            ;;
        "cloudwatch-alarm")
            aws cloudwatch describe-alarms --alarm-names "$resource_name" 2>/dev/null | jq -e '.MetricAlarms | length > 0' >/dev/null
            ;;
        *)
            false
            ;;
    esac
}

# Delete SageMaker endpoint
delete_sagemaker_endpoint() {
    if [ -z "${ENDPOINT_NAME:-}" ]; then
        warning "Endpoint name not found, skipping..."
        return 0
    fi
    
    info "Deleting SageMaker endpoint: $ENDPOINT_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would delete SageMaker endpoint $ENDPOINT_NAME"
        return 0
    fi
    
    if resource_exists "sagemaker-endpoint" "$ENDPOINT_NAME"; then
        aws sagemaker delete-endpoint --endpoint-name "$ENDPOINT_NAME"
        
        # Wait for endpoint deletion
        info "Waiting for endpoint deletion..."
        while resource_exists "sagemaker-endpoint" "$ENDPOINT_NAME"; do
            sleep 30
        done
        
        success "SageMaker endpoint deleted: $ENDPOINT_NAME"
    else
        info "SageMaker endpoint $ENDPOINT_NAME does not exist"
    fi
}

# Delete SageMaker endpoint configuration
delete_sagemaker_endpoint_config() {
    if [ -z "${ENDPOINT_CONFIG_NAME:-}" ]; then
        warning "Endpoint configuration name not found, skipping..."
        return 0
    fi
    
    info "Deleting SageMaker endpoint configuration: $ENDPOINT_CONFIG_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would delete endpoint configuration $ENDPOINT_CONFIG_NAME"
        return 0
    fi
    
    if resource_exists "sagemaker-endpoint-config" "$ENDPOINT_CONFIG_NAME"; then
        aws sagemaker delete-endpoint-config \
            --endpoint-config-name "$ENDPOINT_CONFIG_NAME"
        success "SageMaker endpoint configuration deleted: $ENDPOINT_CONFIG_NAME"
    else
        info "SageMaker endpoint configuration $ENDPOINT_CONFIG_NAME does not exist"
    fi
}

# Delete SageMaker model
delete_sagemaker_model() {
    if [ -z "${MODEL_NAME:-}" ]; then
        warning "Model name not found, skipping..."
        return 0
    fi
    
    info "Deleting SageMaker model: $MODEL_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would delete SageMaker model $MODEL_NAME"
        return 0
    fi
    
    if resource_exists "sagemaker-model" "$MODEL_NAME"; then
        aws sagemaker delete-model --model-name "$MODEL_NAME"
        success "SageMaker model deleted: $MODEL_NAME"
    else
        info "SageMaker model $MODEL_NAME does not exist"
    fi
}

# Stop AutoML job if running
stop_automl_job() {
    if [ -z "${AUTOML_JOB_NAME:-}" ]; then
        warning "AutoML job name not found, skipping..."
        return 0
    fi
    
    info "Checking AutoML job status: $AUTOML_JOB_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would check and stop AutoML job $AUTOML_JOB_NAME"
        return 0
    fi
    
    if resource_exists "sagemaker-automl-job" "$AUTOML_JOB_NAME"; then
        local status=$(aws sagemaker describe-auto-ml-job-v2 \
            --auto-ml-job-name "$AUTOML_JOB_NAME" \
            --query 'AutoMLJobStatus' --output text)
        
        if [ "$status" = "InProgress" ]; then
            confirm_action "AutoML job $AUTOML_JOB_NAME is still running. Stop it?"
            
            aws sagemaker stop-auto-ml-job \
                --auto-ml-job-name "$AUTOML_JOB_NAME"
            
            info "Waiting for AutoML job to stop..."
            while [ "$(aws sagemaker describe-auto-ml-job-v2 \
                --auto-ml-job-name "$AUTOML_JOB_NAME" \
                --query 'AutoMLJobStatus' --output text)" = "Stopping" ]; do
                sleep 30
            done
            
            success "AutoML job stopped: $AUTOML_JOB_NAME"
        else
            info "AutoML job $AUTOML_JOB_NAME is not running (status: $status)"
        fi
    else
        info "AutoML job $AUTOML_JOB_NAME does not exist"
    fi
}

# Delete Lambda function
delete_lambda_function() {
    if [ -z "${LAMBDA_FUNCTION_NAME:-}" ]; then
        warning "Lambda function name not found, skipping..."
        return 0
    fi
    
    info "Deleting Lambda function: $LAMBDA_FUNCTION_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would delete Lambda function $LAMBDA_FUNCTION_NAME"
        return 0
    fi
    
    if resource_exists "lambda-function" "$LAMBDA_FUNCTION_NAME"; then
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
        success "Lambda function deleted: $LAMBDA_FUNCTION_NAME"
    else
        info "Lambda function $LAMBDA_FUNCTION_NAME does not exist"
    fi
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        warning "Random suffix not found, skipping CloudWatch cleanup..."
        return 0
    fi
    
    local dashboard_name="AutoML-Forecasting-${RANDOM_SUFFIX}"
    local alarm_name="ForecastEndpointErrors-${RANDOM_SUFFIX}"
    
    info "Deleting CloudWatch resources..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would delete CloudWatch dashboard $dashboard_name"
        info "DRY RUN: Would delete CloudWatch alarm $alarm_name"
        return 0
    fi
    
    # Delete dashboard
    if resource_exists "cloudwatch-dashboard" "$dashboard_name"; then
        aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name"
        success "CloudWatch dashboard deleted: $dashboard_name"
    else
        info "CloudWatch dashboard $dashboard_name does not exist"
    fi
    
    # Delete alarm
    if resource_exists "cloudwatch-alarm" "$alarm_name"; then
        aws cloudwatch delete-alarms --alarm-names "$alarm_name"
        success "CloudWatch alarm deleted: $alarm_name"
    else
        info "CloudWatch alarm $alarm_name does not exist"
    fi
}

# Delete IAM role
delete_iam_role() {
    if [ -z "${SAGEMAKER_ROLE_NAME:-}" ]; then
        warning "IAM role name not found, skipping..."
        return 0
    fi
    
    info "Deleting IAM role: $SAGEMAKER_ROLE_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would delete IAM role $SAGEMAKER_ROLE_NAME"
        return 0
    fi
    
    if resource_exists "iam-role" "$SAGEMAKER_ROLE_NAME"; then
        # Detach managed policies
        local policies=(
            "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
            "arn:aws:iam::aws:policy/AmazonS3FullAccess"
            "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        )
        
        for policy in "${policies[@]}"; do
            aws iam detach-role-policy \
                --role-name "$SAGEMAKER_ROLE_NAME" \
                --policy-arn "$policy" 2>/dev/null || true
        done
        
        # Delete role
        aws iam delete-role --role-name "$SAGEMAKER_ROLE_NAME"
        success "IAM role deleted: $SAGEMAKER_ROLE_NAME"
    else
        info "IAM role $SAGEMAKER_ROLE_NAME does not exist"
    fi
}

# Delete S3 bucket and contents
delete_s3_bucket() {
    if [ "$KEEP_DATA" = true ]; then
        info "Keeping S3 bucket and data as requested"
        return 0
    fi
    
    if [ -z "${FORECAST_BUCKET:-}" ]; then
        warning "S3 bucket name not found, skipping..."
        return 0
    fi
    
    info "Deleting S3 bucket and contents: $FORECAST_BUCKET"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would delete S3 bucket $FORECAST_BUCKET and all contents"
        return 0
    fi
    
    if resource_exists "s3-bucket" "$FORECAST_BUCKET"; then
        confirm_action "This will permanently delete all data in S3 bucket: $FORECAST_BUCKET"
        
        # Delete all objects and versions
        info "Removing all objects from bucket..."
        aws s3 rm "s3://$FORECAST_BUCKET" --recursive
        
        # Delete all object versions if versioning is enabled
        aws s3api list-object-versions \
            --bucket "$FORECAST_BUCKET" \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output text | while read key version_id; do
            if [ -n "$key" ] && [ -n "$version_id" ]; then
                aws s3api delete-object \
                    --bucket "$FORECAST_BUCKET" \
                    --key "$key" \
                    --version-id "$version_id" 2>/dev/null || true
            fi
        done
        
        # Delete all delete markers
        aws s3api list-object-versions \
            --bucket "$FORECAST_BUCKET" \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
            --output text | while read key version_id; do
            if [ -n "$key" ] && [ -n "$version_id" ]; then
                aws s3api delete-object \
                    --bucket "$FORECAST_BUCKET" \
                    --key "$key" \
                    --version-id "$version_id" 2>/dev/null || true
            fi
        done
        
        # Delete bucket
        aws s3 rb "s3://$FORECAST_BUCKET"
        success "S3 bucket deleted: $FORECAST_BUCKET"
    else
        info "S3 bucket $FORECAST_BUCKET does not exist"
    fi
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    local files_to_remove=(
        "$PROJECT_ROOT/ecommerce_sales_data.csv"
        "$PROJECT_ROOT/automl_train_data.csv"
        "$PROJECT_ROOT/automl_validation_data.csv"
        "$PROJECT_ROOT/automl_schema.json"
        "$PROJECT_ROOT/automl_job_config.json"
        "$PROJECT_ROOT/monitoring_dashboard.json"
        "$PROJECT_ROOT/forecast_api_lambda.py"
        "$PROJECT_ROOT/forecast_api.zip"
        "$PROJECT_ROOT/generate_training_data.py"
        "$PROJECT_ROOT/prepare_automl_data.py"
        "$PROJECT_ROOT/response.json"
        "$PROJECT_ROOT/accuracy_analysis.json"
        "$PROJECT_ROOT/automl_forecasts.json"
        "$PROJECT_ROOT/business_intelligence_report.json"
        "$PROJECT_ROOT/deployment_summary.txt"
    )
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would remove local files:"
        for file in "${files_to_remove[@]}"; do
            if [ -f "$file" ]; then
                echo "  - $file"
            fi
        done
        return 0
    fi
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            info "Removed: $file"
        fi
    done
    
    # Remove deployment state file
    if [ -f "$DEPLOYMENT_STATE_FILE" ]; then
        rm -f "$DEPLOYMENT_STATE_FILE"
        info "Removed deployment state file"
    fi
    
    success "Local files cleaned up"
}

# Parallel cleanup function
parallel_cleanup() {
    info "Running parallel cleanup (faster but less safe)..."
    
    # Define cleanup functions that can run in parallel
    local parallel_functions=(
        "delete_lambda_function"
        "delete_cloudwatch_resources"
    )
    
    # Run parallel cleanup
    for func in "${parallel_functions[@]}"; do
        $func &
    done
    
    # Wait for parallel operations to complete
    wait
    
    # Run sequential cleanup for resources with dependencies
    stop_automl_job
    delete_sagemaker_endpoint
    delete_sagemaker_endpoint_config
    delete_sagemaker_model
    delete_iam_role
    delete_s3_bucket
    cleanup_local_files
}

# Sequential cleanup function
sequential_cleanup() {
    info "Running sequential cleanup (safer)..."
    
    # Delete resources in dependency order
    stop_automl_job
    delete_sagemaker_endpoint
    delete_sagemaker_endpoint_config
    delete_sagemaker_model
    delete_lambda_function
    delete_cloudwatch_resources
    delete_iam_role
    delete_s3_bucket
    cleanup_local_files
}

# Generate cleanup report
generate_cleanup_report() {
    info "Generating cleanup report..."
    
    local report_file="$PROJECT_ROOT/cleanup_report.txt"
    
    cat > "$report_file" << EOF
=== AutoML Forecasting Solution - Cleanup Report ===

Cleanup completed at: $(date)
AWS Region: ${AWS_REGION:-"Unknown"}
AWS Account: ${AWS_ACCOUNT_ID:-"Unknown"}

Resources Processed:
- S3 Bucket: ${FORECAST_BUCKET:-"Not found"}
- IAM Role: ${SAGEMAKER_ROLE_NAME:-"Not found"}
- AutoML Job: ${AUTOML_JOB_NAME:-"Not found"}
- Lambda Function: ${LAMBDA_FUNCTION_NAME:-"Not found"}
- CloudWatch Resources: AutoML-Forecasting-${RANDOM_SUFFIX:-"Unknown"}

Cleanup Method: $([ "$PARALLEL" = true ] && echo "Parallel" || echo "Sequential")
Data Preservation: $([ "$KEEP_DATA" = true ] && echo "Data kept" || echo "Data deleted")

Notes:
- Check AWS Console to verify all resources are removed
- Monitor AWS billing for any unexpected charges
- Some resources may take time to fully terminate

Manual Verification Commands:
- aws s3 ls | grep automl-forecasting
- aws iam list-roles | grep AutoMLForecastingRole
- aws sagemaker list-auto-ml-jobs-v2 | grep retail-demand-forecast
- aws lambda list-functions | grep automl-forecast-api

EOF
    
    success "Cleanup report saved to: $report_file"
}

# Main cleanup function
main() {
    info "Starting AutoML Forecasting solution cleanup..."
    
    # Initialize log file
    echo "=== AutoML Forecasting Cleanup Log ===" > "$LOG_FILE"
    echo "Started at: $(date)" >> "$LOG_FILE"
    
    # Load deployment state
    load_deployment_state
    
    # Confirm cleanup operation
    if [ "$DRY_RUN" = false ]; then
        confirm_action "This will destroy all AutoML Forecasting resources. Continue?"
    fi
    
    # Execute cleanup
    if [ "$PARALLEL" = true ]; then
        parallel_cleanup
    else
        sequential_cleanup
    fi
    
    # Generate cleanup report
    generate_cleanup_report
    
    success "Cleanup completed successfully!"
    
    if [ "$KEEP_DATA" = true ]; then
        warning "S3 bucket and training data were preserved. Remember to delete manually if no longer needed."
    fi
    
    info "Cleanup report saved to: $PROJECT_ROOT/cleanup_report.txt"
    info "Verify all resources are removed in the AWS Console"
}

# Run main function
main "$@"