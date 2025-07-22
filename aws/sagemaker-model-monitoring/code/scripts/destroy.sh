#!/bin/bash

# Destroy script for Model Monitoring and Drift Detection with SageMaker Model Monitor
# This script safely removes all resources created by the deploy script

set -euo pipefail

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

# Confirmation prompt
confirm_destruction() {
    echo -e "${RED}⚠️  WARNING: This will permanently delete all Model Monitor resources!${NC}"
    echo
    echo "Resources to be deleted:"
    echo "- SageMaker monitoring schedules and endpoints"
    echo "- S3 bucket and all data"
    echo "- Lambda functions and IAM roles"
    echo "- CloudWatch alarms and dashboards"
    echo "- SNS topics and subscriptions"
    echo
    
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        warning "Force destroy mode enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirm
    if [[ "$confirm" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
}

# Load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Try to load from saved environment file
    if [[ -f "/tmp/model-monitor-env.sh" ]]; then
        source /tmp/model-monitor-env.sh
        success "Loaded environment from /tmp/model-monitor-env.sh"
    else
        # If no saved environment, try to discover resources
        warning "No saved environment found, attempting to discover resources..."
        
        export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        if [[ -z "$AWS_REGION" ]]; then
            export AWS_REGION="us-east-1"
            warning "AWS region not set, defaulting to us-east-1"
        fi
        
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Prompt for resource suffix if not provided
        if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
            read -p "Enter the resource suffix used during deployment: " RANDOM_SUFFIX
            if [[ -z "$RANDOM_SUFFIX" ]]; then
                error "Resource suffix is required for cleanup"
                exit 1
            fi
        fi
        
        # Set resource names based on suffix
        export MODEL_MONITOR_ROLE_NAME="ModelMonitorRole-${RANDOM_SUFFIX}"
        export MODEL_MONITOR_BUCKET="model-monitor-${RANDOM_SUFFIX}"
        export MONITORING_SCHEDULE_NAME="model-monitor-schedule-${RANDOM_SUFFIX}"
        export BASELINE_JOB_NAME="model-monitor-baseline-${RANDOM_SUFFIX}"
        export SNS_TOPIC_NAME="model-monitor-alerts-${RANDOM_SUFFIX}"
        export LAMBDA_FUNCTION_NAME="model-monitor-handler-${RANDOM_SUFFIX}"
        export MODEL_NAME="demo-model-${RANDOM_SUFFIX}"
        export ENDPOINT_CONFIG_NAME="demo-endpoint-config-${RANDOM_SUFFIX}"
        export ENDPOINT_NAME="demo-endpoint-${RANDOM_SUFFIX}"
        export LAMBDA_ROLE_NAME="ModelMonitorLambdaRole-${RANDOM_SUFFIX}"
        export MODEL_QUALITY_SCHEDULE_NAME="model-quality-schedule-${RANDOM_SUFFIX}"
        export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    fi
    
    log "Using AWS Region: $AWS_REGION"
    log "Using resource suffix: $RANDOM_SUFFIX"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Stop and delete monitoring schedules
delete_monitoring_schedules() {
    log "Deleting monitoring schedules..."
    
    # Stop and delete data quality monitoring schedule
    if aws sagemaker describe-monitoring-schedule --monitoring-schedule-name "$MONITORING_SCHEDULE_NAME" &>/dev/null; then
        log "Stopping monitoring schedule: $MONITORING_SCHEDULE_NAME"
        aws sagemaker stop-monitoring-schedule \
            --monitoring-schedule-name "$MONITORING_SCHEDULE_NAME" || true
        
        # Wait for schedule to stop
        local max_attempts=30
        local attempt=1
        while [[ $attempt -le $max_attempts ]]; do
            local status=$(aws sagemaker describe-monitoring-schedule \
                --monitoring-schedule-name "$MONITORING_SCHEDULE_NAME" \
                --query 'MonitoringScheduleStatus' --output text 2>/dev/null || echo "NotFound")
            
            if [[ "$status" == "Stopped" || "$status" == "NotFound" ]]; then
                break
            fi
            
            log "Waiting for monitoring schedule to stop... (attempt $attempt/$max_attempts)"
            sleep 10
            ((attempt++))
        done
        
        aws sagemaker delete-monitoring-schedule \
            --monitoring-schedule-name "$MONITORING_SCHEDULE_NAME" || true
        
        success "Deleted monitoring schedule: $MONITORING_SCHEDULE_NAME"
    else
        log "Monitoring schedule $MONITORING_SCHEDULE_NAME not found, skipping"
    fi
    
    # Stop and delete model quality monitoring schedule
    if aws sagemaker describe-monitoring-schedule --monitoring-schedule-name "$MODEL_QUALITY_SCHEDULE_NAME" &>/dev/null; then
        log "Stopping model quality schedule: $MODEL_QUALITY_SCHEDULE_NAME"
        aws sagemaker stop-monitoring-schedule \
            --monitoring-schedule-name "$MODEL_QUALITY_SCHEDULE_NAME" || true
        
        # Wait for schedule to stop
        local max_attempts=30
        local attempt=1
        while [[ $attempt -le $max_attempts ]]; do
            local status=$(aws sagemaker describe-monitoring-schedule \
                --monitoring-schedule-name "$MODEL_QUALITY_SCHEDULE_NAME" \
                --query 'MonitoringScheduleStatus' --output text 2>/dev/null || echo "NotFound")
            
            if [[ "$status" == "Stopped" || "$status" == "NotFound" ]]; then
                break
            fi
            
            log "Waiting for model quality schedule to stop... (attempt $attempt/$max_attempts)"
            sleep 10
            ((attempt++))
        done
        
        aws sagemaker delete-monitoring-schedule \
            --monitoring-schedule-name "$MODEL_QUALITY_SCHEDULE_NAME" || true
        
        success "Deleted model quality schedule: $MODEL_QUALITY_SCHEDULE_NAME"
    else
        log "Model quality schedule $MODEL_QUALITY_SCHEDULE_NAME not found, skipping"
    fi
}

# Delete SageMaker resources
delete_sagemaker_resources() {
    log "Deleting SageMaker resources..."
    
    # Delete endpoint
    if aws sagemaker describe-endpoint --endpoint-name "$ENDPOINT_NAME" &>/dev/null; then
        log "Deleting endpoint: $ENDPOINT_NAME"
        aws sagemaker delete-endpoint --endpoint-name "$ENDPOINT_NAME" || true
        
        # Wait for endpoint deletion
        log "Waiting for endpoint deletion to complete..."
        local max_attempts=60
        local attempt=1
        while [[ $attempt -le $max_attempts ]]; do
            if ! aws sagemaker describe-endpoint --endpoint-name "$ENDPOINT_NAME" &>/dev/null; then
                break
            fi
            log "Waiting for endpoint deletion... (attempt $attempt/$max_attempts)"
            sleep 10
            ((attempt++))
        done
        
        success "Deleted endpoint: $ENDPOINT_NAME"
    else
        log "Endpoint $ENDPOINT_NAME not found, skipping"
    fi
    
    # Delete endpoint configuration
    if aws sagemaker describe-endpoint-config --endpoint-config-name "$ENDPOINT_CONFIG_NAME" &>/dev/null; then
        log "Deleting endpoint configuration: $ENDPOINT_CONFIG_NAME"
        aws sagemaker delete-endpoint-config \
            --endpoint-config-name "$ENDPOINT_CONFIG_NAME" || true
        success "Deleted endpoint configuration: $ENDPOINT_CONFIG_NAME"
    else
        log "Endpoint configuration $ENDPOINT_CONFIG_NAME not found, skipping"
    fi
    
    # Delete model
    if aws sagemaker describe-model --model-name "$MODEL_NAME" &>/dev/null; then
        log "Deleting model: $MODEL_NAME"
        aws sagemaker delete-model --model-name "$MODEL_NAME" || true
        success "Deleted model: $MODEL_NAME"
    else
        log "Model $MODEL_NAME not found, skipping"
    fi
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete CloudWatch alarms
    local alarms=(
        "ModelMonitor-ConstraintViolations-${RANDOM_SUFFIX}"
        "ModelMonitor-JobFailures-${RANDOM_SUFFIX}"
    )
    
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --query 'MetricAlarms[0]' --output text &>/dev/null; then
            log "Deleting CloudWatch alarm: $alarm"
            aws cloudwatch delete-alarms --alarm-names "$alarm" || true
            success "Deleted CloudWatch alarm: $alarm"
        else
            log "CloudWatch alarm $alarm not found, skipping"
        fi
    done
    
    # Delete CloudWatch dashboard
    local dashboard_name="ModelMonitor-Dashboard-${RANDOM_SUFFIX}"
    if aws cloudwatch get-dashboard --dashboard-name "$dashboard_name" &>/dev/null; then
        log "Deleting CloudWatch dashboard: $dashboard_name"
        aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name" || true
        success "Deleted CloudWatch dashboard: $dashboard_name"
    else
        log "CloudWatch dashboard $dashboard_name not found, skipping"
    fi
}

# Delete Lambda function and related resources
delete_lambda_resources() {
    log "Deleting Lambda function and related resources..."
    
    # Remove Lambda permission for SNS
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log "Removing Lambda permissions"
        aws lambda remove-permission \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --statement-id sns-invoke &>/dev/null || true
    fi
    
    # Delete Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log "Deleting Lambda function: $LAMBDA_FUNCTION_NAME"
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME" || true
        success "Deleted Lambda function: $LAMBDA_FUNCTION_NAME"
    else
        log "Lambda function $LAMBDA_FUNCTION_NAME not found, skipping"
    fi
    
    # Delete Lambda IAM role
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
        log "Deleting Lambda IAM role: $LAMBDA_ROLE_NAME"
        
        # Delete attached policies
        aws iam delete-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-name ModelMonitorLambdaPolicy &>/dev/null || true
        
        aws iam detach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole &>/dev/null || true
        
        aws iam delete-role --role-name "$LAMBDA_ROLE_NAME" || true
        success "Deleted Lambda IAM role: $LAMBDA_ROLE_NAME"
    else
        log "Lambda IAM role $LAMBDA_ROLE_NAME not found, skipping"
    fi
}

# Delete SNS topic and subscriptions
delete_sns_resources() {
    log "Deleting SNS resources..."
    
    if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &>/dev/null; then
        # List and delete all subscriptions
        local subscriptions=$(aws sns list-subscriptions-by-topic \
            --topic-arn "$SNS_TOPIC_ARN" \
            --query 'Subscriptions[].SubscriptionArn' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$subscriptions" ]]; then
            for subscription in $subscriptions; do
                if [[ "$subscription" != "PendingConfirmation" && "$subscription" != "None" ]]; then
                    log "Deleting SNS subscription: $subscription"
                    aws sns unsubscribe --subscription-arn "$subscription" || true
                fi
            done
        fi
        
        # Delete SNS topic
        log "Deleting SNS topic: $SNS_TOPIC_ARN"
        aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" || true
        success "Deleted SNS topic: $SNS_TOPIC_ARN"
    else
        log "SNS topic $SNS_TOPIC_ARN not found, skipping"
    fi
}

# Delete Model Monitor IAM role
delete_model_monitor_iam_role() {
    log "Deleting Model Monitor IAM role..."
    
    if aws iam get-role --role-name "$MODEL_MONITOR_ROLE_NAME" &>/dev/null; then
        log "Deleting Model Monitor IAM role: $MODEL_MONITOR_ROLE_NAME"
        
        # Delete attached policies
        aws iam delete-role-policy \
            --role-name "$MODEL_MONITOR_ROLE_NAME" \
            --policy-name ModelMonitorCustomPolicy &>/dev/null || true
        
        aws iam detach-role-policy \
            --role-name "$MODEL_MONITOR_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/AmazonSageMakerFullAccess &>/dev/null || true
        
        aws iam delete-role --role-name "$MODEL_MONITOR_ROLE_NAME" || true
        success "Deleted Model Monitor IAM role: $MODEL_MONITOR_ROLE_NAME"
    else
        log "Model Monitor IAM role $MODEL_MONITOR_ROLE_NAME not found, skipping"
    fi
}

# Delete S3 bucket and contents
delete_s3_resources() {
    log "Deleting S3 resources..."
    
    if aws s3api head-bucket --bucket "$MODEL_MONITOR_BUCKET" &>/dev/null; then
        log "Deleting S3 bucket contents: $MODEL_MONITOR_BUCKET"
        
        # Delete all objects and versions
        aws s3 rm "s3://${MODEL_MONITOR_BUCKET}" --recursive || true
        
        # Delete all object versions if versioning is enabled
        aws s3api delete-objects \
            --bucket "$MODEL_MONITOR_BUCKET" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$MODEL_MONITOR_BUCKET" \
                --output json \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" &>/dev/null || true
        
        # Delete delete markers
        aws s3api delete-objects \
            --bucket "$MODEL_MONITOR_BUCKET" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$MODEL_MONITOR_BUCKET" \
                --output json \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" &>/dev/null || true
        
        # Delete the bucket
        log "Deleting S3 bucket: $MODEL_MONITOR_BUCKET"
        aws s3 rb "s3://${MODEL_MONITOR_BUCKET}" --force || true
        success "Deleted S3 bucket: $MODEL_MONITOR_BUCKET"
    else
        log "S3 bucket $MODEL_MONITOR_BUCKET not found, skipping"
    fi
}

# Clean up processing jobs (if any are still running)
cleanup_processing_jobs() {
    log "Checking for running processing jobs..."
    
    # Stop baseline job if still running
    if aws sagemaker describe-processing-job --processing-job-name "$BASELINE_JOB_NAME" &>/dev/null; then
        local job_status=$(aws sagemaker describe-processing-job \
            --processing-job-name "$BASELINE_JOB_NAME" \
            --query 'ProcessingJobStatus' --output text)
        
        if [[ "$job_status" == "InProgress" ]]; then
            log "Stopping processing job: $BASELINE_JOB_NAME"
            aws sagemaker stop-processing-job \
                --processing-job-name "$BASELINE_JOB_NAME" || true
            success "Stopped processing job: $BASELINE_JOB_NAME"
        fi
    fi
    
    # List any other running monitoring jobs and warn about them
    local running_jobs=$(aws sagemaker list-processing-jobs \
        --status-equals InProgress \
        --name-contains "$RANDOM_SUFFIX" \
        --query 'ProcessingJobSummaries[].ProcessingJobName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$running_jobs" ]]; then
        warning "Found running processing jobs that may be related:"
        for job in $running_jobs; do
            warning "- $job"
        done
        warning "These jobs will continue running and incur costs until they complete or are manually stopped."
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove temporary files
    rm -f /tmp/model-monitor-*.json /tmp/lambda-*.json /tmp/lambda-*.py /tmp/lambda-*.zip
    rm -f /tmp/baseline-data.csv /tmp/sample-requests.json /tmp/anomalous-requests.json
    rm -f /tmp/*response*.json /tmp/dashboard-config.json
    rm -rf /tmp/model-artifacts
    
    # Remove environment file
    rm -f /tmp/model-monitor-env.sh
    
    success "Temporary files cleaned up"
}

# Verify destruction
verify_destruction() {
    log "Verifying resource destruction..."
    
    local failed_resources=()
    
    # Check SageMaker resources
    if aws sagemaker describe-endpoint --endpoint-name "$ENDPOINT_NAME" &>/dev/null; then
        failed_resources+=("SageMaker Endpoint: $ENDPOINT_NAME")
    fi
    
    if aws sagemaker describe-monitoring-schedule --monitoring-schedule-name "$MONITORING_SCHEDULE_NAME" &>/dev/null; then
        failed_resources+=("Monitoring Schedule: $MONITORING_SCHEDULE_NAME")
    fi
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "$MODEL_MONITOR_BUCKET" &>/dev/null; then
        failed_resources+=("S3 Bucket: $MODEL_MONITOR_BUCKET")
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        failed_resources+=("Lambda Function: $LAMBDA_FUNCTION_NAME")
    fi
    
    # Check SNS topic
    if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &>/dev/null; then
        failed_resources+=("SNS Topic: $SNS_TOPIC_ARN")
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name "$MODEL_MONITOR_ROLE_NAME" &>/dev/null; then
        failed_resources+=("IAM Role: $MODEL_MONITOR_ROLE_NAME")
    fi
    
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
        failed_resources+=("IAM Role: $LAMBDA_ROLE_NAME")
    fi
    
    if [[ ${#failed_resources[@]} -eq 0 ]]; then
        success "All resources successfully destroyed!"
    else
        warning "Some resources may still exist:"
        for resource in "${failed_resources[@]}"; do
            warning "- $resource"
        done
        warning "You may need to manually delete these resources."
    fi
}

# Main destruction function
main() {
    log "Starting Model Monitor resource destruction..."
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    # Destruction steps (order matters!)
    delete_monitoring_schedules
    delete_cloudwatch_resources
    cleanup_processing_jobs
    delete_sagemaker_resources
    delete_lambda_resources
    delete_sns_resources
    delete_model_monitor_iam_role
    delete_s3_resources
    cleanup_temp_files
    
    verify_destruction
    
    success "Model Monitor destruction completed!"
    
    log "Destruction Summary:"
    log "- Monitoring schedules stopped and deleted"
    log "- SageMaker endpoint and model removed"
    log "- Lambda function and IAM roles deleted"
    log "- CloudWatch alarms and dashboard removed"
    log "- SNS topic and subscriptions deleted"
    log "- S3 bucket and all contents removed"
    
    warning "Note: CloudWatch logs may be retained according to their retention settings."
    warning "Check your AWS bill to ensure all resources have been properly terminated."
}

# Handle script arguments
case "${1:-}" in
    --force)
        export FORCE_DESTROY="true"
        main
        ;;
    --help|-h)
        echo "Usage: $0 [--force] [--help]"
        echo
        echo "Options:"
        echo "  --force    Skip confirmation prompt and force destruction"
        echo "  --help     Show this help message"
        echo
        echo "Environment Variables:"
        echo "  RANDOM_SUFFIX    Resource suffix used during deployment"
        echo "  AWS_REGION       AWS region (defaults to configured region)"
        echo "  FORCE_DESTROY    Set to 'true' to skip confirmation"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac