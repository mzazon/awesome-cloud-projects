#!/bin/bash

# Amazon Fraud Detector Cleanup Script
# This script removes all resources created by the fraud detection system deployment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI configuration
check_aws_config() {
    log "Checking AWS CLI configuration..."
    
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Get AWS account info
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not configured. Run 'aws configure' to set region."
        exit 1
    fi
    
    success "AWS CLI configured - Account: $AWS_ACCOUNT_ID, Region: $AWS_REGION"
}

# Function to load deployment configuration
load_deployment_config() {
    log "Loading deployment configuration..."
    
    if [ -f "./fraud-detector-deployment.json" ]; then
        # Load resource names from deployment file
        export FRAUD_BUCKET=$(jq -r '.resources.s3_bucket' ./fraud-detector-deployment.json)
        export EVENT_TYPE_NAME=$(jq -r '.resources.event_type_name' ./fraud-detector-deployment.json)
        export ENTITY_TYPE_NAME=$(jq -r '.resources.entity_type_name' ./fraud-detector-deployment.json)
        export MODEL_NAME=$(jq -r '.resources.model_name' ./fraud-detector-deployment.json)
        export DETECTOR_NAME=$(jq -r '.resources.detector_name' ./fraud-detector-deployment.json)
        export LAMBDA_FUNCTION_NAME=$(jq -r '.resources.lambda_function_name' ./fraud-detector-deployment.json)
        export IAM_ROLE_NAME=$(jq -r '.resources.iam_role_name' ./fraud-detector-deployment.json)
        
        success "Loaded configuration from deployment file"
    elif [ "$FORCE_CLEANUP" = "true" ]; then
        warning "No deployment file found, but force cleanup enabled"
        warning "Will attempt to find and remove resources by pattern"
        return 0
    else
        error "No deployment file (fraud-detector-deployment.json) found"
        error "Cannot proceed without knowing which resources to delete"
        echo
        echo "Options:"
        echo "1. Run this script from the same directory as deploy.sh"
        echo "2. Use --force to attempt cleanup by resource pattern"
        echo "3. Manually provide resource names via environment variables"
        exit 1
    fi
}

# Function to prompt for confirmation
confirm_deletion() {
    if [ "$FORCE_CLEANUP" = "true" ]; then
        warning "Force cleanup enabled - skipping confirmation prompts"
        return 0
    fi
    
    echo
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo
    if [ -n "${FRAUD_BUCKET:-}" ]; then
        echo "  • S3 Bucket: ${FRAUD_BUCKET}"
    fi
    if [ -n "${EVENT_TYPE_NAME:-}" ]; then
        echo "  • Event Type: ${EVENT_TYPE_NAME}"
    fi
    if [ -n "${ENTITY_TYPE_NAME:-}" ]; then
        echo "  • Entity Type: ${ENTITY_TYPE_NAME}"
    fi
    if [ -n "${MODEL_NAME:-}" ]; then
        echo "  • ML Model: ${MODEL_NAME}"
    fi
    if [ -n "${DETECTOR_NAME:-}" ]; then
        echo "  • Detector: ${DETECTOR_NAME}"
    fi
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        echo "  • Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    fi
    if [ -n "${IAM_ROLE_NAME:-}" ]; then
        echo "  • IAM Role: ${IAM_ROLE_NAME}"
    fi
    echo "  • All associated rules and outcomes"
    echo "  • All training data and models"
    echo
    echo "This action cannot be undone!"
    echo
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource cleanup..."
}

