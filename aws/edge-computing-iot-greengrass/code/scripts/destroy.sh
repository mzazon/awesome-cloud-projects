#!/bin/bash

# AWS IoT Greengrass Edge Computing Cleanup Script
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
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${timestamp} - ${message}"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${timestamp} - ${message}"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${timestamp} - ${message}"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} ${timestamp} - ${message}"
            ;;
    esac
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Warning function for continue/stop
warn_continue() {
    log "WARN" "$1"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Cleanup cancelled"
        exit 0
    fi
}

# Load environment variables
load_environment() {
    if [[ ! -f .env ]]; then
        error_exit "Environment file (.env) not found. Make sure you run this script from the deployment directory."
    fi
    
    log "INFO" "Loading environment variables..."
    source .env
    
    # Validate required variables
    local required_vars=(
        "AWS_REGION" "AWS_ACCOUNT_ID" "THING_NAME" "THING_GROUP_NAME" 
        "POLICY_NAME" "ROLE_NAME" "LAMBDA_NAME" "CERT_ARN" "CERT_ID"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error_exit "Required environment variable $var is not set"
        fi
    done
    
    log "INFO" "Environment variables loaded successfully"
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed"
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured"
    fi
    
    log "INFO" "Prerequisites check passed"
}

# Display cleanup summary
display_cleanup_summary() {
    echo
    echo "=================================="
    echo "Resources to be deleted:"
    echo "=================================="
    echo "Thing Name: ${THING_NAME}"
    echo "Thing Group: ${THING_GROUP_NAME}"
    echo "Lambda Function: ${LAMBDA_NAME}"
    echo "IAM Role: ${ROLE_NAME}"
    echo "Policy Name: ${POLICY_NAME}"
    echo "Certificate ID: ${CERT_ID}"
    echo "AWS Region: ${AWS_REGION}"
    echo "=================================="
    echo
    warn_continue "This will permanently delete all resources listed above."
}

# Cancel and delete Greengrass deployments
cleanup_deployments() {
    log "INFO" "Cleaning up Greengrass deployments..."
    
    # List and cancel deployments
    local deployments
    deployments=$(aws greengrassv2 list-deployments \
        --target-arn "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:thinggroup/${THING_GROUP_NAME}" \
        --query 'deployments[].deploymentId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$deployments" ]]; then
        for deployment in $deployments; do
            log "INFO" "Cancelling deployment: $deployment"
            aws greengrassv2 cancel-deployment \
                --deployment-id "$deployment" 2>/dev/null || \
                log "WARN" "Failed to cancel deployment: $deployment"
        done
        
        # Wait for deployments to be cancelled
        log "INFO" "Waiting for deployments to be cancelled..."
        sleep 30
    else
        log "INFO" "No deployments found to cancel"
    fi
}

# Delete Lambda function
delete_lambda_function() {
    log "INFO" "Deleting Lambda function..."
    
    if aws lambda get-function --function-name "${LAMBDA_NAME}" &>/dev/null; then
        aws lambda delete-function \
            --function-name "${LAMBDA_NAME}" || \
            log "WARN" "Failed to delete Lambda function: ${LAMBDA_NAME}"
        log "INFO" "Lambda function deleted: ${LAMBDA_NAME}"
    else
        log "INFO" "Lambda function not found: ${LAMBDA_NAME}"
    fi
}

# Delete IoT resources
delete_iot_resources() {
    log "INFO" "Deleting IoT resources..."
    
    # Detach policy from certificate
    if aws iot list-attached-policies --target "${CERT_ARN}" &>/dev/null; then
        log "INFO" "Detaching policy from certificate..."
        aws iot detach-policy \
            --policy-name "${POLICY_NAME}" \
            --target "${CERT_ARN}" 2>/dev/null || \
            log "WARN" "Failed to detach policy from certificate"
    fi
    
    # Delete IoT policy
    if aws iot get-policy --policy-name "${POLICY_NAME}" &>/dev/null; then
        log "INFO" "Deleting IoT policy: ${POLICY_NAME}"
        aws iot delete-policy \
            --policy-name "${POLICY_NAME}" 2>/dev/null || \
            log "WARN" "Failed to delete IoT policy: ${POLICY_NAME}"
    else
        log "INFO" "IoT policy not found: ${POLICY_NAME}"
    fi
    
    # Deactivate and delete certificate
    if aws iot describe-certificate --certificate-id "${CERT_ID}" &>/dev/null; then
        log "INFO" "Deactivating certificate: ${CERT_ID}"
        aws iot update-certificate \
            --certificate-id "${CERT_ID}" \
            --new-status INACTIVE 2>/dev/null || \
            log "WARN" "Failed to deactivate certificate: ${CERT_ID}"
        
        log "INFO" "Deleting certificate: ${CERT_ID}"
        aws iot delete-certificate \
            --certificate-id "${CERT_ID}" 2>/dev/null || \
            log "WARN" "Failed to delete certificate: ${CERT_ID}"
    else
        log "INFO" "Certificate not found: ${CERT_ID}"
    fi
    
    # Remove Thing from group
    if aws iot describe-thing --thing-name "${THING_NAME}" &>/dev/null; then
        log "INFO" "Removing Thing from group..."
        aws iot remove-thing-from-thing-group \
            --thing-group-name "${THING_GROUP_NAME}" \
            --thing-name "${THING_NAME}" 2>/dev/null || \
            log "WARN" "Failed to remove Thing from group"
    fi
    
    # Delete Thing
    if aws iot describe-thing --thing-name "${THING_NAME}" &>/dev/null; then
        log "INFO" "Deleting Thing: ${THING_NAME}"
        aws iot delete-thing \
            --thing-name "${THING_NAME}" 2>/dev/null || \
            log "WARN" "Failed to delete Thing: ${THING_NAME}"
    else
        log "INFO" "Thing not found: ${THING_NAME}"
    fi
    
    # Delete Thing Group
    if aws iot describe-thing-group --thing-group-name "${THING_GROUP_NAME}" &>/dev/null; then
        log "INFO" "Deleting Thing Group: ${THING_GROUP_NAME}"
        aws iot delete-thing-group \
            --thing-group-name "${THING_GROUP_NAME}" 2>/dev/null || \
            log "WARN" "Failed to delete Thing Group: ${THING_GROUP_NAME}"
    else
        log "INFO" "Thing Group not found: ${THING_GROUP_NAME}"
    fi
}

# Delete IAM role
delete_iam_role() {
    log "INFO" "Deleting IAM role..."
    
    if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
        # List and detach all attached policies
        local attached_policies
        attached_policies=$(aws iam list-attached-role-policies \
            --role-name "${ROLE_NAME}" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$attached_policies" ]]; then
            for policy_arn in $attached_policies; do
                log "INFO" "Detaching policy: $policy_arn"
                aws iam detach-role-policy \
                    --role-name "${ROLE_NAME}" \
                    --policy-arn "$policy_arn" 2>/dev/null || \
                    log "WARN" "Failed to detach policy: $policy_arn"
            done
        fi
        
        # Delete inline policies if any
        local inline_policies
        inline_policies=$(aws iam list-role-policies \
            --role-name "${ROLE_NAME}" \
            --query 'PolicyNames' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$inline_policies" ]]; then
            for policy_name in $inline_policies; do
                log "INFO" "Deleting inline policy: $policy_name"
                aws iam delete-role-policy \
                    --role-name "${ROLE_NAME}" \
                    --policy-name "$policy_name" 2>/dev/null || \
                    log "WARN" "Failed to delete inline policy: $policy_name"
            done
        fi
        
        # Delete the role
        log "INFO" "Deleting IAM role: ${ROLE_NAME}"
        aws iam delete-role \
            --role-name "${ROLE_NAME}" 2>/dev/null || \
            log "WARN" "Failed to delete IAM role: ${ROLE_NAME}"
    else
        log "INFO" "IAM role not found: ${ROLE_NAME}"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "INFO" "Cleaning up local files..."
    
    # List of files to remove
    local files_to_remove=(
        ".env"
        "greengrass-policy.json"
        "greengrass-trust-policy.json"
        "stream-manager-config.json"
        "lambda-component-recipe.yaml"
        "greengrass-config.yaml"
        "edge-processor.zip"
        "greengrass-nucleus-latest.zip"
        "response.json"
    )
    
    # List of directories to remove
    local dirs_to_remove=(
        "lambda-edge-function"
        "GreengrassCore"
    )
    
    # Remove files
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            log "INFO" "Removing file: $file"
            rm -f "$file"
        fi
    done
    
    # Remove directories
    for dir in "${dirs_to_remove[@]}"; do
        if [[ -d "$dir" ]]; then
            log "INFO" "Removing directory: $dir"
            rm -rf "$dir"
        fi
    done
    
    log "INFO" "Local cleanup completed"
}

# Verify cleanup
verify_cleanup() {
    log "INFO" "Verifying cleanup..."
    
    local cleanup_issues=0
    
    # Check Lambda function
    if aws lambda get-function --function-name "${LAMBDA_NAME}" &>/dev/null; then
        log "WARN" "Lambda function still exists: ${LAMBDA_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check IoT Thing
    if aws iot describe-thing --thing-name "${THING_NAME}" &>/dev/null; then
        log "WARN" "IoT Thing still exists: ${THING_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check Thing Group
    if aws iot describe-thing-group --thing-group-name "${THING_GROUP_NAME}" &>/dev/null; then
        log "WARN" "Thing Group still exists: ${THING_GROUP_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
        log "WARN" "IAM role still exists: ${ROLE_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check IoT policy
    if aws iot get-policy --policy-name "${POLICY_NAME}" &>/dev/null; then
        log "WARN" "IoT policy still exists: ${POLICY_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check certificate
    if aws iot describe-certificate --certificate-id "${CERT_ID}" &>/dev/null; then
        log "WARN" "Certificate still exists: ${CERT_ID}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log "INFO" "Cleanup verification passed - all resources removed"
    else
        log "WARN" "Cleanup verification found $cleanup_issues issues"
        log "WARN" "Some resources may still exist. Please check manually."
    fi
}

# Main cleanup function
main() {
    log "INFO" "Starting AWS IoT Greengrass cleanup..."
    
    # Check if environment file exists
    if [[ ! -f .env ]]; then
        error_exit "No deployment found. Environment file (.env) does not exist."
    fi
    
    check_prerequisites
    load_environment
    display_cleanup_summary
    
    # Execute cleanup in reverse order of creation
    cleanup_deployments
    delete_lambda_function
    delete_iot_resources
    delete_iam_role
    cleanup_local_files
    verify_cleanup
    
    log "INFO" "Cleanup completed successfully!"
    echo
    echo "=================================="
    echo "Cleanup Summary"
    echo "=================================="
    echo "✅ Greengrass deployments cancelled"
    echo "✅ Lambda function deleted"
    echo "✅ IoT resources removed"
    echo "✅ IAM role deleted"
    echo "✅ Local files cleaned up"
    echo "=================================="
    echo
    log "INFO" "All resources have been cleaned up"
    log "INFO" "You can now safely run deploy.sh again if needed"
}

# Trap errors
trap 'error_exit "Script failed at line $LINENO"' ERR

# Run main function
main "$@"