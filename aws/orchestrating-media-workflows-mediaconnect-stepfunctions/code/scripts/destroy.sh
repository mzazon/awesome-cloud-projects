#!/bin/bash

# Destroy script for Orchestrating Media Workflows with MediaConnect and Step Functions
# This script safely removes all resources created by the deploy.sh script

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Load deployment variables
load_deployment_vars() {
    if [[ ! -f .deployment_vars ]]; then
        error "Deployment variables file (.deployment_vars) not found. Cannot proceed with cleanup."
    fi
    
    log "Loading deployment variables..."
    source .deployment_vars
    
    # Verify required variables are set
    local required_vars=(
        "AWS_REGION" "AWS_ACCOUNT_ID" "FLOW_NAME" "STATE_MACHINE_NAME" 
        "SNS_TOPIC_NAME" "LAMBDA_ROLE_NAME" "SF_ROLE_NAME" "EB_ROLE_NAME"
        "LAMBDA_BUCKET" "RANDOM_SUFFIX"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required variable $var is not set in .deployment_vars"
        fi
    done
    
    success "Deployment variables loaded successfully"
}

# Confirmation prompt
confirm_destruction() {
    echo ""
    echo "=================================="
    echo "   RESOURCE DESTRUCTION WARNING"
    echo "=================================="
    echo ""
    echo "This will PERMANENTLY DELETE the following resources:"
    echo "• MediaConnect Flow: ${FLOW_NAME}"
    echo "• Step Functions State Machine: ${STATE_MACHINE_NAME}"
    echo "• Lambda Functions: stream-monitor-${RANDOM_SUFFIX}, alert-handler-${RANDOM_SUFFIX}"
    echo "• SNS Topic: ${SNS_TOPIC_NAME}"
    echo "• CloudWatch Alarms and Dashboard"
    echo "• EventBridge Rules"
    echo "• IAM Roles and Policies"
    echo "• S3 Bucket: ${LAMBDA_BUCKET}"
    echo ""
    echo -e "${RED}This action CANNOT be undone!${NC}"
    echo ""
    
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        echo "Destruction cancelled."
        exit 0
    fi
    
    echo ""
    log "Proceeding with resource destruction..."
}

# Stop and delete MediaConnect flow
destroy_mediaconnect_flow() {
    log "Stopping and deleting MediaConnect flow..."
    
    if [[ -n "${FLOW_ARN:-}" ]]; then
        # Check if flow exists
        if aws mediaconnect describe-flow --flow-arn "${FLOW_ARN}" &>/dev/null; then
            # Stop the flow first
            log "Stopping MediaConnect flow..."
            aws mediaconnect stop-flow --flow-arn "${FLOW_ARN}" || warning "Failed to stop flow (may already be stopped)"
            
            # Wait for flow to stop
            local max_wait=60
            local wait_time=0
            while [[ $wait_time -lt $max_wait ]]; do
                local status=$(aws mediaconnect describe-flow --flow-arn "${FLOW_ARN}" \
                    --query 'Flow.Status' --output text 2>/dev/null || echo "NOT_FOUND")
                
                if [[ "$status" == "STANDBY" ]] || [[ "$status" == "NOT_FOUND" ]]; then
                    break
                fi
                
                log "Waiting for flow to stop... (${wait_time}s/${max_wait}s)"
                sleep 5
                wait_time=$((wait_time + 5))
            done
            
            # Delete the flow
            log "Deleting MediaConnect flow..."
            aws mediaconnect delete-flow --flow-arn "${FLOW_ARN}" || warning "Failed to delete MediaConnect flow"
            
            success "MediaConnect flow deleted"
        else
            warning "MediaConnect flow not found or already deleted"
        fi
    else
        warning "MediaConnect flow ARN not found in deployment variables"
    fi
}

# Delete CloudWatch resources
destroy_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete alarms
    local alarms=(
        "${FLOW_NAME}-packet-loss"
        "${FLOW_NAME}-jitter"
        "${FLOW_NAME}-workflow-trigger"
    )
    
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --query 'MetricAlarms[0]' --output text &>/dev/null; then
            aws cloudwatch delete-alarms --alarm-names "$alarm" || warning "Failed to delete alarm: $alarm"
        else
            log "Alarm $alarm not found or already deleted"
        fi
    done
    
    # Delete dashboard
    local dashboard_name="${FLOW_NAME}-monitoring"
    if aws cloudwatch get-dashboard --dashboard-name "$dashboard_name" &>/dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name" || warning "Failed to delete dashboard"
    else
        log "Dashboard $dashboard_name not found or already deleted"
    fi
    
    success "CloudWatch resources deleted"
}

# Remove EventBridge rule
destroy_eventbridge_rule() {
    log "Removing EventBridge rule..."
    
    local rule_name="${FLOW_NAME}-alarm-rule"
    
    # Check if rule exists
    if aws events describe-rule --name "$rule_name" &>/dev/null; then
        # Remove targets first
        local targets=$(aws events list-targets-by-rule --rule "$rule_name" \
            --query 'Targets[].Id' --output text 2>/dev/null || echo "")
        
        if [[ -n "$targets" ]]; then
            aws events remove-targets --rule "$rule_name" --ids $targets || warning "Failed to remove EventBridge targets"
        fi
        
        # Delete the rule
        aws events delete-rule --name "$rule_name" || warning "Failed to delete EventBridge rule"
        
        success "EventBridge rule deleted"
    else
        warning "EventBridge rule not found or already deleted"
    fi
}

# Delete Step Functions state machine
destroy_step_functions() {
    log "Deleting Step Functions state machine..."
    
    if [[ -n "${STATE_MACHINE_ARN:-}" ]]; then
        # Check if state machine exists
        if aws stepfunctions describe-state-machine --state-machine-arn "${STATE_MACHINE_ARN}" &>/dev/null; then
            aws stepfunctions delete-state-machine --state-machine-arn "${STATE_MACHINE_ARN}" || warning "Failed to delete Step Functions state machine"
            success "Step Functions state machine deleted"
        else
            warning "Step Functions state machine not found or already deleted"
        fi
    else
        warning "Step Functions state machine ARN not found in deployment variables"
    fi
}

# Remove Lambda functions
destroy_lambda_functions() {
    log "Removing Lambda functions..."
    
    local functions=(
        "stream-monitor-${RANDOM_SUFFIX}"
        "alert-handler-${RANDOM_SUFFIX}"
    )
    
    for function_name in "${functions[@]}"; do
        if aws lambda get-function --function-name "$function_name" &>/dev/null; then
            aws lambda delete-function --function-name "$function_name" || warning "Failed to delete Lambda function: $function_name"
        else
            log "Lambda function $function_name not found or already deleted"
        fi
    done
    
    success "Lambda functions deleted"
}

# Clean up IAM roles and policies
destroy_iam_roles() {
    log "Cleaning up IAM roles and policies..."
    
    local roles=(
        "${LAMBDA_ROLE_NAME}"
        "${SF_ROLE_NAME}"
        "${EB_ROLE_NAME}"
    )
    
    for role_name in "${roles[@]}"; do
        if aws iam get-role --role-name "$role_name" &>/dev/null; then
            log "Cleaning up role: $role_name"
            
            # List and delete inline policies
            local policies=$(aws iam list-role-policies --role-name "$role_name" \
                --query 'PolicyNames' --output text 2>/dev/null || echo "")
            
            for policy in $policies; do
                if [[ -n "$policy" && "$policy" != "None" ]]; then
                    aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy" || warning "Failed to delete policy: $policy"
                fi
            done
            
            # List and detach managed policies
            local attached_policies=$(aws iam list-attached-role-policies --role-name "$role_name" \
                --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
            
            for policy_arn in $attached_policies; do
                if [[ -n "$policy_arn" && "$policy_arn" != "None" ]]; then
                    aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" || warning "Failed to detach policy: $policy_arn"
                fi
            done
            
            # Delete the role
            aws iam delete-role --role-name "$role_name" || warning "Failed to delete role: $role_name"
        else
            log "IAM role $role_name not found or already deleted"
        fi
    done
    
    success "IAM roles and policies cleaned up"
}

# Delete SNS topic
destroy_sns_topic() {
    log "Deleting SNS topic..."
    
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        # Check if topic exists
        if aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}" &>/dev/null; then
            aws sns delete-topic --topic-arn "${SNS_TOPIC_ARN}" || warning "Failed to delete SNS topic"
            success "SNS topic deleted"
        else
            warning "SNS topic not found or already deleted"
        fi
    else
        warning "SNS topic ARN not found in deployment variables"
    fi
}

# Clean up S3 bucket
destroy_s3_bucket() {
    log "Cleaning up S3 bucket..."
    
    if aws s3 ls "s3://${LAMBDA_BUCKET}" &>/dev/null; then
        # Remove all objects first
        log "Removing objects from S3 bucket..."
        aws s3 rm "s3://${LAMBDA_BUCKET}" --recursive || warning "Failed to remove objects from S3 bucket"
        
        # Delete the bucket
        aws s3 rb "s3://${LAMBDA_BUCKET}" || warning "Failed to delete S3 bucket"
        
        success "S3 bucket deleted"
    else
        warning "S3 bucket not found or already deleted"
    fi
}

# Wait for resource deletion confirmation
wait_for_deletions() {
    log "Waiting for resource deletions to propagate..."
    
    # Wait a bit for AWS eventual consistency
    sleep 10
    
    # Verify critical resources are deleted
    local verification_passed=true
    
    # Check MediaConnect flow
    if [[ -n "${FLOW_ARN:-}" ]] && aws mediaconnect describe-flow --flow-arn "${FLOW_ARN}" &>/dev/null; then
        warning "MediaConnect flow still exists"
        verification_passed=false
    fi
    
    # Check Step Functions state machine
    if [[ -n "${STATE_MACHINE_ARN:-}" ]] && aws stepfunctions describe-state-machine --state-machine-arn "${STATE_MACHINE_ARN}" &>/dev/null; then
        warning "Step Functions state machine still exists"
        verification_passed=false
    fi
    
    # Check Lambda functions
    if aws lambda get-function --function-name "stream-monitor-${RANDOM_SUFFIX}" &>/dev/null; then
        warning "Lambda function stream-monitor-${RANDOM_SUFFIX} still exists"
        verification_passed=false
    fi
    
    if $verification_passed; then
        success "Resource deletion verification passed"
    else
        warning "Some resources may still exist. Please check AWS console manually."
    fi
}

# Cleanup deployment variables file
cleanup_deployment_vars() {
    log "Cleaning up deployment variables file..."
    
    if [[ -f .deployment_vars ]]; then
        rm -f .deployment_vars
        success "Deployment variables file deleted"
    fi
}

# Display destruction summary
show_destruction_summary() {
    echo ""
    echo "=================================="
    echo "   DESTRUCTION COMPLETE"
    echo "=================================="
    echo ""
    echo "All resources have been removed:"
    echo "• MediaConnect Flow and related resources"
    echo "• Step Functions state machine"
    echo "• Lambda functions and execution roles"
    echo "• CloudWatch alarms and dashboard"
    echo "• EventBridge rules and targets"
    echo "• SNS topic and subscriptions"
    echo "• S3 bucket and contents"
    echo "• IAM roles and policies"
    echo ""
    echo "✨ Cleanup completed successfully!"
    echo ""
    warning "Please verify in AWS Console that all resources have been removed."
    warning "Some charges may still apply for resources created before deletion."
}

# Handle script interruption
handle_interruption() {
    echo ""
    warning "Destruction process interrupted!"
    warning "Some resources may have been partially deleted."
    warning "Please run this script again or check AWS Console manually."
    exit 1
}

# Main destruction function
main() {
    echo "🗑️  Starting destruction of MediaConnect workflow resources..."
    echo ""
    
    load_deployment_vars
    confirm_destruction
    
    # Execute destruction in reverse order of creation
    destroy_cloudwatch_resources
    destroy_eventbridge_rule
    destroy_step_functions
    destroy_lambda_functions
    destroy_mediaconnect_flow
    destroy_iam_roles
    destroy_sns_topic
    destroy_s3_bucket
    
    wait_for_deletions
    cleanup_deployment_vars
    show_destruction_summary
}

# Set up signal handlers
trap handle_interruption INT TERM

# Check if running in dry-run mode
if [[ "${1:-}" == "--dry-run" ]]; then
    echo "🔍 DRY RUN MODE - No resources will be deleted"
    echo ""
    
    if [[ -f .deployment_vars ]]; then
        source .deployment_vars
        echo "The following resources would be deleted:"
        echo "• MediaConnect Flow: ${FLOW_NAME:-'Unknown'}"
        echo "• Step Functions: ${STATE_MACHINE_NAME:-'Unknown'}"
        echo "• SNS Topic: ${SNS_TOPIC_NAME:-'Unknown'}"
        echo "• Lambda Functions: stream-monitor-${RANDOM_SUFFIX:-'Unknown'}, alert-handler-${RANDOM_SUFFIX:-'Unknown'}"
        echo "• S3 Bucket: ${LAMBDA_BUCKET:-'Unknown'}"
        echo "• CloudWatch Alarms and Dashboard"
        echo "• EventBridge Rules"
        echo "• IAM Roles: ${LAMBDA_ROLE_NAME:-'Unknown'}, ${SF_ROLE_NAME:-'Unknown'}, ${EB_ROLE_NAME:-'Unknown'}"
        echo ""
        echo "To proceed with actual deletion, run: ./destroy.sh"
    else
        error "No deployment variables found. Nothing to destroy."
    fi
    exit 0
fi

# Run main function
main "$@"