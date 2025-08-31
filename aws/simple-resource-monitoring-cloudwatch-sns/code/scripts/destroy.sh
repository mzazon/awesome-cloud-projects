#!/bin/bash

# Destroy script for Simple Resource Monitoring with CloudWatch and SNS
# This script safely removes all resources created by the deploy script

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
STATE_FILE="${SCRIPT_DIR}/deploy-state.env"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "[${TIMESTAMP}] $1" | tee -a "${LOG_FILE}"
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

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check if state file exists
    if [[ ! -f "${STATE_FILE}" ]]; then
        warning "State file not found: ${STATE_FILE}"
        warning "Will attempt to clean up resources based on user input"
        return 1
    fi
    
    success "Prerequisites check completed"
    return 0
}

# Load state file
load_state() {
    if [[ -f "${STATE_FILE}" ]]; then
        info "Loading deployment state from: ${STATE_FILE}"
        source "${STATE_FILE}"
        success "State loaded successfully"
        
        # Display loaded resources
        info "Resources to be destroyed:"
        [[ -n "${INSTANCE_ID:-}" ]] && info "  EC2 Instance: ${INSTANCE_ID}"
        [[ -n "${TOPIC_ARN:-}" ]] && info "  SNS Topic: ${TOPIC_ARN}"
        [[ -n "${ALARM_NAME:-}" ]] && info "  CloudWatch Alarm: ${ALARM_NAME}"
        [[ -n "${SUBSCRIPTION_ARN:-}" ]] && info "  SNS Subscription: ${SUBSCRIPTION_ARN}"
        [[ -n "${COMMAND_ID:-}" ]] && info "  SSM Command: ${COMMAND_ID}"
    else
        warning "No state file found. Manual resource specification required."
        return 1
    fi
}

# Manual resource input
manual_resource_input() {
    warning "State file not found. Please provide resource information manually."
    echo ""
    
    # Get AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        read -p "Enter AWS region (default: us-east-1): " AWS_REGION
        AWS_REGION=${AWS_REGION:-us-east-1}
    fi
    
    # Get instance ID
    echo "Enter EC2 Instance ID (leave blank to skip):"
    read -p "Instance ID: " INSTANCE_ID
    
    # Get SNS topic name or ARN
    echo "Enter SNS Topic Name or ARN (leave blank to skip):"
    read -p "Topic: " TOPIC_INPUT
    if [[ -n "${TOPIC_INPUT}" ]]; then
        if [[ "${TOPIC_INPUT}" == arn:aws:sns:* ]]; then
            TOPIC_ARN="${TOPIC_INPUT}"
        else
            TOPIC_ARN="arn:aws:sns:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):${TOPIC_INPUT}"
        fi
    fi
    
    # Get alarm name
    echo "Enter CloudWatch Alarm Name (leave blank to skip):"
    read -p "Alarm Name: " ALARM_NAME
    
    info "Manual input completed"
}

