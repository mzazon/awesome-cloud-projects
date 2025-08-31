#!/bin/bash

# =============================================================================
# AWS Uptime Monitoring Deployment Script
# Simple Website Uptime Monitoring with Route53 and SNS
# =============================================================================

set -euo pipefail

# Colors for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Default configuration
DEFAULT_WEBSITE_URL="https://example.com"
DEFAULT_ADMIN_EMAIL="admin@example.com"

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR") 
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        *)
            echo "[$timestamp] $level: $message" >> "$LOG_FILE"
            ;;
    esac
}

print_header() {
    echo -e "${BLUE}"
    echo "================================================================================"
    echo "  AWS Uptime Monitoring Deployment Script"
    echo "  Simple Website Uptime Monitoring with Route53 and SNS"
    echo "================================================================================"
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -u, --website-url URL     Website URL to monitor (default: ${DEFAULT_WEBSITE_URL})
    -e, --email EMAIL         Email address for alerts (default: ${DEFAULT_ADMIN_EMAIL})
    -h, --help               Show this help message
    -v, --verbose            Enable verbose logging
    --dry-run                Show what would be deployed without making changes

EXAMPLES:
    $0 --website-url https://mywebsite.com --email admin@mycompany.com
    $0 --dry-run --verbose
    $0 -u https://api.example.com -e devops@example.com

ENVIRONMENT VARIABLES:
    AWS_REGION               AWS region (will be detected if not set)
    WEBSITE_URL              Website URL to monitor
    ADMIN_EMAIL              Email address for alerts
EOF
}

# =============================================================================
# Prerequisites Check Functions
# =============================================================================

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install AWS CLI v2.0 or higher."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "INFO" "AWS CLI version: $aws_version"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Get AWS account and region info
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "${AWS_REGION:-}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            log "ERROR" "AWS region not configured. Please set AWS_REGION or run 'aws configure'."
            exit 1
        fi
    fi
    
    log "INFO" "AWS Account ID: $AWS_ACCOUNT_ID"
    log "INFO" "AWS Region: $AWS_REGION"
    
    # Check required permissions (basic check)
    if ! aws sts get-caller-identity --query 'Arn' --output text | grep -q "arn:aws"; then
        log "ERROR" "Unable to verify AWS permissions. Please ensure you have appropriate IAM permissions."
        exit 1
    fi
    
    log "INFO" "Prerequisites check completed successfully."
}

validate_inputs() {
    log "INFO" "Validating input parameters..."
    
    # Validate website URL
    if [[ ! "$WEBSITE_URL" =~ ^https?:// ]]; then
        log "ERROR" "Invalid website URL: $WEBSITE_URL. Must start with http:// or https://"
        exit 1
    fi
    
    # Validate email format
    if [[ ! "$ADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log "ERROR" "Invalid email format: $ADMIN_EMAIL"
        exit 1
    fi
    
    # Test website accessibility (optional warning)
    if ! curl -s --head --max-time 10 "$WEBSITE_URL" > /dev/null 2>&1; then
        log "WARN" "Website $WEBSITE_URL is not currently accessible. Proceeding anyway..."
    fi
    
    log "INFO" "Input validation completed."
}

# =============================================================================
# State Management Functions
# =============================================================================

save_deployment_state() {
    local key="$1"
    local value="$2"
    
    # Create state file if it doesn't exist
    touch "$STATE_FILE"
    
    # Update or add the key-value pair
    if grep -q "^$key=" "$STATE_FILE" 2>/dev/null; then
        sed -i.bak "s/^$key=.*/$key=$value/" "$STATE_FILE"
        rm -f "${STATE_FILE}.bak"
    else
        echo "$key=$value" >> "$STATE_FILE"
    fi
}

load_deployment_state() {
    local key="$1"
    
    if [[ -f "$STATE_FILE" ]]; then
        grep "^$key=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2- || echo ""
    else
        echo ""
    fi
}

# =============================================================================
# AWS Resource Creation Functions
# =============================================================================

create_sns_topic() {
    log "INFO" "Creating SNS topic for uptime alerts..."
    
    # Check if topic already exists
    local existing_topic_arn
    existing_topic_arn=$(load_deployment_state "TOPIC_ARN")
    
    if [[ -n "$existing_topic_arn" ]]; then
        # Verify the topic still exists
        if aws sns get-topic-attributes --topic-arn "$existing_topic_arn" &> /dev/null; then
            log "INFO" "SNS topic already exists: $existing_topic_arn"
            TOPIC_ARN="$existing_topic_arn"
            return 0
        else
            log "WARN" "Previously created topic no longer exists. Creating new one..."
        fi
    fi
    
    # Create new topic
    TOPIC_ARN=$(aws sns create-topic \
        --name "$TOPIC_NAME" \
        --query 'TopicArn' --output text)
    
    if [[ -z "$TOPIC_ARN" || "$TOPIC_ARN" == "None" ]]; then
        log "ERROR" "Failed to create SNS topic"
        exit 1
    fi
    
    # Add tags
    aws sns tag-resource \
        --resource-arn "$TOPIC_ARN" \
        --tags Key=Purpose,Value=UptimeMonitoring \
               Key=Environment,Value=Production \
               Key=DeployedBy,Value="uptime-monitoring-script" \
               Key=Website,Value="$WEBSITE_URL" || log "WARN" "Failed to add tags to SNS topic"
    
    save_deployment_state "TOPIC_ARN" "$TOPIC_ARN"
    save_deployment_state "TOPIC_NAME" "$TOPIC_NAME"
    
    log "INFO" "SNS topic created successfully: $TOPIC_ARN"
}

subscribe_email_to_topic() {
    log "INFO" "Subscribing email address to SNS topic..."
    
    # Check if subscription already exists
    local existing_subscriptions
    existing_subscriptions=$(aws sns list-subscriptions-by-topic \
        --topic-arn "$TOPIC_ARN" \
        --query "Subscriptions[?Endpoint=='$ADMIN_EMAIL'].SubscriptionArn" \
        --output text)
    
    if [[ -n "$existing_subscriptions" && "$existing_subscriptions" != "None" ]]; then
        log "INFO" "Email subscription already exists for $ADMIN_EMAIL"
        SUBSCRIPTION_ARN="$existing_subscriptions"
        save_deployment_state "SUBSCRIPTION_ARN" "$SUBSCRIPTION_ARN"
        return 0
    fi
    
    # Create subscription
    SUBSCRIPTION_ARN=$(aws sns subscribe \
        --topic-arn "$TOPIC_ARN" \
        --protocol email \
        --notification-endpoint "$ADMIN_EMAIL" \
        --query 'SubscriptionArn' --output text)
    
    if [[ -z "$SUBSCRIPTION_ARN" || "$SUBSCRIPTION_ARN" == "None" ]]; then
        log "ERROR" "Failed to create email subscription"
        exit 1
    fi
    
    save_deployment_state "SUBSCRIPTION_ARN" "$SUBSCRIPTION_ARN"
    save_deployment_state "ADMIN_EMAIL" "$ADMIN_EMAIL"
    
    log "INFO" "Email subscription created: $SUBSCRIPTION_ARN"
    log "WARN" "Please check $ADMIN_EMAIL and confirm the subscription to receive alerts"
}

create_health_check() {
    log "INFO" "Creating Route53 health check..."
    
    # Check if health check already exists
    local existing_health_check_id
    existing_health_check_id=$(load_deployment_state "HEALTH_CHECK_ID")
    
    if [[ -n "$existing_health_check_id" ]]; then
        # Verify the health check still exists
        if aws route53 get-health-check --health-check-id "$existing_health_check_id" &> /dev/null; then
            log "INFO" "Route53 health check already exists: $existing_health_check_id"
            HEALTH_CHECK_ID="$existing_health_check_id"
            return 0
        else
            log "WARN" "Previously created health check no longer exists. Creating new one..."
        fi
    fi
    
    # Extract domain and determine protocol/port
    DOMAIN_NAME=$(echo "$WEBSITE_URL" | sed 's|https\?://||' | sed 's|/.*||')
    
    if [[ "$WEBSITE_URL" == https* ]]; then
        PORT=443
        PROTOCOL="HTTPS"
        ENABLE_SNI="true"
    else
        PORT=80
        PROTOCOL="HTTP"
        ENABLE_SNI="false"
    fi
    
    # Create health check configuration
    local config_file
    config_file=$(mktemp)
    cat > "$config_file" << EOF
{
    "Type": "$PROTOCOL",
    "ResourcePath": "/",
    "FullyQualifiedDomainName": "$DOMAIN_NAME",
    "Port": $PORT,
    "RequestInterval": 30,
    "FailureThreshold": 3,
    "EnableSNI": $ENABLE_SNI
}
EOF
    
    # Create health check
    HEALTH_CHECK_ID=$(aws route53 create-health-check \
        --caller-reference "health-check-$(date +%s)-$$" \
        --health-check-config "file://$config_file" \
        --query 'HealthCheck.Id' --output text)
    
    rm -f "$config_file"
    
    if [[ -z "$HEALTH_CHECK_ID" || "$HEALTH_CHECK_ID" == "None" ]]; then
        log "ERROR" "Failed to create Route53 health check"
        exit 1
    fi
    
    # Add tags to health check
    aws route53 change-tags-for-resource \
        --resource-type healthcheck \
        --resource-id "$HEALTH_CHECK_ID" \
        --add-tags Key=Name,Value="$HEALTH_CHECK_NAME" \
                   Key=Website,Value="$WEBSITE_URL" \
                   Key=Purpose,Value=UptimeMonitoring \
                   Key=Environment,Value=Production \
                   Key=DeployedBy,Value="uptime-monitoring-script" || log "WARN" "Failed to add tags to health check"
    
    save_deployment_state "HEALTH_CHECK_ID" "$HEALTH_CHECK_ID"
    save_deployment_state "HEALTH_CHECK_NAME" "$HEALTH_CHECK_NAME"
    save_deployment_state "DOMAIN_NAME" "$DOMAIN_NAME"
    
    log "INFO" "Route53 health check created successfully: $HEALTH_CHECK_ID"
}

create_cloudwatch_alarms() {
    log "INFO" "Creating CloudWatch alarms..."
    
    # Create downtime alarm
    local downtime_alarm_name="Website-Down-$HEALTH_CHECK_NAME"
    
    if aws cloudwatch describe-alarms --alarm-names "$downtime_alarm_name" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$downtime_alarm_name"; then
        log "INFO" "Downtime alarm already exists: $downtime_alarm_name"
    else
        aws cloudwatch put-metric-alarm \
            --alarm-name "$downtime_alarm_name" \
            --alarm-description "Alert when website $WEBSITE_URL is down" \
            --metric-name HealthCheckStatus \
            --namespace AWS/Route53 \
            --statistic Minimum \
            --period 60 \
            --threshold 1 \
            --comparison-operator LessThanThreshold \
            --evaluation-periods 1 \
            --alarm-actions "$TOPIC_ARN" \
            --ok-actions "$TOPIC_ARN" \
            --dimensions Name=HealthCheckId,Value="$HEALTH_CHECK_ID"
        
        log "INFO" "Downtime alarm created: $downtime_alarm_name"
    fi
    
    # Create recovery alarm
    local recovery_alarm_name="Website-Recovered-$HEALTH_CHECK_NAME"
    
    if aws cloudwatch describe-alarms --alarm-names "$recovery_alarm_name" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$recovery_alarm_name"; then
        log "INFO" "Recovery alarm already exists: $recovery_alarm_name"
    else
        aws cloudwatch put-metric-alarm \
            --alarm-name "$recovery_alarm_name" \
            --alarm-description "Notify when website $WEBSITE_URL recovers" \
            --metric-name HealthCheckStatus \
            --namespace AWS/Route53 \
            --statistic Minimum \
            --period 60 \
            --threshold 1 \
            --comparison-operator GreaterThanOrEqualToThreshold \
            --evaluation-periods 2 \
            --alarm-actions "$TOPIC_ARN" \
            --dimensions Name=HealthCheckId,Value="$HEALTH_CHECK_ID"
        
        log "INFO" "Recovery alarm created: $recovery_alarm_name"
    fi
    
    save_deployment_state "DOWNTIME_ALARM_NAME" "$downtime_alarm_name"
    save_deployment_state "RECOVERY_ALARM_NAME" "$recovery_alarm_name"
}

# =============================================================================
# Validation Functions
# =============================================================================

validate_deployment() {
    log "INFO" "Validating deployment..."
    
    # Check SNS topic
    if ! aws sns get-topic-attributes --topic-arn "$TOPIC_ARN" &> /dev/null; then
        log "ERROR" "SNS topic validation failed"
        return 1
    fi
    
    # Check health check
    if ! aws route53 get-health-check --health-check-id "$HEALTH_CHECK_ID" &> /dev/null; then
        log "ERROR" "Route53 health check validation failed"
        return 1
    fi
    
    # Check CloudWatch alarms
    local downtime_alarm_name
    local recovery_alarm_name
    downtime_alarm_name=$(load_deployment_state "DOWNTIME_ALARM_NAME")
    recovery_alarm_name=$(load_deployment_state "RECOVERY_ALARM_NAME")
    
    if [[ -n "$downtime_alarm_name" ]] && ! aws cloudwatch describe-alarms --alarm-names "$downtime_alarm_name" &> /dev/null; then
        log "ERROR" "Downtime alarm validation failed"
        return 1
    fi
    
    if [[ -n "$recovery_alarm_name" ]] && ! aws cloudwatch describe-alarms --alarm-names "$recovery_alarm_name" &> /dev/null; then
        log "ERROR" "Recovery alarm validation failed"
        return 1
    fi
    
    log "INFO" "Deployment validation completed successfully"
    return 0
}

# =============================================================================
# Main Deployment Logic
# =============================================================================

deploy_monitoring() {
    log "INFO" "Starting uptime monitoring deployment..."
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    TOPIC_NAME="website-uptime-alerts-${RANDOM_SUFFIX}"
    HEALTH_CHECK_NAME="website-health-${RANDOM_SUFFIX}"
    
    # Load existing names if available
    local existing_topic_name
    local existing_health_check_name
    existing_topic_name=$(load_deployment_state "TOPIC_NAME")
    existing_health_check_name=$(load_deployment_state "HEALTH_CHECK_NAME")
    
    if [[ -n "$existing_topic_name" ]]; then
        TOPIC_NAME="$existing_topic_name"
    fi
    
    if [[ -n "$existing_health_check_name" ]]; then
        HEALTH_CHECK_NAME="$existing_health_check_name"
    fi
    
    log "INFO" "Using configuration:"
    log "INFO" "  Website URL: $WEBSITE_URL"
    log "INFO" "  Admin Email: $ADMIN_EMAIL"
    log "INFO" "  Topic Name: $TOPIC_NAME"
    log "INFO" "  Health Check Name: $HEALTH_CHECK_NAME"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "INFO" "DRY RUN: Would deploy monitoring with above configuration"
        return 0
    fi
    
    # Deploy resources
    create_sns_topic
    subscribe_email_to_topic
    create_health_check
    create_cloudwatch_alarms
    
    # Validate deployment
    if validate_deployment; then
        log "INFO" "Uptime monitoring deployment completed successfully!"
        
        echo
        echo -e "${GREEN}=== Deployment Summary ===${NC}"
        echo "SNS Topic ARN: $TOPIC_ARN"
        echo "Health Check ID: $HEALTH_CHECK_ID"
        echo "Website URL: $WEBSITE_URL"
        echo "Alert Email: $ADMIN_EMAIL"
        echo
        echo -e "${YELLOW}IMPORTANT:${NC} Please check your email ($ADMIN_EMAIL) and confirm the SNS subscription to receive alerts."
        echo
    else
        log "ERROR" "Deployment validation failed. Check logs for details."
        exit 1
    fi
}

cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Deployment failed with exit code $exit_code"
        log "INFO" "Check the log file for details: $LOG_FILE"
    fi
    exit $exit_code
}

# =============================================================================
# Main Script Execution
# =============================================================================

main() {
    # Set trap for error handling
    trap cleanup_on_error EXIT
    
    # Initialize logging
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    print_header
    
    # Parse command line arguments
    WEBSITE_URL="${WEBSITE_URL:-$DEFAULT_WEBSITE_URL}"
    ADMIN_EMAIL="${ADMIN_EMAIL:-$DEFAULT_ADMIN_EMAIL}"
    VERBOSE=false
    DRY_RUN=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--website-url)
                WEBSITE_URL="$2"
                shift 2
                ;;
            -e|--email)
                ADMIN_EMAIL="$2"
                shift 2
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Set verbose logging if requested
    if [[ "$VERBOSE" == "true" ]]; then
        set -x
    fi
    
    # Run deployment steps
    check_prerequisites
    validate_inputs
    deploy_monitoring
    
    # Remove trap on successful completion
    trap - EXIT
}

# Run main function with all arguments
main "$@"