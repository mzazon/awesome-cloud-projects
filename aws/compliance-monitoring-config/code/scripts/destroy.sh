#!/bin/bash

#==============================================================================
# AWS Config Compliance Monitoring - Cleanup Script
#==============================================================================
# This script safely removes all resources created by the deployment script:
# - AWS Config service components
# - Lambda functions and custom rules
# - EventBridge rules and targets
# - CloudWatch dashboards and alarms
# - IAM roles and policies
# - S3 buckets and SNS topics
#==============================================================================

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/config-compliance-destroy-$(date +%Y%m%d-%H%M%S).log"
readonly FORCE_DELETE=${FORCE_DELETE:-false}
readonly DRY_RUN=${DRY_RUN:-false}

# Global variables for tracking
declare -a RESOURCES_TO_DELETE=()
declare -a DELETION_ERRORS=()

#==============================================================================
# Logging and Output Functions
#==============================================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

#==============================================================================
# Prerequisites and Validation
#==============================================================================

check_prerequisites() {
    info "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Verify AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    # Get AWS account info
    local caller_info
    caller_info=$(aws sts get-caller-identity)
    info "AWS Account: $(echo "$caller_info" | jq -r '.Account' 2>/dev/null || echo 'Unknown')"
    info "AWS User/Role: $(echo "$caller_info" | jq -r '.Arn' 2>/dev/null || echo 'Unknown')"
    
    success "Prerequisites check completed."
}

#==============================================================================
# Resource Discovery
#==============================================================================

discover_resources() {
    info "Discovering Config compliance monitoring resources..."
    
    export AWS_REGION
    AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Discover Config rules
    local config_rules
    config_rules=$(aws configservice describe-config-rules \
        --query 'ConfigRules[?contains(ConfigRuleName, `s3-bucket-public-access-prohibited`) || contains(ConfigRuleName, `encrypted-volumes`) || contains(ConfigRuleName, `root-access-key-check`) || contains(ConfigRuleName, `required-tags-ec2`) || contains(ConfigRuleName, `security-group-restricted-ingress`)].ConfigRuleName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$config_rules" ]]; then
        for rule in $config_rules; do
            RESOURCES_TO_DELETE+=("config-rule:$rule")
        done
    fi
    
    # Discover Lambda functions
    local lambda_functions
    lambda_functions=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `ConfigSecurityGroupRule`) || contains(FunctionName, `ConfigRemediation`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$lambda_functions" ]]; then
        for func in $lambda_functions; do
            RESOURCES_TO_DELETE+=("lambda:$func")
        done
    fi
    
    # Discover EventBridge rules
    local eventbridge_rules
    eventbridge_rules=$(aws events list-rules \
        --query 'Rules[?contains(Name, `ConfigComplianceRule`)].Name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$eventbridge_rules" ]]; then
        for rule in $eventbridge_rules; do
            RESOURCES_TO_DELETE+=("eventbridge-rule:$rule")
        done
    fi
    
    # Discover CloudWatch dashboards
    local dashboards
    dashboards=$(aws cloudwatch list-dashboards \
        --query 'DashboardEntries[?contains(DashboardName, `ConfigCompliance`)].DashboardName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$dashboards" ]]; then
        for dashboard in $dashboards; do
            RESOURCES_TO_DELETE+=("cloudwatch-dashboard:$dashboard")
        done
    fi
    
    # Discover CloudWatch alarms
    local alarms
    alarms=$(aws cloudwatch describe-alarms \
        --query 'MetricAlarms[?contains(AlarmName, `ConfigNonCompliant`) || contains(AlarmName, `ConfigRemediation`)].AlarmName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$alarms" ]]; then
        for alarm in $alarms; do
            RESOURCES_TO_DELETE+=("cloudwatch-alarm:$alarm")
        done
    fi
    
    # Discover IAM roles
    local iam_roles
    iam_roles=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `ConfigServiceRole`) || contains(RoleName, `ConfigLambdaRole`) || contains(RoleName, `ConfigRemediationRole`)].RoleName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$iam_roles" ]]; then
        for role in $iam_roles; do
            RESOURCES_TO_DELETE+=("iam-role:$role")
        done
    fi
    
    # Discover S3 buckets
    local s3_buckets
    s3_buckets=$(aws s3api list-buckets \
        --query 'Buckets[?contains(Name, `config-bucket-'$AWS_ACCOUNT_ID'`)].Name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$s3_buckets" ]]; then
        for bucket in $s3_buckets; do
            RESOURCES_TO_DELETE+=("s3-bucket:$bucket")
        done
    fi
    
    # Discover SNS topics
    local sns_topics
    sns_topics=$(aws sns list-topics \
        --query 'Topics[?contains(TopicArn, `config-compliance-topic`)].TopicArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$sns_topics" ]]; then
        for topic in $sns_topics; do
            RESOURCES_TO_DELETE+=("sns-topic:$topic")
        done
    fi
    
    # Check for Config recorder and delivery channel
    if aws configservice describe-configuration-recorders --configuration-recorder-names default &>/dev/null; then
        RESOURCES_TO_DELETE+=("config-recorder:default")
    fi
    
    if aws configservice describe-delivery-channels --delivery-channel-names default &>/dev/null; then
        RESOURCES_TO_DELETE+=("config-delivery-channel:default")
    fi
    
    info "Discovered ${#RESOURCES_TO_DELETE[@]} resources for deletion."
    
    if [[ ${#RESOURCES_TO_DELETE[@]} -eq 0 ]]; then
        success "No Config compliance monitoring resources found to delete."
        exit 0
    fi
}

#==============================================================================
# User Confirmation
#==============================================================================

confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    warning "This will permanently delete the following resources:"
    echo
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        echo "  • $resource"
    done
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        info "Deletion cancelled by user."
        exit 0
    fi
    
    info "Proceeding with resource deletion..."
}

#==============================================================================
# Resource Deletion Functions
#==============================================================================

delete_config_rules() {
    info "Deleting Config rules..."
    
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" == config-rule:* ]]; then
            local rule_name="${resource#config-rule:}"
            info "Deleting Config rule: $rule_name"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                info "DRY RUN: Would delete Config rule $rule_name"
                continue
            fi
            
            if aws configservice delete-config-rule --config-rule-name "$rule_name" 2>/dev/null; then
                success "Deleted Config rule: $rule_name"
            else
                error "Failed to delete Config rule: $rule_name"
                DELETION_ERRORS+=("config-rule:$rule_name")
            fi
        fi
    done
}

delete_lambda_functions() {
    info "Deleting Lambda functions..."
    
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" == lambda:* ]]; then
            local function_name="${resource#lambda:}"
            info "Deleting Lambda function: $function_name"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                info "DRY RUN: Would delete Lambda function $function_name"
                continue
            fi
            
            if aws lambda delete-function --function-name "$function_name" 2>/dev/null; then
                success "Deleted Lambda function: $function_name"
            else
                error "Failed to delete Lambda function: $function_name"
                DELETION_ERRORS+=("lambda:$function_name")
            fi
        fi
    done
}

delete_eventbridge_rules() {
    info "Deleting EventBridge rules..."
    
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" == eventbridge-rule:* ]]; then
            local rule_name="${resource#eventbridge-rule:}"
            info "Deleting EventBridge rule: $rule_name"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                info "DRY RUN: Would delete EventBridge rule $rule_name"
                continue
            fi
            
            # Remove targets first
            local targets
            targets=$(aws events list-targets-by-rule --rule "$rule_name" --query 'Targets[].Id' --output text 2>/dev/null || echo "")
            
            if [[ -n "$targets" ]]; then
                info "Removing targets from EventBridge rule: $rule_name"
                aws events remove-targets --rule "$rule_name" --ids $targets 2>/dev/null || true
            fi
            
            # Delete the rule
            if aws events delete-rule --name "$rule_name" 2>/dev/null; then
                success "Deleted EventBridge rule: $rule_name"
            else
                error "Failed to delete EventBridge rule: $rule_name"
                DELETION_ERRORS+=("eventbridge-rule:$rule_name")
            fi
        fi
    done
}

delete_cloudwatch_resources() {
    info "Deleting CloudWatch resources..."
    
    # Delete dashboards
    local dashboards_to_delete=()
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" == cloudwatch-dashboard:* ]]; then
            local dashboard_name="${resource#cloudwatch-dashboard:}"
            dashboards_to_delete+=("$dashboard_name")
        fi
    done
    
    if [[ ${#dashboards_to_delete[@]} -gt 0 ]]; then
        info "Deleting CloudWatch dashboards..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "DRY RUN: Would delete dashboards: ${dashboards_to_delete[*]}"
        else
            if aws cloudwatch delete-dashboards --dashboard-names "${dashboards_to_delete[@]}" 2>/dev/null; then
                success "Deleted CloudWatch dashboards: ${dashboards_to_delete[*]}"
            else
                error "Failed to delete some CloudWatch dashboards"
                for dashboard in "${dashboards_to_delete[@]}"; do
                    DELETION_ERRORS+=("cloudwatch-dashboard:$dashboard")
                done
            fi
        fi
    fi
    
    # Delete alarms
    local alarms_to_delete=()
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" == cloudwatch-alarm:* ]]; then
            local alarm_name="${resource#cloudwatch-alarm:}"
            alarms_to_delete+=("$alarm_name")
        fi
    done
    
    if [[ ${#alarms_to_delete[@]} -gt 0 ]]; then
        info "Deleting CloudWatch alarms..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "DRY RUN: Would delete alarms: ${alarms_to_delete[*]}"
        else
            if aws cloudwatch delete-alarms --alarm-names "${alarms_to_delete[@]}" 2>/dev/null; then
                success "Deleted CloudWatch alarms: ${alarms_to_delete[*]}"
            else
                error "Failed to delete some CloudWatch alarms"
                for alarm in "${alarms_to_delete[@]}"; do
                    DELETION_ERRORS+=("cloudwatch-alarm:$alarm")
                done
            fi
        fi
    fi
}

delete_config_service() {
    info "Deleting AWS Config service components..."
    
    # Stop and delete configuration recorder
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" == config-recorder:* ]]; then
            local recorder_name="${resource#config-recorder:}"
            info "Stopping and deleting Config recorder: $recorder_name"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                info "DRY RUN: Would stop and delete Config recorder $recorder_name"
                continue
            fi
            
            # Stop recorder first
            aws configservice stop-configuration-recorder --configuration-recorder-name "$recorder_name" 2>/dev/null || true
            
            # Delete recorder
            if aws configservice delete-configuration-recorder --configuration-recorder-name "$recorder_name" 2>/dev/null; then
                success "Deleted Config recorder: $recorder_name"
            else
                error "Failed to delete Config recorder: $recorder_name"
                DELETION_ERRORS+=("config-recorder:$recorder_name")
            fi
        fi
    done
    
    # Delete delivery channel
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" == config-delivery-channel:* ]]; then
            local channel_name="${resource#config-delivery-channel:}"
            info "Deleting Config delivery channel: $channel_name"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                info "DRY RUN: Would delete Config delivery channel $channel_name"
                continue
            fi
            
            if aws configservice delete-delivery-channel --delivery-channel-name "$channel_name" 2>/dev/null; then
                success "Deleted Config delivery channel: $channel_name"
            else
                error "Failed to delete Config delivery channel: $channel_name"
                DELETION_ERRORS+=("config-delivery-channel:$channel_name")
            fi
        fi
    done
}

delete_iam_roles() {
    info "Deleting IAM roles and policies..."
    
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" == iam-role:* ]]; then
            local role_name="${resource#iam-role:}"
            info "Deleting IAM role: $role_name"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                info "DRY RUN: Would delete IAM role $role_name"
                continue
            fi
            
            # List and detach managed policies
            local attached_policies
            attached_policies=$(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
            
            for policy_arn in $attached_policies; do
                info "Detaching policy: $policy_arn from role: $role_name"
                aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" 2>/dev/null || true
                
                # Delete custom policies (not AWS managed)
                if [[ "$policy_arn" == arn:aws:iam::${AWS_ACCOUNT_ID}:policy/* ]]; then
                    info "Deleting custom policy: $policy_arn"
                    aws iam delete-policy --policy-arn "$policy_arn" 2>/dev/null || true
                fi
            done
            
            # Delete inline policies
            local inline_policies
            inline_policies=$(aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames' --output text 2>/dev/null || echo "")
            
            for policy_name in $inline_policies; do
                info "Deleting inline policy: $policy_name from role: $role_name"
                aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" 2>/dev/null || true
            done
            
            # Delete the role
            if aws iam delete-role --role-name "$role_name" 2>/dev/null; then
                success "Deleted IAM role: $role_name"
            else
                error "Failed to delete IAM role: $role_name"
                DELETION_ERRORS+=("iam-role:$role_name")
            fi
        fi
    done
}

delete_s3_buckets() {
    info "Deleting S3 buckets..."
    
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" == s3-bucket:* ]]; then
            local bucket_name="${resource#s3-bucket:}"
            info "Deleting S3 bucket: $bucket_name"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                info "DRY RUN: Would delete S3 bucket $bucket_name"
                continue
            fi
            
            # Empty bucket first
            info "Emptying S3 bucket: $bucket_name"
            aws s3 rm "s3://$bucket_name" --recursive 2>/dev/null || true
            
            # Delete bucket
            if aws s3 rb "s3://$bucket_name" 2>/dev/null; then
                success "Deleted S3 bucket: $bucket_name"
            else
                error "Failed to delete S3 bucket: $bucket_name"
                DELETION_ERRORS+=("s3-bucket:$bucket_name")
            fi
        fi
    done
}

delete_sns_topics() {
    info "Deleting SNS topics..."
    
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" == sns-topic:* ]]; then
            local topic_arn="${resource#sns-topic:}"
            info "Deleting SNS topic: $topic_arn"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                info "DRY RUN: Would delete SNS topic $topic_arn"
                continue
            fi
            
            if aws sns delete-topic --topic-arn "$topic_arn" 2>/dev/null; then
                success "Deleted SNS topic: $topic_arn"
            else
                error "Failed to delete SNS topic: $topic_arn"
                DELETION_ERRORS+=("sns-topic:$topic_arn")
            fi
        fi
    done
}

#==============================================================================
# Main Cleanup Function
#==============================================================================

main() {
    info "Starting AWS Config Compliance Monitoring cleanup..."
    
    # Pre-cleanup checks
    check_prerequisites
    discover_resources
    confirm_deletion
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN MODE: Resources that would be deleted:"
        for resource in "${RESOURCES_TO_DELETE[@]}"; do
            echo "  • $resource"
        done
        exit 0
    fi
    
    # Perform deletion in order (dependencies first)
    delete_config_rules
    delete_lambda_functions
    delete_eventbridge_rules
    delete_cloudwatch_resources
    delete_config_service
    delete_iam_roles
    delete_s3_buckets
    delete_sns_topics
    
    # Summary
    local deleted_count=$((${#RESOURCES_TO_DELETE[@]} - ${#DELETION_ERRORS[@]}))
    local error_count=${#DELETION_ERRORS[@]}
    
    cat << EOF

${GREEN}===============================================================================${NC}
${GREEN}CLEANUP COMPLETED${NC}
${GREEN}===============================================================================${NC}

${BLUE}SUMMARY:${NC}
• Successfully deleted: $deleted_count resources
• Failed deletions: $error_count resources
• Total resources processed: ${#RESOURCES_TO_DELETE[@]}

EOF

    if [[ $error_count -gt 0 ]]; then
        warning "The following resources could not be deleted:"
        for error in "${DELETION_ERRORS[@]}"; do
            echo "  • $error"
        done
        echo
        warning "You may need to delete these resources manually."
        echo "Check the AWS console or run this script again."
        exit 1
    else
        success "All Config compliance monitoring resources have been successfully deleted."
    fi
    
    info "Log file: $LOG_FILE"
}

#==============================================================================
# Script Execution
#==============================================================================

# Show usage if help requested
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    cat << EOF
AWS Config Compliance Monitoring - Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help      Show this help message
    --dry-run       Show what would be deleted without making changes
    --force         Skip confirmation prompt

ENVIRONMENT VARIABLES:
    DRY_RUN         Set to 'true' for dry run mode
    FORCE_DELETE    Set to 'true' to skip confirmation
    AWS_REGION      Override default AWS region
    AWS_PROFILE     Use specific AWS profile

EXAMPLES:
    $0                          # Interactive cleanup
    $0 --dry-run               # Preview what would be deleted
    $0 --force                 # Delete without confirmation
    DRY_RUN=true $0           # Preview using environment variable
    FORCE_DELETE=true $0      # Force delete using environment variable

SAFETY FEATURES:
• Discovers resources automatically
• Shows preview before deletion
• Requires explicit confirmation
• Handles dependencies correctly
• Provides detailed logging

EOF
    exit 0
fi

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            export DRY_RUN=true
            shift
            ;;
        --force)
            export FORCE_DELETE=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"