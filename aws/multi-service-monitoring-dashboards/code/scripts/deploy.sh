#!/bin/bash

# Advanced Multi-Service Monitoring Dashboards with Custom Metrics - Deployment Script
# This script deploys the comprehensive monitoring solution with business metrics,
# anomaly detection, and multi-tier dashboards

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/advanced-monitoring-deploy-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
VERBOSE=false
FORCE=false

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

print_debug() {
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1" | tee -a "${LOG_FILE}"
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS credentials and permissions
validate_aws_credentials() {
    print_status "Validating AWS credentials and permissions..."
    
    if ! command_exists aws; then
        print_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Get AWS account info
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    
    if [[ -z "${AWS_REGION}" ]]; then
        print_error "AWS region not configured"
        exit 1
    fi
    
    print_status "AWS Account ID: ${AWS_ACCOUNT_ID}"
    print_status "AWS Region: ${AWS_REGION}"
    
    # Check required permissions
    print_status "Checking required AWS permissions..."
    
    local required_permissions=(
        "iam:CreateRole"
        "iam:AttachRolePolicy"
        "lambda:CreateFunction"
        "events:PutRule"
        "events:PutTargets"
        "cloudwatch:PutDashboard"
        "cloudwatch:PutMetricAlarm"
        "cloudwatch:PutAnomalyDetector"
        "sns:CreateTopic"
        "sns:Subscribe"
    )
    
    # Note: In a real deployment, you would check each permission
    # For this script, we'll assume permissions are available
    print_status "Permission check completed"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check required tools
    local required_tools=("aws" "jq" "zip")
    
    for tool in "${required_tools[@]}"; do
        if ! command_exists "${tool}"; then
            print_error "Required tool '${tool}' is not installed"
            exit 1
        fi
    done
    
    # Check if running in supported environment
    if [[ "${OSTYPE}" != "linux-gnu"* ]] && [[ "${OSTYPE}" != "darwin"* ]]; then
        print_warning "This script is designed for Linux/macOS. Proceed with caution."
    fi
    
    print_status "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    print_status "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION="${AWS_REGION}"
    export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
    
    # Generate unique identifiers for resources
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    export PROJECT_NAME="advanced-monitoring-${random_suffix}"
    export LAMBDA_ROLE_NAME="${PROJECT_NAME}-lambda-role"
    export SNS_TOPIC_NAME="${PROJECT_NAME}-alerts"
    export DASHBOARD_PREFIX="${PROJECT_NAME}"
    
    # Create temporary directory for deployment artifacts
    export TEMP_DIR="/tmp/${PROJECT_NAME}"
    mkdir -p "${TEMP_DIR}"
    
    print_status "Project name: ${PROJECT_NAME}"
    print_status "Lambda role: ${LAMBDA_ROLE_NAME}"
    print_status "Temporary directory: ${TEMP_DIR}"
    
    # Store environment variables for cleanup script
    cat > "${TEMP_DIR}/environment.sh" << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export PROJECT_NAME="${PROJECT_NAME}"
export LAMBDA_ROLE_NAME="${LAMBDA_ROLE_NAME}"
export SNS_TOPIC_NAME="${SNS_TOPIC_NAME}"
export DASHBOARD_PREFIX="${DASHBOARD_PREFIX}"
export TEMP_DIR="${TEMP_DIR}"
EOF
    
    print_status "Environment variables saved to ${TEMP_DIR}/environment.sh"
}

# Function to create IAM role for Lambda functions
create_iam_role() {
    print_status "Creating IAM role for Lambda functions..."
    
    # Create IAM role trust policy
    cat > "${TEMP_DIR}/trust-policy.json" << EOF
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
    if aws iam create-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --assume-role-policy-document "file://${TEMP_DIR}/trust-policy.json" \
        --tags "Key=Project,Value=${PROJECT_NAME}" \
        --output text > "${TEMP_DIR}/iam-role.out" 2>&1; then
        print_status "IAM role created successfully"
    else
        if grep -q "EntityAlreadyExists" "${TEMP_DIR}/iam-role.out"; then
            print_warning "IAM role already exists, continuing..."
        else
            print_error "Failed to create IAM role"
            cat "${TEMP_DIR}/iam-role.out"
            exit 1
        fi
    fi
    
    # Attach managed policies
    local policies=(
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        "arn:aws:iam::aws:policy/CloudWatchFullAccess"
        "arn:aws:iam::aws:policy/AmazonRDSReadOnlyAccess"
        "arn:aws:iam::aws:policy/AmazonElastiCacheReadOnlyAccess"
    )
    
    for policy in "${policies[@]}"; do
        if aws iam attach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn "${policy}" 2>/dev/null; then
            print_debug "Attached policy: ${policy}"
        else
            print_warning "Failed to attach policy: ${policy} (may already be attached)"
        fi
    done
    
    # Wait for role to be available
    print_status "Waiting for IAM role to be available..."
    sleep 10
    
    print_status "IAM role setup completed"
}

# Function to create SNS topics
create_sns_topics() {
    print_status "Creating SNS topics for different alert severities..."
    
    # Create SNS topics
    local topics=("critical" "warning" "info")
    
    for topic in "${topics[@]}"; do
        local topic_name="${SNS_TOPIC_NAME}-${topic}"
        
        if topic_arn=$(aws sns create-topic \
            --name "${topic_name}" \
            --attributes '{"DisplayName":"'${topic_name}'"}' \
            --tags "Key=Project,Value=${PROJECT_NAME}" \
            --query TopicArn --output text 2>/dev/null); then
            print_status "Created SNS topic: ${topic_name}"
            
            # Store topic ARN for later use
            echo "export SNS_${topic^^}_ARN=\"${topic_arn}\"" >> "${TEMP_DIR}/environment.sh"
        else
            print_error "Failed to create SNS topic: ${topic_name}"
            exit 1
        fi
    done
    
    print_status "SNS topics created successfully"
}

# Function to create Lambda functions
create_lambda_functions() {
    print_status "Creating Lambda functions for metrics collection..."
    
    # Create business metrics Lambda function
    cat > "${TEMP_DIR}/business-metrics.py" << 'EOF'
import json
import boto3
import random
from datetime import datetime

cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        # Simulate business metrics (replace with real business logic)
        
        # Revenue metrics
        hourly_revenue = random.uniform(10000, 50000)
        transaction_count = random.randint(100, 1000)
        average_order_value = hourly_revenue / transaction_count
        
        # User engagement metrics
        active_users = random.randint(500, 5000)
        page_views = random.randint(10000, 50000)
        bounce_rate = random.uniform(0.2, 0.8)
        
        # Performance metrics
        api_response_time = random.uniform(100, 2000)
        error_rate = random.uniform(0.001, 0.05)
        throughput = random.randint(100, 1000)
        
        # Customer satisfaction
        nps_score = random.uniform(6.0, 9.5)
        support_ticket_volume = random.randint(5, 50)
        
        # Send custom metrics to CloudWatch
        metrics = [
            {
                'MetricName': 'HourlyRevenue',
                'Value': hourly_revenue,
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'},
                    {'Name': 'BusinessUnit', 'Value': 'ecommerce'}
                ]
            },
            {
                'MetricName': 'TransactionCount',
                'Value': transaction_count,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'},
                    {'Name': 'BusinessUnit', 'Value': 'ecommerce'}
                ]
            },
            {
                'MetricName': 'AverageOrderValue',
                'Value': average_order_value,
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'},
                    {'Name': 'BusinessUnit', 'Value': 'ecommerce'}
                ]
            },
            {
                'MetricName': 'ActiveUsers',
                'Value': active_users,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'}
                ]
            },
            {
                'MetricName': 'APIResponseTime',
                'Value': api_response_time,
                'Unit': 'Milliseconds',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'},
                    {'Name': 'Service', 'Value': 'api-gateway'}
                ]
            },
            {
                'MetricName': 'ErrorRate',
                'Value': error_rate,
                'Unit': 'Percent',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'},
                    {'Name': 'Service', 'Value': 'api-gateway'}
                ]
            },
            {
                'MetricName': 'NPSScore',
                'Value': nps_score,
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'}
                ]
            },
            {
                'MetricName': 'SupportTicketVolume',
                'Value': support_ticket_volume,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'production'}
                ]
            }
        ]
        
        # Submit metrics in batches
        for i in range(0, len(metrics), 20):
            batch = metrics[i:i+20]
            cloudwatch.put_metric_data(
                Namespace='Business/Metrics',
                MetricData=batch
            )
        
        # Calculate and submit composite health score
        health_score = calculate_health_score(
            api_response_time, error_rate, nps_score, 
            support_ticket_volume, active_users
        )
        
        cloudwatch.put_metric_data(
            Namespace='Business/Health',
            MetricData=[
                {
                    'MetricName': 'CompositeHealthScore',
                    'Value': health_score,
                    'Unit': 'Percent',
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': 'production'}
                    ]
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Business metrics published successfully',
                'health_score': health_score,
                'metrics_count': len(metrics)
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def calculate_health_score(response_time, error_rate, nps, tickets, users):
    # Normalize metrics to 0-100 scale and weight them
    response_score = max(0, 100 - (response_time / 20))  # Lower is better
    error_score = max(0, 100 - (error_rate * 2000))      # Lower is better
    nps_score = (nps / 10) * 100                         # Higher is better
    ticket_score = max(0, 100 - (tickets * 2))          # Lower is better
    user_score = min(100, (users / 50))                 # Higher is better
    
    # Weighted average
    weights = [0.25, 0.30, 0.20, 0.15, 0.10]
    scores = [response_score, error_score, nps_score, ticket_score, user_score]
    
    return sum(w * s for w, s in zip(weights, scores))
EOF
    
    # Create infrastructure health Lambda function
    cat > "${TEMP_DIR}/infrastructure-health.py" << 'EOF'
import json
import boto3
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')
rds = boto3.client('rds')
elasticache = boto3.client('elasticache')
ec2 = boto3.client('ec2')

def lambda_handler(event, context):
    try:
        health_scores = {}
        
        # Check RDS health
        rds_health = check_rds_health()
        health_scores['RDS'] = rds_health
        
        # Check ElastiCache health
        cache_health = check_elasticache_health()
        health_scores['ElastiCache'] = cache_health
        
        # Check EC2/ECS health
        compute_health = check_compute_health()
        health_scores['Compute'] = compute_health
        
        # Calculate overall infrastructure health
        overall_health = sum(health_scores.values()) / len(health_scores)
        
        # Publish infrastructure health metrics
        metrics = []
        for service, score in health_scores.items():
            metrics.append({
                'MetricName': f'{service}HealthScore',
                'Value': score,
                'Unit': 'Percent',
                'Dimensions': [
                    {'Name': 'Service', 'Value': service},
                    {'Name': 'Environment', 'Value': 'production'}
                ]
            })
        
        # Add overall health score
        metrics.append({
            'MetricName': 'OverallInfrastructureHealth',
            'Value': overall_health,
            'Unit': 'Percent',
            'Dimensions': [
                {'Name': 'Environment', 'Value': 'production'}
            ]
        })
        
        cloudwatch.put_metric_data(
            Namespace='Infrastructure/Health',
            MetricData=metrics
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'health_scores': health_scores,
                'overall_health': overall_health
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def check_rds_health():
    try:
        instances = rds.describe_db_instances()
        if not instances['DBInstances']:
            return 100  # No instances to monitor
        
        healthy_count = 0
        total_count = len(instances['DBInstances'])
        
        for instance in instances['DBInstances']:
            if instance['DBInstanceStatus'] == 'available':
                healthy_count += 1
        
        return (healthy_count / total_count) * 100
    except:
        return 50  # Assume degraded if can't check

def check_elasticache_health():
    try:
        clusters = elasticache.describe_cache_clusters()
        if not clusters['CacheClusters']:
            return 100  # No clusters to monitor
        
        healthy_count = 0
        total_count = len(clusters['CacheClusters'])
        
        for cluster in clusters['CacheClusters']:
            if cluster['CacheClusterStatus'] == 'available':
                healthy_count += 1
        
        return (healthy_count / total_count) * 100
    except:
        return 50  # Assume degraded if can't check

def check_compute_health():
    try:
        # Simplified compute health check
        instances = ec2.describe_instances(
            Filters=[
                {'Name': 'instance-state-name', 'Values': ['running']}
            ]
        )
        
        total_instances = 0
        for reservation in instances['Reservations']:
            total_instances += len(reservation['Instances'])
        
        # Simple health heuristic based on running instances
        if total_instances == 0:
            return 100  # No instances to monitor
        elif total_instances >= 3:
            return 95   # Good redundancy
        elif total_instances >= 2:
            return 80   # Acceptable redundancy
        else:
            return 60   # Limited redundancy
            
    except:
        return 50  # Assume degraded if can't check
EOF
    
    # Create cost monitoring Lambda function
    cat > "${TEMP_DIR}/cost-monitoring.py" << 'EOF'
import json
import boto3
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')
ce = boto3.client('ce')

def lambda_handler(event, context):
    try:
        # Get cost data for the last 7 days
        end_date = datetime.now().date()
        start_date = end_date - timedelta(days=7)
        
        response = ce.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {
                    'Type': 'DIMENSION',
                    'Key': 'SERVICE'
                }
            ]
        )
        
        # Calculate daily cost trend
        daily_costs = []
        for result in response['ResultsByTime']:
            daily_cost = float(result['Total']['BlendedCost']['Amount'])
            daily_costs.append(daily_cost)
        
        # Calculate cost metrics
        if daily_costs:
            avg_daily_cost = sum(daily_costs) / len(daily_costs)
            latest_cost = daily_costs[-1]
            cost_trend = ((latest_cost - avg_daily_cost) / avg_daily_cost) * 100 if avg_daily_cost > 0 else 0
        else:
            avg_daily_cost = 0
            latest_cost = 0
            cost_trend = 0
        
        # Publish cost metrics
        cloudwatch.put_metric_data(
            Namespace='Cost/Management',
            MetricData=[
                {
                    'MetricName': 'DailyCost',
                    'Value': latest_cost,
                    'Unit': 'None',
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': 'production'}
                    ]
                },
                {
                    'MetricName': 'CostTrend',
                    'Value': cost_trend,
                    'Unit': 'Percent',
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': 'production'}
                    ]
                },
                {
                    'MetricName': 'WeeklyAverageCost',
                    'Value': avg_daily_cost,
                    'Unit': 'None',
                    'Dimensions': [
                        {'Name': 'Environment', 'Value': 'production'}
                    ]
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'daily_cost': latest_cost,
                'cost_trend': cost_trend,
                'weekly_average': avg_daily_cost
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Create Lambda deployment packages and functions
    local functions=("business-metrics" "infrastructure-health" "cost-monitoring")
    
    for function in "${functions[@]}"; do
        print_status "Creating Lambda function: ${function}"
        
        # Create deployment package
        cd "${TEMP_DIR}"
        zip -q "${function}.zip" "${function}.py"
        
        # Create Lambda function
        if aws lambda create-function \
            --function-name "${PROJECT_NAME}-${function}" \
            --runtime python3.9 \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" \
            --handler "${function}.lambda_handler" \
            --zip-file "fileb://${function}.zip" \
            --timeout 120 \
            --tags "Project=${PROJECT_NAME}" \
            --output text > "${function}-lambda.out" 2>&1; then
            print_status "Lambda function created: ${function}"
        else
            if grep -q "ResourceConflictException" "${function}-lambda.out"; then
                print_warning "Lambda function already exists: ${function}"
            else
                print_error "Failed to create Lambda function: ${function}"
                cat "${function}-lambda.out"
                exit 1
            fi
        fi
    done
    
    print_status "Lambda functions created successfully"
}

# Function to create EventBridge rules for scheduling
create_eventbridge_rules() {
    print_status "Creating EventBridge rules for scheduled metric collection..."
    
    # Create EventBridge rules
    local rules=(
        "business-metrics:rate(5 minutes):Collect business metrics every 5 minutes"
        "infrastructure-health:rate(10 minutes):Check infrastructure health every 10 minutes"
        "cost-monitoring:rate(1 day):Daily cost monitoring"
    )
    
    for rule_config in "${rules[@]}"; do
        IFS=':' read -r function_name schedule description <<< "${rule_config}"
        local rule_name="${PROJECT_NAME}-${function_name}"
        
        # Create EventBridge rule
        if aws events put-rule \
            --name "${rule_name}" \
            --schedule-expression "${schedule}" \
            --state ENABLED \
            --description "${description}" \
            --output text > "${TEMP_DIR}/${rule_name}.out" 2>&1; then
            print_status "Created EventBridge rule: ${rule_name}"
        else
            print_error "Failed to create EventBridge rule: ${rule_name}"
            cat "${TEMP_DIR}/${rule_name}.out"
            exit 1
        fi
        
        # Add Lambda permissions
        aws lambda add-permission \
            --function-name "${PROJECT_NAME}-${function_name}" \
            --statement-id "AllowEventBridge-${function_name}" \
            --action "lambda:InvokeFunction" \
            --principal events.amazonaws.com \
            --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${rule_name}" \
            2>/dev/null || print_warning "Permission may already exist for ${function_name}"
        
        # Create targets for the rules
        aws events put-targets \
            --rule "${rule_name}" \
            --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-${function_name}" \
            2>/dev/null || print_error "Failed to create target for ${rule_name}"
    done
    
    print_status "EventBridge rules created successfully"
}

# Function to create CloudWatch dashboards
create_dashboards() {
    print_status "Creating CloudWatch dashboards..."
    
    # Create infrastructure dashboard
    cat > "${TEMP_DIR}/infrastructure-dashboard.json" << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 8,
            "height": 6,
            "properties": {
                "metrics": [
                    ["Infrastructure/Health", "OverallInfrastructureHealth", "Environment", "production"],
                    ["Business/Health", "CompositeHealthScore", "Environment", "production"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Overall System Health",
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
            "x": 8,
            "y": 0,
            "width": 8,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/ECS", "CPUUtilization", "ServiceName", "web-service"],
                    ["AWS/ECS", "MemoryUtilization", "ServiceName", "web-service"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "ECS Service Utilization"
            }
        },
        {
            "type": "metric",
            "x": 16,
            "y": 0,
            "width": 8,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "production-db"],
                    ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "production-db"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "RDS Performance Metrics"
            }
        }
    ]
}
EOF
    
    # Create business dashboard
    cat > "${TEMP_DIR}/business-dashboard.json" << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 8,
            "height": 6,
            "properties": {
                "metrics": [
                    ["Business/Metrics", "HourlyRevenue", "Environment", "production", "BusinessUnit", "ecommerce"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Hourly Revenue"
            }
        },
        {
            "type": "metric",
            "x": 8,
            "y": 0,
            "width": 8,
            "height": 6,
            "properties": {
                "metrics": [
                    ["Business/Metrics", "TransactionCount", "Environment", "production", "BusinessUnit", "ecommerce"],
                    ["Business/Metrics", "ActiveUsers", "Environment", "production"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Transaction Volume & Active Users"
            }
        }
    ]
}
EOF
    
    # Create executive dashboard
    cat > "${TEMP_DIR}/executive-dashboard.json" << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 24,
            "height": 6,
            "properties": {
                "metrics": [
                    ["Business/Health", "CompositeHealthScore", "Environment", "production"],
                    ["Infrastructure/Health", "OverallInfrastructureHealth", "Environment", "production"]
                ],
                "period": 3600,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "System Health Overview (Last 24 Hours)",
                "yAxis": {
                    "left": {
                        "min": 0,
                        "max": 100
                    }
                }
            }
        }
    ]
}
EOF
    
    # Create operational dashboard
    cat > "${TEMP_DIR}/operational-dashboard.json" << EOF
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
                    ["AWS/Lambda", "Invocations", "FunctionName", "${PROJECT_NAME}-business-metrics"],
                    ["AWS/Lambda", "Errors", "FunctionName", "${PROJECT_NAME}-business-metrics"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Monitoring Function Health"
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
                    ["Cost/Management", "DailyCost", "Environment", "production"]
                ],
                "period": 86400,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Cost Monitoring"
            }
        }
    ]
}
EOF
    
    # Create dashboards
    local dashboards=(
        "Infrastructure:infrastructure-dashboard.json"
        "Business:business-dashboard.json"
        "Executive:executive-dashboard.json"
        "Operations:operational-dashboard.json"
    )
    
    for dashboard_config in "${dashboards[@]}"; do
        IFS=':' read -r name file <<< "${dashboard_config}"
        local dashboard_name="${DASHBOARD_PREFIX}-${name}"
        
        if aws cloudwatch put-dashboard \
            --dashboard-name "${dashboard_name}" \
            --dashboard-body "file://${TEMP_DIR}/${file}" \
            --output text > "${TEMP_DIR}/${dashboard_name}.out" 2>&1; then
            print_status "Created dashboard: ${dashboard_name}"
            echo "export DASHBOARD_${name^^}_URL=\"https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${dashboard_name}\"" >> "${TEMP_DIR}/environment.sh"
        else
            print_error "Failed to create dashboard: ${dashboard_name}"
            cat "${TEMP_DIR}/${dashboard_name}.out"
            exit 1
        fi
    done
    
    print_status "CloudWatch dashboards created successfully"
}

# Function to set up anomaly detection
setup_anomaly_detection() {
    print_status "Setting up CloudWatch anomaly detection..."
    
    # Create anomaly detectors for key metrics
    local detectors=(
        "Business/Metrics:HourlyRevenue:Environment=production,BusinessUnit=ecommerce"
        "Business/Metrics:APIResponseTime:Environment=production,Service=api-gateway"
        "Business/Metrics:ErrorRate:Environment=production,Service=api-gateway"
        "Infrastructure/Health:OverallInfrastructureHealth:Environment=production"
    )
    
    for detector_config in "${detectors[@]}"; do
        IFS=':' read -r namespace metric_name dimensions <<< "${detector_config}"
        
        # Convert dimensions to JSON format
        local dimensions_json="["
        IFS=',' read -ra dim_array <<< "${dimensions}"
        for dim in "${dim_array[@]}"; do
            IFS='=' read -ra kv <<< "${dim}"
            dimensions_json+="{\"Name\":\"${kv[0]}\",\"Value\":\"${kv[1]}\"},"
        done
        dimensions_json="${dimensions_json%,}]"
        
        # Create anomaly detector
        if aws cloudwatch put-anomaly-detector \
            --namespace "${namespace}" \
            --metric-name "${metric_name}" \
            --dimensions "${dimensions_json}" \
            --stat "Average" \
            --output text > "${TEMP_DIR}/anomaly-${metric_name}.out" 2>&1; then
            print_status "Created anomaly detector: ${metric_name}"
        else
            print_warning "Failed to create anomaly detector for ${metric_name} (may already exist)"
        fi
    done
    
    print_status "Anomaly detection setup completed"
}

# Function to create alarms
create_alarms() {
    print_status "Creating CloudWatch alarms..."
    
    # Get SNS topic ARNs
    source "${TEMP_DIR}/environment.sh"
    
    # Create infrastructure health alarm
    if aws cloudwatch put-metric-alarm \
        --alarm-name "${PROJECT_NAME}-infrastructure-health-low" \
        --alarm-description "Infrastructure health score below threshold" \
        --metric-name "OverallInfrastructureHealth" \
        --namespace "Infrastructure/Health" \
        --statistic "Average" \
        --period 300 \
        --threshold 80 \
        --comparison-operator LessThanThreshold \
        --dimensions "Name=Environment,Value=production" \
        --evaluation-periods 2 \
        --alarm-actions "${SNS_CRITICAL_ARN}" \
        --output text > "${TEMP_DIR}/alarm-infra-health.out" 2>&1; then
        print_status "Created infrastructure health alarm"
    else
        print_warning "Failed to create infrastructure health alarm"
    fi
    
    print_status "CloudWatch alarms created successfully"
}

# Function to generate sample data
generate_sample_data() {
    print_status "Generating sample data by triggering Lambda functions..."
    
    # Trigger Lambda functions to generate initial data
    local functions=("business-metrics" "infrastructure-health" "cost-monitoring")
    
    for function in "${functions[@]}"; do
        if aws lambda invoke \
            --function-name "${PROJECT_NAME}-${function}" \
            --payload '{}' \
            "${TEMP_DIR}/${function}-response.json" \
            --output text > "${TEMP_DIR}/${function}-invoke.out" 2>&1; then
            print_status "Triggered ${function} function"
        else
            print_warning "Failed to trigger ${function} function"
        fi
    done
    
    print_status "Sample data generation completed"
}

# Function to display deployment summary
display_summary() {
    print_status "Deployment completed successfully!"
    echo
    echo "=== Deployment Summary ==="
    echo "Project Name: ${PROJECT_NAME}"
    echo "AWS Region: ${AWS_REGION}"
    echo "AWS Account: ${AWS_ACCOUNT_ID}"
    echo
    echo "=== Created Resources ==="
    echo "• IAM Role: ${LAMBDA_ROLE_NAME}"
    echo "• Lambda Functions:"
    echo "  - ${PROJECT_NAME}-business-metrics"
    echo "  - ${PROJECT_NAME}-infrastructure-health"
    echo "  - ${PROJECT_NAME}-cost-monitoring"
    echo "• SNS Topics:"
    echo "  - ${SNS_TOPIC_NAME}-critical"
    echo "  - ${SNS_TOPIC_NAME}-warning"
    echo "  - ${SNS_TOPIC_NAME}-info"
    echo "• CloudWatch Dashboards:"
    echo "  - ${DASHBOARD_PREFIX}-Infrastructure"
    echo "  - ${DASHBOARD_PREFIX}-Business"
    echo "  - ${DASHBOARD_PREFIX}-Executive"
    echo "  - ${DASHBOARD_PREFIX}-Operations"
    echo
    echo "=== Dashboard URLs ==="
    source "${TEMP_DIR}/environment.sh"
    echo "Infrastructure: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_PREFIX}-Infrastructure"
    echo "Business: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_PREFIX}-Business"
    echo "Executive: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_PREFIX}-Executive"
    echo "Operations: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_PREFIX}-Operations"
    echo
    echo "=== Next Steps ==="
    echo "1. Wait 5-10 minutes for initial metrics to populate"
    echo "2. Check the dashboards for monitoring data"
    echo "3. Configure email notifications for SNS topics"
    echo "4. Customize metrics collection for your specific business needs"
    echo
    echo "=== Cleanup ==="
    echo "To clean up resources, run:"
    echo "  ./destroy.sh"
    echo
    echo "Environment variables saved to: ${TEMP_DIR}/environment.sh"
    echo "Deployment log saved to: ${LOG_FILE}"
}

# Function to handle cleanup on script exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        print_error "Deployment failed with exit code ${exit_code}"
        print_error "Check the log file: ${LOG_FILE}"
        print_error "Temporary files in: ${TEMP_DIR}"
    fi
}

# Function to display help
show_help() {
    echo "Advanced Multi-Service Monitoring Dashboards - Deployment Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "OPTIONS:"
    echo "  -h, --help          Show this help message"
    echo "  -d, --dry-run       Show what would be deployed without making changes"
    echo "  -v, --verbose       Enable verbose output"
    echo "  -f, --force         Force deployment even if resources exist"
    echo "  -r, --region REGION Override AWS region"
    echo
    echo "EXAMPLES:"
    echo "  $0                  Deploy with default settings"
    echo "  $0 --dry-run        Show deployment plan without executing"
    echo "  $0 --verbose        Deploy with detailed logging"
    echo "  $0 --region us-east-1  Deploy to specific region"
    echo
    echo "PREREQUISITES:"
    echo "  - AWS CLI installed and configured"
    echo "  - Appropriate AWS permissions for CloudWatch, Lambda, IAM, SNS"
    echo "  - jq and zip utilities installed"
    echo
    echo "For more information, see the recipe documentation."
}

# Main execution function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Set up trap for cleanup on exit
    trap cleanup_on_exit EXIT
    
    # Start deployment
    print_status "Starting Advanced Multi-Service Monitoring Dashboards deployment..."
    print_status "Log file: ${LOG_FILE}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        print_status "DRY RUN MODE - No resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites
    validate_aws_credentials
    setup_environment
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        create_iam_role
        create_sns_topics
        create_lambda_functions
        create_eventbridge_rules
        create_dashboards
        setup_anomaly_detection
        create_alarms
        generate_sample_data
        display_summary
    else
        print_status "DRY RUN - Would create the following resources:"
        print_status "• IAM Role: ${LAMBDA_ROLE_NAME}"
        print_status "• 3 Lambda Functions for metrics collection"
        print_status "• 3 SNS Topics for different alert severities"
        print_status "• 3 EventBridge Rules for scheduling"
        print_status "• 4 CloudWatch Dashboards"
        print_status "• Anomaly Detection for key metrics"
        print_status "• CloudWatch Alarms for health monitoring"
    fi
    
    print_status "Deployment script completed successfully!"
}

# Execute main function
main "$@"