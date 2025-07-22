#!/bin/bash

# EC2 Hibernation Cost Optimization - Cleanup Script
# This script removes all resources created for the hibernation demo

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Check if .env file exists
    if [ ! -f ".env" ]; then
        error "Environment file .env not found. Cannot proceed with cleanup."
        error "You may need to manually cleanup resources."
        exit 1
    fi
    
    # Load environment variables
    source .env
    
    # Validate required variables
    if [ -z "$KEY_PAIR_NAME" ] || [ -z "$INSTANCE_NAME" ] || [ -z "$TOPIC_NAME" ]; then
        error "Required environment variables not found in .env file."
        error "You may need to manually cleanup resources."
        exit 1
    fi
    
    log "Environment variables loaded successfully"
    info "AWS Region: ${AWS_REGION}"
    info "Key Pair: ${KEY_PAIR_NAME}"
    info "Instance Name: ${INSTANCE_NAME}"
    info "Topic Name: ${TOPIC_NAME}"
}

# Function to confirm deletion
confirm_deletion() {
    echo
    echo "================================================================"
    echo "                       CLEANUP WARNING                          "
    echo "================================================================"
    echo
    echo "This script will DELETE the following resources:"
    echo "  - EC2 Instance: ${INSTANCE_NAME}"
    echo "  - Key Pair: ${KEY_PAIR_NAME}"
    echo "  - Security Group: ${SECURITY_GROUP_NAME}"
    echo "  - SNS Topic: ${TOPIC_NAME}"
    echo "  - CloudWatch Alarm: ${ALARM_NAME}"
    echo
    echo "This action CANNOT be undone!"
    echo
    read -p "Are you sure you want to proceed? (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Cleanup confirmed. Proceeding with resource deletion..."
}

# Function to delete CloudWatch alarm
delete_cloudwatch_alarm() {
    log "Deleting CloudWatch alarm..."
    
    if [ -z "$ALARM_NAME" ]; then
        warn "Alarm name not set, skipping CloudWatch alarm deletion"
        return 0
    fi
    
    # Check if alarm exists
    if aws cloudwatch describe-alarms --alarm-names "${ALARM_NAME}" >/dev/null 2>&1; then
        aws cloudwatch delete-alarms --alarm-names "${ALARM_NAME}"
        log "CloudWatch alarm deleted successfully: ${ALARM_NAME}"
    else
        warn "CloudWatch alarm not found: ${ALARM_NAME}"
    fi
}

# Function to delete SNS topic
delete_sns_topic() {
    log "Deleting SNS topic..."
    
    if [ -z "$TOPIC_ARN" ]; then
        warn "Topic ARN not set, skipping SNS topic deletion"
        return 0
    fi
    
    # Check if topic exists
    if aws sns get-topic-attributes --topic-arn "${TOPIC_ARN}" >/dev/null 2>&1; then
        aws sns delete-topic --topic-arn "${TOPIC_ARN}"
        log "SNS topic deleted successfully: ${TOPIC_ARN}"
    else
        warn "SNS topic not found: ${TOPIC_ARN}"
    fi
}

# Function to terminate EC2 instance
terminate_instance() {
    log "Terminating EC2 instance..."
    
    if [ -z "$INSTANCE_ID" ]; then
        warn "Instance ID not set, skipping EC2 instance termination"
        return 0
    fi
    
    # Check if instance exists
    if aws ec2 describe-instances --instance-ids "${INSTANCE_ID}" >/dev/null 2>&1; then
        # Get current instance state
        INSTANCE_STATE=$(aws ec2 describe-instances \
            --instance-ids "${INSTANCE_ID}" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text)
        
        info "Current instance state: ${INSTANCE_STATE}"
        
        # If instance is hibernated, start it first
        if [ "$INSTANCE_STATE" == "stopped" ]; then
            info "Instance is stopped, checking if hibernated..."
            
            # Check hibernation state
            STATE_REASON=$(aws ec2 describe-instances \
                --instance-ids "${INSTANCE_ID}" \
                --query 'Reservations[0].Instances[0].StateReason.Code' \
                --output text)
            
            if [ "$STATE_REASON" == "Client.UserInitiatedHibernate" ]; then
                info "Instance is hibernated, starting before termination..."
                aws ec2 start-instances --instance-ids "${INSTANCE_ID}"
                aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"
            fi
        fi
        
        # Terminate instance
        aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}"
        
        # Wait for instance to be terminated
        info "Waiting for instance to be terminated..."
        aws ec2 wait instance-terminated --instance-ids "${INSTANCE_ID}"
        
        log "EC2 instance terminated successfully: ${INSTANCE_ID}"
    else
        warn "EC2 instance not found: ${INSTANCE_ID}"
    fi
}

# Function to delete security group
delete_security_group() {
    log "Deleting security group..."
    
    if [ -z "$SECURITY_GROUP_ID" ]; then
        warn "Security group ID not set, skipping security group deletion"
        return 0
    fi
    
    # Wait a bit for instance termination to complete
    sleep 10
    
    # Check if security group exists
    if aws ec2 describe-security-groups --group-ids "${SECURITY_GROUP_ID}" >/dev/null 2>&1; then
        # Try to delete security group with retries
        for i in {1..5}; do
            if aws ec2 delete-security-group --group-id "${SECURITY_GROUP_ID}" 2>/dev/null; then
                log "Security group deleted successfully: ${SECURITY_GROUP_ID}"
                return 0
            else
                warn "Failed to delete security group (attempt ${i}/5), retrying in 10 seconds..."
                sleep 10
            fi
        done
        
        error "Failed to delete security group after 5 attempts: ${SECURITY_GROUP_ID}"
        error "You may need to manually delete this security group."
    else
        warn "Security group not found: ${SECURITY_GROUP_ID}"
    fi
}

# Function to delete key pair
delete_key_pair() {
    log "Deleting key pair..."
    
    if [ -z "$KEY_PAIR_NAME" ]; then
        warn "Key pair name not set, skipping key pair deletion"
        return 0
    fi
    
    # Check if key pair exists
    if aws ec2 describe-key-pairs --key-names "${KEY_PAIR_NAME}" >/dev/null 2>&1; then
        aws ec2 delete-key-pair --key-name "${KEY_PAIR_NAME}"
        log "Key pair deleted successfully: ${KEY_PAIR_NAME}"
    else
        warn "Key pair not found: ${KEY_PAIR_NAME}"
    fi
    
    # Remove local key file
    if [ -f "${KEY_PAIR_NAME}.pem" ]; then
        rm -f "${KEY_PAIR_NAME}.pem"
        log "Local key file removed: ${KEY_PAIR_NAME}.pem"
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [ -f ".env" ]; then
        rm -f ".env"
        log "Environment file removed: .env"
    fi
    
    # Remove any remaining key files
    for key_file in *.pem; do
        if [ -f "$key_file" ]; then
            rm -f "$key_file"
            log "Removed key file: $key_file"
        fi
    done
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    local cleanup_issues=0
    
    # Check if instance still exists
    if [ -n "$INSTANCE_ID" ] && aws ec2 describe-instances --instance-ids "${INSTANCE_ID}" >/dev/null 2>&1; then
        INSTANCE_STATE=$(aws ec2 describe-instances \
            --instance-ids "${INSTANCE_ID}" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text)
        
        if [ "$INSTANCE_STATE" != "terminated" ]; then
            error "Instance still exists and is not terminated: ${INSTANCE_ID} (${INSTANCE_STATE})"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check if key pair still exists
    if [ -n "$KEY_PAIR_NAME" ] && aws ec2 describe-key-pairs --key-names "${KEY_PAIR_NAME}" >/dev/null 2>&1; then
        error "Key pair still exists: ${KEY_PAIR_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check if security group still exists
    if [ -n "$SECURITY_GROUP_ID" ] && aws ec2 describe-security-groups --group-ids "${SECURITY_GROUP_ID}" >/dev/null 2>&1; then
        error "Security group still exists: ${SECURITY_GROUP_ID}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check if SNS topic still exists
    if [ -n "$TOPIC_ARN" ] && aws sns get-topic-attributes --topic-arn "${TOPIC_ARN}" >/dev/null 2>&1; then
        error "SNS topic still exists: ${TOPIC_ARN}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check if CloudWatch alarm still exists
    if [ -n "$ALARM_NAME" ] && aws cloudwatch describe-alarms --alarm-names "${ALARM_NAME}" >/dev/null 2>&1; then
        error "CloudWatch alarm still exists: ${ALARM_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log "Cleanup validation completed successfully"
    else
        error "Cleanup validation found ${cleanup_issues} issues"
        error "You may need to manually cleanup remaining resources"
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo
    echo "================================================================"
    echo "                   CLEANUP COMPLETED                            "
    echo "================================================================"
    echo
    echo "The following resources have been cleaned up:"
    echo "  ✅ EC2 Instance: ${INSTANCE_NAME}"
    echo "  ✅ Key Pair: ${KEY_PAIR_NAME}"
    echo "  ✅ Security Group: ${SECURITY_GROUP_NAME}"
    echo "  ✅ SNS Topic: ${TOPIC_NAME}"
    echo "  ✅ CloudWatch Alarm: ${ALARM_NAME}"
    echo "  ✅ Local files and environment variables"
    echo
    echo "All resources have been successfully removed."
    echo "================================================================"
}

# Main cleanup function
main() {
    log "Starting EC2 Hibernation Cost Optimization cleanup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Load environment
    load_environment
    
    # Confirm deletion
    confirm_deletion
    
    # Delete CloudWatch alarm
    delete_cloudwatch_alarm
    
    # Delete SNS topic
    delete_sns_topic
    
    # Terminate EC2 instance
    terminate_instance
    
    # Delete security group
    delete_security_group
    
    # Delete key pair
    delete_key_pair
    
    # Cleanup local files
    cleanup_local_files
    
    # Validate cleanup
    validate_cleanup
    
    # Display cleanup summary
    display_cleanup_summary
    
    log "Cleanup completed successfully!"
}

# Trap to handle script exit
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        error "Cleanup failed. Check the logs above for details."
        error "You may need to manually cleanup remaining resources."
        echo
        echo "Manual cleanup commands:"
        echo "  aws ec2 terminate-instances --instance-ids ${INSTANCE_ID}"
        echo "  aws ec2 delete-key-pair --key-name ${KEY_PAIR_NAME}"
        echo "  aws ec2 delete-security-group --group-id ${SECURITY_GROUP_ID}"
        echo "  aws sns delete-topic --topic-arn ${TOPIC_ARN}"
        echo "  aws cloudwatch delete-alarms --alarm-names ${ALARM_NAME}"
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"