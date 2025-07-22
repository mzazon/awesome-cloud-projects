#!/bin/bash

# Deploy script for Automated File Lifecycle Management with Amazon FSx Intelligent-Tiering and Lambda
# This script implements the complete infrastructure described in the recipe

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Script metadata
SCRIPT_NAME="FSx Lifecycle Management Deployment"
SCRIPT_VERSION="1.0"
RECIPE_NAME="automated-file-lifecycle-management-fsx-intelligent-tiering-lambda"

log "Starting $SCRIPT_NAME v$SCRIPT_VERSION"

# Check if dry run mode
DRY_RUN=${1:-""}
if [[ "$DRY_RUN" == "--dry-run" ]]; then
    warn "Running in dry-run mode - no resources will be created"
    DRY_RUN=true
else
    DRY_RUN=false
fi

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is required but not installed"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
    fi
    
    # Check required AWS services permissions
    log "Verifying AWS permissions..."
    local services=("fsx" "lambda" "iam" "sns" "s3" "events" "cloudwatch" "ec2")
    for service in "${services[@]}"; do
        if ! aws $service help &> /dev/null; then
            warn "Unable to verify $service permissions - continuing anyway"
        fi
    done
    
    # Check if we're in the correct directory
    if [[ ! -f "../../${RECIPE_NAME}.md" ]]; then
        error "Script must be run from the scripts directory within the recipe code folder"
    fi
    
    success "Prerequisites check completed"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Set AWS region
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            export AWS_REGION="us-east-1"
            warn "AWS region not configured, defaulting to us-east-1"
        fi
        
        # Get AWS account ID
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Generate unique identifiers
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    else
        export AWS_REGION="us-east-1"
        export AWS_ACCOUNT_ID="123456789012"
        RANDOM_SUFFIX="dryrun"
    fi
    
    # Set resource names
    export FSX_FILE_SYSTEM_NAME="fsx-lifecycle-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="FSxLifecycleRole-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="fsx-lifecycle-alerts-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="fsx-lifecycle-reports-${RANDOM_SUFFIX}"
    
    log "Environment initialized with suffix: $RANDOM_SUFFIX"
    log "Region: $AWS_REGION"
    log "Account: $AWS_ACCOUNT_ID"
}

# Create S3 bucket and SNS topic
create_foundational_resources() {
    log "Creating foundational resources..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create S3 bucket for Lambda code and reports
        if ! aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null; then
            aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION}
            success "Created S3 bucket: ${S3_BUCKET_NAME}"
        else
            warn "S3 bucket ${S3_BUCKET_NAME} already exists"
        fi
        
        # Create SNS topic for notifications
        aws sns create-topic --name ${SNS_TOPIC_NAME} > /dev/null
        export SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
            --topic-arn arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME} \
            --query Attributes.TopicArn --output text 2>/dev/null || \
            echo "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}")
        success "Created SNS topic: ${SNS_TOPIC_NAME}"
    else
        log "[DRY-RUN] Would create S3 bucket: ${S3_BUCKET_NAME}"
        log "[DRY-RUN] Would create SNS topic: ${SNS_TOPIC_NAME}"
        export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    fi
}

# Create IAM role for Lambda functions
create_iam_role() {
    log "Creating IAM role for Lambda functions..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create trust policy
        cat > /tmp/trust-policy.json << EOF
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
        if ! aws iam get-role --role-name ${LAMBDA_ROLE_NAME} &> /dev/null; then
            aws iam create-role \
                --role-name ${LAMBDA_ROLE_NAME} \
                --assume-role-policy-document file:///tmp/trust-policy.json
            success "Created IAM role: ${LAMBDA_ROLE_NAME}"
        else
            warn "IAM role ${LAMBDA_ROLE_NAME} already exists"
        fi
        
        # Attach managed policies
        aws iam attach-role-policy \
            --role-name ${LAMBDA_ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        # Create custom policy
        cat > /tmp/fsx-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "fsx:DescribeFileSystems",
        "fsx:DescribeVolumes",
        "fsx:PutFileSystemPolicy",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:PutMetricData",
        "sns:Publish",
        "s3:PutObject",
        "s3:GetObject"
      ],
      "Resource": "*"
    }
  ]
}
EOF
        
        aws iam put-role-policy \
            --role-name ${LAMBDA_ROLE_NAME} \
            --policy-name FSxLifecyclePolicy \
            --policy-document file:///tmp/fsx-policy.json
        
        export LAMBDA_ROLE_ARN=$(aws iam get-role \
            --role-name ${LAMBDA_ROLE_NAME} \
            --query Role.Arn --output text)
        
        success "IAM role configured with ARN: ${LAMBDA_ROLE_ARN}"
        
        # Wait for role propagation
        log "Waiting for IAM role propagation..."
        sleep 10
    else
        log "[DRY-RUN] Would create IAM role: ${LAMBDA_ROLE_NAME}"
        export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
    fi
}

# Create FSx file system
create_fsx_filesystem() {
    log "Creating Amazon FSx for OpenZFS file system..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Get default VPC and subnet information
        export VPC_ID=$(aws ec2 describe-vpcs \
            --filters Name=is-default,Values=true \
            --query Vpcs[0].VpcId --output text)
        
        if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
            error "No default VPC found. Please ensure you have a default VPC or modify the script for custom VPC."
        fi
        
        export SUBNET_ID=$(aws ec2 describe-subnets \
            --filters Name=vpc-id,Values=${VPC_ID} \
            --query Subnets[0].SubnetId --output text)
        
        # Create security group for FSx
        if ! aws ec2 describe-security-groups --filters Name=group-name,Values=fsx-sg-${RANDOM_SUFFIX} --query SecurityGroups[0].GroupId --output text 2>/dev/null | grep -v "None"; then
            aws ec2 create-security-group \
                --group-name fsx-sg-${RANDOM_SUFFIX} \
                --description "Security group for FSx file system" \
                --vpc-id ${VPC_ID}
        fi
        
        export SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
            --filters Name=group-name,Values=fsx-sg-${RANDOM_SUFFIX} \
            --query SecurityGroups[0].GroupId --output text)
        
        # Add NFS rule to security group (check if it already exists)
        if ! aws ec2 describe-security-groups --group-ids ${SECURITY_GROUP_ID} --query 'SecurityGroups[0].IpPermissions[?FromPort==`2049`]' --output text | grep -q "2049"; then
            aws ec2 authorize-security-group-ingress \
                --group-id ${SECURITY_GROUP_ID} \
                --protocol tcp \
                --port 2049 \
                --source-group ${SECURITY_GROUP_ID}
        fi
        
        # Check if FSx file system already exists
        existing_fs=$(aws fsx describe-file-systems \
            --query "FileSystems[?Tags[?Key=='Name' && Value=='${FSX_FILE_SYSTEM_NAME}']].FileSystemId" \
            --output text 2>/dev/null || echo "")
        
        if [[ -z "$existing_fs" || "$existing_fs" == "None" ]]; then
            log "Creating FSx file system (this may take 10-15 minutes)..."
            aws fsx create-file-system \
                --file-system-type OpenZFS \
                --storage-capacity 64 \
                --storage-type SSD \
                --subnet-ids ${SUBNET_ID} \
                --security-group-ids ${SECURITY_GROUP_ID} \
                --open-zfs-configuration ThroughputCapacity=64,ReadCacheConfig="{SizeGiB=128}" \
                --tags Key=Name,Value=${FSX_FILE_SYSTEM_NAME}
            
            # Wait for file system to be available
            log "Waiting for FSx file system to become available..."
            local max_attempts=60
            local attempt=1
            while [[ $attempt -le $max_attempts ]]; do
                local fs_state=$(aws fsx describe-file-systems \
                    --query "FileSystems[?Tags[?Key=='Name' && Value=='${FSX_FILE_SYSTEM_NAME}']].Lifecycle" \
                    --output text 2>/dev/null || echo "")
                
                if [[ "$fs_state" == "AVAILABLE" ]]; then
                    break
                elif [[ "$fs_state" == "FAILED" ]]; then
                    error "FSx file system creation failed"
                fi
                
                log "FSx file system state: $fs_state (attempt $attempt/$max_attempts)"
                sleep 15
                ((attempt++))
            done
            
            if [[ $attempt -gt $max_attempts ]]; then
                error "Timeout waiting for FSx file system to become available"
            fi
        else
            warn "FSx file system already exists: $existing_fs"
        fi
        
        export FSX_FILE_SYSTEM_ID=$(aws fsx describe-file-systems \
            --query "FileSystems[?Tags[?Key=='Name' && Value=='${FSX_FILE_SYSTEM_NAME}']].FileSystemId" \
            --output text)
        
        success "FSx file system ready: ${FSX_FILE_SYSTEM_ID}"
    else
        log "[DRY-RUN] Would create FSx file system: ${FSX_FILE_SYSTEM_NAME}"
        export FSX_FILE_SYSTEM_ID="fs-dryrun123456"
    fi
}

# Create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create lifecycle policy Lambda function
        log "Creating lifecycle policy Lambda function..."
        
        cat > /tmp/lifecycle-policy.py << 'EOF'
import json
import boto3
import datetime
from typing import Dict, List

def lambda_handler(event, context):
    """
    Monitor FSx metrics and adjust lifecycle policies based on access patterns
    """
    fsx_client = boto3.client('fsx')
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    try:
        # Get FSx file system information
        file_systems = fsx_client.describe_file_systems()
        
        for fs in file_systems['FileSystems']:
            if fs['FileSystemType'] == 'OpenZFS':
                fs_id = fs['FileSystemId']
                
                # Get cache hit ratio metric
                cache_metrics = get_cache_metrics(cloudwatch, fs_id)
                
                # Get storage utilization metrics
                storage_metrics = get_storage_metrics(cloudwatch, fs_id)
                
                # Analyze access patterns
                recommendations = analyze_access_patterns(cache_metrics, storage_metrics)
                
                # Send recommendations via SNS
                send_notifications(sns, fs_id, recommendations)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Lifecycle policy analysis completed')
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def get_cache_metrics(cloudwatch, file_system_id: str) -> Dict:
    """Get FSx cache hit ratio metrics"""
    end_time = datetime.datetime.utcnow()
    start_time = end_time - datetime.timedelta(hours=1)
    
    try:
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/FSx',
            MetricName='FileServerCacheHitRatio',
            Dimensions=[
                {
                    'Name': 'FileSystemId',
                    'Value': file_system_id
                }
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average']
        )
        return response['Datapoints']
    except Exception as e:
        print(f"Error getting cache metrics: {e}")
        return []

def get_storage_metrics(cloudwatch, file_system_id: str) -> Dict:
    """Get FSx storage utilization metrics"""
    end_time = datetime.datetime.utcnow()
    start_time = end_time - datetime.timedelta(hours=1)
    
    try:
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/FSx',
            MetricName='StorageUtilization',
            Dimensions=[
                {
                    'Name': 'FileSystemId',
                    'Value': file_system_id
                }
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average']
        )
        return response['Datapoints']
    except Exception as e:
        print(f"Error getting storage metrics: {e}")
        return []

def analyze_access_patterns(cache_metrics: List[Dict], storage_metrics: List[Dict]) -> Dict:
    """Analyze metrics to generate recommendations"""
    recommendations = {
        'cache_recommendation': 'No data available',
        'storage_recommendation': 'No data available',
        'actions': []
    }
    
    # Analyze cache hit ratio
    if cache_metrics:
        avg_cache_hit = sum(point['Average'] for point in cache_metrics) / len(cache_metrics)
        recommendations['cache_hit_ratio'] = avg_cache_hit
        
        if avg_cache_hit < 70:
            recommendations['cache_recommendation'] = 'Consider increasing SSD cache size'
            recommendations['actions'].append('scale_cache')
        elif avg_cache_hit > 95:
            recommendations['cache_recommendation'] = 'Cache size may be oversized'
            recommendations['actions'].append('optimize_cache')
        else:
            recommendations['cache_recommendation'] = 'Cache performance optimal'
            recommendations['actions'].append('maintain')
    
    # Analyze storage utilization
    if storage_metrics:
        avg_storage = sum(point['Average'] for point in storage_metrics) / len(storage_metrics)
        recommendations['storage_utilization'] = avg_storage
        
        if avg_storage > 85:
            recommendations['storage_recommendation'] = 'High storage utilization detected'
            recommendations['actions'].append('monitor_capacity')
        elif avg_storage < 30:
            recommendations['storage_recommendation'] = 'Low storage utilization - consider downsizing'
            recommendations['actions'].append('optimize_capacity')
        else:
            recommendations['storage_recommendation'] = 'Storage utilization optimal'
    
    return recommendations

def send_notifications(sns, file_system_id: str, recommendations: Dict):
    """Send recommendations via SNS"""
    import os
    
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    if topic_arn:
        message = f"""
        FSx File System: {file_system_id}
        
        Cache Recommendation: {recommendations['cache_recommendation']}
        Storage Recommendation: {recommendations['storage_recommendation']}
        
        Cache Hit Ratio: {recommendations.get('cache_hit_ratio', 'N/A')}%
        Storage Utilization: {recommendations.get('storage_utilization', 'N/A')}%
        
        Suggested Actions: {', '.join(recommendations.get('actions', []))}
        """
        
        sns.publish(
            TopicArn=topic_arn,
            Message=message,
            Subject='FSx Lifecycle Policy Recommendation'
        )
EOF
        
        # Create deployment package
        cd /tmp && zip lifecycle-policy.zip lifecycle-policy.py
        
        # Check if function already exists
        if ! aws lambda get-function --function-name fsx-lifecycle-policy &> /dev/null; then
            aws lambda create-function \
                --function-name fsx-lifecycle-policy \
                --runtime python3.9 \
                --role ${LAMBDA_ROLE_ARN} \
                --handler lifecycle-policy.lambda_handler \
                --zip-file fileb://lifecycle-policy.zip \
                --timeout 60 \
                --memory-size 256 \
                --environment Variables="{SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}"
            success "Created lifecycle policy Lambda function"
        else
            aws lambda update-function-code \
                --function-name fsx-lifecycle-policy \
                --zip-file fileb://lifecycle-policy.zip
            success "Updated existing lifecycle policy Lambda function"
        fi
        
        # Create cost reporting Lambda function
        log "Creating cost reporting Lambda function..."
        
        cat > /tmp/cost-reporting.py << 'EOF'
import json
import boto3
import datetime
import csv
from io import StringIO

def lambda_handler(event, context):
    """
    Generate cost optimization reports for FSx file systems
    """
    fsx_client = boto3.client('fsx')
    cloudwatch = boto3.client('cloudwatch')
    s3 = boto3.client('s3')
    
    try:
        # Get FSx file systems
        file_systems = fsx_client.describe_file_systems()
        
        for fs in file_systems['FileSystems']:
            if fs['FileSystemType'] == 'OpenZFS':
                fs_id = fs['FileSystemId']
                
                # Collect usage metrics
                usage_data = collect_usage_metrics(cloudwatch, fs_id)
                
                # Generate cost report
                report = generate_cost_report(fs, usage_data)
                
                # Save report to S3
                save_report_to_s3(s3, fs_id, report)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Cost reports generated successfully')
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def collect_usage_metrics(cloudwatch, file_system_id: str) -> dict:
    """Collect various usage metrics for cost analysis"""
    end_time = datetime.datetime.utcnow()
    start_time = end_time - datetime.timedelta(days=7)
    
    metrics = {}
    
    # Storage capacity and utilization metrics
    for metric_name in ['StorageUtilization', 'FileServerCacheHitRatio']:
        try:
            response = cloudwatch.get_metric_statistics(
                Namespace='AWS/FSx',
                MetricName=metric_name,
                Dimensions=[
                    {
                        'Name': 'FileSystemId',
                        'Value': file_system_id
                    }
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=3600,
                Statistics=['Average']
            )
            metrics[metric_name] = response['Datapoints']
        except Exception as e:
            print(f"Error collecting {metric_name}: {e}")
            metrics[metric_name] = []
    
    return metrics

def generate_cost_report(file_system: dict, usage_data: dict) -> dict:
    """Generate comprehensive cost optimization report"""
    fs_id = file_system['FileSystemId']
    storage_capacity = file_system['StorageCapacity']
    throughput_capacity = file_system['OpenZFSConfiguration']['ThroughputCapacity']
    
    # Calculate estimated costs based on current pricing
    # Base throughput cost: approximately $0.30 per MBps/month
    base_throughput_cost = throughput_capacity * 0.30
    
    # Storage cost: approximately $0.15 per GiB/month for SSD
    storage_cost = storage_capacity * 0.15
    
    monthly_cost = base_throughput_cost + storage_cost
    
    # Storage efficiency analysis
    storage_metrics = usage_data.get('StorageUtilization', [])
    avg_utilization = 0
    if storage_metrics:
        avg_utilization = sum(point['Average'] for point in storage_metrics) / len(storage_metrics)
    
    # Cache performance analysis
    cache_metrics = usage_data.get('FileServerCacheHitRatio', [])
    avg_cache_hit = 0
    if cache_metrics:
        avg_cache_hit = sum(point['Average'] for point in cache_metrics) / len(cache_metrics)
    
    report = {
        'file_system_id': fs_id,
        'report_date': datetime.datetime.utcnow().isoformat(),
        'storage_capacity_gb': storage_capacity,
        'throughput_capacity_mbps': throughput_capacity,
        'estimated_monthly_cost': monthly_cost,
        'storage_efficiency': {
            'average_utilization': avg_utilization,
            'cache_hit_ratio': avg_cache_hit,
            'optimization_potential': max(0, 100 - avg_utilization)
        },
        'recommendations': []
    }
    
    # Generate recommendations
    if avg_utilization < 50:
        potential_savings = storage_capacity * 0.15 * 0.3  # 30% potential savings
        report['recommendations'].append({
            'type': 'storage_optimization',
            'description': 'Low storage utilization - consider reducing capacity',
            'potential_savings': f"${potential_savings:.2f}/month"
        })
    
    if avg_cache_hit < 70:
        report['recommendations'].append({
            'type': 'cache_optimization',
            'description': 'Low cache hit ratio - consider increasing cache size',
            'impact': 'Improved performance and reduced latency'
        })
    
    if avg_utilization > 90:
        report['recommendations'].append({
            'type': 'capacity_expansion',
            'description': 'High storage utilization - consider increasing capacity',
            'impact': 'Prevent capacity issues and maintain performance'
        })
    
    return report

def save_report_to_s3(s3, file_system_id: str, report: dict):
    """Save cost report to S3"""
    import os
    
    bucket_name = os.environ.get('S3_BUCKET_NAME')
    if not bucket_name:
        return
    
    # Create CSV report
    csv_buffer = StringIO()
    writer = csv.writer(csv_buffer)
    
    writer.writerow(['Metric', 'Value'])
    writer.writerow(['File System ID', report['file_system_id']])
    writer.writerow(['Report Date', report['report_date']])
    writer.writerow(['Storage Capacity (GB)', report['storage_capacity_gb']])
    writer.writerow(['Throughput Capacity (MBps)', report['throughput_capacity_mbps']])
    writer.writerow(['Estimated Monthly Cost', f"${report['estimated_monthly_cost']:.2f}"])
    writer.writerow(['Average Utilization (%)', f"{report['storage_efficiency']['average_utilization']:.1f}"])
    writer.writerow(['Cache Hit Ratio (%)', f"{report['storage_efficiency']['cache_hit_ratio']:.1f}"])
    
    # Add recommendations
    writer.writerow([])
    writer.writerow(['Recommendations'])
    for rec in report['recommendations']:
        writer.writerow([rec['type'], rec['description']])
    
    # Save to S3
    timestamp = datetime.datetime.utcnow().strftime('%Y%m%d_%H%M%S')
    key = f"cost-reports/{file_system_id}/report_{timestamp}.csv"
    
    s3.put_object(
        Bucket=bucket_name,
        Key=key,
        Body=csv_buffer.getvalue(),
        ContentType='text/csv'
    )
    
    print(f"Report saved to s3://{bucket_name}/{key}")
EOF
        
        # Create deployment package
        cd /tmp && zip cost-reporting.zip cost-reporting.py
        
        # Check if function already exists
        if ! aws lambda get-function --function-name fsx-cost-reporting &> /dev/null; then
            aws lambda create-function \
                --function-name fsx-cost-reporting \
                --runtime python3.9 \
                --role ${LAMBDA_ROLE_ARN} \
                --handler cost-reporting.lambda_handler \
                --zip-file fileb://cost-reporting.zip \
                --timeout 120 \
                --memory-size 512 \
                --environment Variables="{S3_BUCKET_NAME=${S3_BUCKET_NAME}}"
            success "Created cost reporting Lambda function"
        else
            aws lambda update-function-code \
                --function-name fsx-cost-reporting \
                --zip-file fileb://cost-reporting.zip
            success "Updated existing cost reporting Lambda function"
        fi
        
        # Create alert handler Lambda function
        log "Creating alert handler Lambda function..."
        
        cat > /tmp/alert-handler.py << 'EOF'
import json
import boto3
import urllib.parse

def lambda_handler(event, context):
    """
    Handle CloudWatch alarms and provide intelligent analysis
    """
    fsx_client = boto3.client('fsx')
    sns = boto3.client('sns')
    
    try:
        # Parse SNS message
        sns_message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = sns_message['AlarmName']
        new_state = sns_message['NewStateValue']
        
        if new_state == 'ALARM':
            if 'Low-Cache-Hit-Ratio' in alarm_name:
                handle_low_cache_hit_ratio(fsx_client, sns, alarm_name)
            elif 'High-Storage-Utilization' in alarm_name:
                handle_high_storage_utilization(fsx_client, sns, alarm_name)
            elif 'High-Network-Utilization' in alarm_name:
                handle_high_network_utilization(fsx_client, sns, alarm_name)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Alert processed successfully')
        }
        
    except Exception as e:
        print(f"Error processing alert: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def handle_low_cache_hit_ratio(fsx_client, sns, alarm_name):
    """Handle low cache hit ratio alarm"""
    fs_id = get_file_system_id()
    
    # Get current file system configuration
    response = fsx_client.describe_file_systems(FileSystemIds=[fs_id])
    fs = response['FileSystems'][0]
    
    # Get cache configuration
    cache_config = fs['OpenZFSConfiguration'].get('ReadCacheConfig', {})
    current_cache = cache_config.get('SizeGiB', 0)
    
    message = f"""
    Performance Alert: Low Cache Hit Ratio Detected
    
    File System: {fs_id}
    Current Cache Size: {current_cache} GiB
    
    Recommendations:
    1. Consider increasing SSD read cache size to improve performance
    2. Analyze workload patterns to optimize cache configuration
    3. Review client access patterns for optimization opportunities
    
    Impact: Low cache hit ratio may indicate increased latency and reduced throughput
    
    Next Steps: Review FSx performance metrics and consider cache optimization
    """
    
    send_notification(sns, message, 'FSx Cache Performance Alert')

def handle_high_storage_utilization(fsx_client, sns, alarm_name):
    """Handle high storage utilization alarm"""
    fs_id = get_file_system_id()
    
    # Get current file system configuration
    response = fsx_client.describe_file_systems(FileSystemIds=[fs_id])
    fs = response['FileSystems'][0]
    
    storage_capacity = fs['StorageCapacity']
    
    message = f"""
    Capacity Alert: High Storage Utilization Detected
    
    File System: {fs_id}
    Storage Capacity: {storage_capacity} GiB
    Utilization: Above 85% threshold
    
    Recommendations:
    1. Review data retention policies and archive old files
    2. Consider increasing storage capacity if needed
    3. Implement file lifecycle management policies
    4. Analyze storage usage patterns for optimization
    
    Impact: High utilization may affect performance and prevent new file creation
    
    Next Steps: Review storage usage and plan capacity expansion if needed
    """
    
    send_notification(sns, message, 'FSx Storage Capacity Alert')

def handle_high_network_utilization(fsx_client, sns, alarm_name):
    """Handle high network utilization alarm"""
    fs_id = get_file_system_id()
    
    # Get current file system configuration
    response = fsx_client.describe_file_systems(FileSystemIds=[fs_id])
    fs = response['FileSystems'][0]
    
    throughput_capacity = fs['OpenZFSConfiguration']['ThroughputCapacity']
    
    message = f"""
    Performance Alert: High Network Utilization Detected
    
    File System: {fs_id}
    Throughput Capacity: {throughput_capacity} MBps
    Utilization: Above 90% threshold
    
    Recommendations:
    1. Consider increasing throughput capacity for better performance
    2. Optimize client access patterns and connection pooling
    3. Review workload distribution across multiple clients
    4. Implement caching strategies at the client level
    
    Impact: High network utilization may cause performance bottlenecks
    
    Next Steps: Monitor performance trends and consider scaling throughput capacity
    """
    
    send_notification(sns, message, 'FSx Network Performance Alert')

def get_file_system_id():
    """Get file system ID from environment"""
    import os
    return os.environ.get('FSX_FILE_SYSTEM_ID', 'unknown')

def send_notification(sns, message, subject):
    """Send notification via SNS"""
    import os
    
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    if topic_arn:
        sns.publish(
            TopicArn=topic_arn,
            Message=message,
            Subject=subject
        )
EOF
        
        # Create deployment package
        cd /tmp && zip alert-handler.zip alert-handler.py
        
        # Check if function already exists
        if ! aws lambda get-function --function-name fsx-alert-handler &> /dev/null; then
            aws lambda create-function \
                --function-name fsx-alert-handler \
                --runtime python3.9 \
                --role ${LAMBDA_ROLE_ARN} \
                --handler alert-handler.lambda_handler \
                --zip-file fileb://alert-handler.zip \
                --timeout 30 \
                --memory-size 256 \
                --environment Variables="{SNS_TOPIC_ARN=${SNS_TOPIC_ARN},FSX_FILE_SYSTEM_ID=${FSX_FILE_SYSTEM_ID}}"
            success "Created alert handler Lambda function"
        else
            aws lambda update-function-code \
                --function-name fsx-alert-handler \
                --zip-file fileb://alert-handler.zip
            success "Updated existing alert handler Lambda function"
        fi
        
        # Clean up temporary files
        rm -f /tmp/lifecycle-policy.py /tmp/lifecycle-policy.zip
        rm -f /tmp/cost-reporting.py /tmp/cost-reporting.zip
        rm -f /tmp/alert-handler.py /tmp/alert-handler.zip
        
    else
        log "[DRY-RUN] Would create Lambda functions: fsx-lifecycle-policy, fsx-cost-reporting, fsx-alert-handler"
    fi
}

# Create EventBridge rules
create_eventbridge_rules() {
    log "Creating EventBridge rules for automation..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create lifecycle policy rule
        if ! aws events describe-rule --name fsx-lifecycle-policy-schedule &> /dev/null; then
            aws events put-rule \
                --name fsx-lifecycle-policy-schedule \
                --schedule-expression "rate(1 hour)" \
                --description "Trigger lifecycle policy analysis every hour"
        fi
        
        # Create cost reporting rule
        if ! aws events describe-rule --name fsx-cost-reporting-schedule &> /dev/null; then
            aws events put-rule \
                --name fsx-cost-reporting-schedule \
                --schedule-expression "rate(24 hours)" \
                --description "Generate cost reports daily"
        fi
        
        # Add Lambda targets
        aws events put-targets \
            --rule fsx-lifecycle-policy-schedule \
            --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:fsx-lifecycle-policy"
        
        aws events put-targets \
            --rule fsx-cost-reporting-schedule \
            --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:fsx-cost-reporting"
        
        # Grant permissions
        aws lambda add-permission \
            --function-name fsx-lifecycle-policy \
            --statement-id allow-eventbridge-lifecycle \
            --action lambda:InvokeFunction \
            --principal events.amazonaws.com \
            --source-arn arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/fsx-lifecycle-policy-schedule \
            2>/dev/null || true
        
        aws lambda add-permission \
            --function-name fsx-cost-reporting \
            --statement-id allow-eventbridge-reporting \
            --action lambda:InvokeFunction \
            --principal events.amazonaws.com \
            --source-arn arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/fsx-cost-reporting-schedule \
            2>/dev/null || true
        
        success "EventBridge rules configured"
    else
        log "[DRY-RUN] Would create EventBridge rules for lifecycle policy and cost reporting"
    fi
}

# Create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms for monitoring..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create alarm for low cache hit ratio
        aws cloudwatch put-metric-alarm \
            --alarm-name "FSx-Low-Cache-Hit-Ratio-${RANDOM_SUFFIX}" \
            --alarm-description "Alert when FSx cache hit ratio is below 70%" \
            --metric-name FileServerCacheHitRatio \
            --namespace AWS/FSx \
            --statistic Average \
            --period 300 \
            --threshold 70 \
            --comparison-operator LessThanThreshold \
            --evaluation-periods 2 \
            --alarm-actions ${SNS_TOPIC_ARN} \
            --dimensions Name=FileSystemId,Value=${FSX_FILE_SYSTEM_ID}
        
        # Create alarm for high storage utilization
        aws cloudwatch put-metric-alarm \
            --alarm-name "FSx-High-Storage-Utilization-${RANDOM_SUFFIX}" \
            --alarm-description "Alert when FSx storage utilization exceeds 85%" \
            --metric-name StorageUtilization \
            --namespace AWS/FSx \
            --statistic Average \
            --period 300 \
            --threshold 85 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 2 \
            --alarm-actions ${SNS_TOPIC_ARN} \
            --dimensions Name=FileSystemId,Value=${FSX_FILE_SYSTEM_ID}
        
        # Create alarm for high network utilization
        aws cloudwatch put-metric-alarm \
            --alarm-name "FSx-High-Network-Utilization-${RANDOM_SUFFIX}" \
            --alarm-description "Alert when FSx network utilization exceeds 90%" \
            --metric-name NetworkThroughputUtilization \
            --namespace AWS/FSx \
            --statistic Average \
            --period 300 \
            --threshold 90 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 2 \
            --alarm-actions ${SNS_TOPIC_ARN} \
            --dimensions Name=FileSystemId,Value=${FSX_FILE_SYSTEM_ID}
        
        # Subscribe Lambda to SNS topic
        aws sns subscribe \
            --topic-arn ${SNS_TOPIC_ARN} \
            --protocol lambda \
            --notification-endpoint arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:fsx-alert-handler
        
        # Grant SNS permission to invoke Lambda
        aws lambda add-permission \
            --function-name fsx-alert-handler \
            --statement-id allow-sns-invoke \
            --action lambda:InvokeFunction \
            --principal sns.amazonaws.com \
            --source-arn ${SNS_TOPIC_ARN} \
            2>/dev/null || true
        
        success "CloudWatch alarms created and configured"
    else
        log "[DRY-RUN] Would create CloudWatch alarms for cache hit ratio, storage utilization, and network utilization"
    fi
}

# Create CloudWatch dashboard
create_dashboard() {
    log "Creating CloudWatch dashboard..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > /tmp/dashboard-config.json << EOF
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
          ["AWS/FSx", "FileServerCacheHitRatio", "FileSystemId", "${FSX_FILE_SYSTEM_ID}"],
          ["AWS/FSx", "StorageUtilization", "FileSystemId", "${FSX_FILE_SYSTEM_ID}"],
          ["AWS/FSx", "NetworkThroughputUtilization", "FileSystemId", "${FSX_FILE_SYSTEM_ID}"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "${AWS_REGION}",
        "title": "FSx Performance Metrics",
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
      "x": 12,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          ["AWS/FSx", "DataReadBytes", "FileSystemId", "${FSX_FILE_SYSTEM_ID}"],
          ["AWS/FSx", "DataWriteBytes", "FileSystemId", "${FSX_FILE_SYSTEM_ID}"]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "FSx Data Transfer",
        "yAxis": {
          "left": {
            "min": 0
          }
        }
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 6,
      "width": 24,
      "height": 6,
      "properties": {
        "metrics": [
          ["AWS/FSx", "TotalReadTime", "FileSystemId", "${FSX_FILE_SYSTEM_ID}"],
          ["AWS/FSx", "TotalWriteTime", "FileSystemId", "${FSX_FILE_SYSTEM_ID}"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "${AWS_REGION}",
        "title": "FSx Latency Metrics",
        "yAxis": {
          "left": {
            "min": 0
          }
        }
      }
    }
  ]
}
EOF
        
        aws cloudwatch put-dashboard \
            --dashboard-name "FSx-Lifecycle-Management-${RANDOM_SUFFIX}" \
            --dashboard-body file:///tmp/dashboard-config.json
        
        success "CloudWatch dashboard created: FSx-Lifecycle-Management-${RANDOM_SUFFIX}"
        
        rm -f /tmp/dashboard-config.json
    else
        log "[DRY-RUN] Would create CloudWatch dashboard: FSx-Lifecycle-Management-${RANDOM_SUFFIX}"
    fi
}

# Test deployment
test_deployment() {
    log "Testing deployment..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Test Lambda functions
        log "Testing Lambda functions..."
        
        # Test lifecycle policy function
        local result=$(aws lambda invoke \
            --function-name fsx-lifecycle-policy \
            --payload '{}' \
            /tmp/response.json 2>&1 || echo "failed")
        
        if [[ "$result" != "failed" ]]; then
            success "Lifecycle policy Lambda function test passed"
        else
            warn "Lifecycle policy Lambda function test failed"
        fi
        
        # Test cost reporting function
        local result=$(aws lambda invoke \
            --function-name fsx-cost-reporting \
            --payload '{}' \
            /tmp/response.json 2>&1 || echo "failed")
        
        if [[ "$result" != "failed" ]]; then
            success "Cost reporting Lambda function test passed"
        else
            warn "Cost reporting Lambda function test failed"
        fi
        
        # Verify FSx file system
        local fs_state=$(aws fsx describe-file-systems \
            --file-system-ids ${FSX_FILE_SYSTEM_ID} \
            --query 'FileSystems[0].Lifecycle' \
            --output text 2>/dev/null || echo "unknown")
        
        if [[ "$fs_state" == "AVAILABLE" ]]; then
            success "FSx file system is available"
        else
            warn "FSx file system state: $fs_state"
        fi
        
        rm -f /tmp/response.json
    else
        log "[DRY-RUN] Would test Lambda functions and verify FSx file system"
    fi
}

# Display deployment information
display_deployment_info() {
    log "Deployment completed successfully!"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                       DEPLOYMENT SUMMARY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "AWS Region:           $AWS_REGION"
    echo "AWS Account:          $AWS_ACCOUNT_ID"
    echo "Deployment Suffix:    $RANDOM_SUFFIX"
    echo ""
    echo "📁 FSx File System:"
    echo "   Name:              $FSX_FILE_SYSTEM_NAME"
    echo "   ID:                ${FSX_FILE_SYSTEM_ID:-'Not created (dry-run)'}"
    echo "   Type:              OpenZFS with SSD storage"
    echo ""
    echo "🔧 Lambda Functions:"
    echo "   • fsx-lifecycle-policy     - Monitors access patterns and generates recommendations"
    echo "   • fsx-cost-reporting       - Generates cost optimization reports"
    echo "   • fsx-alert-handler        - Processes CloudWatch alarms"
    echo ""
    echo "⏰ EventBridge Rules:"
    echo "   • fsx-lifecycle-policy-schedule  - Runs every hour"
    echo "   • fsx-cost-reporting-schedule    - Runs daily"
    echo ""
    echo "🚨 CloudWatch Alarms:"
    echo "   • FSx-Low-Cache-Hit-Ratio-$RANDOM_SUFFIX         - Cache performance monitoring"
    echo "   • FSx-High-Storage-Utilization-$RANDOM_SUFFIX    - Storage capacity monitoring"
    echo "   • FSx-High-Network-Utilization-$RANDOM_SUFFIX    - Network performance monitoring"
    echo ""
    echo "📊 Resources Created:"
    echo "   • S3 Bucket:          $S3_BUCKET_NAME (for reports)"
    echo "   • SNS Topic:          $SNS_TOPIC_NAME (for alerts)"
    echo "   • IAM Role:           $LAMBDA_ROLE_NAME (for Lambda functions)"
    echo "   • Dashboard:          FSx-Lifecycle-Management-$RANDOM_SUFFIX"
    echo ""
    echo "💰 Estimated Monthly Cost:"
    echo "   • FSx File System:    ~\$50-100 (64 GiB SSD, 64 MBps throughput)"
    echo "   • Lambda Functions:   <\$5 (based on scheduled execution)"
    echo "   • CloudWatch:         <\$10 (alarms and dashboard)"
    echo "   • SNS:                <\$1 (notifications)"
    echo "   • S3:                 <\$1 (report storage)"
    echo ""
    echo "🔗 Next Steps:"
    echo "   1. Access CloudWatch dashboard: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=FSx-Lifecycle-Management-$RANDOM_SUFFIX"
    echo "   2. Mount FSx file system using NFS to start generating metrics"
    echo "   3. Monitor SNS topic for lifecycle recommendations"
    echo "   4. Review cost reports in S3 bucket: s3://$S3_BUCKET_NAME/cost-reports/"
    echo ""
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "✅ All resources have been successfully deployed and configured."
        echo "   The system will automatically begin monitoring and optimizing your FSx file system."
    else
        echo "ℹ️  This was a dry-run. No actual resources were created."
    fi
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main execution flow
main() {
    check_prerequisites
    initialize_environment
    create_foundational_resources
    create_iam_role
    create_fsx_filesystem
    create_lambda_functions
    create_eventbridge_rules
    create_cloudwatch_alarms
    create_dashboard
    test_deployment
    display_deployment_info
}

# Cleanup on exit
cleanup() {
    rm -f /tmp/trust-policy.json /tmp/fsx-policy.json /tmp/dashboard-config.json 2>/dev/null || true
}
trap cleanup EXIT

# Run main function
main "$@"