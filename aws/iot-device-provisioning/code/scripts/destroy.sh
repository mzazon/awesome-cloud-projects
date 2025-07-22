#!/bin/bash

# IoT Device Provisioning and Certificate Management - Cleanup Script
# This script safely removes all resources created by the deployment script
# Based on the recipe: IoT Device Provisioning and Certificate Management

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE_DELETE=false
SKIP_CONFIRMATION=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force           Force deletion without additional prompts"
            echo "  --yes             Skip confirmation prompts"
            echo "  --config FILE     Use specific configuration file"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Load deployment configuration
load_deployment_config() {
    log "Loading deployment configuration..."
    
    # Try to load from specified config file or default location
    local config_file="${CONFIG_FILE:-/tmp/iot-provisioning-deployment.env}"
    
    if [[ -f "$config_file" ]]; then
        source "$config_file"
        log "Configuration loaded from: $config_file"
    else
        warn "Configuration file not found: $config_file"
        warn "Attempting to discover resources automatically..."
        
        # Try to discover resources automatically
        discover_resources
    fi
    
    # Validate required variables
    if [[ -z "${AWS_REGION:-}" || -z "${AWS_ACCOUNT_ID:-}" ]]; then
        # Set from AWS CLI if not in config
        export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
        export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
    fi
    
    log "AWS Region: ${AWS_REGION}"
    log "AWS Account: ${AWS_ACCOUNT_ID}"
}

# Discover resources automatically if config is missing
discover_resources() {
    log "Discovering IoT provisioning resources..."
    
    # Find provisioning templates
    local templates=$(aws iot list-provisioning-templates --query 'templates[?contains(templateName, `device-provisioning-template`)].templateName' --output text)
    if [[ -n "$templates" ]]; then
        TEMPLATE_NAME=$(echo "$templates" | head -1)
        log "Found provisioning template: $TEMPLATE_NAME"
    fi
    
    # Find Lambda functions
    local functions=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `device-provisioning-hook`)].FunctionName' --output text)
    if [[ -n "$functions" ]]; then
        HOOK_FUNCTION_NAME=$(echo "$functions" | head -1)
        log "Found Lambda function: $HOOK_FUNCTION_NAME"
    fi
    
    # Find DynamoDB tables
    local tables=$(aws dynamodb list-tables --query 'TableNames[?contains(@, `device-registry`)]' --output text)
    if [[ -n "$tables" ]]; then
        DEVICE_REGISTRY_TABLE=$(echo "$tables" | head -1)
        log "Found DynamoDB table: $DEVICE_REGISTRY_TABLE"
    fi
    
    # Find IAM roles
    local roles=$(aws iam list-roles --query 'Roles[?contains(RoleName, `iot-provisioning-role`)].RoleName' --output text)
    if [[ -n "$roles" ]]; then
        IOT_ROLE_NAME=$(echo "$roles" | head -1)
        log "Found IoT role: $IOT_ROLE_NAME"
    fi
    
    # Find thing groups
    local groups=$(aws iot list-thing-groups --query 'thingGroups[?contains(groupName, `provisioned-devices`)].groupName' --output text)
    if [[ -n "$groups" ]]; then
        THING_GROUP_NAME=$(echo "$groups" | head -1)
        log "Found thing group: $THING_GROUP_NAME"
    fi
}

# Confirm deletion with user
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == true ]]; then
        return 0
    fi
    
    echo ""
    warn "⚠️  WARNING: This will permanently delete all IoT provisioning resources!"
    echo ""
    echo "Resources to be deleted:"
    echo "- Provisioning Template: ${TEMPLATE_NAME:-Not found}"
    echo "- Lambda Functions: ${HOOK_FUNCTION_NAME:-Not found}, ${SHADOW_INIT_FUNCTION_NAME:-Not found}"
    echo "- DynamoDB Table: ${DEVICE_REGISTRY_TABLE:-Not found}"
    echo "- IAM Roles and Policies: ${IOT_ROLE_NAME:-Not found}"
    echo "- Thing Groups: ${THING_GROUP_NAME:-Not found}"
    echo "- IoT Policies: TemperatureSensorPolicy, GatewayDevicePolicy, ClaimCertificatePolicy"
    echo "- CloudWatch Log Groups and Alarms"
    echo "- Claim Certificates"
    echo ""
    
    read -p "Are you sure you want to continue? (Type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed. Proceeding with cleanup..."
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured"
        exit 1
    fi
    
    # Check for jq if claim certificates need to be processed
    if ! command -v jq &> /dev/null; then
        warn "jq not found - some certificate operations may be skipped"
    fi
    
    log "Prerequisites check completed"
}

# Delete provisioning template and claim certificates
delete_provisioning_resources() {
    log "Deleting provisioning template and claim certificates..."
    
    # Delete provisioning template
    if [[ -n "${TEMPLATE_NAME:-}" ]]; then
        if aws iot describe-provisioning-template --template-name "$TEMPLATE_NAME" > /dev/null 2>&1; then
            aws iot delete-provisioning-template --template-name "$TEMPLATE_NAME" || warn "Failed to delete provisioning template"
            log "✓ Provisioning template deleted: $TEMPLATE_NAME"
        else
            warn "Provisioning template not found: $TEMPLATE_NAME"
        fi
    fi
    
    # Delete claim certificates
    if [[ -n "${CLAIM_CERT_ARN:-}" && -n "${CLAIM_CERT_ID:-}" ]]; then
        # Detach policy from claim certificate
        aws iot detach-policy \
            --policy-name "ClaimCertificatePolicy" \
            --target "$CLAIM_CERT_ARN" 2>/dev/null || warn "Failed to detach policy from claim certificate"
        
        # Deactivate and delete claim certificate
        aws iot update-certificate \
            --certificate-id "$CLAIM_CERT_ID" \
            --new-status INACTIVE 2>/dev/null || warn "Failed to deactivate claim certificate"
        
        aws iot delete-certificate \
            --certificate-id "$CLAIM_CERT_ID" 2>/dev/null || warn "Failed to delete claim certificate"
        
        log "✓ Claim certificate deleted: $CLAIM_CERT_ID"
    else
        warn "Claim certificate information not found in configuration"
    fi
    
    # Clean up local certificate files
    rm -f /tmp/claim-certificate.pem /tmp/claim-public-key.pem /tmp/claim-private-key.pem
    rm -f /tmp/claim-cert-output.json
    
    log "Provisioning resources cleanup completed"
}

# Delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    # Delete pre-provisioning hook function
    if [[ -n "${HOOK_FUNCTION_NAME:-}" ]]; then
        if aws lambda get-function --function-name "$HOOK_FUNCTION_NAME" > /dev/null 2>&1; then
            aws lambda delete-function --function-name "$HOOK_FUNCTION_NAME" || warn "Failed to delete hook function"
            log "✓ Lambda function deleted: $HOOK_FUNCTION_NAME"
        else
            warn "Lambda function not found: $HOOK_FUNCTION_NAME"
        fi
    fi
    
    # Delete shadow initialization function
    if [[ -n "${SHADOW_INIT_FUNCTION_NAME:-}" ]]; then
        if aws lambda get-function --function-name "$SHADOW_INIT_FUNCTION_NAME" > /dev/null 2>&1; then
            aws lambda delete-function --function-name "$SHADOW_INIT_FUNCTION_NAME" || warn "Failed to delete shadow init function"
            log "✓ Lambda function deleted: $SHADOW_INIT_FUNCTION_NAME"
        else
            warn "Shadow init function not found: $SHADOW_INIT_FUNCTION_NAME"
        fi
    fi
    
    # Clean up Lambda deployment packages
    rm -f /tmp/lambda-functions/*.zip
    rm -rf /tmp/lambda-functions/
    
    log "Lambda functions cleanup completed"
}

# Delete IoT resources
delete_iot_resources() {
    log "Deleting IoT resources..."
    
    # Delete IoT policies
    local policies=("TemperatureSensorPolicy" "GatewayDevicePolicy" "ClaimCertificatePolicy")
    for policy in "${policies[@]}"; do
        if aws iot get-policy --policy-name "$policy" > /dev/null 2>&1; then
            # List and detach any attached targets first
            local targets=$(aws iot list-targets-for-policy --policy-name "$policy" --query 'targets' --output text 2>/dev/null || true)
            if [[ -n "$targets" ]]; then
                for target in $targets; do
                    aws iot detach-policy --policy-name "$policy" --target "$target" 2>/dev/null || true
                done
            fi
            
            aws iot delete-policy --policy-name "$policy" || warn "Failed to delete policy: $policy"
            log "✓ IoT policy deleted: $policy"
        else
            warn "IoT policy not found: $policy"
        fi
    done
    
    # Delete IoT topic rules
    local rules=$(aws iot list-topic-rules --query 'rules[?contains(ruleName, `ProvisioningAuditRule`)].ruleName' --output text)
    for rule in $rules; do
        aws iot delete-topic-rule --rule-name "$rule" || warn "Failed to delete topic rule: $rule"
        log "✓ IoT topic rule deleted: $rule"
    done
    
    # Delete thing groups (child groups first)
    local device_types=("temperature-sensor" "humidity-sensor" "pressure-sensor" "gateway")
    for device_type in "${device_types[@]}"; do
        local group_name="${device_type}-devices"
        if aws iot describe-thing-group --thing-group-name "$group_name" > /dev/null 2>&1; then
            aws iot delete-thing-group --thing-group-name "$group_name" || warn "Failed to delete thing group: $group_name"
            log "✓ Thing group deleted: $group_name"
        fi
    done
    
    # Delete parent thing group
    if [[ -n "${THING_GROUP_NAME:-}" ]]; then
        if aws iot describe-thing-group --thing-group-name "$THING_GROUP_NAME" > /dev/null 2>&1; then
            aws iot delete-thing-group --thing-group-name "$THING_GROUP_NAME" || warn "Failed to delete parent thing group"
            log "✓ Parent thing group deleted: $THING_GROUP_NAME"
        else
            warn "Parent thing group not found: $THING_GROUP_NAME"
        fi
    fi
    
    log "IoT resources cleanup completed"
}

# Delete DynamoDB table
delete_dynamodb_table() {
    log "Deleting DynamoDB table..."
    
    if [[ -n "${DEVICE_REGISTRY_TABLE:-}" ]]; then
        if aws dynamodb describe-table --table-name "$DEVICE_REGISTRY_TABLE" > /dev/null 2>&1; then
            aws dynamodb delete-table --table-name "$DEVICE_REGISTRY_TABLE" || warn "Failed to delete DynamoDB table"
            
            # Wait for table deletion to complete
            log "Waiting for table deletion to complete..."
            aws dynamodb wait table-not-exists --table-name "$DEVICE_REGISTRY_TABLE" || true
            
            log "✓ DynamoDB table deleted: $DEVICE_REGISTRY_TABLE"
        else
            warn "DynamoDB table not found: $DEVICE_REGISTRY_TABLE"
        fi
    fi
    
    log "DynamoDB cleanup completed"
}

# Delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    # Delete Lambda execution role and policy
    if [[ -n "${HOOK_FUNCTION_NAME:-}" ]]; then
        local lambda_role="${HOOK_FUNCTION_NAME}-execution-role"
        local lambda_policy="${HOOK_FUNCTION_NAME}-policy"
        
        # Detach and delete Lambda policy
        if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${lambda_policy}" > /dev/null 2>&1; then
            aws iam detach-role-policy \
                --role-name "$lambda_role" \
                --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${lambda_policy}" 2>/dev/null || true
            
            aws iam delete-policy \
                --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${lambda_policy}" || warn "Failed to delete Lambda policy"
            
            log "✓ Lambda policy deleted: $lambda_policy"
        fi
        
        # Delete Lambda execution role
        if aws iam get-role --role-name "$lambda_role" > /dev/null 2>&1; then
            aws iam delete-role --role-name "$lambda_role" || warn "Failed to delete Lambda role"
            log "✓ Lambda role deleted: $lambda_role"
        fi
    fi
    
    # Delete IoT provisioning role and policy
    if [[ -n "${IOT_ROLE_NAME:-}" ]]; then
        local iot_policy="${IOT_ROLE_NAME}-policy"
        
        # Detach and delete IoT policy
        if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${iot_policy}" > /dev/null 2>&1; then
            aws iam detach-role-policy \
                --role-name "$IOT_ROLE_NAME" \
                --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${iot_policy}" 2>/dev/null || true
            
            aws iam delete-policy \
                --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${iot_policy}" || warn "Failed to delete IoT policy"
            
            log "✓ IoT policy deleted: $iot_policy"
        fi
        
        # Delete IoT role
        if aws iam get-role --role-name "$IOT_ROLE_NAME" > /dev/null 2>&1; then
            aws iam delete-role --role-name "$IOT_ROLE_NAME" || warn "Failed to delete IoT role"
            log "✓ IoT role deleted: $IOT_ROLE_NAME"
        fi
    fi
    
    log "IAM resources cleanup completed"
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete CloudWatch alarms
    local alarms=$(aws cloudwatch describe-alarms --query 'MetricAlarms[?contains(AlarmName, `IoTProvisioning`)].AlarmName' --output text)
    for alarm in $alarms; do
        aws cloudwatch delete-alarms --alarm-names "$alarm" || warn "Failed to delete alarm: $alarm"
        log "✓ CloudWatch alarm deleted: $alarm"
    done
    
    # Delete CloudWatch log groups
    local log_groups=$(aws logs describe-log-groups --query 'logGroups[?contains(logGroupName, `iot/provisioning`)].logGroupName' --output text)
    for log_group in $log_groups; do
        aws logs delete-log-group --log-group-name "$log_group" || warn "Failed to delete log group: $log_group"
        log "✓ CloudWatch log group deleted: $log_group"
    done
    
    # Delete Lambda function log groups
    if [[ -n "${HOOK_FUNCTION_NAME:-}" ]]; then
        local lambda_log_group="/aws/lambda/${HOOK_FUNCTION_NAME}"
        if aws logs describe-log-groups --log-group-name-prefix "$lambda_log_group" --query 'logGroups[0].logGroupName' --output text > /dev/null 2>&1; then
            aws logs delete-log-group --log-group-name "$lambda_log_group" || warn "Failed to delete Lambda log group"
            log "✓ Lambda log group deleted: $lambda_log_group"
        fi
    fi
    
    if [[ -n "${SHADOW_INIT_FUNCTION_NAME:-}" ]]; then
        local shadow_log_group="/aws/lambda/${SHADOW_INIT_FUNCTION_NAME}"
        if aws logs describe-log-groups --log-group-name-prefix "$shadow_log_group" --query 'logGroups[0].logGroupName' --output text > /dev/null 2>&1; then
            aws logs delete-log-group --log-group-name "$shadow_log_group" || warn "Failed to delete shadow init log group"
            log "✓ Shadow init log group deleted: $shadow_log_group"
        fi
    fi
    
    log "CloudWatch resources cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files
    rm -f /tmp/iot-provisioning-*.json
    rm -f /tmp/lambda-*.json
    rm -f /tmp/*-policy.json
    rm -f /tmp/provisioning-template.json
    rm -f /tmp/claim-*.pem
    rm -f /tmp/claim-cert-output.json
    
    # Remove deployment configuration (with confirmation)
    if [[ -f "/tmp/iot-provisioning-deployment.env" ]]; then
        if [[ "$FORCE_DELETE" == true || "$SKIP_CONFIRMATION" == true ]]; then
            rm -f "/tmp/iot-provisioning-deployment.env"
            log "✓ Deployment configuration deleted"
        else
            read -p "Delete deployment configuration file? (y/n): " delete_config
            if [[ "$delete_config" == "y" || "$delete_config" == "Y" ]]; then
                rm -f "/tmp/iot-provisioning-deployment.env"
                log "✓ Deployment configuration deleted"
            else
                log "Deployment configuration preserved"
            fi
        fi
    fi
    
    log "Local files cleanup completed"
}

# Validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    local cleanup_errors=0
    
    # Check if provisioning template still exists
    if [[ -n "${TEMPLATE_NAME:-}" ]] && aws iot describe-provisioning-template --template-name "$TEMPLATE_NAME" > /dev/null 2>&1; then
        error "✗ Provisioning template still exists: $TEMPLATE_NAME"
        ((cleanup_errors++))
    else
        log "✓ Provisioning template cleanup verified"
    fi
    
    # Check if Lambda function still exists
    if [[ -n "${HOOK_FUNCTION_NAME:-}" ]] && aws lambda get-function --function-name "$HOOK_FUNCTION_NAME" > /dev/null 2>&1; then
        error "✗ Lambda function still exists: $HOOK_FUNCTION_NAME"
        ((cleanup_errors++))
    else
        log "✓ Lambda function cleanup verified"
    fi
    
    # Check if DynamoDB table still exists
    if [[ -n "${DEVICE_REGISTRY_TABLE:-}" ]] && aws dynamodb describe-table --table-name "$DEVICE_REGISTRY_TABLE" > /dev/null 2>&1; then
        error "✗ DynamoDB table still exists: $DEVICE_REGISTRY_TABLE"
        ((cleanup_errors++))
    else
        log "✓ DynamoDB table cleanup verified"
    fi
    
    if [[ $cleanup_errors -eq 0 ]]; then
        log "Cleanup validation completed successfully"
        return 0
    else
        warn "Cleanup validation found $cleanup_errors issues"
        return 1
    fi
}

# Print cleanup summary
print_cleanup_summary() {
    log "Cleanup Summary:"
    echo "===================="
    echo "AWS Region: ${AWS_REGION}"
    echo "AWS Account: ${AWS_ACCOUNT_ID}"
    echo ""
    echo "Resources Deleted:"
    echo "- Provisioning Template: ${TEMPLATE_NAME:-N/A}"
    echo "- Lambda Functions: ${HOOK_FUNCTION_NAME:-N/A}, ${SHADOW_INIT_FUNCTION_NAME:-N/A}"
    echo "- DynamoDB Table: ${DEVICE_REGISTRY_TABLE:-N/A}"
    echo "- IAM Roles: ${IOT_ROLE_NAME:-N/A}"
    echo "- Thing Groups: ${THING_GROUP_NAME:-N/A}"
    echo "- IoT Policies: TemperatureSensorPolicy, GatewayDevicePolicy, ClaimCertificatePolicy"
    echo "- CloudWatch Resources: Log groups and alarms"
    echo "- Claim Certificates: ${CLAIM_CERT_ID:-N/A}"
    echo ""
    echo "Cleanup completed at: $(date)"
    echo ""
    echo "Note: Some resources may take a few minutes to be fully removed."
    echo "If you encounter any issues, you can run this script again with --force flag."
}

# Main cleanup function
main() {
    log "Starting IoT Device Provisioning and Certificate Management cleanup..."
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_config
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_provisioning_resources
    delete_lambda_functions
    delete_iot_resources
    delete_dynamodb_table
    delete_iam_resources
    delete_cloudwatch_resources
    cleanup_local_files
    
    # Validate and summarize
    if validate_cleanup; then
        print_cleanup_summary
        log "Cleanup completed successfully!"
    else
        warn "Cleanup completed with some issues. Please review the logs above."
        exit 1
    fi
}

# Handle script interruption
cleanup_on_exit() {
    warn "Cleanup interrupted. Some resources may not have been deleted."
    warn "You can run this script again to complete the cleanup."
    exit 1
}

# Set up signal handlers
trap cleanup_on_exit INT TERM

# Run main function
main "$@"