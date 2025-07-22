#!/bin/bash

# Destroy script for Event-Driven Architecture with EventBridge
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}
FORCE_DELETE=${FORCE_DELETE:-false}

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
DEFAULT_REGION="us-east-1"

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --region REGION          AWS region (default: $DEFAULT_REGION)"
    echo "  --deployment-info FILE   Path to deployment info JSON file"
    echo "  --dry-run               Show what would be deleted without making changes"
    echo "  --skip-confirmation     Skip confirmation prompts"
    echo "  --force                 Force deletion without prompts (use with caution)"
    echo "  --help                  Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  AWS_REGION              AWS region"
    echo "  AWS_PROFILE             AWS profile to use"
    echo "  DRY_RUN                 Set to 'true' for dry run mode"
    echo "  SKIP_CONFIRMATION       Set to 'true' to skip confirmations"
    echo "  FORCE_DELETE            Set to 'true' to force deletion"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --deployment-info)
            DEPLOYMENT_INFO_FILE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --force)
            FORCE_DELETE=true
            SKIP_CONFIRMATION=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            log_error "Unknown parameter: $1"
            usage
            ;;
    esac
done

# Set defaults if not provided
AWS_REGION=${AWS_REGION:-$DEFAULT_REGION}
DEPLOYMENT_INFO_FILE=${DEPLOYMENT_INFO_FILE:-"$PROJECT_DIR/deployment-info.json"}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it and try again."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some functions may not work optimally."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' and try again."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Display destruction information
display_destruction_info() {
    log_info "=== Destruction Configuration ==="
    log_info "AWS Region: $AWS_REGION"
    log_info "Deployment Info File: $DEPLOYMENT_INFO_FILE"
    log_info "Dry Run: $DRY_RUN"
    log_info "Force Delete: $FORCE_DELETE"
    log_info "Script Directory: $SCRIPT_DIR"
    log_info "Project Directory: $PROJECT_DIR"
    
    # Get AWS account info
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local user_arn=$(aws sts get-caller-identity --query Arn --output text)
    
    log_info "AWS Account ID: $account_id"
    log_info "AWS User/Role: $user_arn"
    log_info "================================="
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ ! -f "$DEPLOYMENT_INFO_FILE" ]]; then
        log_warning "Deployment info file not found: $DEPLOYMENT_INFO_FILE"
        log_warning "Will attempt to discover resources automatically"
        return 1
    fi
    
    if command -v jq &> /dev/null; then
        # Use jq to parse JSON
        export RANDOM_SUFFIX=$(jq -r '.randomSuffix' "$DEPLOYMENT_INFO_FILE")
        export EVENT_BUS_NAME=$(jq -r '.resources.eventBusName' "$DEPLOYMENT_INFO_FILE")
        export SNS_TOPIC_ARN=$(jq -r '.resources.snsTopicArn' "$DEPLOYMENT_INFO_FILE")
        export SQS_QUEUE_URL=$(jq -r '.resources.sqsQueueUrl' "$DEPLOYMENT_INFO_FILE")
        export LAMBDA_FUNCTION_NAME=$(jq -r '.resources.lambdaFunctionName' "$DEPLOYMENT_INFO_FILE")
        export EVENTBRIDGE_ROLE_NAME="EventBridgeExecutionRole-${RANDOM_SUFFIX}"
        export LAMBDA_ROLE_NAME="EventProcessorLambdaRole-${RANDOM_SUFFIX}"
        
        # Get rules array
        mapfile -t RULES < <(jq -r '.rules[]' "$DEPLOYMENT_INFO_FILE")
        
        log_success "Loaded deployment information from $DEPLOYMENT_INFO_FILE"
    else
        log_error "jq is required to parse deployment info. Please install jq or delete resources manually."
        exit 1
    fi
}

