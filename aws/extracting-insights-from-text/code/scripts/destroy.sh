#!/bin/bash

# =============================================================================
# Amazon Comprehend NLP Solution - Cleanup Script
# =============================================================================
# This script removes all resources created by the deployment script
# including S3 buckets, Lambda functions, IAM roles, and EventBridge rules.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Deploy script must have been run successfully
# - deploy-config.env file must exist in the same directory
#
# Usage: ./destroy.sh [--force]
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
FORCE_MODE=${1:-""}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Check if configuration file exists
check_config() {
    if [[ ! -f "${SCRIPT_DIR}/deploy-config.env" ]]; then
        log_error "Configuration file not found: ${SCRIPT_DIR}/deploy-config.env"
        log_error "Please ensure the deploy script has been run successfully."
        exit 1
    fi
    
    # Load configuration
    source "${SCRIPT_DIR}/deploy-config.env"
    
    log "Configuration loaded successfully"
    log_info "  AWS_REGION: ${AWS_REGION}"
    log_info "  COMPREHEND_BUCKET: ${COMPREHEND_BUCKET}"
    log_info "  LAMBDA_FUNCTION_NAME: ${LAMBDA_FUNCTION_NAME}"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE_MODE" == "--force" ]]; then
        log_warning "Running in FORCE mode - skipping confirmation"
        return 0
    fi
    
    echo ""
    log_warning "This will permanently delete the following resources:"
    log_info "  - S3 buckets: ${COMPREHEND_BUCKET}, ${COMPREHEND_BUCKET}-output"
    log_info "  - Lambda function: ${LAMBDA_FUNCTION_NAME}"
    log_info "  - EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
    log_info "  - IAM roles: ${COMPREHEND_ROLE}, ${LAMBDA_ROLE}"
    log_info "  - All Comprehend batch jobs"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Stop running Comprehend jobs
stop_comprehend_jobs() {
    log "Stopping running Comprehend jobs..."
    
    # Stop sentiment analysis job if exists
    if [[ -n "${SENTIMENT_JOB_ID:-}" ]]; then
        log_info "Stopping sentiment analysis job: ${SENTIMENT_JOB_ID}"
        aws comprehend stop-sentiment-detection-job \
            --job-id "${SENTIMENT_JOB_ID}" 2>/dev/null || {
            log_warning "Could not stop sentiment job ${SENTIMENT_JOB_ID} (may already be stopped)"
        }
    fi
    
    # Stop entity detection job if exists
    if [[ -n "${ENTITIES_JOB_ID:-}" ]]; then
        log_info "Stopping entity detection job: ${ENTITIES_JOB_ID}"
        aws comprehend stop-entities-detection-job \
            --job-id "${ENTITIES_JOB_ID}" 2>/dev/null || {
            log_warning "Could not stop entity job ${ENTITIES_JOB_ID} (may already be stopped)"
        }
    fi
    
    # Stop topic modeling job if exists
    if [[ -n "${TOPICS_JOB_ID:-}" ]]; then
        log_info "Stopping topic modeling job: ${TOPICS_JOB_ID}"
        aws comprehend stop-topics-detection-job \
            --job-id "${TOPICS_JOB_ID}" 2>/dev/null || {
            log_warning "Could not stop topic job ${TOPICS_JOB_ID} (may already be stopped)"
        }
    fi
    
    log "Comprehend jobs stop commands issued"
}

# Delete EventBridge rule and targets
delete_eventbridge_rule() {
    log "Deleting EventBridge rule..."
    
    # Check if rule exists
    if aws events describe-rule --name "${EVENTBRIDGE_RULE_NAME}" &>/dev/null; then
        # Remove targets first
        log_info "Removing targets from EventBridge rule"
        aws events remove-targets \
            --rule "${EVENTBRIDGE_RULE_NAME}" \
            --ids "1" 2>/dev/null || {
            log_warning "Could not remove targets from EventBridge rule"
        }
        
        # Delete the rule
        log_info "Deleting EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
        aws events delete-rule \
            --name "${EVENTBRIDGE_RULE_NAME}" || {
            log_warning "Could not delete EventBridge rule ${EVENTBRIDGE_RULE_NAME}"
        }
    else
        log_info "EventBridge rule ${EVENTBRIDGE_RULE_NAME} not found"
    fi
    
    log "EventBridge rule deletion completed"
}

# Delete Lambda function
delete_lambda_function() {
    log "Deleting Lambda function..."
    
    # Check if function exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
        # Remove Lambda permissions first
        log_info "Removing Lambda permissions"
        aws lambda remove-permission \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --statement-id "eventbridge-invoke-${RANDOM_SUFFIX:-}" 2>/dev/null || {
            log_warning "Could not remove Lambda permissions"
        }
        
        # Delete the function
        log_info "Deleting Lambda function: ${LAMBDA_FUNCTION_NAME}"
        aws lambda delete-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" || {
            log_error "Could not delete Lambda function ${LAMBDA_FUNCTION_NAME}"
        }
    else
        log_info "Lambda function ${LAMBDA_FUNCTION_NAME} not found"
    fi
    
    log "Lambda function deletion completed"
}

# Delete S3 buckets and contents
delete_s3_resources() {
    log "Deleting S3 buckets and contents..."
    
    # Delete input bucket
    if aws s3 ls "s3://${COMPREHEND_BUCKET}" &>/dev/null; then
        log_info "Deleting contents of input bucket: ${COMPREHEND_BUCKET}"
        aws s3 rm "s3://${COMPREHEND_BUCKET}" --recursive || {
            log_warning "Could not delete all contents from ${COMPREHEND_BUCKET}"
        }
        
        log_info "Deleting input bucket: ${COMPREHEND_BUCKET}"
        aws s3 rb "s3://${COMPREHEND_BUCKET}" || {
            log_warning "Could not delete bucket ${COMPREHEND_BUCKET}"
        }
    else
        log_info "Input bucket ${COMPREHEND_BUCKET} not found"
    fi
    
    # Delete output bucket
    if aws s3 ls "s3://${COMPREHEND_BUCKET}-output" &>/dev/null; then
        log_info "Deleting contents of output bucket: ${COMPREHEND_BUCKET}-output"
        aws s3 rm "s3://${COMPREHEND_BUCKET}-output" --recursive || {
            log_warning "Could not delete all contents from ${COMPREHEND_BUCKET}-output"
        }
        
        log_info "Deleting output bucket: ${COMPREHEND_BUCKET}-output"
        aws s3 rb "s3://${COMPREHEND_BUCKET}-output" || {
            log_warning "Could not delete bucket ${COMPREHEND_BUCKET}-output"
        }
    else
        log_info "Output bucket ${COMPREHEND_BUCKET}-output not found"
    fi
    
    log "S3 resources deletion completed"
}

# Delete IAM roles
delete_iam_roles() {
    log "Deleting IAM roles..."
    
    # Delete Lambda role
    if aws iam get-role --role-name "${LAMBDA_ROLE}" &>/dev/null; then
        log_info "Detaching policies from Lambda role: ${LAMBDA_ROLE}"
        
        # Detach policies
        aws iam detach-role-policy \
            --role-name "${LAMBDA_ROLE}" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || {
            log_warning "Could not detach AWSLambdaBasicExecutionRole policy"
        }
        
        aws iam detach-role-policy \
            --role-name "${LAMBDA_ROLE}" \
            --policy-arn "arn:aws:iam::aws:policy/ComprehendReadOnlyAccess" 2>/dev/null || {
            log_warning "Could not detach ComprehendReadOnlyAccess policy"
        }
        
        # Delete the role
        log_info "Deleting Lambda role: ${LAMBDA_ROLE}"
        aws iam delete-role --role-name "${LAMBDA_ROLE}" || {
            log_warning "Could not delete Lambda role ${LAMBDA_ROLE}"
        }
    else
        log_info "Lambda role ${LAMBDA_ROLE} not found"
    fi
    
    # Delete Comprehend role
    if aws iam get-role --role-name "${COMPREHEND_ROLE}" &>/dev/null; then
        log_info "Detaching policies from Comprehend role: ${COMPREHEND_ROLE}"
        
        # Detach policies
        aws iam detach-role-policy \
            --role-name "${COMPREHEND_ROLE}" \
            --policy-arn "arn:aws:iam::aws:policy/ComprehendFullAccess" 2>/dev/null || {
            log_warning "Could not detach ComprehendFullAccess policy"
        }
        
        aws iam detach-role-policy \
            --role-name "${COMPREHEND_ROLE}" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonS3FullAccess" 2>/dev/null || {
            log_warning "Could not detach AmazonS3FullAccess policy"
        }
        
        # Delete the role
        log_info "Deleting Comprehend role: ${COMPREHEND_ROLE}"
        aws iam delete-role --role-name "${COMPREHEND_ROLE}" || {
            log_warning "Could not delete Comprehend role ${COMPREHEND_ROLE}"
        }
    else
        log_info "Comprehend role ${COMPREHEND_ROLE} not found"
    fi
    
    log "IAM roles deletion completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary directory if it exists
    if [[ -n "${TEMP_DIR:-}" ]] && [[ -d "${TEMP_DIR}" ]]; then
        log_info "Removing temporary directory: ${TEMP_DIR}"
        rm -rf "${TEMP_DIR}" || {
            log_warning "Could not remove temporary directory ${TEMP_DIR}"
        }
    fi
    
    # Remove configuration file
    if [[ -f "${SCRIPT_DIR}/deploy-config.env" ]]; then
        log_info "Removing configuration file"
        rm -f "${SCRIPT_DIR}/deploy-config.env" || {
            log_warning "Could not remove configuration file"
        }
    fi
    
    log "Local files cleanup completed"
}

# Verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local cleanup_successful=true
    
    # Check S3 buckets
    if aws s3 ls "s3://${COMPREHEND_BUCKET}" &>/dev/null; then
        log_warning "Input bucket ${COMPREHEND_BUCKET} still exists"
        cleanup_successful=false
    fi
    
    if aws s3 ls "s3://${COMPREHEND_BUCKET}-output" &>/dev/null; then
        log_warning "Output bucket ${COMPREHEND_BUCKET}-output still exists"
        cleanup_successful=false
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} still exists"
        cleanup_successful=false
    fi
    
    # Check EventBridge rule
    if aws events describe-rule --name "${EVENTBRIDGE_RULE_NAME}" &>/dev/null; then
        log_warning "EventBridge rule ${EVENTBRIDGE_RULE_NAME} still exists"
        cleanup_successful=false
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name "${LAMBDA_ROLE}" &>/dev/null; then
        log_warning "Lambda role ${LAMBDA_ROLE} still exists"
        cleanup_successful=false
    fi
    
    if aws iam get-role --role-name "${COMPREHEND_ROLE}" &>/dev/null; then
        log_warning "Comprehend role ${COMPREHEND_ROLE} still exists"
        cleanup_successful=false
    fi
    
    if [[ "$cleanup_successful" == true ]]; then
        log "Cleanup verification passed - all resources removed"
    else
        log_warning "Some resources may still exist - check warnings above"
    fi
}

# Main cleanup function
main() {
    log "Starting Amazon Comprehend NLP Solution cleanup..."
    
    check_config
    confirm_deletion
    stop_comprehend_jobs
    delete_eventbridge_rule
    delete_lambda_function
    delete_s3_resources
    delete_iam_roles
    cleanup_local_files
    verify_cleanup
    
    log "Cleanup completed successfully!"
    log ""
    log "===== CLEANUP SUMMARY ====="
    log "All resources have been removed from AWS Region: ${AWS_REGION}"
    log "Log file: ${LOG_FILE}"
    log ""
    log "Note: Some Comprehend jobs may take additional time to fully stop."
    log "Check the AWS Console if you need to verify complete cleanup."
    log ""
    log "Thank you for using the Amazon Comprehend NLP Solution!"
}

# Run main function
main "$@"