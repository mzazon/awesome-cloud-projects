#!/bin/bash

# Destroy script for Custom Entity Recognition and Classification with Comprehend
# This script safely removes all infrastructure created by the deploy script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Logging function
log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$TIMESTAMP] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log_warning() {
    echo "[$TIMESTAMP] WARNING: $1" | tee -a "$LOG_FILE"
}

# Check if environment file exists
check_environment() {
    if [ ! -f "${SCRIPT_DIR}/.env" ]; then
        log_error "Environment file .env not found. Cannot proceed with cleanup."
        log_error "This may indicate the deployment was not completed or environment was manually deleted."
        exit 1
    fi
    
    # Load environment variables
    source "${SCRIPT_DIR}/.env"
    
    log "Loaded environment variables:"
    log "  Project Name: ${PROJECT_NAME:-'Not set'}"
    log "  S3 Bucket: ${BUCKET_NAME:-'Not set'}"
    log "  IAM Role: ${ROLE_NAME:-'Not set'}"
    log "  AWS Region: ${AWS_REGION:-'Not set'}"
}

# Confirmation prompt
confirm_destruction() {
    echo ""
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo "   - Amazon Comprehend custom models (entity recognizer and document classifier)"
    echo "   - Step Functions state machine and executions"
    echo "   - Lambda functions (4 functions)"
    echo "   - S3 bucket and all training data: ${BUCKET_NAME}"
    echo "   - IAM role and attached policies: ${ROLE_NAME}"
    echo "   - Local training data and temporary files"
    echo ""
    echo "💰 Note: This will stop any ongoing model training (which may have incurred costs)"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    log "User confirmed destruction. Proceeding with cleanup..."
}

# Check AWS credentials and permissions
check_aws_access() {
    log "Checking AWS access..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or expired."
        exit 1
    fi
    
    CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    if [ "$CURRENT_ACCOUNT" != "$AWS_ACCOUNT_ID" ]; then
        log_error "AWS account mismatch. Expected: $AWS_ACCOUNT_ID, Current: $CURRENT_ACCOUNT"
        exit 1
    fi
    
    log "✅ AWS access verified"
}

# Stop and delete Comprehend models
delete_comprehend_models() {
    log "Deleting Amazon Comprehend custom models..."
    
    # Find and delete entity recognizers
    log "Looking for entity recognizers..."
    ENTITY_RECOGNIZERS=$(aws comprehend list-entity-recognizers \
        --filter "RecognizerName contains ${PROJECT_NAME}" \
        --query 'EntityRecognizerPropertiesList[].EntityRecognizerArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$ENTITY_RECOGNIZERS" ]; then
        for arn in $ENTITY_RECOGNIZERS; do
            log "Processing entity recognizer: $arn"
            
            # Get current status
            STATUS=$(aws comprehend describe-entity-recognizer \
                --entity-recognizer-arn "$arn" \
                --query 'EntityRecognizerProperties.Status' \
                --output text 2>/dev/null || echo "NOT_FOUND")
            
            if [ "$STATUS" = "NOT_FOUND" ]; then
                log "Entity recognizer already deleted: $arn"
                continue
            fi
            
            log "Entity recognizer status: $STATUS"
            
            # Stop if training or trained
            if [ "$STATUS" = "TRAINING" ] || [ "$STATUS" = "TRAINED" ]; then
                log "Stopping entity recognizer: $arn"
                aws comprehend stop-entity-recognizer \
                    --entity-recognizer-arn "$arn" 2>/dev/null || true
                
                # Wait for it to stop
                log "Waiting for entity recognizer to stop..."
                sleep 30
            fi
            
            # Delete the recognizer
            log "Deleting entity recognizer: $arn"
            aws comprehend delete-entity-recognizer \
                --entity-recognizer-arn "$arn" 2>/dev/null || log_warning "Failed to delete entity recognizer: $arn"
        done
    else
        log "No entity recognizers found for project: $PROJECT_NAME"
    fi
    
    # Find and delete document classifiers
    log "Looking for document classifiers..."
    CLASSIFIERS=$(aws comprehend list-document-classifiers \
        --filter "DocumentClassifierName contains ${PROJECT_NAME}" \
        --query 'DocumentClassifierPropertiesList[].DocumentClassifierArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$CLASSIFIERS" ]; then
        for arn in $CLASSIFIERS; do
            log "Processing document classifier: $arn"
            
            # Get current status
            STATUS=$(aws comprehend describe-document-classifier \
                --document-classifier-arn "$arn" \
                --query 'DocumentClassifierProperties.Status' \
                --output text 2>/dev/null || echo "NOT_FOUND")
            
            if [ "$STATUS" = "NOT_FOUND" ]; then
                log "Document classifier already deleted: $arn"
                continue
            fi
            
            log "Document classifier status: $STATUS"
            
            # Stop if training or trained
            if [ "$STATUS" = "TRAINING" ] || [ "$STATUS" = "TRAINED" ]; then
                log "Stopping document classifier: $arn"
                aws comprehend stop-document-classifier \
                    --document-classifier-arn "$arn" 2>/dev/null || true
                
                # Wait for it to stop
                log "Waiting for document classifier to stop..."
                sleep 30
            fi
            
            # Delete the classifier
            log "Deleting document classifier: $arn"
            aws comprehend delete-document-classifier \
                --document-classifier-arn "$arn" 2>/dev/null || log_warning "Failed to delete document classifier: $arn"
        done
    else
        log "No document classifiers found for project: $PROJECT_NAME"
    fi
    
    log "✅ Comprehend models cleanup completed"
}

# Delete Step Functions state machine
delete_step_functions() {
    log "Deleting Step Functions state machine..."
    
    if [ -n "${STATE_MACHINE_ARN:-}" ]; then
        # Stop any running executions first
        log "Checking for running executions..."
        RUNNING_EXECUTIONS=$(aws stepfunctions list-executions \
            --state-machine-arn "$STATE_MACHINE_ARN" \
            --status-filter RUNNING \
            --query 'executions[].executionArn' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$RUNNING_EXECUTIONS" ]; then
            for execution_arn in $RUNNING_EXECUTIONS; do
                log "Stopping execution: $execution_arn"
                aws stepfunctions stop-execution \
                    --execution-arn "$execution_arn" 2>/dev/null || true
            done
            
            # Wait a moment for executions to stop
            sleep 10
        fi
        
        # Delete the state machine
        log "Deleting state machine: $STATE_MACHINE_ARN"
        aws stepfunctions delete-state-machine \
            --state-machine-arn "$STATE_MACHINE_ARN" 2>/dev/null || log_warning "Failed to delete state machine"
    else
        # Try to find state machine by name
        STATE_MACHINE_NAME="${PROJECT_NAME}-training-pipeline"
        STATE_MACHINE_ARN="arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}"
        
        if aws stepfunctions describe-state-machine --state-machine-arn "$STATE_MACHINE_ARN" &>/dev/null; then
            log "Found state machine by name, deleting: $STATE_MACHINE_ARN"
            aws stepfunctions delete-state-machine \
                --state-machine-arn "$STATE_MACHINE_ARN" 2>/dev/null || log_warning "Failed to delete state machine"
        else
            log "No Step Functions state machine found for project: $PROJECT_NAME"
        fi
    fi
    
    log "✅ Step Functions cleanup completed"
}

# Delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    FUNCTION_NAMES=(
        "${PROJECT_NAME}-data-preprocessor"
        "${PROJECT_NAME}-model-trainer"
        "${PROJECT_NAME}-status-checker"
        "${PROJECT_NAME}-inference-api"
    )
    
    for func_name in "${FUNCTION_NAMES[@]}"; do
        log "Deleting Lambda function: $func_name"
        
        if aws lambda get-function --function-name "$func_name" &>/dev/null; then
            aws lambda delete-function --function-name "$func_name" 2>/dev/null || log_warning "Failed to delete function: $func_name"
            log "Deleted Lambda function: $func_name"
        else
            log "Lambda function not found: $func_name"
        fi
    done
    
    log "✅ Lambda functions cleanup completed"
}

# Delete S3 bucket and contents
delete_s3_bucket() {
    log "Deleting S3 bucket and contents..."
    
    if aws s3 ls "s3://${BUCKET_NAME}" &>/dev/null; then
        log "Emptying S3 bucket: $BUCKET_NAME"
        
        # Delete all objects including versions
        aws s3api delete-objects --bucket "$BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' \
                --output json 2>/dev/null || echo '{"Objects": []}')" 2>/dev/null || true
        
        # Delete delete markers
        aws s3api delete-objects --bucket "$BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' \
                --output json 2>/dev/null || echo '{"Objects": []}')" 2>/dev/null || true
        
        # Delete the bucket
        log "Deleting S3 bucket: $BUCKET_NAME"
        aws s3 rb "s3://${BUCKET_NAME}" --force 2>/dev/null || log_warning "Failed to delete S3 bucket: $BUCKET_NAME"
        
        log "✅ S3 bucket deleted: $BUCKET_NAME"
    else
        log "S3 bucket not found: $BUCKET_NAME"
    fi
}

# Delete IAM role and policies
delete_iam_role() {
    log "Deleting IAM role and policies..."
    
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        log "Detaching policies from role: $ROLE_NAME"
        
        # List and detach all attached policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$ROLE_NAME" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$ATTACHED_POLICIES" ]; then
            for policy_arn in $ATTACHED_POLICIES; do
                log "Detaching policy: $policy_arn"
                aws iam detach-role-policy \
                    --role-name "$ROLE_NAME" \
                    --policy-arn "$policy_arn" 2>/dev/null || log_warning "Failed to detach policy: $policy_arn"
            done
        fi
        
        # Delete inline policies if any
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "$ROLE_NAME" \
            --query 'PolicyNames' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$INLINE_POLICIES" ]; then
            for policy_name in $INLINE_POLICIES; do
                log "Deleting inline policy: $policy_name"
                aws iam delete-role-policy \
                    --role-name "$ROLE_NAME" \
                    --policy-name "$policy_name" 2>/dev/null || log_warning "Failed to delete inline policy: $policy_name"
            done
        fi
        
        # Delete the role
        log "Deleting IAM role: $ROLE_NAME"
        aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null || log_warning "Failed to delete IAM role: $ROLE_NAME"
        
        log "✅ IAM role deleted: $ROLE_NAME"
    else
        log "IAM role not found: $ROLE_NAME"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files created during deployment
    FILES_TO_DELETE=(
        "${SCRIPT_DIR}/trust-policy.json"
        "${SCRIPT_DIR}/training_workflow.json"
        "${SCRIPT_DIR}/data_preprocessor.py"
        "${SCRIPT_DIR}/model_trainer.py"
        "${SCRIPT_DIR}/status_checker.py"
        "${SCRIPT_DIR}/inference_api.py"
        "${SCRIPT_DIR}/.env"
    )
    
    for file in "${FILES_TO_DELETE[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "Deleted file: $file"
        fi
    done
    
    # Remove training data directory
    if [ -d "${SCRIPT_DIR}/training-data" ]; then
        rm -rf "${SCRIPT_DIR}/training-data"
        log "Deleted directory: ${SCRIPT_DIR}/training-data"
    fi
    
    log "✅ Local files cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    CLEANUP_ISSUES=0
    
    # Check S3 bucket
    if aws s3 ls "s3://${BUCKET_NAME}" &>/dev/null; then
        log_warning "S3 bucket still exists: $BUCKET_NAME"
        ((CLEANUP_ISSUES++))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        log_warning "IAM role still exists: $ROLE_NAME"
        ((CLEANUP_ISSUES++))
    fi
    
    # Check Lambda functions
    for func_name in "${PROJECT_NAME}-data-preprocessor" "${PROJECT_NAME}-model-trainer" "${PROJECT_NAME}-status-checker" "${PROJECT_NAME}-inference-api"; do
        if aws lambda get-function --function-name "$func_name" &>/dev/null; then
            log_warning "Lambda function still exists: $func_name"
            ((CLEANUP_ISSUES++))
        fi
    done
    
    if [ $CLEANUP_ISSUES -eq 0 ]; then
        log "✅ Cleanup verification passed - all resources successfully removed"
    else
        log_warning "⚠️  Cleanup verification found $CLEANUP_ISSUES remaining resources"
        log_warning "You may need to manually remove these resources or re-run the cleanup script"
    fi
}

# Main cleanup function
main() {
    log "Starting cleanup of Custom Entity Recognition and Classification with Comprehend"
    log "================================================================================"
    
    check_environment
    confirm_destruction
    check_aws_access
    
    log "Beginning resource cleanup..."
    
    # Delete resources in reverse order of creation
    delete_comprehend_models
    delete_step_functions
    delete_lambda_functions
    delete_s3_bucket
    delete_iam_role
    cleanup_local_files
    
    verify_cleanup
    
    log "================================================================================"
    log "✅ Cleanup completed!"
    log ""
    log "All infrastructure for project '$PROJECT_NAME' has been removed."
    log "Logs saved to: $LOG_FILE"
    log ""
    log "💰 Note: Check your AWS billing dashboard to ensure no unexpected charges remain."
    log "    Comprehend model training charges may still appear for recently stopped jobs."
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi