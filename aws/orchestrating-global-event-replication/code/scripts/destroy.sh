#!/bin/bash

# AWS Multi-Region Event Replication with EventBridge - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/deployment_config.json"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration
DEFAULT_PRIMARY_REGION="us-east-1"
DEFAULT_SECONDARY_REGION="us-west-2"
DEFAULT_TERTIARY_REGION="eu-west-1"

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${ERROR_LOG}" >&2)

# Utility functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $1${NC}"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command_exists jq; then
        error "jq is not installed. Please install it first."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Load deployment configuration
load_deployment_config() {
    log "Loading deployment configuration..."
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        error "Deployment configuration file not found: ${CONFIG_FILE}"
        error "Please ensure the deployment script was run successfully."
        exit 1
    fi
    
    # Read configuration values
    DEPLOYMENT_ID=$(jq -r '.deployment_id' "${CONFIG_FILE}")
    PRIMARY_REGION=$(jq -r '.regions.primary' "${CONFIG_FILE}")
    SECONDARY_REGION=$(jq -r '.regions.secondary' "${CONFIG_FILE}")
    TERTIARY_REGION=$(jq -r '.regions.tertiary' "${CONFIG_FILE}")
    
    EVENT_BUS_NAME=$(jq -r '.resources.event_bus_name' "${CONFIG_FILE}")
    LAMBDA_FUNCTION_NAME=$(jq -r '.resources.lambda_function_name' "${CONFIG_FILE}")
    GLOBAL_ENDPOINT_NAME=$(jq -r '.resources.global_endpoint_name' "${CONFIG_FILE}")
    HEALTH_CHECK_NAME=$(jq -r '.resources.health_check_name' "${CONFIG_FILE}")
    SNS_TOPIC_ARN=$(jq -r '.resources.sns_topic_arn' "${CONFIG_FILE}")
    GLOBAL_ENDPOINT_ARN=$(jq -r '.resources.global_endpoint_arn' "${CONFIG_FILE}")
    HEALTH_CHECK_ID=$(jq -r '.resources.health_check_id' "${CONFIG_FILE}")
    
    AWS_ACCOUNT_ID=$(jq -r '.account_id' "${CONFIG_FILE}")
    RANDOM_SUFFIX=$(jq -r '.random_suffix' "${CONFIG_FILE}")
    
    log "Configuration loaded for deployment: ${DEPLOYMENT_ID}"
    log "Primary region: ${PRIMARY_REGION}"
    log "Secondary region: ${SECONDARY_REGION}"
    log "Tertiary region: ${TERTIARY_REGION}"
    log "Random suffix: ${RANDOM_SUFFIX}"
}

# Confirm destruction
confirm_destruction() {
    if [[ "${FORCE:-false}" == "true" ]]; then
        log "FORCE mode enabled, skipping confirmation"
        return 0
    fi
    
    echo
    echo -e "${RED}WARNING: This will delete all resources created by the deployment script!${NC}"
    echo "The following resources will be deleted:"
    echo "- Event buses in all regions: ${EVENT_BUS_NAME}"
    echo "- Lambda functions in all regions: ${LAMBDA_FUNCTION_NAME}"
    echo "- Global endpoint: ${GLOBAL_ENDPOINT_NAME}"
    echo "- Route 53 health check: ${HEALTH_CHECK_ID}"
    echo "- SNS topic: ${SNS_TOPIC_ARN}"
    echo "- CloudWatch alarms and dashboard"
    echo "- EventBridge rules and targets"
    echo "- IAM roles: lambda-execution-role, eventbridge-cross-region-role"
    echo
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed by user"
}

# Wait for resource to be deleted
wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local region="$3"
    local max_attempts=30
    local attempt=1
    
    debug "Waiting for $resource_type: $resource_name to be deleted in region: $region"
    
    while [[ $attempt -le $max_attempts ]]; do
        case "$resource_type" in
            "lambda")
                if ! aws lambda get-function --function-name "$resource_name" --region "$region" >/dev/null 2>&1; then
                    debug "$resource_type $resource_name has been deleted"
                    return 0
                fi
                ;;
            "eventbus")
                if ! aws events describe-event-bus --name "$resource_name" --region "$region" >/dev/null 2>&1; then
                    debug "$resource_type $resource_name has been deleted"
                    return 0
                fi
                ;;
            "endpoint")
                if ! aws events describe-endpoint --name "$resource_name" --region "$region" >/dev/null 2>&1; then
                    debug "$resource_type $resource_name has been deleted"
                    return 0
                fi
                ;;
            "role")
                if ! aws iam get-role --role-name "$resource_name" >/dev/null 2>&1; then
                    debug "$resource_type $resource_name has been deleted"
                    return 0
                fi
                ;;
        esac
        
        debug "Attempt $attempt/$max_attempts: $resource_type $resource_name still exists, waiting..."
        sleep 10
        ((attempt++))
    done
    
    warn "Timeout waiting for $resource_type: $resource_name to be deleted"
    return 1
}

# Remove global endpoint and health check
remove_global_endpoint() {
    log "Removing global endpoint and health check..."
    
    # Delete global endpoint
    if aws events describe-endpoint --name "${GLOBAL_ENDPOINT_NAME}" --region "${PRIMARY_REGION}" >/dev/null 2>&1; then
        aws events delete-endpoint \
            --name "${GLOBAL_ENDPOINT_NAME}" \
            --region "${PRIMARY_REGION}"
        
        wait_for_deletion "endpoint" "${GLOBAL_ENDPOINT_NAME}" "${PRIMARY_REGION}"
        log "Global endpoint deleted: ${GLOBAL_ENDPOINT_NAME}"
    else
        warn "Global endpoint not found: ${GLOBAL_ENDPOINT_NAME}"
    fi
    
    # Delete Route 53 health check
    if aws route53 get-health-check --health-check-id "${HEALTH_CHECK_ID}" >/dev/null 2>&1; then
        aws route53 delete-health-check \
            --health-check-id "${HEALTH_CHECK_ID}"
        
        log "Health check deleted: ${HEALTH_CHECK_ID}"
    else
        warn "Health check not found: ${HEALTH_CHECK_ID}"
    fi
}

# Remove EventBridge rules and targets
remove_eventbridge_rules() {
    log "Removing EventBridge rules and targets..."
    
    # Remove targets and rules from primary region
    if aws events describe-rule --name "cross-region-replication-rule" --event-bus-name "${EVENT_BUS_NAME}" --region "${PRIMARY_REGION}" >/dev/null 2>&1; then
        # Remove targets first
        aws events remove-targets \
            --rule cross-region-replication-rule \
            --ids "1" "2" "3" \
            --event-bus-name "${EVENT_BUS_NAME}" \
            --region "${PRIMARY_REGION}" 2>/dev/null || true
        
        # Delete rule
        aws events delete-rule \
            --name "cross-region-replication-rule" \
            --event-bus-name "${EVENT_BUS_NAME}" \
            --region "${PRIMARY_REGION}"
        
        debug "Cross-region replication rule deleted from primary region"
    else
        warn "Cross-region replication rule not found in primary region"
    fi
    
    # Remove targets and rules from secondary and tertiary regions
    local regions=("${SECONDARY_REGION}" "${TERTIARY_REGION}")
    
    for region in "${regions[@]}"; do
        if aws events describe-rule --name "local-processing-rule" --event-bus-name "${EVENT_BUS_NAME}" --region "$region" >/dev/null 2>&1; then
            # Remove targets first
            aws events remove-targets \
                --rule local-processing-rule \
                --ids "1" \
                --event-bus-name "${EVENT_BUS_NAME}" \
                --region "$region" 2>/dev/null || true
            
            # Delete rule
            aws events delete-rule \
                --name "local-processing-rule" \
                --event-bus-name "${EVENT_BUS_NAME}" \
                --region "$region"
            
            debug "Local processing rule deleted from region: $region"
        else
            warn "Local processing rule not found in region: $region"
        fi
    done
    
    # Remove specialized event pattern rules
    local specialized_rules=("financial-events-rule" "user-events-rule" "system-events-rule")
    
    for rule in "${specialized_rules[@]}"; do
        if aws events describe-rule --name "$rule" --event-bus-name "${EVENT_BUS_NAME}" --region "${PRIMARY_REGION}" >/dev/null 2>&1; then
            aws events delete-rule \
                --name "$rule" \
                --event-bus-name "${EVENT_BUS_NAME}" \
                --region "${PRIMARY_REGION}"
            
            debug "Specialized rule deleted: $rule"
        else
            warn "Specialized rule not found: $rule"
        fi
    done
    
    log "EventBridge rules and targets removed"
}

# Remove Lambda functions
remove_lambda_functions() {
    log "Removing Lambda functions..."
    
    local regions=("${PRIMARY_REGION}" "${SECONDARY_REGION}" "${TERTIARY_REGION}")
    
    for region in "${regions[@]}"; do
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" --region "$region" >/dev/null 2>&1; then
            aws lambda delete-function \
                --function-name "${LAMBDA_FUNCTION_NAME}" \
                --region "$region"
            
            wait_for_deletion "lambda" "${LAMBDA_FUNCTION_NAME}" "$region"
            debug "Lambda function deleted from region: $region"
        else
            warn "Lambda function not found in region: $region"
        fi
    done
    
    log "Lambda functions removed from all regions"
}

# Remove event buses
remove_event_buses() {
    log "Removing custom event buses..."
    
    local regions=("${PRIMARY_REGION}" "${SECONDARY_REGION}" "${TERTIARY_REGION}")
    
    for region in "${regions[@]}"; do
        if aws events describe-event-bus --name "${EVENT_BUS_NAME}" --region "$region" >/dev/null 2>&1; then
            # Remove permissions first
            aws events remove-permission \
                --statement-id "AllowCrossRegionAccess" \
                --event-bus-name "${EVENT_BUS_NAME}" \
                --region "$region" 2>/dev/null || true
            
            # Delete event bus
            aws events delete-event-bus \
                --name "${EVENT_BUS_NAME}" \
                --region "$region"
            
            wait_for_deletion "eventbus" "${EVENT_BUS_NAME}" "$region"
            debug "Event bus deleted from region: $region"
        else
            warn "Event bus not found in region: $region"
        fi
    done
    
    log "Custom event buses removed from all regions"
}

# Remove CloudWatch monitoring resources
remove_monitoring_resources() {
    log "Removing CloudWatch monitoring resources..."
    
    # Delete CloudWatch alarms
    local alarms=(
        "EventBridge-FailedInvocations-${RANDOM_SUFFIX}"
        "Lambda-Errors-${RANDOM_SUFFIX}"
    )
    
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --region "${PRIMARY_REGION}" --query 'MetricAlarms[0]' --output text >/dev/null 2>&1; then
            aws cloudwatch delete-alarms \
                --alarm-names "$alarm" \
                --region "${PRIMARY_REGION}"
            
            debug "CloudWatch alarm deleted: $alarm"
        else
            warn "CloudWatch alarm not found: $alarm"
        fi
    done
    
    # Delete CloudWatch dashboard
    local dashboard_name="EventBridge-MultiRegion-${RANDOM_SUFFIX}"
    if aws cloudwatch get-dashboard --dashboard-name "$dashboard_name" --region "${PRIMARY_REGION}" >/dev/null 2>&1; then
        aws cloudwatch delete-dashboards \
            --dashboard-names "$dashboard_name" \
            --region "${PRIMARY_REGION}"
        
        debug "CloudWatch dashboard deleted: $dashboard_name"
    else
        warn "CloudWatch dashboard not found: $dashboard_name"
    fi
    
    log "CloudWatch monitoring resources removed"
}

# Remove SNS topic
remove_sns_topic() {
    log "Removing SNS topic..."
    
    if aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}" --region "${PRIMARY_REGION}" >/dev/null 2>&1; then
        aws sns delete-topic \
            --topic-arn "${SNS_TOPIC_ARN}" \
            --region "${PRIMARY_REGION}"
        
        log "SNS topic deleted: ${SNS_TOPIC_ARN}"
    else
        warn "SNS topic not found: ${SNS_TOPIC_ARN}"
    fi
}

# Remove IAM roles
remove_iam_roles() {
    log "Removing IAM roles..."
    
    # Remove EventBridge cross-region role
    if aws iam get-role --role-name eventbridge-cross-region-role >/dev/null 2>&1; then
        # Delete inline policy first
        aws iam delete-role-policy \
            --role-name eventbridge-cross-region-role \
            --policy-name EventBridgeCrossRegionPolicy 2>/dev/null || true
        
        # Delete role
        aws iam delete-role \
            --role-name eventbridge-cross-region-role
        
        wait_for_deletion "role" "eventbridge-cross-region-role" "global"
        debug "EventBridge cross-region role deleted"
    else
        warn "EventBridge cross-region role not found"
    fi
    
    # Remove Lambda execution role
    if aws iam get-role --role-name lambda-execution-role >/dev/null 2>&1; then
        # Detach managed policy first
        aws iam detach-role-policy \
            --role-name lambda-execution-role \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        
        # Delete role
        aws iam delete-role \
            --role-name lambda-execution-role
        
        wait_for_deletion "role" "lambda-execution-role" "global"
        debug "Lambda execution role deleted"
    else
        warn "Lambda execution role not found"
    fi
    
    log "IAM roles removed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files
    local files_to_remove=(
        "${SCRIPT_DIR}/lambda_function.py"
        "${SCRIPT_DIR}/lambda_function.zip"
        "${SCRIPT_DIR}/eventbridge-cross-region-trust-policy.json"
        "${SCRIPT_DIR}/eventbridge-cross-region-permissions.json"
        "${SCRIPT_DIR}/event-bus-policy.json"
        "${SCRIPT_DIR}/test-event.json"
        "${SCRIPT_DIR}/financial-events-pattern.json"
        "${SCRIPT_DIR}/user-events-pattern.json"
        "${SCRIPT_DIR}/system-events-pattern.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            debug "Removed file: $file"
        fi
    done
    
    # Remove deployment configuration if requested
    if [[ "${REMOVE_CONFIG:-false}" == "true" ]]; then
        if [[ -f "${CONFIG_FILE}" ]]; then
            rm -f "${CONFIG_FILE}"
            log "Deployment configuration file removed"
        fi
    else
        log "Deployment configuration file preserved: ${CONFIG_FILE}"
    fi
    
    log "Local files cleaned up"
}

# Validate destruction
validate_destruction() {
    log "Validating resource destruction..."
    
    local validation_errors=0
    
    # Check Lambda functions
    local regions=("${PRIMARY_REGION}" "${SECONDARY_REGION}" "${TERTIARY_REGION}")
    
    for region in "${regions[@]}"; do
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" --region "$region" >/dev/null 2>&1; then
            error "Lambda function still exists in region: $region"
            ((validation_errors++))
        fi
    done
    
    # Check event buses
    for region in "${regions[@]}"; do
        if aws events describe-event-bus --name "${EVENT_BUS_NAME}" --region "$region" >/dev/null 2>&1; then
            error "Event bus still exists in region: $region"
            ((validation_errors++))
        fi
    done
    
    # Check global endpoint
    if aws events describe-endpoint --name "${GLOBAL_ENDPOINT_NAME}" --region "${PRIMARY_REGION}" >/dev/null 2>&1; then
        error "Global endpoint still exists"
        ((validation_errors++))
    fi
    
    # Check health check
    if aws route53 get-health-check --health-check-id "${HEALTH_CHECK_ID}" >/dev/null 2>&1; then
        error "Health check still exists"
        ((validation_errors++))
    fi
    
    # Check IAM roles
    local roles=("lambda-execution-role" "eventbridge-cross-region-role")
    for role in "${roles[@]}"; do
        if aws iam get-role --role-name "$role" >/dev/null 2>&1; then
            error "IAM role still exists: $role"
            ((validation_errors++))
        fi
    done
    
    if [[ $validation_errors -eq 0 ]]; then
        log "All resources successfully destroyed"
        return 0
    else
        error "Destruction validation failed with $validation_errors errors"
        return 1
    fi
}

# Main destruction function
main() {
    log "Starting AWS Multi-Region EventBridge cleanup..."
    
    # Check if dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "DRY RUN MODE: No resources will be deleted"
        load_deployment_config
        log "Would delete resources for deployment: ${DEPLOYMENT_ID}"
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment configuration
    load_deployment_config
    
    # Confirm destruction
    confirm_destruction
    
    # Remove resources in reverse order of creation
    remove_global_endpoint
    remove_eventbridge_rules
    remove_lambda_functions
    remove_event_buses
    remove_monitoring_resources
    remove_sns_topic
    remove_iam_roles
    
    # Clean up local files
    cleanup_local_files
    
    # Validate destruction
    if validate_destruction; then
        log "Cleanup completed successfully!"
        log "All resources for deployment ${DEPLOYMENT_ID} have been removed"
    else
        warn "Cleanup completed with some issues. Please review the logs."
        exit 1
    fi
    
    # Print summary
    echo
    echo "Cleanup Summary:"
    echo "- Deployment ID: ${DEPLOYMENT_ID}"
    echo "- Regions processed: ${PRIMARY_REGION}, ${SECONDARY_REGION}, ${TERTIARY_REGION}"
    echo "- All EventBridge resources removed"
    echo "- All Lambda functions removed"
    echo "- All monitoring resources removed"
    echo "- All IAM roles removed"
    echo "- Local files cleaned up"
    echo
    echo "Note: CloudWatch logs are retained by default and may incur small charges."
    echo "You can manually delete them from the AWS Console if needed."
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        --remove-config)
            REMOVE_CONFIG=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run         Show what would be deleted without actually deleting"
            echo "  --force           Skip confirmation prompts"
            echo "  --debug           Enable debug logging"
            echo "  --remove-config   Remove deployment configuration file after cleanup"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"