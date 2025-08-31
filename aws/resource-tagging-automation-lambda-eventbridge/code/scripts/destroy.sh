#!/bin/bash

##############################################################################
# AWS Resource Tagging Automation Cleanup Script
# 
# This script removes all resources created by the deploy.sh script:
# - EventBridge rule and targets
# - Lambda function
# - IAM role and policies
# - Resource Group
# - Test resources (if any)
#
# CAUTION: This will permanently delete all created resources
##############################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid. Run 'aws configure' first."
    fi
    
    success "Prerequisites check passed"
}

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    if [[ -f "deployment-info.json" ]]; then
        export AWS_REGION=$(jq -r '.aws_region // empty' deployment-info.json)
        export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id // empty' deployment-info.json)
        export LAMBDA_FUNCTION_NAME=$(jq -r '.resources.lambda_function_name // empty' deployment-info.json)
        export IAM_ROLE_NAME=$(jq -r '.resources.iam_role_name // empty' deployment-info.json)
        export EVENTBRIDGE_RULE_NAME=$(jq -r '.resources.eventbridge_rule_name // empty' deployment-info.json)
        export RESOURCE_GROUP_NAME=$(jq -r '.resources.resource_group_name // empty' deployment-info.json)
        
        success "Deployment information loaded from deployment-info.json"
    else
        warning "deployment-info.json not found. You'll need to provide resource names manually."
        prompt_for_resource_names
    fi
    
    # Fallback to current AWS configuration if not set
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            export AWS_REGION="us-east-1"
        fi
    fi
    
    if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    log "AWS Region: ${AWS_REGION}"
    log "AWS Account: ${AWS_ACCOUNT_ID}"
}

# Prompt for resource names if deployment-info.json is not available
prompt_for_resource_names() {
    echo ""
    echo -e "${YELLOW}Please provide the resource names created during deployment:${NC}"
    echo ""
    
    read -p "Lambda Function Name: " LAMBDA_FUNCTION_NAME
    read -p "IAM Role Name: " IAM_ROLE_NAME
    read -p "EventBridge Rule Name: " EVENTBRIDGE_RULE_NAME
    read -p "Resource Group Name: " RESOURCE_GROUP_NAME
    
    # Export variables
    export LAMBDA_FUNCTION_NAME
    export IAM_ROLE_NAME
    export EVENTBRIDGE_RULE_NAME
    export RESOURCE_GROUP_NAME
}

