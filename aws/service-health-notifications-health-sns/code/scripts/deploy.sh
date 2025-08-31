#!/bin/bash

# AWS Service Health Notifications Deployment Script
# This script creates an automated notification system using AWS Health, EventBridge, and SNS
# for real-time alerts about AWS service health events

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

# Default values
DEFAULT_NOTIFICATION_EMAIL=""
DEFAULT_AWS_REGION=""

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2 and configure credentials."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        error "Please run 'aws configure' to set up your credentials."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION 2.0.0" | tr " " "\n" | sort -V | head -n1) != "2.0.0" ]]; then
        warning "AWS CLI version is less than 2.0.0. Some features may not work as expected."
    fi
    
    success "Prerequisites check completed"
}

# Function to load or prompt for configuration
setup_configuration() {
    log "Setting up configuration..."
    
    # Load existing configuration if available
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        log "Loaded existing configuration from $CONFIG_FILE"
    fi
    
    # Get AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        AWS_REGION=$(aws configure get region 2>/dev/null || echo "")
        if [[ -z "$AWS_REGION" ]]; then
            read -p "Enter AWS region (e.g., us-east-1): " AWS_REGION
            if [[ -z "$AWS_REGION" ]]; then
                error "AWS region is required"
                exit 1
            fi
        fi
    fi
    
    # Get AWS Account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Get notification email
    if [[ -z "${NOTIFICATION_EMAIL:-}" ]]; then
        read -p "Enter email address for notifications: " NOTIFICATION_EMAIL
        if [[ -z "$NOTIFICATION_EMAIL" ]]; then
            error "Email address is required"
            exit 1
        fi
        
        # Basic email validation
        if [[ ! "$NOTIFICATION_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            error "Invalid email format"
            exit 1
        fi
    fi
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    SNS_TOPIC_NAME="aws-health-notifications-${RANDOM_SUFFIX}"
    EVENTBRIDGE_RULE_NAME="aws-health-events-rule-${RANDOM_SUFFIX}"
    ROLE_NAME="HealthNotificationRole-${RANDOM_SUFFIX}"
    
    # Save configuration
    cat > "$CONFIG_FILE" << EOF
# AWS Service Health Notifications Configuration
# Generated on $(date)
AWS_REGION="$AWS_REGION"
AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
NOTIFICATION_EMAIL="$NOTIFICATION_EMAIL"
RANDOM_SUFFIX="$RANDOM_SUFFIX"
SNS_TOPIC_NAME="$SNS_TOPIC_NAME"
EVENTBRIDGE_RULE_NAME="$EVENTBRIDGE_RULE_NAME"
ROLE_NAME="$ROLE_NAME"
EOF
    
    success "Configuration setup completed"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "Notification Email: $NOTIFICATION_EMAIL"
    log "SNS Topic: $SNS_TOPIC_NAME"
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic for health notifications..."
    
    # Create SNS topic
    aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --attributes DisplayName="AWS Health Notifications" \
        --region "$AWS_REGION" &> /dev/null || {
        warning "SNS topic may already exist, continuing..."
    }
    
    # Get topic ARN
    TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" \
        --region "$AWS_REGION" \
        --query 'Attributes.TopicArn' --output text)
    
    # Save topic ARN to config
    echo "TOPIC_ARN=\"$TOPIC_ARN\"" >> "$CONFIG_FILE"
    
    success "SNS topic created: $TOPIC_ARN"
}

# Function to subscribe email to SNS topic
subscribe_email() {
    log "Subscribing email address to SNS topic..."
    
    # Subscribe email to the SNS topic
    SUBSCRIPTION_ARN=$(aws sns subscribe \
        --topic-arn "$TOPIC_ARN" \
        --protocol email \
        --notification-endpoint "$NOTIFICATION_EMAIL" \
        --region "$AWS_REGION" \
        --query 'SubscriptionArn' --output text)
    
    success "Email subscription created for: $NOTIFICATION_EMAIL"
    warning "Please check your email and confirm the subscription!"
    warning "You must click the confirmation link to receive notifications."
    
    # Wait for user acknowledgment
    read -p "Press Enter after confirming your email subscription..."
}

# Function to create IAM role for EventBridge
create_iam_role() {
    log "Creating IAM role for EventBridge..."
    
    # Create trust policy file
    cat > eventbridge-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "events.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file://eventbridge-trust-policy.json &> /dev/null || {
        warning "IAM role may already exist, continuing..."
    }
    
    log "Waiting for IAM role to propagate..."
    sleep 10
    
    # Create SNS publish policy
    cat > sns-publish-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "$TOPIC_ARN"
        }
    ]
}
EOF
    
    # Attach policy to role
    aws iam put-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-name SNSPublishPolicy \
        --policy-document file://sns-publish-policy.json
    
    # Get role ARN
    ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" \
        --query 'Role.Arn' --output text)
    
    # Save role ARN to config
    echo "ROLE_ARN=\"$ROLE_ARN\"" >> "$CONFIG_FILE"
    
    success "IAM role created: $ROLE_ARN"
}

# Function to create EventBridge rule
create_eventbridge_rule() {
    log "Creating EventBridge rule for AWS Health events..."
    
    # Create event pattern file
    cat > health-event-pattern.json << 'EOF'
{
    "source": ["aws.health"],
    "detail-type": ["AWS Health Event"]
}
EOF
    
    # Create EventBridge rule
    aws events put-rule \
        --name "$EVENTBRIDGE_RULE_NAME" \
        --description "Monitor AWS Health events and send SNS notifications" \
        --event-pattern file://health-event-pattern.json \
        --state ENABLED \
        --region "$AWS_REGION" &> /dev/null
    
    success "EventBridge rule created: $EVENTBRIDGE_RULE_NAME"
}

# Function to configure EventBridge target
configure_eventbridge_target() {
    log "Configuring SNS as EventBridge target..."
    
    # Add SNS topic as target for the EventBridge rule
    aws events put-targets \
        --rule "$EVENTBRIDGE_RULE_NAME" \
        --region "$AWS_REGION" \
        --targets "Id"="1","Arn"="$TOPIC_ARN","RoleArn"="$ROLE_ARN" &> /dev/null
    
    success "SNS target configured for EventBridge rule"
}

# Function to configure SNS topic policy
configure_topic_policy() {
    log "Configuring SNS topic policy for EventBridge access..."
    
    # Create topic policy
    cat > topic-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowEventBridgePublish",
            "Effect": "Allow",
            "Principal": {
                "Service": "events.amazonaws.com"
            },
            "Action": "sns:Publish",
            "Resource": "$TOPIC_ARN"
        }
    ]
}
EOF
    
    # Apply the policy to the SNS topic
    aws sns set-topic-attributes \
        --topic-arn "$TOPIC_ARN" \
        --attribute-name Policy \
        --attribute-value file://topic-policy.json \
        --region "$AWS_REGION"
    
    success "SNS topic policy configured for EventBridge access"
}

# Function to test the notification system
test_notification_system() {
    log "Testing the notification system..."
    
    # Send test message
    aws sns publish \
        --topic-arn "$TOPIC_ARN" \
        --subject "Test: AWS Health Notification System" \
        --message "This is a test message to verify your AWS Health notification system is working correctly. If you receive this email, your notification pipeline is operational." \
        --region "$AWS_REGION" &> /dev/null
    
    success "Test notification sent. Check your email inbox within 1-2 minutes."
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove temporary policy files
    rm -f eventbridge-trust-policy.json sns-publish-policy.json \
          health-event-pattern.json topic-policy.json
    
    success "Temporary files cleaned up"
}

# Function to display deployment summary
display_summary() {
    echo
    echo "======================================="
    success "AWS Health Notification System Deployed Successfully!"
    echo "======================================="
    echo
    echo "📋 Deployment Summary:"
    echo "   • SNS Topic: $SNS_TOPIC_NAME"
    echo "   • EventBridge Rule: $EVENTBRIDGE_RULE_NAME"
    echo "   • IAM Role: $ROLE_NAME"
    echo "   • Notification Email: $NOTIFICATION_EMAIL"
    echo "   • AWS Region: $AWS_REGION"
    echo
    echo "📧 Important:"
    echo "   • Make sure you confirmed your email subscription"
    echo "   • You should receive a test email within 1-2 minutes"
    echo "   • The system will now automatically notify you of AWS Health events"
    echo
    echo "🔧 Configuration saved to: $CONFIG_FILE"
    echo "🗑️  To remove all resources, run: ./destroy.sh"
    echo
}

# Main deployment function
main() {
    echo "======================================="
    echo "AWS Service Health Notifications Setup"
    echo "======================================="
    echo
    
    check_prerequisites
    setup_configuration
    create_sns_topic
    subscribe_email
    create_iam_role
    create_eventbridge_rule
    configure_eventbridge_target
    configure_topic_policy
    test_notification_system
    cleanup_temp_files
    display_summary
}

# Error handling
trap 'error "Deployment failed. Check the error messages above."; cleanup_temp_files; exit 1' ERR

# Run main function
main "$@"