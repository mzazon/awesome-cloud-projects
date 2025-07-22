#!/bin/bash

# AWS Budget Alerts and Automated Actions - Deployment Script
# This script creates a comprehensive budget monitoring system with automated actions
# Version: 1.0
# Last Updated: 2025-07-12

set -e

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Cleanup function for script interruption
cleanup() {
    warning "Script interrupted. Cleaning up temporary files..."
    rm -f /tmp/lambda-trust-policy.json
    rm -f /tmp/budget-action-policy.json
    rm -f /tmp/budget-config.json
    rm -f /tmp/budget-notifications.json
    rm -f /tmp/budget-restriction-policy.json
    rm -f /tmp/budget-service-trust-policy.json
    rm -f /tmp/budget-action-function.py
    rm -f /tmp/budget-action-function.zip
    exit 1
}

trap cleanup INT TERM

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: ${AWS_CLI_VERSION}"
    
    # Check if authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not authenticated. Please run 'aws configure' or set up credentials."
    fi
    
    # Check required permissions
    log "Verifying AWS permissions..."
    CALLER_IDENTITY=$(aws sts get-caller-identity)
    log "Authenticated as: $(echo $CALLER_IDENTITY | jq -r '.Arn // .UserId')"
    
    # Check if zip command is available
    if ! command -v zip &> /dev/null; then
        error "zip command is not available. Please install zip utility."
    fi
    
    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. JSON output will not be formatted."
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No default region found. Using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Prompt for email if not provided
    if [ -z "$BUDGET_EMAIL" ]; then
        read -p "Enter email address for budget notifications: " BUDGET_EMAIL
        export BUDGET_EMAIL
    fi
    
    # Validate email format
    if [[ ! "$BUDGET_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        error "Invalid email format: $BUDGET_EMAIL"
    fi
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export BUDGET_NAME="cost-control-budget-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="budget-alerts-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="budget-action-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="budget-lambda-role-${RANDOM_SUFFIX}"
    export IAM_POLICY_NAME="budget-action-policy-${RANDOM_SUFFIX}"
    
    # Prompt for budget amount if not provided
    if [ -z "$BUDGET_AMOUNT" ]; then
        read -p "Enter monthly budget amount in USD (default: 100): " BUDGET_AMOUNT
        BUDGET_AMOUNT=${BUDGET_AMOUNT:-100}
    fi
    
    # Validate budget amount is numeric
    if ! [[ "$BUDGET_AMOUNT" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        error "Budget amount must be numeric: $BUDGET_AMOUNT"
    fi
    
    log "Environment setup completed"
    log "AWS Region: ${AWS_REGION}"
    log "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log "Budget Email: ${BUDGET_EMAIL}"
    log "Budget Amount: \$${BUDGET_AMOUNT}"
    log "Budget Name: ${BUDGET_NAME}"
    log "SNS Topic: ${SNS_TOPIC_NAME}"
    log "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic for budget notifications..."
    
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "${SNS_TOPIC_NAME}" \
        --query TopicArn --output text)
    
    if [ $? -eq 0 ]; then
        export SNS_TOPIC_ARN
        success "SNS topic created: ${SNS_TOPIC_ARN}"
        
        # Subscribe email to SNS topic
        log "Subscribing email to SNS topic..."
        aws sns subscribe \
            --topic-arn "${SNS_TOPIC_ARN}" \
            --protocol email \
            --notification-endpoint "${BUDGET_EMAIL}" > /dev/null
        
        success "Email subscription created. Please check your email and confirm the subscription."
    else
        error "Failed to create SNS topic"
    fi
}

# Function to create IAM role for Lambda
create_lambda_iam_role() {
    log "Creating IAM role for Lambda function..."
    
    # Create trust policy for Lambda
    cat > /tmp/lambda-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    IAM_ROLE_ARN=$(aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
        --query Role.Arn --output text)
    
    if [ $? -eq 0 ]; then
        export IAM_ROLE_ARN
        success "IAM role created: ${IAM_ROLE_ARN}"
    else
        error "Failed to create IAM role"
    fi
}

# Function to create and attach IAM policy
create_lambda_iam_policy() {
    log "Creating IAM policy for Lambda function..."
    
    # Create policy for budget actions
    cat > /tmp/budget-action-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:StopInstances",
                "ec2:StartInstances",
                "ec2:DescribeInstanceStatus"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "${SNS_TOPIC_ARN}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "budgets:ViewBudget",
                "budgets:ModifyBudget"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Create policy
    aws iam create-policy \
        --policy-name "${IAM_POLICY_NAME}" \
        --policy-document file:///tmp/budget-action-policy.json > /dev/null
    
    if [ $? -eq 0 ]; then
        # Attach policy to role
        aws iam attach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_NAME}"
        
        success "IAM policy created and attached"
    else
        error "Failed to create IAM policy"
    fi
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function for budget actions..."
    
    # Create Lambda function code
    cat > /tmp/budget-action-function.py << 'EOF'
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    try:
        # Parse the budget alert event
        message = json.loads(event['Records'][0]['Sns']['Message'])
        budget_name = message.get('BudgetName', 'Unknown')
        account_id = message.get('AccountId', 'Unknown')
        
        logger.info(f"Budget alert triggered for {budget_name} in account {account_id}")
        
        # Initialize AWS clients
        ec2 = boto3.client('ec2')
        sns = boto3.client('sns')
        
        # Get development instances (tagged as Environment=Development)
        response = ec2.describe_instances(
            Filters=[
                {'Name': 'tag:Environment', 'Values': ['Development', 'Dev']},
                {'Name': 'instance-state-name', 'Values': ['running']}
            ]
        )
        
        instances_to_stop = []
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instances_to_stop.append(instance['InstanceId'])
        
        # Stop development instances
        if instances_to_stop:
            ec2.stop_instances(InstanceIds=instances_to_stop)
            logger.info(f"Stopped {len(instances_to_stop)} development instances")
            
            # Send notification
            topic_arn = context.invoked_function_arn.replace(':function:', ':topic:').replace(context.function_name.split('-')[-1], 'budget-alerts')
            sns.publish(
                TopicArn=topic_arn,
                Subject=f'Budget Action Executed - {budget_name}',
                Message=f'Automatically stopped {len(instances_to_stop)} development instances due to budget alert.\n\nInstances: {", ".join(instances_to_stop)}'
            )
        else:
            logger.info("No development instances found to stop")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Budget action completed for {budget_name}',
                'instances_stopped': len(instances_to_stop)
            })
        }
        
    except Exception as e:
        logger.error(f"Error executing budget action: {str(e)}")
        raise e
EOF
    
    # Create deployment package
    cd /tmp
    zip budget-action-function.zip budget-action-function.py > /dev/null
    
    # Wait for IAM role propagation
    log "Waiting for IAM role propagation..."
    sleep 10
    
    # Create Lambda function
    LAMBDA_FUNCTION_ARN=$(aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "${IAM_ROLE_ARN}" \
        --handler budget-action-function.lambda_handler \
        --zip-file fileb://budget-action-function.zip \
        --description "Automated budget action function" \
        --timeout 60 \
        --query FunctionArn --output text)
    
    if [ $? -eq 0 ]; then
        export LAMBDA_FUNCTION_ARN
        success "Lambda function created: ${LAMBDA_FUNCTION_ARN}"
    else
        error "Failed to create Lambda function"
    fi
    
    cd - > /dev/null
}

# Function to create budget with notifications
create_budget() {
    log "Creating budget with multiple alert thresholds..."
    
    # Get current timestamp for budget time period
    START_DATE=$(date -d "$(date +%Y-%m-01)" +%s)
    END_DATE=$(date -d "$(date +%Y-%m-01) +2 years" +%s)
    
    # Create budget configuration
    cat > /tmp/budget-config.json << EOF
{
    "BudgetName": "${BUDGET_NAME}",
    "BudgetLimit": {
        "Amount": "${BUDGET_AMOUNT}",
        "Unit": "USD"
    },
    "BudgetType": "COST",
    "CostTypes": {
        "IncludeCredit": false,
        "IncludeDiscount": true,
        "IncludeOtherSubscription": true,
        "IncludeRecurring": true,
        "IncludeRefund": true,
        "IncludeSubscription": true,
        "IncludeSupport": true,
        "IncludeTax": true,
        "IncludeUpfront": true,
        "UseBlended": false,
        "UseAmortized": false
    },
    "TimeUnit": "MONTHLY",
    "TimePeriod": {
        "Start": ${START_DATE},
        "End": ${END_DATE}
    }
}
EOF
    
    # Create notifications configuration
    cat > /tmp/budget-notifications.json << EOF
[
    {
        "Notification": {
            "NotificationType": "ACTUAL",
            "ComparisonOperator": "GREATER_THAN",
            "Threshold": 80,
            "ThresholdType": "PERCENTAGE"
        },
        "Subscribers": [
            {
                "SubscriptionType": "EMAIL",
                "Address": "${BUDGET_EMAIL}"
            },
            {
                "SubscriptionType": "SNS",
                "Address": "${SNS_TOPIC_ARN}"
            }
        ]
    },
    {
        "Notification": {
            "NotificationType": "FORECASTED",
            "ComparisonOperator": "GREATER_THAN",
            "Threshold": 90,
            "ThresholdType": "PERCENTAGE"
        },
        "Subscribers": [
            {
                "SubscriptionType": "EMAIL",
                "Address": "${BUDGET_EMAIL}"
            },
            {
                "SubscriptionType": "SNS",
                "Address": "${SNS_TOPIC_ARN}"
            }
        ]
    },
    {
        "Notification": {
            "NotificationType": "ACTUAL",
            "ComparisonOperator": "GREATER_THAN",
            "Threshold": 100,
            "ThresholdType": "PERCENTAGE"
        },
        "Subscribers": [
            {
                "SubscriptionType": "EMAIL",
                "Address": "${BUDGET_EMAIL}"
            },
            {
                "SubscriptionType": "SNS",
                "Address": "${SNS_TOPIC_ARN}"
            }
        ]
    }
]
EOF
    
    # Create budget
    aws budgets create-budget \
        --account-id "${AWS_ACCOUNT_ID}" \
        --budget file:///tmp/budget-config.json \
        --notifications-with-subscribers file:///tmp/budget-notifications.json
    
    if [ $? -eq 0 ]; then
        success "Budget created with multiple alert thresholds"
    else
        error "Failed to create budget"
    fi
}

# Function to configure Lambda trigger
configure_lambda_trigger() {
    log "Configuring Lambda trigger for SNS topic..."
    
    # Add SNS trigger permission to Lambda function
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id "sns-trigger" \
        --action lambda:InvokeFunction \
        --principal sns.amazonaws.com \
        --source-arn "${SNS_TOPIC_ARN}" > /dev/null
    
    if [ $? -eq 0 ]; then
        # Subscribe Lambda to SNS topic
        aws sns subscribe \
            --topic-arn "${SNS_TOPIC_ARN}" \
            --protocol lambda \
            --notification-endpoint "${LAMBDA_FUNCTION_ARN}" > /dev/null
        
        success "Lambda function subscribed to SNS topic"
    else
        error "Failed to configure Lambda trigger"
    fi
}

# Function to create budget action resources
create_budget_action_resources() {
    log "Creating budget action resources..."
    
    # Create restrictive IAM policy for budget actions
    cat > /tmp/budget-restriction-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Deny",
            "Action": [
                "ec2:RunInstances",
                "ec2:StartInstances",
                "rds:CreateDBInstance",
                "rds:StartDBInstance"
            ],
            "Resource": "*",
            "Condition": {
                "StringNotEquals": {
                    "ec2:InstanceType": [
                        "t3.nano",
                        "t3.micro",
                        "t3.small"
                    ]
                }
            }
        }
    ]
}
EOF
    
    # Create budget action policy
    BUDGET_ACTION_POLICY_ARN=$(aws iam create-policy \
        --policy-name "budget-restriction-policy-${RANDOM_SUFFIX}" \
        --policy-document file:///tmp/budget-restriction-policy.json \
        --query Policy.Arn --output text 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        export BUDGET_ACTION_POLICY_ARN
        success "Budget action policy created: ${BUDGET_ACTION_POLICY_ARN}"
    else
        warning "Budget action policy may already exist or failed to create"
    fi
    
    # Create trust policy for AWS Budgets
    cat > /tmp/budget-service-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "budgets.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role for budget actions
    BUDGET_ACTION_ROLE_ARN=$(aws iam create-role \
        --role-name "budget-action-role-${RANDOM_SUFFIX}" \
        --assume-role-policy-document file:///tmp/budget-service-trust-policy.json \
        --query Role.Arn --output text 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        export BUDGET_ACTION_ROLE_ARN
        success "Budget action role created: ${BUDGET_ACTION_ROLE_ARN}"
        
        # Attach necessary policies
        aws iam attach-role-policy \
            --role-name "budget-action-role-${RANDOM_SUFFIX}" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/BudgetsActionsWithAWSResourceControlAccess" > /dev/null
        
        success "Budget action role configured"
    else
        warning "Budget action role may already exist or failed to create"
    fi
}

# Function to save deployment state
save_deployment_state() {
    log "Saving deployment state..."
    
    cat > /tmp/budget-deployment-state.json << EOF
{
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "budget_email": "${BUDGET_EMAIL}",
    "budget_amount": "${BUDGET_AMOUNT}",
    "budget_name": "${BUDGET_NAME}",
    "sns_topic_name": "${SNS_TOPIC_NAME}",
    "sns_topic_arn": "${SNS_TOPIC_ARN}",
    "lambda_function_name": "${LAMBDA_FUNCTION_NAME}",
    "lambda_function_arn": "${LAMBDA_FUNCTION_ARN}",
    "iam_role_name": "${IAM_ROLE_NAME}",
    "iam_role_arn": "${IAM_ROLE_ARN}",
    "iam_policy_name": "${IAM_POLICY_NAME}",
    "budget_action_policy_arn": "${BUDGET_ACTION_POLICY_ARN}",
    "budget_action_role_arn": "${BUDGET_ACTION_ROLE_ARN}",
    "random_suffix": "${RANDOM_SUFFIX}"
}
EOF
    
    # Copy to current directory for destroy script
    cp /tmp/budget-deployment-state.json ./budget-deployment-state.json
    success "Deployment state saved to budget-deployment-state.json"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f /tmp/lambda-trust-policy.json
    rm -f /tmp/budget-action-policy.json
    rm -f /tmp/budget-config.json
    rm -f /tmp/budget-notifications.json
    rm -f /tmp/budget-restriction-policy.json
    rm -f /tmp/budget-service-trust-policy.json
    rm -f /tmp/budget-action-function.py
    rm -f /tmp/budget-action-function.zip
    rm -f /tmp/budget-deployment-state.json
    success "Temporary files cleaned up"
}

# Function to display deployment summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "=========================================="
    echo ""
    echo "Resources Created:"
    echo "- Budget Name: ${BUDGET_NAME}"
    echo "- SNS Topic: ${SNS_TOPIC_ARN}"
    echo "- Lambda Function: ${LAMBDA_FUNCTION_ARN}"
    echo "- IAM Role: ${IAM_ROLE_ARN}"
    echo ""
    echo "Budget Configuration:"
    echo "- Monthly Limit: \$${BUDGET_AMOUNT}"
    echo "- Alert Thresholds: 80%, 90%, 100%"
    echo "- Notification Email: ${BUDGET_EMAIL}"
    echo ""
    echo "Next Steps:"
    echo "1. Check your email and confirm the SNS subscription"
    echo "2. Tag your development EC2 instances with 'Environment=Development' or 'Environment=Dev'"
    echo "3. Monitor your budget in the AWS Console"
    echo ""
    echo "To clean up all resources, run: ./destroy.sh"
    echo "=========================================="
}

# Main execution
main() {
    echo "Starting AWS Budget Alerts and Automated Actions deployment..."
    echo ""
    
    check_prerequisites
    setup_environment
    create_sns_topic
    create_lambda_iam_role
    create_lambda_iam_policy
    create_lambda_function
    create_budget
    configure_lambda_trigger
    create_budget_action_resources
    save_deployment_state
    cleanup_temp_files
    display_summary
}

# Execute main function
main "$@"