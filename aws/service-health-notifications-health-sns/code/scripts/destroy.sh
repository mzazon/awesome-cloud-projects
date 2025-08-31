#!/bin/bash

# AWS Service Health Notifications Cleanup Script
# This script removes all resources created by the deployment script
# including SNS topics, EventBridge rules, IAM roles, and subscriptions

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
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/deploy.config"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check if configuration file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Configuration file not found: $CONFIG_FILE"
        error "This script requires a deployment configuration file."
        error "Please ensure you have run the deploy.sh script first."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to load configuration
load_configuration() {
    log "Loading deployment configuration..."
    
    # Source the configuration file
    source "$CONFIG_FILE"
    
    # Verify required variables are set
    required_vars=(
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
        "SNS_TOPIC_NAME"
        "EVENTBRIDGE_RULE_NAME"
        "ROLE_NAME"
        "TOPIC_ARN"
        "ROLE_ARN"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required configuration variable $var is not set"
            exit 1
        fi
    done
    
    success "Configuration loaded successfully"
    log "AWS Region: $AWS_REGION"
    log "SNS Topic: $SNS_TOPIC_NAME"
    log "EventBridge Rule: $EVENTBRIDGE_RULE_NAME"
    log "IAM Role: $ROLE_NAME"
}

# Function to confirm deletion
confirm_deletion() {
    echo
    warning "This will permanently delete the following AWS resources:"
    echo "   • SNS Topic: $SNS_TOPIC_NAME"
    echo "   • EventBridge Rule: $EVENTBRIDGE_RULE_NAME"
    echo "   • IAM Role: $ROLE_NAME"
    echo "   • All associated subscriptions and policies"
    echo
    warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    log "Proceeding with resource cleanup..."
}

# Function to remove EventBridge rule and targets
remove_eventbridge_rule() {
    log "Removing EventBridge rule and targets..."
    
    # Remove targets from the rule first
    aws events remove-targets \
        --rule "$EVENTBRIDGE_RULE_NAME" \
        --region "$AWS_REGION" \
        --ids "1" 2>/dev/null || {
        warning "EventBridge targets may not exist or already removed"
    }
    
    # Delete the EventBridge rule
    aws events delete-rule \
        --name "$EVENTBRIDGE_RULE_NAME" \
        --region "$AWS_REGION" 2>/dev/null || {
        warning "EventBridge rule may not exist or already removed"
    }
    
    success "EventBridge rule and targets removed"
}

# Function to delete SNS topic
delete_sns_topic() {
    log "Deleting SNS topic and subscriptions..."
    
    # List and display current subscriptions (for logging)
    log "Current subscriptions:"
    aws sns list-subscriptions-by-topic \
        --topic-arn "$TOPIC_ARN" \
        --region "$AWS_REGION" \
        --query 'Subscriptions[].{Protocol:Protocol,Endpoint:Endpoint}' \
        --output table 2>/dev/null || {
        warning "Could not list subscriptions"
    }
    
    # Delete SNS topic (automatically removes all subscriptions)
    aws sns delete-topic \
        --topic-arn "$TOPIC_ARN" \
        --region "$AWS_REGION" 2>/dev/null || {
        warning "SNS topic may not exist or already removed"
    }
    
    success "SNS topic and subscriptions deleted"
}

# Function to remove IAM role and policies
remove_iam_role() {
    log "Removing IAM role and policies..."
    
    # List attached policies (for logging)
    log "Removing inline policies..."
    aws iam list-role-policies \
        --role-name "$ROLE_NAME" \
        --query 'PolicyNames' --output text 2>/dev/null | \
    while read -r policy_name; do
        if [[ -n "$policy_name" && "$policy_name" != "None" ]]; then
            aws iam delete-role-policy \
                --role-name "$ROLE_NAME" \
                --policy-name "$policy_name" 2>/dev/null || {
                warning "Could not delete policy: $policy_name"
            }
            log "Deleted policy: $policy_name"
        fi
    done
    
    # Delete attached managed policies
    log "Removing managed policies..."
    aws iam list-attached-role-policies \
        --role-name "$ROLE_NAME" \
        --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null | \
    while read -r policy_arn; do
        if [[ -n "$policy_arn" && "$policy_arn" != "None" ]]; then
            aws iam detach-role-policy \
                --role-name "$ROLE_NAME" \
                --policy-arn "$policy_arn" 2>/dev/null || {
                warning "Could not detach policy: $policy_arn"
            }
            log "Detached policy: $policy_arn"
        fi
    done
    
    # Wait for policy detachment to propagate
    log "Waiting for policy changes to propagate..."
    sleep 5
    
    # Delete IAM role
    aws iam delete-role \
        --role-name "$ROLE_NAME" 2>/dev/null || {
        warning "IAM role may not exist or already removed"
    }
    
    success "IAM role and policies removed"
}

# Function to verify resource deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local verification_failed=false
    
    # Check SNS topic
    if aws sns get-topic-attributes \
        --topic-arn "$TOPIC_ARN" \
        --region "$AWS_REGION" &>/dev/null; then
        warning "SNS topic still exists: $TOPIC_ARN"
        verification_failed=true
    else
        success "SNS topic successfully deleted"
    fi
    
    # Check EventBridge rule
    if aws events describe-rule \
        --name "$EVENTBRIDGE_RULE_NAME" \
        --region "$AWS_REGION" &>/dev/null; then
        warning "EventBridge rule still exists: $EVENTBRIDGE_RULE_NAME"
        verification_failed=true
    else
        success "EventBridge rule successfully deleted"
    fi
    
    # Check IAM role
    if aws iam get-role \
        --role-name "$ROLE_NAME" &>/dev/null; then
        warning "IAM role still exists: $ROLE_NAME"
        verification_failed=true
    else
        success "IAM role successfully deleted"
    fi
    
    if [[ "$verification_failed" == "true" ]]; then
        warning "Some resources may still exist. Please check the AWS console."
        warning "Resources may take a few minutes to fully propagate deletion."
    else
        success "All resources successfully verified as deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove configuration file
    if [[ -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE"
        success "Configuration file removed: $CONFIG_FILE"
    fi
    
    # Remove any temporary files that might exist
    local temp_files=(
        "eventbridge-trust-policy.json"
        "sns-publish-policy.json"
        "health-event-pattern.json"
        "topic-policy.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "Removed temporary file: $file"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to display cleanup summary
display_summary() {
    echo
    echo "======================================="
    success "AWS Health Notification System Cleanup Complete!"
    echo "======================================="
    echo
    echo "🗑️  Resources Removed:"
    echo "   • SNS Topic: $SNS_TOPIC_NAME"
    echo "   • EventBridge Rule: $EVENTBRIDGE_RULE_NAME"
    echo "   • IAM Role: $ROLE_NAME"
    echo "   • All subscriptions and policies"
    echo "   • Local configuration files"
    echo
    echo "💰 Cost Impact:"
    echo "   • All billable resources have been removed"
    echo "   • No ongoing charges from this deployment"
    echo
    warning "Note: It may take a few minutes for all changes to propagate"
    warning "across AWS services. Some resources may still appear in the"
    warning "console temporarily before being fully removed."
    echo
}

# Function to handle script interruption
cleanup_on_interrupt() {
    echo
    warning "Cleanup interrupted. Some resources may still exist."
    warning "You may need to manually remove remaining resources from the AWS console."
    exit 1
}

# Main cleanup function
main() {
    echo "======================================="
    echo "AWS Service Health Notifications Cleanup"
    echo "======================================="
    echo
    
    check_prerequisites
    load_configuration
    confirm_deletion
    remove_eventbridge_rule
    delete_sns_topic
    remove_iam_role
    verify_deletion
    cleanup_local_files
    display_summary
}

# Error handling
trap 'error "Cleanup failed. Check the error messages above."; exit 1' ERR
trap cleanup_on_interrupt INT TERM

# Run main function
main "$@"