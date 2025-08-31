#!/bin/bash

# Budget Monitoring with AWS Budgets and SNS - Deployment Script
# This script deploys the budget monitoring solution with proper error handling and logging

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Cleanup function for temporary files
cleanup() {
    log "Cleaning up temporary files..."
    rm -f budget.json notifications.json
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AWS Budget Monitoring solution with SNS notifications.

OPTIONS:
    -e, --email EMAIL       Email address for notifications (required)
    -b, --budget AMOUNT     Budget amount in USD (default: 100)
    -r, --region REGION     AWS region (uses configured region by default)
    -n, --name NAME         Budget name prefix (auto-generated if not provided)
    -h, --help              Show this help message
    --dry-run               Show what would be deployed without creating resources

EXAMPLES:
    $0 --email admin@company.com
    $0 --email admin@company.com --budget 500 --region us-east-1
    $0 --email admin@company.com --name my-project-budget

EOF
}

# Default values
BUDGET_AMOUNT="100"
DRY_RUN=false
NOTIFICATION_EMAIL=""
BUDGET_NAME_PREFIX=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--email)
            NOTIFICATION_EMAIL="$2"
            shift 2
            ;;
        -b|--budget)
            BUDGET_AMOUNT="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -n|--name)
            BUDGET_NAME_PREFIX="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$NOTIFICATION_EMAIL" ]]; then
    error "Email address is required. Use --email or -e option."
    show_help
    exit 1
fi

# Validate email format
if [[ ! "$NOTIFICATION_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    error "Invalid email format: $NOTIFICATION_EMAIL"
    exit 1
fi

# Validate budget amount
if ! [[ "$BUDGET_AMOUNT" =~ ^[0-9]+(\.[0-9]+)?$ ]] || (( $(echo "$BUDGET_AMOUNT <= 0" | bc -l) )); then
    error "Invalid budget amount: $BUDGET_AMOUNT. Must be a positive number."
    exit 1
fi

log "Starting Budget Monitoring deployment..."

# Check prerequisites
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if jq is installed for JSON processing
if ! command -v jq &> /dev/null; then
    warning "jq is not installed. Some output formatting may be limited."
fi

# Check if bc is installed for numeric calculations
if ! command -v bc &> /dev/null; then
    error "bc (calculator) is not installed. Please install it first."
    exit 1
fi

# Check AWS authentication
log "Verifying AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured or invalid. Please run 'aws configure' first."
    exit 1
fi

# Set environment variables
log "Setting up environment variables..."

export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
if [[ -z "$AWS_REGION" ]]; then
    export AWS_REGION="us-east-1"
    warning "No region configured, using default: us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [[ -z "$AWS_ACCOUNT_ID" ]]; then
    error "Failed to get AWS account ID"
    exit 1
fi

# Generate unique identifier for budget name
if [[ -z "$BUDGET_NAME_PREFIX" ]]; then
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    export BUDGET_NAME="monthly-cost-budget-${RANDOM_SUFFIX}"
else
    export BUDGET_NAME="${BUDGET_NAME_PREFIX}-$(date +%s | tail -c 4)"
fi

export SNS_TOPIC_NAME="budget-alerts-$(echo $BUDGET_NAME | cut -d'-' -f4-)"

log "Configuration:"
log "  AWS Region: $AWS_REGION"
log "  AWS Account ID: $AWS_ACCOUNT_ID"
log "  Budget Name: $BUDGET_NAME"
log "  Budget Amount: \$$BUDGET_AMOUNT USD"
log "  Notification Email: $NOTIFICATION_EMAIL"
log "  SNS Topic: $SNS_TOPIC_NAME"

if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN MODE - No resources will be created"
    success "Dry run completed successfully"
    exit 0
fi

# Confirmation prompt
echo
read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Deployment cancelled by user"
    exit 0
fi

# Step 1: Create SNS Topic for Budget Notifications
log "Step 1: Creating SNS topic for budget notifications..."
SNS_TOPIC_ARN=$(aws sns create-topic \
    --name "${SNS_TOPIC_NAME}" \
    --query 'TopicArn' --output text 2>/dev/null || {
    error "Failed to create SNS topic"
    exit 1
})

if [[ -z "$SNS_TOPIC_ARN" ]]; then
    error "Failed to get SNS topic ARN"
    exit 1
fi

success "Created SNS topic: $SNS_TOPIC_ARN"

# Step 2: Subscribe Email Address to SNS Topic
log "Step 2: Subscribing email address to SNS topic..."
SUBSCRIPTION_ARN=$(aws sns subscribe \
    --topic-arn "${SNS_TOPIC_ARN}" \
    --protocol email \
    --notification-endpoint "${NOTIFICATION_EMAIL}" \
    --query 'SubscriptionArn' --output text 2>/dev/null || {
    error "Failed to create email subscription"
    exit 1
})

success "Email subscription created for: $NOTIFICATION_EMAIL"
warning "Please check your email and confirm the subscription before proceeding!"

# Step 3: Create Budget Configuration JSON File
log "Step 3: Creating budget configuration..."

# Get current month start for budget period
BUDGET_START=$(date -d "$(date +%Y-%m-01)" --iso-8601 2>/dev/null || date -v1d +%Y-%m-%d)
BUDGET_START_EPOCH=$(date -d "${BUDGET_START}" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "${BUDGET_START}" +%s)

# Create budget configuration file
cat > budget.json << EOF
{
    "BudgetName": "${BUDGET_NAME}",
    "BudgetLimit": {
        "Amount": "${BUDGET_AMOUNT}",
        "Unit": "USD"
    },
    "BudgetType": "COST",
    "TimeUnit": "MONTHLY",
    "TimePeriod": {
        "Start": ${BUDGET_START_EPOCH},
        "End": 3706473600
    },
    "CostTypes": {
        "IncludeCredit": true,
        "IncludeDiscount": true,
        "IncludeOtherSubscription": true,
        "IncludeRecurring": true,
        "IncludeRefund": true,
        "IncludeSubscription": true,
        "IncludeSupport": true,
        "IncludeTax": true,
        "IncludeUpfront": true,
        "UseBlended": false
    }
}
EOF

success "Budget configuration created with \$$BUDGET_AMOUNT monthly limit"

# Step 4: Create Notification Configuration for Budget Alerts
log "Step 4: Creating notification configuration..."

cat > notifications.json << EOF
[
    {
        "Notification": {
            "ComparisonOperator": "GREATER_THAN",
            "NotificationType": "ACTUAL",
            "Threshold": 80,
            "ThresholdType": "PERCENTAGE"
        },
        "Subscribers": [
            {
                "Address": "${SNS_TOPIC_ARN}",
                "SubscriptionType": "SNS"
            }
        ]
    },
    {
        "Notification": {
            "ComparisonOperator": "GREATER_THAN",
            "NotificationType": "ACTUAL",
            "Threshold": 100,
            "ThresholdType": "PERCENTAGE"
        },
        "Subscribers": [
            {
                "Address": "${SNS_TOPIC_ARN}",
                "SubscriptionType": "SNS"
            }
        ]
    },
    {
        "Notification": {
            "ComparisonOperator": "GREATER_THAN",
            "NotificationType": "FORECASTED",
            "Threshold": 80,
            "ThresholdType": "PERCENTAGE"
        },
        "Subscribers": [
            {
                "Address": "${SNS_TOPIC_ARN}",
                "SubscriptionType": "SNS"
            }
        ]
    }
]
EOF

success "Notification configuration created with 80% and 100% thresholds"

# Step 5: Create AWS Budget with Notifications
log "Step 5: Creating AWS Budget with notifications..."

# Check if budget already exists
if aws budgets describe-budget \
    --account-id "${AWS_ACCOUNT_ID}" \
    --budget-name "${BUDGET_NAME}" &> /dev/null; then
    warning "Budget ${BUDGET_NAME} already exists. Skipping creation."
else
    aws budgets create-budget \
        --account-id "${AWS_ACCOUNT_ID}" \
        --budget file://budget.json \
        --notifications-with-subscribers file://notifications.json || {
        error "Failed to create budget"
        exit 1
    }
    success "Budget created successfully: $BUDGET_NAME"
fi

# Step 6: Verify Budget Creation and Configuration
log "Step 6: Verifying budget creation..."

aws budgets describe-budget \
    --account-id "${AWS_ACCOUNT_ID}" \
    --budget-name "${BUDGET_NAME}" \
    --query 'Budget.{Name:BudgetName,Limit:BudgetLimit,ActualSpend:CalculatedSpend.ActualSpend,ForecastedSpend:CalculatedSpend.ForecastedSpend}' \
    --output table || {
    error "Failed to verify budget creation"
    exit 1
}

success "Budget verification completed"

# Test SNS notification
log "Testing SNS notification..."
aws sns publish \
    --topic-arn "${SNS_TOPIC_ARN}" \
    --message "Budget monitoring system has been successfully deployed for ${BUDGET_NAME}. You will receive notifications when spending reaches 80% or 100% of your \$${BUDGET_AMOUNT} budget." \
    --subject "Budget Alert System Activated" || {
    warning "Failed to send test notification, but budget is still active"
}

# Save deployment information
cat > deployment_info.txt << EOF
Budget Monitoring Deployment Information
========================================
Deployment Date: $(date)
AWS Region: $AWS_REGION
AWS Account ID: $AWS_ACCOUNT_ID
Budget Name: $BUDGET_NAME
Budget Amount: \$$BUDGET_AMOUNT USD
SNS Topic ARN: $SNS_TOPIC_ARN
Notification Email: $NOTIFICATION_EMAIL

To clean up this deployment, run:
./destroy.sh --budget-name "$BUDGET_NAME" --topic-arn "$SNS_TOPIC_ARN"
EOF

success "Deployment completed successfully!"
log "Deployment information saved to: deployment_info.txt"
log ""
log "Next steps:"
log "1. Check your email ($NOTIFICATION_EMAIL) and confirm the SNS subscription"
log "2. Monitor your AWS costs through the AWS Budgets console"
log "3. You will receive notifications at 80% and 100% of your \$$BUDGET_AMOUNT budget"
log ""
log "To verify the deployment:"
log "  aws budgets describe-budget --account-id $AWS_ACCOUNT_ID --budget-name $BUDGET_NAME"
log ""
log "To clean up resources:"
log "  ./destroy.sh --budget-name \"$BUDGET_NAME\" --topic-arn \"$SNS_TOPIC_ARN\""