#!/bin/bash

# Destroy script for Basic Monitoring with Amazon CloudWatch Alarms
# This script removes CloudWatch alarms, SNS subscriptions, and SNS topics
# created by the deploy.sh script

set -e  # Exit on any error
set -u  # Exit on undefined variable

# Colors for output
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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to load deployment configuration
load_configuration() {
    local config_file="deployment-config.sh"
    
    if [[ -f "$config_file" ]]; then
        log "Loading configuration from $config_file"
        source "$config_file"
        
        # Validate required variables
        if [[ -z "${SNS_TOPIC_ARN:-}" ]] || [[ -z "${RANDOM_SUFFIX:-}" ]]; then
            error "Configuration file is missing required variables"
            return 1
        fi
        
        success "Configuration loaded successfully"
        return 0
    else
        log "Configuration file not found: $config_file"
        return 1
    fi
}

# Function to prompt for manual configuration
prompt_manual_configuration() {
    log "Manual configuration required"
    
    echo -n "Enter the SNS Topic ARN (or press Enter to skip): "
    read -r SNS_TOPIC_ARN
    
    echo -n "Enter the resource suffix used during deployment (or press Enter to skip): "
    read -r RANDOM_SUFFIX
    
    if [[ -z "$SNS_TOPIC_ARN" ]] && [[ -z "$RANDOM_SUFFIX" ]]; then
        warning "No configuration provided. Will attempt to find and delete all monitoring resources."
        return 1
    fi
    
    export SNS_TOPIC_ARN
    export RANDOM_SUFFIX
    return 0
}

# Function to wait for user confirmation
wait_for_confirmation() {
    local message="$1"
    if [[ "${AUTO_CONFIRM:-false}" == "true" ]]; then
        log "Auto-confirmation enabled, skipping user prompt"
        return 0
    fi
    
    echo -n "$message (y/N): "
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    local alarms_to_delete=()
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        # Delete specific alarms if suffix is known
        alarms_to_delete=(
            "HighCPUUtilization-${RANDOM_SUFFIX}"
            "HighResponseTime-${RANDOM_SUFFIX}"
            "HighDBConnections-${RANDOM_SUFFIX}"
        )
    else
        # Find all monitoring alarms if no suffix is known
        warning "No suffix provided. Searching for all monitoring alarms..."
        
        local existing_alarms
        existing_alarms=$(aws cloudwatch describe-alarms \
            --alarm-name-prefix "High" \
            --query 'MetricAlarms[?starts_with(AlarmName, `HighCPUUtilization-`) || starts_with(AlarmName, `HighResponseTime-`) || starts_with(AlarmName, `HighDBConnections-`)].AlarmName' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$existing_alarms" ]]; then
            # Convert space-separated string to array
            read -ra alarms_to_delete <<< "$existing_alarms"
        fi
    fi
    
    if [[ ${#alarms_to_delete[@]} -eq 0 ]]; then
        log "No CloudWatch alarms found to delete"
        return 0
    fi
    
    # Check which alarms actually exist
    local existing_alarms=()
    for alarm in "${alarms_to_delete[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --query 'MetricAlarms[0].AlarmName' --output text >/dev/null 2>&1; then
            existing_alarms+=("$alarm")
        else
            log "Alarm $alarm does not exist (already deleted or never created)"
        fi
    done
    
    if [[ ${#existing_alarms[@]} -eq 0 ]]; then
        log "No existing CloudWatch alarms found to delete"
        return 0
    fi
    
    log "Found ${#existing_alarms[@]} alarm(s) to delete:"
    for alarm in "${existing_alarms[@]}"; do
        log "  - $alarm"
    done
    
    if ! wait_for_confirmation "Delete these CloudWatch alarms?"; then
        log "Skipping CloudWatch alarms deletion"
        return 0
    fi
    
    # Delete alarms
    aws cloudwatch delete-alarms --alarm-names "${existing_alarms[@]}"
    success "CloudWatch alarms deleted successfully"
}

# Function to delete SNS subscription
delete_sns_subscription() {
    local topic_arn="$1"
    
    log "Deleting SNS subscriptions for topic: $topic_arn"
    
    # Get all subscriptions for the topic
    local subscriptions
    subscriptions=$(aws sns list-subscriptions-by-topic \
        --topic-arn "$topic_arn" \
        --query 'Subscriptions[].SubscriptionArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$subscriptions" ]] || [[ "$subscriptions" == "None" ]]; then
        log "No subscriptions found for topic"
        return 0
    fi
    
    # Delete each subscription
    for subscription_arn in $subscriptions; do
        if [[ "$subscription_arn" != "PendingConfirmation" ]]; then
            log "Deleting subscription: $subscription_arn"
            aws sns unsubscribe --subscription-arn "$subscription_arn"
            success "Subscription deleted: $subscription_arn"
        else
            log "Skipping pending confirmation subscription"
        fi
    done
}

# Function to delete SNS topic
delete_sns_topic() {
    local topic_arn="$1"
    
    if [[ -z "$topic_arn" ]]; then
        log "No SNS topic ARN provided, skipping topic deletion"
        return 0
    fi
    
    log "Deleting SNS topic: $topic_arn"
    
    # Check if topic exists
    if ! aws sns get-topic-attributes --topic-arn "$topic_arn" >/dev/null 2>&1; then
        log "SNS topic does not exist (already deleted or never created)"
        return 0
    fi
    
    # Delete subscriptions first
    delete_sns_subscription "$topic_arn"
    
    # Delete the topic
    aws sns delete-topic --topic-arn "$topic_arn"
    success "SNS topic deleted: $topic_arn"
}

# Function to find and delete SNS topics by name pattern
delete_sns_topics_by_pattern() {
    log "Searching for SNS topics with pattern: monitoring-alerts-*"
    
    local topics
    topics=$(aws sns list-topics \
        --query 'Topics[?contains(TopicArn, `monitoring-alerts-`)].TopicArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$topics" ]]; then
        log "No monitoring SNS topics found"
        return 0
    fi
    
    log "Found monitoring topics:"
    for topic in $topics; do
        log "  - $topic"
    done
    
    if ! wait_for_confirmation "Delete these SNS topics and their subscriptions?"; then
        log "Skipping SNS topics deletion"
        return 0
    fi
    
    # Delete each topic
    for topic in $topics; do
        delete_sns_topic "$topic"
    done
}

# Function to clean up configuration file
cleanup_configuration() {
    local config_file="deployment-config.sh"
    
    if [[ -f "$config_file" ]]; then
        log "Removing configuration file: $config_file"
        rm -f "$config_file"
        success "Configuration file removed"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check for remaining alarms
    local remaining_alarms
    remaining_alarms=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "High" \
        --query 'MetricAlarms[?starts_with(AlarmName, `HighCPUUtilization-`) || starts_with(AlarmName, `HighResponseTime-`) || starts_with(AlarmName, `HighDBConnections-`)].AlarmName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_alarms" ]]; then
        warning "Some CloudWatch alarms may still exist:"
        echo "$remaining_alarms"
    else
        success "No remaining CloudWatch alarms found"
    fi
    
    # Check for remaining monitoring topics
    local remaining_topics
    remaining_topics=$(aws sns list-topics \
        --query 'Topics[?contains(TopicArn, `monitoring-alerts-`)].TopicArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_topics" ]]; then
        warning "Some SNS topics may still exist:"
        echo "$remaining_topics"
    else
        success "No remaining monitoring SNS topics found"
    fi
    
    success "Cleanup verification completed"
}

# Main cleanup function
main() {
    log "Starting cleanup of Basic Monitoring with CloudWatch Alarms"
    
    # Check prerequisites
    check_prerequisites
    
    # Try to load configuration from deployment
    local config_loaded=false
    if load_configuration; then
        config_loaded=true
        log "Using configuration from deployment"
    else
        log "Configuration not available, attempting manual configuration"
        if prompt_manual_configuration; then
            config_loaded=true
        else
            log "Manual configuration not provided, will search for all monitoring resources"
        fi
    fi
    
    # Show what will be deleted
    echo
    log "Resources to be deleted:"
    if [[ "$config_loaded" == "true" ]]; then
        [[ -n "${SNS_TOPIC_ARN:-}" ]] && echo "- SNS Topic: $SNS_TOPIC_ARN"
        [[ -n "${RANDOM_SUFFIX:-}" ]] && echo "- CloudWatch Alarms with suffix: $RANDOM_SUFFIX"
    else
        echo "- All monitoring CloudWatch alarms (HighCPUUtilization-*, HighResponseTime-*, HighDBConnections-*)"
        echo "- All monitoring SNS topics (monitoring-alerts-*)"
    fi
    echo
    
    # Confirm cleanup
    if ! wait_for_confirmation "Do you want to proceed with the cleanup?"; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    # Delete CloudWatch alarms
    delete_cloudwatch_alarms
    
    # Delete SNS resources
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        delete_sns_topic "$SNS_TOPIC_ARN"
    else
        delete_sns_topics_by_pattern
    fi
    
    # Clean up configuration file
    cleanup_configuration
    
    # Verify cleanup
    verify_cleanup
    
    success "Cleanup completed successfully!"
    echo
    log "All monitoring resources have been removed."
    log "You may still receive email notifications for a short time if subscriptions were recently deleted."
}

# Script usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -y, --yes                  Auto-confirm cleanup"
    echo "  -h, --help                 Show this help message"
    echo
    echo "Environment variables:"
    echo "  AUTO_CONFIRM               Set to 'true' to skip confirmation prompts"
    echo
    echo "Examples:"
    echo "  $0 -y"
    echo "  AUTO_CONFIRM=true $0"
    echo
    echo "Note: This script will first try to load configuration from deployment-config.sh"
    echo "      If not found, it will prompt for manual configuration or search for all monitoring resources."
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            AUTO_CONFIRM="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run main function
main "$@"