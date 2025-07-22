#!/bin/bash

# =============================================================================
# AWS Cost Optimization Workflows Deployment Script
# =============================================================================
# This script deploys an automated cost optimization solution using:
# - AWS Cost Optimization Hub
# - AWS Budgets (Cost, Usage, RI Utilization)
# - SNS for notifications
# - Cost Anomaly Detection
# - Lambda for automation
# - IAM roles and policies
# =============================================================================

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/cost-optimization-deployment-$(date +%Y%m%d-%H%M%S).log"
RESOURCE_TAG_KEY="CostOptimizationProject"
RESOURCE_TAG_VALUE="automated-workflows"

# Global variables for cleanup tracking
CREATED_RESOURCES=()
DEPLOYMENT_ID=""
NOTIFICATION_EMAIL=""

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
            echo -e "${BLUE}[INFO]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "[DEBUG] ${message}" | tee -a "$LOG_FILE"
            fi
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "INFO" "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions
    log "INFO" "Validating AWS permissions..."
    local required_services=("budgets" "sns" "lambda" "iam" "ce" "cost-optimization-hub")
    
    for service in "${required_services[@]}"; do
        case $service in
            "budgets")
                if ! aws budgets describe-budgets --account-id "$(aws sts get-caller-identity --query Account --output text)" --max-results 1 &> /dev/null; then
                    log "WARNING" "Unable to validate AWS Budgets permissions"
                fi
                ;;
            "cost-optimization-hub")
                if ! aws cost-optimization-hub get-preferences &> /dev/null 2>&1; then
                    log "INFO" "Cost Optimization Hub not yet enabled (will enable during deployment)"
                fi
                ;;
        esac
    done
    
    log "SUCCESS" "Prerequisites check completed"
}

