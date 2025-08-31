#!/bin/bash

#######################################################################
# Private API Integration with VPC Lattice and EventBridge - Cleanup Script
# 
# This script removes all infrastructure created by the deploy.sh script
# for the private API integration demo.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Same AWS permissions as deployment
# - deployment_vars.env file from successful deployment
#
# Usage:
#   ./destroy.sh [--force] [--dry-run] [--keep-logs]
#
# Options:
#   --force       Skip confirmation prompts (use with caution)
#   --dry-run     Show what would be deleted without making changes
#   --keep-logs   Preserve CloudWatch logs and deployment logs
#   --help        Show this help message
#######################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_VARS="${SCRIPT_DIR}/deployment_vars.env"
FORCE_DELETE=false
DRY_RUN=false
KEEP_LOGS=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Help function
show_help() {
    cat << EOF
Private API Integration with VPC Lattice and EventBridge - Cleanup Script

Usage: $0 [OPTIONS]

Options:
    --force         Skip confirmation prompts (use with caution)
    --dry-run       Show what would be deleted without making changes
    --keep-logs     Preserve CloudWatch logs and deployment logs
    --help          Show this help message

Examples:
    $0                      # Interactive cleanup with confirmations
    $0 --dry-run           # Preview what would be deleted
    $0 --force             # Delete everything without prompts
    $0 --keep-logs         # Clean up but keep logs

Safety Features:
    - Interactive confirmations for destructive operations
    - Dry-run mode to preview changes
    - Detailed logging of all operations
    - Graceful handling of missing resources

For more information, see the recipe documentation.
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --keep-logs)
            KEEP_LOGS=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Initialize log file
mkdir -p "$(dirname "$LOG_FILE")"
echo "Cleanup started at $(date)" > "$LOG_FILE"

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check for deployment variables
    if [[ ! -f "$DEPLOYMENT_VARS" ]]; then
        error "Deployment variables file not found: $DEPLOYMENT_VARS"
        error "This file is created during deployment and contains resource identifiers."
        error "Without it, manual cleanup may be required."
        exit 1
    fi
    
    log "Prerequisites check completed"
}

# Load deployment variables
load_deployment_vars() {
    info "Loading deployment variables..."
    
    if [[ -f "$DEPLOYMENT_VARS" ]]; then
        source "$DEPLOYMENT_VARS"
        log "Loaded deployment variables from $DEPLOYMENT_VARS"
        
        # Verify required variables are set
        local required_vars=(
            "AWS_REGION" "AWS_ACCOUNT_ID" "RANDOM_SUFFIX"
            "VPC_LATTICE_SERVICE_NETWORK" "EVENTBRIDGE_BUS_NAME"
            "STEP_FUNCTION_NAME" "API_GATEWAY_NAME"
        )
        
        for var in "${required_vars[@]}"; do
            if [[ -z "${!var:-}" ]]; then
                warn "Required variable $var is not set"
            fi
        done
    else
        error "Cannot proceed without deployment variables"
        exit 1
    fi
}

# Confirmation prompt
confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log "Force mode enabled - proceeding with: $message"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would prompt: $message"
        return 0
    fi
    
    local prompt="$message (y/N): "
    if [[ "$default" == "y" ]]; then
        prompt="$message (Y/n): "
    fi
    
    echo -n -e "${YELLOW}$prompt${NC}"
    read -r response
    
    response=${response:-$default}
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Execute deletion command with safety checks
execute_delete() {
    local cmd="$1"
    local description="$2"
    local ignore_not_found="${3:-true}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would execute: $description"
        info "[DRY RUN] Command: $cmd"
        return 0
    fi
    
    info "Executing: $description"
    
    if eval "$cmd" 2>/dev/null; then
        log "✅ $description completed successfully"
        return 0
    else
        local exit_code=$?
        if [[ "$ignore_not_found" == "true" && $exit_code -ne 0 ]]; then
            warn "⚠️ $description - resource may not exist or already deleted"
            return 0
        else
            error "❌ Failed: $description"
            return 1
        fi
    fi
}

# Wait for resource deletion
wait_for_deletion() {
    local check_cmd="$1"
    local resource_name="$2"
    local max_attempts="${3:-15}"
    local sleep_interval="${4:-10}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would wait for $resource_name deletion"
        return 0
    fi
    
    info "Waiting for $resource_name to be deleted..."
    local attempts=0
    
    while [[ $attempts -lt $max_attempts ]]; do
        if ! eval "$check_cmd" &> /dev/null; then
            log "✅ $resource_name has been deleted"
            return 0
        fi
        
        ((attempts++))
        info "Attempt $attempts/$max_attempts - waiting ${sleep_interval}s..."
        sleep "$sleep_interval"
    done
    
    warn "⚠️ $resource_name deletion taking longer than expected"
    return 0  # Continue cleanup even if waiting times out
}

# Delete EventBridge resources
delete_eventbridge_resources() {
    info "Cleaning up EventBridge resources..."
    
    if confirm_action "Delete EventBridge rule and targets?"; then
        # Remove targets first
        execute_delete \
            "aws events remove-targets \
                --event-bus-name \"${EVENTBRIDGE_BUS_NAME}\" \
                --rule \"trigger-private-api-workflow-${RANDOM_SUFFIX}\" \
                --ids \"1\"" \
            "Remove EventBridge rule targets"
        
        # Delete rule
        execute_delete \
            "aws events delete-rule \
                --event-bus-name \"${EVENTBRIDGE_BUS_NAME}\" \
                --name \"trigger-private-api-workflow-${RANDOM_SUFFIX}\"" \
            "Delete EventBridge rule"
        
        # Delete custom event bus
        execute_delete \
            "aws events delete-event-bus --name \"${EVENTBRIDGE_BUS_NAME}\"" \
            "Delete EventBridge custom bus"
        
        # Delete connection
        execute_delete \
            "aws events delete-connection --name \"private-api-connection-${RANDOM_SUFFIX}\"" \
            "Delete EventBridge connection"
    fi
}

# Delete Step Functions resources
delete_step_functions() {
    info "Cleaning up Step Functions resources..."
    
    if confirm_action "Delete Step Functions state machine?"; then
        if [[ -n "${STATE_MACHINE_ARN:-}" ]]; then
            execute_delete \
                "aws stepfunctions delete-state-machine --state-machine-arn \"${STATE_MACHINE_ARN}\"" \
                "Delete Step Functions state machine"
        else
            warn "State machine ARN not found in deployment variables"
        fi
        
        # Clean up local state machine definition file
        if [[ -f "${SCRIPT_DIR}/step-function-definition.json" ]]; then
            rm -f "${SCRIPT_DIR}/step-function-definition.json"
            log "✅ Removed local state machine definition file"
        fi
    fi
}

# Delete VPC Lattice resources
delete_vpc_lattice_resources() {
    info "Cleaning up VPC Lattice resources..."
    
    if confirm_action "Delete VPC Lattice resources?"; then
        # Delete resource association first
        if [[ -n "${ASSOCIATION_ID:-}" ]]; then
            execute_delete \
                "aws vpc-lattice delete-service-network-resource-association \
                    --service-network-resource-association-identifier \"${ASSOCIATION_ID}\"" \
                "Delete service network resource association"
            
            # Wait for association deletion
            wait_for_deletion \
                "aws vpc-lattice get-service-network-resource-association --service-network-resource-association-identifier \"${ASSOCIATION_ID}\"" \
                "Resource association" \
                10 5
        fi
        
        # Delete resource configuration
        if [[ -n "${RESOURCE_CONFIG_ARN:-}" ]]; then
            execute_delete \
                "aws vpc-lattice delete-resource-configuration \
                    --resource-configuration-identifier \"${RESOURCE_CONFIG_ARN}\"" \
                "Delete resource configuration"
            
            # Wait for configuration deletion
            wait_for_deletion \
                "aws vpc-lattice get-resource-configuration --resource-configuration-identifier \"${RESOURCE_CONFIG_ARN}\"" \
                "Resource configuration" \
                10 5
        fi
        
        # Delete resource gateway
        if [[ -n "${RESOURCE_GATEWAY_ID:-}" ]]; then
            execute_delete \
                "aws vpc-lattice delete-resource-gateway \
                    --resource-gateway-identifier \"${RESOURCE_GATEWAY_ID}\"" \
                "Delete resource gateway"
            
            # Wait for gateway deletion
            wait_for_deletion \
                "aws vpc-lattice get-resource-gateway --resource-gateway-identifier \"${RESOURCE_GATEWAY_ID}\"" \
                "Resource gateway" \
                20 10
        fi
        
        # Delete service network
        if [[ -n "${SERVICE_NETWORK_ID:-}" ]]; then
            execute_delete \
                "aws vpc-lattice delete-service-network \
                    --service-network-identifier \"${SERVICE_NETWORK_ID}\"" \
                "Delete VPC Lattice service network"
        fi
    fi
}

# Delete API Gateway resources
delete_api_gateway_resources() {
    info "Cleaning up API Gateway and VPC resources..."
    
    if confirm_action "Delete API Gateway and VPC endpoint?"; then
        # Delete API Gateway
        if [[ -n "${API_ID:-}" ]]; then
            execute_delete \
                "aws apigateway delete-rest-api --rest-api-id \"${API_ID}\"" \
                "Delete API Gateway"
        fi
        
        # Delete VPC endpoint
        if [[ -n "${VPC_ENDPOINT_ID:-}" ]]; then
            execute_delete \
                "aws ec2 delete-vpc-endpoint --vpc-endpoint-id \"${VPC_ENDPOINT_ID}\"" \
                "Delete VPC endpoint"
        fi
    fi
}

# Delete VPC and networking resources
delete_vpc_resources() {
    info "Cleaning up VPC and networking resources..."
    
    if confirm_action "Delete VPC, subnets, and networking resources?"; then
        # Delete subnets
        if [[ -n "${SUBNET_ID_1:-}" ]]; then
            execute_delete \
                "aws ec2 delete-subnet --subnet-id \"${SUBNET_ID_1}\"" \
                "Delete subnet 1"
        fi
        
        if [[ -n "${SUBNET_ID_2:-}" ]]; then
            execute_delete \
                "aws ec2 delete-subnet --subnet-id \"${SUBNET_ID_2}\"" \
                "Delete subnet 2"
        fi
        
        # Delete VPC
        if [[ -n "${TARGET_VPC_ID:-}" ]]; then
            execute_delete \
                "aws ec2 delete-vpc --vpc-id \"${TARGET_VPC_ID}\"" \
                "Delete target VPC"
        fi
    fi
}

# Delete IAM resources
delete_iam_resources() {
    info "Cleaning up IAM resources..."
    
    if confirm_action "Delete IAM role and policies?"; then
        # Delete role policy first
        execute_delete \
            "aws iam delete-role-policy \
                --role-name \"EventBridgeStepFunctionsVPCLatticeRole-${RANDOM_SUFFIX}\" \
                --policy-name \"VPCLatticeConnectionPolicy\"" \
            "Delete IAM role policy"
        
        # Delete role
        execute_delete \
            "aws iam delete-role \
                --role-name \"EventBridgeStepFunctionsVPCLatticeRole-${RANDOM_SUFFIX}\"" \
            "Delete IAM role"
    fi
}

# Clean up CloudWatch logs (optional)
delete_cloudwatch_logs() {
    if [[ "$KEEP_LOGS" == "true" ]]; then
        info "Keeping CloudWatch logs as requested"
        return 0
    fi
    
    info "Checking for CloudWatch log groups..."
    
    if confirm_action "Delete CloudWatch log groups?"; then
        # Check for Step Functions log groups
        local log_groups=$(aws logs describe-log-groups \
            --log-group-name-prefix "/aws/stepfunctions/${STEP_FUNCTION_NAME}" \
            --query 'logGroups[].logGroupName' --output text 2>/dev/null || true)
        
        if [[ -n "$log_groups" ]]; then
            for log_group in $log_groups; do
                execute_delete \
                    "aws logs delete-log-group --log-group-name \"$log_group\"" \
                    "Delete CloudWatch log group: $log_group"
            done
        else
            info "No CloudWatch log groups found to delete"
        fi
    fi
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    if confirm_action "Remove local deployment files?"; then
        local files_to_remove=(
            "${SCRIPT_DIR}/step-function-definition.json"
            "${DEPLOYMENT_VARS}"
        )
        
        if [[ "$KEEP_LOGS" != "true" ]]; then
            files_to_remove+=("$LOG_FILE")
        fi
        
        for file in "${files_to_remove[@]}"; do
            if [[ -f "$file" ]]; then
                rm -f "$file"
                log "✅ Removed local file: $(basename "$file")"
            fi
        done
    fi
}

# Verify cleanup completion
verify_cleanup() {
    info "Verifying cleanup completion..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would verify cleanup completion"
        return 0
    fi
    
    local remaining_resources=0
    
    # Check VPC Lattice service network
    if [[ -n "${SERVICE_NETWORK_ID:-}" ]]; then
        if aws vpc-lattice get-service-network \
            --service-network-identifier "${SERVICE_NETWORK_ID}" &> /dev/null; then
            warn "⚠️ VPC Lattice service network still exists"
            ((remaining_resources++))
        fi
    fi
    
    # Check EventBridge bus
    if [[ -n "${EVENTBRIDGE_BUS_NAME:-}" ]]; then
        if aws events describe-event-bus \
            --name "${EVENTBRIDGE_BUS_NAME}" &> /dev/null; then
            warn "⚠️ EventBridge bus still exists"
            ((remaining_resources++))
        fi
    fi
    
    # Check API Gateway
    if [[ -n "${API_ID:-}" ]]; then
        if aws apigateway get-rest-api \
            --rest-api-id "${API_ID}" &> /dev/null; then
            warn "⚠️ API Gateway still exists"
            ((remaining_resources++))
        fi
    fi
    
    # Check VPC
    if [[ -n "${TARGET_VPC_ID:-}" ]]; then
        if aws ec2 describe-vpcs \
            --vpc-ids "${TARGET_VPC_ID}" &> /dev/null; then
            warn "⚠️ Target VPC still exists"
            ((remaining_resources++))
        fi
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
        log "✅ All resources have been successfully cleaned up"
    else
        warn "⚠️ $remaining_resources resource(s) may still exist"
        warn "Some resources may take additional time to be fully deleted"
    fi
}

# Print cleanup summary
print_summary() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "=== DRY RUN SUMMARY ==="
        info "This was a dry run. No resources were actually deleted."
        info "To delete for real, run the script without --dry-run flag."
        return 0
    fi
    
    log "=== CLEANUP SUMMARY ==="
    log "✅ Private API Integration with VPC Lattice cleanup completed!"
    log ""
    log "The following resource types were cleaned up:"
    log "  • EventBridge rules, targets, connections, and custom bus"
    log "  • Step Functions state machine"
    log "  • VPC Lattice service network and resource configurations"
    log "  • API Gateway and VPC endpoint"
    log "  • VPC, subnets, and networking resources"
    log "  • IAM roles and policies"
    
    if [[ "$KEEP_LOGS" == "true" ]]; then
        log "  • CloudWatch logs (preserved as requested)"
    else
        log "  • CloudWatch logs"
    fi
    
    log ""
    log "Note: Some resources may take additional time to be fully deleted."
    log "Check the AWS console to verify complete cleanup if needed."
    
    if [[ "$KEEP_LOGS" == "true" ]]; then
        log "Cleanup log preserved at: $LOG_FILE"
    fi
}

# Main execution function
main() {
    log "Starting Private API Integration with VPC Lattice cleanup..."
    
    check_prerequisites
    load_deployment_vars
    
    # Show what will be deleted
    if [[ "$DRY_RUN" == "false" && "$FORCE_DELETE" == "false" ]]; then
        echo ""
        warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
        warn "This will delete the following resources:"
        warn "  • EventBridge bus: ${EVENTBRIDGE_BUS_NAME}"
        warn "  • Step Functions: ${STEP_FUNCTION_NAME}"
        warn "  • API Gateway: ${API_GATEWAY_NAME}"
        warn "  • VPC Lattice Service Network: ${VPC_LATTICE_SERVICE_NETWORK}"
        warn "  • Target VPC and associated networking resources"
        warn "  • IAM role: EventBridgeStepFunctionsVPCLatticeRole-${RANDOM_SUFFIX}"
        echo ""
        
        if ! confirm_action "Continue with cleanup?"; then
            info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Execute cleanup in reverse order of creation
    delete_eventbridge_resources
    delete_step_functions
    delete_vpc_lattice_resources
    delete_api_gateway_resources
    delete_vpc_resources
    delete_iam_resources
    delete_cloudwatch_logs
    cleanup_local_files
    verify_cleanup
    print_summary
    
    log "Cleanup completed successfully!"
}

# Execute main function
main "$@"