# Function to deactivate and delete detector
delete_detector() {
    if [ -z "${DETECTOR_NAME:-}" ]; then
        warning "No detector name provided, skipping detector cleanup"
        return 0
    fi
    
    log "Deactivating and deleting detector: ${DETECTOR_NAME}"
    
    # Check if detector exists
    if ! aws frauddetector describe-detector --detector-id "$DETECTOR_NAME" >/dev/null 2>&1; then
        warning "Detector ${DETECTOR_NAME} not found"
        return 0
    fi
    
    # Get detector versions
    local versions=$(aws frauddetector describe-detector \
        --detector-id "$DETECTOR_NAME" \
        --query 'detectorVersionSummaries[].detectorVersionId' \
        --output text 2>/dev/null || echo "")
    
    # Deactivate and delete each version
    for version in $versions; do
        if [ -n "$version" ] && [ "$version" != "None" ]; then
            log "Processing detector version: ${version}"
            
            # Get current status
            local status=$(aws frauddetector describe-detector \
                --detector-id "$DETECTOR_NAME" \
                --query "detectorVersionSummaries[?detectorVersionId=='${version}'].status" \
                --output text 2>/dev/null || echo "")
            
            # Deactivate if active
            if [ "$status" = "ACTIVE" ]; then
                log "Deactivating detector version ${version}..."
                aws frauddetector update-detector-version-status \
                    --detector-id "$DETECTOR_NAME" \
                    --detector-version-id "$version" \
                    --status INACTIVE
                
                # Wait for deactivation
                sleep 5
            fi
            
            # Delete version
            log "Deleting detector version ${version}..."
            aws frauddetector delete-detector-version \
                --detector-id "$DETECTOR_NAME" \
                --detector-version-id "$version" \
                2>/dev/null || warning "Failed to delete detector version ${version}"
        fi
    done
    
    # Delete the detector itself
    log "Deleting detector: ${DETECTOR_NAME}"
    aws frauddetector delete-detector \
        --detector-id "$DETECTOR_NAME" \
        2>/dev/null || warning "Failed to delete detector ${DETECTOR_NAME}"
    
    success "Detector cleanup completed"
}

# Function to delete rules
delete_rules() {
    if [ -z "${DETECTOR_NAME:-}" ]; then
        warning "No detector name provided, skipping rules cleanup"
        return 0
    fi
    
    log "Deleting fraud detection rules..."
    
    local rules=("high_risk_rule" "obvious_fraud_rule" "low_risk_rule")
    
    for rule in "${rules[@]}"; do
        if aws frauddetector describe-rule \
            --detector-id "$DETECTOR_NAME" \
            --rule-id "$rule" \
            --rule-version "1" >/dev/null 2>&1; then
            
            log "Deleting rule: ${rule}"
            aws frauddetector delete-rule \
                --detector-id "$DETECTOR_NAME" \
                --rule-id "$rule" \
                2>/dev/null || warning "Failed to delete rule ${rule}"
        else
            warning "Rule ${rule} not found"
        fi
    done
    
    success "Rules cleanup completed"
}

# Function to delete outcomes
delete_outcomes() {
    log "Deleting outcomes..."
    
    local outcomes=("review" "block" "approve")
    
    for outcome in "${outcomes[@]}"; do
        if aws frauddetector describe-outcome --name "$outcome" >/dev/null 2>&1; then
            log "Deleting outcome: ${outcome}"
            aws frauddetector delete-outcome --name "$outcome" \
                2>/dev/null || warning "Failed to delete outcome ${outcome}"
        else
            warning "Outcome ${outcome} not found"
        fi
    done
    
    success "Outcomes cleanup completed"
}

# Function to delete model
delete_model() {
    if [ -z "${MODEL_NAME:-}" ]; then
        warning "No model name provided, skipping model cleanup"
        return 0
    fi
    
    log "Deleting ML model: ${MODEL_NAME}"
    
    # Check if model exists
    if ! aws frauddetector describe-model-versions \
        --model-id "$MODEL_NAME" \
        --model-type ONLINE_FRAUD_INSIGHTS >/dev/null 2>&1; then
        warning "Model ${MODEL_NAME} not found"
        return 0
    fi
    
    # Delete model version
    log "Deleting model version 1.0..."
    aws frauddetector delete-model-version \
        --model-id "$MODEL_NAME" \
        --model-type ONLINE_FRAUD_INSIGHTS \
        --model-version-number 1.0 \
        2>/dev/null || warning "Failed to delete model version"
    
    # Delete model
    log "Deleting model: ${MODEL_NAME}"
    aws frauddetector delete-model \
        --model-id "$MODEL_NAME" \
        --model-type ONLINE_FRAUD_INSIGHTS \
        2>/dev/null || warning "Failed to delete model ${MODEL_NAME}"
    
    success "Model cleanup completed"
}

# Function to delete event and entity types
delete_types() {
    log "Deleting event and entity types..."
    
    # Delete event type
    if [ -n "${EVENT_TYPE_NAME:-}" ]; then
        if aws frauddetector describe-event-type --name "$EVENT_TYPE_NAME" >/dev/null 2>&1; then
            log "Deleting event type: ${EVENT_TYPE_NAME}"
            aws frauddetector delete-event-type --name "$EVENT_TYPE_NAME" \
                2>/dev/null || warning "Failed to delete event type ${EVENT_TYPE_NAME}"
        else
            warning "Event type ${EVENT_TYPE_NAME} not found"
        fi
    fi
    
    # Delete entity type
    if [ -n "${ENTITY_TYPE_NAME:-}" ]; then
        if aws frauddetector describe-entity-type --name "$ENTITY_TYPE_NAME" >/dev/null 2>&1; then
            log "Deleting entity type: ${ENTITY_TYPE_NAME}"
            aws frauddetector delete-entity-type --name "$ENTITY_TYPE_NAME" \
                2>/dev/null || warning "Failed to delete entity type ${ENTITY_TYPE_NAME}"
        else
            warning "Entity type ${ENTITY_TYPE_NAME} not found"
        fi
    fi
    
    success "Types cleanup completed"
}

# Function to delete labels
delete_labels() {
    log "Deleting labels..."
    
    local labels=("fraud" "legit")
    
    for label in "${labels[@]}"; do
        if aws frauddetector describe-label --name "$label" >/dev/null 2>&1; then
            log "Deleting label: ${label}"
            aws frauddetector delete-label --name "$label" \
                2>/dev/null || warning "Failed to delete label ${label}"
        else
            warning "Label ${label} not found"
        fi
    done
    
    success "Labels cleanup completed"
}

# Function to delete Lambda function
delete_lambda_function() {
    if [ -z "${LAMBDA_FUNCTION_NAME:-}" ]; then
        warning "No Lambda function name provided, skipping Lambda cleanup"
        return 0
    fi
    
    log "Deleting Lambda function: ${LAMBDA_FUNCTION_NAME}"
    
    # Check if function exists
    if ! aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
        warning "Lambda function ${LAMBDA_FUNCTION_NAME} not found"
        return 0
    fi
    
    # Delete function
    aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
    
    success "Lambda function deleted: ${LAMBDA_FUNCTION_NAME}"
}

# Function to delete S3 bucket
delete_s3_bucket() {
    if [ -z "${FRAUD_BUCKET:-}" ]; then
        warning "No S3 bucket name provided, skipping S3 cleanup"
        return 0
    fi
    
    log "Deleting S3 bucket: ${FRAUD_BUCKET}"
    
    # Check if bucket exists
    if ! aws s3 ls "s3://${FRAUD_BUCKET}" >/dev/null 2>&1; then
        warning "S3 bucket ${FRAUD_BUCKET} not found"
        return 0
    fi
    
    # Remove all objects from bucket (including versions)
    log "Removing all objects from bucket..."
    aws s3 rm "s3://${FRAUD_BUCKET}" --recursive
    
    # Remove all versions if versioning is enabled
    aws s3api list-object-versions \
        --bucket "$FRAUD_BUCKET" \
        --query 'Versions[].{Key:Key,VersionId:VersionId}' \
        --output text | while read key version_id; do
        if [ -n "$key" ] && [ -n "$version_id" ] && [ "$version_id" != "null" ]; then
            aws s3api delete-object \
                --bucket "$FRAUD_BUCKET" \
                --key "$key" \
                --version-id "$version_id" >/dev/null 2>&1
        fi
    done
    
    # Remove all delete markers
    aws s3api list-object-versions \
        --bucket "$FRAUD_BUCKET" \
        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
        --output text | while read key version_id; do
        if [ -n "$key" ] && [ -n "$version_id" ] && [ "$version_id" != "null" ]; then
            aws s3api delete-object \
                --bucket "$FRAUD_BUCKET" \
                --key "$key" \
                --version-id "$version_id" >/dev/null 2>&1
        fi
    done
    
    # Delete bucket
    aws s3 rb "s3://${FRAUD_BUCKET}"
    
    success "S3 bucket deleted: ${FRAUD_BUCKET}"
}

# Function to delete IAM role
delete_iam_role() {
    if [ -z "${IAM_ROLE_NAME:-}" ]; then
        warning "No IAM role name provided, skipping IAM cleanup"
        return 0
    fi
    
    log "Deleting IAM role: ${IAM_ROLE_NAME}"
    
    # Check if role exists
    if ! aws iam get-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
        warning "IAM role ${IAM_ROLE_NAME} not found"
        return 0
    fi
    
    # Detach policies
    log "Detaching policies from role..."
    aws iam detach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonFraudDetectorFullAccessPolicy \
        2>/dev/null || warning "Failed to detach Fraud Detector policy"
    
    # Delete role
    aws iam delete-role --role-name "$IAM_ROLE_NAME"
    
    success "IAM role deleted: ${IAM_ROLE_NAME}"
}

# Function to delete Lambda execution role if created
delete_lambda_execution_role() {
    log "Checking for Lambda execution role..."
    
    # Only delete if we created it (check if it has minimal policies)
    if aws iam get-role --role-name lambda-execution-role >/dev/null 2>&1; then
        local policies=$(aws iam list-attached-role-policies \
            --role-name lambda-execution-role \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text)
        
        # Check if it has our specific policies
        if echo "$policies" | grep -q "AmazonFraudDetectorFullAccessPolicy" && \
           echo "$policies" | grep -q "AWSLambdaBasicExecutionRole"; then
            
            log "Deleting Lambda execution role (created by this deployment)..."
            
            # Detach policies
            aws iam detach-role-policy \
                --role-name lambda-execution-role \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
                2>/dev/null || true
            
            aws iam detach-role-policy \
                --role-name lambda-execution-role \
                --policy-arn arn:aws:iam::aws:policy/AmazonFraudDetectorFullAccessPolicy \
                2>/dev/null || true
            
            # Delete role
            aws iam delete-role --role-name lambda-execution-role
            
            success "Lambda execution role deleted"
        else
            warning "Lambda execution role exists but wasn't created by this deployment"
        fi
    else
        log "Lambda execution role not found"
    fi
}

# Function to search and delete resources by pattern (force cleanup)
force_cleanup_by_pattern() {
    warning "Performing force cleanup - searching for resources by pattern..."
    
    # Search for detectors with pattern
    log "Searching for detectors with 'payment_fraud' pattern..."
    local detectors=$(aws frauddetector list-detectors \
        --query 'detectors[?contains(detectorId, `payment_fraud`)].detectorId' \
        --output text 2>/dev/null || echo "")
    
    for detector in $detectors; do
        if [ -n "$detector" ] && [ "$detector" != "None" ]; then
            warning "Found detector: ${detector}"
            export DETECTOR_NAME="$detector"
            delete_detector
        fi
    done
    
    # Search for models with pattern
    log "Searching for models with 'fraud_detection_model' pattern..."
    local models=$(aws frauddetector list-models \
        --model-type ONLINE_FRAUD_INSIGHTS \
        --query 'models[?contains(modelId, `fraud_detection_model`)].modelId' \
        --output text 2>/dev/null || echo "")
    
    for model in $models; do
        if [ -n "$model" ] && [ "$model" != "None" ]; then
            warning "Found model: ${model}"
            export MODEL_NAME="$model"
            delete_model
        fi
    done
    
    # Search for S3 buckets with pattern
    log "Searching for S3 buckets with 'fraud-detection-data' pattern..."
    local buckets=$(aws s3 ls | grep fraud-detection-data | awk '{print $3}' || echo "")
    
    for bucket in $buckets; do
        if [ -n "$bucket" ]; then
            warning "Found bucket: ${bucket}"
            export FRAUD_BUCKET="$bucket"
            delete_s3_bucket
        fi
    done
    
    # Search for Lambda functions with pattern
    log "Searching for Lambda functions with 'fraud-prediction-processor' pattern..."
    local functions=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `fraud-prediction-processor`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    for function in $functions; do
        if [ -n "$function" ] && [ "$function" != "None" ]; then
            warning "Found function: ${function}"
            export LAMBDA_FUNCTION_NAME="$function"
            delete_lambda_function
        fi
    done
    
    # Clean up common resources
    delete_outcomes
    delete_labels
    
    warning "Force cleanup completed - some resources may remain if they don't match patterns"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "./fraud-detector-deployment.json"
        "/tmp/fraud-detector-trust-policy.json"
        "/tmp/lambda-trust-policy.json"
        "/tmp/training-data.csv"
        "/tmp/fraud-processor.py"
        "/tmp/fraud-processor.zip"
        "/tmp/fraud-detector-deployment.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "Removed: ${file}"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to display cleanup summary
display_summary() {
    echo
    echo "================================================"
    echo "🧹 FRAUD DETECTION SYSTEM CLEANUP COMPLETE!"
    echo "================================================"
    echo
    echo "✅ Completed cleanup operations:"
    echo "  • Deactivated and deleted fraud detector"
    echo "  • Deleted ML models and training data"
    echo "  • Removed detection rules and outcomes"
    echo "  • Deleted event and entity types"
    echo "  • Removed Lambda function"
    echo "  • Deleted S3 bucket and contents"
    echo "  • Removed IAM roles and policies"
    echo "  • Cleaned up local files"
    echo
    echo "💡 Notes:"
    echo "  • All billable resources have been removed"
    echo "  • No ongoing charges should occur"
    echo "  • Some IAM policies may have a brief delay before full removal"
    echo
    echo "🔍 Verification:"
    echo "  • Check AWS console to confirm resource removal"
    echo "  • Monitor AWS billing for charge cessation"
    echo
    echo "================================================"
}

# Main execution function
main() {
    log "Starting Amazon Fraud Detector cleanup..."
    
    # Pre-cleanup checks
    check_aws_config
    
    # Load configuration or perform force cleanup
    if [ "$FORCE_CLEANUP" = "true" ]; then
        warning "Force cleanup mode enabled"
        confirm_deletion
        force_cleanup_by_pattern
    else
        load_deployment_config
        confirm_deletion
        
        # Execute cleanup in reverse order of creation
        delete_detector
        delete_rules
        delete_outcomes
        delete_model
        delete_types
        delete_labels
        delete_lambda_function
        delete_s3_bucket
        delete_iam_role
        delete_lambda_execution_role
    fi
    
    # Clean up local files
    cleanup_local_files
    
    # Display summary
    display_summary
    
    success "Cleanup completed successfully!"
}

# Parse command line arguments
FORCE_CLEANUP=false

# Check for help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Amazon Fraud Detector Cleanup Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --help, -h     Show this help message"
    echo "  --force        Force cleanup without deployment file (searches by pattern)"
    echo "  --yes          Skip confirmation prompts"
    echo
    echo "Environment Variables:"
    echo "  FORCE_CLEANUP  Set to 'true' to enable force cleanup mode"
    echo
    echo "Examples:"
    echo "  $0                    # Normal cleanup using deployment file"
    echo "  $0 --force            # Force cleanup by searching for resources"
    echo "  $0 --yes              # Skip confirmation prompts"
    echo "  $0 --force --yes      # Force cleanup without prompts"
    echo
    echo "Notes:"
    echo "  • Normal mode requires fraud-detector-deployment.json file"
    echo "  • Force mode searches for resources by naming patterns"
    echo "  • Always verify resource deletion in AWS console"
    exit 0
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_CLEANUP=true
            shift
            ;;
        --yes)
            export FORCE_CLEANUP=true  # Skip confirmations
            shift
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check for jq if not in force mode
if [ "$FORCE_CLEANUP" != "true" ] && ! command_exists jq; then
    error "jq is required to parse deployment configuration"
    error "Install jq or use --force flag to cleanup by pattern"
    exit 1
fi

# Run main function
main "$@"