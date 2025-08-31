#!/bin/bash

# SSL Certificate Monitoring Cleanup Script
# This script removes SSL certificate monitoring resources created by deploy.sh
# Version: 1.0
# Last Updated: 2025-07-12

set -e

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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to load deployment information
load_deployment_info() {
    local info_file="./deployment-info.txt"
    
    if [[ -f "$info_file" ]]; then
        log "Loading deployment information from ${info_file}..."
        
        # Extract resource information from deployment file
        export SNS_TOPIC_NAME=$(grep "SNS Topic Name:" "$info_file" | cut -d' ' -f4)
        export SNS_TOPIC_ARN=$(grep "SNS Topic ARN:" "$info_file" | cut -d' ' -f4-)
        export ALARM_NAME=$(grep "CloudWatch Alarm:" "$info_file" | cut -d' ' -f3)
        export NOTIFICATION_EMAIL=$(grep "Notification Email:" "$info_file" | cut -d' ' -f3)
        
        if [[ -n "$SNS_TOPIC_NAME" && -n "$SNS_TOPIC_ARN" && -n "$ALARM_NAME" ]]; then
            success "Deployment information loaded successfully"
            return 0
        else
            warning "Some deployment information is missing from the file"
        fi
    else
        warning "Deployment info file not found: ${info_file}"
    fi
    
    return 1
}

# Function to discover resources by tags
discover_resources() {
    log "Discovering SSL certificate monitoring resources..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "No default region found, using us-east-1"
    fi
    
    # Find SNS topics with SSL certificate monitoring tags
    local topics
    topics=$(aws sns list-topics --query 'Topics[].TopicArn' --output text)
    
    for topic_arn in $topics; do
        local tags
        tags=$(aws sns list-tags-for-resource --resource-arn "$topic_arn" --query 'Tags[?Key==`Purpose`].Value' --output text 2>/dev/null || echo "")
        
        if [[ "$tags" == "SSLCertificateMonitoring" ]]; then
            export SNS_TOPIC_ARN="$topic_arn"
            export SNS_TOPIC_NAME=$(echo "$topic_arn" | sed 's/.*://')
            log "Found SNS topic: ${SNS_TOPIC_NAME}"
            break
        fi
    done
    
    # Find CloudWatch alarms with SSL certificate monitoring tags
    local alarms
    alarms=$(aws cloudwatch describe-alarms --query 'MetricAlarms[?starts_with(AlarmName, `SSL-`)].AlarmName' --output text)
    
    if [[ -n "$alarms" ]]; then
        export ALARM_NAME=$(echo "$alarms" | tr '\t' '\n' | head -1)
        log "Found CloudWatch alarm: ${ALARM_NAME}"
    fi
}

# Function to confirm deletion
confirm_deletion() {
    echo
    echo "=========================================="
    echo "RESOURCE DELETION CONFIRMATION"
    echo "=========================================="
    echo
    echo "The following resources will be deleted:"
    echo
    
    if [[ -n "$SNS_TOPIC_ARN" ]]; then
        echo "- SNS Topic: ${SNS_TOPIC_NAME}"
        echo "  ARN: ${SNS_TOPIC_ARN}"
    fi
    
    if [[ -n "$ALARM_NAME" ]]; then
        echo "- CloudWatch Alarm: ${ALARM_NAME}"
    fi
    
    # List all SSL-related alarms
    local all_ssl_alarms
    all_ssl_alarms=$(aws cloudwatch describe-alarms --query 'MetricAlarms[?starts_with(AlarmName, `SSL-`)].AlarmName' --output text 2>/dev/null || echo "")
    
    if [[ -n "$all_ssl_alarms" ]]; then
        echo "- All SSL Certificate Alarms:"
        echo "$all_ssl_alarms" | tr '\t' '\n' | sed 's/^/  - /'
    fi
    
    echo
    warning "This action cannot be undone!"
    echo
    echo -n "Are you sure you want to delete these resources? (y/N): "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    success "Deletion confirmed"
}

# Function to delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    # Delete specific alarm if known
    if [[ -n "$ALARM_NAME" ]]; then
        log "Deleting alarm: ${ALARM_NAME}"
        aws cloudwatch delete-alarms --alarm-names "$ALARM_NAME" 2>/dev/null || warning "Failed to delete alarm: ${ALARM_NAME}"
        success "Deleted alarm: ${ALARM_NAME}"
    fi
    
    # Find and delete all SSL certificate monitoring alarms
    local all_ssl_alarms
    all_ssl_alarms=$(aws cloudwatch describe-alarms --query 'MetricAlarms[?starts_with(AlarmName, `SSL-`)].AlarmName' --output text 2>/dev/null || echo "")
    
    if [[ -n "$all_ssl_alarms" ]]; then
        echo "$all_ssl_alarms" | tr '\t' '\n' | while read -r alarm_name; do
            if [[ -n "$alarm_name" ]]; then
                log "Deleting SSL alarm: ${alarm_name}"
                aws cloudwatch delete-alarms --alarm-names "$alarm_name" 2>/dev/null || warning "Failed to delete alarm: ${alarm_name}"
                success "Deleted alarm: ${alarm_name}"
            fi
        done
    fi
    
    # Wait for alarms to be deleted
    sleep 5
    success "CloudWatch alarms deletion completed"
}

# Function to delete SNS subscriptions and topic
delete_sns_resources() {
    log "Deleting SNS resources..."
    
    if [[ -z "$SNS_TOPIC_ARN" ]]; then
        warning "No SNS topic ARN found, skipping SNS cleanup"
        return 0
    fi
    
    # List and delete subscriptions
    local subscriptions
    subscriptions=$(aws sns list-subscriptions-by-topic \
        --topic-arn "$SNS_TOPIC_ARN" \
        --query 'Subscriptions[].SubscriptionArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$subscriptions" ]]; then
        echo "$subscriptions" | tr '\t' '\n' | while read -r subscription_arn; do
            if [[ -n "$subscription_arn" && "$subscription_arn" != "PendingConfirmation" ]]; then
                log "Deleting subscription: ${subscription_arn}"
                aws sns unsubscribe --subscription-arn "$subscription_arn" 2>/dev/null || warning "Failed to delete subscription: ${subscription_arn}"
                success "Deleted subscription: ${subscription_arn}"
            fi
        done
    fi
    
    # Delete SNS topic
    log "Deleting SNS topic: ${SNS_TOPIC_NAME}"
    aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" 2>/dev/null || warning "Failed to delete SNS topic: ${SNS_TOPIC_NAME}"
    success "Deleted SNS topic: ${SNS_TOPIC_NAME}"
}

# Function to verify resource deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local errors=0
    
    # Check if SNS topic still exists
    if [[ -n "$SNS_TOPIC_ARN" ]]; then
        local topic_exists
        topic_exists=$(aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" --query 'Attributes.TopicArn' --output text 2>/dev/null || echo "")
        
        if [[ -n "$topic_exists" ]]; then
            error "SNS topic still exists: ${SNS_TOPIC_NAME}"
            ((errors++))
        else
            success "SNS topic deletion verified: ${SNS_TOPIC_NAME}"
        fi
    fi
    
    # Check if CloudWatch alarms still exist
    if [[ -n "$ALARM_NAME" ]]; then
        local alarm_exists
        alarm_exists=$(aws cloudwatch describe-alarms --alarm-names "$ALARM_NAME" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null || echo "")
        
        if [[ -n "$alarm_exists" && "$alarm_exists" != "None" ]]; then
            error "CloudWatch alarm still exists: ${ALARM_NAME}"
            ((errors++))
        else
            success "CloudWatch alarm deletion verified: ${ALARM_NAME}"
        fi
    fi
    
    # Check for any remaining SSL alarms
    local remaining_alarms
    remaining_alarms=$(aws cloudwatch describe-alarms --query 'MetricAlarms[?starts_with(AlarmName, `SSL-`)].AlarmName' --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_alarms" ]]; then
        warning "Some SSL alarms may still exist:"
        echo "$remaining_alarms" | tr '\t' '\n' | sed 's/^/  - /'
        ((errors++))
    else
        success "All SSL certificate alarms deleted"
    fi
    
    if [[ $errors -eq 0 ]]; then
        success "All resources successfully deleted"
    else
        warning "$errors verification issues found"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "./deployment-info.txt"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            success "Removed file: ${file}"
        fi
    done
    
    # Clean up environment variables
    unset SNS_TOPIC_ARN SNS_TOPIC_NAME ALARM_NAME NOTIFICATION_EMAIL AWS_REGION
    success "Environment variables cleared"
}

# Function to provide cleanup summary
show_cleanup_summary() {
    echo
    echo "=========================================="
    echo "CLEANUP SUMMARY"
    echo "=========================================="
    echo
    echo "Resources that were deleted:"
    echo "- SNS Topic and subscriptions"
    echo "- CloudWatch alarms for SSL certificate monitoring"
    echo "- Local deployment information files"
    echo
    echo "Note: SSL certificates in AWS Certificate Manager were NOT deleted"
    echo "      (these are your actual certificates and should be preserved)"
    echo
    success "SSL Certificate Monitoring cleanup completed successfully!"
    echo
}

# Main cleanup function
main() {
    echo "=========================================="
    echo "SSL Certificate Monitoring Cleanup"
    echo "=========================================="
    echo
    
    # Run cleanup steps
    check_prerequisites
    
    # Try to load deployment info, fall back to resource discovery
    if ! load_deployment_info; then
        log "Attempting to discover resources..."
        discover_resources
    fi
    
    # Check if we found any resources to delete
    if [[ -z "$SNS_TOPIC_ARN" && -z "$ALARM_NAME" ]]; then
        warning "No SSL certificate monitoring resources found to delete"
        echo
        echo "This could mean:"
        echo "1. Resources were already deleted"
        echo "2. Resources were created with different names"
        echo "3. You're running this in a different AWS region"
        echo
        exit 0
    fi
    
    confirm_deletion
    delete_cloudwatch_alarms
    delete_sns_resources
    verify_deletion
    cleanup_local_files
    show_cleanup_summary
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi