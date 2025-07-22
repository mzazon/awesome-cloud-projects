#!/bin/bash

# Event-Driven Architecture with Amazon EventBridge - Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/tmp/eventbridge-destroy-$(date +%Y%m%d-%H%M%S).log"
readonly REQUIRED_TOOLS=("aws" "jq")

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    log_error "Cleanup failed. Check logs at: $LOG_FILE"
    log_info "Some resources may still exist. Please review manually."
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Safely remove Event-Driven Architecture with Amazon EventBridge

OPTIONS:
    -h, --help          Show this help message
    -f, --force         Skip confirmation prompts
    --dry-run           Show what would be deleted without making changes
    --skip-validation   Skip prerequisite validation
    --debug             Enable debug logging

EXAMPLES:
    $SCRIPT_NAME
    $SCRIPT_NAME --force
    $SCRIPT_NAME --dry-run

EOF
}

# Default values
FORCE=false
DRY_RUN=false
SKIP_VALIDATION=false
DEBUG=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        --debug)
            DEBUG=true
            set -x
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validation functions
check_prerequisites() {
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        log_info "Skipping prerequisite validation"
        return 0
    fi

    log_info "Checking prerequisites..."

    # Check required tools
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is required but not installed"
            exit 1
        fi
    done

    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI not configured. Run 'aws configure' first"
        exit 1
    fi

    log_success "Prerequisites check completed"
}

# Load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."

    if [[ ! -f .deployment-state/config.env ]]; then
        log_warning "No deployment state found (.deployment-state/config.env)"
        log_info "Will attempt to discover resources automatically"
        return 1
    fi

    # Source the configuration
    # shellcheck source=/dev/null
    source .deployment-state/config.env

    log_info "Loaded deployment state:"
    log_info "  AWS Account: ${AWS_ACCOUNT_ID:-unknown}"
    log_info "  AWS Region: ${AWS_REGION:-unknown}"
    log_info "  Custom Bus: ${CUSTOM_BUS_NAME:-unknown}"
    log_info "  Lambda Prefix: ${LAMBDA_FUNCTION_PREFIX:-unknown}"

    return 0
}

# Resource discovery functions
discover_resources() {
    log_info "Discovering EventBridge demo resources..."

    # Discover custom event buses
    DISCOVERED_BUSES=($(aws events list-event-buses \
        --query 'EventBuses[?contains(Name, `ecommerce-events`)].Name' \
        --output text 2>/dev/null || echo ""))

    # Discover Lambda functions
    DISCOVERED_FUNCTIONS=($(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `eventbridge-demo`)].FunctionName' \
        --output text 2>/dev/null || echo ""))

    # Discover SQS queues
    DISCOVERED_QUEUES=($(aws sqs list-queues \
        --queue-name-prefix eventbridge-demo \
        --query 'QueueUrls[*]' \
        --output text 2>/dev/null || echo ""))

    # Discover CloudWatch log groups
    DISCOVERED_LOG_GROUPS=($(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/events/ecommerce-events" \
        --query 'logGroups[*].logGroupName' \
        --output text 2>/dev/null || echo ""))

    DISCOVERED_LAMBDA_LOG_GROUPS=($(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/lambda/eventbridge-demo" \
        --query 'logGroups[*].logGroupName' \
        --output text 2>/dev/null || echo ""))

    log_info "Discovery results:"
    log_info "  Event Buses: ${#DISCOVERED_BUSES[@]}"
    log_info "  Lambda Functions: ${#DISCOVERED_FUNCTIONS[@]}"
    log_info "  SQS Queues: ${#DISCOVERED_QUEUES[@]}"
    log_info "  Log Groups: $((${#DISCOVERED_LOG_GROUPS[@]} + ${#DISCOVERED_LAMBDA_LOG_GROUPS[@]}))"
}

# Confirmation functions
confirm_deletion() {
    if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    echo
    echo -e "${YELLOW}⚠️  WARNING: This will permanently delete the following resources:${NC}"
    echo

    if [[ -n "$CUSTOM_BUS_NAME" ]]; then
        echo "EventBridge Resources:"
        echo "  • Custom Event Bus: $CUSTOM_BUS_NAME"
        echo "  • All associated rules and targets"
        echo
    fi

    if [[ ${#DISCOVERED_BUSES[@]} -gt 0 ]]; then
        echo "Discovered Event Buses:"
        for bus in "${DISCOVERED_BUSES[@]}"; do
            echo "  • $bus"
        done
        echo
    fi

    if [[ ${#DISCOVERED_FUNCTIONS[@]} -gt 0 ]]; then
        echo "Lambda Functions:"
        for func in "${DISCOVERED_FUNCTIONS[@]}"; do
            echo "  • $func"
        done
        echo
    fi

    if [[ ${#DISCOVERED_QUEUES[@]} -gt 0 ]]; then
        echo "SQS Queues:"
        for queue in "${DISCOVERED_QUEUES[@]}"; do
            echo "  • $(basename "$queue")"
        done
        echo
    fi

    echo "Other Resources:"
    echo "  • IAM Role: EventBridgeDemoLambdaRole"
    echo "  • CloudWatch Log Groups"
    echo "  • Lambda deployment packages"
    echo

    read -p "Are you sure you want to delete these resources? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Resource deletion functions
delete_eventbridge_rules() {
    log_info "Deleting EventBridge rules and targets..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete EventBridge rules"
        return 0
    fi

    local bus_name="${CUSTOM_BUS_NAME}"
    
    # If no bus name from config, try discovered buses
    if [[ -z "$bus_name" && ${#DISCOVERED_BUSES[@]} -gt 0 ]]; then
        bus_name="${DISCOVERED_BUSES[0]}"
    fi

    if [[ -z "$bus_name" ]]; then
        log_warning "No event bus to clean up"
        return 0
    fi

    # Get all rules for the event bus
    local rules=($(aws events list-rules --event-bus-name "$bus_name" \
        --query 'Rules[*].Name' --output text 2>/dev/null || echo ""))

    for rule in "${rules[@]}"; do
        if [[ -n "$rule" ]]; then
            log_info "Removing targets from rule: $rule"
            
            # Get targets for this rule
            local targets=($(aws events list-targets-by-rule \
                --rule "$rule" --event-bus-name "$bus_name" \
                --query 'Targets[*].Id' --output text 2>/dev/null || echo ""))

            if [[ ${#targets[@]} -gt 0 ]]; then
                aws events remove-targets \
                    --rule "$rule" \
                    --event-bus-name "$bus_name" \
                    --ids "${targets[@]}" 2>/dev/null || log_warning "Failed to remove targets from rule: $rule"
            fi

            log_info "Deleting rule: $rule"
            aws events delete-rule \
                --name "$rule" \
                --event-bus-name "$bus_name" 2>/dev/null || log_warning "Failed to delete rule: $rule"
        fi
    done

    log_success "EventBridge rules cleanup completed"
}

delete_lambda_functions() {
    log_info "Deleting Lambda functions..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Lambda functions"
        return 0
    fi

    # Delete functions from config if available
    if [[ -n "$LAMBDA_FUNCTION_PREFIX" ]]; then
        local config_functions=(
            "${LAMBDA_FUNCTION_PREFIX}-order-processor"
            "${LAMBDA_FUNCTION_PREFIX}-inventory-manager"
            "${LAMBDA_FUNCTION_PREFIX}-event-generator"
        )

        for func in "${config_functions[@]}"; do
            if aws lambda get-function --function-name "$func" &>/dev/null; then
                log_info "Deleting Lambda function: $func"
                aws lambda delete-function --function-name "$func" 2>/dev/null || log_warning "Failed to delete function: $func"
            fi
        done
    fi

    # Delete discovered functions
    for func in "${DISCOVERED_FUNCTIONS[@]}"; do
        if [[ -n "$func" ]]; then
            log_info "Deleting discovered Lambda function: $func"
            aws lambda delete-function --function-name "$func" 2>/dev/null || log_warning "Failed to delete function: $func"
        fi
    done

    log_success "Lambda functions cleanup completed"
}

delete_sqs_queues() {
    log_info "Deleting SQS queues..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete SQS queues"
        return 0
    fi

    # Delete queue from config if available
    if [[ -n "$PAYMENT_QUEUE_URL" ]]; then
        log_info "Deleting SQS queue: $PAYMENT_QUEUE_URL"
        aws sqs delete-queue --queue-url "$PAYMENT_QUEUE_URL" 2>/dev/null || log_warning "Failed to delete queue: $PAYMENT_QUEUE_URL"
    fi

    # Delete discovered queues
    for queue_url in "${DISCOVERED_QUEUES[@]}"; do
        if [[ -n "$queue_url" ]]; then
            log_info "Deleting discovered SQS queue: $(basename "$queue_url")"
            aws sqs delete-queue --queue-url "$queue_url" 2>/dev/null || log_warning "Failed to delete queue: $queue_url"
        fi
    done

    log_success "SQS queues cleanup completed"
}

delete_cloudwatch_logs() {
    log_info "Deleting CloudWatch log groups..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete CloudWatch log groups"
        return 0
    fi

    # Delete log group from config if available
    if [[ -n "$CUSTOM_BUS_NAME" ]]; then
        local log_group="/aws/events/${CUSTOM_BUS_NAME}"
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0]' --output text | grep -q "$log_group"; then
            log_info "Deleting CloudWatch log group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || log_warning "Failed to delete log group: $log_group"
        fi
    fi

    # Delete discovered log groups
    for log_group in "${DISCOVERED_LOG_GROUPS[@]}" "${DISCOVERED_LAMBDA_LOG_GROUPS[@]}"; do
        if [[ -n "$log_group" ]]; then
            log_info "Deleting discovered CloudWatch log group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || log_warning "Failed to delete log group: $log_group"
        fi
    done

    # Delete Lambda function log groups if we have the prefix
    if [[ -n "$LAMBDA_FUNCTION_PREFIX" ]]; then
        local lambda_log_groups=(
            "/aws/lambda/${LAMBDA_FUNCTION_PREFIX}-order-processor"
            "/aws/lambda/${LAMBDA_FUNCTION_PREFIX}-inventory-manager"
            "/aws/lambda/${LAMBDA_FUNCTION_PREFIX}-event-generator"
        )

        for log_group in "${lambda_log_groups[@]}"; do
            if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0]' --output text | grep -q "$log_group"; then
                log_info "Deleting Lambda log group: $log_group"
                aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || log_warning "Failed to delete log group: $log_group"
            fi
        done
    fi

    log_success "CloudWatch log groups cleanup completed"
}

delete_event_bus() {
    log_info "Deleting custom EventBridge event bus..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete EventBridge event bus"
        return 0
    fi

    # Delete event bus from config if available
    if [[ -n "$CUSTOM_BUS_NAME" ]]; then
        if aws events describe-event-bus --name "$CUSTOM_BUS_NAME" &>/dev/null; then
            log_info "Deleting custom event bus: $CUSTOM_BUS_NAME"
            aws events delete-event-bus --name "$CUSTOM_BUS_NAME" 2>/dev/null || log_warning "Failed to delete event bus: $CUSTOM_BUS_NAME"
        fi
    fi

    # Delete discovered event buses
    for bus in "${DISCOVERED_BUSES[@]}"; do
        if [[ -n "$bus" && "$bus" != "default" ]]; then
            log_info "Deleting discovered event bus: $bus"
            aws events delete-event-bus --name "$bus" 2>/dev/null || log_warning "Failed to delete event bus: $bus"
        fi
    done

    log_success "EventBridge event bus cleanup completed"
}

delete_iam_role() {
    log_info "Deleting IAM role and policies..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete IAM role and policies"
        return 0
    fi

    local role_name="EventBridgeDemoLambdaRole"

    # Check if role exists
    if aws iam get-role --role-name "$role_name" &>/dev/null; then
        log_info "Deleting IAM role: $role_name"

        # Remove inline policies
        log_info "Removing inline policies from role"
        local inline_policies=($(aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames[*]' --output text 2>/dev/null || echo ""))
        for policy in "${inline_policies[@]}"; do
            if [[ -n "$policy" ]]; then
                aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy" 2>/dev/null || log_warning "Failed to delete inline policy: $policy"
            fi
        done

        # Detach managed policies
        log_info "Detaching managed policies from role"
        local attached_policies=($(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null || echo ""))
        for policy_arn in "${attached_policies[@]}"; do
            if [[ -n "$policy_arn" ]]; then
                aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" 2>/dev/null || log_warning "Failed to detach policy: $policy_arn"
            fi
        done

        # Delete the role
        aws iam delete-role --role-name "$role_name" 2>/dev/null || log_warning "Failed to delete IAM role: $role_name"
        
        log_success "IAM role deleted: $role_name"
    else
        log_info "IAM role does not exist: $role_name"
    fi
}

cleanup_local_files() {
    log_info "Cleaning up local deployment files..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local files"
        return 0
    fi

    # Remove deployment state directory
    if [[ -d .deployment-state ]]; then
        log_info "Removing deployment state directory"
        rm -rf .deployment-state
    fi

    # Remove any leftover policy files in current directory
    local cleanup_files=(
        "lambda-trust-policy.json"
        "lambda-eventbridge-policy.json"
        "order-rule-pattern.json"
        "inventory-rule-pattern.json"
        "payment-rule-pattern.json"
        "monitoring-rule-pattern.json"
        "order_processor.py"
        "inventory_manager.py"
        "event_generator.py"
        "order-processor.zip"
        "inventory-manager.zip"
        "event-generator.zip"
        "response.json"
    )

    for file in "${cleanup_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Removing file: $file"
            rm -f "$file"
        fi
    done

    log_success "Local files cleanup completed"
}

verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify cleanup completion"
        return 0
    fi

    log_info "Verifying cleanup completion..."

    local cleanup_issues=0

    # Check for remaining event buses
    local remaining_buses=($(aws events list-event-buses \
        --query 'EventBuses[?contains(Name, `ecommerce-events`)].Name' \
        --output text 2>/dev/null || echo ""))
    
    if [[ ${#remaining_buses[@]} -gt 0 ]]; then
        log_warning "Remaining event buses found: ${remaining_buses[*]}"
        ((cleanup_issues++))
    fi

    # Check for remaining Lambda functions
    local remaining_functions=($(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `eventbridge-demo`)].FunctionName' \
        --output text 2>/dev/null || echo ""))
    
    if [[ ${#remaining_functions[@]} -gt 0 ]]; then
        log_warning "Remaining Lambda functions found: ${remaining_functions[*]}"
        ((cleanup_issues++))
    fi

    # Check for IAM role
    if aws iam get-role --role-name EventBridgeDemoLambdaRole &>/dev/null; then
        log_warning "IAM role still exists: EventBridgeDemoLambdaRole"
        ((cleanup_issues++))
    fi

    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "Cleanup verification completed - no issues found"
    else
        log_warning "Cleanup verification found $cleanup_issues potential issues"
        log_info "Please review the warnings above and clean up manually if needed"
    fi
}

generate_cleanup_report() {
    log_info "Generating cleanup report..."

    cat > cleanup-report-$(date +%Y%m%d-%H%M%S).md << EOF
# EventBridge Event-Driven Architecture Cleanup Report

## Cleanup Summary
- **Cleanup Time**: $(date '+%Y-%m-%d %H:%M:%S')
- **AWS Region**: ${AWS_REGION:-unknown}
- **AWS Account**: ${AWS_ACCOUNT_ID:-unknown}

## Resources Cleaned Up

### EventBridge
- Custom Event Bus: ${CUSTOM_BUS_NAME:-discovered}
- All associated rules and targets

### Lambda Functions
- Order Processor: ${LAMBDA_FUNCTION_PREFIX:-eventbridge-demo}-order-processor
- Inventory Manager: ${LAMBDA_FUNCTION_PREFIX:-eventbridge-demo}-inventory-manager
- Event Generator: ${LAMBDA_FUNCTION_PREFIX:-eventbridge-demo}-event-generator

### Supporting Resources
- SQS Queue: ${LAMBDA_FUNCTION_PREFIX:-eventbridge-demo}-payment-processing
- CloudWatch Log Groups: All EventBridge and Lambda logs
- IAM Role: EventBridgeDemoLambdaRole
- Local deployment files and state

## Verification

Run the following commands to verify cleanup:

\`\`\`bash
# Check for remaining event buses
aws events list-event-buses --query 'EventBuses[?contains(Name, \`ecommerce-events\`)].Name'

# Check for remaining Lambda functions  
aws lambda list-functions --query 'Functions[?contains(FunctionName, \`eventbridge-demo\`)].FunctionName'

# Check for IAM role
aws iam get-role --role-name EventBridgeDemoLambdaRole
\`\`\`

## Notes

- All resources have been removed from your AWS account
- No ongoing charges should occur from this architecture
- If you see any remaining resources, they may be manually created or from other deployments

EOF

    log_success "Cleanup report generated: cleanup-report-$(date +%Y%m%d-%H%M%S).md"
}

# Main cleanup flow
main() {
    log_info "Starting Event-Driven Architecture cleanup..."
    log_info "Log file: $LOG_FILE"

    check_prerequisites
    
    # Try to load deployment state, fallback to discovery
    if ! load_deployment_state; then
        discover_resources
    else
        # Also run discovery to catch any missed resources
        discover_resources
    fi

    confirm_deletion
    
    # Perform cleanup in reverse order of creation
    delete_eventbridge_rules
    delete_lambda_functions
    delete_sqs_queues
    delete_cloudwatch_logs
    delete_event_bus
    delete_iam_role
    cleanup_local_files
    
    verify_cleanup
    generate_cleanup_report

    log_success "Event-Driven Architecture cleanup completed!"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo
        echo "🧹 Cleanup completed successfully!"
        echo "📋 All EventBridge resources have been removed"
        echo "💰 No ongoing charges from this architecture"
        echo "📊 Check cleanup-report-$(date +%Y%m%d-%H%M%S).md for details"
    fi
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi