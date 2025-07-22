#!/bin/bash

# Cost-Aware Resource Lifecycle Deployment Script
# Deploys MemoryDB cluster with EventBridge Scheduler and Lambda-based cost optimization
# Version: 1.0

set -euo pipefail

# Enable debug mode if requested
if [[ "${DEBUG:-false}" == "true" ]]; then
    set -x
fi

# Color codes for output
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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEMP_DIR="/tmp/memorydb-cost-optimization-$$"
readonly LOG_FILE="/tmp/memorydb-deployment-$(date +%Y%m%d-%H%M%S).log"

# Default values
DRY_RUN=${DRY_RUN:-false}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}
BUDGET_EMAIL=${BUDGET_EMAIL:-admin@example.com}
COST_THRESHOLD=${COST_THRESHOLD:-100}

# Cleanup function
cleanup() {
    local exit_code=$?
    log_info "Cleaning up temporary resources..."
    rm -rf "${TEMP_DIR}" 2>/dev/null || true
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "Deployment completed successfully. Log file: ${LOG_FILE}"
    else
        log_error "Deployment failed with exit code $exit_code. Check log file: ${LOG_FILE}"
    fi
    
    exit $exit_code
}

trap cleanup EXIT

# Initialize logging
exec > >(tee -a "${LOG_FILE}")
exec 2>&1

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI and configure credentials."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid. Please run 'aws configure'."
        exit 1
    fi
    
    # Check required AWS CLI version (minimum 2.0.0)
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ "$(printf '%s\n' "2.0.0" "$aws_version" | sort -V | head -n1)" != "2.0.0" ]]; then
        log_error "AWS CLI version 2.0.0 or higher required. Current version: $aws_version"
        exit 1
    fi
    
    # Check required permissions (basic check)
    local required_services=("memorydb" "lambda" "scheduler" "iam" "ce" "budgets")
    for service in "${required_services[@]}"; do
        if [[ "$service" == "ce" ]]; then
            # Cost Explorer check
            if ! aws ce get-cost-and-usage --time-period Start=2025-07-01,End=2025-07-12 --granularity MONTHLY --metrics BlendedCost &> /dev/null; then
                log_warning "Cost Explorer access may be limited. Some cost features may not work."
            fi
        elif [[ "$service" == "budgets" ]]; then
            # Budgets check
            if ! aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text) --max-results 1 &> /dev/null; then
                log_warning "Budgets access may be limited. Budget alerts may not work."
            fi
        else
            # General service check
            if ! aws $service help &> /dev/null; then
                log_error "AWS CLI does not support $service service or insufficient permissions."
                exit 1
            fi
        fi
    done
    
    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. JSON output may be less readable."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
        exit 1
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            echo "$(date +%s | tail -c 6)")
    fi
    
    # Set resource names
    export CLUSTER_NAME="cost-aware-memorydb-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="memorydb-cost-optimizer-${RANDOM_SUFFIX}"
    export SCHEDULER_GROUP_NAME="cost-optimization-schedules-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="memorydb-cost-optimizer-role-${RANDOM_SUFFIX}"
    
    log_success "Environment configured:"
    log_info "  AWS Region: $AWS_REGION"
    log_info "  AWS Account: $AWS_ACCOUNT_ID"
    log_info "  Random Suffix: $RANDOM_SUFFIX"
    log_info "  Cluster Name: $CLUSTER_NAME"
    log_info "  Lambda Function: $LAMBDA_FUNCTION_NAME"
}

# Function to create IAM resources
create_iam_resources() {
    log_info "Creating IAM resources..."
    
    # Check if Lambda role already exists
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &> /dev/null; then
        log_warning "IAM role $IAM_ROLE_NAME already exists. Skipping creation."
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would create IAM role: $IAM_ROLE_NAME"
        else
            # Create Lambda execution role
            aws iam create-role \
                --role-name "$IAM_ROLE_NAME" \
                --assume-role-policy-document '{
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
                }' \
                --description "Role for MemoryDB cost optimization Lambda function"
            
            log_success "Created IAM role: $IAM_ROLE_NAME"
        fi
    fi
    
    # Attach basic Lambda execution policy
    if [[ "$DRY_RUN" == "false" ]]; then
        aws iam attach-role-policy \
            --role-name "$IAM_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
            2>/dev/null || log_warning "Basic execution role already attached"
    fi
    
    # Create custom policy for cost optimization
    local policy_name="memorydb-cost-optimizer-policy-${RANDOM_SUFFIX}"
    if aws iam get-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$policy_name" &> /dev/null; then
        log_warning "Custom policy $policy_name already exists. Skipping creation."
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would create custom IAM policy: $policy_name"
        else
            aws iam create-policy \
                --policy-name "$policy_name" \
                --policy-document '{
                    "Version": "2012-10-17",
                    "Statement": [
                        {
                            "Effect": "Allow",
                            "Action": [
                                "memorydb:DescribeClusters",
                                "memorydb:ModifyCluster",
                                "memorydb:DescribeSubnetGroups",
                                "memorydb:DescribeParameterGroups"
                            ],
                            "Resource": "*"
                        },
                        {
                            "Effect": "Allow",
                            "Action": [
                                "ce:GetCostAndUsage",
                                "ce:GetUsageReport",
                                "ce:GetDimensionValues",
                                "budgets:ViewBudget"
                            ],
                            "Resource": "*"
                        },
                        {
                            "Effect": "Allow",
                            "Action": [
                                "cloudwatch:PutMetricData",
                                "cloudwatch:GetMetricStatistics"
                            ],
                            "Resource": "*"
                        },
                        {
                            "Effect": "Allow",
                            "Action": [
                                "scheduler:GetSchedule",
                                "scheduler:UpdateSchedule"
                            ],
                            "Resource": "*"
                        }
                    ]
                }' \
                --description "Custom policy for MemoryDB cost optimization operations"
            
            log_success "Created custom IAM policy: $policy_name"
        fi
    fi
    
    # Attach custom policy to role
    if [[ "$DRY_RUN" == "false" ]]; then
        aws iam attach-role-policy \
            --role-name "$IAM_ROLE_NAME" \
            --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$policy_name" \
            2>/dev/null || log_warning "Custom policy already attached"
    fi
}

# Function to create MemoryDB cluster
create_memorydb_cluster() {
    log_info "Creating MemoryDB cluster..."
    
    # Check if cluster already exists
    if aws memorydb describe-clusters --cluster-name "$CLUSTER_NAME" &> /dev/null; then
        log_warning "MemoryDB cluster $CLUSTER_NAME already exists. Skipping creation."
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create MemoryDB cluster: $CLUSTER_NAME"
        return 0
    fi
    
    # Create subnet group
    local subnet_group_name="${CLUSTER_NAME}-subnet-group"
    if ! aws memorydb describe-subnet-groups --subnet-group-name "$subnet_group_name" &> /dev/null; then
        log_info "Creating subnet group: $subnet_group_name"
        
        # Get default VPC subnets
        local subnets=$(aws ec2 describe-subnets \
            --filters "Name=default-for-az,Values=true" \
            --query "Subnets[0:2].SubnetId" \
            --output text)
        
        if [[ -z "$subnets" ]]; then
            log_error "No default subnets found. Please ensure you have a default VPC."
            exit 1
        fi
        
        aws memorydb create-subnet-group \
            --subnet-group-name "$subnet_group_name" \
            --description "Subnet group for cost-aware MemoryDB cluster" \
            --subnet-ids $subnets
        
        log_success "Created subnet group: $subnet_group_name"
    fi
    
    # Get default security group
    local security_group=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=default" \
        --query "SecurityGroups[0].GroupId" \
        --output text)
    
    if [[ -z "$security_group" || "$security_group" == "None" ]]; then
        log_error "No default security group found."
        exit 1
    fi
    
    # Create MemoryDB cluster
    log_info "Creating MemoryDB cluster with cost-optimized configuration..."
    aws memorydb create-cluster \
        --cluster-name "$CLUSTER_NAME" \
        --node-type db.t4g.small \
        --num-shards 1 \
        --num-replicas-per-shard 0 \
        --subnet-group-name "$subnet_group_name" \
        --security-group-ids "$security_group" \
        --maintenance-window "sun:03:00-sun:04:00" \
        --description "Cost-aware MemoryDB cluster for optimization testing"
    
    log_success "Initiated MemoryDB cluster creation: $CLUSTER_NAME"
    
    # Wait for cluster to become available
    log_info "Waiting for MemoryDB cluster to become available (this may take 10-15 minutes)..."
    local timeout=1200  # 20 minutes
    local elapsed=0
    local interval=30
    
    while [[ $elapsed -lt $timeout ]]; do
        local status=$(aws memorydb describe-clusters \
            --cluster-name "$CLUSTER_NAME" \
            --query "Clusters[0].Status" \
            --output text 2>/dev/null || echo "unknown")
        
        case "$status" in
            "available")
                log_success "MemoryDB cluster is now available"
                return 0
                ;;
            "creating"|"snapshotting")
                log_info "Cluster status: $status (waiting ${interval}s...)"
                sleep $interval
                elapsed=$((elapsed + interval))
                ;;
            "unknown")
                log_warning "Unable to check cluster status. Continuing..."
                sleep $interval
                elapsed=$((elapsed + interval))
                ;;
            *)
                log_error "Unexpected cluster status: $status"
                exit 1
                ;;
        esac
    done
    
    log_error "Timeout waiting for MemoryDB cluster to become available"
    exit 1
}

# Function to create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function for cost optimization..."
    
    # Check if function already exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        log_warning "Lambda function $LAMBDA_FUNCTION_NAME already exists. Updating code..."
        local update_function=true
    else
        local update_function=false
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create/update Lambda function: $LAMBDA_FUNCTION_NAME"
        return 0
    fi
    
    # Create temporary directory for Lambda package
    mkdir -p "$TEMP_DIR/lambda"
    
    # Create Lambda function code
    cat > "$TEMP_DIR/lambda/lambda_function.py" << 'EOF'
import json
import boto3
import datetime
import logging
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

memorydb = boto3.client('memorydb')
ce = boto3.client('ce')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Intelligent cost-aware MemoryDB cluster management.
    Analyzes cost patterns and adjusts cluster configuration based on thresholds.
    """
    
    cluster_name = event.get('cluster_name')
    action = event.get('action', 'analyze')
    cost_threshold = event.get('cost_threshold', 100.0)
    
    if not cluster_name:
        return {
            'statusCode': 400,
            'body': {'error': 'cluster_name is required'}
        }
    
    try:
        # Get current cluster status
        cluster_response = memorydb.describe_clusters(ClusterName=cluster_name)
        if not cluster_response['Clusters']:
            return {
                'statusCode': 404,
                'body': {'error': f'Cluster {cluster_name} not found'}
            }
            
        cluster = cluster_response['Clusters'][0]
        current_node_type = cluster['NodeType']
        current_shards = cluster['NumberOfShards']
        cluster_status = cluster['Status']
        
        # Only proceed if cluster is available
        if cluster_status != 'available':
            logger.warning(f"Cluster {cluster_name} is not available, status: {cluster_status}")
            return {
                'statusCode': 200,
                'body': {'message': f'Cluster not available for modification, status: {cluster_status}'}
            }
        
        # Analyze recent cost trends
        cost_data = get_cost_analysis()
        memorydb_cost = cost_data['total_cost']
        
        # Determine scaling action based on cost analysis
        scaling_recommendation = analyze_scaling_needs(
            memorydb_cost, cost_threshold, current_node_type, action
        )
        
        # Execute scaling if recommended and cluster is available
        if scaling_recommendation['action'] != 'none' and cluster_status == 'available':
            modify_result = modify_cluster(cluster_name, scaling_recommendation)
            scaling_recommendation['execution_result'] = modify_result
        
        # Send metrics to CloudWatch
        send_cloudwatch_metrics(cluster_name, memorydb_cost, scaling_recommendation)
        
        return {
            'statusCode': 200,
            'body': {
                'cluster_name': cluster_name,
                'current_cost': memorydb_cost,
                'current_node_type': current_node_type,
                'recommendation': scaling_recommendation,
                'timestamp': datetime.datetime.now().isoformat()
            }
        }
        
    except Exception as e:
        logger.error(f"Error in cost optimization: {str(e)}")
        return {
            'statusCode': 500,
            'body': {'error': str(e)}
        }

def get_cost_analysis() -> Dict[str, float]:
    """Retrieve and analyze recent MemoryDB costs."""
    try:
        end_date = datetime.datetime.now()
        start_date = end_date - datetime.timedelta(days=7)
        
        cost_response = ce.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'},
            ]
        )
        
        # Calculate MemoryDB costs
        memorydb_cost = 0.0
        for result_by_time in cost_response['ResultsByTime']:
            for group in result_by_time['Groups']:
                if 'MemoryDB' in group['Keys'][0] or 'ElastiCache' in group['Keys'][0]:
                    memorydb_cost += float(group['Metrics']['BlendedCost']['Amount'])
        
        return {'total_cost': memorydb_cost}
        
    except Exception as e:
        logger.warning(f"Could not retrieve cost data: {str(e)}")
        return {'total_cost': 0.0}

def analyze_scaling_needs(cost: float, threshold: float, node_type: str, action: str) -> Dict[str, Any]:
    """Analyze cost patterns and recommend scaling actions."""
    
    if action == 'scale_down' and cost > threshold:
        # Business hours ended, scale down for cost savings
        if 'large' in node_type:
            return {
                'action': 'modify_node_type',
                'target_node_type': node_type.replace('large', 'small'),
                'reason': 'Off-peak cost optimization',
                'estimated_savings': '30-40%'
            }
        elif 'medium' in node_type:
            return {
                'action': 'modify_node_type',
                'target_node_type': node_type.replace('medium', 'small'),
                'reason': 'Off-peak cost optimization',
                'estimated_savings': '20-30%'
            }
    elif action == 'scale_up':
        # Business hours starting, scale up for performance
        if 'small' in node_type:
            return {
                'action': 'modify_node_type',
                'target_node_type': node_type.replace('small', 'medium'),
                'reason': 'Business hours performance optimization',
                'estimated_impact': 'Improved performance for business workloads'
            }
    
    return {'action': 'none', 'reason': 'No scaling needed based on current conditions'}

def modify_cluster(cluster_name: str, recommendation: Dict[str, Any]) -> Dict[str, str]:
    """Execute cluster modifications based on recommendations."""
    
    try:
        if recommendation['action'] == 'modify_node_type':
            response = memorydb.modify_cluster(
                ClusterName=cluster_name,
                NodeType=recommendation['target_node_type']
            )
            
            logger.info(f"Initiated cluster modification: {cluster_name} -> {recommendation['target_node_type']}")
            return {
                'status': 'initiated',
                'message': f"Cluster modification started to {recommendation['target_node_type']}"
            }
            
    except Exception as e:
        logger.error(f"Failed to modify cluster {cluster_name}: {str(e)}")
        return {
            'status': 'failed',
            'message': f"Cluster modification failed: {str(e)}"
        }

def send_cloudwatch_metrics(cluster_name: str, cost: float, recommendation: Dict[str, Any]) -> None:
    """Send cost optimization metrics to CloudWatch."""
    
    try:
        cloudwatch.put_metric_data(
            Namespace='MemoryDB/CostOptimization',
            MetricData=[
                {
                    'MetricName': 'WeeklyCost',
                    'Value': cost,
                    'Unit': 'None',
                    'Dimensions': [
                        {'Name': 'ClusterName', 'Value': cluster_name}
                    ]
                },
                {
                    'MetricName': 'OptimizationAction',
                    'Value': 1 if recommendation['action'] != 'none' else 0,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'ClusterName', 'Value': cluster_name}
                    ]
                }
            ]
        )
    except Exception as e:
        logger.warning(f"Failed to send CloudWatch metrics: {str(e)}")
EOF
    
    # Create deployment package
    cd "$TEMP_DIR/lambda"
    zip -r ../lambda-function.zip . > /dev/null
    cd - > /dev/null
    
    # Wait for IAM role propagation
    if [[ "$update_function" == "false" ]]; then
        log_info "Waiting for IAM role propagation..."
        sleep 10
    fi
    
    if [[ "$update_function" == "true" ]]; then
        # Update existing function
        aws lambda update-function-code \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --zip-file "fileb://$TEMP_DIR/lambda-function.zip"
        
        log_success "Updated Lambda function code: $LAMBDA_FUNCTION_NAME"
    else
        # Create new function
        aws lambda create-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --runtime python3.9 \
            --role "arn:aws:iam::$AWS_ACCOUNT_ID:role/$IAM_ROLE_NAME" \
            --handler lambda_function.lambda_handler \
            --zip-file "fileb://$TEMP_DIR/lambda-function.zip" \
            --timeout 300 \
            --memory-size 256 \
            --description "Cost-aware MemoryDB cluster lifecycle management" \
            --environment "Variables={LOG_LEVEL=INFO}"
        
        log_success "Created Lambda function: $LAMBDA_FUNCTION_NAME"
    fi
}

# Function to create EventBridge Scheduler resources
create_scheduler_resources() {
    log_info "Creating EventBridge Scheduler resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create EventBridge Scheduler resources"
        return 0
    fi
    
    # Create scheduler group
    if ! aws scheduler get-schedule-group --name "$SCHEDULER_GROUP_NAME" &> /dev/null; then
        aws scheduler create-schedule-group \
            --name "$SCHEDULER_GROUP_NAME" \
            --description "Cost optimization schedules for MemoryDB lifecycle management"
        
        log_success "Created scheduler group: $SCHEDULER_GROUP_NAME"
    else
        log_warning "Scheduler group $SCHEDULER_GROUP_NAME already exists"
    fi
    
    # Create IAM role for EventBridge Scheduler
    local scheduler_role_name="eventbridge-scheduler-role-${RANDOM_SUFFIX}"
    if ! aws iam get-role --role-name "$scheduler_role_name" &> /dev/null; then
        aws iam create-role \
            --role-name "$scheduler_role_name" \
            --assume-role-policy-document '{
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
            }' \
            --description "Role for EventBridge Scheduler to invoke Lambda functions"
        
        # Create and attach policy for Lambda invocation
        local scheduler_policy_name="scheduler-lambda-invoke-policy-${RANDOM_SUFFIX}"
        aws iam create-policy \
            --policy-name "$scheduler_policy_name" \
            --policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Action": "lambda:InvokeFunction",
                        "Resource": "arn:aws:lambda:'$AWS_REGION':'$AWS_ACCOUNT_ID':function:'$LAMBDA_FUNCTION_NAME'"
                    }
                ]
            }' \
            --description "Policy for EventBridge Scheduler to invoke cost optimization Lambda"
        
        aws iam attach-role-policy \
            --role-name "$scheduler_role_name" \
            --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$scheduler_policy_name"
        
        log_success "Created EventBridge Scheduler IAM role: $scheduler_role_name"
        
        # Wait for role propagation
        log_info "Waiting for IAM role propagation..."
        sleep 10
    else
        log_warning "EventBridge Scheduler role $scheduler_role_name already exists"
    fi
    
    # Create schedules
    local schedules=(
        "memorydb-business-hours-start-${RANDOM_SUFFIX}:cron(0 8 ? * MON-FRI *):scale_up:Scale up MemoryDB for business hours performance"
        "memorydb-business-hours-end-${RANDOM_SUFFIX}:cron(0 18 ? * MON-FRI *):scale_down:Scale down MemoryDB for cost optimization during off-hours"
        "memorydb-weekly-cost-analysis-${RANDOM_SUFFIX}:cron(0 9 ? * MON *):analyze:Weekly MemoryDB cost analysis and optimization review"
    )
    
    for schedule_def in "${schedules[@]}"; do
        IFS=':' read -r schedule_name cron_expr action description <<< "$schedule_def"
        
        if aws scheduler get-schedule --name "$schedule_name" --group-name "$SCHEDULER_GROUP_NAME" &> /dev/null; then
            log_warning "Schedule $schedule_name already exists. Skipping creation."
            continue
        fi
        
        local cost_threshold_val="100"
        if [[ "$action" == "scale_down" ]]; then
            cost_threshold_val="50"
        elif [[ "$action" == "analyze" ]]; then
            cost_threshold_val="150"
        fi
        
        aws scheduler create-schedule \
            --name "$schedule_name" \
            --group-name "$SCHEDULER_GROUP_NAME" \
            --schedule-expression "$cron_expr" \
            --target '{
                "Arn": "arn:aws:lambda:'$AWS_REGION':'$AWS_ACCOUNT_ID':function:'$LAMBDA_FUNCTION_NAME'",
                "RoleArn": "arn:aws:iam::'$AWS_ACCOUNT_ID':role/'$scheduler_role_name'",
                "Input": "{\"cluster_name\": \"'$CLUSTER_NAME'\", \"action\": \"'$action'\", \"cost_threshold\": '$cost_threshold_val'}"
            }' \
            --flexible-time-window '{"Mode": "OFF"}' \
            --description "$description"
        
        log_success "Created schedule: $schedule_name"
    done
}

# Function to create cost monitoring
create_cost_monitoring() {
    log_info "Setting up cost monitoring and budget alerts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create cost monitoring resources"
        return 0
    fi
    
    # Create budget for MemoryDB cost monitoring
    local budget_name="MemoryDB-Cost-Budget-${RANDOM_SUFFIX}"
    
    # Check if budget already exists
    if aws budgets describe-budget --account-id "$AWS_ACCOUNT_ID" --budget-name "$budget_name" &> /dev/null; then
        log_warning "Budget $budget_name already exists. Skipping creation."
    else
        aws budgets create-budget \
            --account-id "$AWS_ACCOUNT_ID" \
            --budget '{
                "BudgetName": "'$budget_name'",
                "BudgetLimit": {
                    "Amount": "200",
                    "Unit": "USD"
                },
                "TimeUnit": "MONTHLY",
                "BudgetType": "COST",
                "CostFilters": {
                    "Service": ["Amazon MemoryDB for Redis"]
                },
                "TimePeriod": {
                    "Start": "2025-07-01",
                    "End": "2025-12-31"
                }
            }' \
            --notifications-with-subscribers '[
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
                            "Address": "'$BUDGET_EMAIL'"
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
                            "Address": "'$BUDGET_EMAIL'"
                        }
                    ]
                }
            ]'
        
        log_success "Created budget with email notifications: $budget_name"
    fi
    
    # Create CloudWatch dashboard
    local dashboard_name="MemoryDB-Cost-Optimization-${RANDOM_SUFFIX}"
    aws cloudwatch put-dashboard \
        --dashboard-name "$dashboard_name" \
        --dashboard-body '{
            "widgets": [
                {
                    "type": "metric",
                    "x": 0, "y": 0, "width": 12, "height": 6,
                    "properties": {
                        "metrics": [
                            ["MemoryDB/CostOptimization", "WeeklyCost", "ClusterName", "'$CLUSTER_NAME'"],
                            [".", "OptimizationAction", ".", "."]
                        ],
                        "period": 86400,
                        "stat": "Average",
                        "region": "'$AWS_REGION'",
                        "title": "MemoryDB Cost Optimization Metrics",
                        "yAxis": {
                            "left": {"min": 0}
                        }
                    }
                },
                {
                    "type": "metric",
                    "x": 12, "y": 0, "width": 12, "height": 6,
                    "properties": {
                        "metrics": [
                            ["AWS/MemoryDB", "CPUUtilization", "ClusterName", "'$CLUSTER_NAME'"],
                            [".", "NetworkBytesIn", ".", "."],
                            [".", "NetworkBytesOut", ".", "."]
                        ],
                        "period": 300,
                        "stat": "Average",
                        "region": "'$AWS_REGION'",
                        "title": "MemoryDB Performance Metrics"
                    }
                },
                {
                    "type": "metric",
                    "x": 0, "y": 6, "width": 24, "height": 6,
                    "properties": {
                        "metrics": [
                            ["AWS/Lambda", "Duration", "FunctionName", "'$LAMBDA_FUNCTION_NAME'"],
                            [".", "Errors", ".", "."],
                            [".", "Invocations", ".", "."]
                        ],
                        "period": 300,
                        "stat": "Average",
                        "region": "'$AWS_REGION'",
                        "title": "Cost Optimization Lambda Metrics"
                    }
                }
            ]
        }'
    
    log_success "Created CloudWatch dashboard: $dashboard_name"
    
    # Create cost optimization alarms
    aws cloudwatch put-metric-alarm \
        --alarm-name "MemoryDB-Weekly-Cost-High-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when MemoryDB weekly costs exceed threshold" \
        --metric-name WeeklyCost \
        --namespace MemoryDB/CostOptimization \
        --statistic Average \
        --period 604800 \
        --threshold 150 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --dimensions Name=ClusterName,Value="$CLUSTER_NAME" \
        --treat-missing-data notBreaching
    
    # Create Lambda error alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "MemoryDB-Optimizer-Lambda-Errors-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when cost optimization Lambda function has errors" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 2 \
        --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME"
    
    log_success "Created CloudWatch alarms for monitoring"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check MemoryDB cluster
    local cluster_status=$(aws memorydb describe-clusters \
        --cluster-name "$CLUSTER_NAME" \
        --query 'Clusters[0].Status' \
        --output text 2>/dev/null || echo "not-found")
    
    if [[ "$cluster_status" == "available" ]]; then
        log_success "MemoryDB cluster is available: $CLUSTER_NAME"
    else
        log_warning "MemoryDB cluster status: $cluster_status"
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        log_success "Lambda function exists: $LAMBDA_FUNCTION_NAME"
        
        # Test Lambda function
        log_info "Testing Lambda function..."
        local test_result=$(aws lambda invoke \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --payload '{"cluster_name":"'$CLUSTER_NAME'","action":"analyze","cost_threshold":100}' \
            "$TEMP_DIR/lambda-test-response.json" \
            --output text 2>/dev/null || echo "ERROR")
        
        if [[ "$test_result" != "ERROR" ]]; then
            log_success "Lambda function test completed"
        else
            log_warning "Lambda function test failed"
        fi
    else
        log_error "Lambda function not found: $LAMBDA_FUNCTION_NAME"
    fi
    
    # Check scheduler group and schedules
    local schedule_count=$(aws scheduler list-schedules \
        --group-name "$SCHEDULER_GROUP_NAME" \
        --query 'length(Schedules)' \
        --output text 2>/dev/null || echo "0")
    
    if [[ "$schedule_count" -gt "0" ]]; then
        log_success "EventBridge Scheduler configured with $schedule_count schedules"
    else
        log_warning "No schedules found in scheduler group"
    fi
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo "=================================="
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account: $AWS_ACCOUNT_ID"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Created Resources:"
    echo "  MemoryDB Cluster: $CLUSTER_NAME"
    echo "  Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "  Scheduler Group: $SCHEDULER_GROUP_NAME"
    echo "  IAM Role: $IAM_ROLE_NAME"
    echo ""
    echo "Budget Alert Email: $BUDGET_EMAIL"
    echo "Cost Threshold: $COST_THRESHOLD"
    echo ""
    echo "Log File: $LOG_FILE"
    echo "=================================="
    
    log_info "Next Steps:"
    echo "1. Verify resources in AWS Console"
    echo "2. Monitor CloudWatch dashboard for cost optimization metrics"
    echo "3. Check email for budget alert confirmations"
    echo "4. Test scaling by invoking Lambda function manually"
    echo "5. Run './destroy.sh' when ready to clean up resources"
}

# Main deployment function
main() {
    log_info "Starting Cost-Aware Resource Lifecycle Deployment"
    log_info "================================================="
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-confirmation)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --budget-email)
                BUDGET_EMAIL="$2"
                shift 2
                ;;
            --cost-threshold)
                COST_THRESHOLD="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --dry-run              Show what would be created without making changes"
                echo "  --skip-confirmation    Skip confirmation prompts"
                echo "  --budget-email EMAIL   Email for budget notifications (default: admin@example.com)"
                echo "  --cost-threshold N     Cost threshold for optimization (default: 100)"
                echo "  --help                 Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Show deployment configuration
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be created"
    fi
    
    if [[ "$SKIP_CONFIRMATION" == "false" ]]; then
        echo "This will deploy cost optimization infrastructure for MemoryDB."
        echo "Estimated cost: $50-100/month for test environment"
        echo "Budget email: $BUDGET_EMAIL"
        echo "Cost threshold: $COST_THRESHOLD"
        echo ""
        read -p "Continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_iam_resources
    create_memorydb_cluster
    create_lambda_function
    create_scheduler_resources
    create_cost_monitoring
    
    if [[ "$DRY_RUN" == "false" ]]; then
        validate_deployment
    fi
    
    display_summary
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "Deployment completed successfully!"
        log_info "Monitor the CloudWatch dashboard and Lambda logs for cost optimization activities."
    else
        log_info "Dry run completed. Use --skip-confirmation to proceed with actual deployment."
    fi
}

# Run main function with all arguments
main "$@"