# Confirm destruction
confirm_destruction() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo -e "${RED}⚠️  DESTRUCTIVE OPERATION WARNING ⚠️${NC}"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    echo "This script will permanently delete the following resources:"
    echo ""
    echo -e "${YELLOW}Resources to be deleted:${NC}"
    echo "  • Lambda Function: ${LAMBDA_FUNCTION_NAME:-'Not specified'}"
    echo "  • EventBridge Rule: ${EVENTBRIDGE_RULE_NAME:-'Not specified'}"
    echo "  • IAM Role: ${IAM_ROLE_NAME:-'Not specified'}"
    echo "  • Resource Group: ${RESOURCE_GROUP_NAME:-'Not specified'}"
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    
    # Multiple confirmation prompts for safety
    read -p "Are you sure you want to delete these resources? (yes/no): " confirm1
    if [[ "$confirm1" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    read -p "Type 'DELETE' to confirm permanent deletion: " confirm2
    if [[ "$confirm2" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed. Proceeding with cleanup..."
}

# Find and remove test resources
cleanup_test_resources() {
    log "Cleaning up test resources..."
    
    # Find EC2 instances with AutoTagged=true
    INSTANCE_IDS=$(aws ec2 describe-instances \
        --filters "Name=tag:AutoTagged,Values=true" "Name=instance-state-name,Values=running,stopped" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$INSTANCE_IDS" ]]; then
        log "Found test EC2 instances: $INSTANCE_IDS"
        read -p "Delete these test EC2 instances? (yes/no): " delete_instances
        if [[ "$delete_instances" == "yes" ]]; then
            aws ec2 terminate-instances --instance-ids $INSTANCE_IDS &>/dev/null || true
            success "Test EC2 instances terminated"
        fi
    fi
    
    # Find S3 buckets with AutoTagged=true (this is more complex and risky)
    warning "Skipping S3 bucket cleanup - please manually review and delete test buckets if needed"
    
    success "Test resource cleanup completed"
}

# Remove Resource Group
remove_resource_group() {
    log "Removing Resource Group..."
    
    if [[ -n "${RESOURCE_GROUP_NAME:-}" ]]; then
        # Check if resource group exists
        if aws resource-groups get-group --group-name ${RESOURCE_GROUP_NAME} &>/dev/null; then
            aws resource-groups delete-group --group-name ${RESOURCE_GROUP_NAME} &>/dev/null || {
                warning "Failed to delete resource group ${RESOURCE_GROUP_NAME}"
                return 1
            }
            success "Resource Group deleted: ${RESOURCE_GROUP_NAME}"
        else
            warning "Resource Group ${RESOURCE_GROUP_NAME} not found"
        fi
    else
        warning "Resource Group name not specified, skipping"
    fi
}

# Remove EventBridge rule and targets
remove_eventbridge_resources() {
    log "Removing EventBridge rule and targets..."
    
    if [[ -n "${EVENTBRIDGE_RULE_NAME:-}" ]]; then
        # Check if rule exists
        if aws events describe-rule --name ${EVENTBRIDGE_RULE_NAME} &>/dev/null; then
            # Remove targets first
            TARGET_IDS=$(aws events list-targets-by-rule \
                --rule ${EVENTBRIDGE_RULE_NAME} \
                --query 'Targets[*].Id' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$TARGET_IDS" ]]; then
                aws events remove-targets \
                    --rule ${EVENTBRIDGE_RULE_NAME} \
                    --ids $TARGET_IDS &>/dev/null || {
                    warning "Failed to remove EventBridge targets"
                }
                success "EventBridge targets removed"
            fi
            
            # Delete the rule
            aws events delete-rule --name ${EVENTBRIDGE_RULE_NAME} &>/dev/null || {
                warning "Failed to delete EventBridge rule ${EVENTBRIDGE_RULE_NAME}"
                return 1
            }
            success "EventBridge rule deleted: ${EVENTBRIDGE_RULE_NAME}"
        else
            warning "EventBridge rule ${EVENTBRIDGE_RULE_NAME} not found"
        fi
    else
        warning "EventBridge rule name not specified, skipping"
    fi
}

# Remove Lambda function
remove_lambda_function() {
    log "Removing Lambda function..."
    
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        # Check if function exists
        if aws lambda get-function --function-name ${LAMBDA_FUNCTION_NAME} &>/dev/null; then
            # Remove EventBridge permission first
            aws lambda remove-permission \
                --function-name ${LAMBDA_FUNCTION_NAME} \
                --statement-id allow-eventbridge &>/dev/null || {
                warning "Failed to remove Lambda permission (may not exist)"
            }
            
            # Delete the function
            aws lambda delete-function --function-name ${LAMBDA_FUNCTION_NAME} &>/dev/null || {
                warning "Failed to delete Lambda function ${LAMBDA_FUNCTION_NAME}"
                return 1
            }
            success "Lambda function deleted: ${LAMBDA_FUNCTION_NAME}"
        else
            warning "Lambda function ${LAMBDA_FUNCTION_NAME} not found"
        fi
    else
        warning "Lambda function name not specified, skipping"
    fi
}

# Remove IAM role and policies
remove_iam_resources() {
    log "Removing IAM role and policies..."
    
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        # Check if role exists
        if aws iam get-role --role-name ${IAM_ROLE_NAME} &>/dev/null; then
            # Remove inline policies
            POLICY_NAMES=$(aws iam list-role-policies \
                --role-name ${IAM_ROLE_NAME} \
                --query 'PolicyNames' \
                --output text 2>/dev/null || echo "")
            
            for policy in $POLICY_NAMES; do
                aws iam delete-role-policy \
                    --role-name ${IAM_ROLE_NAME} \
                    --policy-name $policy &>/dev/null || {
                    warning "Failed to delete policy $policy"
                }
            done
            
            # Remove attached managed policies
            ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
                --role-name ${IAM_ROLE_NAME} \
                --query 'AttachedPolicies[*].PolicyArn' \
                --output text 2>/dev/null || echo "")
            
            for policy_arn in $ATTACHED_POLICIES; do
                aws iam detach-role-policy \
                    --role-name ${IAM_ROLE_NAME} \
                    --policy-arn $policy_arn &>/dev/null || {
                    warning "Failed to detach policy $policy_arn"
                }
            done
            
            # Delete the role
            aws iam delete-role --role-name ${IAM_ROLE_NAME} &>/dev/null || {
                warning "Failed to delete IAM role ${IAM_ROLE_NAME}"
                return 1
            }
            success "IAM role deleted: ${IAM_ROLE_NAME}"
        else
            warning "IAM role ${IAM_ROLE_NAME} not found"
        fi
    else
        warning "IAM role name not specified, skipping"
    fi
}

# Remove CloudWatch log groups
remove_cloudwatch_logs() {
    log "Removing CloudWatch log groups..."
    
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        LOG_GROUP_NAME="/aws/lambda/${LAMBDA_FUNCTION_NAME}"
        
        # Check if log group exists
        if aws logs describe-log-groups --log-group-name-prefix ${LOG_GROUP_NAME} --query 'logGroups' --output text | grep -q ${LOG_GROUP_NAME}; then
            aws logs delete-log-group --log-group-name ${LOG_GROUP_NAME} &>/dev/null || {
                warning "Failed to delete CloudWatch log group ${LOG_GROUP_NAME}"
                return 1
            }
            success "CloudWatch log group deleted: ${LOG_GROUP_NAME}"
        else
            warning "CloudWatch log group ${LOG_GROUP_NAME} not found"
        fi
    else
        warning "Lambda function name not specified, skipping log group cleanup"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment files
    local files_to_remove=(
        "deployment-info.json"
        "trust-policy.json"
        "tagging-policy.json"
        "event-pattern.json"
        "resource-group-query.json"
        "lambda_function.py"
        "lambda-deployment.zip"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "Removed: $file"
        fi
    done
    
    # Remove deployment logs
    if ls deployment-*.log 1> /dev/null 2>&1; then
        read -p "Remove deployment log files? (yes/no): " remove_logs
        if [[ "$remove_logs" == "yes" ]]; then
            rm -f deployment-*.log
            success "Deployment logs removed"
        fi
    fi
    
    success "Local files cleaned up"
}

# Display final summary
display_cleanup_summary() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo -e "${GREEN}🧹 AWS Resource Tagging Automation Cleanup Complete!${NC}"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    echo -e "${BLUE}📋 Resources Removed:${NC}"
    echo "  • Lambda Function: ${LAMBDA_FUNCTION_NAME:-'N/A'}"
    echo "  • EventBridge Rule: ${EVENTBRIDGE_RULE_NAME:-'N/A'}"
    echo "  • IAM Role: ${IAM_ROLE_NAME:-'N/A'}"
    echo "  • Resource Group: ${RESOURCE_GROUP_NAME:-'N/A'}"
    echo "  • CloudWatch Logs: /aws/lambda/${LAMBDA_FUNCTION_NAME:-'N/A'}"
    echo ""
    echo -e "${BLUE}🔍 Post-Cleanup Actions:${NC}"
    echo "  1. Verify resources are deleted in AWS Console"
    echo "  2. Check AWS Cost Explorer for any remaining charges"
    echo "  3. Review CloudTrail logs if needed"
    echo ""
    echo -e "${YELLOW}⚠️  Manual Review Recommended:${NC}"
    echo "  • Check for any remaining test resources with AutoTagged=true"
    echo "  • Verify S3 buckets created during testing"
    echo "  • Review any custom tags that were applied"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
}

# Main cleanup function
main() {
    echo "🧹 Starting AWS Resource Tagging Automation Cleanup..."
    echo ""
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_info
    confirm_destruction
    
    log "Beginning resource cleanup..."
    
    # Clean up in reverse order of creation
    cleanup_test_resources
    remove_resource_group
    remove_eventbridge_resources
    remove_lambda_function
    remove_cloudwatch_logs
    remove_iam_resources
    cleanup_local_files
    
    display_cleanup_summary
    
    echo ""
    success "Cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Script interrupted. Some resources may not have been cleaned up."' INT TERM

# Check if running as source or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi