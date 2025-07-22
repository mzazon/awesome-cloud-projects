#!/bin/bash

# AWS Lambda Cost Optimizer Cleanup Script
# This script removes resources created by the Lambda cost optimization deployment

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ANALYSIS_DIR="${SCRIPT_DIR}/../analysis"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

# Success message function
success() {
    log "${GREEN}✅ $1${NC}"
}

# Warning message function
warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

# Info message function
info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# Confirmation function
confirm() {
    local message="$1"
    local default="${2:-n}"
    
    if [ "$default" = "y" ]; then
        local prompt="$message [Y/n]: "
    else
        local prompt="$message [y/N]: "
    fi
    
    read -p "$prompt" -n 1 -r
    echo
    
    if [ "$default" = "y" ]; then
        [[ ! $REPLY =~ ^[Nn]$ ]]
    else
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    success "Prerequisites check completed"
}

# Setup environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log "Region: $AWS_REGION"
    log "Account ID: $AWS_ACCOUNT_ID"
    
    success "Environment setup completed"
}

# Remove CloudWatch alarms
remove_cloudwatch_alarms() {
    info "Removing CloudWatch alarms..."
    
    local alarms=("Lambda-Optimization-High-Error-Rate" "Lambda-Optimization-Duration-Increase")
    
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --query 'MetricAlarms' --output text | grep -q "$alarm"; then
            info "Removing CloudWatch alarm: $alarm"
            aws cloudwatch delete-alarms --alarm-names "$alarm"
            success "Removed alarm: $alarm"
        else
            info "Alarm $alarm not found (may have been removed already)"
        fi
    done
    
    success "CloudWatch alarms cleanup completed"
}

# Remove SNS topic
remove_sns_topic() {
    info "Removing SNS topic..."
    
    local sns_topic_name="lambda-optimization-alerts"
    local sns_topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${sns_topic_name}"
    
    if aws sns get-topic-attributes --topic-arn "$sns_topic_arn" &>/dev/null; then
        if confirm "Remove SNS topic '$sns_topic_name'? This will stop all alert notifications."; then
            # List subscriptions first
            local subscriptions=$(aws sns list-subscriptions-by-topic --topic-arn "$sns_topic_arn" --query 'Subscriptions[].SubscriptionArn' --output text)
            
            # Remove subscriptions
            if [ -n "$subscriptions" ] && [ "$subscriptions" != "None" ]; then
                info "Removing SNS subscriptions..."
                for subscription in $subscriptions; do
                    if [ "$subscription" != "PendingConfirmation" ]; then
                        aws sns unsubscribe --subscription-arn "$subscription"
                        info "Removed subscription: $subscription"
                    fi
                done
            fi
            
            # Remove topic
            aws sns delete-topic --topic-arn "$sns_topic_arn"
            success "Removed SNS topic: $sns_topic_name"
        else
            info "Keeping SNS topic: $sns_topic_name"
        fi
    else
        info "SNS topic '$sns_topic_name' not found"
    fi
}

# Disable Compute Optimizer
disable_compute_optimizer() {
    info "Checking Compute Optimizer status..."
    
    local current_status=$(aws compute-optimizer get-enrollment-status --query 'status' --output text 2>/dev/null || echo "Inactive")
    
    if [ "$current_status" = "Active" ]; then
        warning "Compute Optimizer is currently enabled"
        warning "Disabling it will stop generating new recommendations and remove historical data"
        
        if confirm "Do you want to disable AWS Compute Optimizer? This action cannot be undone."; then
            aws compute-optimizer put-enrollment-status --status Inactive
            
            local new_status=$(aws compute-optimizer get-enrollment-status --query 'status' --output text)
            
            if [ "$new_status" = "Inactive" ]; then
                success "Compute Optimizer disabled successfully"
                warning "Historical recommendations have been removed"
            else
                error_exit "Failed to disable Compute Optimizer"
            fi
        else
            info "Keeping Compute Optimizer enabled"
        fi
    else
        info "Compute Optimizer is not active"
    fi
}

# Restore Lambda function configurations
restore_lambda_configurations() {
    info "Checking for Lambda function baseline configurations..."
    
    local baseline_file="${ANALYSIS_DIR}/lambda-functions-baseline.json"
    
    if [ -f "$baseline_file" ]; then
        if confirm "Do you want to restore Lambda functions to their original memory configurations?"; then
            info "Restoring Lambda function configurations from baseline..."
            
            if command -v jq &> /dev/null; then
                local functions=$(jq -r '.[].functionName' "$baseline_file" 2>/dev/null || echo "")
                
                if [ -n "$functions" ]; then
                    for function_name in $functions; do
                        local original_memory=$(jq -r ".[] | select(.functionName == \"$function_name\") | .memorySize" "$baseline_file")
                        
                        if [ "$original_memory" != "null" ] && [ -n "$original_memory" ]; then
                            info "Restoring $function_name to ${original_memory}MB..."
                            
                            if aws lambda update-function-configuration \
                                --function-name "$function_name" \
                                --memory-size "$original_memory" >/dev/null 2>&1; then
                                success "Restored $function_name to ${original_memory}MB"
                            else
                                warning "Failed to restore $function_name (function may not exist)"
                            fi
                        fi
                    done
                else
                    warning "No functions found in baseline file"
                fi
            else
                warning "jq not available, cannot parse baseline file"
            fi
        else
            info "Keeping current Lambda function configurations"
        fi
    else
        info "No baseline configuration file found"
    fi
}

# Remove analysis files and directories
remove_analysis_files() {
    info "Removing analysis files and directories..."
    
    if [ -d "$ANALYSIS_DIR" ]; then
        if confirm "Remove analysis directory and all optimization data? This includes scripts and recommendations."; then
            # List what will be removed
            info "Files to be removed:"
            find "$ANALYSIS_DIR" -type f | while read -r file; do
                log "  - $(basename "$file")"
            done
            
            if confirm "Proceed with removal?"; then
                rm -rf "$ANALYSIS_DIR"
                success "Analysis directory removed: $ANALYSIS_DIR"
            else
                info "Keeping analysis directory"
            fi
        else
            info "Keeping analysis directory: $ANALYSIS_DIR"
        fi
    else
        info "Analysis directory not found: $ANALYSIS_DIR"
    fi
}

# Remove test resources (if any)
remove_test_resources() {
    info "Checking for test resources..."
    
    local test_function_name="test-optimization-function"
    
    # Check if test function exists
    if aws lambda get-function --function-name "$test_function_name" &>/dev/null; then
        if confirm "Remove test Lambda function '$test_function_name'?"; then
            aws lambda delete-function --function-name "$test_function_name"
            success "Removed test function: $test_function_name"
        else
            info "Keeping test function: $test_function_name"
        fi
    else
        info "No test function found"
    fi
    
    # Remove test files from script directory
    local test_files=("test-function.py" "test-function.zip")
    for file in "${test_files[@]}"; do
        if [ -f "$SCRIPT_DIR/$file" ]; then
            rm -f "$SCRIPT_DIR/$file"
            info "Removed test file: $file"
        fi
    done
    
    # Remove response files from /tmp
    if ls /tmp/response*.json &>/dev/null; then
        rm -f /tmp/response*.json
        info "Removed temporary response files"
    fi
}

# Display cleanup summary
display_cleanup_summary() {
    info "Cleanup Summary:"
    log "=================="
    
    # Check Compute Optimizer status
    local co_status=$(aws compute-optimizer get-enrollment-status --query 'status' --output text 2>/dev/null || echo "Unknown")
    log "Compute Optimizer Status: $co_status"
    
    # Check CloudWatch alarms
    local alarm_count=$(aws cloudwatch describe-alarms --alarm-names "Lambda-Optimization-High-Error-Rate" "Lambda-Optimization-Duration-Increase" --query 'length(MetricAlarms)' --output text 2>/dev/null || echo "0")
    log "Remaining CloudWatch Alarms: $alarm_count"
    
    # Check SNS topic
    local sns_topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:lambda-optimization-alerts"
    if aws sns get-topic-attributes --topic-arn "$sns_topic_arn" &>/dev/null; then
        log "SNS Topic Status: Active"
    else
        log "SNS Topic Status: Removed"
    fi
    
    # Check analysis directory
    if [ -d "$ANALYSIS_DIR" ]; then
        log "Analysis Directory: Preserved"
    else
        log "Analysis Directory: Removed"
    fi
    
    log ""
    success "Cleanup completed successfully!"
    
    if [ "$co_status" = "Active" ]; then
        warning "Compute Optimizer is still active and will continue generating recommendations"
        info "Run the script again to disable it if desired"
    fi
}

# Main cleanup function
main() {
    log "Starting AWS Lambda Cost Optimizer cleanup..."
    log "Timestamp: $(date)"
    log "Script: $0"
    log "Log file: $LOG_FILE"
    
    # Clear previous log
    > "$LOG_FILE"
    
    warning "This script will remove resources created by the Lambda cost optimization deployment"
    warning "Please review what will be removed before proceeding"
    log ""
    
    if ! confirm "Do you want to proceed with the cleanup?"; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    check_prerequisites
    setup_environment
    
    log ""
    info "Starting cleanup process..."
    log ""
    
    remove_cloudwatch_alarms
    remove_sns_topic
    remove_test_resources
    restore_lambda_configurations
    remove_analysis_files
    disable_compute_optimizer
    
    log ""
    display_cleanup_summary
    
    log ""
    info "Cleanup recommendations:"
    log "- Review your Lambda functions to ensure they're configured optimally"
    log "- Consider re-enabling Compute Optimizer in the future for ongoing optimization"
    log "- Monitor your AWS bill to verify cost savings from previous optimizations"
    
    log "Cleanup completed at: $(date)"
}

# Run main function
main "$@"