# Discover resources automatically
discover_resources() {
    log_info "Discovering resources automatically..."
    
    # Try to find event buses with our naming pattern
    local event_buses=$(aws events list-event-buses --query 'EventBuses[?contains(Name, `ecommerce-events-`)].Name' --output text)
    
    if [[ -n "$event_buses" ]]; then
        log_info "Found event buses: $event_buses"
        
        # Use the first one found
        export EVENT_BUS_NAME=$(echo "$event_buses" | awk '{print $1}')
        
        # Extract suffix from event bus name
        export RANDOM_SUFFIX=$(echo "$EVENT_BUS_NAME" | sed 's/ecommerce-events-//')
        
        # Construct other resource names
        export SNS_TOPIC_NAME="order-notifications-${RANDOM_SUFFIX}"
        export SQS_QUEUE_NAME="event-processing-${RANDOM_SUFFIX}"
        export LAMBDA_FUNCTION_NAME="event-processor-${RANDOM_SUFFIX}"
        export EVENTBRIDGE_ROLE_NAME="EventBridgeExecutionRole-${RANDOM_SUFFIX}"
        export LAMBDA_ROLE_NAME="EventProcessorLambdaRole-${RANDOM_SUFFIX}"
        
        # Get SNS topic ARN
        export SNS_TOPIC_ARN=$(aws sns list-topics --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text)
        
        # Get SQS queue URL
        export SQS_QUEUE_URL=$(aws sqs list-queues --queue-name-prefix "$SQS_QUEUE_NAME" --query 'QueueUrls[0]' --output text)
        
        # Get EventBridge rules
        mapfile -t RULES < <(aws events list-rules --event-bus-name "$EVENT_BUS_NAME" --query 'Rules[].Name' --output text | tr '\t' '\n')
        
        log_success "Discovered resources automatically"
    else
        log_error "No event buses found matching the expected pattern"
        log_error "Please provide a valid deployment-info.json file or delete resources manually"
        exit 1
    fi
}

# Delete EventBridge rules and targets
delete_eventbridge_rules() {
    log_info "Deleting EventBridge rules and targets..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete EventBridge rules: ${RULES[*]}"
        return 0
    fi
    
    if [[ -z "$EVENT_BUS_NAME" ]]; then
        log_warning "Event bus name not available, skipping rule deletion"
        return 0
    fi
    
    # Get all rules for the event bus
    local rules_to_delete=()
    if [[ ${#RULES[@]} -gt 0 ]]; then
        rules_to_delete=("${RULES[@]}")
    else
        # Discover rules if not provided
        mapfile -t rules_to_delete < <(aws events list-rules --event-bus-name "$EVENT_BUS_NAME" --query 'Rules[].Name' --output text | tr '\t' '\n')
    fi
    
    for rule in "${rules_to_delete[@]}"; do
        if [[ -n "$rule" && "$rule" != "None" ]]; then
            log_info "Deleting rule: $rule"
            
            # Remove targets first
            local targets=$(aws events list-targets-by-rule \
                --rule "$rule" \
                --event-bus-name "$EVENT_BUS_NAME" \
                --query 'Targets[].Id' --output text 2>/dev/null || echo "")
            
            if [[ -n "$targets" ]]; then
                aws events remove-targets \
                    --rule "$rule" \
                    --event-bus-name "$EVENT_BUS_NAME" \
                    --ids $targets 2>/dev/null || log_warning "Failed to remove targets for rule $rule"
            fi
            
            # Delete rule
            aws events delete-rule \
                --name "$rule" \
                --event-bus-name "$EVENT_BUS_NAME" 2>/dev/null || log_warning "Failed to delete rule $rule"
        fi
    done
    
    log_success "Deleted EventBridge rules and targets"
}

# Delete Lambda function and permissions
delete_lambda_function() {
    log_info "Deleting Lambda function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Lambda function: $LAMBDA_FUNCTION_NAME"
        return 0
    fi
    
    if [[ -z "$LAMBDA_FUNCTION_NAME" ]]; then
        log_warning "Lambda function name not available, skipping deletion"
        return 0
    fi
    
    # Remove Lambda permissions first
    local statement_ids=(
        "allow-eventbridge-order-events-${RANDOM_SUFFIX}"
        "allow-eventbridge-user-events-${RANDOM_SUFFIX}"
    )
    
    for statement_id in "${statement_ids[@]}"; do
        aws lambda remove-permission \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --statement-id "$statement_id" 2>/dev/null || log_warning "Failed to remove permission $statement_id"
    done
    
    # Delete Lambda function
    aws lambda delete-function \
        --function-name "$LAMBDA_FUNCTION_NAME" 2>/dev/null || log_warning "Failed to delete Lambda function"
    
    log_success "Deleted Lambda function"
}

# Delete EventBridge event bus
delete_event_bus() {
    log_info "Deleting EventBridge event bus..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete event bus: $EVENT_BUS_NAME"
        return 0
    fi
    
    if [[ -z "$EVENT_BUS_NAME" ]]; then
        log_warning "Event bus name not available, skipping deletion"
        return 0
    fi
    
    # Delete event bus
    aws events delete-event-bus --name "$EVENT_BUS_NAME" 2>/dev/null || log_warning "Failed to delete event bus"
    
    log_success "Deleted EventBridge event bus"
}

# Delete SNS topic
delete_sns_topic() {
    log_info "Deleting SNS topic..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete SNS topic: $SNS_TOPIC_ARN"
        return 0
    fi
    
    if [[ -z "$SNS_TOPIC_ARN" || "$SNS_TOPIC_ARN" == "None" ]]; then
        log_warning "SNS topic ARN not available, skipping deletion"
        return 0
    fi
    
    # Delete SNS topic
    aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" 2>/dev/null || log_warning "Failed to delete SNS topic"
    
    log_success "Deleted SNS topic"
}

# Delete SQS queue
delete_sqs_queue() {
    log_info "Deleting SQS queue..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete SQS queue: $SQS_QUEUE_URL"
        return 0
    fi
    
    if [[ -z "$SQS_QUEUE_URL" || "$SQS_QUEUE_URL" == "None" ]]; then
        log_warning "SQS queue URL not available, skipping deletion"
        return 0
    fi
    
    # Delete SQS queue
    aws sqs delete-queue --queue-url "$SQS_QUEUE_URL" 2>/dev/null || log_warning "Failed to delete SQS queue"
    
    log_success "Deleted SQS queue"
}

# Delete IAM roles
delete_iam_roles() {
    log_info "Deleting IAM roles..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete IAM roles: $EVENTBRIDGE_ROLE_NAME, $LAMBDA_ROLE_NAME"
        return 0
    fi
    
    # Delete EventBridge role
    if [[ -n "$EVENTBRIDGE_ROLE_NAME" ]]; then
        # Delete role policy
        aws iam delete-role-policy \
            --role-name "$EVENTBRIDGE_ROLE_NAME" \
            --policy-name EventBridgeTargetsPolicy 2>/dev/null || log_warning "Failed to delete EventBridge role policy"
        
        # Delete role
        aws iam delete-role --role-name "$EVENTBRIDGE_ROLE_NAME" 2>/dev/null || log_warning "Failed to delete EventBridge role"
    fi
    
    # Delete Lambda role
    if [[ -n "$LAMBDA_ROLE_NAME" ]]; then
        # Detach managed policy
        aws iam detach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || log_warning "Failed to detach Lambda policy"
        
        # Delete role
        aws iam delete-role --role-name "$LAMBDA_ROLE_NAME" 2>/dev/null || log_warning "Failed to delete Lambda role"
    fi
    
    log_success "Deleted IAM roles"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    # List of files to clean up
    local files_to_remove=(
        "$PROJECT_DIR/eventbridge-trust-policy.json"
        "$PROJECT_DIR/eventbridge-targets-policy.json"
        "$PROJECT_DIR/lambda-trust-policy.json"
        "$PROJECT_DIR/event_processor.py"
        "$PROJECT_DIR/event_processor.zip"
        "$PROJECT_DIR/event_publisher.py"
        "$PROJECT_DIR/monitor_events.py"
        "$PROJECT_DIR/deployment-info.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "Removed: $file"
        fi
    done
    
    log_success "Cleaned up local files"
}

# Verify resource deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local resources_remaining=false
    
    # Check event bus
    if [[ -n "$EVENT_BUS_NAME" ]]; then
        if aws events describe-event-bus --name "$EVENT_BUS_NAME" &>/dev/null; then
            log_warning "Event bus still exists: $EVENT_BUS_NAME"
            resources_remaining=true
        fi
    fi
    
    # Check Lambda function
    if [[ -n "$LAMBDA_FUNCTION_NAME" ]]; then
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
            log_warning "Lambda function still exists: $LAMBDA_FUNCTION_NAME"
            resources_remaining=true
        fi
    fi
    
    # Check SNS topic
    if [[ -n "$SNS_TOPIC_ARN" && "$SNS_TOPIC_ARN" != "None" ]]; then
        if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &>/dev/null; then
            log_warning "SNS topic still exists: $SNS_TOPIC_ARN"
            resources_remaining=true
        fi
    fi
    
    # Check SQS queue
    if [[ -n "$SQS_QUEUE_URL" && "$SQS_QUEUE_URL" != "None" ]]; then
        if aws sqs get-queue-attributes --queue-url "$SQS_QUEUE_URL" &>/dev/null; then
            log_warning "SQS queue still exists: $SQS_QUEUE_URL"
            resources_remaining=true
        fi
    fi
    
    # Check IAM roles
    if [[ -n "$EVENTBRIDGE_ROLE_NAME" ]]; then
        if aws iam get-role --role-name "$EVENTBRIDGE_ROLE_NAME" &>/dev/null; then
            log_warning "EventBridge IAM role still exists: $EVENTBRIDGE_ROLE_NAME"
            resources_remaining=true
        fi
    fi
    
    if [[ -n "$LAMBDA_ROLE_NAME" ]]; then
        if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
            log_warning "Lambda IAM role still exists: $LAMBDA_ROLE_NAME"
            resources_remaining=true
        fi
    fi
    
    if [[ "$resources_remaining" == "true" ]]; then
        log_warning "Some resources may still exist. Please check the AWS console."
        log_warning "Some resources may take time to fully delete."
    else
        log_success "All resources appear to have been deleted successfully"
    fi
}

# Display destruction summary
display_destruction_summary() {
    log_info "=== Destruction Summary ==="
    log_info "Destruction completed!"
    log_info ""
    log_info "Resources deleted:"
    log_info "  • EventBridge Event Bus: $EVENT_BUS_NAME"
    log_info "  • EventBridge Rules: ${#RULES[@]} rules"
    log_info "  • Lambda Function: $LAMBDA_FUNCTION_NAME"
    log_info "  • SNS Topic: $SNS_TOPIC_ARN"
    log_info "  • SQS Queue: $SQS_QUEUE_URL"
    log_info "  • IAM Roles: EventBridge and Lambda execution roles"
    log_info "  • Local Files: All generated files cleaned up"
    log_info ""
    log_info "Note: Some resources may take a few minutes to fully delete."
    log_info "Check the AWS console to verify all resources are removed."
    log_info "=========================="
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "⚠️  DANGER: This will permanently delete all EventBridge architecture resources!"
    log_warning "⚠️  This action cannot be undone!"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY RUN mode - no resources will be deleted"
        return 0
    fi
    
    echo "Resources to be deleted:"
    echo "  • EventBridge Event Bus: $EVENT_BUS_NAME"
    echo "  • EventBridge Rules: ${#RULES[@]} rules"
    echo "  • Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "  • SNS Topic: $SNS_TOPIC_ARN"
    echo "  • SQS Queue: $SQS_QUEUE_URL"
    echo "  • IAM Roles: 2 roles"
    echo "  • Local Files: All generated files"
    echo ""
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log_warning "Force deletion mode enabled - proceeding without confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to delete all these resources? Type 'DELETE' to confirm: " -r
    echo
    if [[ "$REPLY" != "DELETE" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    # Second confirmation for extra safety
    read -p "Final confirmation - type 'YES' to proceed with deletion: " -r
    echo
    if [[ "$REPLY" != "YES" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
}

# List resources before deletion
list_resources() {
    log_info "=== Resources Found ==="
    
    if [[ -n "$EVENT_BUS_NAME" ]]; then
        log_info "EventBridge Event Bus: $EVENT_BUS_NAME"
        
        # List rules
        if [[ ${#RULES[@]} -gt 0 ]]; then
            log_info "EventBridge Rules:"
            for rule in "${RULES[@]}"; do
                log_info "  • $rule"
            done
        fi
    fi
    
    if [[ -n "$LAMBDA_FUNCTION_NAME" ]]; then
        log_info "Lambda Function: $LAMBDA_FUNCTION_NAME"
    fi
    
    if [[ -n "$SNS_TOPIC_ARN" && "$SNS_TOPIC_ARN" != "None" ]]; then
        log_info "SNS Topic: $SNS_TOPIC_ARN"
    fi
    
    if [[ -n "$SQS_QUEUE_URL" && "$SQS_QUEUE_URL" != "None" ]]; then
        log_info "SQS Queue: $SQS_QUEUE_URL"
    fi
    
    if [[ -n "$EVENTBRIDGE_ROLE_NAME" ]]; then
        log_info "EventBridge IAM Role: $EVENTBRIDGE_ROLE_NAME"
    fi
    
    if [[ -n "$LAMBDA_ROLE_NAME" ]]; then
        log_info "Lambda IAM Role: $LAMBDA_ROLE_NAME"
    fi
    
    log_info "======================="
}

# Main destruction function
main() {
    echo ""
    log_info "EventBridge Event-Driven Architecture Destruction"
    log_info "================================================"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Display destruction configuration
    display_destruction_info
    
    # Load deployment information or discover resources
    if ! load_deployment_info; then
        discover_resources
    fi
    
    # List resources to be deleted
    list_resources
    
    # Confirm destruction
    confirm_destruction
    
    # Delete resources in reverse order of creation
    log_info "Starting resource deletion..."
    
    delete_eventbridge_rules
    delete_lambda_function
    delete_event_bus
    delete_sns_topic
    delete_sqs_queue
    delete_iam_roles
    cleanup_local_files
    
    # Verify deletion
    if [[ "$DRY_RUN" != "true" ]]; then
        sleep 5  # Give AWS time to process deletions
        verify_deletion
        display_destruction_summary
    else
        log_info "DRY RUN completed - no resources were deleted"
    fi
}

# Handle script interruption
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        log_error "Destruction script encountered an error."
        log_error "Some resources may still exist. Please check the AWS console."
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"