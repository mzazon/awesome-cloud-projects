#!/bin/bash

# Destroy script for Dynamic Configuration with Parameter Store
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
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    if [[ ! -f .deployment_info ]]; then
        error "Deployment info file not found. Please run from the same directory as deploy.sh"
        error "Or set the environment variables manually:"
        error "  - AWS_REGION"
        error "  - AWS_ACCOUNT_ID" 
        error "  - FUNCTION_NAME"
        error "  - ROLE_NAME"
        error "  - PARAMETER_PREFIX"
        error "  - EVENTBRIDGE_RULE_NAME"
        error "  - RANDOM_SUFFIX"
        exit 1
    fi
    
    # Load variables from deployment info file
    source .deployment_info
    
    success "Deployment information loaded"
    log "Function Name: ${FUNCTION_NAME}"
    log "Role Name: ${ROLE_NAME}"
    log "Parameter Prefix: ${PARAMETER_PREFIX}"
    log "EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
}

# Function to confirm destruction
confirm_destruction() {
    echo
    warning "⚠️  WARNING: This will permanently delete the following resources:"
    echo "   • Lambda function: ${FUNCTION_NAME}"
    echo "   • IAM role: ${ROLE_NAME}"
    echo "   • IAM policy: ParameterStoreAccessPolicy-${RANDOM_SUFFIX}"
    echo "   • EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
    echo "   • CloudWatch alarms: ConfigManager-*-${RANDOM_SUFFIX}"
    echo "   • CloudWatch dashboard: ConfigManager-${RANDOM_SUFFIX}"
    echo "   • Parameter Store parameters under: ${PARAMETER_PREFIX}"
    echo
    
    # Force mode check
    if [[ "${1:-}" == "--force" ]]; then
        warning "Force mode enabled. Skipping confirmation prompt."
        return 0
    fi
    
    # Interactive confirmation
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    # Double confirmation for safety
    read -p "Type 'DELETE' to confirm resource deletion: " -r
    if [[ $REPLY != "DELETE" ]]; then
        log "Destruction cancelled. Expected 'DELETE', got: $REPLY"
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Function to delete Lambda function and EventBridge resources
delete_lambda_and_eventbridge() {
    log "Deleting Lambda function and EventBridge resources..."
    
    # Remove EventBridge rule targets first
    if aws events describe-rule --name "${EVENTBRIDGE_RULE_NAME}" &> /dev/null; then
        log "Removing EventBridge rule targets..."
        aws events remove-targets \
            --rule "${EVENTBRIDGE_RULE_NAME}" \
            --ids "1" || warning "Failed to remove EventBridge targets (may not exist)"
        
        log "Deleting EventBridge rule..."
        aws events delete-rule \
            --name "${EVENTBRIDGE_RULE_NAME}" || warning "Failed to delete EventBridge rule"
        
        success "EventBridge rule deleted"
    else
        warning "EventBridge rule not found: ${EVENTBRIDGE_RULE_NAME}"
    fi
    
    # Delete Lambda function
    if aws lambda get-function --function-name "${FUNCTION_NAME}" &> /dev/null; then
        log "Deleting Lambda function..."
        aws lambda delete-function \
            --function-name "${FUNCTION_NAME}"
        
        success "Lambda function deleted: ${FUNCTION_NAME}"
    else
        warning "Lambda function not found: ${FUNCTION_NAME}"
    fi
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Define alarm names
    ALARM_NAMES=(
        "ConfigManager-Errors-${RANDOM_SUFFIX}"
        "ConfigManager-Duration-${RANDOM_SUFFIX}" 
        "ConfigManager-RetrievalFailures-${RANDOM_SUFFIX}"
    )
    
    # Delete CloudWatch alarms
    EXISTING_ALARMS=()
    for alarm in "${ALARM_NAMES[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$alarm"; then
            EXISTING_ALARMS+=("$alarm")
        fi
    done
    
    if [[ ${#EXISTING_ALARMS[@]} -gt 0 ]]; then
        log "Deleting CloudWatch alarms: ${EXISTING_ALARMS[*]}"
        aws cloudwatch delete-alarms --alarm-names "${EXISTING_ALARMS[@]}"
        success "CloudWatch alarms deleted"
    else
        warning "No CloudWatch alarms found to delete"
    fi
    
    # Delete CloudWatch dashboard
    DASHBOARD_NAME="ConfigManager-${RANDOM_SUFFIX}"
    if aws cloudwatch describe-dashboards --dashboard-name-prefix "$DASHBOARD_NAME" --query 'DashboardEntries[0].DashboardName' --output text 2>/dev/null | grep -q "$DASHBOARD_NAME"; then
        log "Deleting CloudWatch dashboard..."
        aws cloudwatch delete-dashboards --dashboard-names "$DASHBOARD_NAME"
        success "CloudWatch dashboard deleted: $DASHBOARD_NAME"
    else
        warning "CloudWatch dashboard not found: $DASHBOARD_NAME"
    fi
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    # Check if role exists
    if aws iam get-role --role-name "${ROLE_NAME}" &> /dev/null; then
        log "Detaching policies from IAM role..."
        
        # Detach AWS managed policy
        aws iam detach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
            || warning "Failed to detach AWSLambdaBasicExecutionRole policy"
        
        # Detach custom policy
        CUSTOM_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/ParameterStoreAccessPolicy-${RANDOM_SUFFIX}"
        aws iam detach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn "$CUSTOM_POLICY_ARN" \
            || warning "Failed to detach custom policy"
        
        log "Deleting IAM role..."
        aws iam delete-role --role-name "${ROLE_NAME}"
        success "IAM role deleted: ${ROLE_NAME}"
    else
        warning "IAM role not found: ${ROLE_NAME}"
    fi
    
    # Delete custom policy
    CUSTOM_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/ParameterStoreAccessPolicy-${RANDOM_SUFFIX}"
    if aws iam get-policy --policy-arn "$CUSTOM_POLICY_ARN" &> /dev/null; then
        log "Deleting custom IAM policy..."
        aws iam delete-policy --policy-arn "$CUSTOM_POLICY_ARN"
        success "Custom IAM policy deleted"
    else
        warning "Custom IAM policy not found"
    fi
}

# Function to delete Parameter Store parameters
delete_parameter_store_parameters() {
    log "Deleting Parameter Store parameters..."
    
    # List all parameters under the prefix
    PARAMETER_NAMES=(
        "${PARAMETER_PREFIX}/database/host"
        "${PARAMETER_PREFIX}/database/port"
        "${PARAMETER_PREFIX}/database/password"
        "${PARAMETER_PREFIX}/api/timeout"
        "${PARAMETER_PREFIX}/features/new-ui"
    )
    
    # Check which parameters exist and delete them
    EXISTING_PARAMETERS=()
    for param in "${PARAMETER_NAMES[@]}"; do
        if aws ssm get-parameter --name "$param" &> /dev/null; then
            EXISTING_PARAMETERS+=("$param")
        fi
    done
    
    if [[ ${#EXISTING_PARAMETERS[@]} -gt 0 ]]; then
        log "Deleting ${#EXISTING_PARAMETERS[@]} parameters..."
        aws ssm delete-parameters --names "${EXISTING_PARAMETERS[@]}"
        success "Parameter Store parameters deleted"
    else
        warning "No Parameter Store parameters found to delete"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # List of files to remove
    LOCAL_FILES=(
        ".deployment_info"
        "trust-policy.json"
        "parameter-store-policy.json"
        "dashboard.json"
        "function.zip"
        "lambda_function.py"
        "response.json"
        "response-cached.json"
        "test-response.json"
    )
    
    REMOVED_COUNT=0
    for file in "${LOCAL_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            ((REMOVED_COUNT++))
        fi
    done
    
    if [[ $REMOVED_COUNT -gt 0 ]]; then
        success "Cleaned up $REMOVED_COUNT local files"
    else
        log "No local files to clean up"
    fi
}

# Function to verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    REMAINING_RESOURCES=()
    
    # Check Lambda function
    if aws lambda get-function --function-name "${FUNCTION_NAME}" &> /dev/null; then
        REMAINING_RESOURCES+=("Lambda function: ${FUNCTION_NAME}")
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${ROLE_NAME}" &> /dev/null; then
        REMAINING_RESOURCES+=("IAM role: ${ROLE_NAME}")
    fi
    
    # Check EventBridge rule
    if aws events describe-rule --name "${EVENTBRIDGE_RULE_NAME}" &> /dev/null; then
        REMAINING_RESOURCES+=("EventBridge rule: ${EVENTBRIDGE_RULE_NAME}")
    fi
    
    # Check some parameters
    if aws ssm get-parameter --name "${PARAMETER_PREFIX}/database/host" &> /dev/null; then
        REMAINING_RESOURCES+=("Parameter Store parameters under: ${PARAMETER_PREFIX}")
    fi
    
    if [[ ${#REMAINING_RESOURCES[@]} -gt 0 ]]; then
        warning "Some resources may still exist:"
        for resource in "${REMAINING_RESOURCES[@]}"; do
            echo "  - $resource"
        done
        warning "Please check the AWS console and delete manually if needed"
    else
        success "All resources appear to be deleted successfully"
    fi
}

# Function to display destruction summary
display_summary() {
    echo
    log "Destruction Summary"
    echo "==========================================";
    
    echo -e "${GREEN}✅ Lambda function and EventBridge resources${NC}"
    echo -e "${GREEN}✅ CloudWatch alarms and dashboard${NC}"
    echo -e "${GREEN}✅ IAM role and custom policy${NC}"
    echo -e "${GREEN}✅ Parameter Store parameters${NC}"
    echo -e "${GREEN}✅ Local files${NC}"
    echo
    
    echo -e "${BLUE}📋 What was deleted:${NC}"
    echo "• Lambda function: ${FUNCTION_NAME}"
    echo "• IAM role: ${ROLE_NAME}"
    echo "• Custom policy: ParameterStoreAccessPolicy-${RANDOM_SUFFIX}"
    echo "• EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
    echo "• CloudWatch alarms and dashboard"
    echo "• Configuration parameters under: ${PARAMETER_PREFIX}"
    echo "• Local deployment files"
    echo
    
    echo -e "${YELLOW}💡 Next Steps:${NC}"
    echo "1. Check AWS billing console for any remaining charges"
    echo "2. Verify no resources remain in the AWS console"
    echo "3. Review CloudWatch logs (will be automatically deleted after retention period)"
    echo
    
    success "Destruction completed successfully! 🎉"
}

# Function to handle partial cleanup on error
cleanup_on_error() {
    error "An error occurred during destruction. Some resources may remain."
    error "Please check the AWS console and delete any remaining resources manually:"
    echo "  - Lambda function: ${FUNCTION_NAME:-unknown}"
    echo "  - IAM role: ${ROLE_NAME:-unknown}"
    echo "  - EventBridge rule: ${EVENTBRIDGE_RULE_NAME:-unknown}"
    echo "  - CloudWatch resources with suffix: ${RANDOM_SUFFIX:-unknown}"
    echo "  - Parameters under: ${PARAMETER_PREFIX:-unknown}"
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR

# Main execution
main() {
    log "Starting Dynamic Configuration Management destruction..."
    
    check_prerequisites
    load_deployment_info
    confirm_destruction "$@"
    
    # Delete resources in reverse order of creation
    delete_lambda_and_eventbridge
    delete_cloudwatch_resources
    delete_iam_resources
    delete_parameter_store_parameters
    cleanup_local_files
    
    verify_deletion
    display_summary
}

# Parse command line arguments
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [--force]"
    echo
    echo "Options:"
    echo "  --force    Skip confirmation prompts and delete resources immediately"
    echo "  --help     Show this help message"
    echo
    echo "This script will delete all resources created by the deploy script:"
    echo "  - Lambda function"
    echo "  - IAM role and custom policy"
    echo "  - EventBridge rule"
    echo "  - CloudWatch alarms and dashboard"
    echo "  - Parameter Store parameters"
    echo "  - Local deployment files"
    exit 0
fi

# Execute main function with arguments
main "$@"