#!/bin/bash

# Destroy script for Basic Secret Management with Secrets Manager and Lambda
# This script removes all infrastructure created by the deploy.sh script
set -e

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

# Force mode flag
FORCE_MODE=false
SKIP_CONFIRMATION=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_MODE=true
            SKIP_CONFIRMATION=true
            warning "Running in FORCE mode - will attempt to delete all resources without confirmation"
            shift
            ;;
        --yes)
            SKIP_CONFIRMATION=true
            log "Auto-confirming destruction"
            shift
            ;;
        *)
            error "Unknown option: $1"
            echo "Usage: $0 [--force] [--yes]"
            echo "  --force  Force deletion even if deployment state file is missing"
            echo "  --yes    Skip confirmation prompts"
            exit 1
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    if [[ -f ".deployment-state" ]]; then
        # Source the deployment state file
        source .deployment-state
        
        success "Deployment state loaded"
        log "Found resources to clean up:"
        log "  - Secret: ${SECRET_NAME:-'Not found'}"
        log "  - Lambda Function: ${LAMBDA_FUNCTION_NAME:-'Not found'}"
        log "  - IAM Role: ${IAM_ROLE_NAME:-'Not found'}"
        log "  - IAM Policy: ${POLICY_NAME:-'Not found'}"
        log "  - AWS Region: ${AWS_REGION:-'Not found'}"
        log "  - Deployment Date: ${DEPLOYMENT_DATE:-'Not found'}"
        
        # Validate required variables
        if [[ -z "$SECRET_NAME" || -z "$LAMBDA_FUNCTION_NAME" || -z "$IAM_ROLE_NAME" || -z "$POLICY_NAME" ]]; then
            error "Deployment state file is incomplete or corrupted"
            if [[ "$FORCE_MODE" == "false" ]]; then
                exit 1
            else
                warning "Continuing in force mode despite incomplete state file"
            fi
        fi
        
    else
        if [[ "$FORCE_MODE" == "false" ]]; then
            error "Deployment state file (.deployment-state) not found!"
            error "Cannot determine which resources to clean up."
            error "Use --force flag to attempt cleanup without state file."
            exit 1
        else
            warning "No deployment state file found, running in force mode"
            warning "You will need to manually specify resource names or clean up manually"
            
            # Set default values for common resource patterns
            read -p "Enter the resource suffix used during deployment (or press Enter to skip): " MANUAL_SUFFIX
            if [[ -n "$MANUAL_SUFFIX" ]]; then
                SECRET_NAME="my-app-secrets-${MANUAL_SUFFIX}"
                LAMBDA_FUNCTION_NAME="secret-demo-${MANUAL_SUFFIX}"
                IAM_ROLE_NAME="lambda-secrets-role-${MANUAL_SUFFIX}"
                POLICY_NAME="SecretsAccess-${MANUAL_SUFFIX}"
                AWS_REGION=$(aws configure get region || echo "us-east-1")
                AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
                
                log "Using manual resource names with suffix: ${MANUAL_SUFFIX}"
            else
                error "Cannot proceed without resource names"
                exit 1
            fi
        fi
    fi
}

# Confirm destruction
confirm_destruction() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    log "This will permanently delete the following resources:"
    echo "  🔐 Secret Manager Secret: ${SECRET_NAME}"
    echo "  ⚡ Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  🔑 IAM Role: ${IAM_ROLE_NAME}"
    echo "  📋 IAM Policy: ${POLICY_NAME}"
    echo "  🌍 AWS Region: ${AWS_REGION}"
    echo ""
    warning "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " CONFIRMATION
    
    if [[ "$CONFIRMATION" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed by user"
}

# Check if resource exists (generic function)
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local check_command=$3
    
    if eval "$check_command" &> /dev/null; then
        return 0  # Resource exists
    else
        return 1  # Resource doesn't exist
    fi
}

# Delete Lambda function
delete_lambda_function() {
    log "Deleting Lambda function..."
    
    if resource_exists "Lambda Function" "$LAMBDA_FUNCTION_NAME" "aws lambda get-function --function-name ${LAMBDA_FUNCTION_NAME}"; then
        aws lambda delete-function --function-name ${LAMBDA_FUNCTION_NAME}
        success "Lambda function deleted: ${LAMBDA_FUNCTION_NAME}"
    else
        warning "Lambda function not found: ${LAMBDA_FUNCTION_NAME}"
    fi
}

# Delete IAM policy and detach from role
delete_iam_policy() {
    log "Removing IAM policy and detaching from role..."
    
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
    
    # Check if policy exists and is attached to role
    if resource_exists "IAM Policy" "$POLICY_NAME" "aws iam get-policy --policy-arn ${policy_arn}"; then
        # Detach policy from role
        if resource_exists "IAM Role" "$IAM_ROLE_NAME" "aws iam get-role --role-name ${IAM_ROLE_NAME}"; then
            aws iam detach-role-policy \
                --role-name ${IAM_ROLE_NAME} \
                --policy-arn ${policy_arn} 2>/dev/null || warning "Policy may not be attached to role"
            
            # Also detach the basic execution policy
            aws iam detach-role-policy \
                --role-name ${IAM_ROLE_NAME} \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || warning "Basic execution policy may not be attached"
        fi
        
        # Delete the custom policy
        aws iam delete-policy --policy-arn ${policy_arn}
        success "IAM policy deleted: ${POLICY_NAME}"
    else
        warning "IAM policy not found: ${POLICY_NAME}"
    fi
}

# Delete IAM role
delete_iam_role() {
    log "Deleting IAM role..."
    
    if resource_exists "IAM Role" "$IAM_ROLE_NAME" "aws iam get-role --role-name ${IAM_ROLE_NAME}"; then
        # List and detach any remaining policies (safety check)
        attached_policies=$(aws iam list-attached-role-policies --role-name ${IAM_ROLE_NAME} --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
        
        if [[ -n "$attached_policies" ]]; then
            warning "Found remaining attached policies, detaching them..."
            for policy_arn in $attached_policies; do
                aws iam detach-role-policy --role-name ${IAM_ROLE_NAME} --policy-arn ${policy_arn}
                log "Detached policy: ${policy_arn}"
            done
        fi
        
        # Delete the role
        aws iam delete-role --role-name ${IAM_ROLE_NAME}
        success "IAM role deleted: ${IAM_ROLE_NAME}"
    else
        warning "IAM role not found: ${IAM_ROLE_NAME}"
    fi
}

# Delete secret from Secrets Manager
delete_secret() {
    log "Deleting secret from Secrets Manager..."
    
    if resource_exists "Secret" "$SECRET_NAME" "aws secretsmanager describe-secret --secret-id ${SECRET_NAME}"; then
        # Check if secret is already scheduled for deletion
        secret_status=$(aws secretsmanager describe-secret --secret-id ${SECRET_NAME} --query 'DeletedDate' --output text 2>/dev/null || echo "None")
        
        if [[ "$secret_status" != "None" ]]; then
            warning "Secret is already scheduled for deletion: ${SECRET_NAME}"
            log "Attempting to force immediate deletion..."
        fi
        
        # Force delete the secret immediately (for demo purposes)
        aws secretsmanager delete-secret \
            --secret-id ${SECRET_NAME} \
            --force-delete-without-recovery
        
        success "Secret deleted from Secrets Manager: ${SECRET_NAME}"
    else
        warning "Secret not found in Secrets Manager: ${SECRET_NAME}"
    fi
}

# Clean up CloudWatch logs
cleanup_cloudwatch_logs() {
    log "Cleaning up CloudWatch log groups..."
    
    local log_group_name="/aws/lambda/${LAMBDA_FUNCTION_NAME}"
    
    if resource_exists "Log Group" "$log_group_name" "aws logs describe-log-groups --log-group-name-prefix ${log_group_name}"; then
        aws logs delete-log-group --log-group-name ${log_group_name}
        success "CloudWatch log group deleted: ${log_group_name}"
    else
        warning "CloudWatch log group not found: ${log_group_name}"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # List of files to clean up
    local files_to_remove=(
        ".deployment-state"
        "trust-policy.json"
        "secrets-policy.json"
        "lambda-function.zip"
        "response.json"
        "lambda-package"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            rm -rf "$file"
            log "Removed: $file"
        fi
    done
    
    success "Local cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_errors=0
    
    # Check Lambda function
    if resource_exists "Lambda Function" "$LAMBDA_FUNCTION_NAME" "aws lambda get-function --function-name ${LAMBDA_FUNCTION_NAME}"; then
        error "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
        ((cleanup_errors++))
    fi
    
    # Check IAM role
    if resource_exists "IAM Role" "$IAM_ROLE_NAME" "aws iam get-role --role-name ${IAM_ROLE_NAME}"; then
        error "IAM role still exists: ${IAM_ROLE_NAME}"
        ((cleanup_errors++))
    fi
    
    # Check IAM policy
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
    if resource_exists "IAM Policy" "$POLICY_NAME" "aws iam get-policy --policy-arn ${policy_arn}"; then
        error "IAM policy still exists: ${POLICY_NAME}"
        ((cleanup_errors++))
    fi
    
    # Check secret (should be scheduled for deletion or gone)
    if resource_exists "Secret" "$SECRET_NAME" "aws secretsmanager describe-secret --secret-id ${SECRET_NAME}"; then
        # Check if it's scheduled for deletion
        secret_status=$(aws secretsmanager describe-secret --secret-id ${SECRET_NAME} --query 'DeletedDate' --output text 2>/dev/null || echo "None")
        if [[ "$secret_status" == "None" ]]; then
            error "Secret still exists and not scheduled for deletion: ${SECRET_NAME}"
            ((cleanup_errors++))
        else
            success "Secret is scheduled for deletion: ${SECRET_NAME}"
        fi
    fi
    
    if [[ $cleanup_errors -eq 0 ]]; then
        success "Cleanup verification passed - all resources removed successfully"
        return 0
    else
        error "Cleanup verification failed - $cleanup_errors resources still exist"
        return 1
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    echo ""
    success "=== CLEANUP SUMMARY ==="
    log "Successfully removed resources:"
    log "  ✅ Lambda Function: ${LAMBDA_FUNCTION_NAME:-'N/A'}"
    log "  ✅ IAM Role: ${IAM_ROLE_NAME:-'N/A'}"
    log "  ✅ IAM Policy: ${POLICY_NAME:-'N/A'}"
    log "  ✅ Secret: ${SECRET_NAME:-'N/A'}"
    log "  ✅ CloudWatch Logs: /aws/lambda/${LAMBDA_FUNCTION_NAME:-'N/A'}"
    log "  ✅ Local Files: deployment state and temporary files"
    echo ""
    log "AWS Region: ${AWS_REGION:-'N/A'}"
    log "Cleanup completed at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo ""
    success "All resources have been successfully removed!"
    warning "Note: It may take a few minutes for all resources to be fully removed from AWS"
}

# Main cleanup function
main() {
    log "Starting cleanup of Basic Secret Management solution..."
    
    # Run all cleanup steps
    check_prerequisites
    load_deployment_state
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_lambda_function
    cleanup_cloudwatch_logs
    delete_iam_policy
    delete_iam_role
    delete_secret
    cleanup_local_files
    
    # Verify cleanup
    if verify_cleanup; then
        show_cleanup_summary
    else
        error "Some resources may still exist. Please check the AWS console manually."
        exit 1
    fi
}

# Handle script interruption
trap 'error "Cleanup interrupted! Some resources may still exist. Please run the script again or clean up manually."; exit 1' INT TERM

# Run main function
main "$@"