# Confirmation prompt
confirm_destruction() {
    echo ""
    echo "=========================================="
    echo "DESTRUCTION CONFIRMATION"
    echo "=========================================="
    echo "The following resources will be PERMANENTLY DELETED:"
    echo ""
    
    if [[ -n "${INSTANCE_ID:-}" ]]; then
        echo "  🖥️  EC2 Instance: ${INSTANCE_ID}"
    fi
    
    if [[ -n "${TOPIC_ARN:-}" ]]; then
        echo "  📧 SNS Topic: ${TOPIC_ARN}"
    fi
    
    if [[ -n "${ALARM_NAME:-}" ]]; then
        echo "  ⏰ CloudWatch Alarm: ${ALARM_NAME}"
    fi
    
    if [[ -n "${SUBSCRIPTION_ARN:-}" ]]; then
        echo "  📮 SNS Subscription: ${SUBSCRIPTION_ARN}"
    fi
    
    if [[ -n "${COMMAND_ID:-}" ]]; then
        echo "  💻 SSM Command: ${COMMAND_ID} (will be cancelled if running)"
    fi
    
    echo ""
    echo "=========================================="
    echo ""
    
    # Force confirmation
    read -p "Are you sure you want to delete these resources? Type 'DELETE' to confirm: " CONFIRMATION
    
    if [[ "${CONFIRMATION}" != "DELETE" ]]; then
        warning "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Cancel SSM command if running
cancel_ssm_command() {
    if [[ -n "${COMMAND_ID:-}" && -n "${INSTANCE_ID:-}" ]]; then
        info "Cancelling SSM command if running..."
        
        aws ssm cancel-command \
            --command-id "${COMMAND_ID}" \
            --instance-ids "${INSTANCE_ID}" 2>/dev/null || {
            info "SSM command not found or already completed"
        }
        
        success "SSM command cancellation attempted"
    fi
}

# Delete CloudWatch alarm
delete_cloudwatch_alarm() {
    if [[ -n "${ALARM_NAME:-}" ]]; then
        info "Deleting CloudWatch alarm: ${ALARM_NAME}"
        
        # Check if alarm exists
        if aws cloudwatch describe-alarms --alarm-names "${ALARM_NAME}" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "${ALARM_NAME}"; then
            aws cloudwatch delete-alarms --alarm-names "${ALARM_NAME}"
            
            if [[ $? -eq 0 ]]; then
                success "CloudWatch alarm deleted: ${ALARM_NAME}"
            else
                warning "Failed to delete CloudWatch alarm: ${ALARM_NAME}"
            fi
        else
            info "CloudWatch alarm not found: ${ALARM_NAME}"
        fi
    else
        info "No CloudWatch alarm to delete"
    fi
}

# Unsubscribe from SNS topic
unsubscribe_from_sns() {
    if [[ -n "${TOPIC_ARN:-}" ]]; then
        info "Unsubscribing from SNS topic..."
        
        # Get all subscriptions for the topic
        SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
            --topic-arn "${TOPIC_ARN}" \
            --query 'Subscriptions[*].SubscriptionArn' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${SUBSCRIPTIONS}" ]]; then
            for SUB_ARN in ${SUBSCRIPTIONS}; do
                if [[ "${SUB_ARN}" != "None" && "${SUB_ARN}" != "PendingConfirmation" ]]; then
                    info "Unsubscribing: ${SUB_ARN}"
                    aws sns unsubscribe --subscription-arn "${SUB_ARN}" || {
                        warning "Failed to unsubscribe: ${SUB_ARN}"
                    }
                fi
            done
            success "SNS subscriptions removed"
        else
            info "No SNS subscriptions to remove"
        fi
    fi
}

# Delete SNS topic
delete_sns_topic() {
    if [[ -n "${TOPIC_ARN:-}" ]]; then
        info "Deleting SNS topic: ${TOPIC_ARN}"
        
        # Check if topic exists
        if aws sns get-topic-attributes --topic-arn "${TOPIC_ARN}" &>/dev/null; then
            aws sns delete-topic --topic-arn "${TOPIC_ARN}"
            
            if [[ $? -eq 0 ]]; then
                success "SNS topic deleted: ${TOPIC_ARN}"
            else
                warning "Failed to delete SNS topic: ${TOPIC_ARN}"
            fi
        else
            info "SNS topic not found: ${TOPIC_ARN}"
        fi
    else
        info "No SNS topic to delete"
    fi
}

# Terminate EC2 instance
terminate_ec2_instance() {
    if [[ -n "${INSTANCE_ID:-}" ]]; then
        info "Terminating EC2 instance: ${INSTANCE_ID}"
        
        # Check if instance exists and is not already terminated
        INSTANCE_STATE=$(aws ec2 describe-instances \
            --instance-ids "${INSTANCE_ID}" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "not-found")
        
        if [[ "${INSTANCE_STATE}" == "not-found" ]]; then
            info "EC2 instance not found: ${INSTANCE_ID}"
        elif [[ "${INSTANCE_STATE}" == "terminated" ]]; then
            info "EC2 instance already terminated: ${INSTANCE_ID}"
        else
            info "Current instance state: ${INSTANCE_STATE}"
            
            # Terminate the instance
            aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}"
            
            if [[ $? -eq 0 ]]; then
                info "Termination initiated for instance: ${INSTANCE_ID}"
                
                # Wait for termination to complete
                info "Waiting for instance termination..."
                aws ec2 wait instance-terminated --instance-ids "${INSTANCE_ID}" --cli-read-timeout 300 || {
                    warning "Timeout waiting for instance termination, but termination was initiated"
                }
                
                success "EC2 instance terminated: ${INSTANCE_ID}"
            else
                warning "Failed to terminate EC2 instance: ${INSTANCE_ID}"
            fi
        fi
    else
        info "No EC2 instance to terminate"
    fi
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove state file
    if [[ -f "${STATE_FILE}" ]]; then
        rm -f "${STATE_FILE}"
        success "State file removed: ${STATE_FILE}"
    fi
    
    # Keep log files for reference
    info "Log files retained for reference"
}

# Display destruction summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "DESTRUCTION SUMMARY"
    echo "=========================================="
    echo "The following cleanup actions were performed:"
    echo ""
    
    if [[ -n "${COMMAND_ID:-}" ]]; then
        echo "  ✅ SSM Command cancelled (if running)"
    fi
    
    if [[ -n "${ALARM_NAME:-}" ]]; then
        echo "  ✅ CloudWatch Alarm deleted"
    fi
    
    echo "  ✅ SNS Subscriptions removed"
    
    if [[ -n "${TOPIC_ARN:-}" ]]; then
        echo "  ✅ SNS Topic deleted"
    fi
    
    if [[ -n "${INSTANCE_ID:-}" ]]; then
        echo "  ✅ EC2 Instance terminated"
    fi
    
    echo "  ✅ Local state file cleaned up"
    echo ""
    echo "All monitoring resources have been destroyed."
    echo "Log file preserved at: ${LOG_FILE}"
    echo "=========================================="
}

# Main execution flow
main() {
    log "${BLUE}Starting destruction of Simple Resource Monitoring resources${NC}"
    log "Timestamp: ${TIMESTAMP}"
    log "Log file: ${LOG_FILE}"
    
    # Trap to handle interruptions
    trap 'echo ""; warning "Destruction interrupted. Some resources may remain."; exit 1' INT TERM
    
    # Check prerequisites
    if ! check_prerequisites; then
        # If state file doesn't exist, try manual input
        manual_resource_input
    else
        load_state
    fi
    
    # Show confirmation prompt
    confirm_destruction
    
    # Perform cleanup in reverse order of creation
    info "Beginning resource destruction..."
    
    cancel_ssm_command
    delete_cloudwatch_alarm
    unsubscribe_from_sns
    delete_sns_topic
    terminate_ec2_instance
    cleanup_local_files
    
    display_summary
    success "Destruction completed successfully!"
}

# Run main function
main "$@"