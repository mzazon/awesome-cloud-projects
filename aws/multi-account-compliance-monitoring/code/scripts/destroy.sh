#!/bin/bash

# =============================================================================
# AWS Cross-Account Compliance Monitoring Cleanup Script
# =============================================================================
# This script safely removes all resources created by the compliance monitoring
# deployment, including Security Hub configuration, Lambda functions, EventBridge
# rules, CloudTrail, S3 buckets, and IAM roles.
#
# Services: Systems Manager, Security Hub, CloudTrail, IAM, Lambda, EventBridge
# =============================================================================

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS CLI configuration
validate_aws_config() {
    log_info "Validating AWS CLI configuration..."
    
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Get current account and region
    CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    CURRENT_REGION=$(aws configure get region)
    
    if [[ -z "${CURRENT_REGION}" ]]; then
        log_error "No default region configured. Please set a default region."
        exit 1
    fi
    
    log_success "AWS CLI configured for account ${CURRENT_ACCOUNT} in region ${CURRENT_REGION}"
}

# Function to confirm destructive action
confirm_deletion() {
    echo ""
    log_warning "This script will DELETE all compliance monitoring resources in account ${CURRENT_ACCOUNT}"
    log_warning "This action is IRREVERSIBLE and will remove:"
    echo "  - Security Hub configuration and findings"
    echo "  - Lambda functions and EventBridge rules"
    echo "  - CloudTrail and S3 audit logs"
    echo "  - IAM roles and policies"
    echo "  - Systems Manager documents and associations"
    echo ""
    
    # Interactive confirmation
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [[ "${confirmation}" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource deletion..."
}

# Function to discover resources by tags and naming patterns
discover_resources() {
    log_info "Discovering compliance monitoring resources..."
    
    # Try to discover resources by common patterns
    LAMBDA_FUNCTIONS=($(aws lambda list-functions \
        --query "Functions[?contains(FunctionName, 'ComplianceAutomation')].FunctionName" \
        --output text 2>/dev/null || echo ""))
    
    EVENTBRIDGE_RULES=($(aws events list-rules \
        --query "Rules[?contains(Name, 'ComplianceMonitoring')].Name" \
        --output text 2>/dev/null || echo ""))
    
    CLOUDTRAILS=($(aws cloudtrail describe-trails \
        --query "trailList[?contains(Name, 'ComplianceAuditTrail')].Name" \
        --output text 2>/dev/null || echo ""))
    
    IAM_ROLES=($(aws iam list-roles \
        --query "Roles[?contains(RoleName, 'SecurityHubCompliance') || contains(RoleName, 'ComplianceProcessing')].RoleName" \
        --output text 2>/dev/null || echo ""))
    
    SSM_DOCUMENTS=($(aws ssm list-documents \
        --filters "Key=Name,Values=CustomComplianceCheck" \
        --query "DocumentIdentifiers[].Name" \
        --output text 2>/dev/null || echo ""))
    
    S3_BUCKETS=($(aws s3api list-buckets \
        --query "Buckets[?contains(Name, 'compliance-audit-trail')].Name" \
        --output text 2>/dev/null || echo ""))
    
    log_info "Discovery completed"
    log_info "Found ${#LAMBDA_FUNCTIONS[@]} Lambda functions, ${#EVENTBRIDGE_RULES[@]} EventBridge rules, ${#CLOUDTRAILS[@]} CloudTrails"
    log_info "Found ${#IAM_ROLES[@]} IAM roles, ${#SSM_DOCUMENTS[@]} SSM documents, ${#S3_BUCKETS[@]} S3 buckets"
}

# Function to remove EventBridge rules and Lambda functions
cleanup_eventbridge_lambda() {
    log_info "Removing EventBridge rules and Lambda functions..."
    
    # Remove EventBridge rules
    for rule in "${EVENTBRIDGE_RULES[@]}"; do
        if [[ -n "${rule}" ]]; then
            log_info "Removing EventBridge rule: ${rule}"
            
            # Remove targets first
            if aws events remove-targets \
                --rule "${rule}" \
                --ids "1" \
                >/dev/null 2>&1; then
                log_success "Removed targets from rule ${rule}"
            else
                log_warning "Could not remove targets from rule ${rule}"
            fi
            
            # Delete the rule
            if aws events delete-rule --name "${rule}" >/dev/null 2>&1; then
                log_success "Deleted EventBridge rule: ${rule}"
            else
                log_warning "Could not delete EventBridge rule: ${rule}"
            fi
        fi
    done
    
    # Remove Lambda functions
    for function_name in "${LAMBDA_FUNCTIONS[@]}"; do
        if [[ -n "${function_name}" ]]; then
            log_info "Removing Lambda function: ${function_name}"
            
            if aws lambda delete-function --function-name "${function_name}" >/dev/null 2>&1; then
                log_success "Deleted Lambda function: ${function_name}"
            else
                log_warning "Could not delete Lambda function: ${function_name}"
            fi
        fi
    done
}

# Function to remove Systems Manager documents and associations
cleanup_systems_manager() {
    log_info "Removing Systems Manager documents and associations..."
    
    # Remove SSM documents
    for document in "${SSM_DOCUMENTS[@]}"; do
        if [[ -n "${document}" ]]; then
            log_info "Removing SSM document: ${document}"
            
            if aws ssm delete-document --name "${document}" >/dev/null 2>&1; then
                log_success "Deleted SSM document: ${document}"
            else
                log_warning "Could not delete SSM document: ${document}"
            fi
        fi
    done
    
    # Remove compliance associations (by pattern)
    local associations
    associations=($(aws ssm list-associations \
        --query "Associations[?contains(Name, 'AWS-RunPatchBaseline') && contains(AssociationName, 'CompliancePatching')].AssociationId" \
        --output text 2>/dev/null || echo ""))
    
    for association_id in "${associations[@]}"; do
        if [[ -n "${association_id}" ]]; then
            log_info "Removing compliance association: ${association_id}"
            
            if aws ssm delete-association --association-id "${association_id}" >/dev/null 2>&1; then
                log_success "Deleted association: ${association_id}"
            else
                log_warning "Could not delete association: ${association_id}"
            fi
        fi
    done
}

# Function to disable Security Hub and remove member accounts
cleanup_security_hub() {
    log_info "Cleaning up Security Hub configuration..."
    
    # List and remove member accounts
    local member_accounts
    member_accounts=($(aws securityhub list-members \
        --query "Members[].AccountId" \
        --output text 2>/dev/null || echo ""))
    
    if [[ ${#member_accounts[@]} -gt 0 ]] && [[ -n "${member_accounts[0]}" ]]; then
        log_info "Removing ${#member_accounts[@]} member accounts from Security Hub"
        
        # Disassociate members
        if aws securityhub disassociate-members \
            --account-ids "${member_accounts[@]}" \
            >/dev/null 2>&1; then
            log_success "Disassociated member accounts"
        else
            log_warning "Could not disassociate member accounts"
        fi
        
        # Delete members
        if aws securityhub delete-members \
            --account-ids "${member_accounts[@]}" \
            >/dev/null 2>&1; then
            log_success "Deleted member accounts"
        else
            log_warning "Could not delete member accounts"
        fi
    fi
    
    # Disable import findings for Systems Manager
    if aws securityhub disable-import-findings-for-product \
        --product-arn "arn:aws:securityhub:${CURRENT_REGION}::product/aws/systems-manager" \
        >/dev/null 2>&1; then
        log_success "Disabled Systems Manager integration"
    else
        log_warning "Could not disable Systems Manager integration"
    fi
    
    # Disable Security Hub (only if explicitly requested)
    echo ""
    read -p "Do you want to completely disable Security Hub? This will remove ALL findings and configurations. (y/N): " disable_hub
    
    if [[ "${disable_hub}" =~ ^[Yy]$ ]]; then
        if aws securityhub disable-security-hub >/dev/null 2>&1; then
            log_success "Security Hub disabled"
        else
            log_warning "Could not disable Security Hub (may have dependencies)"
        fi
    else
        log_info "Security Hub left enabled"
    fi
}

# Function to remove CloudTrail and S3 buckets
cleanup_cloudtrail_s3() {
    log_info "Removing CloudTrail and S3 resources..."
    
    # Stop and delete CloudTrails
    for trail in "${CLOUDTRAILS[@]}"; do
        if [[ -n "${trail}" ]]; then
            log_info "Removing CloudTrail: ${trail}"
            
            # Stop logging
            if aws cloudtrail stop-logging --name "${trail}" >/dev/null 2>&1; then
                log_success "Stopped logging for CloudTrail: ${trail}"
            else
                log_warning "Could not stop logging for CloudTrail: ${trail}"
            fi
            
            # Delete trail
            if aws cloudtrail delete-trail --name "${trail}" >/dev/null 2>&1; then
                log_success "Deleted CloudTrail: ${trail}"
            else
                log_warning "Could not delete CloudTrail: ${trail}"
            fi
        fi
    done
    
    # Remove S3 buckets
    for bucket in "${S3_BUCKETS[@]}"; do
        if [[ -n "${bucket}" ]]; then
            log_info "Removing S3 bucket: ${bucket}"
            
            # Empty bucket first
            if aws s3 rm "s3://${bucket}" --recursive >/dev/null 2>&1; then
                log_success "Emptied S3 bucket: ${bucket}"
            else
                log_warning "Could not empty S3 bucket: ${bucket}"
            fi
            
            # Delete bucket
            if aws s3 rb "s3://${bucket}" >/dev/null 2>&1; then
                log_success "Deleted S3 bucket: ${bucket}"
            else
                log_warning "Could not delete S3 bucket: ${bucket}"
            fi
        fi
    done
}

# Function to remove IAM roles and policies
cleanup_iam_roles() {
    log_info "Removing IAM roles and policies..."
    
    for role in "${IAM_ROLES[@]}"; do
        if [[ -n "${role}" ]]; then
            log_info "Removing IAM role: ${role}"
            
            # List and delete attached policies
            local policies
            policies=($(aws iam list-role-policies \
                --role-name "${role}" \
                --query "PolicyNames" \
                --output text 2>/dev/null || echo ""))
            
            for policy in "${policies[@]}"; do
                if [[ -n "${policy}" ]]; then
                    if aws iam delete-role-policy \
                        --role-name "${role}" \
                        --policy-name "${policy}" \
                        >/dev/null 2>&1; then
                        log_success "Deleted policy ${policy} from role ${role}"
                    else
                        log_warning "Could not delete policy ${policy} from role ${role}"
                    fi
                fi
            done
            
            # Delete the role
            if aws iam delete-role --role-name "${role}" >/dev/null 2>&1; then
                log_success "Deleted IAM role: ${role}"
            else
                log_warning "Could not delete IAM role: ${role}"
            fi
        fi
    done
}

# Function to clean up Lambda permissions
cleanup_lambda_permissions() {
    log_info "Cleaning up Lambda permissions..."
    
    # This function removes any orphaned Lambda permissions that might remain
    for function_name in "${LAMBDA_FUNCTIONS[@]}"; do
        if [[ -n "${function_name}" ]]; then
            # Try to remove the EventBridge permission (may fail if already removed)
            aws lambda remove-permission \
                --function-name "${function_name}" \
                --statement-id ComplianceEventBridgePermission \
                >/dev/null 2>&1 || true
        fi
    done
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check for remaining Lambda functions
    local remaining_lambdas
    remaining_lambdas=$(aws lambda list-functions \
        --query "Functions[?contains(FunctionName, 'ComplianceAutomation')].FunctionName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${remaining_lambdas}" ]]; then
        log_warning "Remaining Lambda functions: ${remaining_lambdas}"
        ((cleanup_issues++))
    fi
    
    # Check for remaining EventBridge rules
    local remaining_rules
    remaining_rules=$(aws events list-rules \
        --query "Rules[?contains(Name, 'ComplianceMonitoring')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${remaining_rules}" ]]; then
        log_warning "Remaining EventBridge rules: ${remaining_rules}"
        ((cleanup_issues++))
    fi
    
    # Check for remaining CloudTrails
    local remaining_trails
    remaining_trails=$(aws cloudtrail describe-trails \
        --query "trailList[?contains(Name, 'ComplianceAuditTrail')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${remaining_trails}" ]]; then
        log_warning "Remaining CloudTrails: ${remaining_trails}"
        ((cleanup_issues++))
    fi
    
    # Check for remaining IAM roles
    local remaining_roles
    remaining_roles=$(aws iam list-roles \
        --query "Roles[?contains(RoleName, 'SecurityHubCompliance') || contains(RoleName, 'ComplianceProcessing')].RoleName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${remaining_roles}" ]]; then
        log_warning "Remaining IAM roles: ${remaining_roles}"
        ((cleanup_issues++))
    fi
    
    # Check for remaining S3 buckets
    local remaining_buckets
    remaining_buckets=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, 'compliance-audit-trail')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${remaining_buckets}" ]]; then
        log_warning "Remaining S3 buckets: ${remaining_buckets}"
        ((cleanup_issues++))
    fi
    
    if [[ "${cleanup_issues}" -eq 0 ]]; then
        log_success "Cleanup verification passed - no compliance monitoring resources found"
    else
        log_warning "Cleanup verification found ${cleanup_issues} issues - manual cleanup may be required"
        log_info "Some resources may need to be removed manually due to dependencies"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary"
    echo "==============="
    echo "Account: ${CURRENT_ACCOUNT}"
    echo "Region: ${CURRENT_REGION}"
    echo ""
    echo "Resources processed:"
    echo "- Lambda functions: ${#LAMBDA_FUNCTIONS[@]}"
    echo "- EventBridge rules: ${#EVENTBRIDGE_RULES[@]}"
    echo "- CloudTrails: ${#CLOUDTRAILS[@]}"
    echo "- IAM roles: ${#IAM_ROLES[@]}"
    echo "- SSM documents: ${#SSM_DOCUMENTS[@]}"
    echo "- S3 buckets: ${#S3_BUCKETS[@]}"
    echo ""
    echo "Note: Security Hub may still be enabled if you chose to keep it"
    echo "Note: Some AWS Config rules and other dependencies may require manual cleanup"
}

# Function to handle cleanup errors gracefully
cleanup_with_error_handling() {
    local cleanup_function=$1
    local description=$2
    
    log_info "Starting: ${description}"
    
    if ${cleanup_function}; then
        log_success "Completed: ${description}"
    else
        log_warning "Issues encountered during: ${description}"
        log_info "Continuing with remaining cleanup tasks..."
    fi
}

# Main cleanup function
main() {
    log_info "Starting AWS Cross-Account Compliance Monitoring cleanup..."
    echo "============================================================"
    
    # Validate prerequisites
    validate_aws_config
    
    # Confirm destructive action
    confirm_deletion
    
    # Discover resources to be cleaned up
    discover_resources
    
    # Perform cleanup in reverse order of creation
    cleanup_with_error_handling cleanup_eventbridge_lambda "EventBridge rules and Lambda functions"
    cleanup_with_error_handling cleanup_lambda_permissions "Lambda permissions"
    cleanup_with_error_handling cleanup_systems_manager "Systems Manager documents and associations"
    cleanup_with_error_handling cleanup_security_hub "Security Hub configuration"
    cleanup_with_error_handling cleanup_cloudtrail_s3 "CloudTrail and S3 resources"
    cleanup_with_error_handling cleanup_iam_roles "IAM roles and policies"
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    display_cleanup_summary
    
    log_success "AWS Cross-Account Compliance Monitoring cleanup completed!"
    log_info "If you encounter any issues, check the AWS Console for remaining resources"
}

# Handle script interruption
cleanup_on_signal() {
    log_warning "Cleanup script interrupted. Some resources may not have been cleaned up."
    exit 1
}

trap cleanup_on_signal SIGINT SIGTERM

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi