#!/bin/bash

# Event Sourcing Architecture Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Destroy Event Sourcing Architecture resources"
    echo ""
    echo "Options:"
    echo "  -c, --config FILE           Configuration file path (default: .deployment_config)"
    echo "  -f, --force                 Skip confirmation prompts"
    echo "  -d, --dry-run              Perform a dry run without deleting resources"
    echo "  -k, --keep-iam             Keep IAM roles and policies"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  AWS_REGION                 AWS region override"
    echo "  FORCE_DESTROY             Skip confirmation (true/false)"
    echo ""
    exit 1
}

# Parse command line arguments
DRY_RUN=false
FORCE_DESTROY=false
KEEP_IAM=false
CONFIG_FILE=".deployment_config"

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_DESTROY=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -k|--keep-iam)
            KEEP_IAM=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            usage
            ;;
    esac
done

# Check if force destroy is set via environment variable
if [[ "${FORCE_DESTROY_ENV:-}" == "true" ]]; then
    FORCE_DESTROY=true
fi

# Load deployment configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Configuration file $CONFIG_FILE not found."
        error "Please run this script from the same directory where you ran deploy.sh"
        error "or specify the correct config file path with -c option."
        exit 1
    fi
    
    log "Loading configuration from $CONFIG_FILE..."
    
    # Source the configuration file
    source "$CONFIG_FILE"
    
    # Validate required variables
    local required_vars=(
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
        "RANDOM_SUFFIX"
        "EVENT_BUS_NAME"
        "EVENT_STORE_TABLE"
        "READ_MODEL_TABLE"
        "COMMAND_FUNCTION"
        "PROJECTION_FUNCTION"
        "QUERY_FUNCTION"
        "DLQ_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required configuration variable $var is not set in $CONFIG_FILE"
            exit 1
        fi
    done
    
    log "Configuration loaded successfully ✅"
    info "AWS Region: $AWS_REGION"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    info "Resource Suffix: $RANDOM_SUFFIX"
}

# Confirmation function
confirm_destruction() {
    if [[ "$FORCE_DESTROY" == "true" ]]; then
        warn "Force destroy mode enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    warn "⚠️  WARNING: This will permanently delete the following resources:"
    echo "   - EventBridge Bus: $EVENT_BUS_NAME"
    echo "   - Event Store Table: $EVENT_STORE_TABLE (and all data)"
    echo "   - Read Model Table: $READ_MODEL_TABLE (and all data)"
    echo "   - Lambda Functions: $COMMAND_FUNCTION, $PROJECTION_FUNCTION, $QUERY_FUNCTION"
    echo "   - SQS Queue: $DLQ_NAME"
    echo "   - CloudWatch Alarms and EventBridge Rules"
    
    if [[ "$KEEP_IAM" == "false" ]]; then
        echo "   - IAM Roles and Policies"
    fi
    
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'YES' to confirm): " confirmation
    
    if [[ "$confirmation" != "YES" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed by user"
}

# Check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    
    case $resource_type in
        "iam-role")
            aws iam get-role --role-name "$resource_name" &>/dev/null
            ;;
        "iam-policy")
            aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$resource_name" &>/dev/null
            ;;
        "eventbridge-bus")
            aws events describe-event-bus --name "$resource_name" &>/dev/null
            ;;
        "dynamodb-table")
            aws dynamodb describe-table --table-name "$resource_name" &>/dev/null
            ;;
        "lambda-function")
            aws lambda get-function --function-name "$resource_name" &>/dev/null
            ;;
        "sqs-queue")
            aws sqs get-queue-url --queue-name "$resource_name" &>/dev/null
            ;;
        "cloudwatch-alarm")
            aws cloudwatch describe-alarms --alarm-names "$resource_name" --query 'MetricAlarms[0]' --output text &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    local alarms=(
        "EventStore-WriteThrottles-${RANDOM_SUFFIX}"
        "CommandHandler-Errors-${RANDOM_SUFFIX}"
        "EventBridge-FailedInvocations-${RANDOM_SUFFIX}"
    )
    
    for alarm in "${alarms[@]}"; do
        if resource_exists "cloudwatch-alarm" "$alarm"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                info "[DRY RUN] Would delete CloudWatch alarm: $alarm"
            else
                aws cloudwatch delete-alarms --alarm-names "$alarm"
                log "Deleted CloudWatch alarm: $alarm ✅"
            fi
        else
            warn "CloudWatch alarm $alarm not found, skipping"
        fi
    done
}

# Delete EventBridge rules and targets
delete_eventbridge_rules() {
    log "Deleting EventBridge rules and targets..."
    
    local rules=("financial-events-rule" "failed-events-rule")
    
    for rule in "${rules[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete EventBridge rule: $rule"
        else
            # Remove targets first
            local targets=$(aws events list-targets-by-rule \
                --rule "$rule" \
                --event-bus-name "$EVENT_BUS_NAME" \
                --query 'Targets[].Id' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$targets" ]]; then
                aws events remove-targets \
                    --rule "$rule" \
                    --event-bus-name "$EVENT_BUS_NAME" \
                    --ids $targets
                info "Removed targets from rule: $rule"
            fi
            
            # Delete the rule
            aws events delete-rule \
                --name "$rule" \
                --event-bus-name "$EVENT_BUS_NAME" 2>/dev/null || warn "Rule $rule not found"
            
            log "Deleted EventBridge rule: $rule ✅"
        fi
    done
}

# Delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    local functions=("$COMMAND_FUNCTION" "$PROJECTION_FUNCTION" "$QUERY_FUNCTION")
    
    for func in "${functions[@]}"; do
        if resource_exists "lambda-function" "$func"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                info "[DRY RUN] Would delete Lambda function: $func"
            else
                # Remove EventBridge permissions first
                aws lambda remove-permission \
                    --function-name "$func" \
                    --statement-id "allow-eventbridge-invoke" 2>/dev/null || warn "Permission not found for $func"
                
                # Delete the function
                aws lambda delete-function --function-name "$func"
                log "Deleted Lambda function: $func ✅"
            fi
        else
            warn "Lambda function $func not found, skipping"
        fi
    done
}

# Delete SQS queue
delete_sqs_queue() {
    log "Deleting SQS queue..."
    
    if resource_exists "sqs-queue" "$DLQ_NAME"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete SQS queue: $DLQ_NAME"
        else
            local queue_url=$(aws sqs get-queue-url --queue-name "$DLQ_NAME" --query 'QueueUrl' --output text)
            aws sqs delete-queue --queue-url "$queue_url"
            log "Deleted SQS queue: $DLQ_NAME ✅"
        fi
    else
        warn "SQS queue $DLQ_NAME not found, skipping"
    fi
}

# Delete EventBridge resources
delete_eventbridge_resources() {
    log "Deleting EventBridge resources..."
    
    if resource_exists "eventbridge-bus" "$EVENT_BUS_NAME"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete EventBridge bus: $EVENT_BUS_NAME"
        else
            # Delete archive first
            aws events delete-archive --archive-name "${EVENT_BUS_NAME}-archive" 2>/dev/null || warn "Archive not found"
            
            # Delete the event bus
            aws events delete-event-bus --name "$EVENT_BUS_NAME"
            log "Deleted EventBridge bus: $EVENT_BUS_NAME ✅"
        fi
    else
        warn "EventBridge bus $EVENT_BUS_NAME not found, skipping"
    fi
}

# Delete DynamoDB tables
delete_dynamodb_tables() {
    log "Deleting DynamoDB tables..."
    
    local tables=("$EVENT_STORE_TABLE" "$READ_MODEL_TABLE")
    
    for table in "${tables[@]}"; do
        if resource_exists "dynamodb-table" "$table"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                info "[DRY RUN] Would delete DynamoDB table: $table"
            else
                aws dynamodb delete-table --table-name "$table"
                log "Initiated deletion of DynamoDB table: $table ✅"
                
                # Wait for table to be deleted (optional, can be slow)
                info "Waiting for table $table to be deleted..."
                aws dynamodb wait table-not-exists --table-name "$table" &
            fi
        else
            warn "DynamoDB table $table not found, skipping"
        fi
    done
    
    # Wait for all background table deletions to complete
    if [[ "$DRY_RUN" == "false" ]]; then
        wait
        log "All DynamoDB table deletions completed ✅"
    fi
}

# Delete IAM resources
delete_iam_resources() {
    if [[ "$KEEP_IAM" == "true" ]]; then
        warn "Keeping IAM resources as requested"
        return
    fi
    
    log "Deleting IAM resources..."
    
    local role_name="event-sourcing-lambda-role"
    local policy_name="EventSourcingPolicy"
    
    if resource_exists "iam-role" "$role_name"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete IAM role: $role_name"
        else
            # Detach policies first
            aws iam detach-role-policy \
                --role-name "$role_name" \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || warn "Basic execution policy not attached"
            
            aws iam detach-role-policy \
                --role-name "$role_name" \
                --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$policy_name" 2>/dev/null || warn "Custom policy not attached"
            
            # Delete the role
            aws iam delete-role --role-name "$role_name"
            log "Deleted IAM role: $role_name ✅"
        fi
    else
        warn "IAM role $role_name not found, skipping"
    fi
    
    if resource_exists "iam-policy" "$policy_name"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete IAM policy: $policy_name"
        else
            aws iam delete-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$policy_name"
            log "Deleted IAM policy: $policy_name ✅"
        fi
    else
        warn "IAM policy $policy_name not found, skipping"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "command-handler.py"
        "command-handler.zip"
        "projection-handler.py"
        "projection-handler.zip"
        "query-handler.py"
        "query-handler.zip"
        "response.json"
        "response2.json"
        "reconstruction.json"
        "replay-config.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                info "[DRY RUN] Would remove file: $file"
            else
                rm -f "$file"
                info "Removed file: $file"
            fi
        fi
    done
    
    # Remove deployment config file
    if [[ -f "$CONFIG_FILE" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would remove config file: $CONFIG_FILE"
        else
            rm -f "$CONFIG_FILE"
            log "Removed configuration file: $CONFIG_FILE ✅"
        fi
    fi
}

# Validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would validate cleanup"
        return
    fi
    
    local remaining_resources=0
    
    # Check if resources still exist
    if resource_exists "eventbridge-bus" "$EVENT_BUS_NAME"; then
        warn "EventBridge bus $EVENT_BUS_NAME still exists"
        ((remaining_resources++))
    fi
    
    if resource_exists "dynamodb-table" "$EVENT_STORE_TABLE"; then
        warn "DynamoDB table $EVENT_STORE_TABLE still exists (may be in deletion process)"
        ((remaining_resources++))
    fi
    
    if resource_exists "dynamodb-table" "$READ_MODEL_TABLE"; then
        warn "DynamoDB table $READ_MODEL_TABLE still exists (may be in deletion process)"
        ((remaining_resources++))
    fi
    
    if resource_exists "lambda-function" "$COMMAND_FUNCTION"; then
        warn "Lambda function $COMMAND_FUNCTION still exists"
        ((remaining_resources++))
    fi
    
    if resource_exists "lambda-function" "$PROJECTION_FUNCTION"; then
        warn "Lambda function $PROJECTION_FUNCTION still exists"
        ((remaining_resources++))
    fi
    
    if resource_exists "lambda-function" "$QUERY_FUNCTION"; then
        warn "Lambda function $QUERY_FUNCTION still exists"
        ((remaining_resources++))
    fi
    
    if resource_exists "sqs-queue" "$DLQ_NAME"; then
        warn "SQS queue $DLQ_NAME still exists"
        ((remaining_resources++))
    fi
    
    if [[ "$KEEP_IAM" == "false" ]]; then
        if resource_exists "iam-role" "event-sourcing-lambda-role"; then
            warn "IAM role event-sourcing-lambda-role still exists"
            ((remaining_resources++))
        fi
        
        if resource_exists "iam-policy" "EventSourcingPolicy"; then
            warn "IAM policy EventSourcingPolicy still exists"
            ((remaining_resources++))
        fi
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
        log "Cleanup validation passed ✅"
    else
        warn "Cleanup validation found $remaining_resources remaining resources"
        warn "Some resources may still be in deletion process (especially DynamoDB tables)"
    fi
}

# Print cleanup summary
print_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account ID: $AWS_ACCOUNT_ID"
    echo "Resource Suffix: $RANDOM_SUFFIX"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN MODE - No resources were actually deleted"
    else
        echo "Deleted Resources:"
        echo "- EventBridge Bus: $EVENT_BUS_NAME"
        echo "- Event Store Table: $EVENT_STORE_TABLE"
        echo "- Read Model Table: $READ_MODEL_TABLE"
        echo "- Lambda Functions: $COMMAND_FUNCTION, $PROJECTION_FUNCTION, $QUERY_FUNCTION"
        echo "- SQS Queue: $DLQ_NAME"
        echo "- CloudWatch Alarms and EventBridge Rules"
        
        if [[ "$KEEP_IAM" == "false" ]]; then
            echo "- IAM Roles and Policies"
        fi
        
        echo ""
        echo "Local files and configuration cleaned up"
    fi
    
    echo ""
    echo "Notes:"
    echo "- DynamoDB tables may take several minutes to be fully deleted"
    echo "- Check the AWS console to confirm all resources are removed"
    echo "- CloudWatch logs are retained and may incur minimal costs"
}

# Main cleanup function
main() {
    log "Starting Event Sourcing Architecture cleanup..."
    
    # Check prerequisites
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Load configuration
    load_config
    
    # Confirm destruction
    confirm_destruction
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN MODE - No resources will be deleted"
    fi
    
    # Delete resources in reverse order of creation
    delete_cloudwatch_alarms
    delete_eventbridge_rules
    delete_lambda_functions
    delete_sqs_queue
    delete_eventbridge_resources
    delete_dynamodb_tables
    delete_iam_resources
    
    # Clean up local files
    cleanup_local_files
    
    # Validate cleanup
    validate_cleanup
    
    # Print summary
    print_summary
    
    log "Cleanup completed successfully! 🎉"
}

# Run main function
main "$@"