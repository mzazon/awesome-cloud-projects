#!/bin/bash

# =============================================================================
# Deploy Script for Simple Business Notifications with EventBridge Scheduler and SNS
# 
# This script deploys a serverless notification system using:
# - EventBridge Scheduler for precise timing control
# - SNS for reliable message delivery
# - IAM roles and policies for secure access
#
# Prerequisites:
# - AWS CLI v2.x installed and configured
# - Sufficient permissions for EventBridge, SNS, and IAM
# - Valid email address for notifications
# =============================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# -----------------------------------------------------------------------------
# Configuration and Setup
# -----------------------------------------------------------------------------

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Script metadata
readonly SCRIPT_NAME="Simple Business Notifications Deployment"
readonly SCRIPT_VERSION="1.0"
readonly DEPLOYMENT_TAG="BusinessNotifications"

# Default configuration
DEFAULT_REGION="us-east-1"
DEFAULT_TIMEZONE="America/New_York"

# -----------------------------------------------------------------------------
# Prerequisites Check
# -----------------------------------------------------------------------------

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2.x"
        exit 1
    fi
    
    # Check AWS CLI version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d. -f1)
    if [[ "$aws_version" -lt 2 ]]; then
        log_warning "AWS CLI v1.x detected. Consider upgrading to v2.x for better performance"
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure' first"
        exit 1
    fi
    
    # Check required permissions (basic check)
    log_info "Validating AWS permissions..."
    if ! aws sts get-caller-identity > /dev/null; then
        log_error "Unable to validate AWS credentials"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# -----------------------------------------------------------------------------
# Environment Setup
# -----------------------------------------------------------------------------

setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_REGION=${AWS_REGION:-$DEFAULT_REGION}
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set resource names
    export TOPIC_NAME="business-notifications-${random_suffix}"
    export SCHEDULE_GROUP_NAME="business-schedules-${random_suffix}"
    export ROLE_NAME="eventbridge-scheduler-role-${random_suffix}"
    export POLICY_NAME="${ROLE_NAME}-sns-policy"
    
    # Set timezone (can be overridden)
    export TIMEZONE=${TIMEZONE:-$DEFAULT_TIMEZONE}
    
    log_success "Environment configured:"
    log_info "  AWS Region: ${AWS_REGION}"
    log_info "  Account ID: ${AWS_ACCOUNT_ID}"
    log_info "  Topic Name: ${TOPIC_NAME}"
    log_info "  Schedule Group: ${SCHEDULE_GROUP_NAME}"
    log_info "  IAM Role: ${ROLE_NAME}"
    log_info "  Timezone: ${TIMEZONE}"
}

# -----------------------------------------------------------------------------
# Resource Deployment Functions
# -----------------------------------------------------------------------------

create_sns_topic() {
    log_info "Creating SNS topic for business notifications..."
    
    # Create SNS topic
    aws sns create-topic \
        --name "${TOPIC_NAME}" \
        --attributes DisplayName="Business Notifications" \
        --tags Key=Purpose,Value=BusinessNotifications \
               Key=Environment,Value=Production \
               Key=DeployedBy,Value="${SCRIPT_NAME}" \
        --region "${AWS_REGION}"
    
    # Store topic ARN
    export TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${TOPIC_NAME}" \
        --query Attributes.TopicArn --output text)
    
    log_success "SNS topic created: ${TOPIC_ARN}"
}

create_email_subscription() {
    log_info "Setting up email subscription..."
    
    # Prompt for email address if not provided
    if [[ -z "${EMAIL_ADDRESS:-}" ]]; then
        read -p "Enter your email address for notifications: " EMAIL_ADDRESS
    fi
    
    # Validate email format (basic validation)
    if [[ ! "$EMAIL_ADDRESS" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log_error "Invalid email address format"
        exit 1
    fi
    
    # Create email subscription
    aws sns subscribe \
        --topic-arn "${TOPIC_ARN}" \
        --protocol email \
        --notification-endpoint "${EMAIL_ADDRESS}" \
        --region "${AWS_REGION}"
    
    log_success "Email subscription created for ${EMAIL_ADDRESS}"
    log_warning "Please check your email and confirm the subscription to receive notifications"
    
    # Export for cleanup reference
    export EMAIL_ADDRESS
}

create_iam_role() {
    log_info "Creating IAM role for EventBridge Scheduler..."
    
    # Create trust policy
    cat > /tmp/scheduler-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "scheduler.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document file:///tmp/scheduler-trust-policy.json \
        --description "Execution role for EventBridge Scheduler business notifications" \
        --tags Key=Purpose,Value=BusinessNotifications \
               Key=DeployedBy,Value="${SCRIPT_NAME}"
    
    # Store role ARN
    export ROLE_ARN=$(aws iam get-role \
        --role-name "${ROLE_NAME}" \
        --query Role.Arn --output text)
    
    log_success "IAM role created: ${ROLE_ARN}"
    
    # Clean up temporary file
    rm -f /tmp/scheduler-trust-policy.json
}

create_iam_policy() {
    log_info "Creating IAM policy for SNS access..."
    
    # Create IAM policy for SNS publishing
    cat > /tmp/sns-publish-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "${TOPIC_ARN}"
    }
  ]
}
EOF
    
    # Create policy
    aws iam create-policy \
        --policy-name "${POLICY_NAME}" \
        --policy-document file:///tmp/sns-publish-policy.json \
        --description "Policy for EventBridge Scheduler to publish to SNS business notifications topic"
    
    # Store policy ARN
    export POLICY_ARN=$(aws iam list-policies \
        --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" \
        --output text)
    
    # Attach policy to role
    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn "${POLICY_ARN}"
    
    log_success "IAM policy created and attached: ${POLICY_ARN}"
    
    # Clean up temporary file
    rm -f /tmp/sns-publish-policy.json
    
    # Wait for IAM consistency
    log_info "Waiting for IAM role propagation..."
    sleep 10
}

create_schedule_group() {
    log_info "Creating EventBridge Scheduler schedule group..."
    
    aws scheduler create-schedule-group \
        --name "${SCHEDULE_GROUP_NAME}" \
        --tags Purpose=BusinessNotifications,Environment=Production,DeployedBy="${SCRIPT_NAME}"
    
    log_success "Schedule group created: ${SCHEDULE_GROUP_NAME}"
}

create_schedules() {
    log_info "Creating business notification schedules..."
    
    # Daily business report schedule (9 AM on weekdays)
    log_info "Creating daily business report schedule..."
    aws scheduler create-schedule \
        --name "daily-business-report" \
        --group-name "${SCHEDULE_GROUP_NAME}" \
        --schedule-expression "cron(0 9 ? * MON-FRI *)" \
        --schedule-expression-timezone "${TIMEZONE}" \
        --description "Daily business report notification for weekdays at 9 AM" \
        --target "{
          \"Arn\": \"${TOPIC_ARN}\",
          \"RoleArn\": \"${ROLE_ARN}\",
          \"SnsParameters\": {
            \"Subject\": \"Daily Business Report - Ready for Review\",
            \"Message\": \"Good morning! Your daily business report is ready for review. Please check the dashboard for key metrics including sales performance, customer engagement, and operational status. Have a great day!\"
          }
        }" \
        --flexible-time-window "{
          \"Mode\": \"FLEXIBLE\",
          \"MaximumWindowInMinutes\": 15
        }"
    
    # Weekly summary schedule (Monday 8 AM)
    log_info "Creating weekly summary schedule..."
    aws scheduler create-schedule \
        --name "weekly-summary" \
        --group-name "${SCHEDULE_GROUP_NAME}" \
        --schedule-expression "cron(0 8 ? * MON *)" \
        --schedule-expression-timezone "${TIMEZONE}" \
        --description "Weekly business summary notification every Monday at 8 AM" \
        --target "{
          \"Arn\": \"${TOPIC_ARN}\",
          \"RoleArn\": \"${ROLE_ARN}\",
          \"SnsParameters\": {
            \"Subject\": \"Weekly Business Summary - New Week Ahead\",
            \"Message\": \"Good Monday morning! Here is your weekly business summary with key achievements from last week and priorities for the week ahead. Review the quarterly goals progress and upcoming milestones. Let us make this week productive!\"
          }
        }" \
        --flexible-time-window "{
          \"Mode\": \"FLEXIBLE\",
          \"MaximumWindowInMinutes\": 30
        }"
    
    # Monthly reminder schedule (1st of each month at 10 AM)
    log_info "Creating monthly reminder schedule..."
    aws scheduler create-schedule \
        --name "monthly-reminder" \
        --group-name "${SCHEDULE_GROUP_NAME}" \
        --schedule-expression "cron(0 10 1 * ? *)" \
        --schedule-expression-timezone "${TIMEZONE}" \
        --description "Monthly business reminder notification on 1st of each month at 10 AM" \
        --target "{
          \"Arn\": \"${TOPIC_ARN}\",
          \"RoleArn\": \"${ROLE_ARN}\",
          \"SnsParameters\": {
            \"Subject\": \"Monthly Business Reminder - Important Tasks\",
            \"Message\": \"Welcome to a new month! This is your monthly reminder for important business tasks: review financial reports, update quarterly projections, conduct team performance reviews, and assess goal progress. Schedule time for strategic planning and process improvements.\"
          }
        }" \
        --flexible-time-window "{
          \"Mode\": \"OFF\"
        }"
    
    log_success "All business notification schedules created successfully"
}

# -----------------------------------------------------------------------------
# Testing Functions
# -----------------------------------------------------------------------------

test_deployment() {
    log_info "Testing the deployment..."
    
    # Test SNS topic
    log_info "Sending test notification..."
    aws sns publish \
        --topic-arn "${TOPIC_ARN}" \
        --subject "Test Business Notification - Deployment Successful" \
        --message "Congratulations! Your business notification system has been deployed successfully. You should receive scheduled notifications according to your configured schedule. This test confirms that your SNS topic and email subscription are working correctly." \
        --region "${AWS_REGION}"
    
    log_success "Test notification sent. Check your email to confirm delivery."
    
    # Verify schedules
    log_info "Verifying schedules..."
    local schedule_count
    schedule_count=$(aws scheduler list-schedules \
        --group-name "${SCHEDULE_GROUP_NAME}" \
        --query 'length(Schedules)' \
        --output text)
    
    if [[ "$schedule_count" -eq 3 ]]; then
        log_success "All 3 schedules created successfully"
    else
        log_warning "Expected 3 schedules, found ${schedule_count}"
    fi
}

# -----------------------------------------------------------------------------
# Resource Information Display
# -----------------------------------------------------------------------------

display_deployment_info() {
    log_info "=== Deployment Summary ==="
    echo
    echo "🎉 Business Notification System Deployed Successfully!"
    echo
    echo "📧 Email Notifications:"
    echo "   • Address: ${EMAIL_ADDRESS}"
    echo "   • Topic: ${TOPIC_NAME}"
    echo "   • Topic ARN: ${TOPIC_ARN}"
    echo
    echo "⏰ Notification Schedules:"
    echo "   • Daily Report: Weekdays at 9:00 AM ${TIMEZONE}"
    echo "   • Weekly Summary: Mondays at 8:00 AM ${TIMEZONE}"
    echo "   • Monthly Reminder: 1st of each month at 10:00 AM ${TIMEZONE}"
    echo
    echo "🔐 Security:"
    echo "   • IAM Role: ${ROLE_NAME}"
    echo "   • IAM Policy: ${POLICY_NAME}"
    echo
    echo "🏷️ Resource Identifiers (save for cleanup):"
    echo "   • Schedule Group: ${SCHEDULE_GROUP_NAME}"
    echo "   • Region: ${AWS_REGION}"
    echo
    echo "📝 Next Steps:"
    echo "   1. Confirm your email subscription (check your email)"
    echo "   2. Monitor CloudWatch logs for schedule execution"
    echo "   3. Customize schedules as needed for your business"
    echo "   4. Use destroy.sh script when ready to clean up"
    echo
    echo "💰 Estimated Monthly Cost: \$0.01 - \$0.50 (depends on message volume)"
    echo
}

# -----------------------------------------------------------------------------
# Cleanup Function
# -----------------------------------------------------------------------------

cleanup_on_failure() {
    log_error "Deployment failed. Starting cleanup of partially created resources..."
    
    # Call destroy script if it exists
    if [[ -f "./destroy.sh" ]]; then
        log_info "Running cleanup script..."
        bash "./destroy.sh" --force
    else
        log_warning "Cleanup script not found. Manual cleanup may be required."
        log_info "Resources that may need manual cleanup:"
        echo "   • SNS Topic: ${TOPIC_NAME:-'N/A'}"
        echo "   • Schedule Group: ${SCHEDULE_GROUP_NAME:-'N/A'}"
        echo "   • IAM Role: ${ROLE_NAME:-'N/A'}"
    fi
}

# -----------------------------------------------------------------------------
# Main Deployment Function
# -----------------------------------------------------------------------------

main() {
    # Handle script interruption
    trap cleanup_on_failure ERR EXIT
    
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"
    echo "==============================================================================="
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --email)
                EMAIL_ADDRESS="$2"
                shift 2
                ;;
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            --timezone)
                TIMEZONE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --email EMAIL     Email address for notifications"
                echo "  --region REGION   AWS region (default: configured region or us-east-1)"
                echo "  --timezone TZ     Timezone for schedules (default: America/New_York)"
                echo "  --dry-run         Show what would be deployed without creating resources"
                echo "  --help            Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        echo "Would deploy business notification system with:"
        echo "  • SNS topic for notifications"
        echo "  • Email subscription"
        echo "  • EventBridge Scheduler with 3 schedules"
        echo "  • IAM role and policy for secure access"
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_sns_topic
    create_email_subscription
    create_iam_role
    create_iam_policy
    create_schedule_group
    create_schedules
    test_deployment
    
    # Clear the trap since we succeeded
    trap - ERR EXIT
    
    display_deployment_info
    
    log_success "Deployment completed successfully!"
    echo "==============================================================================="
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi