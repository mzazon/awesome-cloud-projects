#!/bin/bash
# Destroy script for Real-time Anomaly Detection with Kinesis Data Analytics
# This script safely removes all infrastructure created for the anomaly detection system
# and provides cost-saving cleanup with confirmation prompts

set -e  # Exit on any error

# Colors for output
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
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to confirm destructive actions
confirm_action() {
    local message="$1"
    local default_response="${2:-n}"
    
    if [[ "$FORCE_DESTROY" == "true" ]]; then
        log "Force mode enabled, skipping confirmation for: $message"
        return 0
    fi
    
    echo -e "${YELLOW}$message${NC}"
    read -p "Are you sure? (y/N): " -r response
    response=${response:-$default_response}
    
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            log "Skipping: $message"
            return 1
            ;;
    esac
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local check_command="$2"
    local max_wait="${3:-300}"  # Default 5 minutes
    
    log "Waiting for $resource_type deletion to complete..."
    
    local wait_time=0
    while [[ $wait_time -lt $max_wait ]]; do
        if ! eval "$check_command" &>/dev/null; then
            success "$resource_type deletion completed"
            return 0
        fi
        
        echo -n "."
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    warning "$resource_type deletion timeout after ${max_wait} seconds"
    return 1
}

log "Starting cleanup of Real-time Anomaly Detection system..."

# Check if running in force mode
if [[ "$1" == "--force" ]]; then
    export FORCE_DESTROY="true"
    warning "Running in FORCE MODE - all confirmations will be skipped"
fi

# Load environment variables from deployment
if [[ -f .env ]]; then
    log "Loading environment variables from .env file..."
    source .env
    success "Environment variables loaded"
else
    warning ".env file not found. You may need to provide resource names manually."
    
    # Prompt for required variables if not found
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION=$(aws configure get region || echo "us-east-1")
    fi
    
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    # Try to find resources by pattern if variables not set
    if [[ -z "$STREAM_NAME" ]]; then
        warning "STREAM_NAME not found in .env. Attempting to find transaction streams..."
        STREAMS=$(aws kinesis list-streams --query 'StreamNames[?starts_with(@, `transaction-stream-`)]' --output text)
        if [[ -n "$STREAMS" ]]; then
            echo "Found streams: $STREAMS"
            read -p "Enter stream name to delete: " STREAM_NAME
        fi
    fi
fi

# Prerequisites check
log "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install AWS CLI v2."
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please run 'aws configure'."
fi

success "Prerequisites check completed"

# Display resources to be deleted
log "Resources to be deleted:"
echo "==============================================="
[[ -n "$FLINK_APP_NAME" ]] && echo "Flink Application: $FLINK_APP_NAME"
[[ -n "$STREAM_NAME" ]] && echo "Kinesis Stream: $STREAM_NAME"
[[ -n "$LAMBDA_FUNCTION_NAME" ]] && echo "Lambda Function: $LAMBDA_FUNCTION_NAME"
[[ -n "$S3_BUCKET_NAME" ]] && echo "S3 Bucket: $S3_BUCKET_NAME"
[[ -n "$SNS_TOPIC_NAME" ]] && echo "SNS Topic: $SNS_TOPIC_NAME"
echo "IAM Roles: FlinkAnomalyDetectionRole, lambda-execution-role"
echo "CloudWatch Alarms: AnomalyDetectionAlarm"
echo "CloudWatch Anomaly Detector: AnomalyDetection namespace"
echo "==============================================="

if ! confirm_action "This will permanently delete all resources listed above."; then
    log "Cleanup cancelled by user"
    exit 0
fi

