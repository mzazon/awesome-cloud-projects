#!/bin/bash

# AWS Chat Notifications with SNS and Chatbot - Cleanup Script
# This script removes all infrastructure created by the deployment script

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
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

# Script header
echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║         AWS Chat Notifications Cleanup Script              ║${NC}"
echo -e "${RED}║                 ⚠️  DESTRUCTIVE OPERATION ⚠️                  ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to show usage
show_usage() {
    echo "Usage: $0 [STATE_FILE]"
    echo ""
    echo "Options:"
    echo "  STATE_FILE    Path to deployment state file (optional)"
    echo "  --help        Show this help message"
    echo "  --force       Skip confirmation prompts"
    echo ""
    echo "Examples:"
    echo "  $0 /tmp/chat-notifications-deployment-abc123.state"
    echo "  $0 --force"
    echo "  $0"
    echo ""
    echo "If no state file is provided, the script will attempt to find resources"
    echo "by searching for common naming patterns."
}

# Parse command line arguments
FORCE_MODE=false
STATE_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_usage
            exit 0
            ;;
        --force)
            FORCE_MODE=true
            shift
            ;;
        -*)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            if [[ -z "$STATE_FILE" ]]; then
                STATE_FILE="$1"
            else
                error "Multiple state files specified"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Check prerequisites
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS CLI is not configured or credentials are invalid."
    echo "Run: aws configure"
    exit 1
fi

success "Prerequisites check completed"

# Load deployment state
if [[ -n "$STATE_FILE" ]]; then
    if [[ -f "$STATE_FILE" ]]; then
        log "Loading deployment state from: $STATE_FILE"
        source "$STATE_FILE"
        success "State file loaded successfully"
    else
        error "State file not found: $STATE_FILE"
        exit 1
    fi
else
    # Try to find the last deployment state file
    LAST_DEPLOYMENT_ENV="/tmp/last-chat-notifications-deployment.env"
    if [[ -f "$LAST_DEPLOYMENT_ENV" ]]; then
        source "$LAST_DEPLOYMENT_ENV"
        if [[ -n "$DEPLOYMENT_STATE_FILE" && -f "$DEPLOYMENT_STATE_FILE" ]]; then
            log "Found last deployment state file: $DEPLOYMENT_STATE_FILE"
            source "$DEPLOYMENT_STATE_FILE"
            STATE_FILE="$DEPLOYMENT_STATE_FILE"
            success "Last deployment state loaded"
        else
            warning "Last deployment state file reference found but file missing"
        fi
    fi
    
    # If no state file found, try interactive discovery
    if [[ -z "$STATE_FILE" ]]; then
        warning "No state file provided. Attempting to discover resources..."
        
        # Set basic environment variables
        export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        if [[ -z "$AWS_REGION" ]]; then
            error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
            exit 1
        fi
        
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
        if [[ -z "$AWS_ACCOUNT_ID" ]]; then
            error "Unable to get AWS Account ID. Check your credentials."
            exit 1
        fi
        
        log "Searching for chat notification resources in ${AWS_REGION}..."
        
        # Try to find SNS topics with team-notifications prefix
        POTENTIAL_TOPICS=$(aws sns list-topics --query "Topics[?contains(TopicArn, 'team-notifications')]" --output text | awk '{print $1}' | cut -d: -f6)
        
        if [[ -n "$POTENTIAL_TOPICS" ]]; then
            echo "Found potential SNS topics:"
            echo "$POTENTIAL_TOPICS" | nl
            
            if [[ ! "$FORCE_MODE" == "true" ]]; then
                echo ""
                read -p "Enter the number of the topic to cleanup (or 'all' for all topics, 'none' to skip): " TOPIC_CHOICE
                
                if [[ "$TOPIC_CHOICE" == "none" ]]; then
                    success "Skipping cleanup as requested"
                    exit 0
                elif [[ "$TOPIC_CHOICE" == "all" ]]; then
                    TOPICS_TO_DELETE="$POTENTIAL_TOPICS"
                else
                    TOPICS_TO_DELETE=$(echo "$POTENTIAL_TOPICS" | sed -n "${TOPIC_CHOICE}p")
                fi
            else
                TOPICS_TO_DELETE="$POTENTIAL_TOPICS"
            fi
        else
            warning "No team-notifications SNS topics found"
            TOPICS_TO_DELETE=""
        fi
    fi
fi

# Display resources to be deleted
echo ""
log "Resources scheduled for deletion:"
echo ""

RESOURCES_FOUND=false

if [[ -n "${SNS_TOPIC_NAME:-}" ]]; then
    echo "📞 SNS Topic: ${SNS_TOPIC_NAME}"
    echo "   ARN: ${SNS_TOPIC_ARN:-arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}}"
    RESOURCES_FOUND=true
fi

if [[ -n "${ALARM_NAME:-}" ]]; then
    echo "⏰ CloudWatch Alarm: ${ALARM_NAME}"
    RESOURCES_FOUND=true
fi

if [[ -n "${CHATBOT_CONFIG_NAME:-}" ]]; then
    echo "🤖 Chatbot Configuration: ${CHATBOT_CONFIG_NAME} (manual cleanup required)"
    RESOURCES_FOUND=true
fi

if [[ -n "${TOPICS_TO_DELETE:-}" ]]; then
    echo "📞 SNS Topics (discovered): "
    echo "$TOPICS_TO_DELETE" | sed 's/^/   - /'
    RESOURCES_FOUND=true
fi

if [[ "$RESOURCES_FOUND" == "false" ]]; then
    warning "No resources found to delete."
    echo ""
    echo "This could mean:"
    echo "  • Resources were already deleted"
    echo "  • Wrong AWS region or account"
    echo "  • State file is corrupted or invalid"
    echo "  • Resources were created outside of the deployment script"
    exit 0
fi

# Confirmation prompt
if [[ ! "$FORCE_MODE" == "true" ]]; then
    echo ""
    echo -e "${RED}⚠️  WARNING: This operation will permanently delete AWS resources!${NC}"
    echo -e "${RED}⚠️  This action cannot be undone!${NC}"
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRMATION
    
    if [[ "$CONFIRMATION" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
fi

echo ""
log "Starting resource cleanup..."

# Function to safely delete CloudWatch alarm
delete_cloudwatch_alarm() {
    local alarm_name=$1
    
    log "Checking if CloudWatch alarm exists: ${alarm_name}"
    
    if aws cloudwatch describe-alarms --alarm-names "${alarm_name}" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "${alarm_name}"; then
        log "Deleting CloudWatch alarm: ${alarm_name}"
        
        if aws cloudwatch delete-alarms --alarm-names "${alarm_name}"; then
            success "CloudWatch alarm deleted: ${alarm_name}"
        else
            error "Failed to delete CloudWatch alarm: ${alarm_name}"
            return 1
        fi
    else
        warning "CloudWatch alarm not found: ${alarm_name}"
    fi
}

# Function to safely delete SNS topic
delete_sns_topic() {
    local topic_name=$1
    local topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${topic_name}"
    
    log "Checking if SNS topic exists: ${topic_name}"
    
    if aws sns get-topic-attributes --topic-arn "${topic_arn}" &>/dev/null; then
        # List and remove subscriptions first
        log "Checking for SNS topic subscriptions..."
        SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic --topic-arn "${topic_arn}" --query 'Subscriptions[].SubscriptionArn' --output text 2>/dev/null || echo "")
        
        if [[ -n "$SUBSCRIPTIONS" && "$SUBSCRIPTIONS" != "None" ]]; then
            log "Found subscriptions, removing them first..."
            echo "$SUBSCRIPTIONS" | while read -r SUB_ARN; do
                if [[ -n "$SUB_ARN" && "$SUB_ARN" != "PendingConfirmation" ]]; then
                    log "Unsubscribing: ${SUB_ARN}"
                    aws sns unsubscribe --subscription-arn "$SUB_ARN" || warning "Failed to unsubscribe: ${SUB_ARN}"
                fi
            done
            
            # Wait a moment for unsubscriptions to process
            sleep 2
        fi
        
        log "Deleting SNS topic: ${topic_name}"
        
        if aws sns delete-topic --topic-arn "${topic_arn}"; then
            success "SNS topic deleted: ${topic_name}"
        else
            error "Failed to delete SNS topic: ${topic_name}"
            return 1
        fi
    else
        warning "SNS topic not found: ${topic_name}"
    fi
}

# Delete CloudWatch alarm first (it references SNS topic)
if [[ -n "${ALARM_NAME:-}" ]]; then
    delete_cloudwatch_alarm "$ALARM_NAME"
else
    # Try to find and delete alarms that reference our topics
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        log "Searching for CloudWatch alarms referencing SNS topic..."
        ALARMS_WITH_TOPIC=$(aws cloudwatch describe-alarms --query "MetricAlarms[?contains(AlarmActions, '${SNS_TOPIC_ARN}')].AlarmName" --output text 2>/dev/null || echo "")
        
        if [[ -n "$ALARMS_WITH_TOPIC" ]]; then
            echo "$ALARMS_WITH_TOPIC" | while read -r ALARM; do
                if [[ -n "$ALARM" ]]; then
                    delete_cloudwatch_alarm "$ALARM"
                fi
            done
        fi
    fi
fi

# Delete SNS topics
if [[ -n "${SNS_TOPIC_NAME:-}" ]]; then
    delete_sns_topic "$SNS_TOPIC_NAME"
fi

# Delete discovered topics
if [[ -n "${TOPICS_TO_DELETE:-}" ]]; then
    echo "$TOPICS_TO_DELETE" | while read -r TOPIC; do
        if [[ -n "$TOPIC" ]]; then
            delete_sns_topic "$TOPIC"
        fi
    done
fi

# Manual cleanup instructions for Chatbot
if [[ -n "${CHATBOT_CONFIG_NAME:-}" ]] || [[ "$RESOURCES_FOUND" == "true" ]]; then
    echo ""
    log "Manual cleanup required for AWS Chatbot..."
    echo ""
    echo -e "${YELLOW}┌─────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│                MANUAL CLEANUP REQUIRED                     │${NC}"
    echo -e "${YELLOW}└─────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo "🔧 AWS Chatbot Configuration Cleanup:"
    echo "1. Go to AWS Chatbot console: https://console.aws.amazon.com/chatbot/"
    echo "2. Select your Slack workspace"
    if [[ -n "${CHATBOT_CONFIG_NAME:-}" ]]; then
        echo "3. Find and delete configuration: ${CHATBOT_CONFIG_NAME}"
    else
        echo "3. Delete any chat notification configurations you created"
    fi
    echo "4. (Optional) Remove AWS Chatbot from your Slack workspace"
    echo ""
fi

# Clean up state files
if [[ -n "$STATE_FILE" && -f "$STATE_FILE" ]]; then
    log "Removing deployment state file: $STATE_FILE"
    rm -f "$STATE_FILE"
    success "State file removed"
fi

# Clean up last deployment reference
LAST_DEPLOYMENT_ENV="/tmp/last-chat-notifications-deployment.env"
if [[ -f "$LAST_DEPLOYMENT_ENV" ]]; then
    log "Removing last deployment reference"
    rm -f "$LAST_DEPLOYMENT_ENV"
    success "Last deployment reference removed"
fi

# Clean up environment variables
log "Cleaning up environment variables..."
unset SNS_TOPIC_NAME SNS_TOPIC_ARN ALARM_NAME CHATBOT_CONFIG_NAME RANDOM_SUFFIX AWS_ACCOUNT_ID 2>/dev/null || true

# Final cleanup summary
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                   CLEANUP COMPLETED                         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "📋 Cleanup Summary:"
echo "   • CloudWatch alarms: Deleted"
echo "   • SNS topics: Deleted"
echo "   • Subscriptions: Removed"
echo "   • State files: Cleaned up"
echo "   • Environment variables: Cleared"
echo ""

if [[ -n "${CHATBOT_CONFIG_NAME:-}" ]] || [[ "$RESOURCES_FOUND" == "true" ]]; then
    echo "⚠️  Manual cleanup still required:"
    echo "   • AWS Chatbot configuration (see instructions above)"
fi

echo ""
success "Chat notifications infrastructure cleanup completed!"

# Check for any remaining resources
log "Performing final resource check..."

REMAINING_TOPICS=$(aws sns list-topics --query "Topics[?contains(TopicArn, 'team-notifications')]" --output text 2>/dev/null | wc -l)
if [[ "$REMAINING_TOPICS" -gt 0 ]]; then
    warning "Found ${REMAINING_TOPICS} remaining team-notifications topics"
    echo "Run with --force to attempt cleanup of all discovered resources"
fi

# Final cost reminder
echo ""
echo "💰 Cost Impact:"
echo "   • No ongoing charges for deleted resources"
echo "   • Check AWS billing console for final usage charges"
echo "   • Consider setting up billing alerts for future deployments"
echo ""

success "Cleanup script completed successfully!"

exit 0