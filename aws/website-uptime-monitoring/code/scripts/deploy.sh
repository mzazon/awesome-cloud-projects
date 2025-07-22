#!/bin/bash

# Deploy script for Website Uptime Monitoring with Route 53 Health Checks
# This script automates the deployment of the complete monitoring solution

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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI version 2."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $aws_version"
    
    # Verify required permissions
    log "Verifying AWS permissions..."
    
    # Test Route 53 permissions
    if ! aws route53 list-health-checks --max-items 1 &> /dev/null; then
        error "Missing Route 53 permissions. Please ensure you have route53:* permissions."
    fi
    
    # Test CloudWatch permissions
    if ! aws cloudwatch list-dashboards --max-records 1 &> /dev/null; then
        error "Missing CloudWatch permissions. Please ensure you have cloudwatch:* permissions."
    fi
    
    # Test SNS permissions
    if ! aws sns list-topics &> /dev/null; then
        error "Missing SNS permissions. Please ensure you have sns:* permissions."
    fi
    
    success "Prerequisites check passed"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 6))
    
    # Set default values or prompt for user input
    if [ -z "${WEBSITE_URL:-}" ]; then
        read -p "Enter the website URL to monitor (default: https://httpbin.org/status/200): " input_url
        export WEBSITE_URL="${input_url:-https://httpbin.org/status/200}"
    fi
    
    if [ -z "${MONITOR_EMAIL:-}" ]; then
        read -p "Enter your email address for notifications: " input_email
        if [ -z "$input_email" ]; then
            error "Email address is required for notifications"
        fi
        export MONITOR_EMAIL="$input_email"
    fi
    
    # Create resource names
    export SNS_TOPIC_NAME="website-uptime-alerts-${RANDOM_SUFFIX}"
    export HEALTH_CHECK_NAME="website-uptime-${RANDOM_SUFFIX}"
    export ALARM_NAME="website-down-${RANDOM_SUFFIX}"
    export DASHBOARD_NAME="website-uptime-dashboard-${RANDOM_SUFFIX}"
    
    # Parse URL components for health check
    if [[ "$WEBSITE_URL" =~ ^https://([^/]+)(/.*)? ]]; then
        export HEALTH_CHECK_DOMAIN="${BASH_REMATCH[1]}"
        export HEALTH_CHECK_PATH="${BASH_REMATCH[2]:-/}"
    elif [[ "$WEBSITE_URL" =~ ^http://([^/]+)(/.*)? ]]; then
        export HEALTH_CHECK_DOMAIN="${BASH_REMATCH[1]}"
        export HEALTH_CHECK_PATH="${BASH_REMATCH[2]:-/}"
        export HEALTH_CHECK_PROTOCOL="HTTP"
        export HEALTH_CHECK_PORT="80"
    else
        error "Invalid URL format. Please provide a valid HTTP or HTTPS URL."
    fi
    
    # Set default protocol and port for HTTPS
    export HEALTH_CHECK_PROTOCOL="${HEALTH_CHECK_PROTOCOL:-HTTPS}"
    export HEALTH_CHECK_PORT="${HEALTH_CHECK_PORT:-443}"
    
    log "Environment configured:"
    log "  Website URL: $WEBSITE_URL"
    log "  Domain: $HEALTH_CHECK_DOMAIN"
    log "  Path: $HEALTH_CHECK_PATH"
    log "  Protocol: $HEALTH_CHECK_PROTOCOL"
    log "  Email: $MONITOR_EMAIL"
    log "  AWS Region: $AWS_REGION"
    log "  Resource suffix: $RANDOM_SUFFIX"
}

# Create SNS topic and subscription
create_sns_topic() {
    log "Creating SNS topic for notifications..."
    
    # Create SNS topic
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --query TopicArn --output text)
    
    if [ $? -eq 0 ]; then
        success "SNS topic created: $SNS_TOPIC_ARN"
        echo "$SNS_TOPIC_ARN" > .sns_topic_arn
    else
        error "Failed to create SNS topic"
    fi
    
    # Subscribe email to topic
    log "Creating email subscription..."
    SUBSCRIPTION_ARN=$(aws sns subscribe \
        --topic-arn "$SNS_TOPIC_ARN" \
        --protocol email \
        --notification-endpoint "$MONITOR_EMAIL" \
        --query SubscriptionArn --output text)
    
    if [ $? -eq 0 ]; then
        success "Email subscription created"
        warning "Please check your email and confirm the subscription before proceeding"
        echo "$SUBSCRIPTION_ARN" > .sns_subscription_arn
        
        # Wait for user confirmation
        read -p "Press Enter after confirming your email subscription..."
    else
        error "Failed to create email subscription"
    fi
}

# Create Route 53 health check
create_health_check() {
    log "Creating Route 53 health check..."
    
    # Create health check configuration
    cat > health-check-config.json << EOF
{
    "Type": "$HEALTH_CHECK_PROTOCOL",
    "ResourcePath": "$HEALTH_CHECK_PATH",
    "FullyQualifiedDomainName": "$HEALTH_CHECK_DOMAIN",
    "Port": $HEALTH_CHECK_PORT,
    "RequestInterval": 30,
    "FailureThreshold": 3,
    "MeasureLatency": true,
    "EnableSNI": true
}
EOF
    
    # Create the health check
    HEALTH_CHECK_ID=$(aws route53 create-health-check \
        --caller-reference "uptime-monitor-$(date +%s)" \
        --health-check-config file://health-check-config.json \
        --query HealthCheck.Id --output text)
    
    if [ $? -eq 0 ]; then
        success "Health check created with ID: $HEALTH_CHECK_ID"
        echo "$HEALTH_CHECK_ID" > .health_check_id
    else
        error "Failed to create health check"
    fi
    
    # Add tags to health check
    log "Adding tags to health check..."
    aws route53 change-tags-for-resource \
        --resource-type healthcheck \
        --resource-id "$HEALTH_CHECK_ID" \
        --add-tags \
            Key=Name,Value="$HEALTH_CHECK_NAME" \
            Key=Purpose,Value=UptimeMonitoring \
            Key=Environment,Value=Production \
            Key=Owner,Value=DevOps \
            Key=CreatedBy,Value=AutomatedScript
    
    if [ $? -eq 0 ]; then
        success "Tags added to health check"
    else
        warning "Failed to add tags to health check (health check still functional)"
    fi
}

# Create CloudWatch alarm
create_cloudwatch_alarm() {
    log "Creating CloudWatch alarm..."
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "$ALARM_NAME" \
        --alarm-description "Alert when website $WEBSITE_URL is down" \
        --metric-name HealthCheckStatus \
        --namespace AWS/Route53 \
        --statistic Minimum \
        --period 60 \
        --threshold 1 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --ok-actions "$SNS_TOPIC_ARN" \
        --dimensions Name=HealthCheckId,Value="$HEALTH_CHECK_ID"
    
    if [ $? -eq 0 ]; then
        success "CloudWatch alarm created: $ALARM_NAME"
        echo "$ALARM_NAME" > .alarm_name
    else
        error "Failed to create CloudWatch alarm"
    fi
}

# Create CloudWatch dashboard
create_dashboard() {
    log "Creating CloudWatch dashboard..."
    
    # Create dashboard configuration
    cat > dashboard-config.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Route53", "HealthCheckStatus", "HealthCheckId", "$HEALTH_CHECK_ID"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "us-east-1",
                "title": "Website Health Status - $HEALTH_CHECK_DOMAIN",
                "yAxis": {
                    "left": {
                        "min": 0,
                        "max": 1
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Route53", "HealthCheckPercentHealthy", "HealthCheckId", "$HEALTH_CHECK_ID"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "us-east-1",
                "title": "Health Check Percentage - $HEALTH_CHECK_DOMAIN",
                "yAxis": {
                    "left": {
                        "min": 0,
                        "max": 100
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Route53", "ConnectionTime", "HealthCheckId", "$HEALTH_CHECK_ID"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "us-east-1",
                "title": "Connection Time - $HEALTH_CHECK_DOMAIN"
            }
        }
    ]
}
EOF
    
    # Create the dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "$DASHBOARD_NAME" \
        --dashboard-body file://dashboard-config.json
    
    if [ $? -eq 0 ]; then
        success "CloudWatch dashboard created: $DASHBOARD_NAME"
        echo "$DASHBOARD_NAME" > .dashboard_name
    else
        warning "Failed to create CloudWatch dashboard (monitoring still functional)"
    fi
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Wait for health check to initialize
    log "Waiting for health check to initialize (this may take 2-3 minutes)..."
    sleep 120
    
    # Check health check status
    log "Checking health check status..."
    HEALTH_STATUS=$(aws route53 get-health-check \
        --health-check-id "$HEALTH_CHECK_ID" \
        --query 'HealthCheck.Status.StatusList[0].Status' \
        --output text 2>/dev/null || echo "PENDING")
    
    log "Health check status: $HEALTH_STATUS"
    
    # Test alarm functionality
    log "Testing alarm notification system..."
    aws cloudwatch set-alarm-state \
        --alarm-name "$ALARM_NAME" \
        --state-value ALARM \
        --state-reason "Deployment test - triggering alarm"
    
    sleep 10
    
    aws cloudwatch set-alarm-state \
        --alarm-name "$ALARM_NAME" \
        --state-value OK \
        --state-reason "Deployment test - resetting alarm"
    
    success "Alarm test completed. You should receive email notifications for both ALARM and OK states."
}

# Generate deployment summary
generate_summary() {
    log "Generating deployment summary..."
    
    cat > deployment-summary.txt << EOF
Website Uptime Monitoring Deployment Summary
============================================

Deployment Date: $(date)
Website URL: $WEBSITE_URL
Notification Email: $MONITOR_EMAIL

Resources Created:
- SNS Topic: $SNS_TOPIC_NAME ($SNS_TOPIC_ARN)
- Health Check: $HEALTH_CHECK_NAME ($HEALTH_CHECK_ID)
- CloudWatch Alarm: $ALARM_NAME
- CloudWatch Dashboard: $DASHBOARD_NAME

URLs:
- Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=$DASHBOARD_NAME
- Health Check: https://console.aws.amazon.com/route53/healthchecks/home#/details/$HEALTH_CHECK_ID
- SNS Topic: https://console.aws.amazon.com/sns/v3/home?region=$AWS_REGION#/topic/$SNS_TOPIC_ARN

Configuration Files:
- health-check-config.json
- dashboard-config.json

State Files (for cleanup):
- .sns_topic_arn
- .health_check_id
- .alarm_name
- .dashboard_name

Next Steps:
1. Confirm your email subscription if you haven't already
2. Monitor the dashboard for health check status
3. Test the system by temporarily taking your website offline
4. Consider implementing the challenge enhancements listed in the recipe

To clean up resources, run: ./destroy.sh
EOF

    success "Deployment summary saved to deployment-summary.txt"
}

# Main deployment function
main() {
    log "Starting Website Uptime Monitoring deployment..."
    
    check_prerequisites
    setup_environment
    create_sns_topic
    create_health_check
    create_cloudwatch_alarm
    create_dashboard
    validate_deployment
    generate_summary
    
    success "Deployment completed successfully!"
    success "Your website uptime monitoring is now active."
    success "Dashboard URL: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=$DASHBOARD_NAME"
    
    warning "Don't forget to confirm your email subscription if you haven't already!"
    warning "Keep the state files (.sns_topic_arn, .health_check_id, etc.) for cleanup purposes."
}

# Run main function
main "$@"