# Step 1: Stop and delete Flink application
if [[ -n "$FLINK_APP_NAME" ]]; then
    log "Stopping and deleting Flink application..."
    
    # Check if application exists and get its status
    APP_STATUS=$(aws kinesisanalyticsv2 describe-application \
        --application-name ${FLINK_APP_NAME} \
        --query 'ApplicationDetail.ApplicationStatus' \
        --output text --region ${AWS_REGION} 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$APP_STATUS" != "NOT_FOUND" ]]; then
        # Stop the application if it's running
        if [[ "$APP_STATUS" == "RUNNING" ]]; then
            log "Stopping Flink application..."
            aws kinesisanalyticsv2 stop-application \
                --application-name ${FLINK_APP_NAME} \
                --region ${AWS_REGION} || warning "Failed to stop Flink application"
            
            # Wait for application to stop
            wait_for_deletion "Flink application stop" \
                "aws kinesisanalyticsv2 describe-application --application-name ${FLINK_APP_NAME} --query 'ApplicationDetail.ApplicationStatus' --output text --region ${AWS_REGION} | grep -q RUNNING" \
                180
        fi
        
        # Get the create timestamp for deletion
        CREATE_TIMESTAMP=$(aws kinesisanalyticsv2 describe-application \
            --application-name ${FLINK_APP_NAME} \
            --query 'ApplicationDetail.CreateTimestamp' \
            --output text --region ${AWS_REGION} 2>/dev/null || echo "")
        
        if [[ -n "$CREATE_TIMESTAMP" ]]; then
            log "Deleting Flink application..."
            aws kinesisanalyticsv2 delete-application \
                --application-name ${FLINK_APP_NAME} \
                --create-timestamp ${CREATE_TIMESTAMP} \
                --region ${AWS_REGION} || warning "Failed to delete Flink application"
            
            success "Flink application deletion initiated"
        else
            warning "Could not retrieve application timestamp for deletion"
        fi
    else
        log "Flink application not found, skipping deletion"
    fi
else
    warning "FLINK_APP_NAME not set, skipping Flink application deletion"
fi

# Step 2: Delete CloudWatch resources
log "Deleting CloudWatch resources..."

# Delete CloudWatch alarm
aws cloudwatch delete-alarms \
    --alarm-names "AnomalyDetectionAlarm" \
    --region ${AWS_REGION} 2>/dev/null || log "CloudWatch alarm not found or already deleted"

# Delete anomaly detector
aws cloudwatch delete-anomaly-detector \
    --namespace "AnomalyDetection" \
    --metric-name "AnomalyCount" \
    --stat "Sum" \
    --dimensions Name=Source,Value=FlinkApp \
    --region ${AWS_REGION} 2>/dev/null || log "CloudWatch anomaly detector not found or already deleted"

success "CloudWatch resources deleted"

# Step 3: Delete Lambda function
if [[ -n "$LAMBDA_FUNCTION_NAME" ]]; then
    log "Deleting Lambda function..."
    
    aws lambda delete-function \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --region ${AWS_REGION} 2>/dev/null || log "Lambda function not found or already deleted"
    
    success "Lambda function deleted"
else
    warning "LAMBDA_FUNCTION_NAME not set, skipping Lambda function deletion"
fi

# Step 4: Delete Kinesis Data Stream
if [[ -n "$STREAM_NAME" ]]; then
    log "Deleting Kinesis Data Stream..."
    
    aws kinesis delete-stream \
        --stream-name ${STREAM_NAME} \
        --region ${AWS_REGION} 2>/dev/null || log "Kinesis stream not found or already deleted"
    
    # Wait for stream deletion
    wait_for_deletion "Kinesis stream" \
        "aws kinesis describe-stream --stream-name ${STREAM_NAME} --region ${AWS_REGION}" \
        300
    
    success "Kinesis Data Stream deleted"
else
    warning "STREAM_NAME not set, skipping Kinesis stream deletion"
fi

# Step 5: Delete SNS topic
if [[ -n "$SNS_TOPIC_NAME" ]] && [[ -n "$AWS_ACCOUNT_ID" ]] && [[ -n "$AWS_REGION" ]]; then
    log "Deleting SNS topic..."
    
    SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    
    aws sns delete-topic \
        --topic-arn ${SNS_TOPIC_ARN} \
        --region ${AWS_REGION} 2>/dev/null || log "SNS topic not found or already deleted"
    
    success "SNS topic deleted"
else
    warning "SNS topic information not complete, skipping SNS topic deletion"
fi

# Step 6: Delete IAM resources
log "Deleting IAM resources..."

# Delete Flink IAM role and policy
if aws iam get-role --role-name FlinkAnomalyDetectionRole &>/dev/null; then
    log "Deleting Flink IAM role..."
    
    # Delete attached policies first
    aws iam delete-role-policy \
        --role-name FlinkAnomalyDetectionRole \
        --policy-name FlinkAnomalyDetectionPolicy 2>/dev/null || log "Flink IAM policy not found"
    
    # Delete the role
    aws iam delete-role \
        --role-name FlinkAnomalyDetectionRole 2>/dev/null || warning "Failed to delete Flink IAM role"
    
    success "Flink IAM role deleted"
else
    log "Flink IAM role not found, skipping deletion"
fi

# Delete Lambda IAM role and policy
if aws iam get-role --role-name lambda-execution-role &>/dev/null; then
    log "Deleting Lambda IAM role..."
    
    # Detach managed policies
    aws iam detach-role-policy \
        --role-name lambda-execution-role \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || log "Basic execution policy not attached"
    
    # Delete inline policies
    aws iam delete-role-policy \
        --role-name lambda-execution-role \
        --policy-name LambdaAnomalyProcessorPolicy 2>/dev/null || log "Lambda IAM policy not found"
    
    # Delete the role
    aws iam delete-role \
        --role-name lambda-execution-role 2>/dev/null || warning "Failed to delete Lambda IAM role"
    
    success "Lambda IAM role deleted"
else
    log "Lambda IAM role not found, skipping deletion"
fi

# Step 7: Delete S3 bucket
if [[ -n "$S3_BUCKET_NAME" ]]; then
    if confirm_action "Delete S3 bucket ${S3_BUCKET_NAME} and all its contents?"; then
        log "Deleting S3 bucket..."
        
        # Empty the bucket first
        aws s3 rm s3://${S3_BUCKET_NAME} --recursive 2>/dev/null || log "S3 bucket already empty or not found"
        
        # Delete the bucket
        aws s3 rb s3://${S3_BUCKET_NAME} 2>/dev/null || log "S3 bucket not found or already deleted"
        
        success "S3 bucket deleted"
    else
        warning "Skipping S3 bucket deletion"
    fi
else
    warning "S3_BUCKET_NAME not set, skipping S3 bucket deletion"
fi

# Step 8: Clean up local files
log "Cleaning up local files..."

# Remove temporary files created during deployment
rm -f *.json 2>/dev/null || true
rm -f *.py 2>/dev/null || true
rm -f *.zip 2>/dev/null || true
rm -rf anomaly-detection-app 2>/dev/null || true

# Ask before removing .env file
if [[ -f .env ]]; then
    if confirm_action "Remove .env file containing deployment configuration?"; then
        rm -f .env
        success "Local .env file removed"
    else
        warning "Keeping .env file for reference"
    fi
fi

success "Local files cleaned up"

# Step 9: Verify cleanup completion
log "Verifying cleanup completion..."

CLEANUP_ERRORS=0

# Check Flink application
if [[ -n "$FLINK_APP_NAME" ]]; then
    if aws kinesisanalyticsv2 describe-application --application-name ${FLINK_APP_NAME} --region ${AWS_REGION} &>/dev/null; then
        warning "Flink application still exists: ${FLINK_APP_NAME}"
        CLEANUP_ERRORS=$((CLEANUP_ERRORS + 1))
    fi
fi

# Check Kinesis stream
if [[ -n "$STREAM_NAME" ]]; then
    if aws kinesis describe-stream --stream-name ${STREAM_NAME} --region ${AWS_REGION} &>/dev/null; then
        warning "Kinesis stream still exists: ${STREAM_NAME}"
        CLEANUP_ERRORS=$((CLEANUP_ERRORS + 1))
    fi
fi

# Check Lambda function
if [[ -n "$LAMBDA_FUNCTION_NAME" ]]; then
    if aws lambda get-function --function-name ${LAMBDA_FUNCTION_NAME} --region ${AWS_REGION} &>/dev/null; then
        warning "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
        CLEANUP_ERRORS=$((CLEANUP_ERRORS + 1))
    fi
fi

# Check IAM roles
if aws iam get-role --role-name FlinkAnomalyDetectionRole &>/dev/null; then
    warning "Flink IAM role still exists: FlinkAnomalyDetectionRole"
    CLEANUP_ERRORS=$((CLEANUP_ERRORS + 1))
fi

if aws iam get-role --role-name lambda-execution-role &>/dev/null; then
    warning "Lambda IAM role still exists: lambda-execution-role"
    CLEANUP_ERRORS=$((CLEANUP_ERRORS + 1))
fi

# Final status
echo ""
echo "=== CLEANUP SUMMARY ==="
if [[ $CLEANUP_ERRORS -eq 0 ]]; then
    success "All resources have been successfully deleted!"
    log "The Real-time Anomaly Detection system has been completely removed."
    log "No ongoing charges should occur from these resources."
else
    warning "Cleanup completed with ${CLEANUP_ERRORS} potential issues."
    log "Please check the warnings above and manually verify resource deletion."
    log "Some resources may take additional time to fully delete."
fi

echo ""
log "To verify no charges are being incurred:"
echo "1. Check AWS Cost Explorer for any remaining charges"
echo "2. Review CloudWatch metrics to ensure no active applications"
echo "3. Verify S3 buckets are empty if not deleted"
echo ""

if [[ $CLEANUP_ERRORS -eq 0 ]]; then
    success "Cleanup completed successfully!"
else
    warning "Cleanup completed with potential issues. Please review manually."
    exit 1
fi