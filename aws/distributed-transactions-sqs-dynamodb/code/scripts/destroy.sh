#!/bin/bash

# AWS Distributed Transaction Processing with SQS - Cleanup Script
# This script safely removes all resources created by the deployment script
# including DynamoDB tables, SQS queues, Lambda functions, and API Gateway

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            warning "Running in dry-run mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            warning "Force delete mode enabled - will skip confirmation prompts"
            shift
            ;;
        --stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Function to execute commands with dry-run support
execute_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: $1"
    else
        log "Executing: $1"
        eval "$1" || true  # Continue on error for cleanup
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --dry-run                   Run in dry-run mode (no resources deleted)"
    echo "  --force                     Skip confirmation prompts"
    echo "  --stack-name STACK_NAME     Specify stack name to delete"
    echo "  --help                      Show this help message"
    echo ""
    echo "Example:"
    echo "  $0                          # Interactive cleanup"
    echo "  $0 --dry-run                # Preview cleanup without deleting resources"
    echo "  $0 --force                  # Skip confirmation prompts"
    echo "  $0 --stack-name my-stack    # Delete specific stack"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required tools
    for tool in jq; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    success "Prerequisites check passed"
}

# Function to setup environment
setup_environment() {
    log "Setting up environment variables..."
    
    # AWS region and account setup
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, using default: $AWS_REGION"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    
    success "Environment setup completed"
}

# Function to discover stack resources
discover_stack_resources() {
    log "Discovering stack resources..."
    
    if [[ -z "$STACK_NAME" ]]; then
        # Try to find deployment state file
        local state_files=(deployment_state_*.json)
        if [[ -f "${state_files[0]}" ]]; then
            STACK_NAME=$(jq -r '.stackName' "${state_files[0]}")
            log "Found stack name from state file: $STACK_NAME"
        else
            # Interactive mode - list available stacks
            log "Available stacks (searching for distributed-tx-* resources):"
            
            # Find DynamoDB tables with the pattern
            local tables=$(aws dynamodb list-tables --query "TableNames[?starts_with(@, 'distributed-tx-')]" --output text)
            if [[ -n "$tables" ]]; then
                echo "Found DynamoDB tables:"
                echo "$tables" | tr '\t' '\n' | sed 's/^/  /'
                
                # Extract stack name from first table
                local first_table=$(echo "$tables" | cut -f1)
                STACK_NAME=$(echo "$first_table" | sed 's/-saga-state$//' | sed 's/-orders$//' | sed 's/-payments$//' | sed 's/-inventory$//')
                log "Detected stack name: $STACK_NAME"
            fi
            
            # If still no stack name, ask user
            if [[ -z "$STACK_NAME" ]]; then
                read -p "Enter stack name to delete (e.g., distributed-tx-abc123): " STACK_NAME
                if [[ -z "$STACK_NAME" ]]; then
                    error "Stack name is required"
                    exit 1
                fi
            fi
        fi
    fi
    
    # Set resource names based on stack name
    export SAGA_STATE_TABLE="${STACK_NAME}-saga-state"
    export ORDER_TABLE="${STACK_NAME}-orders"
    export PAYMENT_TABLE="${STACK_NAME}-payments"
    export INVENTORY_TABLE="${STACK_NAME}-inventory"
    
    log "Stack name: $STACK_NAME"
    success "Resource discovery completed"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log "Force delete mode - skipping confirmation"
        return
    fi
    
    warning "This will permanently delete the following resources:"
    echo ""
    echo "Stack: $STACK_NAME"
    echo "Region: $AWS_REGION"
    echo ""
    echo "Resources to be deleted:"
    echo "  - DynamoDB Tables: $SAGA_STATE_TABLE, $ORDER_TABLE, $PAYMENT_TABLE, $INVENTORY_TABLE"
    echo "  - SQS Queues: ${STACK_NAME}-order-processing.fifo, ${STACK_NAME}-payment-processing.fifo, etc."
    echo "  - Lambda Functions: ${STACK_NAME}-orchestrator, ${STACK_NAME}-order-service, etc."
    echo "  - API Gateway: ${STACK_NAME}-transaction-api"
    echo "  - CloudWatch Alarms and Dashboard"
    echo "  - IAM Role: ${STACK_NAME}-lambda-role"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY-RUN MODE: No resources will actually be deleted"
    else
        warning "THIS ACTION CANNOT BE UNDONE!"
    fi
    
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed, proceeding..."
}

# Function to list event source mappings for cleanup
list_event_source_mappings() {
    log "Finding event source mappings..."
    
    # Get all event source mappings for our Lambda functions
    local functions=(
        "${STACK_NAME}-orchestrator"
        "${STACK_NAME}-compensation-handler"
        "${STACK_NAME}-order-service"
        "${STACK_NAME}-payment-service"
        "${STACK_NAME}-inventory-service"
    )
    
    EVENT_SOURCE_MAPPINGS=()
    
    for func in "${functions[@]}"; do
        if [[ "$DRY_RUN" == "false" ]]; then
            local mappings=$(aws lambda list-event-source-mappings \
                --function-name "$func" \
                --query 'EventSourceMappings[].UUID' \
                --output text 2>/dev/null || true)
            
            if [[ -n "$mappings" ]]; then
                EVENT_SOURCE_MAPPINGS+=($mappings)
                log "Found event source mappings for $func: $mappings"
            fi
        else
            log "DRY-RUN: Would find event source mappings for $func"
        fi
    done
    
    success "Event source mapping discovery completed"
}

# Function to delete event source mappings
delete_event_source_mappings() {
    log "Deleting event source mappings..."
    
    for mapping in "${EVENT_SOURCE_MAPPINGS[@]}"; do
        execute_cmd "aws lambda delete-event-source-mapping --uuid '$mapping'"
    done
    
    success "Event source mappings deleted"
}

# Function to delete API Gateway
delete_api_gateway() {
    log "Deleting API Gateway..."
    
    # Find API Gateway by name
    if [[ "$DRY_RUN" == "false" ]]; then
        local api_id=$(aws apigateway get-rest-apis \
            --query "items[?name=='${STACK_NAME}-transaction-api'].id" \
            --output text 2>/dev/null || true)
        
        if [[ -n "$api_id" && "$api_id" != "None" ]]; then
            execute_cmd "aws apigateway delete-rest-api --rest-api-id '$api_id'"
            log "API Gateway deleted: $api_id"
        else
            warning "API Gateway not found or already deleted"
        fi
    else
        execute_cmd "# Would delete API Gateway: ${STACK_NAME}-transaction-api"
    fi
    
    success "API Gateway cleanup completed"
}

# Function to delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    local functions=(
        "${STACK_NAME}-orchestrator"
        "${STACK_NAME}-compensation-handler"
        "${STACK_NAME}-order-service"
        "${STACK_NAME}-payment-service"
        "${STACK_NAME}-inventory-service"
    )
    
    for func in "${functions[@]}"; do
        if [[ "$DRY_RUN" == "false" ]]; then
            # Check if function exists before attempting to delete
            if aws lambda get-function --function-name "$func" &>/dev/null; then
                execute_cmd "aws lambda delete-function --function-name '$func'"
                log "Lambda function deleted: $func"
            else
                warning "Lambda function not found: $func"
            fi
        else
            execute_cmd "# Would delete Lambda function: $func"
        fi
    done
    
    success "Lambda functions deleted"
}

# Function to delete SQS queues
delete_sqs_queues() {
    log "Deleting SQS queues..."
    
    local queues=(
        "${STACK_NAME}-order-processing.fifo"
        "${STACK_NAME}-payment-processing.fifo"
        "${STACK_NAME}-inventory-update.fifo"
        "${STACK_NAME}-compensation.fifo"
        "${STACK_NAME}-dlq.fifo"
    )
    
    for queue in "${queues[@]}"; do
        if [[ "$DRY_RUN" == "false" ]]; then
            # Get queue URL first
            local queue_url=$(aws sqs get-queue-url --queue-name "$queue" --query 'QueueUrl' --output text 2>/dev/null || true)
            
            if [[ -n "$queue_url" && "$queue_url" != "None" ]]; then
                execute_cmd "aws sqs delete-queue --queue-url '$queue_url'"
                log "SQS queue deleted: $queue"
            else
                warning "SQS queue not found: $queue"
            fi
        else
            execute_cmd "# Would delete SQS queue: $queue"
        fi
    done
    
    success "SQS queues deleted"
}

# Function to delete DynamoDB tables
delete_dynamodb_tables() {
    log "Deleting DynamoDB tables..."
    
    local tables=(
        "$SAGA_STATE_TABLE"
        "$ORDER_TABLE"
        "$PAYMENT_TABLE"
        "$INVENTORY_TABLE"
    )
    
    for table in "${tables[@]}"; do
        if [[ "$DRY_RUN" == "false" ]]; then
            # Check if table exists before attempting to delete
            if aws dynamodb describe-table --table-name "$table" &>/dev/null; then
                execute_cmd "aws dynamodb delete-table --table-name '$table'"
                log "DynamoDB table deletion initiated: $table"
            else
                warning "DynamoDB table not found: $table"
            fi
        else
            execute_cmd "# Would delete DynamoDB table: $table"
        fi
    done
    
    # Wait for tables to be deleted
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for DynamoDB tables to be deleted..."
        for table in "${tables[@]}"; do
            aws dynamodb wait table-not-exists --table-name "$table" 2>/dev/null || true
        done
    fi
    
    success "DynamoDB tables deleted"
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete CloudWatch alarms
    local alarms=(
        "${STACK_NAME}-failed-transactions"
        "${STACK_NAME}-message-age"
    )
    
    for alarm in "${alarms[@]}"; do
        if [[ "$DRY_RUN" == "false" ]]; then
            # Check if alarm exists
            if aws cloudwatch describe-alarms --alarm-names "$alarm" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$alarm"; then
                execute_cmd "aws cloudwatch delete-alarms --alarm-names '$alarm'"
                log "CloudWatch alarm deleted: $alarm"
            else
                warning "CloudWatch alarm not found: $alarm"
            fi
        else
            execute_cmd "# Would delete CloudWatch alarm: $alarm"
        fi
    done
    
    # Delete CloudWatch dashboard
    local dashboard="${STACK_NAME}-transactions"
    if [[ "$DRY_RUN" == "false" ]]; then
        if aws cloudwatch get-dashboard --dashboard-name "$dashboard" &>/dev/null; then
            execute_cmd "aws cloudwatch delete-dashboards --dashboard-names '$dashboard'"
            log "CloudWatch dashboard deleted: $dashboard"
        else
            warning "CloudWatch dashboard not found: $dashboard"
        fi
    else
        execute_cmd "# Would delete CloudWatch dashboard: $dashboard"
    fi
    
    success "CloudWatch resources deleted"
}

# Function to delete IAM role
delete_iam_role() {
    log "Deleting IAM role..."
    
    local role_name="${STACK_NAME}-lambda-role"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Check if role exists
        if aws iam get-role --role-name "$role_name" &>/dev/null; then
            # Detach policies first
            local policies=(
                "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
                "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
                "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
            )
            
            for policy in "${policies[@]}"; do
                execute_cmd "aws iam detach-role-policy --role-name '$role_name' --policy-arn '$policy'"
            done
            
            # Delete the role
            execute_cmd "aws iam delete-role --role-name '$role_name'"
            log "IAM role deleted: $role_name"
        else
            warning "IAM role not found: $role_name"
        fi
    else
        execute_cmd "# Would delete IAM role: $role_name"
    fi
    
    success "IAM role deleted"
}

# Function to cleanup local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment state file
    local state_file="deployment_state_${STACK_NAME}.json"
    if [[ -f "$state_file" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            rm -f "$state_file"
            log "Removed deployment state file: $state_file"
        else
            log "DRY-RUN: Would remove deployment state file: $state_file"
        fi
    fi
    
    # Remove any temporary Lambda zip files
    local zip_files=(*.zip)
    for zip_file in "${zip_files[@]}"; do
        if [[ -f "$zip_file" && "$zip_file" == *"service.zip" ]] || [[ "$zip_file" == "orchestrator.zip" ]]; then
            if [[ "$DRY_RUN" == "false" ]]; then
                rm -f "$zip_file"
                log "Removed temporary file: $zip_file"
            else
                log "DRY-RUN: Would remove temporary file: $zip_file"
            fi
        fi
    done
    
    success "Local files cleaned up"
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN mode - skipping verification"
        return
    fi
    
    local cleanup_errors=false
    
    # Check DynamoDB tables
    for table in "$SAGA_STATE_TABLE" "$ORDER_TABLE" "$PAYMENT_TABLE" "$INVENTORY_TABLE"; do
        if aws dynamodb describe-table --table-name "$table" &>/dev/null; then
            error "DynamoDB table still exists: $table"
            cleanup_errors=true
        fi
    done
    
    # Check Lambda functions
    local functions=("${STACK_NAME}-orchestrator" "${STACK_NAME}-compensation-handler" "${STACK_NAME}-order-service" "${STACK_NAME}-payment-service" "${STACK_NAME}-inventory-service")
    for func in "${functions[@]}"; do
        if aws lambda get-function --function-name "$func" &>/dev/null; then
            error "Lambda function still exists: $func"
            cleanup_errors=true
        fi
    done
    
    # Check IAM role
    if aws iam get-role --role-name "${STACK_NAME}-lambda-role" &>/dev/null; then
        error "IAM role still exists: ${STACK_NAME}-lambda-role"
        cleanup_errors=true
    fi
    
    if [[ "$cleanup_errors" == "true" ]]; then
        error "Some resources were not properly deleted. Please check manually."
        exit 1
    else
        success "Cleanup verification completed successfully"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "================================================"
    echo "Stack Name: ${STACK_NAME}"
    echo "Region: ${AWS_REGION}"
    echo "Account ID: ${AWS_ACCOUNT_ID}"
    echo ""
    echo "Resources cleaned up:"
    echo "  ✓ DynamoDB Tables (4)"
    echo "  ✓ SQS Queues (5)"
    echo "  ✓ Lambda Functions (5)"
    echo "  ✓ API Gateway (1)"
    echo "  ✓ CloudWatch Alarms (2)"
    echo "  ✓ CloudWatch Dashboard (1)"
    echo "  ✓ IAM Role (1)"
    echo "  ✓ Local Files"
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Status: DRY-RUN COMPLETED (no resources deleted)"
    else
        echo "Status: CLEANUP COMPLETED"
    fi
    echo "================================================"
}

# Function to handle script interruption
cleanup_on_interrupt() {
    error "Script interrupted during cleanup. Some resources may still exist."
    warning "Please run the script again to complete cleanup."
    exit 1
}

# Main cleanup function
main() {
    # Set up interrupt handler
    trap cleanup_on_interrupt SIGINT SIGTERM
    
    log "Starting distributed transaction processing cleanup..."
    
    # Run cleanup steps
    check_prerequisites
    setup_environment
    discover_stack_resources
    confirm_deletion
    
    # Cleanup in reverse order of creation
    list_event_source_mappings
    delete_event_source_mappings
    delete_api_gateway
    delete_lambda_functions
    delete_sqs_queues
    delete_dynamodb_tables
    delete_cloudwatch_resources
    delete_iam_role
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    display_cleanup_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "Dry-run completed successfully. No resources were deleted."
    else
        success "Cleanup completed successfully!"
        log "All resources have been removed. You will no longer be charged for these resources."
    fi
}

# Run main function
main