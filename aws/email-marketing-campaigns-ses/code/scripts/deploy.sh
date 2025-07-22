#!/bin/bash

# Deploy Email Marketing Campaigns with Amazon SES
# This script deploys the complete email marketing infrastructure

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    log_warning "Running in DRY-RUN mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY-RUN: Would execute: $cmd"
        log "DRY-RUN: $description"
        return 0
    else
        log "$description"
        eval "$cmd"
        return $?
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions by attempting to list SES identities
    if ! aws sesv2 list-email-identities &> /dev/null; then
        log_error "Insufficient permissions. Please ensure you have SES, S3, SNS, and CloudWatch permissions."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Set AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export BUCKET_NAME="email-marketing-${random_suffix}"
    export CONFIG_SET_NAME="marketing-campaigns-${random_suffix}"
    export SNS_TOPIC_NAME="email-events-${random_suffix}"
    
    # Prompt for sender email and domain
    if [ -z "${SENDER_EMAIL:-}" ]; then
        echo -n "Enter your sender email address: "
        read SENDER_EMAIL
        export SENDER_EMAIL
    fi
    
    if [ -z "${SENDER_DOMAIN:-}" ]; then
        echo -n "Enter your sender domain (e.g., yourdomain.com): "
        read SENDER_DOMAIN
        export SENDER_DOMAIN
    fi
    
    # Validate email and domain format
    if [[ ! "$SENDER_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid email format: $SENDER_EMAIL"
        exit 1
    fi
    
    if [[ ! "$SENDER_DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid domain format: $SENDER_DOMAIN"
        exit 1
    fi
    
    log_success "Environment variables set:"
    log "  AWS_REGION: $AWS_REGION"
    log "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
    log "  BUCKET_NAME: $BUCKET_NAME"
    log "  CONFIG_SET_NAME: $CONFIG_SET_NAME"
    log "  SNS_TOPIC_NAME: $SNS_TOPIC_NAME"
    log "  SENDER_EMAIL: $SENDER_EMAIL"
    log "  SENDER_DOMAIN: $SENDER_DOMAIN"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for templates and subscriber lists..."
    
    local create_cmd="aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}"
    if execute_cmd "$create_cmd" "Creating S3 bucket"; then
        log_success "S3 bucket created: $BUCKET_NAME"
    else
        log_error "Failed to create S3 bucket"
        exit 1
    fi
    
    # Enable versioning for data protection
    local versioning_cmd="aws s3api put-bucket-versioning --bucket ${BUCKET_NAME} --versioning-configuration Status=Enabled"
    execute_cmd "$versioning_cmd" "Enabling S3 bucket versioning"
    
    # Set bucket policy for secure access
    local bucket_policy=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DenyInsecureConnections",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
EOF
    )
    
    echo "$bucket_policy" > /tmp/bucket-policy.json
    local policy_cmd="aws s3api put-bucket-policy --bucket ${BUCKET_NAME} --policy file:///tmp/bucket-policy.json"
    execute_cmd "$policy_cmd" "Setting secure bucket policy"
    
    rm -f /tmp/bucket-policy.json
}

# Function to verify email identities
verify_email_identities() {
    log "Verifying email identities..."
    
    # Verify domain identity
    local domain_cmd="aws sesv2 create-email-identity --email-identity ${SENDER_DOMAIN}"
    if execute_cmd "$domain_cmd" "Verifying domain identity"; then
        log_success "Domain identity verification initiated: $SENDER_DOMAIN"
    else
        log_warning "Domain identity may already exist or verification failed"
    fi
    
    # Verify email identity
    local email_cmd="aws sesv2 create-email-identity --email-identity ${SENDER_EMAIL}"
    if execute_cmd "$email_cmd" "Verifying email identity"; then
        log_success "Email identity verification initiated: $SENDER_EMAIL"
    else
        log_warning "Email identity may already exist or verification failed"
    fi
    
    # Get domain verification details
    if [ "$DRY_RUN" = false ]; then
        log "Retrieving domain verification details..."
        aws sesv2 get-email-identity --email-identity ${SENDER_DOMAIN} \
            --query 'DkimAttributes.Tokens' --output table || true
        
        log_warning "Configure DNS records as shown above to complete verification"
        log_warning "Domain verification typically takes 24-72 hours to complete"
    fi
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic for email event notifications..."
    
    local sns_cmd="aws sns create-topic --name ${SNS_TOPIC_NAME}"
    if execute_cmd "$sns_cmd" "Creating SNS topic"; then
        if [ "$DRY_RUN" = false ]; then
            export SNS_TOPIC_ARN=$(aws sns create-topic --name ${SNS_TOPIC_NAME} --query 'TopicArn' --output text)
            log_success "SNS topic created: $SNS_TOPIC_ARN"
        else
            export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
            log_success "SNS topic would be created: $SNS_TOPIC_ARN"
        fi
    else
        log_error "Failed to create SNS topic"
        exit 1
    fi
    
    # Subscribe email endpoint
    local subscribe_cmd="aws sns subscribe --topic-arn ${SNS_TOPIC_ARN} --protocol email --notification-endpoint ${SENDER_EMAIL}"
    if execute_cmd "$subscribe_cmd" "Subscribing email to SNS topic"; then
        log_success "Email subscription created - check your email to confirm"
    else
        log_warning "Failed to create email subscription"
    fi
}

# Function to create configuration set
create_configuration_set() {
    log "Creating configuration set for campaign tracking..."
    
    local config_set_cmd="aws sesv2 create-configuration-set \
        --configuration-set-name ${CONFIG_SET_NAME} \
        --delivery-options TlsPolicy=Require \
        --reputation-options ReputationMetricsEnabled=true \
        --sending-options SendingEnabled=true \
        --suppression-options SuppressedReasons=BOUNCE,COMPLAINT"
    
    if execute_cmd "$config_set_cmd" "Creating configuration set"; then
        log_success "Configuration set created: $CONFIG_SET_NAME"
    else
        log_error "Failed to create configuration set"
        exit 1
    fi
    
    # Create event destination
    local event_dest_cmd="aws sesv2 create-configuration-set-event-destination \
        --configuration-set-name ${CONFIG_SET_NAME} \
        --event-destination-name 'email-events' \
        --event-destination 'Enabled=true,MatchingEventTypes=bounce,complaint,delivery,send,reject,open,click,renderingFailure,deliveryDelay,subscription,CloudWatchDestination={DefaultDimensionValue=default,DimensionConfigurations=[{DimensionName=MessageTag,DimensionValueSource=messageTag,DefaultDimensionValue=campaign}]},SnsDestination={TopicArn='${SNS_TOPIC_ARN}'}'"
    
    if execute_cmd "$event_dest_cmd" "Creating event destination"; then
        log_success "Event destination created for configuration set"
    else
        log_warning "Failed to create event destination"
    fi
}

# Function to create email templates
create_email_templates() {
    log "Creating email templates for marketing campaigns..."
    
    # Create welcome campaign template
    local welcome_template_cmd="aws sesv2 create-email-template \
        --template-name 'welcome-campaign' \
        --template-content '{
            \"Subject\": \"Welcome to Our Community, {{name}}!\",
            \"Html\": \"<html><body><h2>Welcome {{name}}!</h2><p>Thank you for joining our community. We are excited to have you aboard!</p><p>As a welcome gift, use code <strong>WELCOME10</strong> for 10% off your first purchase.</p><p>Best regards,<br/>The Marketing Team</p><p><a href=\\\"{{unsubscribe_url}}\\\">Unsubscribe</a></p></body></html>\",
            \"Text\": \"Welcome {{name}}! Thank you for joining our community. Use code WELCOME10 for 10% off your first purchase. Unsubscribe: {{unsubscribe_url}}\"
        }'"
    
    if execute_cmd "$welcome_template_cmd" "Creating welcome campaign template"; then
        log_success "Welcome campaign template created"
    else
        log_warning "Failed to create welcome campaign template"
    fi
    
    # Create promotional campaign template
    local promo_template_cmd="aws sesv2 create-email-template \
        --template-name 'product-promotion' \
        --template-content '{
            \"Subject\": \"Exclusive Offer: {{discount}}% Off {{product_name}}\",
            \"Html\": \"<html><body><h2>Special Offer for {{name}}!</h2><p>Get {{discount}}% off our popular {{product_name}}!</p><p>Limited time offer - expires {{expiry_date}}</p><p><a href=\\\"{{product_url}}\\\" style=\\\"background-color: #007bff; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px;\\\">Shop Now</a></p><p>Best regards,<br/>The Marketing Team</p><p><a href=\\\"{{unsubscribe_url}}\\\">Unsubscribe</a></p></body></html>\",
            \"Text\": \"Special Offer for {{name}}! Get {{discount}}% off {{product_name}}. Expires {{expiry_date}}. Shop: {{product_url}} Unsubscribe: {{unsubscribe_url}}\"
        }'"
    
    if execute_cmd "$promo_template_cmd" "Creating promotional campaign template"; then
        log_success "Promotional campaign template created"
    else
        log_warning "Failed to create promotional campaign template"
    fi
}

# Function to create subscriber lists
create_subscriber_lists() {
    log "Creating sample subscriber lists..."
    
    # Create sample subscriber list
    local subscriber_list=$(cat <<'EOF'
[
    {
        "email": "subscriber1@example.com",
        "name": "John Doe",
        "segment": "new_customers",
        "preferences": ["electronics", "books"]
    },
    {
        "email": "subscriber2@example.com", 
        "name": "Jane Smith",
        "segment": "loyal_customers",
        "preferences": ["fashion", "home"]
    },
    {
        "email": "subscriber3@example.com",
        "name": "Bob Johnson",
        "segment": "new_customers", 
        "preferences": ["sports", "electronics"]
    }
]
EOF
    )
    
    echo "$subscriber_list" > /tmp/subscribers.json
    
    # Upload to S3
    local upload_cmd="aws s3 cp /tmp/subscribers.json s3://${BUCKET_NAME}/subscribers/subscribers.json"
    if execute_cmd "$upload_cmd" "Uploading subscriber list to S3"; then
        log_success "Subscriber list uploaded to S3"
    else
        log_error "Failed to upload subscriber list"
        exit 1
    fi
    
    # Create suppression list
    local suppression_cmd="aws s3 cp /dev/null s3://${BUCKET_NAME}/suppression/bounced-emails.txt"
    execute_cmd "$suppression_cmd" "Creating suppression list file"
    
    # Clean up temporary file
    rm -f /tmp/subscribers.json
}

# Function to set up monitoring
setup_monitoring() {
    log "Setting up email analytics and monitoring..."
    
    # Create CloudWatch dashboard
    local dashboard_body=$(cat <<EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/SES", "Send"],
                    ["AWS/SES", "Bounce"],
                    ["AWS/SES", "Complaint"],
                    ["AWS/SES", "Delivery"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Email Campaign Metrics"
            }
        }
    ]
}
EOF
    )
    
    echo "$dashboard_body" > /tmp/dashboard.json
    local dashboard_cmd="aws cloudwatch put-dashboard --dashboard-name 'EmailMarketingDashboard' --dashboard-body file:///tmp/dashboard.json"
    
    if execute_cmd "$dashboard_cmd" "Creating CloudWatch dashboard"; then
        log_success "CloudWatch dashboard created"
    else
        log_warning "Failed to create CloudWatch dashboard"
    fi
    
    # Create bounce rate alarm
    local alarm_cmd="aws cloudwatch put-metric-alarm \
        --alarm-name 'HighBounceRate' \
        --alarm-description 'Alert when bounce rate exceeds 5%' \
        --metric-name Bounce \
        --namespace AWS/SES \
        --statistic Sum \
        --period 3600 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --alarm-actions ${SNS_TOPIC_ARN}"
    
    if execute_cmd "$alarm_cmd" "Creating bounce rate alarm"; then
        log_success "Bounce rate alarm created"
    else
        log_warning "Failed to create bounce rate alarm"
    fi
    
    # Clean up temporary file
    rm -f /tmp/dashboard.json
}

# Function to setup campaign automation
setup_automation() {
    log "Setting up campaign automation..."
    
    # Create EventBridge rule for weekly campaigns
    local event_rule_cmd="aws events put-rule \
        --name 'WeeklyEmailCampaign' \
        --schedule-expression 'rate(7 days)' \
        --description 'Trigger weekly email campaigns'"
    
    if execute_cmd "$event_rule_cmd" "Creating EventBridge rule"; then
        log_success "EventBridge rule created for weekly campaigns"
    else
        log_warning "Failed to create EventBridge rule"
    fi
    
    log_warning "Note: Deploy Lambda function to complete automation setup"
}

# Function to save deployment info
save_deployment_info() {
    log "Saving deployment information..."
    
    local deployment_info=$(cat <<EOF
# Email Marketing Campaign Deployment Information
# Generated on: $(date)

export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export BUCKET_NAME="$BUCKET_NAME"
export CONFIG_SET_NAME="$CONFIG_SET_NAME"
export SNS_TOPIC_NAME="$SNS_TOPIC_NAME"
export SNS_TOPIC_ARN="$SNS_TOPIC_ARN"
export SENDER_EMAIL="$SENDER_EMAIL"
export SENDER_DOMAIN="$SENDER_DOMAIN"

# Resources created:
# - S3 Bucket: $BUCKET_NAME
# - SES Configuration Set: $CONFIG_SET_NAME
# - SNS Topic: $SNS_TOPIC_ARN
# - Email Templates: welcome-campaign, product-promotion
# - CloudWatch Dashboard: EmailMarketingDashboard
# - CloudWatch Alarm: HighBounceRate
# - EventBridge Rule: WeeklyEmailCampaign

# Next steps:
# 1. Complete domain verification by adding DNS records
# 2. Confirm SNS email subscription
# 3. Test email sending with templates
# 4. Deploy Lambda function for automated bounce handling
EOF
    )
    
    echo "$deployment_info" > .deployment_info.sh
    chmod +x .deployment_info.sh
    
    log_success "Deployment information saved to .deployment_info.sh"
}

# Function to run validation tests
run_validation_tests() {
    if [ "$DRY_RUN" = true ]; then
        log "Skipping validation tests in dry-run mode"
        return 0
    fi
    
    log "Running validation tests..."
    
    # Test S3 bucket access
    if aws s3 ls s3://${BUCKET_NAME} &>/dev/null; then
        log_success "S3 bucket accessible"
    else
        log_error "S3 bucket not accessible"
    fi
    
    # Test configuration set
    if aws sesv2 get-configuration-set --configuration-set-name ${CONFIG_SET_NAME} &>/dev/null; then
        log_success "Configuration set accessible"
    else
        log_error "Configuration set not accessible"
    fi
    
    # Test email templates
    if aws sesv2 get-email-template --template-name "welcome-campaign" &>/dev/null; then
        log_success "Welcome campaign template accessible"
    else
        log_error "Welcome campaign template not accessible"
    fi
    
    if aws sesv2 get-email-template --template-name "product-promotion" &>/dev/null; then
        log_success "Product promotion template accessible"
    else
        log_error "Product promotion template not accessible"
    fi
    
    # Test SNS topic
    if aws sns get-topic-attributes --topic-arn ${SNS_TOPIC_ARN} &>/dev/null; then
        log_success "SNS topic accessible"
    else
        log_error "SNS topic not accessible"
    fi
}

# Main deployment function
main() {
    log "Starting Email Marketing Campaign deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Setup environment
    setup_environment
    
    # Create resources
    create_s3_bucket
    verify_email_identities
    create_sns_topic
    create_configuration_set
    create_email_templates
    create_subscriber_lists
    setup_monitoring
    setup_automation
    
    # Save deployment info
    save_deployment_info
    
    # Run validation tests
    run_validation_tests
    
    log_success "Email Marketing Campaign deployment completed successfully!"
    
    # Print next steps
    echo
    log "📋 Next Steps:"
    echo "1. Complete domain verification by adding DNS records shown above"
    echo "2. Confirm SNS email subscription by checking your email"
    echo "3. Test email sending with the created templates"
    echo "4. Deploy Lambda function for automated bounce handling"
    echo "5. Source the deployment info: source .deployment_info.sh"
    echo
    log "💡 Useful commands:"
    echo "- Check domain verification: aws sesv2 get-email-identity --email-identity $SENDER_DOMAIN"
    echo "- List templates: aws sesv2 list-email-templates"
    echo "- View CloudWatch dashboard: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=EmailMarketingDashboard"
    echo
    log "🧹 To clean up resources, run: ./destroy.sh"
}

# Handle script interruption
trap 'log_error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"