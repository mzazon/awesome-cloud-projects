#!/bin/bash

# WAF Rules Web Application Security - Cleanup Script
# This script safely removes all WAF resources created by the deployment script.

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to load deployment state
load_deployment_state() {
    local state_file="/tmp/waf_deployment_state.env"
    
    if [[ ! -f "$state_file" ]]; then
        log_error "Deployment state file not found: $state_file"
        log_error "Cannot proceed with automated cleanup."
        echo
        log_info "You can manually clean up resources or provide the following information:"
        echo "  - WAF Web ACL name"
        echo "  - CloudWatch Log Group name"
        echo "  - SNS Topic name"
        echo "  - CloudWatch alarm name"
        echo "  - IP Set name"
        echo "  - Regex Pattern Set name"
        echo "  - CloudWatch Dashboard name"
        exit 1
    fi
    
    log_info "Loading deployment state from: $state_file"
    source "$state_file"
    
    # Verify required variables are set
    local required_vars=(
        "AWS_REGION" "AWS_ACCOUNT_ID" "WAF_NAME" "LOG_GROUP_NAME"
        "CLOUDWATCH_ALARM_NAME" "IP_SET_NAME" "REGEX_SET_NAME"
        "SNS_TOPIC_NAME" "DASHBOARD_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable $var not found in state file."
            exit 1
        fi
    done
    
    log_success "Deployment state loaded successfully."
    log_info "Region: $AWS_REGION"
    log_info "WAF Name: $WAF_NAME"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    log_success "Prerequisites check completed."
}

# Function to confirm destructive action
confirm_destruction() {
    echo
    log_warning "This script will permanently delete the following AWS resources:"
    echo "  - WAF Web ACL: $WAF_NAME"
    echo "  - CloudWatch Log Group: $LOG_GROUP_NAME"
    echo "  - SNS Topic: $SNS_TOPIC_NAME"
    echo "  - CloudWatch Alarm: $CLOUDWATCH_ALARM_NAME"
    echo "  - CloudWatch Dashboard: $DASHBOARD_NAME"
    echo "  - IP Set: $IP_SET_NAME"
    echo "  - Regex Pattern Set: $REGEX_SET_NAME"
    echo "  - Any CloudFront associations"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    # Check if force flag is provided
    if [[ "${1:-}" == "--force" ]]; then
        log_warning "Force flag detected. Proceeding with cleanup..."
        return 0
    fi
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Function to remove WAF association from CloudFront
remove_cloudfront_association() {
    log_info "Checking for CloudFront associations..."
    
    # Check if distribution ID was saved during deployment
    if [[ -n "${CLOUDFRONT_DISTRIBUTION_ID:-}" ]]; then
        log_info "Removing WAF association from CloudFront distribution: $CLOUDFRONT_DISTRIBUTION_ID"
        
        # Verify distribution still exists
        if aws cloudfront get-distribution --id "$CLOUDFRONT_DISTRIBUTION_ID" &> /dev/null; then
            # Get current distribution config
            aws cloudfront get-distribution-config --id "$CLOUDFRONT_DISTRIBUTION_ID" \
                --query "DistributionConfig" > /tmp/cleanup-config.json
            
            # Remove WAF association
            jq '.WebACLId = ""' /tmp/cleanup-config.json > /tmp/cleanup-updated.json
            
            # Get current ETag
            local etag=$(aws cloudfront get-distribution-config --id "$CLOUDFRONT_DISTRIBUTION_ID" \
                --query "ETag" --output text)
            
            # Update distribution
            if aws cloudfront update-distribution \
                --id "$CLOUDFRONT_DISTRIBUTION_ID" \
                --distribution-config file:///tmp/cleanup-updated.json \
                --if-match "$etag" \
                --region "$AWS_REGION" &> /dev/null; then
                
                log_success "Removed WAF association from CloudFront distribution"
                
                # Wait for distribution to update
                log_info "Waiting for CloudFront distribution to update (this may take several minutes)..."
                local wait_count=0
                while [[ $wait_count -lt 30 ]]; do
                    local status=$(aws cloudfront get-distribution --id "$CLOUDFRONT_DISTRIBUTION_ID" \
                        --query "Distribution.Status" --output text)
                    
                    if [[ "$status" == "Deployed" ]]; then
                        log_success "CloudFront distribution updated successfully"
                        break
                    fi
                    
                    echo -n "."
                    sleep 10
                    ((wait_count++))
                done
                echo
                
                if [[ $wait_count -eq 30 ]]; then
                    log_warning "CloudFront distribution update is taking longer than expected"
                    log_warning "Proceeding with WAF cleanup, but the association may still exist"
                fi
            else
                log_warning "Failed to remove WAF association from CloudFront distribution"
                log_warning "You may need to manually remove the association before deleting the WAF"
            fi
            
            # Cleanup temp files
            rm -f /tmp/cleanup-config.json /tmp/cleanup-updated.json
        else
            log_warning "CloudFront distribution $CLOUDFRONT_DISTRIBUTION_ID not found"
        fi
    else
        log_info "No CloudFront distribution association found in state file"
        log_info "Checking for any existing associations..."
        
        # Check if WAF exists and get its ARN
        local waf_arn=""
        if aws wafv2 list-web-acls --scope CLOUDFRONT --region "$AWS_REGION" \
            --query "WebACLs[?Name=='$WAF_NAME']" --output text | grep -q "$WAF_NAME"; then
            waf_arn=$(aws wafv2 list-web-acls --scope CLOUDFRONT --region "$AWS_REGION" \
                --query "WebACLs[?Name=='$WAF_NAME'].ARN" --output text)
            
            log_warning "WAF exists but no CloudFront association tracking found"
            log_warning "Please manually remove any CloudFront associations before proceeding"
            log_warning "WAF ARN: $waf_arn"
            
            read -p "Have you removed all CloudFront associations? (y/n): " -r associations_removed
            
            if [[ ! $associations_removed =~ ^[Yy]$ ]]; then
                log_error "Please remove CloudFront associations manually and run the script again"
                exit 1
            fi
        fi
    fi
}

# Function to disable WAF logging
disable_waf_logging() {
    log_info "Disabling WAF logging..."
    
    local waf_arn=""
    if aws wafv2 list-web-acls --scope CLOUDFRONT --region "$AWS_REGION" \
        --query "WebACLs[?Name=='$WAF_NAME']" --output text | grep -q "$WAF_NAME"; then
        waf_arn=$(aws wafv2 list-web-acls --scope CLOUDFRONT --region "$AWS_REGION" \
            --query "WebACLs[?Name=='$WAF_NAME'].ARN" --output text)
        
        if aws wafv2 get-logging-configuration --resource-arn "$waf_arn" \
            --region "$AWS_REGION" &> /dev/null; then
            
            aws wafv2 delete-logging-configuration \
                --resource-arn "$waf_arn" \
                --region "$AWS_REGION"
            
            log_success "Disabled WAF logging"
        else
            log_info "WAF logging not configured or already disabled"
        fi
    else
        log_info "WAF not found, skipping logging cleanup"
    fi
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log_info "Deleting CloudWatch resources..."
    
    # Delete CloudWatch alarm
    if aws cloudwatch describe-alarms --alarm-names "$CLOUDWATCH_ALARM_NAME" \
        --region "$AWS_REGION" --query "MetricAlarms" --output text | grep -q "$CLOUDWATCH_ALARM_NAME"; then
        
        aws cloudwatch delete-alarms \
            --alarm-names "$CLOUDWATCH_ALARM_NAME" \
            --region "$AWS_REGION"
        
        log_success "Deleted CloudWatch alarm: $CLOUDWATCH_ALARM_NAME"
    else
        log_info "CloudWatch alarm not found or already deleted"
    fi
    
    # Delete CloudWatch dashboard
    if aws cloudwatch list-dashboards --region "$AWS_REGION" \
        --query "DashboardEntries[?DashboardName=='$DASHBOARD_NAME']" \
        --output text | grep -q "$DASHBOARD_NAME"; then
        
        aws cloudwatch delete-dashboards \
            --dashboard-names "$DASHBOARD_NAME" \
            --region "$AWS_REGION"
        
        log_success "Deleted CloudWatch dashboard: $DASHBOARD_NAME"
    else
        log_info "CloudWatch dashboard not found or already deleted"
    fi
}

# Function to delete SNS topic
delete_sns_topic() {
    log_info "Deleting SNS topic..."
    
    local sns_topic_arn="arn:aws:sns:$AWS_REGION:$AWS_ACCOUNT_ID:$SNS_TOPIC_NAME"
    
    if aws sns get-topic-attributes --topic-arn "$sns_topic_arn" &> /dev/null; then
        aws sns delete-topic \
            --topic-arn "$sns_topic_arn" \
            --region "$AWS_REGION"
        
        log_success "Deleted SNS topic: $sns_topic_arn"
    else
        log_info "SNS topic not found or already deleted"
    fi
}

# Function to delete IP Set
delete_ip_set() {
    log_info "Deleting IP Set..."
    
    if aws wafv2 list-ip-sets --scope CLOUDFRONT --region "$AWS_REGION" \
        --query "IPSets[?Name=='$IP_SET_NAME']" --output text | grep -q "$IP_SET_NAME"; then
        
        local ip_set_id=$(aws wafv2 list-ip-sets --scope CLOUDFRONT --region "$AWS_REGION" \
            --query "IPSets[?Name=='$IP_SET_NAME'].Id" --output text)
        
        local lock_token=$(aws wafv2 get-ip-set --scope CLOUDFRONT --id "$ip_set_id" \
            --region "$AWS_REGION" --query "LockToken" --output text)
        
        aws wafv2 delete-ip-set \
            --scope CLOUDFRONT \
            --id "$ip_set_id" \
            --lock-token "$lock_token" \
            --region "$AWS_REGION"
        
        log_success "Deleted IP Set: $IP_SET_NAME"
    else
        log_info "IP Set not found or already deleted"
    fi
}

# Function to delete Regex Pattern Set
delete_regex_pattern_set() {
    log_info "Deleting Regex Pattern Set..."
    
    if aws wafv2 list-regex-pattern-sets --scope CLOUDFRONT --region "$AWS_REGION" \
        --query "RegexPatternSets[?Name=='$REGEX_SET_NAME']" --output text | grep -q "$REGEX_SET_NAME"; then
        
        local regex_set_id=$(aws wafv2 list-regex-pattern-sets --scope CLOUDFRONT --region "$AWS_REGION" \
            --query "RegexPatternSets[?Name=='$REGEX_SET_NAME'].Id" --output text)
        
        local lock_token=$(aws wafv2 get-regex-pattern-set --scope CLOUDFRONT --id "$regex_set_id" \
            --region "$AWS_REGION" --query "LockToken" --output text)
        
        aws wafv2 delete-regex-pattern-set \
            --scope CLOUDFRONT \
            --id "$regex_set_id" \
            --lock-token "$lock_token" \
            --region "$AWS_REGION"
        
        log_success "Deleted Regex Pattern Set: $REGEX_SET_NAME"
    else
        log_info "Regex Pattern Set not found or already deleted"
    fi
}

# Function to delete WAF Web ACL
delete_waf_web_acl() {
    log_info "Deleting WAF Web ACL..."
    
    if aws wafv2 list-web-acls --scope CLOUDFRONT --region "$AWS_REGION" \
        --query "WebACLs[?Name=='$WAF_NAME']" --output text | grep -q "$WAF_NAME"; then
        
        local waf_id=$(aws wafv2 list-web-acls --scope CLOUDFRONT --region "$AWS_REGION" \
            --query "WebACLs[?Name=='$WAF_NAME'].Id" --output text)
        
        local lock_token=$(aws wafv2 get-web-acl --scope CLOUDFRONT --id "$waf_id" \
            --region "$AWS_REGION" --query "LockToken" --output text)
        
        aws wafv2 delete-web-acl \
            --scope CLOUDFRONT \
            --id "$waf_id" \
            --lock-token "$lock_token" \
            --region "$AWS_REGION"
        
        log_success "Deleted WAF Web ACL: $WAF_NAME"
    else
        log_info "WAF Web ACL not found or already deleted"
    fi
}

# Function to delete CloudWatch Log Group
delete_log_group() {
    log_info "Deleting CloudWatch Log Group..."
    
    if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" \
        --query "logGroups[?logGroupName=='$LOG_GROUP_NAME']" \
        --output text | grep -q "$LOG_GROUP_NAME"; then
        
        aws logs delete-log-group \
            --log-group-name "$LOG_GROUP_NAME" \
            --region "$AWS_REGION"
        
        log_success "Deleted CloudWatch Log Group: $LOG_GROUP_NAME"
    else
        log_info "CloudWatch Log Group not found or already deleted"
    fi
}

# Function to cleanup temporary files and state
cleanup_temporary_files() {
    log_info "Cleaning up temporary files..."
    
    local files_to_remove=(
        "/tmp/waf_deployment_state.env"
        "/tmp/cleanup-config.json"
        "/tmp/cleanup-updated.json"
        "/tmp/distribution-config.json"
        "/tmp/updated-config.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "Removed: $file"
        fi
    done
    
    log_success "Temporary files cleanup completed"
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check WAF Web ACL
    if aws wafv2 list-web-acls --scope CLOUDFRONT --region "$AWS_REGION" \
        --query "WebACLs[?Name=='$WAF_NAME']" --output text | grep -q "$WAF_NAME"; then
        log_warning "WAF Web ACL still exists: $WAF_NAME"
        ((cleanup_issues++))
    fi
    
    # Check IP Set
    if aws wafv2 list-ip-sets --scope CLOUDFRONT --region "$AWS_REGION" \
        --query "IPSets[?Name=='$IP_SET_NAME']" --output text | grep -q "$IP_SET_NAME"; then
        log_warning "IP Set still exists: $IP_SET_NAME"
        ((cleanup_issues++))
    fi
    
    # Check Regex Pattern Set
    if aws wafv2 list-regex-pattern-sets --scope CLOUDFRONT --region "$AWS_REGION" \
        --query "RegexPatternSets[?Name=='$REGEX_SET_NAME']" --output text | grep -q "$REGEX_SET_NAME"; then
        log_warning "Regex Pattern Set still exists: $REGEX_SET_NAME"
        ((cleanup_issues++))
    fi
    
    # Check CloudWatch Log Group
    if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" \
        --query "logGroups[?logGroupName=='$LOG_GROUP_NAME']" \
        --output text | grep -q "$LOG_GROUP_NAME"; then
        log_warning "CloudWatch Log Group still exists: $LOG_GROUP_NAME"
        ((cleanup_issues++))
    fi
    
    # Check SNS Topic
    local sns_topic_arn="arn:aws:sns:$AWS_REGION:$AWS_ACCOUNT_ID:$SNS_TOPIC_NAME"
    if aws sns get-topic-attributes --topic-arn "$sns_topic_arn" &> /dev/null; then
        log_warning "SNS Topic still exists: $sns_topic_arn"
        ((cleanup_issues++))
    fi
    
    # Check CloudWatch Alarm
    if aws cloudwatch describe-alarms --alarm-names "$CLOUDWATCH_ALARM_NAME" \
        --region "$AWS_REGION" --query "MetricAlarms" --output text | grep -q "$CLOUDWATCH_ALARM_NAME"; then
        log_warning "CloudWatch Alarm still exists: $CLOUDWATCH_ALARM_NAME"
        ((cleanup_issues++))
    fi
    
    # Check CloudWatch Dashboard
    if aws cloudwatch list-dashboards --region "$AWS_REGION" \
        --query "DashboardEntries[?DashboardName=='$DASHBOARD_NAME']" \
        --output text | grep -q "$DASHBOARD_NAME"; then
        log_warning "CloudWatch Dashboard still exists: $DASHBOARD_NAME"
        ((cleanup_issues++))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "All resources have been successfully cleaned up!"
    else
        log_warning "Cleanup completed with $cleanup_issues issues"
        log_warning "Some resources may still exist and require manual cleanup"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "WAF cleanup process completed!"
    
    echo
    echo "=================================="
    echo "Cleanup Summary"
    echo "=================================="
    echo "The following resources have been removed:"
    echo "  ✅ WAF Web ACL: $WAF_NAME"
    echo "  ✅ CloudWatch Log Group: $LOG_GROUP_NAME"
    echo "  ✅ SNS Topic: $SNS_TOPIC_NAME"
    echo "  ✅ CloudWatch Alarm: $CLOUDWATCH_ALARM_NAME"
    echo "  ✅ CloudWatch Dashboard: $DASHBOARD_NAME"
    echo "  ✅ IP Set: $IP_SET_NAME"
    echo "  ✅ Regex Pattern Set: $REGEX_SET_NAME"
    echo "  ✅ WAF Logging Configuration"
    echo "  ✅ CloudFront Associations (if any)"
    echo "  ✅ Temporary files and state"
    echo
    echo "Note: CloudFront distributions may take time to reflect"
    echo "the removal of WAF associations across all edge locations."
    echo "=================================="
}

# Main cleanup function
main() {
    log_info "Starting WAF Rules Web Application Security cleanup..."
    
    # Check for dry run mode
    local dry_run=false
    local force_cleanup=false
    
    for arg in "$@"; do
        case $arg in
            --dry-run)
                dry_run=true
                ;;
            --force)
                force_cleanup=true
                ;;
        esac
    done
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "Running in dry-run mode - no resources will be deleted"
        load_deployment_state
        log_info "Resources that would be deleted:"
        echo "  - WAF Web ACL: $WAF_NAME"
        echo "  - CloudWatch Log Group: $LOG_GROUP_NAME"
        echo "  - SNS Topic: $SNS_TOPIC_NAME"
        echo "  - CloudWatch Alarm: $CLOUDWATCH_ALARM_NAME"
        echo "  - CloudWatch Dashboard: $DASHBOARD_NAME"
        echo "  - IP Set: $IP_SET_NAME"
        echo "  - Regex Pattern Set: $REGEX_SET_NAME"
        log_info "Dry run completed - no resources were deleted"
        return 0
    fi
    
    check_prerequisites
    load_deployment_state
    
    if [[ "$force_cleanup" == "true" ]]; then
        confirm_destruction --force
    else
        confirm_destruction
    fi
    
    # Execute cleanup in proper order
    remove_cloudfront_association
    disable_waf_logging
    delete_cloudwatch_resources
    delete_sns_topic
    delete_ip_set
    delete_regex_pattern_set
    delete_waf_web_acl
    delete_log_group
    cleanup_temporary_files
    verify_cleanup
    display_cleanup_summary
}

# Handle script interruption
trap 'log_error "Cleanup script interrupted. Some resources may still exist."; exit 1' INT TERM

# Run main function
main "$@"