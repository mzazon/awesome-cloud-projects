#!/bin/bash

# Destroy script for DNS Security Monitoring with Route 53 Resolver DNS Firewall and CloudWatch
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_INFO="${SCRIPT_DIR}/deployment-info.json"

# Colors for output
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
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handler (non-fatal for cleanup operations)
error_handler() {
    local line_number=$1
    warn "Error occurred at line ${line_number}, continuing cleanup..."
}

trap 'error_handler ${LINENO}' ERR

# Function to confirm destruction
confirm_destruction() {
    info "This script will destroy all DNS Security Monitoring resources."
    echo ""
    warn "WARNING: This action cannot be undone!"
    echo ""
    
    if [ -f "${DEPLOYMENT_INFO}" ]; then
        info "Resources to be destroyed:"
        if command -v jq &> /dev/null; then
            jq -r 'to_entries[] | "  \(.key): \(.value)"' "${DEPLOYMENT_INFO}" | grep -v "null"
        else
            info "  (See ${DEPLOYMENT_INFO} for details)"
        fi
        echo ""
    else
        warn "Deployment info file not found. Will attempt to discover resources."
        echo ""
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    if [ "${confirm}" != "yes" ]; then
        info "Destruction cancelled by user."
        exit 0
    fi
}

# Function to load deployment information
load_deployment_info() {
    info "Loading deployment information..."
    
    if [ -f "${DEPLOYMENT_INFO}" ]; then
        if command -v jq &> /dev/null; then
            export AWS_REGION=$(jq -r '.aws_region // empty' "${DEPLOYMENT_INFO}")
            export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id // empty' "${DEPLOYMENT_INFO}")
            export RANDOM_SUFFIX=$(jq -r '.random_suffix // empty' "${DEPLOYMENT_INFO}")
            export VPC_ID=$(jq -r '.vpc_id // empty' "${DEPLOYMENT_INFO}")
            export SNS_TOPIC_ARN=$(jq -r '.sns_topic_arn // empty' "${DEPLOYMENT_INFO}")
            export DOMAIN_LIST_ID=$(jq -r '.domain_list_id // empty' "${DEPLOYMENT_INFO}")
            export RULE_GROUP_ID=$(jq -r '.rule_group_id // empty' "${DEPLOYMENT_INFO}")
            export ASSOCIATION_ID=$(jq -r '.association_id // empty' "${DEPLOYMENT_INFO}")
            export LOG_GROUP_NAME=$(jq -r '.log_group_name // empty' "${DEPLOYMENT_INFO}")
            export QUERY_LOG_CONFIG_ID=$(jq -r '.query_log_config_id // empty' "${DEPLOYMENT_INFO}")
            export LAMBDA_FUNCTION_ARN=$(jq -r '.lambda_function_arn // empty' "${DEPLOYMENT_INFO}")
            
            success "Deployment information loaded successfully"
        else
            warn "jq not available, will attempt to discover resources"
        fi
    else
        warn "Deployment info file not found, will attempt to discover resources"
    fi
    
    # Set defaults if not loaded
    export AWS_REGION=${AWS_REGION:-$(aws configure get region || echo "us-east-1")}
    export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")}
}

# Function to discover resources if deployment info is missing
discover_resources() {
    info "Attempting to discover DNS Security Monitoring resources..."
    
    # Discover SNS topics
    if [ -z "${SNS_TOPIC_ARN:-}" ]; then
        export SNS_TOPIC_ARN=$(aws sns list-topics \
            --query "Topics[?contains(TopicArn, 'dns-security-alerts')].TopicArn" \
            --output text 2>/dev/null || echo "")
    fi
    
    # Discover DNS Firewall rule groups
    if [ -z "${RULE_GROUP_ID:-}" ]; then
        export RULE_GROUP_ID=$(aws route53resolver list-firewall-rule-groups \
            --query "FirewallRuleGroups[?contains(Name, 'dns-security-rules')].Id" \
            --output text 2>/dev/null || echo "")
    fi
    
    # Discover domain lists
    if [ -z "${DOMAIN_LIST_ID:-}" ]; then
        export DOMAIN_LIST_ID=$(aws route53resolver list-firewall-domain-lists \
            --query "FirewallDomainLists[?contains(Name, 'malicious-domains')].Id" \
            --output text 2>/dev/null || echo "")
    fi
    
    # Discover query log configurations
    if [ -z "${QUERY_LOG_CONFIG_ID:-}" ]; then
        export QUERY_LOG_CONFIG_ID=$(aws route53resolver list-resolver-query-log-configs \
            --query "ResolverQueryLogConfigs[?contains(Name, 'dns-security-logs')].Id" \
            --output text 2>/dev/null || echo "")
    fi
    
    # Discover CloudWatch log groups
    if [ -z "${LOG_GROUP_NAME:-}" ]; then
        export LOG_GROUP_NAME=$(aws logs describe-log-groups \
            --log-group-name-prefix "/aws/route53resolver/dns-security" \
            --query "logGroups[0].logGroupName" --output text 2>/dev/null || echo "")
    fi
    
    # Discover Lambda functions
    if [ -z "${LAMBDA_FUNCTION_ARN:-}" ]; then
        export LAMBDA_FUNCTION_ARN=$(aws lambda list-functions \
            --query "Functions[?contains(FunctionName, 'dns-security-response')].FunctionArn" \
            --output text 2>/dev/null || echo "")
    fi
    
    success "Resource discovery completed"
}

# Function to remove DNS query logging configuration
remove_dns_query_logging() {
    info "Removing DNS query logging configuration..."
    
    if [ -n "${QUERY_LOG_CONFIG_ID:-}" ] && [ "${QUERY_LOG_CONFIG_ID}" != "None" ]; then
        # Get and remove query log associations
        local associations=$(aws route53resolver list-resolver-query-log-config-associations \
            --query "ResolverQueryLogConfigAssociations[?ResolverQueryLogConfigId=='${QUERY_LOG_CONFIG_ID}'].Id" \
            --output text 2>/dev/null || echo "")
        
        for association_id in $associations; do
            if [ -n "$association_id" ] && [ "$association_id" != "None" ]; then
                info "Removing query log association: $association_id"
                aws route53resolver disassociate-resolver-query-log-config \
                    --resolver-query-log-config-association-id "$association_id" \
                    > /dev/null 2>&1 || warn "Failed to remove association $association_id"
            fi
        done
        
        # Wait for disassociation
        if [ -n "$associations" ]; then
            info "Waiting for query log disassociation..."
            sleep 30
        fi
        
        # Delete query log configuration
        info "Deleting query log configuration: ${QUERY_LOG_CONFIG_ID}"
        aws route53resolver delete-resolver-query-log-config \
            --resolver-query-log-config-id "${QUERY_LOG_CONFIG_ID}" \
            > /dev/null 2>&1 || warn "Failed to delete query log configuration"
        
        success "DNS query logging configuration removed"
    else
        info "No DNS query logging configuration found to remove"
    fi
}

# Function to remove CloudWatch resources
remove_cloudwatch_resources() {
    info "Removing CloudWatch alarms and log groups..."
    
    # Remove CloudWatch alarms
    local alarm_names=$(aws cloudwatch describe-alarms \
        --query "MetricAlarms[?contains(AlarmName, 'DNS-')].AlarmName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$alarm_names" ]; then
        info "Deleting CloudWatch alarms..."
        aws cloudwatch delete-alarms --alarm-names $alarm_names > /dev/null 2>&1 || warn "Failed to delete some alarms"
        success "CloudWatch alarms removed"
    fi
    
    # Remove CloudWatch log group
    if [ -n "${LOG_GROUP_NAME:-}" ] && [ "${LOG_GROUP_NAME}" != "None" ]; then
        info "Deleting CloudWatch log group: ${LOG_GROUP_NAME}"
        aws logs delete-log-group --log-group-name "${LOG_GROUP_NAME}" > /dev/null 2>&1 || warn "Failed to delete log group"
        success "CloudWatch log group removed"
    fi
}

# Function to remove Lambda function and IAM role
remove_lambda_resources() {
    info "Removing Lambda function and IAM role..."
    
    # Extract function name from ARN if available
    local function_name=""
    if [ -n "${LAMBDA_FUNCTION_ARN:-}" ] && [ "${LAMBDA_FUNCTION_ARN}" != "None" ]; then
        function_name=$(echo "${LAMBDA_FUNCTION_ARN}" | cut -d':' -f7)
    else
        # Try to find function by name pattern
        function_name=$(aws lambda list-functions \
            --query "Functions[?contains(FunctionName, 'dns-security-response')].FunctionName" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [ -n "$function_name" ] && [ "$function_name" != "None" ]; then
        info "Deleting Lambda function: $function_name"
        aws lambda delete-function --function-name "$function_name" > /dev/null 2>&1 || warn "Failed to delete Lambda function"
        success "Lambda function removed"
        
        # Extract suffix from function name for role cleanup
        local suffix=$(echo "$function_name" | sed 's/.*-//')
        local role_name="dns-security-lambda-role-$suffix"
        
        # Remove IAM role
        info "Removing IAM role: $role_name"
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
            > /dev/null 2>&1 || warn "Failed to detach policy from role"
        
        aws iam delete-role --role-name "$role_name" > /dev/null 2>&1 || warn "Failed to delete IAM role"
        success "IAM role removed"
    else
        info "No Lambda function found to remove"
    fi
    
    # Clean up local Lambda files
    local lambda_dir="${SCRIPT_DIR}/../lambda"
    if [ -d "$lambda_dir" ]; then
        info "Cleaning up local Lambda files..."
        rm -rf "$lambda_dir"
        success "Local Lambda files cleaned up"
    fi
}

# Function to remove DNS Firewall configuration
remove_dns_firewall() {
    info "Removing DNS Firewall configuration..."
    
    # Get and remove firewall rule group associations
    if [ -n "${RULE_GROUP_ID:-}" ] && [ "${RULE_GROUP_ID}" != "None" ]; then
        local associations=$(aws route53resolver list-firewall-rule-group-associations \
            --query "FirewallRuleGroupAssociations[?FirewallRuleGroupId=='${RULE_GROUP_ID}'].Id" \
            --output text 2>/dev/null || echo "")
        
        for association_id in $associations; do
            if [ -n "$association_id" ] && [ "$association_id" != "None" ]; then
                info "Removing firewall association: $association_id"
                aws route53resolver disassociate-firewall-rule-group \
                    --firewall-rule-group-association-id "$association_id" \
                    > /dev/null 2>&1 || warn "Failed to remove association $association_id"
            fi
        done
        
        # Wait for disassociation
        if [ -n "$associations" ]; then
            info "Waiting for firewall disassociation..."
            sleep 60
        fi
        
        # Remove firewall rules from rule group
        local rules=$(aws route53resolver list-firewall-rules \
            --firewall-rule-group-id "${RULE_GROUP_ID}" \
            --query "FirewallRules[].Name" --output text 2>/dev/null || echo "")
        
        for rule_name in $rules; do
            if [ -n "$rule_name" ] && [ "$rule_name" != "None" ]; then
                info "Deleting firewall rule: $rule_name"
                aws route53resolver delete-firewall-rule \
                    --firewall-rule-group-id "${RULE_GROUP_ID}" \
                    --name "$rule_name" \
                    > /dev/null 2>&1 || warn "Failed to delete rule $rule_name"
            fi
        done
        
        # Delete rule group
        info "Deleting firewall rule group: ${RULE_GROUP_ID}"
        aws route53resolver delete-firewall-rule-group \
            --firewall-rule-group-id "${RULE_GROUP_ID}" \
            > /dev/null 2>&1 || warn "Failed to delete rule group"
        
        success "DNS Firewall rule group removed"
    else
        info "No DNS Firewall rule group found to remove"
    fi
    
    # Remove domain list
    if [ -n "${DOMAIN_LIST_ID:-}" ] && [ "${DOMAIN_LIST_ID}" != "None" ]; then
        info "Deleting domain list: ${DOMAIN_LIST_ID}"
        aws route53resolver delete-firewall-domain-list \
            --firewall-domain-list-id "${DOMAIN_LIST_ID}" \
            > /dev/null 2>&1 || warn "Failed to delete domain list"
        success "DNS Firewall domain list removed"
    else
        info "No DNS Firewall domain list found to remove"
    fi
}

# Function to remove SNS resources
remove_sns_resources() {
    info "Removing SNS topic and subscriptions..."
    
    if [ -n "${SNS_TOPIC_ARN:-}" ] && [ "${SNS_TOPIC_ARN}" != "None" ]; then
        # List and delete subscriptions (SNS will handle this, but for clarity)
        local subscriptions=$(aws sns list-subscriptions-by-topic \
            --topic-arn "${SNS_TOPIC_ARN}" \
            --query "Subscriptions[].SubscriptionArn" --output text 2>/dev/null || echo "")
        
        for subscription_arn in $subscriptions; do
            if [ -n "$subscription_arn" ] && [ "$subscription_arn" != "None" ] && [ "$subscription_arn" != "PendingConfirmation" ]; then
                info "Removing subscription: $subscription_arn"
                aws sns unsubscribe --subscription-arn "$subscription_arn" > /dev/null 2>&1 || warn "Failed to remove subscription"
            fi
        done
        
        # Delete SNS topic
        info "Deleting SNS topic: ${SNS_TOPIC_ARN}"
        aws sns delete-topic --topic-arn "${SNS_TOPIC_ARN}" > /dev/null 2>&1 || warn "Failed to delete SNS topic"
        success "SNS topic removed"
    else
        info "No SNS topic found to remove"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove deployment info
    if [ -f "${DEPLOYMENT_INFO}" ]; then
        rm -f "${DEPLOYMENT_INFO}"
        success "Deployment info file removed"
    fi
    
    # Keep log files for reference but notify user
    info "Log files preserved for reference:"
    info "  Deploy log: ${SCRIPT_DIR}/deploy.log"
    info "  Destroy log: ${LOG_FILE}"
}

# Function to verify resource removal
verify_cleanup() {
    info "Verifying resource cleanup..."
    
    local remaining_resources=0
    
    # Check for remaining SNS topics
    local sns_topics=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, 'dns-security-alerts')]" \
        --output text 2>/dev/null || echo "")
    if [ -n "$sns_topics" ]; then
        warn "Some SNS topics may still exist"
        remaining_resources=$((remaining_resources + 1))
    fi
    
    # Check for remaining DNS Firewall rule groups
    local rule_groups=$(aws route53resolver list-firewall-rule-groups \
        --query "FirewallRuleGroups[?contains(Name, 'dns-security-rules')]" \
        --output text 2>/dev/null || echo "")
    if [ -n "$rule_groups" ]; then
        warn "Some DNS Firewall rule groups may still exist"
        remaining_resources=$((remaining_resources + 1))
    fi
    
    # Check for remaining Lambda functions
    local lambda_functions=$(aws lambda list-functions \
        --query "Functions[?contains(FunctionName, 'dns-security-response')]" \
        --output text 2>/dev/null || echo "")
    if [ -n "$lambda_functions" ]; then
        warn "Some Lambda functions may still exist"
        remaining_resources=$((remaining_resources + 1))
    fi
    
    # Check for remaining log groups
    local log_groups=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/route53resolver/dns-security" \
        --query "logGroups" --output text 2>/dev/null || echo "")
    if [ -n "$log_groups" ] && [ "$log_groups" != "None" ]; then
        warn "Some CloudWatch log groups may still exist"
        remaining_resources=$((remaining_resources + 1))
    fi
    
    if [ $remaining_resources -eq 0 ]; then
        success "All resources appear to have been removed successfully"
    else
        warn "Some resources may still exist. Please check the AWS console manually"
        info "This can happen due to propagation delays or dependencies"
    fi
}

# Main destruction function
main() {
    info "Starting DNS Security Monitoring resource destruction..."
    info "Logs are being written to: ${LOG_FILE}"
    
    confirm_destruction
    load_deployment_info
    discover_resources
    
    # Remove resources in reverse order of creation
    remove_dns_query_logging
    remove_cloudwatch_resources
    remove_lambda_resources
    remove_dns_firewall
    remove_sns_resources
    cleanup_local_files
    
    # Wait for final propagation
    info "Waiting for final resource cleanup propagation..."
    sleep 30
    
    verify_cleanup
    
    success "DNS Security Monitoring destruction completed!"
    echo ""
    info "Cleanup Summary:"
    info "  All DNS Security Monitoring resources have been removed"
    info "  Log files have been preserved for reference"
    info "  If any resources remain, please check the AWS console manually"
    echo ""
    info "You may want to check for any remaining charges in AWS Billing Console"
}

# Handle script interruption
cleanup_on_interrupt() {
    warn "Script interrupted! Some resources may not have been cleaned up."
    warn "You may need to manually remove remaining resources from the AWS console."
    exit 1
}

trap cleanup_on_interrupt INT TERM

# Run main function
main "$@"