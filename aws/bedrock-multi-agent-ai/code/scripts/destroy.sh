#!/bin/bash

# Multi-Agent AI Workflows with Amazon Bedrock AgentCore - Cleanup Script
# This script removes all resources created by the deployment script

set -e
set -o pipefail

# Color codes for output formatting
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

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command '$1' not found. Please install it and try again."
        exit 1
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local max_attempts="${3:-30}"
    local attempt=0
    
    log_info "Waiting for $resource_type: $resource_name to be deleted..."
    
    while [ $attempt -lt $max_attempts ]; do
        case $resource_type in
            "dynamodb-table")
                if ! aws dynamodb describe-table --table-name "$resource_name" >/dev/null 2>&1; then
                    return 0
                fi
                ;;
            "bedrock-agent")
                if ! aws bedrock-agent get-agent --agent-id "$resource_name" >/dev/null 2>&1; then
                    return 0
                fi
                ;;
        esac
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 10
    done
    
    log_warning "Timeout waiting for $resource_type: $resource_name deletion"
    return 1
}

# Function to prompt for confirmation
confirm_destruction() {
    local suffix="$1"
    
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This script will permanently delete the following resources:"
    echo "• All Bedrock agents with suffix: ${suffix}"
    echo "• Lambda function: agent-coordinator-${suffix}"
    echo "• DynamoDB table: agent-memory-${suffix}"
    echo "• EventBridge bus: multi-agent-bus-${suffix}"
    echo "• IAM roles: BedrockAgentRole-${suffix}, LambdaCoordinatorRole-${suffix}"
    echo "• CloudWatch logs and dashboards"
    echo "• SQS dead letter queue"
    echo ""
    log_warning "This action cannot be undone!"
    echo ""
    
    if [ "${FORCE_DELETE:-false}" = "true" ]; then
        log_info "Force deletion enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
}

# Function to load deployment configuration
load_deployment_config() {
    local config_file="$1"
    
    if [ -n "$config_file" ] && [ -f "$config_file" ]; then
        log_info "Loading deployment configuration from: $config_file"
        source "$config_file"
        return 0
    fi
    
    # Try to find config file in /tmp
    local tmp_configs
    tmp_configs=$(ls /tmp/multi-agent-deployment-*.env 2>/dev/null || true)
    
    if [ -n "$tmp_configs" ]; then
        local latest_config
        latest_config=$(echo "$tmp_configs" | tail -n1)
        log_info "Found deployment configuration: $latest_config"
        read -p "Load this configuration? (y/n): " load_config
        
        if [ "$load_config" = "y" ] || [ "$load_config" = "Y" ]; then
            source "$latest_config"
            return 0
        fi
    fi
    
    return 1
}

# Function to discover resources by tags
discover_resources() {
    log_info "Discovering resources to delete..."
    
    # Set AWS region if not already set
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
    
    if [ -z "$RANDOM_SUFFIX" ]; then
        log_info "No deployment configuration loaded. Attempting to discover resources..."
        
        # Look for resources with MultiAgentWorkflow tag
        local agents
        agents=$(aws bedrock-agent list-agents --query 'agentSummaries[?contains(agentName, `agent-`)].{Name:agentName,ID:agentId}' --output json 2>/dev/null || echo "[]")
        
        if [ "$agents" != "[]" ] && [ "$(echo "$agents" | jq length)" -gt 0 ]; then
            echo ""
            log_info "Found the following Bedrock agents:"
            echo "$agents" | jq -r '.[] | "  • \(.Name) (\(.ID))"'
            echo ""
            
            read -p "Enter the deployment suffix to delete (e.g., abc123): " user_suffix
            if [ -n "$user_suffix" ]; then
                export RANDOM_SUFFIX="$user_suffix"
                
                # Set resource names based on suffix
                export SUPERVISOR_AGENT_NAME="supervisor-agent-${RANDOM_SUFFIX}"
                export FINANCE_AGENT_NAME="finance-agent-${RANDOM_SUFFIX}"
                export SUPPORT_AGENT_NAME="support-agent-${RANDOM_SUFFIX}"
                export ANALYTICS_AGENT_NAME="analytics-agent-${RANDOM_SUFFIX}"
                export EVENT_BUS_NAME="multi-agent-bus-${RANDOM_SUFFIX}"
                export COORDINATOR_FUNCTION_NAME="agent-coordinator-${RANDOM_SUFFIX}"
                export MEMORY_TABLE_NAME="agent-memory-${RANDOM_SUFFIX}"
            else
                log_error "No suffix provided. Cannot proceed with cleanup."
                exit 1
            fi
        else
            log_error "No resources found to delete. Deployment may have been already cleaned up."
            exit 0
        fi
    fi
}

# Function to get agent IDs
get_agent_ids() {
    log_info "Getting agent IDs for deletion..."
    
    # Get agent IDs if not already set
    if [ -z "$SUPERVISOR_AGENT_ID" ]; then
        export SUPERVISOR_AGENT_ID=$(aws bedrock-agent list-agents \
            --query "agentSummaries[?agentName=='${SUPERVISOR_AGENT_NAME}'].agentId" \
            --output text 2>/dev/null || true)
    fi
    
    if [ -z "$FINANCE_AGENT_ID" ]; then
        export FINANCE_AGENT_ID=$(aws bedrock-agent list-agents \
            --query "agentSummaries[?agentName=='${FINANCE_AGENT_NAME}'].agentId" \
            --output text 2>/dev/null || true)
    fi
    
    if [ -z "$SUPPORT_AGENT_ID" ]; then
        export SUPPORT_AGENT_ID=$(aws bedrock-agent list-agents \
            --query "agentSummaries[?agentName=='${SUPPORT_AGENT_NAME}'].agentId" \
            --output text 2>/dev/null || true)
    fi
    
    if [ -z "$ANALYTICS_AGENT_ID" ]; then
        export ANALYTICS_AGENT_ID=$(aws bedrock-agent list-agents \
            --query "agentSummaries[?agentName=='${ANALYTICS_AGENT_NAME}'].agentId" \
            --output text 2>/dev/null || true)
    fi
}

# Function to delete Bedrock agents
delete_bedrock_agents() {
    log_info "Deleting Bedrock agents and aliases..."
    
    local agents=(
        "${SUPERVISOR_AGENT_ID}:${SUPERVISOR_AGENT_NAME}"
        "${FINANCE_AGENT_ID}:${FINANCE_AGENT_NAME}"
        "${SUPPORT_AGENT_ID}:${SUPPORT_AGENT_NAME}"
        "${ANALYTICS_AGENT_ID}:${ANALYTICS_AGENT_ID}"
    )
    
    for agent_info in "${agents[@]}"; do
        local agent_id="${agent_info%%:*}"
        local agent_name="${agent_info##*:}"
        
        if [ -n "$agent_id" ] && [ "$agent_id" != "None" ]; then
            log_info "Deleting agent: $agent_name ($agent_id)"
            
            # Delete agent aliases first
            local aliases
            aliases=$(aws bedrock-agent list-agent-aliases \
                --agent-id "$agent_id" \
                --query 'agentAliasSummaries[].agentAliasId' \
                --output text 2>/dev/null || true)
            
            if [ -n "$aliases" ]; then
                for alias_id in $aliases; do
                    if [ "$alias_id" != "None" ]; then
                        aws bedrock-agent delete-agent-alias \
                            --agent-id "$agent_id" \
                            --agent-alias-id "$alias_id" >/dev/null 2>&1 || true
                    fi
                done
                log_success "Deleted aliases for agent: $agent_name"
            fi
            
            # Delete the agent
            aws bedrock-agent delete-agent --agent-id "$agent_id" >/dev/null 2>&1 || true
            log_success "Deleted agent: $agent_name"
        else
            log_warning "Agent not found: $agent_name"
        fi
    done
    
    log_success "Bedrock agents deletion completed"
}

# Function to delete EventBridge resources
delete_eventbridge_resources() {
    log_info "Deleting EventBridge resources..."
    
    # Remove EventBridge targets
    if aws events describe-rule --name agent-task-router --event-bus-name "${EVENT_BUS_NAME}" >/dev/null 2>&1; then
        aws events remove-targets \
            --rule agent-task-router \
            --event-bus-name "${EVENT_BUS_NAME}" \
            --ids 1 >/dev/null 2>&1 || true
        
        # Delete EventBridge rule
        aws events delete-rule \
            --name agent-task-router \
            --event-bus-name "${EVENT_BUS_NAME}" >/dev/null 2>&1 || true
        
        log_success "Deleted EventBridge rule: agent-task-router"
    fi
    
    # Delete custom event bus
    if aws events describe-event-bus --name "${EVENT_BUS_NAME}" >/dev/null 2>&1; then
        aws events delete-event-bus --name "${EVENT_BUS_NAME}" >/dev/null 2>&1 || true
        log_success "Deleted EventBridge bus: ${EVENT_BUS_NAME}"
    fi
    
    log_success "EventBridge resources deletion completed"
}

# Function to delete Lambda function
delete_lambda_function() {
    log_info "Deleting Lambda function..."
    
    if aws lambda get-function --function-name "${COORDINATOR_FUNCTION_NAME}" >/dev/null 2>&1; then
        aws lambda delete-function --function-name "${COORDINATOR_FUNCTION_NAME}" >/dev/null 2>&1 || true
        log_success "Deleted Lambda function: ${COORDINATOR_FUNCTION_NAME}"
    else
        log_warning "Lambda function not found: ${COORDINATOR_FUNCTION_NAME}"
    fi
    
    log_success "Lambda function deletion completed"
}

# Function to delete IAM roles
delete_iam_roles() {
    log_info "Deleting IAM roles..."
    
    local roles=(
        "LambdaCoordinatorRole-${RANDOM_SUFFIX}"
        "BedrockAgentRole-${RANDOM_SUFFIX}"
    )
    
    for role_name in "${roles[@]}"; do
        if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
            log_info "Deleting IAM role: $role_name"
            
            # Detach managed policies
            local attached_policies
            attached_policies=$(aws iam list-attached-role-policies \
                --role-name "$role_name" \
                --query 'AttachedPolicies[].PolicyArn' \
                --output text 2>/dev/null || true)
            
            for policy_arn in $attached_policies; do
                if [ "$policy_arn" != "None" ]; then
                    aws iam detach-role-policy \
                        --role-name "$role_name" \
                        --policy-arn "$policy_arn" >/dev/null 2>&1 || true
                fi
            done
            
            # Delete inline policies
            local inline_policies
            inline_policies=$(aws iam list-role-policies \
                --role-name "$role_name" \
                --query 'PolicyNames' \
                --output text 2>/dev/null || true)
            
            for policy_name in $inline_policies; do
                if [ "$policy_name" != "None" ]; then
                    aws iam delete-role-policy \
                        --role-name "$role_name" \
                        --policy-name "$policy_name" >/dev/null 2>&1 || true
                fi
            done
            
            # Delete the role
            aws iam delete-role --role-name "$role_name" >/dev/null 2>&1 || true
            log_success "Deleted IAM role: $role_name"
        else
            log_warning "IAM role not found: $role_name"
        fi
    done
    
    log_success "IAM roles deletion completed"
}

# Function to delete DynamoDB table
delete_dynamodb_table() {
    log_info "Deleting DynamoDB table..."
    
    if aws dynamodb describe-table --table-name "${MEMORY_TABLE_NAME}" >/dev/null 2>&1; then
        aws dynamodb delete-table --table-name "${MEMORY_TABLE_NAME}" >/dev/null 2>&1 || true
        
        # Wait for table deletion
        wait_for_deletion "dynamodb-table" "${MEMORY_TABLE_NAME}"
        
        log_success "Deleted DynamoDB table: ${MEMORY_TABLE_NAME}"
    else
        log_warning "DynamoDB table not found: ${MEMORY_TABLE_NAME}"
    fi
    
    log_success "DynamoDB table deletion completed"
}

# Function to delete SQS resources
delete_sqs_resources() {
    log_info "Deleting SQS resources..."
    
    local queue_name="multi-agent-dlq-${RANDOM_SUFFIX}"
    
    # Get queue URL if not already set
    if [ -z "$DLQ_URL" ]; then
        DLQ_URL=$(aws sqs get-queue-url --queue-name "$queue_name" --query 'QueueUrl' --output text 2>/dev/null || true)
    fi
    
    if [ -n "$DLQ_URL" ] && [ "$DLQ_URL" != "None" ]; then
        aws sqs delete-queue --queue-url "$DLQ_URL" >/dev/null 2>&1 || true
        log_success "Deleted SQS queue: $queue_name"
    else
        log_warning "SQS queue not found: $queue_name"
    fi
    
    log_success "SQS resources deletion completed"
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log_info "Deleting CloudWatch resources..."
    
    # Delete CloudWatch Dashboard
    local dashboard_name="MultiAgentWorkflow-${RANDOM_SUFFIX}"
    if aws cloudwatch describe-dashboards --dashboard-names "$dashboard_name" >/dev/null 2>&1; then
        aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name" >/dev/null 2>&1 || true
        log_success "Deleted CloudWatch dashboard: $dashboard_name"
    fi
    
    # Delete CloudWatch Log Groups
    local log_groups=(
        "/aws/bedrock/agents/supervisor"
        "/aws/bedrock/agents/specialized"
        "/aws/lambda/${COORDINATOR_FUNCTION_NAME}"
    )
    
    for log_group in "${log_groups[@]}"; do
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group"; then
            aws logs delete-log-group --log-group-name "$log_group" >/dev/null 2>&1 || true
            log_success "Deleted log group: $log_group"
        fi
    done
    
    log_success "CloudWatch resources deletion completed"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove deployment configuration file
    local config_file="/tmp/multi-agent-deployment-${RANDOM_SUFFIX}.env"
    if [ -f "$config_file" ]; then
        rm -f "$config_file"
        log_success "Deleted configuration file: $config_file"
    fi
    
    # Remove any other temporary files
    rm -f /tmp/coordinator.py /tmp/coordinator.zip /tmp/dashboard-config.json 2>/dev/null || true
    
    log_success "Temporary files cleanup completed"
}

# Function to display deletion summary
display_deletion_summary() {
    log_success "🧹 Multi-Agent AI Workflow cleanup completed successfully!"
    log_info "Cleanup completed at: $(date)"
    
    echo ""
    log_info "=== DELETION SUMMARY ==="
    echo "Deployment Suffix: ${RANDOM_SUFFIX}"
    echo "• Deleted Bedrock agents and aliases"
    echo "• Deleted Lambda function: ${COORDINATOR_FUNCTION_NAME}"
    echo "• Deleted DynamoDB table: ${MEMORY_TABLE_NAME}"
    echo "• Deleted EventBridge bus: ${EVENT_BUS_NAME}"
    echo "• Deleted IAM roles with suffix: ${RANDOM_SUFFIX}"
    echo "• Deleted CloudWatch resources"
    echo "• Deleted SQS dead letter queue"
    echo "• Cleaned up temporary files"
    echo ""
    log_info "All resources have been successfully removed."
    log_info "You will no longer be charged for these resources."
}

# Function to check AWS connectivity
check_aws_connectivity() {
    log_info "Checking AWS connectivity..."
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "Unable to connect to AWS. Please check your credentials and try again."
        exit 1
    fi
    
    log_success "AWS connectivity verified"
}

# Usage function
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --config FILE     Load deployment configuration from FILE"
    echo "  -s, --suffix SUFFIX   Use specific deployment suffix"
    echo "  -f, --force          Skip confirmation prompts"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup"
    echo "  $0 -c /tmp/deployment.env            # Use config file"
    echo "  $0 -s abc123                         # Use specific suffix"
    echo "  $0 -f -s abc123                      # Force cleanup with suffix"
}

# Main cleanup function
main() {
    local config_file=""
    local suffix=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                config_file="$2"
                shift 2
                ;;
            -s|--suffix)
                suffix="$2"
                shift 2
                ;;
            -f|--force)
                export FORCE_DELETE="true"
                shift
                ;;
            -h|--help)
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
    
    log_info "Starting Multi-Agent AI Workflow cleanup..."
    log_info "Cleanup started at: $(date)"
    
    # Check prerequisites
    check_command "aws"
    check_command "jq"
    check_aws_connectivity
    
    # Set suffix if provided
    if [ -n "$suffix" ]; then
        export RANDOM_SUFFIX="$suffix"
    fi
    
    # Load configuration or discover resources
    if ! load_deployment_config "$config_file"; then
        discover_resources
    fi
    
    # Get agent IDs
    get_agent_ids
    
    # Confirm deletion
    confirm_destruction "$RANDOM_SUFFIX"
    
    log_info "Starting resource deletion..."
    
    # Delete resources in reverse order of creation
    delete_bedrock_agents
    delete_eventbridge_resources
    delete_lambda_function
    delete_iam_roles
    delete_dynamodb_table
    delete_sqs_resources
    delete_cloudwatch_resources
    cleanup_temp_files
    
    # Display summary
    display_deletion_summary
}

# Run main function
main "$@"