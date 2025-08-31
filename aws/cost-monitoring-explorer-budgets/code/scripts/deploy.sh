#!/bin/bash

# AWS Cost Monitoring with Cost Explorer and Budgets - Deployment Script
# This script deploys comprehensive cost monitoring using AWS Cost Explorer and Budgets
# with SNS notifications for proactive budget management

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly CONFIG_DIR="${SCRIPT_DIR}/../config"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Cleanup function for error handling
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Deployment failed. Check ${LOG_FILE} for details."
        warn "You may need to manually clean up any partially created resources."
    fi
}

trap cleanup EXIT

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI version 2.x"
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    info "AWS CLI version: ${aws_version}"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check if Cost Explorer is accessible (this also enables it)
    info "Checking Cost Explorer access..."
    local current_date=$(date +%Y-%m-01)
    if ! aws ce get-cost-and-usage \
        --time-period Start=${current_date},End=$(date +%Y-%m-%d) \
        --granularity MONTHLY \
        --metrics BlendedCost \
        --group-by Type=DIMENSION,Key=SERVICE \
        --max-items 1 &> /dev/null; then
        error "Cannot access Cost Explorer. Ensure you have proper billing permissions."
        exit 1
    fi
    
    success "All prerequisites met"
}

# Function to validate environment variables
validate_environment() {
    info "Validating environment configuration..."
    
    # Check required environment variables
    if [ -z "${NOTIFICATION_EMAIL:-}" ]; then
        read -p "Enter notification email address: " NOTIFICATION_EMAIL
        if [ -z "${NOTIFICATION_EMAIL}" ]; then
            error "Notification email is required"
            exit 1
        fi
    fi
    
    # Validate email format
    if [[ ! "${NOTIFICATION_EMAIL}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        error "Invalid email format: ${NOTIFICATION_EMAIL}"
        exit 1
    fi
    
    # Set default budget amount if not provided
    export BUDGET_AMOUNT="${BUDGET_AMOUNT:-100.00}"
    
    # Validate budget amount is numeric
    if ! [[ "${BUDGET_AMOUNT}" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        error "Invalid budget amount: ${BUDGET_AMOUNT}"
        exit 1
    fi
    
    success "Environment configuration validated"
}

# Function to set up environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    # AWS account and region information
    export AWS_REGION=$(aws configure get region)
    if [ -z "${AWS_REGION}" ]; then
        export AWS_REGION="us-east-1"
        warn "No default region configured, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 7))
    
    # Set resource names with unique suffix
    export MONTHLY_BUDGET_NAME="monthly-cost-budget-${random_suffix}"
    export SNS_TOPIC_NAME="budget-alerts-${random_suffix}"
    
    # Set date variables
    export CURRENT_DATE=$(date +%Y-%m-%d)
    export FIRST_OF_MONTH=$(date +%Y-%m-01)
    
    # Create configuration directory
    mkdir -p "${CONFIG_DIR}"
    
    # Save environment variables to file for cleanup script
    cat > "${CONFIG_DIR}/deployment-vars.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
NOTIFICATION_EMAIL=${NOTIFICATION_EMAIL}
BUDGET_AMOUNT=${BUDGET_AMOUNT}
MONTHLY_BUDGET_NAME=${MONTHLY_BUDGET_NAME}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
CURRENT_DATE=${CURRENT_DATE}
FIRST_OF_MONTH=${FIRST_OF_MONTH}
EOF
    
    info "Environment configured:"
    info "  AWS Region: ${AWS_REGION}"
    info "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    info "  Budget Name: ${MONTHLY_BUDGET_NAME}"
    info "  SNS Topic: ${SNS_TOPIC_NAME}"
    info "  Budget Amount: \$${BUDGET_AMOUNT}"
}

# Function to create SNS topic and subscription
create_sns_resources() {
    info "Creating SNS topic for budget notifications..."
    
    # Create SNS topic
    local sns_topic_arn=$(aws sns create-topic \
        --name "${SNS_TOPIC_NAME}" \
        --query TopicArn --output text)
    
    if [ $? -eq 0 ]; then
        success "SNS topic created: ${sns_topic_arn}"
        echo "SNS_TOPIC_ARN=${sns_topic_arn}" >> "${CONFIG_DIR}/deployment-vars.env"
    else
        error "Failed to create SNS topic"
        exit 1
    fi
    
    # Subscribe email to topic
    info "Subscribing email to SNS topic..."
    aws sns subscribe \
        --topic-arn "${sns_topic_arn}" \
        --protocol email \
        --notification-endpoint "${NOTIFICATION_EMAIL}"
    
    if [ $? -eq 0 ]; then
        success "Email subscription created"
        warn "IMPORTANT: Check your email (${NOTIFICATION_EMAIL}) and confirm the SNS subscription"
    else
        error "Failed to create email subscription"
        exit 1
    fi
    
    export SNS_TOPIC_ARN="${sns_topic_arn}"
}

# Function to create budget configuration
create_budget() {
    info "Creating monthly cost budget..."
    
    # Generate budget configuration
    cat > "${CONFIG_DIR}/budget-config.json" << EOF
{
    "BudgetName": "${MONTHLY_BUDGET_NAME}",
    "BudgetLimit": {
        "Amount": "${BUDGET_AMOUNT}",
        "Unit": "USD"
    },
    "TimeUnit": "MONTHLY",
    "TimePeriod": {
        "Start": "${FIRST_OF_MONTH}T00:00:00Z",
        "End": "2087-06-15T00:00:00Z"
    },
    "BudgetType": "COST",
    "CostFilters": {},
    "CostTypes": {
        "IncludeTax": true,
        "IncludeSubscription": true,
        "UseBlended": false,
        "IncludeRefund": false,
        "IncludeCredit": false,
        "IncludeUpfront": true,
        "IncludeRecurring": true,
        "IncludeOtherSubscription": true,
        "IncludeSupport": true,
        "IncludeDiscount": true,
        "UseAmortized": false
    }
}
EOF
    
    # Create the budget
    aws budgets create-budget \
        --account-id "${AWS_ACCOUNT_ID}" \
        --budget "file://${CONFIG_DIR}/budget-config.json"
    
    if [ $? -eq 0 ]; then
        success "Budget created: ${MONTHLY_BUDGET_NAME} (\$${BUDGET_AMOUNT})"
    else
        error "Failed to create budget"
        exit 1
    fi
}

# Function to create budget notifications
create_budget_notifications() {
    info "Creating budget notifications with graduated thresholds..."
    
    # Create notification configurations
    local thresholds=("50" "75" "90")
    
    for threshold in "${thresholds[@]}"; do
        cat > "${CONFIG_DIR}/notification-${threshold}.json" << EOF
{
    "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": ${threshold}.0,
        "ThresholdType": "PERCENTAGE",
        "NotificationState": "ALARM"
    },
    "Subscribers": [
        {
            "SubscriptionType": "SNS",
            "Address": "${SNS_TOPIC_ARN}"
        }
    ]
}
EOF
        
        # Add notification to budget
        aws budgets create-notification \
            --account-id "${AWS_ACCOUNT_ID}" \
            --budget-name "${MONTHLY_BUDGET_NAME}" \
            --cli-input-json "file://${CONFIG_DIR}/notification-${threshold}.json"
        
        if [ $? -eq 0 ]; then
            success "Created ${threshold}% threshold notification"
        else
            error "Failed to create ${threshold}% threshold notification"
            exit 1
        fi
    done
    
    # Create forecasted notification
    info "Creating forecasted budget alert..."
    cat > "${CONFIG_DIR}/notification-forecast.json" << EOF
{
    "Notification": {
        "NotificationType": "FORECASTED",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 100.0,
        "ThresholdType": "PERCENTAGE",
        "NotificationState": "ALARM"
    },
    "Subscribers": [
        {
            "SubscriptionType": "SNS",
            "Address": "${SNS_TOPIC_ARN}"
        }
    ]
}
EOF
    
    aws budgets create-notification \
        --account-id "${AWS_ACCOUNT_ID}" \
        --budget-name "${MONTHLY_BUDGET_NAME}" \
        --cli-input-json "file://${CONFIG_DIR}/notification-forecast.json"
    
    if [ $? -eq 0 ]; then
        success "Created forecasted budget alert (100% threshold)"
    else
        error "Failed to create forecasted budget alert"
        exit 1
    fi
}

# Function to validate deployment
validate_deployment() {
    info "Validating deployment..."
    
    # Check budget exists
    if aws budgets describe-budget \
        --account-id "${AWS_ACCOUNT_ID}" \
        --budget-name "${MONTHLY_BUDGET_NAME}" &> /dev/null; then
        success "Budget validation passed"
    else
        error "Budget validation failed"
        exit 1
    fi
    
    # Check notifications exist
    local notification_count=$(aws budgets describe-notifications-for-budget \
        --account-id "${AWS_ACCOUNT_ID}" \
        --budget-name "${MONTHLY_BUDGET_NAME}" \
        --query 'length(Notifications)' --output text)
    
    if [ "${notification_count}" -eq 4 ]; then
        success "All 4 budget notifications validated"
    else
        warn "Expected 4 notifications, found ${notification_count}"
    fi
    
    # Check SNS topic exists
    if aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}" &> /dev/null; then
        success "SNS topic validation passed"
    else
        error "SNS topic validation failed"
        exit 1
    fi
}

# Function to display deployment summary
display_summary() {
    info "Deployment completed successfully!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Budget Name: ${MONTHLY_BUDGET_NAME}"
    echo "Budget Amount: \$${BUDGET_AMOUNT}"
    echo "SNS Topic: ${SNS_TOPIC_ARN}"
    echo "Notification Email: ${NOTIFICATION_EMAIL}"
    echo
    echo "=== ALERT THRESHOLDS ==="
    echo "• 50% of budget (\$$(echo "${BUDGET_AMOUNT} * 0.5" | bc -l)) - Early warning"
    echo "• 75% of budget (\$$(echo "${BUDGET_AMOUNT} * 0.75" | bc -l)) - Serious concern"
    echo "• 90% of budget (\$$(echo "${BUDGET_AMOUNT} * 0.9" | bc -l)) - Critical alert"
    echo "• 100% forecasted - Predictive alert"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Confirm your email subscription by checking ${NOTIFICATION_EMAIL}"
    echo "2. Monitor your AWS costs through the Cost Explorer console"
    echo "3. Review budget performance in the AWS Budgets console"
    echo
    echo "=== CLEANUP ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo
}

# Main execution function
main() {
    info "Starting AWS Cost Monitoring deployment..."
    info "Log file: ${LOG_FILE}"
    
    check_prerequisites
    validate_environment
    setup_environment
    create_sns_resources
    create_budget
    create_budget_notifications
    validate_deployment
    display_summary
    
    success "AWS Cost Monitoring deployment completed successfully!"
}

# Help function
show_help() {
    cat << EOF
AWS Cost Monitoring Deployment Script

USAGE:
    ${SCRIPT_NAME} [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -e, --email EMAIL       Set notification email address
    -b, --budget AMOUNT     Set budget amount in USD (default: 100.00)
    --dry-run              Show what would be done without making changes

ENVIRONMENT VARIABLES:
    NOTIFICATION_EMAIL      Email address for budget notifications
    BUDGET_AMOUNT          Budget amount in USD (default: 100.00)
    AWS_REGION             AWS region (uses CLI default if not set)

EXAMPLES:
    ${SCRIPT_NAME}
    ${SCRIPT_NAME} --email user@example.com --budget 500.00
    NOTIFICATION_EMAIL=admin@company.com ${SCRIPT_NAME}

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -e|--email)
            export NOTIFICATION_EMAIL="$2"
            shift 2
            ;;
        -b|--budget)
            export BUDGET_AMOUNT="$2"
            shift 2
            ;;
        --dry-run)
            info "Dry-run mode not implemented yet"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"