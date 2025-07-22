#!/bin/bash

# =============================================================================
# AWS Cost Optimization Workflows Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deploy.sh script:
# - Lambda functions and IAM roles
# - Budget actions IAM resources
# - Cost Anomaly Detection resources
# - AWS Budgets
# - SNS topic and subscriptions
# - Cost Optimization Hub settings (optional)
# =============================================================================

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/cost-optimization-cleanup-$(date +%Y%m%d-%H%M%S).log"
RESOURCE_TAG_KEY="CostOptimizationProject"
RESOURCE_TAG_VALUE="automated-workflows"

# Global variables
DEPLOYMENT_ID=""
AWS_ACCOUNT_ID=""
AWS_REGION=""
SNS_TOPIC_ARN=""
FORCE_CLEANUP=false
DISABLE_COH=false

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "[DEBUG] ${message}" | tee -a "$LOG_FILE"
            fi
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

show_help() {
    cat << EOF
Usage: $0 [DEPLOYMENT_ID] [OPTIONS]

Safely removes AWS Cost Optimization Workflows resources.

Arguments:
  DEPLOYMENT_ID    The deployment ID from the original deployment
                   (found in deployment-info-*.json or deployment output)

Options:
  --force                    Skip confirmation prompts
  --disable-cost-hub        Also disable Cost Optimization Hub (use with caution)
  --dry-run                 Show what would be deleted without actually deleting
  --help                    Show this help message

Examples:
  $0 ab1c2d                                    # Interactive cleanup
  $0 ab1c2d --force                           # Force cleanup without prompts
  $0 ab1c2d --force --disable-cost-hub       # Also disable Cost Optimization Hub
  $0 --dry-run ab1c2d                        # Show what would be deleted

If no DEPLOYMENT_ID is provided, the script will attempt to find deployment
info files in the current directory and prompt you to select one.
EOF
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check jq for JSON parsing (optional but helpful)
    if ! command -v jq &> /dev/null; then
        log "WARNING" "jq not found. JSON parsing will be limited."
    fi
    
    log "SUCCESS" "Prerequisites check completed"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --force)
                FORCE_CLEANUP=true
                shift
                ;;
            --disable-cost-hub)
                DISABLE_COH=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -*)
                log "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$DEPLOYMENT_ID" ]]; then
                    DEPLOYMENT_ID="$1"
                else
                    log "ERROR" "Multiple deployment IDs specified: $DEPLOYMENT_ID and $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

find_deployment_info() {
    if [[ -n "$DEPLOYMENT_ID" ]]; then
        # Look for deployment info file with the provided ID
        local info_file="${SCRIPT_DIR}/deployment-info-${DEPLOYMENT_ID}.json"
        if [[ -f "$info_file" ]]; then
            log "INFO" "Found deployment info file: $info_file"
            load_deployment_info "$info_file"
            return 0
        else
            log "WARNING" "Deployment info file not found: $info_file"
            log "INFO" "Will attempt cleanup using deployment ID: $DEPLOYMENT_ID"
            setup_environment_from_id
            return 0
        fi
    fi
    
    # Look for any deployment info files
    local info_files=("${SCRIPT_DIR}"/deployment-info-*.json)
    if [[ ${#info_files[@]} -eq 0 || ! -f "${info_files[0]}" ]]; then
        log "ERROR" "No deployment info files found and no deployment ID provided."
        log "ERROR" "Please provide a deployment ID or ensure deployment info files exist."
        echo
        show_help
        exit 1
    fi
    
    # If only one file, use it
    if [[ ${#info_files[@]} -eq 1 ]]; then
        log "INFO" "Found single deployment info file: ${info_files[0]}"
        load_deployment_info "${info_files[0]}"
        return 0
    fi
    
    # Multiple files found, let user choose
    echo "Multiple deployment info files found:"
    local i=1
    for file in "${info_files[@]}"; do
        local file_id=$(basename "$file" .json | sed 's/deployment-info-//')
        local file_date=$(stat -f %Sm -t "%Y-%m-%d %H:%M" "$file" 2>/dev/null || stat -c %y "$file" 2>/dev/null || echo "unknown")
        echo "  $i) $file_id (created: $file_date)"
        ((i++))
    done
    
    echo
    read -p "Select deployment to clean up (1-${#info_files[@]}): " selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#info_files[@]} ]]; then
        local selected_file="${info_files[$((selection-1))]}"
        log "INFO" "Selected deployment info file: $selected_file"
        load_deployment_info "$selected_file"
    else
        log "ERROR" "Invalid selection: $selection"
        exit 1
    fi
}

load_deployment_info() {
    local info_file="$1"
    
    if command -v jq &> /dev/null; then
        # Use jq for robust JSON parsing
        DEPLOYMENT_ID=$(jq -r '.deploymentId' "$info_file")
        AWS_ACCOUNT_ID=$(jq -r '.awsAccountId' "$info_file")
        AWS_REGION=$(jq -r '.awsRegion' "$info_file")
        SNS_TOPIC_ARN=$(jq -r '.snsTopicArn' "$info_file")
    else
        # Fallback to grep/sed parsing
        DEPLOYMENT_ID=$(grep '"deploymentId"' "$info_file" | sed 's/.*: *"\([^"]*\)".*/\1/')
        AWS_ACCOUNT_ID=$(grep '"awsAccountId"' "$info_file" | sed 's/.*: *"\([^"]*\)".*/\1/')
        AWS_REGION=$(grep '"awsRegion"' "$info_file" | sed 's/.*: *"\([^"]*\)".*/\1/')
        SNS_TOPIC_ARN=$(grep '"snsTopicArn"' "$info_file" | sed 's/.*: *"\([^"]*\)".*/\1/')
    fi
    
    if [[ -z "$DEPLOYMENT_ID" || -z "$AWS_ACCOUNT_ID" || -z "$AWS_REGION" ]]; then
        log "ERROR" "Failed to parse deployment info from: $info_file"
        exit 1
    fi
    
    log "INFO" "Loaded deployment info:"
    log "INFO" "  Deployment ID: $DEPLOYMENT_ID"
    log "INFO" "  AWS Account: $AWS_ACCOUNT_ID"
    log "INFO" "  AWS Region: $AWS_REGION"
    log "INFO" "  SNS Topic: ${SNS_TOPIC_ARN:-'N/A'}"
}

setup_environment_from_id() {
    log "INFO" "Setting up environment from deployment ID: $DEPLOYMENT_ID"
    
    # Get current AWS environment
    AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        AWS_REGION="us-east-1"
        log "WARNING" "No default region configured, using us-east-1"
    fi
    
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Construct SNS topic ARN based on naming convention
    SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:cost-optimization-alerts-${DEPLOYMENT_ID}"
    
    log "INFO" "Environment setup complete:"
    log "INFO" "  AWS Account: $AWS_ACCOUNT_ID"
    log "INFO" "  AWS Region: $AWS_REGION"
    log "INFO" "  Expected SNS Topic: $SNS_TOPIC_ARN"
}

confirm_cleanup() {
    if [[ "$FORCE_CLEANUP" == "true" ]]; then
        log "INFO" "Force cleanup enabled, skipping confirmation"
        return 0
    fi
    
    echo
    echo "=========================================="
    echo "CLEANUP CONFIRMATION"
    echo "=========================================="
    echo "This will delete the following resources:"
    echo "• Lambda function: cost-optimization-handler-${DEPLOYMENT_ID}"
    echo "• IAM roles and policies for Lambda and Budget Actions"
    echo "• Cost Anomaly Detection resources"
    echo "• AWS Budgets: monthly-cost-budget-${DEPLOYMENT_ID}, ec2-usage-budget-${DEPLOYMENT_ID}, ri-utilization-budget-${DEPLOYMENT_ID}"
    echo "• SNS topic and subscriptions"
    
    if [[ "$DISABLE_COH" == "true" ]]; then
        echo "• Cost Optimization Hub (will be DISABLED)"
    fi
    
    echo
    echo "Deployment ID: $DEPLOYMENT_ID"
    echo "AWS Account: $AWS_ACCOUNT_ID"
    echo "AWS Region: $AWS_REGION"
    echo "=========================================="
    echo
    
    read -p "Are you sure you want to proceed with cleanup? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "INFO" "Cleanup cancelled by user"
        exit 0
    fi
    
    if [[ "$DISABLE_COH" == "true" ]]; then
        echo
        log "WARNING" "You chose to disable Cost Optimization Hub."
        log "WARNING" "This will affect ALL cost optimization recommendations in your account."
        read -p "Are you absolutely sure? (y/N): " coh_confirm
        if [[ ! "$coh_confirm" =~ ^[Yy]$ ]]; then
            log "INFO" "Cost Optimization Hub will NOT be disabled"
            DISABLE_COH=false
        fi
    fi
}

dry_run_cleanup() {
    log "INFO" "DRY RUN MODE - No resources will be deleted"
    echo
    echo "Would delete the following resources:"
    
    # Check Lambda function
    local function_name="cost-optimization-handler-${DEPLOYMENT_ID}"
    if aws lambda get-function --function-name "$function_name" &> /dev/null; then
        echo "✓ Lambda function: $function_name"
    else
        echo "✗ Lambda function: $function_name (not found)"
    fi
    
    # Check IAM roles
    local lambda_role="CostOptimizationLambdaRole-${DEPLOYMENT_ID}"
    local budget_role="BudgetActionsRole-${DEPLOYMENT_ID}"
    
    if aws iam get-role --role-name "$lambda_role" &> /dev/null; then
        echo "✓ IAM role: $lambda_role"
    else
        echo "✗ IAM role: $lambda_role (not found)"
    fi
    
    if aws iam get-role --role-name "$budget_role" &> /dev/null; then
        echo "✓ IAM role: $budget_role"
    else
        echo "✗ IAM role: $budget_role (not found)"
    fi
    
    # Check budgets
    local budgets=("monthly-cost-budget-${DEPLOYMENT_ID}" "ec2-usage-budget-${DEPLOYMENT_ID}" "ri-utilization-budget-${DEPLOYMENT_ID}")
    for budget in "${budgets[@]}"; do
        if aws budgets describe-budget --account-id "$AWS_ACCOUNT_ID" --budget-name "$budget" &> /dev/null; then
            echo "✓ Budget: $budget"
        else
            echo "✗ Budget: $budget (not found)"
        fi
    done
    
    # Check SNS topic
    if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &> /dev/null; then
        echo "✓ SNS topic: $SNS_TOPIC_ARN"
    else
        echo "✗ SNS topic: $SNS_TOPIC_ARN (not found)"
    fi
    
    # Check Cost Anomaly Detection
    local detector_name="cost-anomaly-detector-${DEPLOYMENT_ID}"
    if aws ce get-anomaly-detectors --query "AnomalyDetectors[?DetectorName=='${detector_name}']" --output text | grep -q "$detector_name"; then
        echo "✓ Cost anomaly detector: $detector_name"
    else
        echo "✗ Cost anomaly detector: $detector_name (not found)"
    fi
    
    echo
    log "SUCCESS" "Dry run completed"
}

cleanup_lambda_function() {
    log "INFO" "Cleaning up Lambda function and related resources..."
    
    local function_name="cost-optimization-handler-${DEPLOYMENT_ID}"
    local role_name="CostOptimizationLambdaRole-${DEPLOYMENT_ID}"
    
    # Delete Lambda function
    if aws lambda delete-function --function-name "$function_name" 2>/dev/null; then
        log "SUCCESS" "Deleted Lambda function: $function_name"
    else
        log "WARNING" "Lambda function not found or already deleted: $function_name"
    fi
    
    # Wait for function deletion to propagate
    sleep 5
    
    # Detach policies from Lambda role
    local policies=("arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 
                   "arn:aws:iam::aws:policy/CostOptimizationHubServiceRolePolicy")
    
    for policy in "${policies[@]}"; do
        if aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy" 2>/dev/null; then
            log "SUCCESS" "Detached policy from Lambda role: $(basename "$policy")"
        else
            log "WARNING" "Failed to detach policy or policy not attached: $(basename "$policy")"
        fi
    done
    
    # Delete Lambda role
    if aws iam delete-role --role-name "$role_name" 2>/dev/null; then
        log "SUCCESS" "Deleted Lambda IAM role: $role_name"
    else
        log "WARNING" "Lambda IAM role not found or already deleted: $role_name"
    fi
}

cleanup_budget_actions() {
    log "INFO" "Cleaning up budget actions resources..."
    
    local role_name="BudgetActionsRole-${DEPLOYMENT_ID}"
    local policy_name="BudgetRestrictionPolicy-${DEPLOYMENT_ID}"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
    
    # Detach policy from role
    if aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" 2>/dev/null; then
        log "SUCCESS" "Detached budget restriction policy from role"
    else
        log "WARNING" "Failed to detach budget restriction policy or policy not attached"
    fi
    
    # Delete policy
    if aws iam delete-policy --policy-arn "$policy_arn" 2>/dev/null; then
        log "SUCCESS" "Deleted budget restriction policy: $policy_name"
    else
        log "WARNING" "Budget restriction policy not found or already deleted: $policy_name"
    fi
    
    # Delete role
    if aws iam delete-role --role-name "$role_name" 2>/dev/null; then
        log "SUCCESS" "Deleted budget actions IAM role: $role_name"
    else
        log "WARNING" "Budget actions IAM role not found or already deleted: $role_name"
    fi
}

cleanup_cost_anomaly_detection() {
    log "INFO" "Cleaning up Cost Anomaly Detection resources..."
    
    local detector_name="cost-anomaly-detector-${DEPLOYMENT_ID}"
    local subscription_name="cost-anomaly-subscription-${DEPLOYMENT_ID}"
    
    # Get anomaly subscription ARN
    local subscription_arn=$(aws ce get-anomaly-subscriptions \
        --query "AnomalySubscriptions[?SubscriptionName=='${subscription_name}'].SubscriptionArn" \
        --output text 2>/dev/null)
    
    if [[ -n "$subscription_arn" && "$subscription_arn" != "None" ]]; then
        if aws ce delete-anomaly-subscription --subscription-arn "$subscription_arn" 2>/dev/null; then
            log "SUCCESS" "Deleted cost anomaly subscription: $subscription_name"
        else
            log "WARNING" "Failed to delete cost anomaly subscription: $subscription_name"
        fi
    else
        log "WARNING" "Cost anomaly subscription not found: $subscription_name"
    fi
    
    # Get anomaly detector ARN
    local detector_arn=$(aws ce get-anomaly-detectors \
        --query "AnomalyDetectors[?DetectorName=='${detector_name}'].DetectorArn" \
        --output text 2>/dev/null)
    
    if [[ -n "$detector_arn" && "$detector_arn" != "None" ]]; then
        if aws ce delete-anomaly-detector --detector-arn "$detector_arn" 2>/dev/null; then
            log "SUCCESS" "Deleted cost anomaly detector: $detector_name"
        else
            log "WARNING" "Failed to delete cost anomaly detector: $detector_name"
        fi
    else
        log "WARNING" "Cost anomaly detector not found: $detector_name"
    fi
}

cleanup_budgets() {
    log "INFO" "Cleaning up AWS Budgets..."
    
    local budgets=("monthly-cost-budget-${DEPLOYMENT_ID}" 
                   "ec2-usage-budget-${DEPLOYMENT_ID}" 
                   "ri-utilization-budget-${DEPLOYMENT_ID}")
    
    for budget in "${budgets[@]}"; do
        if aws budgets delete-budget --account-id "$AWS_ACCOUNT_ID" --budget-name "$budget" 2>/dev/null; then
            log "SUCCESS" "Deleted budget: $budget"
        else
            log "WARNING" "Budget not found or already deleted: $budget"
        fi
    done
}

cleanup_sns_topic() {
    log "INFO" "Cleaning up SNS topic and subscriptions..."
    
    if [[ -z "$SNS_TOPIC_ARN" ]]; then
        log "WARNING" "SNS topic ARN not provided, skipping SNS cleanup"
        return 0
    fi
    
    # Delete SNS topic (this automatically removes all subscriptions)
    if aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" 2>/dev/null; then
        log "SUCCESS" "Deleted SNS topic and all subscriptions: $SNS_TOPIC_ARN"
    else
        log "WARNING" "SNS topic not found or already deleted: $SNS_TOPIC_ARN"
    fi
}

cleanup_cost_optimization_hub() {
    if [[ "$DISABLE_COH" != "true" ]]; then
        log "INFO" "Leaving Cost Optimization Hub enabled"
        return 0
    fi
    
    log "WARNING" "Disabling Cost Optimization Hub..."
    
    # Note: There's no direct way to completely disable COH via CLI
    # We can only modify preferences, not disable the service entirely
    log "WARNING" "Cost Optimization Hub cannot be completely disabled via CLI"
    log "INFO" "The service will remain enabled but you can ignore its recommendations"
    log "INFO" "To disable in console: Go to Cost Management -> Cost Optimization Hub -> Settings"
}

cleanup_temporary_files() {
    log "INFO" "Cleaning up temporary files..."
    
    # Remove temporary test files
    rm -f /tmp/lambda_test_response.json
    
    # Remove deployment info file if it exists
    local info_file="${SCRIPT_DIR}/deployment-info-${DEPLOYMENT_ID}.json"
    if [[ -f "$info_file" ]]; then
        if [[ "$FORCE_CLEANUP" == "true" ]]; then
            rm -f "$info_file"
            log "SUCCESS" "Removed deployment info file: $info_file"
        else
            read -p "Remove deployment info file ($info_file)? (y/N): " remove_info
            if [[ "$remove_info" =~ ^[Yy]$ ]]; then
                rm -f "$info_file"
                log "SUCCESS" "Removed deployment info file: $info_file"
            else
                log "INFO" "Keeping deployment info file: $info_file"
            fi
        fi
    fi
}

validate_cleanup() {
    log "INFO" "Validating cleanup completion..."
    
    local cleanup_issues=0
    
    # Check Lambda function
    local function_name="cost-optimization-handler-${DEPLOYMENT_ID}"
    if aws lambda get-function --function-name "$function_name" &> /dev/null; then
        log "WARNING" "Lambda function still exists: $function_name"
        ((cleanup_issues++))
    fi
    
    # Check IAM roles
    local roles=("CostOptimizationLambdaRole-${DEPLOYMENT_ID}" "BudgetActionsRole-${DEPLOYMENT_ID}")
    for role in "${roles[@]}"; do
        if aws iam get-role --role-name "$role" &> /dev/null; then
            log "WARNING" "IAM role still exists: $role"
            ((cleanup_issues++))
        fi
    done
    
    # Check budgets
    local budget_count=$(aws budgets describe-budgets --account-id "$AWS_ACCOUNT_ID" \
        --query "Budgets[?contains(BudgetName, \`${DEPLOYMENT_ID}\`)] | length(@)" 2>/dev/null || echo "0")
    if [[ "$budget_count" -gt 0 ]]; then
        log "WARNING" "Found $budget_count budget(s) still exist with deployment ID"
        ((cleanup_issues++))
    fi
    
    # Check SNS topic
    if [[ -n "$SNS_TOPIC_ARN" ]] && aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &> /dev/null; then
        log "WARNING" "SNS topic still exists: $SNS_TOPIC_ARN"
        ((cleanup_issues++))
    fi
    
    if [[ "$cleanup_issues" -eq 0 ]]; then
        log "SUCCESS" "All resources successfully cleaned up"
    else
        log "WARNING" "Cleanup completed with $cleanup_issues issue(s)"
        log "WARNING" "Some resources may need manual cleanup"
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    echo "=========================================="
    echo "AWS Cost Optimization Workflows Cleanup"
    echo "=========================================="
    echo
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check for dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        check_prerequisites
        find_deployment_info
        dry_run_cleanup
        exit 0
    fi
    
    # Main cleanup flow
    check_prerequisites
    find_deployment_info
    confirm_cleanup
    
    log "INFO" "Starting cleanup for deployment ID: $DEPLOYMENT_ID"
    
    # Cleanup resources in reverse order of creation
    cleanup_lambda_function
    cleanup_budget_actions
    cleanup_cost_anomaly_detection
    cleanup_budgets
    cleanup_sns_topic
    cleanup_cost_optimization_hub
    cleanup_temporary_files
    validate_cleanup
    
    echo
    echo "=========================================="
    echo "CLEANUP COMPLETED"
    echo "=========================================="
    echo "Deployment ID: $DEPLOYMENT_ID"
    echo "Log File: $LOG_FILE"
    
    if [[ "$DISABLE_COH" == "true" ]]; then
        echo
        echo "NOTE: Cost Optimization Hub cannot be completely disabled via CLI."
        echo "Visit AWS Console -> Cost Management -> Cost Optimization Hub -> Settings"
        echo "to manage the service preferences."
    fi
    
    echo "=========================================="
    
    log "SUCCESS" "Cleanup completed successfully!"
}

# Run main function with all arguments
main "$@"