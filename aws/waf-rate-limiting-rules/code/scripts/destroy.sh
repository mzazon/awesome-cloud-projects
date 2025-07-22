#!/bin/bash

# Cleanup AWS WAF with Rate Limiting Rules
# This script removes all resources created by the WAF deployment

set -e  # Exit on any error

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

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' or set environment variables."
    fi
    
    success "Prerequisites check completed"
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    if [ -f ".waf_deployment_state" ]; then
        source .waf_deployment_state
        log "Loaded deployment state from .waf_deployment_state"
        log "  WAF_WEB_ACL_NAME: ${WAF_WEB_ACL_NAME}"
        log "  WEB_ACL_ARN: ${WEB_ACL_ARN}"
        log "  DASHBOARD_NAME: ${DASHBOARD_NAME}"
        log "  LOG_GROUP_NAME: ${LOG_GROUP_NAME}"
        success "Deployment state loaded successfully"
    else
        warning "No deployment state file found (.waf_deployment_state)"
        warning "You may need to provide resource names manually"
        prompt_for_resources
    fi
}

# Function to prompt for resource names if state file not found
prompt_for_resources() {
    log "Please provide the resource names to clean up:"
    
    read -p "WAF Web ACL Name: " WAF_WEB_ACL_NAME
    read -p "CloudWatch Dashboard Name: " DASHBOARD_NAME
    read -p "AWS Region (default: us-east-1): " AWS_REGION
    
    AWS_REGION=${AWS_REGION:-us-east-1}
    LOG_GROUP_NAME="/aws/wafv2/security-logs"
    
    # Get Web ACL ARN
    WEB_ACL_ARN=$(aws wafv2 list-web-acls \
        --scope CLOUDFRONT \
        --region us-east-1 \
        --query "WebACLs[?Name=='${WAF_WEB_ACL_NAME}'].ARN" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$WEB_ACL_ARN" ]; then
        warning "Could not find Web ACL with name: ${WAF_WEB_ACL_NAME}"
        log "Available Web ACLs:"
        aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 --query 'WebACLs[*].Name' --output table
    fi
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    echo "=========================================="
    echo "     RESOURCE DELETION CONFIRMATION"
    echo "=========================================="
    echo ""
    echo "The following resources will be PERMANENTLY DELETED:"
    echo ""
    echo "  • WAF Web ACL: ${WAF_WEB_ACL_NAME}"
    echo "  • WAF Logging Configuration"
    echo "  • CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo "  • CloudWatch Log Group: ${LOG_GROUP_NAME}"
    echo ""
    echo "⚠️  WARNING: This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " CONFIRM
    
    if [[ "$CONFIRM" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Deletion confirmed, proceeding with cleanup..."
}

# Function to disable WAF logging
disable_logging() {
    log "Disabling WAF logging configuration..."
    
    if [ -n "$WEB_ACL_ARN" ]; then
        # Check if logging configuration exists
        if aws wafv2 get-logging-configuration --resource-arn ${WEB_ACL_ARN} --region us-east-1 &>/dev/null; then
            aws wafv2 delete-logging-configuration \
                --resource-arn ${WEB_ACL_ARN} \
                --region us-east-1
            success "WAF logging configuration removed"
        else
            warning "No logging configuration found for Web ACL"
        fi
    else
        warning "Web ACL ARN not available, skipping logging configuration removal"
    fi
}

# Function to delete CloudWatch dashboard
delete_dashboard() {
    log "Deleting CloudWatch dashboard..."
    
    if [ -n "$DASHBOARD_NAME" ]; then
        # Check if dashboard exists
        if aws cloudwatch get-dashboard --dashboard-name "${DASHBOARD_NAME}" --region ${AWS_REGION} &>/dev/null; then
            aws cloudwatch delete-dashboards \
                --dashboard-names "${DASHBOARD_NAME}" \
                --region ${AWS_REGION}
            success "CloudWatch dashboard deleted: ${DASHBOARD_NAME}"
        else
            warning "Dashboard ${DASHBOARD_NAME} not found"
        fi
    else
        warning "Dashboard name not provided, skipping dashboard deletion"
    fi
}

# Function to delete WAF Web ACL
delete_web_acl() {
    log "Deleting WAF Web ACL and all associated rules..."
    
    if [ -n "$WEB_ACL_ARN" ] && [ -n "$WAF_WEB_ACL_NAME" ]; then
        # Get current lock token
        LOCK_TOKEN=$(aws wafv2 get-web-acl \
            --id $(echo ${WEB_ACL_ARN} | cut -d'/' -f3) \
            --scope CLOUDFRONT \
            --region us-east-1 \
            --query 'LockToken' --output text 2>/dev/null || echo "")
        
        if [ -n "$LOCK_TOKEN" ]; then
            # Check if Web ACL is associated with any resources
            log "Checking for Web ACL associations..."
            ASSOCIATIONS=$(aws wafv2 list-resources-for-web-acl \
                --web-acl-arn ${WEB_ACL_ARN} \
                --resource-type CLOUDFRONT \
                --region us-east-1 \
                --query 'ResourceArns' --output text 2>/dev/null || echo "")
            
            if [ -n "$ASSOCIATIONS" ] && [ "$ASSOCIATIONS" != "None" ]; then
                warning "Web ACL is still associated with the following resources:"
                echo "$ASSOCIATIONS"
                warning "Please disassociate the Web ACL from these resources before deletion"
                warning "Use: aws cloudfront update-distribution to remove Web ACL association"
                error "Cannot delete Web ACL while it's still associated with resources"
            fi
            
            # Delete the Web ACL
            aws wafv2 delete-web-acl \
                --id $(echo ${WEB_ACL_ARN} | cut -d'/' -f3) \
                --scope CLOUDFRONT \
                --lock-token ${LOCK_TOKEN} \
                --region us-east-1
            success "WAF Web ACL and all rules deleted: ${WAF_WEB_ACL_NAME}"
        else
            warning "Could not get lock token for Web ACL, it may already be deleted"
        fi
    else
        warning "Web ACL information not available, checking for existing Web ACLs..."
        
        # List any remaining Web ACLs
        EXISTING_ACLS=$(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 --query 'WebACLs[*].Name' --output text)
        if [ -n "$EXISTING_ACLS" ]; then
            warning "Found existing Web ACLs that may need manual cleanup:"
            echo "$EXISTING_ACLS"
        else
            success "No Web ACLs found in the account"
        fi
    fi
}

# Function to delete CloudWatch log group
delete_log_group() {
    log "Deleting CloudWatch log group..."
    
    if [ -n "$LOG_GROUP_NAME" ]; then
        # Check if log group exists
        if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" --region ${AWS_REGION} --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "${LOG_GROUP_NAME}"; then
            # Check if log group has any log streams
            LOG_STREAMS=$(aws logs describe-log-streams \
                --log-group-name "${LOG_GROUP_NAME}" \
                --region ${AWS_REGION} \
                --query 'logStreams[*].logStreamName' --output text 2>/dev/null || echo "")
            
            if [ -n "$LOG_STREAMS" ]; then
                warning "Log group contains log streams with data"
                read -p "Do you want to delete the log group and all its data? (yes/no): " DELETE_LOGS
                if [[ "$DELETE_LOGS" != "yes" ]]; then
                    warning "Skipping log group deletion as requested"
                    return
                fi
            fi
            
            aws logs delete-log-group \
                --log-group-name "${LOG_GROUP_NAME}" \
                --region ${AWS_REGION}
            success "CloudWatch log group deleted: ${LOG_GROUP_NAME}"
        else
            warning "Log group ${LOG_GROUP_NAME} not found"
        fi
    else
        warning "Log group name not provided, skipping log group deletion"
    fi
}

# Function to clean up deployment state file
cleanup_state_file() {
    log "Cleaning up deployment state file..."
    
    if [ -f ".waf_deployment_state" ]; then
        rm -f .waf_deployment_state
        success "Deployment state file removed"
    else
        warning "No deployment state file found"
    fi
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating resource cleanup..."
    
    # Check for remaining Web ACLs
    REMAINING_ACLS=$(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 --query 'WebACLs[*].Name' --output text 2>/dev/null || echo "")
    if [ -n "$REMAINING_ACLS" ]; then
        warning "Some Web ACLs still exist:"
        echo "$REMAINING_ACLS"
    else
        success "No Web ACLs found - cleanup appears successful"
    fi
    
    # Check for log group
    if [ -n "$LOG_GROUP_NAME" ]; then
        if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" --region ${AWS_REGION} --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "${LOG_GROUP_NAME}"; then
            warning "Log group ${LOG_GROUP_NAME} still exists"
        else
            success "Log group successfully deleted"
        fi
    fi
    
    # Check for dashboard
    if [ -n "$DASHBOARD_NAME" ]; then
        if aws cloudwatch get-dashboard --dashboard-name "${DASHBOARD_NAME}" --region ${AWS_REGION} &>/dev/null; then
            warning "Dashboard ${DASHBOARD_NAME} still exists"
        else
            success "Dashboard successfully deleted"
        fi
    fi
    
    success "Cleanup validation completed"
}

# Function to display cleanup summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "     AWS WAF CLEANUP COMPLETED"
    echo "=========================================="
    echo ""
    echo "Resources Cleaned Up:"
    echo "  • WAF Web ACL and all rules"
    echo "  • WAF logging configuration"
    echo "  • CloudWatch dashboard"
    echo "  • CloudWatch log group (if confirmed)"
    echo "  • Deployment state file"
    echo ""
    echo "Notes:"
    echo "  • If the Web ACL was associated with CloudFront distributions"
    echo "    or ALBs, those associations have been preserved"
    echo "  • CloudWatch metrics data is retained per AWS retention policies"
    echo "  • No charges will occur for the deleted WAF resources"
    echo ""
    echo "If you need to recreate the WAF configuration, run: ./deploy.sh"
    echo "=========================================="
}

# Function to handle partial cleanup on error
cleanup_on_error() {
    error "Cleanup failed at line $LINENO. Some resources may still exist."
    log "You may need to manually check and clean up remaining resources:"
    log "  • Web ACLs: aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1"
    log "  • Dashboards: aws cloudwatch list-dashboards --region ${AWS_REGION}"
    log "  • Log groups: aws logs describe-log-groups --region ${AWS_REGION}"
}

# Main cleanup function
main() {
    echo "=========================================="
    echo "     AWS WAF Resource Cleanup"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    load_deployment_state
    confirm_deletion
    disable_logging
    delete_dashboard
    delete_web_acl
    delete_log_group
    cleanup_state_file
    validate_cleanup
    display_summary
}

# Trap errors and provide helpful messaging
trap 'cleanup_on_error' ERR

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi