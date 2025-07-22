#!/bin/bash

# Deploy script for Basic Monitoring with Amazon CloudWatch Alarms
# This script creates SNS topics, email subscriptions, and CloudWatch alarms
# for monitoring AWS resources

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
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command_exists jq; then
        warning "jq is not installed. Some output formatting may be limited."
    fi
    
    success "Prerequisites check completed"
}

# Function to validate email format
validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        error "Invalid email format: $email"
        exit 1
    fi
}

# Function to generate random suffix
generate_random_suffix() {
    if command_exists aws; then
        aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
        openssl rand -hex 3 2>/dev/null || \
        date +%s | tail -c 7
    else
        openssl rand -hex 3 2>/dev/null || date +%s | tail -c 7
    fi
}

# Function to create SNS topic
create_sns_topic() {
    local topic_name="$1"
    log "Creating SNS topic: $topic_name"
    
    local topic_arn
    topic_arn=$(aws sns create-topic --name "$topic_name" --query TopicArn --output text)
    
    if [[ -z "$topic_arn" ]]; then
        error "Failed to create SNS topic"
        exit 1
    fi
    
    success "SNS topic created: $topic_arn"
    echo "$topic_arn"
}

# Function to create email subscription
create_email_subscription() {
    local topic_arn="$1"
    local email="$2"
    
    log "Creating email subscription for: $email"
    
    aws sns subscribe \
        --topic-arn "$topic_arn" \
        --protocol email \
        --notification-endpoint "$email" >/dev/null
    
    success "Email subscription created for $email"
    warning "Please check your email and confirm the subscription before alarms can send notifications"
}

# Function to create CloudWatch alarm
create_cloudwatch_alarm() {
    local alarm_name="$1"
    local alarm_description="$2"
    local metric_name="$3"
    local namespace="$4"
    local threshold="$5"
    local comparison_operator="$6"
    local evaluation_periods="$7"
    local sns_topic_arn="$8"
    local statistic="${9:-Average}"
    local period="${10:-300}"
    local treat_missing_data="${11:-notBreaching}"
    
    log "Creating CloudWatch alarm: $alarm_name"
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "$alarm_name" \
        --alarm-description "$alarm_description" \
        --metric-name "$metric_name" \
        --namespace "$namespace" \
        --statistic "$statistic" \
        --period "$period" \
        --threshold "$threshold" \
        --comparison-operator "$comparison_operator" \
        --evaluation-periods "$evaluation_periods" \
        --alarm-actions "$sns_topic_arn" \
        --ok-actions "$sns_topic_arn" \
        --treat-missing-data "$treat_missing_data"
    
    success "CloudWatch alarm created: $alarm_name"
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

# Function to cleanup on error
cleanup_on_error() {
    error "Deployment failed. Cleaning up created resources..."
    
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        log "Deleting SNS topic: $SNS_TOPIC_ARN"
        aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" 2>/dev/null || true
    fi
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        log "Deleting any created alarms with suffix: $RANDOM_SUFFIX"
        aws cloudwatch delete-alarms --alarm-names \
            "HighCPUUtilization-${RANDOM_SUFFIX}" \
            "HighResponseTime-${RANDOM_SUFFIX}" \
            "HighDBConnections-${RANDOM_SUFFIX}" 2>/dev/null || true
    fi
    
    exit 1
}

# Trap to cleanup on error
trap cleanup_on_error ERR

# Main deployment function
main() {
    log "Starting deployment of Basic Monitoring with CloudWatch Alarms"
    
    # Check prerequisites
    check_prerequisites
    
    # Get configuration from environment variables or prompt user
    if [[ -z "${NOTIFICATION_EMAIL:-}" ]]; then
        echo -n "Enter your email address for notifications: "
        read -r NOTIFICATION_EMAIL
    fi
    
    validate_email "$NOTIFICATION_EMAIL"
    
    # Set environment variables
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "Notification Email: $NOTIFICATION_EMAIL"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(generate_random_suffix)
    export SNS_TOPIC_NAME="monitoring-alerts-${RANDOM_SUFFIX}"
    
    log "Generated suffix: $RANDOM_SUFFIX"
    log "SNS Topic Name: $SNS_TOPIC_NAME"
    
    # Confirm deployment
    if ! wait_for_confirmation "Do you want to proceed with the deployment?"; then
        log "Deployment cancelled by user"
        exit 0
    fi
    
    # Create SNS topic
    SNS_TOPIC_ARN=$(create_sns_topic "$SNS_TOPIC_NAME")
    export SNS_TOPIC_ARN
    
    # Create email subscription
    create_email_subscription "$SNS_TOPIC_ARN" "$NOTIFICATION_EMAIL"
    
    # Create CloudWatch alarms
    log "Creating CloudWatch alarms..."
    
    # High CPU Utilization alarm
    create_cloudwatch_alarm \
        "HighCPUUtilization-${RANDOM_SUFFIX}" \
        "Triggers when EC2 CPU exceeds 80%" \
        "CPUUtilization" \
        "AWS/EC2" \
        "80" \
        "GreaterThanThreshold" \
        "2" \
        "$SNS_TOPIC_ARN"
    
    # High Response Time alarm
    create_cloudwatch_alarm \
        "HighResponseTime-${RANDOM_SUFFIX}" \
        "Triggers when ALB response time exceeds 1 second" \
        "TargetResponseTime" \
        "AWS/ApplicationELB" \
        "1.0" \
        "GreaterThanThreshold" \
        "3" \
        "$SNS_TOPIC_ARN"
    
    # High Database Connections alarm
    create_cloudwatch_alarm \
        "HighDBConnections-${RANDOM_SUFFIX}" \
        "Triggers when RDS connections exceed 80% of max" \
        "DatabaseConnections" \
        "AWS/RDS" \
        "80" \
        "GreaterThanThreshold" \
        "2" \
        "$SNS_TOPIC_ARN"
    
    # Save configuration for cleanup script
    cat > "deployment-config.sh" << EOF
#!/bin/bash
# Configuration file for cleanup script
export SNS_TOPIC_ARN="$SNS_TOPIC_ARN"
export SNS_TOPIC_NAME="$SNS_TOPIC_NAME"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
export NOTIFICATION_EMAIL="$NOTIFICATION_EMAIL"
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
EOF
    
    success "Deployment completed successfully!"
    echo
    echo "Created resources:"
    echo "- SNS Topic: $SNS_TOPIC_ARN"
    echo "- Email subscription for: $NOTIFICATION_EMAIL"
    echo "- CloudWatch alarms:"
    echo "  - HighCPUUtilization-${RANDOM_SUFFIX}"
    echo "  - HighResponseTime-${RANDOM_SUFFIX}"
    echo "  - HighDBConnections-${RANDOM_SUFFIX}"
    echo
    warning "Don't forget to confirm your email subscription to receive notifications!"
    echo
    echo "To test the alarms, you can manually trigger them using:"
    echo "aws cloudwatch set-alarm-state --alarm-name HighCPUUtilization-${RANDOM_SUFFIX} --state-value ALARM --state-reason 'Testing alarm'"
    echo
    echo "To clean up all resources, run: ./destroy.sh"
}

# Script usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -e, --email EMAIL          Email address for notifications"
    echo "  -y, --yes                  Auto-confirm deployment"
    echo "  -h, --help                 Show this help message"
    echo
    echo "Environment variables:"
    echo "  NOTIFICATION_EMAIL         Email address for notifications"
    echo "  AUTO_CONFIRM               Set to 'true' to skip confirmation prompts"
    echo
    echo "Examples:"
    echo "  $0 -e user@example.com -y"
    echo "  NOTIFICATION_EMAIL=user@example.com $0"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--email)
            NOTIFICATION_EMAIL="$2"
            shift 2
            ;;
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