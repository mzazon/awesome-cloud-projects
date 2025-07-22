#!/bin/bash

#################################################################################
# Circuit Breaker Patterns with Step Functions - Cleanup Script
#
# This script safely removes all resources created by the deploy.sh script.
# It includes safety checks, confirmation prompts, and detailed logging.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Same AWS credentials used for deployment
# - Deployment state file from deploy.sh
#
# Usage: ./destroy.sh [--auto-confirm] [--dry-run] [--force]
#################################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Default options
AUTO_CONFIRM=false
DRY_RUN=false
FORCE_DELETE=false

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

#################################################################################
# Utility Functions
#################################################################################

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$LOG_FILE"
}

resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case "$resource_type" in
        "dynamodb-table")
            aws dynamodb describe-table --table-name "$resource_name" &> /dev/null
            ;;
        "lambda-function")
            aws lambda get-function --function-name "$resource_name" &> /dev/null
            ;;
        "stepfunctions-statemachine")
            aws stepfunctions describe-state-machine --state-machine-arn "$resource_name" &> /dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_name" &> /dev/null
            ;;
        "cloudwatch-alarm")
            aws cloudwatch describe-alarms --alarm-names "$resource_name" --query 'MetricAlarms[0]' --output text | grep -q "$resource_name"
            ;;
        *)
            log_error "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
}

#################################################################################
# Validation Functions
#################################################################################

validate_prerequisites() {
    log "Validating prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

load_deployment_state() {
    if [[ ! -f "$DEPLOYMENT_STATE_FILE" ]]; then
        log_error "Deployment state file not found: $DEPLOYMENT_STATE_FILE"
        log_error "Unable to determine which resources to clean up."
        
        if [[ "$FORCE_DELETE" == "true" ]]; then
            log_warning "Force mode enabled - will attempt manual resource discovery"
            discover_resources_manually
        else
            echo
            echo "Options:"
            echo "  1. Use --force to attempt manual resource discovery"
            echo "  2. Manually delete resources using AWS Console"
            echo "  3. Run this script from the same directory as deploy.sh"
            exit 1
        fi
    else
        log "Loading deployment state from $DEPLOYMENT_STATE_FILE"
        source "$DEPLOYMENT_STATE_FILE"
        
        # Validate required variables
        local required_vars=(
            "AWS_REGION" "AWS_ACCOUNT_ID" "RANDOM_SUFFIX"
            "CIRCUIT_BREAKER_TABLE" "DOWNSTREAM_SERVICE_FUNCTION"
            "FALLBACK_SERVICE_FUNCTION" "HEALTH_CHECK_FUNCTION"
            "CIRCUIT_BREAKER_ROLE" "LAMBDA_EXECUTION_ROLE"
        )
        
        for var in "${required_vars[@]}"; do
            if [[ -z "${!var:-}" ]]; then
                log_error "Required variable $var not found in deployment state"
                exit 1
            fi
        done
        
        log_success "Deployment state loaded successfully"
    fi
}

discover_resources_manually() {
    log "Attempting manual resource discovery..."
    
    # Try to discover resources by naming patterns
    export AWS_REGION
    AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Discover DynamoDB tables
    local tables
    tables=$(aws dynamodb list-tables --query 'TableNames[?contains(@, `circuit-breaker-state`)]' --output text)
    if [[ -n "$tables" ]]; then
        export CIRCUIT_BREAKER_TABLE="$tables"
        log "Found DynamoDB table: $CIRCUIT_BREAKER_TABLE"
    fi
    
    # Discover Lambda functions
    local functions
    functions=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `downstream-service`) || contains(FunctionName, `fallback-service`) || contains(FunctionName, `health-check`)].FunctionName' --output text)
    
    for func in $functions; do
        case "$func" in
            *downstream-service*)
                export DOWNSTREAM_SERVICE_FUNCTION="$func"
                log "Found downstream service function: $func"
                ;;
            *fallback-service*)
                export FALLBACK_SERVICE_FUNCTION="$func"
                log "Found fallback service function: $func"
                ;;
            *health-check*)
                export HEALTH_CHECK_FUNCTION="$func"
                log "Found health check function: $func"
                ;;
        esac
    done
    
    # Discover Step Functions state machines
    local state_machines
    state_machines=$(aws stepfunctions list-state-machines --query 'stateMachines[?contains(name, `CircuitBreaker`)].stateMachineArn' --output text)
    if [[ -n "$state_machines" ]]; then
        export STATE_MACHINE_ARN="$state_machines"
        log "Found Step Functions state machine: $STATE_MACHINE_ARN"
    fi
    
    # Discover IAM roles
    local roles
    roles=$(aws iam list-roles --query 'Roles[?contains(RoleName, `circuit-breaker`) || contains(RoleName, `lambda-execution`)].RoleName' --output text)
    
    for role in $roles; do
        case "$role" in
            *circuit-breaker*)
                export CIRCUIT_BREAKER_ROLE="$role"
                log "Found circuit breaker role: $role"
                ;;
            *lambda-execution*)
                export LAMBDA_EXECUTION_ROLE="$role"
                log "Found lambda execution role: $role"
                ;;
        esac
    done
    
    log_success "Manual resource discovery completed"
}

check_resource_dependencies() {
    log "Checking resource dependencies and usage..."
    
    # Check if Step Functions state machine has running executions
    if [[ -n "${STATE_MACHINE_ARN:-}" ]]; then
        local running_executions
        running_executions=$(aws stepfunctions list-executions \
            --state-machine-arn "$STATE_MACHINE_ARN" \
            --status-filter RUNNING \
            --query 'executions' --output text 2>/dev/null || echo "")
        
        if [[ -n "$running_executions" && "$running_executions" != "None" ]]; then
            log_warning "Found running executions for state machine"
            if [[ "$FORCE_DELETE" != "true" ]]; then
                echo "Running executions found. Use --force to delete anyway, or wait for executions to complete."
                return 1
            fi
        fi
    fi
    
    # Check if Lambda functions are being invoked
    if [[ -n "${DOWNSTREAM_SERVICE_FUNCTION:-}" ]]; then
        log "Checking recent Lambda function activity..."
        # Note: In production, you might want to check CloudWatch metrics for recent invocations
    fi
    
    log_success "Resource dependency check completed"
}

#################################################################################
# Resource Deletion Functions
#################################################################################

delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete CloudWatch alarms"
        return 0
    fi
    
    local alarms=()
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        alarms=(
            "CircuitBreakerOpenAlarm-${RANDOM_SUFFIX}"
            "ServiceFailureRateAlarm-${RANDOM_SUFFIX}"
        )
    else
        # Manual discovery of alarms
        local discovered_alarms
        discovered_alarms=$(aws cloudwatch describe-alarms \
            --query 'MetricAlarms[?contains(AlarmName, `CircuitBreaker`) || contains(AlarmName, `ServiceFailure`)].AlarmName' \
            --output text)
        
        if [[ -n "$discovered_alarms" ]]; then
            read -ra alarms <<< "$discovered_alarms"
        fi
    fi
    
    for alarm in "${alarms[@]}"; do
        if [[ -n "$alarm" ]]; then
            if resource_exists "cloudwatch-alarm" "$alarm"; then
                aws cloudwatch delete-alarms --alarm-names "$alarm"
                log_success "Deleted CloudWatch alarm: $alarm"
            else
                log_warning "CloudWatch alarm not found: $alarm"
            fi
        fi
    done
    
    if [[ ${#alarms[@]} -eq 0 ]]; then
        log_warning "No CloudWatch alarms found to delete"
    fi
}

delete_step_functions_state_machine() {
    log "Deleting Step Functions state machine..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete Step Functions state machine"
        return 0
    fi
    
    if [[ -n "${STATE_MACHINE_ARN:-}" ]]; then
        if resource_exists "stepfunctions-statemachine" "$STATE_MACHINE_ARN"; then
            # Stop any running executions first (if force delete)
            if [[ "$FORCE_DELETE" == "true" ]]; then
                local executions
                executions=$(aws stepfunctions list-executions \
                    --state-machine-arn "$STATE_MACHINE_ARN" \
                    --status-filter RUNNING \
                    --query 'executions[].executionArn' --output text 2>/dev/null || echo "")
                
                for execution in $executions; do
                    if [[ -n "$execution" && "$execution" != "None" ]]; then
                        aws stepfunctions stop-execution --execution-arn "$execution" || true
                        log_warning "Stopped running execution: $execution"
                    fi
                done
                
                # Wait a moment for executions to stop
                sleep 5
            fi
            
            aws stepfunctions delete-state-machine --state-machine-arn "$STATE_MACHINE_ARN"
            log_success "Deleted Step Functions state machine: $STATE_MACHINE_ARN"
        else
            log_warning "Step Functions state machine not found: $STATE_MACHINE_ARN"
        fi
    else
        log_warning "No Step Functions state machine ARN found"
    fi
}

delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete Lambda functions"
        return 0
    fi
    
    local functions=(
        "${DOWNSTREAM_SERVICE_FUNCTION:-}"
        "${FALLBACK_SERVICE_FUNCTION:-}"
        "${HEALTH_CHECK_FUNCTION:-}"
    )
    
    for func in "${functions[@]}"; do
        if [[ -n "$func" ]]; then
            if resource_exists "lambda-function" "$func"; then
                aws lambda delete-function --function-name "$func"
                log_success "Deleted Lambda function: $func"
            else
                log_warning "Lambda function not found: $func"
            fi
        fi
    done
    
    # Check for any remaining functions with circuit breaker pattern
    if [[ "$FORCE_DELETE" == "true" ]]; then
        local remaining_functions
        remaining_functions=$(aws lambda list-functions \
            --query 'Functions[?contains(FunctionName, `circuit`) || contains(FunctionName, `downstream`) || contains(FunctionName, `fallback`) || contains(FunctionName, `health-check`)].FunctionName' \
            --output text)
        
        for func in $remaining_functions; do
            if [[ -n "$func" ]]; then
                aws lambda delete-function --function-name "$func"
                log_warning "Force deleted additional function: $func"
            fi
        done
    fi
}

delete_dynamodb_table() {
    log "Deleting DynamoDB table..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete DynamoDB table"
        return 0
    fi
    
    if [[ -n "${CIRCUIT_BREAKER_TABLE:-}" ]]; then
        if resource_exists "dynamodb-table" "$CIRCUIT_BREAKER_TABLE"; then
            aws dynamodb delete-table --table-name "$CIRCUIT_BREAKER_TABLE"
            
            # Wait for table deletion to complete
            log "Waiting for DynamoDB table deletion to complete..."
            aws dynamodb wait table-not-exists --table-name "$CIRCUIT_BREAKER_TABLE"
            
            log_success "Deleted DynamoDB table: $CIRCUIT_BREAKER_TABLE"
        else
            log_warning "DynamoDB table not found: $CIRCUIT_BREAKER_TABLE"
        fi
    else
        log_warning "No DynamoDB table name found"
    fi
}

delete_iam_roles() {
    log "Deleting IAM roles and policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete IAM roles and policies"
        return 0
    fi
    
    # Delete Step Functions role
    if [[ -n "${CIRCUIT_BREAKER_ROLE:-}" ]]; then
        if resource_exists "iam-role" "$CIRCUIT_BREAKER_ROLE"; then
            # Detach managed policies
            aws iam detach-role-policy \
                --role-name "$CIRCUIT_BREAKER_ROLE" \
                --policy-arn arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess 2>/dev/null || true
            
            aws iam detach-role-policy \
                --role-name "$CIRCUIT_BREAKER_ROLE" \
                --policy-arn arn:aws:iam::aws:policy/AWSLambdaRole 2>/dev/null || true
            
            # Delete inline policies
            aws iam delete-role-policy \
                --role-name "$CIRCUIT_BREAKER_ROLE" \
                --policy-name DynamoDBCircuitBreakerPolicy 2>/dev/null || true
            
            # Delete role
            aws iam delete-role --role-name "$CIRCUIT_BREAKER_ROLE"
            log_success "Deleted IAM role: $CIRCUIT_BREAKER_ROLE"
        else
            log_warning "IAM role not found: $CIRCUIT_BREAKER_ROLE"
        fi
    fi
    
    # Delete Lambda execution role
    if [[ -n "${LAMBDA_EXECUTION_ROLE:-}" ]]; then
        if resource_exists "iam-role" "$LAMBDA_EXECUTION_ROLE"; then
            # Detach managed policies
            aws iam detach-role-policy \
                --role-name "$LAMBDA_EXECUTION_ROLE" \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
            
            # Delete inline policies
            aws iam delete-role-policy \
                --role-name "$LAMBDA_EXECUTION_ROLE" \
                --policy-name DynamoDBLambdaPolicy 2>/dev/null || true
            
            # Delete role
            aws iam delete-role --role-name "$LAMBDA_EXECUTION_ROLE"
            log_success "Deleted IAM role: $LAMBDA_EXECUTION_ROLE"
        else
            log_warning "IAM role not found: $LAMBDA_EXECUTION_ROLE"
        fi
    fi
}

#################################################################################
# Verification Functions
#################################################################################

verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_success=true
    
    # Verify DynamoDB table deletion
    if [[ -n "${CIRCUIT_BREAKER_TABLE:-}" ]]; then
        if resource_exists "dynamodb-table" "$CIRCUIT_BREAKER_TABLE"; then
            log_error "DynamoDB table still exists: $CIRCUIT_BREAKER_TABLE"
            cleanup_success=false
        else
            log_success "✓ DynamoDB table successfully deleted"
        fi
    fi
    
    # Verify Lambda functions deletion
    local functions=(
        "${DOWNSTREAM_SERVICE_FUNCTION:-}"
        "${FALLBACK_SERVICE_FUNCTION:-}"
        "${HEALTH_CHECK_FUNCTION:-}"
    )
    
    for func in "${functions[@]}"; do
        if [[ -n "$func" ]]; then
            if resource_exists "lambda-function" "$func"; then
                log_error "Lambda function still exists: $func"
                cleanup_success=false
            else
                log_success "✓ Lambda function successfully deleted: $func"
            fi
        fi
    done
    
    # Verify Step Functions state machine deletion
    if [[ -n "${STATE_MACHINE_ARN:-}" ]]; then
        if resource_exists "stepfunctions-statemachine" "$STATE_MACHINE_ARN"; then
            log_error "Step Functions state machine still exists: $STATE_MACHINE_ARN"
            cleanup_success=false
        else
            log_success "✓ Step Functions state machine successfully deleted"
        fi
    fi
    
    # Verify IAM roles deletion
    local roles=("${CIRCUIT_BREAKER_ROLE:-}" "${LAMBDA_EXECUTION_ROLE:-}")
    for role in "${roles[@]}"; do
        if [[ -n "$role" ]]; then
            if resource_exists "iam-role" "$role"; then
                log_error "IAM role still exists: $role"
                cleanup_success=false
            else
                log_success "✓ IAM role successfully deleted: $role"
            fi
        fi
    done
    
    if [[ "$cleanup_success" == "true" ]]; then
        log_success "✅ All resources successfully cleaned up"
        return 0
    else
        log_error "❌ Some resources were not cleaned up properly"
        return 1
    fi
}

#################################################################################
# Cost and Impact Analysis
#################################################################################

estimate_cost_savings() {
    log "Calculating cost savings from resource cleanup..."
    
    echo
    echo "Estimated Monthly Cost Savings:"
    echo "  • DynamoDB Table (5 RCU/5 WCU): ~\$2.50/month"
    echo "  • Lambda Functions (3 functions): ~\$0.20/month (idle)"
    echo "  • Step Functions: ~\$0.25/month (minimal executions)"
    echo "  • CloudWatch Alarms (2 alarms): ~\$0.20/month"
    echo "  • IAM Roles: \$0.00/month (no charge)"
    echo "  Total estimated savings: ~\$3.15/month"
    echo
    echo "Note: Actual costs depend on usage patterns and AWS region."
}

#################################################################################
# Main Cleanup Flow
#################################################################################

show_usage() {
    cat << EOF
Circuit Breaker Patterns with Step Functions - Cleanup Script

Usage: $0 [OPTIONS]

Options:
    --auto-confirm    Skip confirmation prompts and proceed with cleanup
    --dry-run         Show what would be deleted without making changes
    --force           Force deletion even if resources are in use
    --help            Show this help message

Examples:
    $0                     # Interactive cleanup with confirmations
    $0 --dry-run          # Preview cleanup actions
    $0 --auto-confirm     # Automated cleanup without prompts
    $0 --force            # Force cleanup of all resources

Safety Features:
    • Deployment state validation
    • Resource dependency checking
    • Detailed logging and confirmation prompts
    • Dry-run mode for preview
    • Automatic cleanup verification

EOF
}

confirm_deletion() {
    if [[ "$AUTO_CONFIRM" == "true" ]]; then
        return 0
    fi
    
    echo
    log "Resources to be deleted:"
    if [[ -n "${CIRCUIT_BREAKER_TABLE:-}" ]]; then
        echo "  • DynamoDB Table: $CIRCUIT_BREAKER_TABLE"
    fi
    if [[ -n "${DOWNSTREAM_SERVICE_FUNCTION:-}" ]]; then
        echo "  • Lambda Function: $DOWNSTREAM_SERVICE_FUNCTION"
    fi
    if [[ -n "${FALLBACK_SERVICE_FUNCTION:-}" ]]; then
        echo "  • Lambda Function: $FALLBACK_SERVICE_FUNCTION"
    fi
    if [[ -n "${HEALTH_CHECK_FUNCTION:-}" ]]; then
        echo "  • Lambda Function: $HEALTH_CHECK_FUNCTION"
    fi
    if [[ -n "${STATE_MACHINE_ARN:-}" ]]; then
        echo "  • Step Functions: $(basename "$STATE_MACHINE_ARN")"
    fi
    if [[ -n "${CIRCUIT_BREAKER_ROLE:-}" ]]; then
        echo "  • IAM Role: $CIRCUIT_BREAKER_ROLE"
    fi
    if [[ -n "${LAMBDA_EXECUTION_ROLE:-}" ]]; then
        echo "  • IAM Role: $LAMBDA_EXECUTION_ROLE"
    fi
    echo "  • CloudWatch Alarms: 2 alarms"
    echo
    
    estimate_cost_savings
    
    echo
    log_warning "⚠️  This action cannot be undone!"
    read -p "Are you sure you want to delete all these resources? (type 'yes' to confirm): " -r
    
    if [[ "$REPLY" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

cleanup_deployment_state() {
    log "Cleaning up deployment state file..."
    
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        if [[ "$DRY_RUN" != "true" ]]; then
            rm -f "$DEPLOYMENT_STATE_FILE"
            log_success "Deployment state file removed"
        else
            log "DRY RUN: Would remove deployment state file"
        fi
    fi
}

main() {
    # Initialize log file
    echo "Circuit Breaker Cleanup Log - $(date)" > "$LOG_FILE"
    
    log "Starting Circuit Breaker Pattern cleanup..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto-confirm)
                AUTO_CONFIRM=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validation phase
    validate_prerequisites
    load_deployment_state
    check_resource_dependencies
    
    # Show deletion summary and get confirmation
    confirm_deletion
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "=== DRY RUN MODE - No resources will be deleted ==="
    fi
    
    # Deletion phase (reverse order of creation)
    log "Starting resource cleanup..."
    
    delete_cloudwatch_alarms
    delete_step_functions_state_machine
    delete_lambda_functions
    delete_dynamodb_table
    delete_iam_roles
    
    # Verification phase
    if [[ "$DRY_RUN" != "true" ]]; then
        verify_cleanup
        cleanup_deployment_state
    fi
    
    # Success summary
    echo
    log_success "🎉 Circuit Breaker Pattern cleanup completed successfully!"
    echo
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "All resources have been removed from your AWS account."
        estimate_cost_savings
    else
        echo "DRY RUN completed - no resources were actually deleted."
        echo "Run without --dry-run to perform actual cleanup."
    fi
    echo
    
    log "Cleanup completed at $(date)"
}

# Execute main function with all arguments
main "$@"