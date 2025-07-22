#!/bin/bash

# Aurora Serverless v2 Cost Optimization Patterns - Deployment Script
# This script deploys the complete Aurora Serverless v2 infrastructure with
# intelligent scaling patterns, cost monitoring, and automated optimization

set -e  # Exit on any error

# Color codes for output formatting
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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $aws_version"
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or authentication failed."
        error "Please run 'aws configure' or set up your credentials."
        exit 1
    fi
    
    # Check required permissions (basic check)
    local account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [[ -z "$account_id" ]]; then
        error "Unable to retrieve AWS account ID. Check your permissions."
        exit 1
    fi
    
    log "AWS Account ID: $account_id"
    
    # Check if region is set
    local region=$(aws configure get region)
    if [[ -z "$region" ]]; then
        error "AWS region is not set. Please configure your default region."
        exit 1
    fi
    
    log "AWS Region: $region"
    
    # Check for required services availability in region
    log "Checking service availability in region..."
    if ! aws rds describe-db-clusters --region "$region" &> /dev/null; then
        error "RDS service is not available or accessible in region $region"
        exit 1
    fi
    
    success "Prerequisites check completed successfully"
}

# Function to generate unique identifiers
generate_identifiers() {
    log "Generating unique resource identifiers..."
    
    # Generate random suffix for unique naming
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null)
    
    if [[ -z "$RANDOM_SUFFIX" ]]; then
        # Fallback to timestamp if Secrets Manager fails
        RANDOM_SUFFIX=$(date +%s | tail -c 7)
        warning "Using timestamp-based suffix: $RANDOM_SUFFIX"
    fi
    
    # Set global variables
    export CLUSTER_NAME="aurora-sv2-cost-opt-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="aurora-sv2-lambda-role-${RANDOM_SUFFIX}"
    export CLUSTER_PARAMETER_GROUP="aurora-sv2-params-${RANDOM_SUFFIX}"
    export MASTER_PASSWORD="AuroraSv2Pass2024!"
    
    log "Resource identifiers generated:"
    log "  Cluster Name: $CLUSTER_NAME"
    log "  Lambda Role: $LAMBDA_ROLE_NAME"
    log "  Parameter Group: $CLUSTER_PARAMETER_GROUP"
}

# Function to create IAM resources
create_iam_resources() {
    log "Creating IAM resources..."
    
    # Create Lambda trust policy
    cat > /tmp/lambda-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    # Create IAM role for Lambda functions
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
        warning "IAM role $LAMBDA_ROLE_NAME already exists, skipping creation"
    else
        aws iam create-role \
            --role-name "$LAMBDA_ROLE_NAME" \
            --assume-role-policy-document file:///tmp/lambda-trust-policy.json
        log "Created IAM role: $LAMBDA_ROLE_NAME"
    fi
    
    # Create custom policy for Aurora management
    cat > /tmp/aurora-lambda-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBClusters",
        "rds:DescribeDBInstances",
        "rds:ModifyDBCluster",
        "rds:ModifyDBInstance",
        "rds:StartDBCluster",
        "rds:StopDBCluster",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:PutMetricData",
        "ce:GetUsageAndCosts",
        "budgets:ViewBudget",
        "sns:Publish",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF

    # Check if policy exists
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/aurora-sv2-lambda-policy"
    if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        warning "IAM policy aurora-sv2-lambda-policy already exists, skipping creation"
    else
        aws iam create-policy \
            --policy-name aurora-sv2-lambda-policy \
            --policy-document file:///tmp/aurora-lambda-policy.json
        log "Created IAM policy: aurora-sv2-lambda-policy"
    fi
    
    # Attach policy to role
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn "$policy_arn"
    
    success "IAM resources created successfully"
}

# Function to create Aurora cluster parameter group
create_parameter_group() {
    log "Creating Aurora cluster parameter group..."
    
    # Check if parameter group already exists
    if aws rds describe-db-cluster-parameter-groups \
        --db-cluster-parameter-group-name "$CLUSTER_PARAMETER_GROUP" &> /dev/null; then
        warning "Parameter group $CLUSTER_PARAMETER_GROUP already exists, skipping creation"
        return 0
    fi
    
    # Create parameter group
    aws rds create-db-cluster-parameter-group \
        --db-cluster-parameter-group-name "$CLUSTER_PARAMETER_GROUP" \
        --db-parameter-group-family aurora-postgresql15 \
        --description "Aurora Serverless v2 cost optimization parameters"
    
    # Configure parameters for cost optimization
    aws rds modify-db-cluster-parameter-group \
        --db-cluster-parameter-group-name "$CLUSTER_PARAMETER_GROUP" \
        --parameters \
            "ParameterName=shared_preload_libraries,ParameterValue='pg_stat_statements',ApplyMethod=pending-reboot" \
            "ParameterName=track_activity_query_size,ParameterValue=2048,ApplyMethod=immediate" \
            "ParameterName=log_statement,ParameterValue=ddl,ApplyMethod=immediate" \
            "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate"
    
    success "Parameter group created and configured"
}

# Function to create Aurora Serverless v2 cluster
create_aurora_cluster() {
    log "Creating Aurora Serverless v2 cluster..."
    
    # Check if cluster already exists
    if aws rds describe-db-clusters --db-cluster-identifier "$CLUSTER_NAME" &> /dev/null; then
        warning "Cluster $CLUSTER_NAME already exists, skipping creation"
        return 0
    fi
    
    # Get default VPC security group
    local default_sg=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=default" \
        --query 'SecurityGroups[0].GroupId' \
        --output text)
    
    if [[ "$default_sg" == "None" || -z "$default_sg" ]]; then
        error "Could not find default security group. Please create a VPC first."
        exit 1
    fi
    
    # Create Aurora Serverless v2 cluster
    aws rds create-db-cluster \
        --db-cluster-identifier "$CLUSTER_NAME" \
        --engine aurora-postgresql \
        --engine-version 15.4 \
        --master-username postgres \
        --master-user-password "$MASTER_PASSWORD" \
        --storage-encrypted \
        --vpc-security-group-ids "$default_sg" \
        --db-cluster-parameter-group-name "$CLUSTER_PARAMETER_GROUP" \
        --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=16 \
        --backup-retention-period 7 \
        --preferred-backup-window "03:00-04:00" \
        --preferred-maintenance-window "sun:04:00-sun:05:00" \
        --enable-cloudwatch-logs-exports postgresql \
        --enable-performance-insights \
        --performance-insights-retention-period 7 \
        --tags Key=Environment,Value=CostOptimized Key=Application,Value=AuroraServerlessV2
    
    log "Waiting for cluster to become available..."
    aws rds wait db-cluster-available --db-cluster-identifier "$CLUSTER_NAME"
    
    success "Aurora Serverless v2 cluster created successfully"
}

# Function to create database instances
create_db_instances() {
    log "Creating database instances..."
    
    # Create writer instance
    if aws rds describe-db-instances --db-instance-identifier "${CLUSTER_NAME}-writer" &> /dev/null; then
        warning "Writer instance already exists, skipping creation"
    else
        aws rds create-db-instance \
            --db-instance-identifier "${CLUSTER_NAME}-writer" \
            --db-cluster-identifier "$CLUSTER_NAME" \
            --engine aurora-postgresql \
            --db-instance-class db.serverless \
            --promotion-tier 1 \
            --enable-performance-insights \
            --performance-insights-retention-period 7 \
            --monitoring-interval 60 \
            --tags Key=InstanceType,Value=Writer Key=Environment,Value=CostOptimized
        
        log "Waiting for writer instance to become available..."
        aws rds wait db-instance-available --db-instance-identifier "${CLUSTER_NAME}-writer"
        success "Writer instance created successfully"
    fi
    
    # Create read replica 1 (standard scaling)
    if aws rds describe-db-instances --db-instance-identifier "${CLUSTER_NAME}-reader-1" &> /dev/null; then
        warning "Reader instance 1 already exists, skipping creation"
    else
        aws rds create-db-instance \
            --db-instance-identifier "${CLUSTER_NAME}-reader-1" \
            --db-cluster-identifier "$CLUSTER_NAME" \
            --engine aurora-postgresql \
            --db-instance-class db.serverless \
            --promotion-tier 2 \
            --enable-performance-insights \
            --performance-insights-retention-period 7 \
            --tags Key=InstanceType,Value=Reader Key=ScalingTier,Value=Standard
        
        log "Waiting for reader instance 1 to become available..."
        aws rds wait db-instance-available --db-instance-identifier "${CLUSTER_NAME}-reader-1"
        success "Reader instance 1 created successfully"
    fi
    
    # Create read replica 2 (aggressive scaling)
    if aws rds describe-db-instances --db-instance-identifier "${CLUSTER_NAME}-reader-2" &> /dev/null; then
        warning "Reader instance 2 already exists, skipping creation"
    else
        aws rds create-db-instance \
            --db-instance-identifier "${CLUSTER_NAME}-reader-2" \
            --db-cluster-identifier "$CLUSTER_NAME" \
            --engine aurora-postgresql \
            --db-instance-class db.serverless \
            --promotion-tier 3 \
            --enable-performance-insights \
            --performance-insights-retention-period 7 \
            --tags Key=InstanceType,Value=Reader Key=ScalingTier,Value=Aggressive
        
        log "Waiting for reader instance 2 to become available..."
        aws rds wait db-instance-available --db-instance-identifier "${CLUSTER_NAME}-reader-2"
        success "Reader instance 2 created successfully"
    fi
}

# Function to create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create cost-aware scaling function
    cat > /tmp/cost-aware-scaler.py << 'EOF'
import json
import boto3
from datetime import datetime, timedelta
import os

rds = boto3.client('rds')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    cluster_id = os.environ['CLUSTER_ID']
    
    try:
        # Get current cluster configuration
        cluster_response = rds.describe_db_clusters(DBClusterIdentifier=cluster_id)
        cluster = cluster_response['DBClusters'][0]
        
        current_min = cluster['ServerlessV2ScalingConfiguration']['MinCapacity']
        current_max = cluster['ServerlessV2ScalingConfiguration']['MaxCapacity']
        
        # Get CPU utilization metrics
        cpu_metrics = get_cpu_utilization(cluster_id)
        connection_metrics = get_connection_count(cluster_id)
        
        # Determine optimal scaling based on patterns
        new_min, new_max = calculate_optimal_scaling(
            cpu_metrics, connection_metrics, current_min, current_max
        )
        
        # Apply scaling if needed
        if new_min != current_min or new_max != current_max:
            update_scaling_configuration(cluster_id, new_min, new_max)
            send_scaling_notification(cluster_id, current_min, current_max, new_min, new_max)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'cluster': cluster_id,
                'previous_scaling': {'min': current_min, 'max': current_max},
                'new_scaling': {'min': new_min, 'max': new_max},
                'cpu_avg': cpu_metrics['average'],
                'connections_avg': connection_metrics['average']
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

def get_cpu_utilization(cluster_id):
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=1)
    
    response = cloudwatch.get_metric_statistics(
        Namespace='AWS/RDS',
        MetricName='CPUUtilization',
        Dimensions=[{'Name': 'DBClusterIdentifier', 'Value': cluster_id}],
        StartTime=start_time,
        EndTime=end_time,
        Period=300,
        Statistics=['Average', 'Maximum']
    )
    
    if response['Datapoints']:
        avg_cpu = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
        max_cpu = max(dp['Maximum'] for dp in response['Datapoints'])
        return {'average': avg_cpu, 'maximum': max_cpu}
    return {'average': 0, 'maximum': 0}

def get_connection_count(cluster_id):
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=1)
    
    response = cloudwatch.get_metric_statistics(
        Namespace='AWS/RDS',
        MetricName='DatabaseConnections',
        Dimensions=[{'Name': 'DBClusterIdentifier', 'Value': cluster_id}],
        StartTime=start_time,
        EndTime=end_time,
        Period=300,
        Statistics=['Average', 'Maximum']
    )
    
    if response['Datapoints']:
        avg_conn = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
        max_conn = max(dp['Maximum'] for dp in response['Datapoints'])
        return {'average': avg_conn, 'maximum': max_conn}
    return {'average': 0, 'maximum': 0}

def calculate_optimal_scaling(cpu_metrics, conn_metrics, current_min, current_max):
    cpu_avg = cpu_metrics['average']
    cpu_max = cpu_metrics['maximum']
    conn_avg = conn_metrics['average']
    
    # Determine optimal minimum capacity
    if cpu_avg < 20 and conn_avg < 5:
        new_min = 0.5
    elif cpu_avg < 40 and conn_avg < 20:
        new_min = max(0.5, current_min - 0.5)
    elif cpu_avg > 70 or conn_avg > 50:
        new_min = min(8, current_min + 1)
    else:
        new_min = current_min
    
    # Determine optimal maximum capacity
    if cpu_max > 80 or conn_avg > 80:
        new_max = min(32, current_max + 4)
    elif cpu_max < 50 and conn_avg < 30:
        new_max = max(4, current_max - 2)
    else:
        new_max = current_max
    
    new_min = min(new_min, new_max)
    return new_min, new_max

def update_scaling_configuration(cluster_id, min_capacity, max_capacity):
    rds.modify_db_cluster(
        DBClusterIdentifier=cluster_id,
        ServerlessV2ScalingConfiguration={
            'MinCapacity': min_capacity,
            'MaxCapacity': max_capacity
        },
        ApplyImmediately=True
    )

def send_scaling_notification(cluster_id, old_min, old_max, new_min, new_max):
    cost_impact = calculate_cost_impact(old_min, old_max, new_min, new_max)
    
    cloudwatch.put_metric_data(
        Namespace='Aurora/CostOptimization',
        MetricData=[
            {
                'MetricName': 'ScalingAdjustment',
                'Dimensions': [
                    {'Name': 'ClusterIdentifier', 'Value': cluster_id},
                    {'Name': 'ScalingType', 'Value': 'MinCapacity'}
                ],
                'Value': new_min - old_min,
                'Unit': 'Count'
            },
            {
                'MetricName': 'EstimatedCostImpact',
                'Dimensions': [{'Name': 'ClusterIdentifier', 'Value': cluster_id}],
                'Value': cost_impact,
                'Unit': 'None'
            }
        ]
    )

def calculate_cost_impact(old_min, old_max, new_min, new_max):
    hours_per_month = 730
    cost_per_acu_hour = 0.12
    
    old_avg_usage = (old_min + old_max) / 2
    new_avg_usage = (new_min + new_max) / 2
    
    old_cost = old_avg_usage * hours_per_month * cost_per_acu_hour
    new_cost = new_avg_usage * hours_per_month * cost_per_acu_hour
    
    return new_cost - old_cost
EOF
    
    # Package and deploy cost-aware scaler
    cd /tmp && zip cost-aware-scaler.zip cost-aware-scaler.py
    
    if aws lambda get-function --function-name "${CLUSTER_NAME}-cost-aware-scaler" &> /dev/null; then
        warning "Cost-aware scaler function already exists, updating code"
        aws lambda update-function-code \
            --function-name "${CLUSTER_NAME}-cost-aware-scaler" \
            --zip-file fileb://cost-aware-scaler.zip
    else
        aws lambda create-function \
            --function-name "${CLUSTER_NAME}-cost-aware-scaler" \
            --runtime python3.9 \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" \
            --handler cost-aware-scaler.lambda_handler \
            --zip-file fileb://cost-aware-scaler.zip \
            --timeout 300 \
            --memory-size 256 \
            --environment Variables="{CLUSTER_ID=${CLUSTER_NAME}}"
        success "Cost-aware scaling Lambda function created"
    fi
    
    # Create auto-pause/resume function
    cat > /tmp/auto-pause-resume.py << 'EOF'
import json
import boto3
from datetime import datetime, time
import os

rds = boto3.client('rds')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    cluster_id = os.environ['CLUSTER_ID']
    environment = os.environ.get('ENVIRONMENT', 'development')
    
    try:
        current_time = datetime.utcnow().time()
        action = determine_action(current_time, environment)
        
        if action == 'pause':
            result = pause_cluster_if_idle(cluster_id)
        elif action == 'resume':
            result = resume_cluster_if_needed(cluster_id)
        else:
            result = {'action': 'no_action', 'reason': 'Outside operating hours'}
        
        record_pause_resume_metrics(cluster_id, action, result)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'cluster': cluster_id,
                'environment': environment,
                'action': action,
                'result': result,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

def determine_action(current_time, environment):
    if environment == 'development':
        start_hour = time(8, 0)
        end_hour = time(20, 0)
    elif environment == 'staging':
        start_hour = time(6, 0)
        end_hour = time(22, 0)
    else:
        return 'monitor'
    
    if start_hour <= current_time <= end_hour:
        return 'resume'
    else:
        return 'pause'

def pause_cluster_if_idle(cluster_id):
    if is_cluster_idle(cluster_id):
        rds.modify_db_cluster(
            DBClusterIdentifier=cluster_id,
            ServerlessV2ScalingConfiguration={
                'MinCapacity': 0.5,
                'MaxCapacity': 1
            },
            ApplyImmediately=True
        )
        return {'action': 'paused', 'reason': 'Low activity detected during off-hours'}
    else:
        return {'action': 'not_paused', 'reason': 'Active connections detected'}

def resume_cluster_if_needed(cluster_id):
    cluster_response = rds.describe_db_clusters(DBClusterIdentifier=cluster_id)
    cluster = cluster_response['DBClusters'][0]
    
    current_min = cluster['ServerlessV2ScalingConfiguration']['MinCapacity']
    current_max = cluster['ServerlessV2ScalingConfiguration']['MaxCapacity']
    
    if current_min <= 0.5 and current_max <= 1:
        rds.modify_db_cluster(
            DBClusterIdentifier=cluster_id,
            ServerlessV2ScalingConfiguration={
                'MinCapacity': 0.5,
                'MaxCapacity': 8
            },
            ApplyImmediately=True
        )
        return {'action': 'resumed', 'reason': 'Operating hours started'}
    else:
        return {'action': 'already_active', 'reason': 'Cluster already in active state'}

def is_cluster_idle(cluster_id):
    from datetime import timedelta
    
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(minutes=30)
    
    response = cloudwatch.get_metric_statistics(
        Namespace='AWS/RDS',
        MetricName='DatabaseConnections',
        Dimensions=[{'Name': 'DBClusterIdentifier', 'Value': cluster_id}],
        StartTime=start_time,
        EndTime=end_time,
        Period=300,
        Statistics=['Maximum']
    )
    
    if response['Datapoints']:
        max_connections = max(dp['Maximum'] for dp in response['Datapoints'])
        return max_connections <= 1
    
    return True

def record_pause_resume_metrics(cluster_id, action, result):
    metric_value = 1 if result.get('action') in ['paused', 'resumed'] else 0
    
    cloudwatch.put_metric_data(
        Namespace='Aurora/CostOptimization',
        MetricData=[
            {
                'MetricName': 'AutoPauseResumeActions',
                'Dimensions': [
                    {'Name': 'ClusterIdentifier', 'Value': cluster_id},
                    {'Name': 'Action', 'Value': action}
                ],
                'Value': metric_value,
                'Unit': 'Count'
            }
        ]
    )
EOF
    
    # Package and deploy auto-pause/resume function
    cd /tmp && zip auto-pause-resume.zip auto-pause-resume.py
    
    if aws lambda get-function --function-name "${CLUSTER_NAME}-auto-pause-resume" &> /dev/null; then
        warning "Auto-pause/resume function already exists, updating code"
        aws lambda update-function-code \
            --function-name "${CLUSTER_NAME}-auto-pause-resume" \
            --zip-file fileb://auto-pause-resume.zip
    else
        aws lambda create-function \
            --function-name "${CLUSTER_NAME}-auto-pause-resume" \
            --runtime python3.9 \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" \
            --handler auto-pause-resume.lambda_handler \
            --zip-file fileb://auto-pause-resume.zip \
            --timeout 300 \
            --memory-size 256 \
            --environment Variables="{CLUSTER_ID=${CLUSTER_NAME},ENVIRONMENT=development}"
        success "Auto-pause/resume Lambda function created"
    fi
    
    success "Lambda functions created successfully"
}

# Function to create EventBridge schedules
create_eventbridge_schedules() {
    log "Creating EventBridge schedules..."
    
    # Create rule for cost-aware scaling
    if aws events describe-rule --name "${CLUSTER_NAME}-cost-aware-scaling" &> /dev/null; then
        warning "Cost-aware scaling rule already exists, skipping creation"
    else
        aws events put-rule \
            --name "${CLUSTER_NAME}-cost-aware-scaling" \
            --schedule-expression "rate(15 minutes)" \
            --description "Trigger cost-aware scaling for Aurora Serverless v2"
        
        # Add Lambda permission
        aws lambda add-permission \
            --function-name "${CLUSTER_NAME}-cost-aware-scaler" \
            --statement-id cost-aware-scaling-permission \
            --action lambda:InvokeFunction \
            --principal events.amazonaws.com \
            --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${CLUSTER_NAME}-cost-aware-scaling" \
            2>/dev/null || true
        
        # Add target
        aws events put-targets \
            --rule "${CLUSTER_NAME}-cost-aware-scaling" \
            --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${CLUSTER_NAME}-cost-aware-scaler"
        
        success "Cost-aware scaling schedule created"
    fi
    
    # Create rule for auto-pause/resume
    if aws events describe-rule --name "${CLUSTER_NAME}-auto-pause-resume" &> /dev/null; then
        warning "Auto-pause/resume rule already exists, skipping creation"
    else
        aws events put-rule \
            --name "${CLUSTER_NAME}-auto-pause-resume" \
            --schedule-expression "rate(1 hour)" \
            --description "Trigger auto-pause/resume for Aurora Serverless v2"
        
        # Add Lambda permission
        aws lambda add-permission \
            --function-name "${CLUSTER_NAME}-auto-pause-resume" \
            --statement-id auto-pause-resume-permission \
            --action lambda:InvokeFunction \
            --principal events.amazonaws.com \
            --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${CLUSTER_NAME}-auto-pause-resume" \
            2>/dev/null || true
        
        # Add target
        aws events put-targets \
            --rule "${CLUSTER_NAME}-auto-pause-resume" \
            --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${CLUSTER_NAME}-auto-pause-resume"
        
        success "Auto-pause/resume schedule created"
    fi
}

# Function to create cost monitoring
create_cost_monitoring() {
    log "Creating cost monitoring and alerting system..."
    
    # Create SNS topic for cost alerts
    local topic_output
    if topic_output=$(aws sns create-topic --name "aurora-sv2-cost-alerts" 2>/dev/null); then
        COST_TOPIC_ARN=$(echo "$topic_output" | jq -r '.TopicArn')
        success "Created SNS topic: $COST_TOPIC_ARN"
    else
        # Topic might already exist, get its ARN
        COST_TOPIC_ARN=$(aws sns list-topics --query "Topics[?contains(TopicArn, 'aurora-sv2-cost-alerts')].TopicArn" --output text)
        if [[ -n "$COST_TOPIC_ARN" ]]; then
            warning "SNS topic already exists: $COST_TOPIC_ARN"
        else
            error "Failed to create or find SNS topic"
            return 1
        fi
    fi
    
    # Create CloudWatch alarms
    if aws cloudwatch describe-alarms --alarm-names "${CLUSTER_NAME}-high-acu-usage" &> /dev/null; then
        warning "High ACU usage alarm already exists, skipping creation"
    else
        aws cloudwatch put-metric-alarm \
            --alarm-name "${CLUSTER_NAME}-high-acu-usage" \
            --alarm-description "Alert when Aurora Serverless v2 ACU usage is high" \
            --metric-name ServerlessDatabaseCapacity \
            --namespace AWS/RDS \
            --statistic Average \
            --period 300 \
            --threshold 12 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 3 \
            --alarm-actions "$COST_TOPIC_ARN" \
            --dimensions Name=DBClusterIdentifier,Value="$CLUSTER_NAME"
        success "Created high ACU usage alarm"
    fi
    
    if aws cloudwatch describe-alarms --alarm-names "${CLUSTER_NAME}-sustained-high-capacity" &> /dev/null; then
        warning "Sustained high capacity alarm already exists, skipping creation"
    else
        aws cloudwatch put-metric-alarm \
            --alarm-name "${CLUSTER_NAME}-sustained-high-capacity" \
            --alarm-description "Alert when capacity remains high for extended period" \
            --metric-name ServerlessDatabaseCapacity \
            --namespace AWS/RDS \
            --statistic Average \
            --period 1800 \
            --threshold 8 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 4 \
            --alarm-actions "$COST_TOPIC_ARN" \
            --dimensions Name=DBClusterIdentifier,Value="$CLUSTER_NAME"
        success "Created sustained high capacity alarm"
    fi
    
    # Create budget
    cat > /tmp/budget-config.json << EOF
{
  "BudgetName": "Aurora-Serverless-v2-Monthly",
  "BudgetLimit": {
    "Amount": "200.00",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST",
  "CostFilters": {
    "Service": ["Amazon Relational Database Service"],
    "TagKey": ["Application"],
    "TagValue": ["AuroraServerlessV2"]
  }
}
EOF
    
    cat > /tmp/budget-notification.json << EOF
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
        "SubscriptionType": "SNS",
        "Address": "$COST_TOPIC_ARN"
      }
    ]
  },
  {
    "Notification": {
      "NotificationType": "FORECASTED",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 100,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [
      {
        "SubscriptionType": "SNS",
        "Address": "$COST_TOPIC_ARN"
      }
    ]
  }
]
EOF
    
    if aws budgets describe-budget --account-id "$AWS_ACCOUNT_ID" --budget-name "Aurora-Serverless-v2-Monthly" &> /dev/null; then
        warning "Budget already exists, skipping creation"
    else
        aws budgets create-budget \
            --account-id "$AWS_ACCOUNT_ID" \
            --budget file:///tmp/budget-config.json \
            --notifications-with-subscribers file:///tmp/budget-notification.json
        success "Created cost budget with notifications"
    fi
}

# Function to save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    local deployment_file="aurora-sv2-deployment-${RANDOM_SUFFIX}.json"
    
    cat > "$deployment_file" << EOF
{
  "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "cluster_name": "$CLUSTER_NAME",
  "lambda_role_name": "$LAMBDA_ROLE_NAME",
  "parameter_group_name": "$CLUSTER_PARAMETER_GROUP",
  "aws_region": "$AWS_REGION",
  "aws_account_id": "$AWS_ACCOUNT_ID",
  "resources": {
    "aurora_cluster": "$CLUSTER_NAME",
    "writer_instance": "${CLUSTER_NAME}-writer",
    "reader_instances": [
      "${CLUSTER_NAME}-reader-1",
      "${CLUSTER_NAME}-reader-2"
    ],
    "lambda_functions": [
      "${CLUSTER_NAME}-cost-aware-scaler",
      "${CLUSTER_NAME}-auto-pause-resume"
    ],
    "eventbridge_rules": [
      "${CLUSTER_NAME}-cost-aware-scaling",
      "${CLUSTER_NAME}-auto-pause-resume"
    ],
    "cloudwatch_alarms": [
      "${CLUSTER_NAME}-high-acu-usage",
      "${CLUSTER_NAME}-sustained-high-capacity"
    ],
    "budget_name": "Aurora-Serverless-v2-Monthly"
  }
}
EOF
    
    success "Deployment information saved to: $deployment_file"
    log "Use this file as reference for cleanup operations"
}

# Function to display deployment summary
display_deployment_summary() {
    echo
    echo "================================"
    echo "   DEPLOYMENT COMPLETED"
    echo "================================"
    echo
    echo "Aurora Serverless v2 Cluster Details:"
    echo "  Cluster Name: $CLUSTER_NAME"
    echo "  Writer Instance: ${CLUSTER_NAME}-writer"
    echo "  Reader Instances: ${CLUSTER_NAME}-reader-1, ${CLUSTER_NAME}-reader-2"
    echo
    echo "Cost Optimization Features:"
    echo "  ✓ Intelligent auto-scaling (15-minute intervals)"
    echo "  ✓ Auto-pause/resume for development (hourly checks)"
    echo "  ✓ CloudWatch cost monitoring alarms"
    echo "  ✓ AWS Budget with SNS notifications"
    echo
    echo "Connection Information:"
    local cluster_endpoint
    cluster_endpoint=$(aws rds describe-db-clusters \
        --db-cluster-identifier "$CLUSTER_NAME" \
        --query 'DBClusters[0].Endpoint' \
        --output text 2>/dev/null || echo "Pending...")
    echo "  Cluster Endpoint: $cluster_endpoint"
    echo "  Database: postgres"
    echo "  Username: postgres"
    echo "  Password: [Set in environment variable MASTER_PASSWORD]"
    echo
    echo "Next Steps:"
    echo "  1. Connect to your database using the endpoint above"
    echo "  2. Monitor scaling activities in CloudWatch"
    echo "  3. Review cost optimization metrics in Aurora/CostOptimization namespace"
    echo "  4. Adjust scaling parameters based on your workload patterns"
    echo
    echo "Cleanup:"
    echo "  Run ./destroy.sh to remove all resources when no longer needed"
    echo
}

# Main deployment function
main() {
    log "Starting Aurora Serverless v2 Cost Optimization deployment..."
    
    # Set environment variables
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
    
    # Execute deployment steps
    check_prerequisites
    generate_identifiers
    create_iam_resources
    create_parameter_group
    create_aurora_cluster
    create_db_instances
    create_lambda_functions
    create_eventbridge_schedules
    create_cost_monitoring
    save_deployment_info
    
    # Clean up temporary files
    rm -f /tmp/lambda-trust-policy.json /tmp/aurora-lambda-policy.json
    rm -f /tmp/budget-config.json /tmp/budget-notification.json
    rm -f /tmp/cost-aware-scaler.py /tmp/cost-aware-scaler.zip
    rm -f /tmp/auto-pause-resume.py /tmp/auto-pause-resume.zip
    
    display_deployment_summary
    
    success "Aurora Serverless v2 Cost Optimization deployment completed successfully!"
    echo
    log "Total deployment time: $SECONDS seconds"
}

# Handle script interruption
trap 'error "Deployment interrupted. Some resources may have been created."; exit 1' INT TERM

# Validate script is not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
else
    error "This script should be executed, not sourced"
    exit 1
fi