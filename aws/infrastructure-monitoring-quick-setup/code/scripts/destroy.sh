#!/bin/bash

# AWS Infrastructure Monitoring Quick Setup - Cleanup Script
# This script removes all infrastructure created by the deployment script
# Based on the infrastructure-monitoring-quick-setup recipe

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 could not be found. Please install $1 and try again."
        exit 1
    fi
}

# Function to check AWS CLI authentication
check_aws_auth() {
    log "Checking AWS CLI authentication..."
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        log "Please run 'aws configure' or set AWS credentials and try again."
        exit 1
    fi
    log_success "AWS CLI authentication verified"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [[ -f ".env" ]]; then
        source .env
        log_success "Environment loaded from .env file"
        log "Region: ${AWS_REGION:-not set}, Account: ${AWS_ACCOUNT_ID:-not set}, Suffix: ${RANDOM_SUFFIX:-not set}"
    else
        log_warning ".env file not found. Attempting to detect resources..."
        
        # Try to get current AWS configuration
        export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
        
        # We'll need to scan for resources if RANDOM_SUFFIX is not available
        if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
            log_warning "RANDOM_SUFFIX not available. Will attempt to identify resources by pattern."
            export RANDOM_SUFFIX=""
        fi
    fi
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo "This script will permanently delete the following AWS resources:"
    echo "- CloudWatch Alarms and Dashboards"
    echo "- Systems Manager Associations"
    echo "- CloudWatch Log Groups (including all log data)"
    echo "- SSM Parameters"
    echo "- IAM Roles and Policies"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        echo "Resources with suffix: $RANDOM_SUFFIX"
    else
        echo "Will attempt to find and delete matching resources by pattern"
    fi
    
    echo ""
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " -r
    echo
    
    if [[ "$REPLY" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource cleanup..."
}

# Function to get resource suffix if not available
detect_resources() {
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        log "Attempting to detect resource suffix..."
        
        # Try to find IAM role with our pattern
        local roles
        roles=$(aws iam list-roles --query 'Roles[?starts_with(RoleName, `SSMServiceRole-`)].RoleName' --output text 2>/dev/null || echo "")
        
        if [[ -n "$roles" ]]; then
            # Extract suffix from first matching role
            RANDOM_SUFFIX=$(echo "$roles" | head -n1 | sed 's/SSMServiceRole-//')
            log_success "Detected resource suffix: $RANDOM_SUFFIX"
            export RANDOM_SUFFIX
        else
            log_warning "Could not detect resource suffix. Will try to clean up by pattern matching."
        fi
    fi
}

# Function to delete CloudWatch alarms
delete_alarms() {
    log "Removing CloudWatch alarms..."
    
    local alarm_names=()
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        alarm_names=("High-CPU-Utilization-${RANDOM_SUFFIX}" "High-Disk-Usage-${RANDOM_SUFFIX}")
    else
        # Try to find alarms by pattern
        mapfile -t alarm_names < <(aws cloudwatch describe-alarms \
            --query 'MetricAlarms[?starts_with(AlarmName, `High-CPU-Utilization-`) || starts_with(AlarmName, `High-Disk-Usage-`)].AlarmName' \
            --output text 2>/dev/null | tr '\t' '\n' | grep -v '^$' || echo "")
    fi
    
    if [[ ${#alarm_names[@]} -gt 0 && -n "${alarm_names[0]}" ]]; then
        aws cloudwatch delete-alarms --alarm-names "${alarm_names[@]}" 2>/dev/null || log_warning "Some alarms may not exist"
        log_success "CloudWatch alarms deleted: ${alarm_names[*]}"
    else
        log_warning "No matching CloudWatch alarms found"
    fi
}

# Function to delete CloudWatch dashboard
delete_dashboard() {
    log "Removing CloudWatch dashboard..."
    
    local dashboard_name
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        dashboard_name="Infrastructure-Monitoring-${RANDOM_SUFFIX}"
    else
        # Try to find dashboard by pattern
        dashboard_name=$(aws cloudwatch list-dashboards \
            --query 'DashboardEntries[?starts_with(DashboardName, `Infrastructure-Monitoring-`)].DashboardName' \
            --output text 2>/dev/null | head -n1 || echo "")
    fi
    
    if [[ -n "$dashboard_name" ]]; then
        aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name" 2>/dev/null || log_warning "Dashboard may not exist"
        log_success "CloudWatch dashboard deleted: $dashboard_name"
    else
        log_warning "No matching CloudWatch dashboard found"
    fi
}

# Function to delete Systems Manager associations
delete_associations() {
    log "Removing Systems Manager associations..."
    
    local association_names=()
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        association_names=("Daily-Inventory-Collection-${RANDOM_SUFFIX}" "Weekly-Patch-Scanning-${RANDOM_SUFFIX}")
    else
        # Try to find associations by pattern
        mapfile -t association_names < <(aws ssm describe-associations \
            --query 'Associations[?starts_with(AssociationName, `Daily-Inventory-Collection-`) || starts_with(AssociationName, `Weekly-Patch-Scanning-`)].AssociationName' \
            --output text 2>/dev/null | tr '\t' '\n' | grep -v '^$' || echo "")
    fi
    
    for assoc_name in "${association_names[@]}"; do
        if [[ -n "$assoc_name" ]]; then
            local assoc_id
            assoc_id=$(aws ssm describe-associations \
                --association-filter-list "key=AssociationName,value=$assoc_name" \
                --query 'Associations[0].AssociationId' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$assoc_id" && "$assoc_id" != "None" ]]; then
                aws ssm delete-association --association-id "$assoc_id" 2>/dev/null || log_warning "Association $assoc_name may not exist"
                log_success "Systems Manager association deleted: $assoc_name"
            fi
        fi
    done
    
    if [[ ${#association_names[@]} -eq 0 || -z "${association_names[0]}" ]]; then
        log_warning "No matching Systems Manager associations found"
    fi
}

# Function to delete CloudWatch log groups
delete_log_groups() {
    log "Removing CloudWatch log groups..."
    
    local log_groups=()
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        log_groups=("/aws/systems-manager/infrastructure-${RANDOM_SUFFIX}" "/aws/ec2/application-logs-${RANDOM_SUFFIX}")
    else
        # Try to find log groups by pattern
        mapfile -t log_groups < <(aws logs describe-log-groups \
            --query 'logGroups[?starts_with(logGroupName, `/aws/systems-manager/infrastructure-`) || starts_with(logGroupName, `/aws/ec2/application-logs-`)].logGroupName' \
            --output text 2>/dev/null | tr '\t' '\n' | grep -v '^$' || echo "")
    fi
    
    for log_group in "${log_groups[@]}"; do
        if [[ -n "$log_group" ]]; then
            aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || log_warning "Log group $log_group may not exist"
            log_success "CloudWatch log group deleted: $log_group"
        fi
    done
    
    if [[ ${#log_groups[@]} -eq 0 || -z "${log_groups[0]}" ]]; then
        log_warning "No matching CloudWatch log groups found"
    fi
}

# Function to delete SSM parameters and IAM role
delete_parameters_and_role() {
    log "Removing SSM parameters and IAM resources..."
    
    # Delete CloudWatch Agent configuration
    local param_name
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        param_name="AmazonCloudWatch-Agent-Config-${RANDOM_SUFFIX}"
    else
        # Try to find parameter by pattern
        param_name=$(aws ssm describe-parameters \
            --query 'Parameters[?starts_with(Name, `AmazonCloudWatch-Agent-Config-`)].Name' \
            --output text 2>/dev/null | head -n1 || echo "")
    fi
    
    if [[ -n "$param_name" ]]; then
        aws ssm delete-parameter --name "$param_name" 2>/dev/null || log_warning "Parameter $param_name may not exist"
        log_success "SSM parameter deleted: $param_name"
    else
        log_warning "No matching SSM parameter found"
    fi
    
    # Delete IAM role
    local role_name
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        role_name="SSMServiceRole-${RANDOM_SUFFIX}"
    else
        # Try to find role by pattern
        role_name=$(aws iam list-roles \
            --query 'Roles[?starts_with(RoleName, `SSMServiceRole-`)].RoleName' \
            --output text 2>/dev/null | head -n1 || echo "")
    fi
    
    if [[ -n "$role_name" ]]; then
        # Detach policies from IAM role
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" 2>/dev/null || log_warning "Policy may not be attached"
        
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" 2>/dev/null || log_warning "Policy may not be attached"
        
        # Delete IAM role
        aws iam delete-role --role-name "$role_name" 2>/dev/null || log_warning "Role $role_name may not exist"
        
        log_success "IAM role and policies deleted: $role_name"
    else
        log_warning "No matching IAM role found"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local remaining_resources=0
    
    # Check for remaining alarms
    local alarms
    alarms=$(aws cloudwatch describe-alarms \
        --query 'MetricAlarms[?starts_with(AlarmName, `High-CPU-Utilization-`) || starts_with(AlarmName, `High-Disk-Usage-`)].AlarmName' \
        --output text 2>/dev/null | wc -w || echo 0)
    
    if [[ "$alarms" -gt 0 ]]; then
        log_warning "Found $alarms remaining CloudWatch alarms"
        remaining_resources=$((remaining_resources + alarms))
    fi
    
    # Check for remaining dashboards
    local dashboards
    dashboards=$(aws cloudwatch list-dashboards \
        --query 'DashboardEntries[?starts_with(DashboardName, `Infrastructure-Monitoring-`)].DashboardName' \
        --output text 2>/dev/null | wc -w || echo 0)
    
    if [[ "$dashboards" -gt 0 ]]; then
        log_warning "Found $dashboards remaining CloudWatch dashboards"
        remaining_resources=$((remaining_resources + dashboards))
    fi
    
    # Check for remaining IAM roles
    local roles
    roles=$(aws iam list-roles \
        --query 'Roles[?starts_with(RoleName, `SSMServiceRole-`)].RoleName' \
        --output text 2>/dev/null | wc -w || echo 0)
    
    if [[ "$roles" -gt 0 ]]; then
        log_warning "Found $roles remaining IAM roles"
        remaining_resources=$((remaining_resources + roles))
    fi
    
    if [[ "$remaining_resources" -eq 0 ]]; then
        log_success "All resources appear to have been cleaned up successfully"
    else
        log_warning "Some resources may still exist. Please check AWS Console for any remaining resources."
    fi
}

# Function to cleanup environment file
cleanup_environment() {
    if [[ -f ".env" ]]; then
        rm -f .env
        log_success "Environment file cleaned up"
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary:"
    echo "===================="
    echo "The following resource types were processed for deletion:"
    echo "- CloudWatch Alarms (CPU and Disk usage)"
    echo "- CloudWatch Dashboard (Infrastructure monitoring)"
    echo "- Systems Manager Associations (Inventory and Patch scanning)"
    echo "- CloudWatch Log Groups (System and application logs)"
    echo "- SSM Parameters (CloudWatch Agent configuration)"
    echo "- IAM Roles and Policy attachments (Systems Manager service role)"
    echo ""
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        echo "Resources with suffix '$RANDOM_SUFFIX' have been removed."
    else
        echo "Resources matching infrastructure monitoring patterns have been removed."
    fi
    echo ""
    echo "Please verify in the AWS Console that all resources have been properly cleaned up."
    echo "Some resources may take a few minutes to be fully removed from the console."
    echo "===================="
}

# Main cleanup function
main() {
    log "Starting AWS Infrastructure Monitoring cleanup..."
    
    # Check prerequisites
    check_command "aws"
    check_aws_auth
    
    # Load environment variables
    load_environment
    
    # Detect resources if suffix not available
    detect_resources
    
    # Confirm destruction
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_alarms
    delete_dashboard
    delete_associations
    delete_log_groups
    delete_parameters_and_role
    
    # Verify cleanup
    verify_cleanup
    
    # Cleanup environment file
    cleanup_environment
    
    # Display summary
    display_summary
    
    log_success "AWS Infrastructure Monitoring cleanup completed!"
}

# Error handling
trap 'log_error "Cleanup failed on line $LINENO. Check the error above."' ERR

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi