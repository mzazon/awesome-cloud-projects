#!/bin/bash

# AWS Distributed Tracing with X-Ray - Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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

# Global variables
DEPLOYMENT_INFO_FILE="deployment-info.json"
FORCE_DELETE=false
DRY_RUN=false

# Parse command line arguments
parse_arguments() {
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
            --deployment-info)
                DEPLOYMENT_INFO_FILE="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help information
show_help() {
    cat << EOF
AWS Distributed Tracing Cleanup Script

Usage: $0 [OPTIONS]

Options:
    --force                Skip confirmation prompts
    --dry-run             Show what would be deleted without actually deleting
    --deployment-info     Path to deployment info file (default: deployment-info.json)
    --help, -h            Show this help message

Examples:
    $0                    # Interactive cleanup with confirmation
    $0 --force            # Automatic cleanup without confirmation
    $0 --dry-run          # Preview what would be deleted
    $0 --deployment-info ./my-deployment.json --force

EOF
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set up IAM role."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ ! -f "$DEPLOYMENT_INFO_FILE" ]]; then
        log_warning "Deployment info file not found: $DEPLOYMENT_INFO_FILE"
        log_info "Attempting to discover resources using manual input..."
        manual_resource_discovery
        return
    fi
    
    # Check if jq is available for JSON parsing
    if command -v jq &> /dev/null; then
        # Use jq for robust JSON parsing
        export DEPLOYMENT_ID=$(jq -r '.deploymentId' "$DEPLOYMENT_INFO_FILE")
        export AWS_REGION=$(jq -r '.region' "$DEPLOYMENT_INFO_FILE")
        export AWS_ACCOUNT_ID=$(jq -r '.accountId' "$DEPLOYMENT_INFO_FILE")
        export EVENT_BUS_NAME=$(jq -r '.eventBusName' "$DEPLOYMENT_INFO_FILE")
        export LAMBDA_ROLE_NAME=$(jq -r '.lambdaRoleName' "$DEPLOYMENT_INFO_FILE")
        export API_GATEWAY_NAME=$(jq -r '.apiGatewayName' "$DEPLOYMENT_INFO_FILE")
        export API_ID=$(jq -r '.apiId' "$DEPLOYMENT_INFO_FILE")
    else
        # Fallback to grep/sed parsing
        log_warning "jq not found, using basic parsing. Consider installing jq for better reliability."
        export DEPLOYMENT_ID=$(grep '"deploymentId"' "$DEPLOYMENT_INFO_FILE" | sed 's/.*": "\(.*\)".*/\1/')
        export AWS_REGION=$(grep '"region"' "$DEPLOYMENT_INFO_FILE" | sed 's/.*": "\(.*\)".*/\1/')
        export AWS_ACCOUNT_ID=$(grep '"accountId"' "$DEPLOYMENT_INFO_FILE" | sed 's/.*": "\(.*\)".*/\1/')
        export EVENT_BUS_NAME=$(grep '"eventBusName"' "$DEPLOYMENT_INFO_FILE" | sed 's/.*": "\(.*\)".*/\1/')
        export LAMBDA_ROLE_NAME=$(grep '"lambdaRoleName"' "$DEPLOYMENT_INFO_FILE" | sed 's/.*": "\(.*\)".*/\1/')
        export API_GATEWAY_NAME=$(grep '"apiGatewayName"' "$DEPLOYMENT_INFO_FILE" | sed 's/.*": "\(.*\)".*/\1/')
        export API_ID=$(grep '"apiId"' "$DEPLOYMENT_INFO_FILE" | sed 's/.*": "\(.*\)".*/\1/')
    fi
    
    # Validate required variables
    if [[ -z "${DEPLOYMENT_ID:-}" || -z "${AWS_REGION:-}" ]]; then
        log_error "Failed to parse deployment information from $DEPLOYMENT_INFO_FILE"
        exit 1
    fi
    
    log_success "Loaded deployment info for deployment ID: $DEPLOYMENT_ID"
    log_info "Region: $AWS_REGION"
}

# Manual resource discovery when deployment info is not available
manual_resource_discovery() {
    log_warning "Manual resource discovery mode"
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region not set. Please set AWS_REGION environment variable."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Prompt for deployment ID
    if [[ "$FORCE_DELETE" != "true" ]]; then
        echo
        log_warning "Please provide the deployment ID (6-character suffix used during deployment):"
        read -r DEPLOYMENT_ID
        
        if [[ -z "$DEPLOYMENT_ID" ]]; then
            log_error "Deployment ID is required for cleanup"
            exit 1
        fi
    else
        log_error "Cannot proceed with --force flag without deployment info file"
        exit 1
    fi
    
    # Construct resource names
    export EVENT_BUS_NAME="distributed-tracing-bus-${DEPLOYMENT_ID}"
    export LAMBDA_ROLE_NAME="distributed-tracing-lambda-role-${DEPLOYMENT_ID}"
    export API_GATEWAY_NAME="distributed-tracing-api-${DEPLOYMENT_ID}"
    
    log_info "Using deployment ID: $DEPLOYMENT_ID"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "⚠️  WARNING: This will permanently delete the following resources:"
    echo
    echo "  📡 API Gateway: ${API_GATEWAY_NAME:-Unknown}"
    echo "  🚌 EventBridge Bus: ${EVENT_BUS_NAME}"
    echo "  ⚡ Lambda Functions: 4 functions with suffix ${DEPLOYMENT_ID}"
    echo "  🔐 IAM Role: ${LAMBDA_ROLE_NAME}"
    echo "  📋 EventBridge Rules: 3 rules with suffix ${DEPLOYMENT_ID}"
    echo "  🌍 Region: ${AWS_REGION}"
    echo
    log_warning "This action cannot be undone!"
    echo
    read -p "Are you sure you want to delete these resources? (yes/no): " -r
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Execute command with dry-run support
execute_command() {
    local description="$1"
    shift
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: $description"
        log_info "[DRY RUN] Command: $*"
        return 0
    fi
    
    log_info "$description"
    "$@" 2>/dev/null || {
        log_warning "Failed: $description (resource may not exist)"
        return 0
    }
}

# Delete API Gateway
delete_api_gateway() {
    if [[ -n "${API_ID:-}" ]]; then
        execute_command "Deleting API Gateway: $API_ID" \
            aws apigateway delete-rest-api --rest-api-id "$API_ID"
        log_success "Deleted API Gateway"
    else
        log_warning "API Gateway ID not found, attempting discovery..."
        
        # Try to find API Gateway by name
        local found_api_id
        found_api_id=$(aws apigateway get-rest-apis \
            --query "items[?name=='${API_GATEWAY_NAME}'].id" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$found_api_id" && "$found_api_id" != "None" ]]; then
            execute_command "Deleting discovered API Gateway: $found_api_id" \
                aws apigateway delete-rest-api --rest-api-id "$found_api_id"
            log_success "Deleted discovered API Gateway"
        else
            log_warning "No API Gateway found to delete"
        fi
    fi
}

# Remove EventBridge rules and targets
delete_eventbridge_rules() {
    log_info "Removing EventBridge rules and targets..."
    
    local rules=("payment-processing" "inventory-update" "notification")
    
    for rule in "${rules[@]}"; do
        local rule_name="${rule}-rule-${DEPLOYMENT_ID}"
        
        # Remove targets first
        execute_command "Removing targets from rule: $rule_name" \
            aws events remove-targets \
                --rule "$rule_name" \
                --event-bus-name "$EVENT_BUS_NAME" \
                --ids 1
        
        # Delete rule
        execute_command "Deleting rule: $rule_name" \
            aws events delete-rule \
                --name "$rule_name" \
                --event-bus-name "$EVENT_BUS_NAME"
    done
    
    log_success "Deleted EventBridge rules and targets"
}

# Delete Lambda functions
delete_lambda_functions() {
    log_info "Deleting Lambda functions..."
    
    local services=("order" "payment" "inventory" "notification")
    
    for service in "${services[@]}"; do
        local function_name="${service}-service-${DEPLOYMENT_ID}"
        
        # Remove Lambda permissions first
        execute_command "Removing permissions for: $function_name" \
            aws lambda remove-permission \
                --function-name "$function_name" \
                --statement-id "eventbridge-invoke-${service}"
        
        if [[ "$service" == "order" ]]; then
            execute_command "Removing API Gateway permission for: $function_name" \
                aws lambda remove-permission \
                    --function-name "$function_name" \
                    --statement-id "apigateway-invoke"
        fi
        
        # Delete function
        execute_command "Deleting Lambda function: $function_name" \
            aws lambda delete-function --function-name "$function_name"
    done
    
    log_success "Deleted Lambda functions"
}

# Delete EventBridge custom bus
delete_event_bus() {
    execute_command "Deleting EventBridge custom bus: $EVENT_BUS_NAME" \
        aws events delete-event-bus --name "$EVENT_BUS_NAME"
    log_success "Deleted EventBridge custom bus"
}

# Delete IAM role
delete_iam_role() {
    if [[ -n "${LAMBDA_ROLE_NAME:-}" ]]; then
        log_info "Deleting IAM role and policies..."
        
        # Detach managed policies
        local policies=(
            "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
            "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
            "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"
        )
        
        for policy in "${policies[@]}"; do
            execute_command "Detaching policy: $policy" \
                aws iam detach-role-policy \
                    --role-name "$LAMBDA_ROLE_NAME" \
                    --policy-arn "$policy"
        done
        
        # Delete role
        execute_command "Deleting IAM role: $LAMBDA_ROLE_NAME" \
            aws iam delete-role --role-name "$LAMBDA_ROLE_NAME"
        
        log_success "Deleted IAM role and policies"
    else
        log_warning "IAM role name not found, skipping role deletion"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment-info.json"
        "*.py"
        "*.zip"
    )
    
    for pattern in "${files_to_remove[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would remove files matching: $pattern"
        else
            # Use find to safely remove files
            find . -maxdepth 1 -name "$pattern" -type f -delete 2>/dev/null || true
        fi
    done
    
    log_success "Cleaned up local files"
}

# Verify cleanup completion
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Cleanup verification skipped in dry-run mode"
        return
    fi
    
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check if EventBridge bus still exists
    if aws events describe-event-bus --name "$EVENT_BUS_NAME" &>/dev/null; then
        log_warning "EventBridge bus still exists: $EVENT_BUS_NAME"
        ((cleanup_issues++))
    fi
    
    # Check if Lambda functions still exist
    local services=("order" "payment" "inventory" "notification")
    for service in "${services[@]}"; do
        local function_name="${service}-service-${DEPLOYMENT_ID}"
        if aws lambda get-function --function-name "$function_name" &>/dev/null; then
            log_warning "Lambda function still exists: $function_name"
            ((cleanup_issues++))
        fi
    done
    
    # Check if IAM role still exists
    if [[ -n "${LAMBDA_ROLE_NAME:-}" ]] && aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
        log_warning "IAM role still exists: $LAMBDA_ROLE_NAME"
        ((cleanup_issues++))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "✅ Cleanup verification passed - all resources removed"
    else
        log_warning "⚠️  Cleanup verification found $cleanup_issues remaining resources"
        log_info "Some resources may take additional time to be fully removed"
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    echo
    log_success "🎉 Cleanup completed!"
    echo
    log_info "📋 Cleanup Summary:"
    log_info "   Deployment ID: ${DEPLOYMENT_ID}"
    log_info "   Region: ${AWS_REGION}"
    log_info "   EventBridge Bus: ${EVENT_BUS_NAME}"
    log_info "   Lambda Functions: 4 functions removed"
    log_info "   IAM Role: ${LAMBDA_ROLE_NAME:-Unknown}"
    echo
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "🔍 This was a dry run. No actual resources were deleted."
        log_info "Run without --dry-run to perform actual cleanup."
    else
        log_info "💰 All resources have been removed to prevent ongoing charges."
        log_info "📊 X-Ray traces will remain available for 30 days (no additional charge)."
    fi
    echo
}

# Main cleanup function
main() {
    parse_arguments "$@"
    
    echo "AWS Distributed Tracing Cleanup Script"
    echo "====================================="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "🔍 Running in DRY RUN mode - no resources will be deleted"
    fi
    
    check_prerequisites
    load_deployment_info
    confirm_deletion
    
    # Execute cleanup steps in reverse order of creation
    delete_api_gateway
    delete_eventbridge_rules
    delete_lambda_functions
    delete_event_bus
    delete_iam_role
    cleanup_local_files
    
    verify_cleanup
    show_cleanup_summary
}

# Error handler
error_handler() {
    local line_number=$1
    log_error "Script failed at line $line_number"
    log_error "Partial cleanup may have occurred. Check AWS console for remaining resources."
    exit 1
}

trap 'error_handler $LINENO' ERR

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi