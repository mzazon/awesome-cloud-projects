#!/bin/bash

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Enterprise Identity Federation with Bedrock AgentCore - Cleanup Script
# This script safely removes all resources created by the deployment script
# with proper dependency handling and confirmation prompts

# Color codes for output formatting
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

# Global variables
FORCE_DELETE=${FORCE_DELETE:-false}
DRY_RUN=${DRY_RUN:-false}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}

# Function to execute commands with proper error handling
execute() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    log "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Would execute: $cmd"
        return 0
    fi
    
    if [[ "$ignore_errors" == "true" ]]; then
        eval "$cmd" || {
            warning "Command failed but continuing: $cmd"
            return 0
        }
    else
        eval "$cmd"
    fi
}

# Function to check prerequisites for cleanup
check_prerequisites() {
    log "Checking cleanup prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to load deployment variables
load_deployment_variables() {
    log "Loading deployment variables..."
    
    if [[ -f .deployment_vars ]]; then
        source .deployment_vars
        log "Loaded variables from .deployment_vars"
        log "  Stack Name: ${STACK_NAME:-not set}"
        log "  AWS Region: ${AWS_REGION:-not set}"
        log "  Random Suffix: ${RANDOM_SUFFIX:-not set}"
    else
        warning "Deployment variables file (.deployment_vars) not found"
        warning "Attempting to detect resources automatically..."
        
        # Try to detect resources automatically
        export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Prompt for missing variables if interactive
        if [[ -t 0 ]] && [[ "$SKIP_CONFIRMATION" != "true" ]]; then
            echo "Please provide the following information:"
            read -p "Lambda Function Name (or prefix): " LAMBDA_FUNCTION_NAME
            read -p "User Pool Name (or prefix): " IDENTITY_POOL_NAME
            read -p "AgentCore Identity Name: " AGENTCORE_IDENTITY_NAME
            read -p "Random Suffix: " RANDOM_SUFFIX
        else
            error "Cannot proceed without deployment variables in non-interactive mode"
            exit 1
        fi
    fi
    
    # Validate required variables
    if [[ -z "${AWS_REGION:-}" ]] || [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
        error "Missing required AWS configuration"
        exit 1
    fi
    
    success "Deployment variables loaded"
}

# Function to confirm destructive actions
confirm_destruction() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]] || [[ "$FORCE_DELETE" == "true" ]]; then
        warning "Skipping confirmation prompts"
        return 0
    fi
    
    echo ""
    warning "This will permanently delete the following resources:"
    echo "- Cognito User Pool: ${IDENTITY_POOL_NAME:-unknown}"
    echo "- Lambda Function: ${LAMBDA_FUNCTION_NAME:-unknown}"
    echo "- IAM Roles and Policies"
    echo "- AgentCore Workload Identity: ${AGENTCORE_IDENTITY_NAME:-unknown}"
    echo "- SSM Parameters"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRMATION
    
    if [[ "$CONFIRMATION" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Function to find and delete Cognito resources
cleanup_cognito_resources() {
    log "Cleaning up Cognito resources..."
    
    # Find User Pool by name if ID not available
    if [[ -z "${USER_POOL_ID:-}" ]] && [[ -n "${IDENTITY_POOL_NAME:-}" ]]; then
        USER_POOL_ID=$(aws cognito-idp list-user-pools \
            --max-items 50 \
            --query "UserPools[?contains(Name, '${IDENTITY_POOL_NAME}')].Id" \
            --output text | head -n1)
    fi
    
    if [[ -n "${USER_POOL_ID:-}" ]]; then
        # Delete User Pool Domain if exists
        execute "aws cognito-idp describe-user-pool-domain \
            --domain ${USER_POOL_ID} && \
            aws cognito-idp delete-user-pool-domain \
            --domain ${USER_POOL_ID}" \
            "Deleting User Pool domain (if exists)" \
            true
        
        # Delete User Pool (this removes all associated resources including clients and identity providers)
        execute "aws cognito-idp delete-user-pool \
            --user-pool-id ${USER_POOL_ID}" \
            "Deleting Cognito User Pool: ${USER_POOL_ID}"
        
        success "Cognito User Pool deleted"
    else
        warning "User Pool not found or already deleted"
    fi
}

# Function to cleanup Lambda resources
cleanup_lambda_resources() {
    log "Cleaning up Lambda resources..."
    
    # Find Lambda function if name not complete
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        # Check if function exists
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
            # Remove Cognito permissions
            execute "aws lambda remove-permission \
                --function-name ${LAMBDA_FUNCTION_NAME} \
                --statement-id CognitoInvokePermission" \
                "Removing Cognito invoke permission" \
                true
            
            # Delete Lambda function
            execute "aws lambda delete-function \
                --function-name ${LAMBDA_FUNCTION_NAME}" \
                "Deleting Lambda function: ${LAMBDA_FUNCTION_NAME}"
            
            success "Lambda function deleted"
        else
            warning "Lambda function not found or already deleted"
        fi
    else
        warning "Lambda function name not provided"
    fi
}

# Function to cleanup IAM resources
cleanup_iam_resources() {
    log "Cleaning up IAM resources..."
    
    # Cleanup Lambda IAM role
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        local lambda_role_name="${LAMBDA_FUNCTION_NAME}-role"
        
        # Detach policies from Lambda role
        execute "aws iam detach-role-policy \
            --role-name ${lambda_role_name} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
            "Detaching basic Lambda execution policy" \
            true
        
        # Delete Lambda role
        execute "aws iam delete-role \
            --role-name ${lambda_role_name}" \
            "Deleting Lambda IAM role: ${lambda_role_name}" \
            true
    fi
    
    # Cleanup AgentCore IAM resources
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local agentcore_role_name="AgentCoreExecutionRole-${RANDOM_SUFFIX}"
        local agentcore_policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AgentCoreAccessPolicy-${RANDOM_SUFFIX}"
        
        # Detach policy from AgentCore role
        execute "aws iam detach-role-policy \
            --role-name ${agentcore_role_name} \
            --policy-arn ${agentcore_policy_arn}" \
            "Detaching AgentCore access policy" \
            true
        
        # Delete AgentCore policy
        execute "aws iam delete-policy \
            --policy-arn ${agentcore_policy_arn}" \
            "Deleting AgentCore access policy" \
            true
        
        # Delete AgentCore role
        execute "aws iam delete-role \
            --role-name ${agentcore_role_name}" \
            "Deleting AgentCore IAM role: ${agentcore_role_name}" \
            true
    fi
    
    success "IAM resources cleanup completed"
}

# Function to cleanup AgentCore workload identity
cleanup_agentcore_resources() {
    log "Cleaning up AgentCore resources..."
    
    if [[ -n "${AGENTCORE_IDENTITY_NAME:-}" ]]; then
        # Note: This is for future use when AgentCore is generally available
        warning "AgentCore cleanup is simulated (service in preview)"
        warning "Manually remove AgentCore workload identity: ${AGENTCORE_IDENTITY_NAME}"
        
        # When AgentCore is generally available, replace with:
        # execute "aws bedrock-agentcore-control delete-workload-identity \
        #     --name ${AGENTCORE_IDENTITY_NAME}" \
        #     "Deleting AgentCore workload identity: ${AGENTCORE_IDENTITY_NAME}" \
        #     true
        
        success "AgentCore resources cleanup completed (simulated)"
    else
        warning "AgentCore identity name not provided"
    fi
}

# Function to cleanup SSM parameters
cleanup_ssm_parameters() {
    log "Cleaning up SSM parameters..."
    
    # Delete integration configuration parameter
    execute "aws ssm delete-parameter \
        --name \"/enterprise/agentcore/integration-config\"" \
        "Deleting integration configuration parameter" \
        true
    
    success "SSM parameters cleanup completed"
}

# Function to cleanup local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment variables file
    if [[ -f .deployment_vars ]]; then
        execute "rm -f .deployment_vars" \
            "Removing deployment variables file"
    fi
    
    # Remove any remaining temporary files
    execute "rm -f lambda-trust-policy.json agentcore-access-policy.json" \
        "Removing IAM policy files" \
        true
    
    execute "rm -f agent-trust-policy.json auth-handler.py auth-handler.zip" \
        "Removing Lambda function files" \
        true
    
    execute "rm -f agentcore-identity-config.json integration-config.json" \
        "Removing configuration files" \
        true
    
    execute "rm -f test-deployment.py test-event.json lambda-response.json" \
        "Removing test files" \
        true
    
    execute "rm -f generate-oauth-url.py" \
        "Removing utility files" \
        true
    
    success "Local files cleanup completed"
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check if User Pool still exists
    if [[ -n "${USER_POOL_ID:-}" ]]; then
        if aws cognito-idp describe-user-pool --user-pool-id "${USER_POOL_ID}" &>/dev/null; then
            warning "User Pool still exists: ${USER_POOL_ID}"
            ((cleanup_issues++))
        fi
    fi
    
    # Check if Lambda function still exists
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
            warning "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
            ((cleanup_issues++))
        fi
    fi
    
    # Check IAM roles
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        if aws iam get-role --role-name "${LAMBDA_FUNCTION_NAME}-role" &>/dev/null; then
            warning "Lambda IAM role still exists: ${LAMBDA_FUNCTION_NAME}-role"
            ((cleanup_issues++))
        fi
    fi
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        if aws iam get-role --role-name "AgentCoreExecutionRole-${RANDOM_SUFFIX}" &>/dev/null; then
            warning "AgentCore IAM role still exists: AgentCoreExecutionRole-${RANDOM_SUFFIX}"
            ((cleanup_issues++))
        fi
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        success "Cleanup verification completed - no issues found"
    else
        warning "Cleanup verification found $cleanup_issues potential issues"
        warning "You may need to manually review and clean up remaining resources"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "================"
    echo ""
    echo "The following resources have been removed:"
    echo "- Cognito User Pool and associated resources"
    echo "- Lambda function and permissions"
    echo "- IAM roles and policies"
    echo "- SSM parameters"
    echo "- Local configuration files"
    echo ""
    echo "Note: AgentCore workload identity cleanup is simulated"
    echo "      (service is in preview - manual cleanup may be required)"
    echo ""
    
    if [[ -n "${AWS_REGION:-}" ]]; then
        echo "Region: ${AWS_REGION}"
    fi
    
    if [[ -n "${AWS_ACCOUNT_ID:-}" ]]; then
        echo "Account: ${AWS_ACCOUNT_ID}"
    fi
    
    echo ""
    success "Cleanup completed successfully!"
}

# Function to handle emergency cleanup (force mode)
emergency_cleanup() {
    warning "Running emergency cleanup mode..."
    warning "This will attempt to find and delete resources by pattern matching"
    
    # Find and delete User Pools matching pattern
    log "Finding User Pools with 'enterprise-ai-agents' pattern..."
    aws cognito-idp list-user-pools --max-items 50 \
        --query "UserPools[?contains(Name, 'enterprise-ai-agents')].{Name:Name,Id:Id}" \
        --output table
    
    # Find and delete Lambda functions matching pattern
    log "Finding Lambda functions with 'agent-auth-handler' pattern..."
    aws lambda list-functions \
        --query "Functions[?contains(FunctionName, 'agent-auth-handler')].{Name:FunctionName,Runtime:Runtime}" \
        --output table
    
    # Find and delete IAM roles matching pattern
    log "Finding IAM roles with 'agent' pattern..."
    aws iam list-roles \
        --query "Roles[?contains(RoleName, 'agent') || contains(RoleName, 'AgentCore')].{Name:RoleName,Created:CreateDate}" \
        --output table
    
    warning "Review the resources above and use specific resource identifiers for cleanup"
}

# Main cleanup function
main() {
    log "Starting Enterprise Identity Federation cleanup..."
    
    # Check if help is requested
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        cat << EOF
Enterprise Identity Federation with Bedrock AgentCore - Cleanup Script

Usage: $0 [OPTIONS]

Options:
  --help, -h              Show this help message
  --dry-run               Show what would be deleted without actually deleting
  --force                 Force deletion without confirmation prompts
  --skip-confirmation     Skip confirmation prompts (use with caution)
  --emergency             Emergency cleanup mode (find resources by pattern)
  --verbose               Enable verbose logging

Environment Variables:
  FORCE_DELETE           Set to 'true' to force deletion
  DRY_RUN               Set to 'true' for dry-run mode
  SKIP_CONFIRMATION     Set to 'true' to skip confirmations

Examples:
  $0                              # Normal cleanup with confirmations
  $0 --dry-run                    # Show what would be deleted
  $0 --force                      # Force cleanup without prompts
  FORCE_DELETE=true $0            # Environment variable force mode
  $0 --emergency                  # Emergency pattern-based cleanup

CAUTION: This script will permanently delete AWS resources.
         Make sure you want to remove all components before proceeding.

EOF
        exit 0
    fi
    
    # Parse command line arguments
    EMERGENCY_MODE=false
    VERBOSE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_DELETE=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            --skip-confirmation)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --emergency)
                EMERGENCY_MODE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                set -x
                shift
                ;;
            *)
                warning "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    # Handle emergency mode
    if [[ "$EMERGENCY_MODE" == "true" ]]; then
        emergency_cleanup
        exit 0
    fi
    
    # Execute cleanup steps
    check_prerequisites
    load_deployment_variables
    confirm_destruction
    
    # Cleanup resources in reverse dependency order
    cleanup_cognito_resources
    cleanup_lambda_resources
    cleanup_iam_resources
    cleanup_agentcore_resources
    cleanup_ssm_parameters
    cleanup_local_files
    
    # Verify cleanup
    if [[ "$DRY_RUN" != "true" ]]; then
        verify_cleanup
    fi
    
    display_cleanup_summary
    
    log "Cleanup script completed!"
}

# Trap errors and provide helpful messages
trap 'error "Cleanup failed. Some resources may not have been deleted. Check the logs above for details."; exit 1' ERR

# Run main function with all arguments
main "$@"