prompt_for_configuration() {
    log "INFO" "Gathering deployment configuration..."
    
    # Get notification email
    while [[ -z "$NOTIFICATION_EMAIL" ]]; do
        read -p "Enter email address for budget notifications: " NOTIFICATION_EMAIL
        if [[ ! "$NOTIFICATION_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            log "ERROR" "Invalid email format. Please try again."
            NOTIFICATION_EMAIL=""
        fi
    done
    
    # Get budget amounts
    read -p "Enter monthly cost budget amount in USD (default: 1000): " MONTHLY_BUDGET
    MONTHLY_BUDGET=${MONTHLY_BUDGET:-1000}
    
    read -p "Enter EC2 usage budget in hours (default: 2000): " EC2_USAGE_BUDGET
    EC2_USAGE_BUDGET=${EC2_USAGE_BUDGET:-2000}
    
    read -p "Enter minimum RI utilization threshold % (default: 80): " RI_THRESHOLD
    RI_THRESHOLD=${RI_THRESHOLD:-80}
    
    # Confirm deployment
    echo
    log "INFO" "Deployment Configuration Summary:"
    echo "  Email: $NOTIFICATION_EMAIL"
    echo "  Monthly Budget: \$$MONTHLY_BUDGET USD"
    echo "  EC2 Usage Budget: $EC2_USAGE_BUDGET hours"
    echo "  RI Utilization Threshold: $RI_THRESHOLD%"
    echo
    
    read -p "Proceed with deployment? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log "INFO" "Deployment cancelled by user"
        exit 0
    fi
}

setup_environment() {
    log "INFO" "Setting up deployment environment..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log "WARNING" "No default region configured, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique deployment identifier
    DEPLOYMENT_ID=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    log "INFO" "Deployment ID: $DEPLOYMENT_ID"
    log "INFO" "AWS Region: $AWS_REGION"
    log "INFO" "AWS Account: $AWS_ACCOUNT_ID"
}

enable_cost_optimization_hub() {
    log "INFO" "Enabling AWS Cost Optimization Hub..."
    
    # Check if already enabled
    if aws cost-optimization-hub get-preferences &> /dev/null; then
        log "INFO" "Cost Optimization Hub already enabled"
        return 0
    fi
    
    # Enable Cost Optimization Hub
    if aws cost-optimization-hub update-preferences \
        --savings-estimation-mode AFTER_DISCOUNTS \
        --member-account-discount-visibility STANDARD; then
        
        log "SUCCESS" "Cost Optimization Hub enabled"
        CREATED_RESOURCES+=("cost-optimization-hub")
        
        # Wait for activation
        log "INFO" "Waiting for Cost Optimization Hub activation..."
        sleep 30
        
        # Verify activation
        if aws cost-optimization-hub get-preferences &> /dev/null; then
            log "SUCCESS" "Cost Optimization Hub activation verified"
        else
            log "WARNING" "Cost Optimization Hub activation status unclear"
        fi
    else
        log "ERROR" "Failed to enable Cost Optimization Hub"
        return 1
    fi
}

create_sns_topic() {
    log "INFO" "Creating SNS topic for notifications..."
    
    local topic_name="cost-optimization-alerts-${DEPLOYMENT_ID}"
    
    # Create SNS topic
    if aws sns create-topic \
        --name "$topic_name" \
        --region "$AWS_REGION" \
        --tags Key="$RESOURCE_TAG_KEY",Value="$RESOURCE_TAG_VALUE" \
        Key=Environment,Value=production \
        Key=Purpose,Value=cost-optimization; then
        
        # Get topic ARN
        export SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
            --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${topic_name}" \
            --query 'Attributes.TopicArn' --output text)
        
        log "SUCCESS" "SNS topic created: $SNS_TOPIC_ARN"
        CREATED_RESOURCES+=("sns:$SNS_TOPIC_ARN")
        
        # Subscribe email to SNS topic
        if aws sns subscribe \
            --topic-arn "$SNS_TOPIC_ARN" \
            --protocol email \
            --notification-endpoint "$NOTIFICATION_EMAIL"; then
            log "SUCCESS" "Email subscription created for $NOTIFICATION_EMAIL"
        else
            log "ERROR" "Failed to create email subscription"
            return 1
        fi
        
        # Set SNS topic policy for AWS Budgets
        local policy="{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Effect\": \"Allow\",
                    \"Principal\": {
                        \"Service\": \"budgets.amazonaws.com\"
                    },
                    \"Action\": \"SNS:Publish\",
                    \"Resource\": \"$SNS_TOPIC_ARN\"
                }
            ]
        }"
        
        if aws sns set-topic-attributes \
            --topic-arn "$SNS_TOPIC_ARN" \
            --attribute-name Policy \
            --attribute-value "$policy"; then
            log "SUCCESS" "SNS topic policy configured for AWS Budgets"
        else
            log "ERROR" "Failed to set SNS topic policy"
            return 1
        fi
        
    else
        log "ERROR" "Failed to create SNS topic"
        return 1
    fi
}

create_budgets() {
    log "INFO" "Creating AWS Budgets..."
    
    local current_date=$(date -u +%Y-%m-01)
    local end_date=$(date -u -d "$(date +%Y-%m-01) +1 month -1 day" +%Y-%m-%d)
    
    # Create monthly cost budget
    log "INFO" "Creating monthly cost budget..."
    local cost_budget_name="monthly-cost-budget-${DEPLOYMENT_ID}"
    
    local cost_budget="{
        \"BudgetName\": \"$cost_budget_name\",
        \"BudgetLimit\": {
            \"Amount\": \"$MONTHLY_BUDGET\",
            \"Unit\": \"USD\"
        },
        \"TimeUnit\": \"MONTHLY\",
        \"BudgetType\": \"COST\",
        \"CostFilters\": {},
        \"TimePeriod\": {
            \"Start\": \"$current_date\",
            \"End\": \"$end_date\"
        }
    }"
    
    if aws budgets create-budget \
        --account-id "$AWS_ACCOUNT_ID" \
        --budget "$cost_budget"; then
        
        log "SUCCESS" "Monthly cost budget created: $cost_budget_name"
        CREATED_RESOURCES+=("budget:$cost_budget_name")
        
        # Create notification for 80% threshold
        local notification="{
            \"NotificationType\": \"ACTUAL\",
            \"ComparisonOperator\": \"GREATER_THAN\",
            \"Threshold\": 80,
            \"ThresholdType\": \"PERCENTAGE\"
        }"
        
        local subscribers="[{
            \"SubscriptionType\": \"SNS\",
            \"Address\": \"$SNS_TOPIC_ARN\"
        }]"
        
        if aws budgets create-notification \
            --account-id "$AWS_ACCOUNT_ID" \
            --budget-name "$cost_budget_name" \
            --notification "$notification" \
            --subscribers "$subscribers"; then
            log "SUCCESS" "Budget notification created for 80% threshold"
        else
            log "WARNING" "Failed to create budget notification"
        fi
    else
        log "ERROR" "Failed to create monthly cost budget"
        return 1
    fi
    
    # Create EC2 usage budget
    log "INFO" "Creating EC2 usage budget..."
    local usage_budget_name="ec2-usage-budget-${DEPLOYMENT_ID}"
    
    local usage_budget="{
        \"BudgetName\": \"$usage_budget_name\",
        \"BudgetLimit\": {
            \"Amount\": \"$EC2_USAGE_BUDGET\",
            \"Unit\": \"HOURS\"
        },
        \"TimeUnit\": \"MONTHLY\",
        \"BudgetType\": \"USAGE\",
        \"CostFilters\": {
            \"Service\": [\"Amazon Elastic Compute Cloud - Compute\"]
        },
        \"TimePeriod\": {
            \"Start\": \"$current_date\",
            \"End\": \"$end_date\"
        }
    }"
    
    if aws budgets create-budget \
        --account-id "$AWS_ACCOUNT_ID" \
        --budget "$usage_budget"; then
        
        log "SUCCESS" "EC2 usage budget created: $usage_budget_name"
        CREATED_RESOURCES+=("budget:$usage_budget_name")
        
        # Create forecasted notification
        local forecast_notification="{
            \"NotificationType\": \"FORECASTED\",
            \"ComparisonOperator\": \"GREATER_THAN\",
            \"Threshold\": 90,
            \"ThresholdType\": \"PERCENTAGE\"
        }"
        
        if aws budgets create-notification \
            --account-id "$AWS_ACCOUNT_ID" \
            --budget-name "$usage_budget_name" \
            --notification "$forecast_notification" \
            --subscribers "$subscribers"; then
            log "SUCCESS" "EC2 usage budget forecasted notification created"
        else
            log "WARNING" "Failed to create EC2 usage budget notification"
        fi
    else
        log "ERROR" "Failed to create EC2 usage budget"
        return 1
    fi
    
    # Create RI utilization budget
    log "INFO" "Creating Reserved Instance utilization budget..."
    local ri_budget_name="ri-utilization-budget-${DEPLOYMENT_ID}"
    
    local ri_budget="{
        \"BudgetName\": \"$ri_budget_name\",
        \"BudgetLimit\": {
            \"Amount\": \"$RI_THRESHOLD\",
            \"Unit\": \"PERCENT\"
        },
        \"TimeUnit\": \"MONTHLY\",
        \"BudgetType\": \"RI_UTILIZATION\",
        \"CostFilters\": {
            \"Service\": [\"Amazon Elastic Compute Cloud - Compute\"]
        },
        \"TimePeriod\": {
            \"Start\": \"$current_date\",
            \"End\": \"$end_date\"
        }
    }"
    
    if aws budgets create-budget \
        --account-id "$AWS_ACCOUNT_ID" \
        --budget "$ri_budget"; then
        
        log "SUCCESS" "RI utilization budget created: $ri_budget_name"
        CREATED_RESOURCES+=("budget:$ri_budget_name")
        
        # Create notification for low RI utilization
        local ri_notification="{
            \"NotificationType\": \"ACTUAL\",
            \"ComparisonOperator\": \"LESS_THAN\",
            \"Threshold\": $RI_THRESHOLD,
            \"ThresholdType\": \"PERCENTAGE\"
        }"
        
        if aws budgets create-notification \
            --account-id "$AWS_ACCOUNT_ID" \
            --budget-name "$ri_budget_name" \
            --notification "$ri_notification" \
            --subscribers "$subscribers"; then
            log "SUCCESS" "RI utilization budget notification created"
        else
            log "WARNING" "Failed to create RI utilization budget notification"
        fi
    else
        log "WARNING" "Failed to create RI utilization budget (may not have RIs)"
    fi
}

create_budget_actions_iam() {
    log "INFO" "Creating IAM resources for budget actions..."
    
    local role_name="BudgetActionsRole-${DEPLOYMENT_ID}"
    local policy_name="BudgetRestrictionPolicy-${DEPLOYMENT_ID}"
    
    # Create assume role policy
    local trust_policy="{
        \"Version\": \"2012-10-17\",
        \"Statement\": [
            {
                \"Effect\": \"Allow\",
                \"Principal\": {
                    \"Service\": \"budgets.amazonaws.com\"
                },
                \"Action\": \"sts:AssumeRole\"
            }
        ]
    }"
    
    # Create IAM role
    if aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document "$trust_policy" \
        --tags Key="$RESOURCE_TAG_KEY",Value="$RESOURCE_TAG_VALUE" \
               Key=Purpose,Value=budget-actions; then
        
        log "SUCCESS" "Budget actions IAM role created: $role_name"
        CREATED_RESOURCES+=("iam-role:$role_name")
        
        # Create restrictive policy
        local restriction_policy="{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Effect\": \"Deny\",
                    \"Action\": [
                        \"ec2:RunInstances\",
                        \"ec2:StartInstances\",
                        \"rds:CreateDBInstance\",
                        \"rds:CreateDBCluster\"
                    ],
                    \"Resource\": \"*\"
                }
            ]
        }"
        
        # Create policy
        if aws iam create-policy \
            --policy-name "$policy_name" \
            --policy-document "$restriction_policy" \
            --tags Key="$RESOURCE_TAG_KEY",Value="$RESOURCE_TAG_VALUE" \
                   Key=Purpose,Value=budget-restrictions; then
            
            log "SUCCESS" "Budget restriction policy created: $policy_name"
            CREATED_RESOURCES+=("iam-policy:arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}")
            
            # Attach policy to role
            if aws iam attach-role-policy \
                --role-name "$role_name" \
                --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"; then
                log "SUCCESS" "Policy attached to budget actions role"
            else
                log "ERROR" "Failed to attach policy to role"
                return 1
            fi
        else
            log "ERROR" "Failed to create budget restriction policy"
            return 1
        fi
    else
        log "ERROR" "Failed to create budget actions IAM role"
        return 1
    fi
}

create_cost_anomaly_detection() {
    log "INFO" "Setting up Cost Anomaly Detection..."
    
    # Create anomaly detector
    local detector_name="cost-anomaly-detector-${DEPLOYMENT_ID}"
    
    local detector_config="{
        \"DetectorName\": \"$detector_name\",
        \"MonitorType\": \"DIMENSIONAL\",
        \"DimensionKey\": \"SERVICE\",
        \"MatchOptions\": [\"EQUALS\"],
        \"MonitorSpecification\": \"{\\\"DimensionKey\\\":\\\"SERVICE\\\",\\\"MatchOptions\\\":[\\\"EQUALS\\\"],\\\"Values\\\":[\\\"EC2-Instance\\\",\\\"RDS\\\",\\\"S3\\\"]}\"
    }"
    
    if DETECTOR_ARN=$(aws ce create-anomaly-detector \
        --anomaly-detector "$detector_config" \
        --tags Key="$RESOURCE_TAG_KEY",Value="$RESOURCE_TAG_VALUE" \
               Key=Purpose,Value=cost-anomaly-detection \
        --query 'DetectorArn' --output text 2>/dev/null); then
        
        log "SUCCESS" "Cost anomaly detector created: $DETECTOR_ARN"
        CREATED_RESOURCES+=("anomaly-detector:$DETECTOR_ARN")
        
        # Create anomaly subscription
        local subscription_name="cost-anomaly-subscription-${DEPLOYMENT_ID}"
        local subscription_config="{
            \"SubscriptionName\": \"$subscription_name\",
            \"MonitorArnList\": [\"$DETECTOR_ARN\"],
            \"Subscribers\": [
                {
                    \"Address\": \"$SNS_TOPIC_ARN\",
                    \"Type\": \"SNS\"
                }
            ],
            \"Threshold\": 100,
            \"Frequency\": \"DAILY\"
        }"
        
        if SUBSCRIPTION_ARN=$(aws ce create-anomaly-subscription \
            --anomaly-subscription "$subscription_config" \
            --tags Key="$RESOURCE_TAG_KEY",Value="$RESOURCE_TAG_VALUE" \
                   Key=Purpose,Value=cost-anomaly-subscription \
            --query 'SubscriptionArn' --output text 2>/dev/null); then
            
            log "SUCCESS" "Cost anomaly subscription created: $SUBSCRIPTION_ARN"
            CREATED_RESOURCES+=("anomaly-subscription:$SUBSCRIPTION_ARN")
        else
            log "WARNING" "Failed to create cost anomaly subscription"
        fi
    else
        log "WARNING" "Failed to create cost anomaly detector"
    fi
}

create_lambda_function() {
    log "INFO" "Creating Lambda function for cost optimization automation..."
    
    local function_name="cost-optimization-handler-${DEPLOYMENT_ID}"
    local role_name="CostOptimizationLambdaRole-${DEPLOYMENT_ID}"
    
    # Create Lambda execution role
    local lambda_trust_policy="{
        \"Version\": \"2012-10-17\",
        \"Statement\": [
            {
                \"Effect\": \"Allow\",
                \"Principal\": {
                    \"Service\": \"lambda.amazonaws.com\"
                },
                \"Action\": \"sts:AssumeRole\"
            }
        ]
    }"
    
    if aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document "$lambda_trust_policy" \
        --tags Key="$RESOURCE_TAG_KEY",Value="$RESOURCE_TAG_VALUE" \
               Key=Purpose,Value=lambda-cost-optimization; then
        
        log "SUCCESS" "Lambda execution role created: $role_name"
        CREATED_RESOURCES+=("iam-role:$role_name")
        
        # Attach basic execution policy
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        
        # Attach Cost Optimization Hub policy
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/CostOptimizationHubServiceRolePolicy"
        
        log "SUCCESS" "Lambda policies attached"
        
        # Wait for role propagation
        sleep 10
        
        # Create Lambda function code
        local temp_dir=$(mktemp -d)
        cat > "$temp_dir/cost_optimization_handler.py" << 'EOF'
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process Cost Optimization Hub recommendations and budget alerts
    """
    try:
        # Initialize AWS clients
        coh_client = boto3.client('cost-optimization-hub')
        ce_client = boto3.client('ce')
        sns_client = boto3.client('sns')
        
        logger.info(f"Processing cost optimization event: {json.dumps(event, default=str)}")
        
        # Process SNS message from budget alerts
        if 'Records' in event:
            for record in event['Records']:
                if record.get('EventSource') == 'aws:sns':
                    message = json.loads(record['Sns']['Message'])
                    logger.info(f"Processing budget alert: {message}")
                    
                    # Get cost optimization recommendations
                    try:
                        recommendations = coh_client.list_recommendations(
                            includeAllRecommendations=True,
                            maxResults=50
                        )
                        
                        # Process top recommendations
                        recommendation_count = 0
                        total_savings = 0
                        
                        for rec in recommendations.get('items', []):
                            recommendation_count += 1
                            logger.info(f"Recommendation {recommendation_count}: {rec.get('recommendationId', 'N/A')} - {rec.get('actionType', 'N/A')}")
                            
                            if 'estimatedMonthlySavings' in rec:
                                total_savings += float(rec['estimatedMonthlySavings'])
                                logger.info(f"Potential monthly savings: ${rec['estimatedMonthlySavings']}")
                        
                        logger.info(f"Total recommendations processed: {recommendation_count}")
                        logger.info(f"Total potential monthly savings: ${total_savings:.2f}")
                        
                    except Exception as e:
                        logger.error(f"Error retrieving cost optimization recommendations: {str(e)}")
        
        # Direct invocation for testing
        elif event.get('source') == 'cost-optimization-test':
            logger.info("Processing test invocation")
            
            try:
                # Test Cost Optimization Hub access
                preferences = coh_client.get_preferences()
                logger.info(f"Cost Optimization Hub preferences: {preferences}")
                
                # Get sample recommendations
                recommendations = coh_client.list_recommendations(maxResults=5)
                logger.info(f"Retrieved {len(recommendations.get('items', []))} recommendations")
                
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'message': 'Cost optimization test completed successfully',
                        'recommendationCount': len(recommendations.get('items', [])),
                        'timestamp': datetime.now().isoformat()
                    })
                }
                
            except Exception as e:
                logger.error(f"Error during test invocation: {str(e)}")
                return {
                    'statusCode': 500,
                    'body': json.dumps({
                        'message': f'Test failed: {str(e)}',
                        'timestamp': datetime.now().isoformat()
                    })
                }
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost optimization processing completed',
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing cost optimization: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': f'Error: {str(e)}',
                'timestamp': datetime.now().isoformat()
            })
        }
EOF
        
        # Create deployment package
        cd "$temp_dir"
        zip cost_optimization_function.zip cost_optimization_handler.py
        
        # Create Lambda function
        if aws lambda create-function \
            --function-name "$function_name" \
            --runtime python3.9 \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${role_name}" \
            --handler cost_optimization_handler.lambda_handler \
            --zip-file fileb://cost_optimization_function.zip \
            --timeout 60 \
            --memory-size 256 \
            --tags "$RESOURCE_TAG_KEY=$RESOURCE_TAG_VALUE,Purpose=cost-optimization-automation"; then
            
            log "SUCCESS" "Lambda function created: $function_name"
            CREATED_RESOURCES+=("lambda:$function_name")
            
            # Clean up temp files
            rm -rf "$temp_dir"
        else
            log "ERROR" "Failed to create Lambda function"
            rm -rf "$temp_dir"
            return 1
        fi
    else
        log "ERROR" "Failed to create Lambda execution role"
        return 1
    fi
}

validate_deployment() {
    log "INFO" "Validating deployment..."
    
    # Validate Cost Optimization Hub
    if aws cost-optimization-hub get-preferences &> /dev/null; then
        log "SUCCESS" "Cost Optimization Hub is active"
    else
        log "WARNING" "Cost Optimization Hub validation failed"
    fi
    
    # Validate budgets
    local budget_count=$(aws budgets describe-budgets \
        --account-id "$AWS_ACCOUNT_ID" \
        --query "Budgets[?contains(BudgetName, \`${DEPLOYMENT_ID}\`)] | length(@)")
    
    if [[ "$budget_count" -gt 0 ]]; then
        log "SUCCESS" "Created $budget_count budget(s)"
    else
        log "WARNING" "No budgets found with deployment ID"
    fi
    
    # Validate SNS topic
    if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &> /dev/null; then
        log "SUCCESS" "SNS topic is accessible"
        
        # Check subscriptions
        local subscription_count=$(aws sns list-subscriptions-by-topic \
            --topic-arn "$SNS_TOPIC_ARN" \
            --query 'Subscriptions | length(@)')
        log "INFO" "SNS topic has $subscription_count subscription(s)"
    else
        log "WARNING" "SNS topic validation failed"
    fi
    
    # Test Lambda function
    local function_name="cost-optimization-handler-${DEPLOYMENT_ID}"
    if aws lambda invoke \
        --function-name "$function_name" \
        --payload '{"source": "cost-optimization-test"}' \
        /tmp/lambda_test_response.json &> /dev/null; then
        
        local status_code=$(grep -o '"statusCode":[0-9]*' /tmp/lambda_test_response.json | cut -d: -f2)
        if [[ "$status_code" == "200" ]]; then
            log "SUCCESS" "Lambda function test successful"
        else
            log "WARNING" "Lambda function returned status code: $status_code"
        fi
    else
        log "WARNING" "Lambda function test failed"
    fi
}

save_deployment_info() {
    log "INFO" "Saving deployment information..."
    
    local info_file="${SCRIPT_DIR}/deployment-info-${DEPLOYMENT_ID}.json"
    
    cat > "$info_file" << EOF
{
    "deploymentId": "$DEPLOYMENT_ID",
    "deploymentDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "awsRegion": "$AWS_REGION",
    "awsAccountId": "$AWS_ACCOUNT_ID",
    "notificationEmail": "$NOTIFICATION_EMAIL",
    "monthlyBudget": "$MONTHLY_BUDGET",
    "ec2UsageBudget": "$EC2_USAGE_BUDGET",
    "riThreshold": "$RI_THRESHOLD",
    "snsTopicArn": "$SNS_TOPIC_ARN",
    "createdResources": $(printf '%s\n' "${CREATED_RESOURCES[@]}" | jq -R . | jq -s .),
    "logFile": "$LOG_FILE"
}
EOF
    
    log "SUCCESS" "Deployment information saved to: $info_file"
    
    echo
    echo "=========================================="
    echo "DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "=========================================="
    echo "Deployment ID: $DEPLOYMENT_ID"
    echo "SNS Topic: $SNS_TOPIC_ARN"
    echo "Email: $NOTIFICATION_EMAIL (please confirm subscription)"
    echo "Monthly Budget: \$$MONTHLY_BUDGET"
    echo "Log File: $LOG_FILE"
    echo "Info File: $info_file"
    echo
    echo "Next Steps:"
    echo "1. Confirm your email subscription in your inbox"
    echo "2. Monitor the Cost Optimization Hub for recommendations"
    echo "3. Review budget alerts as they arrive"
    echo "4. Use destroy.sh with deployment ID to clean up: ./destroy.sh $DEPLOYMENT_ID"
    echo "=========================================="
}

cleanup_on_error() {
    log "ERROR" "Deployment failed. Initiating cleanup..."
    
    if [[ -f "${SCRIPT_DIR}/destroy.sh" ]]; then
        log "INFO" "Running cleanup script..."
        bash "${SCRIPT_DIR}/destroy.sh" "$DEPLOYMENT_ID" --force
    else
        log "WARNING" "Cleanup script not found. Manual cleanup may be required."
        log "WARNING" "Created resources: ${CREATED_RESOURCES[*]}"
    fi
    
    exit 1
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    echo "=========================================="
    echo "AWS Cost Optimization Workflows Deployment"
    echo "=========================================="
    echo
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Check for dry-run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log "INFO" "Running in dry-run mode (validation only)"
        check_prerequisites
        log "SUCCESS" "Dry-run completed successfully"
        exit 0
    fi
    
    # Main deployment flow
    check_prerequisites
    prompt_for_configuration
    setup_environment
    
    log "INFO" "Starting deployment with ID: $DEPLOYMENT_ID"
    
    enable_cost_optimization_hub
    create_sns_topic
    create_budgets
    create_budget_actions_iam
    create_cost_anomaly_detection
    create_lambda_function
    validate_deployment
    save_deployment_info
    
    log "SUCCESS" "Deployment completed successfully!"
}

# Run main function with all arguments
main "$@"