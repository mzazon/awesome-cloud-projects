#!/bin/bash

#######################################################################
# AWS Resource Tagging Strategies for Cost Management - Destroy Script
#######################################################################
# This script safely removes all resources created by the deploy script
# including AWS Config, Lambda functions, SNS topics, and demo resources.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate IAM permissions to delete created resources
# - Resource tracking file from deploy.sh (.deployed_resources)
#
# Usage: ./destroy.sh [--force] [--dry-run]
#######################################################################

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
FORCE_DELETE=false
DRY_RUN=false

# Resource tracking file
RESOURCE_FILE="${SCRIPT_DIR}/.deployed_resources"

#######################################################################
# Utility Functions
#######################################################################

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log ERROR "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log ERROR "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check resource tracking file
    if [[ ! -f "$RESOURCE_FILE" ]]; then
        log WARN "Resource tracking file not found: $RESOURCE_FILE"
        log WARN "Will attempt cleanup using environment variables or manual input"
    else
        log INFO "Found resource tracking file with $(wc -l < "$RESOURCE_FILE") entries"
    fi
    
    log INFO "Prerequisites check completed"
}

confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log INFO "Force delete enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    echo -e "${RED}⚠️  WARNING: This will delete all AWS resources created by the tagging strategy deployment!${NC}"
    echo ""
    echo "Resources to be deleted may include:"
    echo "- AWS Config rules and configuration recorder"
    echo "- Lambda functions and IAM roles"
    echo "- SNS topics and subscriptions"
    echo "- S3 buckets and their contents"
    echo "- Demo EC2 instances and S3 buckets"
    echo ""
    
    if [[ -f "$RESOURCE_FILE" ]]; then
        echo "Resources found in tracking file:"
        while IFS='|' read -r resource_type resource_id resource_name; do
            if [[ ! "$resource_type" =~ ^#.* ]] && [[ -n "$resource_type" ]]; then
                echo "  - $resource_type: $resource_name ($resource_id)"
            fi
        done < "$RESOURCE_FILE"
        echo ""
    fi
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log INFO "Deletion cancelled by user"
        exit 0
    fi
    
    log INFO "User confirmed deletion"
}

load_environment_from_tracking() {
    if [[ ! -f "$RESOURCE_FILE" ]]; then
        return 1
    fi
    
    log INFO "Loading environment variables from resource tracking..."
    
    # Extract common resource names to determine the strategy name
    local strategy_name=""
    while IFS='|' read -r resource_type resource_id resource_name; do
        if [[ "$resource_name" =~ cost-mgmt-([a-z0-9]+) ]]; then
            strategy_name="${BASH_REMATCH[1]}"
            break
        fi
    done < "$RESOURCE_FILE"
    
    if [[ -n "$strategy_name" ]]; then
        export TAG_STRATEGY_NAME="cost-mgmt-${strategy_name}"
        export SNS_TOPIC_NAME="tag-compliance-${strategy_name}"
        export CONFIG_ROLE_NAME="aws-config-role-${TAG_STRATEGY_NAME}"
        export LAMBDA_ROLE_NAME="tag-remediation-lambda-role-${TAG_STRATEGY_NAME}"
        export LAMBDA_FUNCTION_NAME="tag-remediation-${TAG_STRATEGY_NAME}"
        export DEMO_BUCKET="cost-mgmt-demo-${TAG_STRATEGY_NAME}"
        
        export AWS_REGION=$(aws configure get region)
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        export CONFIG_BUCKET="aws-config-${TAG_STRATEGY_NAME}-${AWS_ACCOUNT_ID}"
        
        log INFO "Loaded environment for strategy: $TAG_STRATEGY_NAME"
        return 0
    else
        log WARN "Could not determine strategy name from tracking file"
        return 1
    fi
}

prompt_for_environment() {
    log INFO "Prompting for environment variables..."
    
    echo ""
    echo "Please provide the following information to locate resources:"
    echo ""
    
    read -p "Enter the TAG_STRATEGY_NAME (e.g., cost-mgmt-abc123): " TAG_STRATEGY_NAME
    if [[ -z "$TAG_STRATEGY_NAME" ]]; then
        log ERROR "TAG_STRATEGY_NAME is required"
        exit 1
    fi
    
    export TAG_STRATEGY_NAME
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Derive other names
    export SNS_TOPIC_NAME="tag-compliance-${TAG_STRATEGY_NAME#cost-mgmt-}"
    export CONFIG_BUCKET="aws-config-${TAG_STRATEGY_NAME}-${AWS_ACCOUNT_ID}"
    export CONFIG_ROLE_NAME="aws-config-role-${TAG_STRATEGY_NAME}"
    export LAMBDA_ROLE_NAME="tag-remediation-lambda-role-${TAG_STRATEGY_NAME}"
    export LAMBDA_FUNCTION_NAME="tag-remediation-${TAG_STRATEGY_NAME}"
    export DEMO_BUCKET="cost-mgmt-demo-${TAG_STRATEGY_NAME}"
    
    log INFO "Environment variables set manually"
}

delete_config_rules() {
    log INFO "Deleting AWS Config rules..."
    
    local rules=("required-tag-costcenter" "required-tag-environment" "required-tag-project" "required-tag-owner")
    
    for rule in "${rules[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log INFO "[DRY RUN] Would delete Config rule: $rule"
            continue
        fi
        
        if aws configservice describe-config-rules --config-rule-names "$rule" &> /dev/null; then
            aws configservice delete-config-rule --config-rule-name "$rule"
            log INFO "✅ Deleted Config rule: $rule"
        else
            log WARN "Config rule not found: $rule"
        fi
    done
}

stop_config_recorder() {
    log INFO "Stopping AWS Config recorder..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would stop Config recorder and delete delivery channel"
        return 0
    fi
    
    # Stop configuration recorder
    if aws configservice describe-configuration-recorders --configuration-recorder-names default &> /dev/null; then
        aws configservice stop-configuration-recorder --configuration-recorder-name default
        log INFO "✅ Stopped Config recorder"
        
        # Wait a moment for recorder to stop
        sleep 5
        
        # Delete configuration recorder
        aws configservice delete-configuration-recorder --configuration-recorder-name default
        log INFO "✅ Deleted Config recorder"
    else
        log WARN "Config recorder 'default' not found"
    fi
    
    # Delete delivery channel
    if aws configservice describe-delivery-channels --delivery-channel-names default &> /dev/null; then
        aws configservice delete-delivery-channel --delivery-channel-name default
        log INFO "✅ Deleted Config delivery channel"
    else
        log WARN "Config delivery channel 'default' not found"
    fi
}

delete_lambda_function() {
    log INFO "Deleting Lambda function and related resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete Lambda function: $LAMBDA_FUNCTION_NAME"
        log INFO "[DRY RUN] Would delete Lambda role: $LAMBDA_ROLE_NAME"
        return 0
    fi
    
    # Delete Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
        log INFO "✅ Deleted Lambda function: $LAMBDA_FUNCTION_NAME"
    else
        log WARN "Lambda function not found: $LAMBDA_FUNCTION_NAME"
    fi
    
    # Delete Lambda role and policy
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
        # Delete inline policy
        aws iam delete-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-name TagRemediationPolicy 2>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name "$LAMBDA_ROLE_NAME"
        log INFO "✅ Deleted Lambda IAM role: $LAMBDA_ROLE_NAME"
    else
        log WARN "Lambda IAM role not found: $LAMBDA_ROLE_NAME"
    fi
}

delete_config_role() {
    log INFO "Deleting AWS Config service role..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete Config role: $CONFIG_ROLE_NAME"
        return 0
    fi
    
    if aws iam get-role --role-name "$CONFIG_ROLE_NAME" &> /dev/null; then
        # Detach managed policy
        aws iam detach-role-policy \
            --role-name "$CONFIG_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole 2>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name "$CONFIG_ROLE_NAME"
        log INFO "✅ Deleted Config IAM role: $CONFIG_ROLE_NAME"
    else
        log WARN "Config IAM role not found: $CONFIG_ROLE_NAME"
    fi
}

delete_sns_topic() {
    log INFO "Deleting SNS topic..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete SNS topic: $SNS_TOPIC_NAME"
        return 0
    fi
    
    # Find SNS topic ARN
    local topic_arn
    topic_arn=$(aws sns list-topics --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" --output text)
    
    if [[ -n "$topic_arn" ]]; then
        aws sns delete-topic --topic-arn "$topic_arn"
        log INFO "✅ Deleted SNS topic: $topic_arn"
    else
        log WARN "SNS topic not found: $SNS_TOPIC_NAME"
    fi
}

delete_demo_resources() {
    log INFO "Deleting demo resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete demo EC2 instances and S3 buckets"
        return 0
    fi
    
    # Delete demo EC2 instances
    local instances
    instances=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=cost-mgmt-demo-instance" \
        "Name=instance-state-name,Values=running,stopped,stopping,pending" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text 2>/dev/null || true)
    
    if [[ -n "$instances" ]]; then
        for instance_id in $instances; do
            aws ec2 terminate-instances --instance-ids "$instance_id"
            log INFO "✅ Terminated demo EC2 instance: $instance_id"
        done
    else
        log WARN "No demo EC2 instances found"
    fi
    
    # Delete demo S3 bucket
    if aws s3api head-bucket --bucket "$DEMO_BUCKET" &> /dev/null; then
        aws s3 rm "s3://${DEMO_BUCKET}" --recursive 2>/dev/null || true
        aws s3 rb "s3://${DEMO_BUCKET}"
        log INFO "✅ Deleted demo S3 bucket: $DEMO_BUCKET"
    else
        log WARN "Demo S3 bucket not found: $DEMO_BUCKET"
    fi
}

delete_config_bucket() {
    log INFO "Deleting AWS Config S3 bucket..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete Config S3 bucket: $CONFIG_BUCKET"
        return 0
    fi
    
    if aws s3api head-bucket --bucket "$CONFIG_BUCKET" &> /dev/null; then
        # Empty bucket first
        log INFO "Emptying Config S3 bucket..."
        aws s3 rm "s3://${CONFIG_BUCKET}" --recursive 2>/dev/null || true
        
        # Delete bucket
        aws s3 rb "s3://${CONFIG_BUCKET}"
        log INFO "✅ Deleted Config S3 bucket: $CONFIG_BUCKET"
    else
        log WARN "Config S3 bucket not found: $CONFIG_BUCKET"
    fi
}

delete_resource_groups() {
    log INFO "Deleting resource groups..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete resource groups"
        return 0
    fi
    
    # Delete resource groups created by deployment
    local groups=(
        "Production-Environment-${TAG_STRATEGY_NAME}"
        "Engineering-CostCenter-${TAG_STRATEGY_NAME}"
    )
    
    for group in "${groups[@]}"; do
        if aws resource-groups get-group --group-name "$group" &> /dev/null; then
            aws resource-groups delete-group --group-name "$group"
            log INFO "✅ Deleted resource group: $group"
        else
            log WARN "Resource group not found: $group"
        fi
    done
}

cleanup_local_files() {
    log INFO "Cleaning up local files..."
    
    local files=(
        "tag-taxonomy.json"
        "config-bucket-policy.json"
        "config-trust-policy.json"
        "lambda-trust-policy.json"
        "lambda-policy.json"
        "tag-remediation-lambda.py"
        "tag-remediation-lambda.zip"
        "check-cost-tags.sh"
    )
    
    for file in "${files[@]}"; do
        local file_path="${SCRIPT_DIR}/${file}"
        if [[ -f "$file_path" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log INFO "[DRY RUN] Would delete local file: $file"
            else
                rm -f "$file_path"
                log INFO "✅ Deleted local file: $file"
            fi
        fi
    done
    
    # Clean up resource tracking file
    if [[ -f "$RESOURCE_FILE" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log INFO "[DRY RUN] Would delete resource tracking file"
        else
            mv "$RESOURCE_FILE" "${RESOURCE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
            log INFO "✅ Backed up and removed resource tracking file"
        fi
    fi
}

verify_cleanup() {
    log INFO "Verifying resource cleanup..."
    
    local remaining_resources=0
    
    # Check Config rules
    local config_rules
    config_rules=$(aws configservice describe-config-rules \
        --query 'ConfigRules[?starts_with(ConfigRuleName, `required-tag-`)] | length(@)' \
        --output text 2>/dev/null || echo "0")
    
    if [[ "$config_rules" -gt 0 ]]; then
        log WARN "⚠️  $config_rules Config rules still exist"
        remaining_resources=$((remaining_resources + 1))
    else
        log INFO "✅ No Config rules remaining"
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        log WARN "⚠️  Lambda function still exists: $LAMBDA_FUNCTION_NAME"
        remaining_resources=$((remaining_resources + 1))
    else
        log INFO "✅ Lambda function successfully deleted"
    fi
    
    # Check SNS topic
    local topic_arn
    topic_arn=$(aws sns list-topics --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" --output text 2>/dev/null || true)
    
    if [[ -n "$topic_arn" ]]; then
        log WARN "⚠️  SNS topic still exists: $topic_arn"
        remaining_resources=$((remaining_resources + 1))
    else
        log INFO "✅ SNS topic successfully deleted"
    fi
    
    # Check S3 buckets
    if aws s3api head-bucket --bucket "$CONFIG_BUCKET" &> /dev/null; then
        log WARN "⚠️  Config S3 bucket still exists: $CONFIG_BUCKET"
        remaining_resources=$((remaining_resources + 1))
    else
        log INFO "✅ Config S3 bucket successfully deleted"
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
        log INFO "🎉 All resources successfully cleaned up!"
    else
        log WARN "⚠️  $remaining_resources resource(s) may require manual cleanup"
    fi
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DELETE=true
                log INFO "Force delete enabled"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                log INFO "Dry run mode enabled"
                shift
                ;;
            --help)
                echo "Usage: $0 [--force] [--dry-run]"
                echo ""
                echo "Options:"
                echo "  --force            Skip confirmation prompts"
                echo "  --dry-run          Show what would be deleted without making changes"
                echo "  --help             Show this help message"
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

#######################################################################
# Main Execution
#######################################################################

main() {
    echo "======================================================================="
    echo "AWS Resource Tagging Strategies for Cost Management - Destroy Script"
    echo "======================================================================="
    echo ""
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Initialize logging
    echo "Destruction started at $(date)" > "$LOG_FILE"
    log INFO "Starting cleanup of AWS resource tagging strategy"
    
    # Execute cleanup steps
    check_prerequisites
    
    # Load environment variables
    if ! load_environment_from_tracking; then
        prompt_for_environment
    fi
    
    # Confirm deletion unless forced
    confirm_deletion
    
    # Execute deletion in reverse order of creation
    delete_config_rules
    stop_config_recorder
    delete_lambda_function
    delete_config_role
    delete_demo_resources
    delete_resource_groups
    delete_sns_topic
    delete_config_bucket
    cleanup_local_files
    
    # Verify cleanup
    if [[ "$DRY_RUN" != "true" ]]; then
        verify_cleanup
    fi
    
    # Success message
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${BLUE}🔍 Dry run completed - no resources were actually deleted${NC}"
    else
        echo -e "${GREEN}🎉 Cleanup completed successfully!${NC}"
    fi
    echo ""
    echo -e "${BLUE}Cleanup summary:${NC}"
    echo "- AWS Config rules and recorder removed"
    echo "- Lambda function and IAM roles deleted"
    echo "- SNS topic and subscriptions removed"
    echo "- S3 buckets emptied and deleted"
    echo "- Demo resources cleaned up"
    echo "- Local files removed"
    echo ""
    echo -e "${YELLOW}Cleanup log:${NC} $LOG_FILE"
    echo ""
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo -e "${BLUE}Final steps:${NC}"
        echo "1. Check AWS Billing Console to deactivate cost allocation tags if no longer needed"
        echo "2. Review any remaining Cost Explorer saved reports or budgets"
        echo "3. Verify no unexpected charges in next billing cycle"
        echo ""
    fi
}

# Execute main function with all arguments
main "$@"