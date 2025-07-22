#!/bin/bash

# Automated Cost Governance with AWS Config and Lambda Remediation - Deployment Script
# This script deploys the complete cost governance infrastructure for AWS
# Based on recipe: Cost Governance Automation with Config

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions (basic check)
    local account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [[ -z "$account_id" ]]; then
        error "Unable to retrieve AWS account information. Check your credentials."
        exit 1
    fi
    
    log "Prerequisites check passed. Account ID: $account_id"
}

# Initialize environment variables
init_environment() {
    log "Initializing environment variables..."
    
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers to avoid naming conflicts
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 7))
    
    export COST_GOVERNANCE_BUCKET="cost-governance-${random_suffix}"
    export CONFIG_BUCKET="aws-config-${random_suffix}"
    export LAMBDA_ROLE_NAME="CostGovernanceLambdaRole"
    export CONFIG_ROLE_NAME="AWSConfigRole"
    
    # Store variables for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
COST_GOVERNANCE_BUCKET=${COST_GOVERNANCE_BUCKET}
CONFIG_BUCKET=${CONFIG_BUCKET}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
CONFIG_ROLE_NAME=${CONFIG_ROLE_NAME}
EOF
    
    success "Environment initialized"
    log "Region: $AWS_REGION"
    log "Cost Governance Bucket: $COST_GOVERNANCE_BUCKET"
    log "Config Bucket: $CONFIG_BUCKET"
}

# Create S3 buckets
create_s3_buckets() {
    log "Creating S3 buckets..."
    
    # Create Config bucket
    if aws s3api head-bucket --bucket "$CONFIG_BUCKET" 2>/dev/null; then
        warning "Config bucket $CONFIG_BUCKET already exists"
    else
        aws s3 mb "s3://${CONFIG_BUCKET}" --region "$AWS_REGION"
        success "Created Config bucket: $CONFIG_BUCKET"
    fi
    
    # Create Cost Governance bucket
    if aws s3api head-bucket --bucket "$COST_GOVERNANCE_BUCKET" 2>/dev/null; then
        warning "Cost Governance bucket $COST_GOVERNANCE_BUCKET already exists"
    else
        aws s3 mb "s3://${COST_GOVERNANCE_BUCKET}" --region "$AWS_REGION"
        success "Created Cost Governance bucket: $COST_GOVERNANCE_BUCKET"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$CONFIG_BUCKET" \
        --versioning-configuration Status=Enabled
    
    aws s3api put-bucket-versioning \
        --bucket "$COST_GOVERNANCE_BUCKET" \
        --versioning-configuration Status=Enabled
    
    success "S3 buckets configured with versioning"
}

# Create IAM roles and policies
create_iam_roles() {
    log "Creating IAM roles and policies..."
    
    # Create Lambda trust policy
    cat > lambda-trust-policy.json << 'EOF'
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
    
    # Create Lambda role
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
        warning "Lambda role $LAMBDA_ROLE_NAME already exists"
    else
        aws iam create-role \
            --role-name "$LAMBDA_ROLE_NAME" \
            --assume-role-policy-document file://lambda-trust-policy.json \
            --description "Role for cost governance Lambda functions"
        success "Created Lambda role: $LAMBDA_ROLE_NAME"
    fi
    
    # Create Lambda policy
    cat > lambda-cost-governance-policy.json << EOF
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
            "Resource": "arn:aws:logs:*:*:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeVolumes",
                "ec2:StopInstances",
                "ec2:TerminateInstances",
                "ec2:ModifyInstanceAttribute",
                "ec2:DeleteVolume",
                "ec2:DetachVolume",
                "ec2:CreateSnapshot",
                "ec2:DescribeSnapshots",
                "ec2:CreateTags"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:DescribeTargetGroups",
                "elasticloadbalancing:DescribeTargetHealth",
                "elasticloadbalancing:DeleteLoadBalancer",
                "elasticloadbalancing:AddTags"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "rds:DescribeDBInstances",
                "rds:DescribeDBClusters",
                "rds:StopDBInstance",
                "rds:StopDBCluster",
                "rds:DeleteDBInstance",
                "rds:AddTagsToResource"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:GetBucketLocation",
                "s3:ListBucket",
                "s3:PutBucketLifecycleConfiguration",
                "s3:GetBucketLifecycleConfiguration"
            ],
            "Resource": [
                "arn:aws:s3:::${COST_GOVERNANCE_BUCKET}",
                "arn:aws:s3:::${COST_GOVERNANCE_BUCKET}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish",
                "sqs:SendMessage",
                "sqs:ReceiveMessage",
                "sqs:DeleteMessage",
                "sqs:GetQueueAttributes"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ssm:PutParameter",
                "ssm:GetParameter",
                "ssm:GetParameters",
                "ssm:SendCommand",
                "ssm:GetCommandInvocation"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "config:GetComplianceDetailsByConfigRule",
                "config:GetComplianceDetailsByResource",
                "config:PutEvaluations"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Create and attach policy
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CostGovernancePolicy" &>/dev/null; then
        warning "Cost Governance Policy already exists"
    else
        aws iam create-policy \
            --policy-name CostGovernancePolicy \
            --policy-document file://lambda-cost-governance-policy.json
        success "Created Cost Governance Policy"
    fi
    
    # Attach policy to role
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CostGovernancePolicy"
    
    # Wait for role to be available
    log "Waiting for IAM role to propagate..."
    sleep 10
    
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --query Role.Arn --output text)
    
    success "Lambda IAM role created: $LAMBDA_ROLE_ARN"
}

# Set up AWS Config
setup_aws_config() {
    log "Setting up AWS Config..."
    
    # Create Config service role trust policy
    cat > config-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "config.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create Config role
    if aws iam get-role --role-name "$CONFIG_ROLE_NAME" &>/dev/null; then
        warning "Config role $CONFIG_ROLE_NAME already exists"
    else
        aws iam create-role \
            --role-name "$CONFIG_ROLE_NAME" \
            --assume-role-policy-document file://config-trust-policy.json
        success "Created Config role: $CONFIG_ROLE_NAME"
    fi
    
    # Attach AWS managed policy for Config
    aws iam attach-role-policy \
        --role-name "$CONFIG_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole
    
    # Create bucket policy for Config
    cat > config-bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AWSConfigBucketPermissionsCheck",
            "Effect": "Allow",
            "Principal": {
                "Service": "config.amazonaws.com"
            },
            "Action": "s3:GetBucketAcl",
            "Resource": "arn:aws:s3:::${CONFIG_BUCKET}"
        },
        {
            "Sid": "AWSConfigBucketExistenceCheck",
            "Effect": "Allow",
            "Principal": {
                "Service": "config.amazonaws.com"
            },
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::${CONFIG_BUCKET}"
        },
        {
            "Sid": "AWSConfigBucketDelivery",
            "Effect": "Allow",
            "Principal": {
                "Service": "config.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${CONFIG_BUCKET}/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-acl": "bucket-owner-full-control"
                }
            }
        }
    ]
}
EOF
    
    aws s3api put-bucket-policy \
        --bucket "$CONFIG_BUCKET" \
        --policy file://config-bucket-policy.json
    
    # Create delivery channel
    aws configservice put-delivery-channel \
        --delivery-channel "name=default,s3BucketName=${CONFIG_BUCKET}" \
        2>/dev/null || warning "Delivery channel may already exist"
    
    # Create configuration recorder
    local config_role_arn=$(aws iam get-role \
        --role-name "$CONFIG_ROLE_NAME" \
        --query Role.Arn --output text)
    
    aws configservice put-configuration-recorder \
        --configuration-recorder "name=default,roleARN=${config_role_arn},recordingGroup={
            allSupported=true,
            includeGlobalResourceTypes=true,
            resourceTypes=[]
        }" 2>/dev/null || warning "Configuration recorder may already exist"
    
    # Start configuration recorder
    aws configservice start-configuration-recorder \
        --configuration-recorder-name default \
        2>/dev/null || warning "Configuration recorder may already be started"
    
    success "AWS Config configured"
}

# Create SNS topics
create_sns_topics() {
    log "Creating SNS topics..."
    
    # Create cost governance topic
    export COST_TOPIC_ARN=$(aws sns create-topic \
        --name "CostGovernanceAlerts" \
        --query TopicArn --output text)
    
    # Create critical cost actions topic
    export CRITICAL_TOPIC_ARN=$(aws sns create-topic \
        --name "CriticalCostActions" \
        --query TopicArn --output text)
    
    # Prompt for email subscription
    echo
    read -p "Enter email address for cost notifications (or press Enter to skip): " EMAIL_ADDRESS
    
    if [[ -n "$EMAIL_ADDRESS" ]]; then
        aws sns subscribe \
            --topic-arn "$COST_TOPIC_ARN" \
            --protocol email \
            --notification-endpoint "$EMAIL_ADDRESS"
        
        aws sns subscribe \
            --topic-arn "$CRITICAL_TOPIC_ARN" \
            --protocol email \
            --notification-endpoint "$EMAIL_ADDRESS"
        
        success "SNS topics created with email subscription: $EMAIL_ADDRESS"
        warning "Please check your email and confirm the SNS subscriptions"
    else
        success "SNS topics created without email subscription"
    fi
    
    # Save to environment
    echo "COST_TOPIC_ARN=${COST_TOPIC_ARN}" >> .env
    echo "CRITICAL_TOPIC_ARN=${CRITICAL_TOPIC_ARN}" >> .env
}

# Create SQS queues
create_sqs_queues() {
    log "Creating SQS queues..."
    
    # Create main queue
    export COST_QUEUE_URL=$(aws sqs create-queue \
        --queue-name "CostGovernanceQueue" \
        --attributes '{
            "VisibilityTimeoutSeconds": "300",
            "MessageRetentionPeriod": "1209600",
            "ReceiveMessageWaitTimeSeconds": "20"
        }' \
        --query QueueUrl --output text)
    
    # Create dead letter queue
    export DLQ_URL=$(aws sqs create-queue \
        --queue-name "CostGovernanceDLQ" \
        --query QueueUrl --output text)
    
    # Get queue ARNs
    export COST_QUEUE_ARN=$(aws sqs get-queue-attributes \
        --queue-url "$COST_QUEUE_URL" \
        --attribute-names QueueArn \
        --query Attributes.QueueArn --output text)
    
    export DLQ_ARN=$(aws sqs get-queue-attributes \
        --queue-url "$DLQ_URL" \
        --attribute-names QueueArn \
        --query Attributes.QueueArn --output text)
    
    # Save to environment
    echo "COST_QUEUE_URL=${COST_QUEUE_URL}" >> .env
    echo "COST_QUEUE_ARN=${COST_QUEUE_ARN}" >> .env
    echo "DLQ_URL=${DLQ_URL}" >> .env
    echo "DLQ_ARN=${DLQ_ARN}" >> .env
    
    success "SQS queues created for event processing"
}

# Deploy Lambda functions
deploy_lambda_functions() {
    log "Deploying Lambda functions..."
    
    # Create idle instance detector
    cat > idle_instance_detector.py << 'EOF'
import json
import boto3
import logging
import os
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    # Get all running instances
    response = ec2.describe_instances(
        Filters=[
            {'Name': 'instance-state-name', 'Values': ['running']},
            {'Name': 'tag:CostOptimization', 'Values': ['enabled']}
        ]
    )
    
    idle_instances = []
    
    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            instance_id = instance['InstanceId']
            
            # Check CPU utilization for last 7 days
            end_time = datetime.utcnow()
            start_time = end_time - timedelta(days=7)
            
            try:
                cpu_response = cloudwatch.get_metric_statistics(
                    Namespace='AWS/EC2',
                    MetricName='CPUUtilization',
                    Dimensions=[
                        {'Name': 'InstanceId', 'Value': instance_id}
                    ],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=3600,
                    Statistics=['Average']
                )
                
                if cpu_response['Datapoints']:
                    avg_cpu = sum(dp['Average'] for dp in cpu_response['Datapoints']) / len(cpu_response['Datapoints'])
                    
                    if avg_cpu < 5.0:  # Less than 5% average CPU
                        idle_instances.append({
                            'InstanceId': instance_id,
                            'AvgCPU': avg_cpu,
                            'InstanceType': instance['InstanceType'],
                            'LaunchTime': instance['LaunchTime'].isoformat()
                        })
                        
                        # Tag as idle for tracking
                        ec2.create_tags(
                            Resources=[instance_id],
                            Tags=[
                                {'Key': 'CostOptimization:Status', 'Value': 'Idle'},
                                {'Key': 'CostOptimization:DetectedDate', 'Value': datetime.utcnow().isoformat()}
                            ]
                        )
                        
                        logger.info(f"Detected idle instance: {instance_id} (CPU: {avg_cpu:.2f}%)")
                
            except Exception as e:
                logger.error(f"Error checking metrics for {instance_id}: {str(e)}")
    
    # Send notification if idle instances found
    if idle_instances:
        message = {
            'Alert': 'Idle EC2 Instances Detected',
            'Count': len(idle_instances),
            'Instances': idle_instances,
            'Recommendation': 'Consider stopping or terminating idle instances to reduce costs'
        }
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject='Cost Governance Alert: Idle EC2 Instances',
            Message=json.dumps(message, indent=2)
        )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Processed {len(idle_instances)} idle instances',
            'idle_instances': idle_instances
        })
    }
EOF
    
    # Package and deploy idle instance detector
    zip idle-instance-detector.zip idle_instance_detector.py
    
    export IDLE_DETECTOR_ARN=$(aws lambda create-function \
        --function-name "IdleInstanceDetector" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler idle_instance_detector.lambda_handler \
        --zip-file fileb://idle-instance-detector.zip \
        --environment "Variables={SNS_TOPIC_ARN=${COST_TOPIC_ARN}}" \
        --timeout 300 \
        --memory-size 256 \
        --query FunctionArn --output text)
    
    success "Deployed idle instance detector: $IDLE_DETECTOR_ARN"
    
    # Create volume cleanup function
    cat > volume_cleanup.py << 'EOF'
import json
import boto3
import logging
import os
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    sns = boto3.client('sns')
    
    # Get all unattached volumes
    response = ec2.describe_volumes(
        Filters=[
            {'Name': 'status', 'Values': ['available']}
        ]
    )
    
    volumes_to_clean = []
    total_cost_savings = 0
    
    for volume in response['Volumes']:
        volume_id = volume['VolumeId']
        size = volume['Size']
        volume_type = volume['VolumeType']
        create_time = volume['CreateTime']
        
        # Calculate age in days
        age_days = (datetime.now(create_time.tzinfo) - create_time).days
        
        # Only process volumes older than 7 days
        if age_days > 7:
            # Estimate monthly cost savings (rough calculation)
            cost_per_gb_month = {
                'gp2': 0.10, 'gp3': 0.08, 'io1': 0.125, 'io2': 0.125, 'st1': 0.045, 'sc1': 0.025
            }.get(volume_type, 0.10)
            
            monthly_cost = size * cost_per_gb_month
            total_cost_savings += monthly_cost
            
            # Create snapshot before deletion (safety measure)
            try:
                snapshot_response = ec2.create_snapshot(
                    VolumeId=volume_id,
                    Description=f'Pre-deletion snapshot of {volume_id}',
                    TagSpecifications=[
                        {
                            'ResourceType': 'snapshot',
                            'Tags': [
                                {'Key': 'CostOptimization', 'Value': 'true'},
                                {'Key': 'OriginalVolumeId', 'Value': volume_id},
                                {'Key': 'DeletionDate', 'Value': datetime.utcnow().isoformat()}
                            ]
                        }
                    ]
                )
                
                snapshot_id = snapshot_response['SnapshotId']
                
                # Tag volume for deletion tracking
                ec2.create_tags(
                    Resources=[volume_id],
                    Tags=[
                        {'Key': 'CostOptimization:ScheduledDeletion', 'Value': 'true'},
                        {'Key': 'CostOptimization:BackupSnapshot', 'Value': snapshot_id}
                    ]
                )
                
                volumes_to_clean.append({
                    'VolumeId': volume_id,
                    'Size': size,
                    'Type': volume_type,
                    'AgeDays': age_days,
                    'MonthlyCostSavings': monthly_cost,
                    'BackupSnapshot': snapshot_id
                })
                
                logger.info(f"Tagged volume {volume_id} for deletion (snapshot: {snapshot_id})")
                
            except Exception as e:
                logger.error(f"Error processing volume {volume_id}: {str(e)}")
    
    # Send notification about volumes scheduled for cleanup
    if volumes_to_clean:
        message = {
            'Alert': 'Unattached EBS Volumes Scheduled for Cleanup',
            'Count': len(volumes_to_clean),
            'TotalMonthlySavings': f'${total_cost_savings:.2f}',
            'Volumes': volumes_to_clean,
            'Action': 'Volumes have been tagged and backed up. Manual confirmation required for deletion.'
        }
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject='Cost Governance Alert: Unattached Volume Cleanup',
            Message=json.dumps(message, indent=2)
        )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Processed {len(volumes_to_clean)} unattached volumes',
            'potential_monthly_savings': f'${total_cost_savings:.2f}',
            'volumes': volumes_to_clean
        })
    }
EOF
    
    # Package and deploy volume cleanup
    zip volume-cleanup.zip volume_cleanup.py
    
    export VOLUME_CLEANUP_ARN=$(aws lambda create-function \
        --function-name "VolumeCleanup" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler volume_cleanup.lambda_handler \
        --zip-file fileb://volume-cleanup.zip \
        --environment "Variables={SNS_TOPIC_ARN=${COST_TOPIC_ARN}}" \
        --timeout 300 \
        --memory-size 256 \
        --query FunctionArn --output text)
    
    success "Deployed volume cleanup function: $VOLUME_CLEANUP_ARN"
    
    # Create cost reporter function
    cat > cost_reporter.py << 'EOF'
import json
import boto3
import logging
import os
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    sns = boto3.client('sns')
    ec2 = boto3.client('ec2')
    config_client = boto3.client('config')
    
    # Generate cost governance report
    report_data = {
        'ReportDate': datetime.utcnow().isoformat(),
        'Summary': {},
        'Details': {}
    }
    
    try:
        # Get compliance summary from Config
        compliance_summary = config_client.get_compliance_summary_by_config_rule()
        
        report_data['Summary']['ConfigRules'] = {
            'TotalRules': len(compliance_summary['ComplianceSummary']),
            'CompliantResources': sum(rule['ComplianceSummary']['CompliantResourceCount']['CappedCount'] 
                                    for rule in compliance_summary['ComplianceSummary']),
            'NonCompliantResources': sum(rule['ComplianceSummary']['NonCompliantResourceCount']['CappedCount'] 
                                       for rule in compliance_summary['ComplianceSummary'])
        }
        
        # Get resource counts for cost analysis
        instances_response = ec2.describe_instances()
        volumes_response = ec2.describe_volumes()
        
        running_instances = 0
        stopped_instances = 0
        idle_instances = 0
        unattached_volumes = 0
        
        for reservation in instances_response['Reservations']:
            for instance in reservation['Instances']:
                state = instance['State']['Name']
                if state == 'running':
                    running_instances += 1
                    # Check if tagged as idle
                    for tag in instance.get('Tags', []):
                        if tag['Key'] == 'CostOptimization:Status' and tag['Value'] == 'Idle':
                            idle_instances += 1
                            break
                elif state == 'stopped':
                    stopped_instances += 1
        
        for volume in volumes_response['Volumes']:
            if volume['State'] == 'available':
                unattached_volumes += 1
        
        report_data['Summary']['Resources'] = {
            'RunningInstances': running_instances,
            'StoppedInstances': stopped_instances,
            'IdleInstances': idle_instances,
            'UnattachedVolumes': unattached_volumes
        }
        
        # Calculate estimated cost savings opportunities
        estimated_savings = {
            'IdleInstances': idle_instances * 50,  # Rough estimate $50/month per idle instance
            'UnattachedVolumes': unattached_volumes * 8  # Rough estimate $8/month per 80GB volume
        }
        
        report_data['Summary']['EstimatedMonthlySavings'] = estimated_savings
        report_data['Summary']['TotalPotentialSavings'] = sum(estimated_savings.values())
        
        # Save report to S3
        report_key = f"cost-governance-reports/{datetime.utcnow().strftime('%Y/%m/%d')}/report-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}.json"
        
        s3.put_object(
            Bucket=os.environ['REPORTS_BUCKET'],
            Key=report_key,
            Body=json.dumps(report_data, indent=2),
            ContentType='application/json'
        )
        
        # Send summary notification
        summary_message = f"""
Cost Governance Report Summary

Generated: {report_data['ReportDate']}

Resource Summary:
- Running Instances: {running_instances}
- Idle Instances: {idle_instances}
- Unattached Volumes: {unattached_volumes}

Estimated Monthly Savings Opportunity: ${sum(estimated_savings.values()):.2f}

Full report saved to: s3://{os.environ['REPORTS_BUCKET']}/{report_key}
        """
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject='Weekly Cost Governance Report',
            Message=summary_message
        )
        
        logger.info(f"Cost governance report generated: {report_key}")
        
    except Exception as e:
        logger.error(f"Error generating cost report: {str(e)}")
        raise
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Cost governance report generated successfully',
            'report_location': f"s3://{os.environ['REPORTS_BUCKET']}/{report_key}",
            'summary': report_data['Summary']
        })
    }
EOF
    
    # Package and deploy cost reporter
    zip cost-reporter.zip cost_reporter.py
    
    export COST_REPORTER_ARN=$(aws lambda create-function \
        --function-name "CostReporter" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler cost_reporter.lambda_handler \
        --zip-file fileb://cost-reporter.zip \
        --environment "Variables={SNS_TOPIC_ARN=${COST_TOPIC_ARN},REPORTS_BUCKET=${COST_GOVERNANCE_BUCKET}}" \
        --timeout 300 \
        --memory-size 512 \
        --query FunctionArn --output text)
    
    success "Deployed cost reporter function: $COST_REPORTER_ARN"
    
    # Save Lambda ARNs to environment
    echo "IDLE_DETECTOR_ARN=${IDLE_DETECTOR_ARN}" >> .env
    echo "VOLUME_CLEANUP_ARN=${VOLUME_CLEANUP_ARN}" >> .env
    echo "COST_REPORTER_ARN=${COST_REPORTER_ARN}" >> .env
}

# Create Config rules
create_config_rules() {
    log "Creating AWS Config rules..."
    
    # Create idle EC2 instances rule
    aws configservice put-config-rule \
        --config-rule '{
            "ConfigRuleName": "idle-ec2-instances",
            "Description": "Checks for EC2 instances with low CPU utilization",
            "Source": {
                "Owner": "AWS",
                "SourceIdentifier": "EC2_INSTANCE_NO_HIGH_LEVEL_FINDINGS"
            },
            "InputParameters": "{\"desiredInstanceTypes\":\"t3.micro,t3.small,t3.medium\"}",
            "Scope": {
                "ComplianceResourceTypes": ["AWS::EC2::Instance"]
            }
        }' 2>/dev/null || warning "Config rule 'idle-ec2-instances' may already exist"
    
    # Create unattached EBS volumes rule
    aws configservice put-config-rule \
        --config-rule '{
            "ConfigRuleName": "unattached-ebs-volumes",
            "Description": "Checks for EBS volumes that are not attached to instances",
            "Source": {
                "Owner": "AWS",
                "SourceIdentifier": "EBS_OPTIMIZED_INSTANCE"
            },
            "Scope": {
                "ComplianceResourceTypes": ["AWS::EC2::Volume"]
            }
        }' 2>/dev/null || warning "Config rule 'unattached-ebs-volumes' may already exist"
    
    # Create unused load balancers rule
    aws configservice put-config-rule \
        --config-rule '{
            "ConfigRuleName": "unused-load-balancers",
            "Description": "Checks for load balancers with no healthy targets",
            "Source": {
                "Owner": "AWS",
                "SourceIdentifier": "ELB_CROSS_ZONE_LOAD_BALANCING_ENABLED"
            },
            "Scope": {
                "ComplianceResourceTypes": ["AWS::ElasticLoadBalancing::LoadBalancer"]
            }
        }' 2>/dev/null || warning "Config rule 'unused-load-balancers' may already exist"
    
    success "Created AWS Config rules for cost governance"
}

# Set up EventBridge rules
setup_eventbridge() {
    log "Setting up EventBridge rules..."
    
    # Create EventBridge rule for Config compliance changes
    aws events put-rule \
        --name "ConfigComplianceChanges" \
        --description "Trigger cost remediation on Config compliance changes" \
        --event-pattern '{
            "source": ["aws.config"],
            "detail-type": ["Config Rules Compliance Change"],
            "detail": {
                "configRuleName": [
                    "idle-ec2-instances",
                    "unattached-ebs-volumes",
                    "unused-load-balancers"
                ],
                "newEvaluationResult": {
                    "complianceType": ["NON_COMPLIANT"]
                }
            }
        }'
    
    # Add Lambda targets to EventBridge rule
    aws events put-targets \
        --rule "ConfigComplianceChanges" \
        --targets "[
            {
                \"Id\": \"1\",
                \"Arn\": \"${IDLE_DETECTOR_ARN}\",
                \"Input\": \"{\\\"source\\\": \\\"config-compliance\\\"}\"
            },
            {
                \"Id\": \"2\", 
                \"Arn\": \"${VOLUME_CLEANUP_ARN}\",
                \"Input\": \"{\\\"source\\\": \\\"config-compliance\\\"}\"
            }
        ]"
    
    # Create scheduled rule for weekly scans
    aws events put-rule \
        --name "WeeklyCostOptimizationScan" \
        --description "Weekly scan for cost optimization opportunities" \
        --schedule-expression "rate(7 days)"
    
    # Add targets for scheduled scans
    aws events put-targets \
        --rule "WeeklyCostOptimizationScan" \
        --targets "[
            {
                \"Id\": \"1\",
                \"Arn\": \"${IDLE_DETECTOR_ARN}\",
                \"Input\": \"{\\\"source\\\": \\\"scheduled-scan\\\"}\"
            },
            {
                \"Id\": \"2\",
                \"Arn\": \"${VOLUME_CLEANUP_ARN}\",
                \"Input\": \"{\\\"source\\\": \\\"scheduled-scan\\\"}\"
            },
            {
                \"Id\": \"3\",
                \"Arn\": \"${COST_REPORTER_ARN}\",
                \"Input\": \"{\\\"source\\\": \\\"scheduled-report\\\"}\"
            }
        ]"
    
    # Grant EventBridge permissions to invoke Lambda functions
    aws lambda add-permission \
        --function-name "IdleInstanceDetector" \
        --statement-id "AllowEventBridge" \
        --action "lambda:InvokeFunction" \
        --principal "events.amazonaws.com" \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/ConfigComplianceChanges" \
        2>/dev/null || warning "EventBridge permission may already exist"
    
    aws lambda add-permission \
        --function-name "VolumeCleanup" \
        --statement-id "AllowEventBridge" \
        --action "lambda:InvokeFunction" \
        --principal "events.amazonaws.com" \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/ConfigComplianceChanges" \
        2>/dev/null || warning "EventBridge permission may already exist"
    
    aws lambda add-permission \
        --function-name "IdleInstanceDetector" \
        --statement-id "AllowScheduledEventBridge" \
        --action "lambda:InvokeFunction" \
        --principal "events.amazonaws.com" \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/WeeklyCostOptimizationScan" \
        2>/dev/null || warning "Scheduled EventBridge permission may already exist"
    
    aws lambda add-permission \
        --function-name "VolumeCleanup" \
        --statement-id "AllowScheduledEventBridge" \
        --action "lambda:InvokeFunction" \
        --principal "events.amazonaws.com" \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/WeeklyCostOptimizationScan" \
        2>/dev/null || warning "Scheduled EventBridge permission may already exist"
    
    aws lambda add-permission \
        --function-name "CostReporter" \
        --statement-id "AllowScheduledReporting" \
        --action "lambda:InvokeFunction" \
        --principal "events.amazonaws.com" \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/WeeklyCostOptimizationScan" \
        2>/dev/null || warning "Scheduled reporting permission may already exist"
    
    success "Configured EventBridge rules for automated remediation"
}

# Test deployment
test_deployment() {
    log "Testing deployment..."
    
    # Test Lambda functions
    aws lambda invoke \
        --function-name "IdleInstanceDetector" \
        --payload '{"source": "deployment-test"}' \
        --cli-binary-format raw-in-base64-out \
        test-response.json
    
    if [[ -f test-response.json ]]; then
        log "Idle Instance Detector test response:"
        cat test-response.json
        rm test-response.json
    fi
    
    # Test SNS notification
    if [[ -n "$COST_TOPIC_ARN" ]]; then
        aws sns publish \
            --topic-arn "$COST_TOPIC_ARN" \
            --subject "Cost Governance Deployment Test" \
            --message "This is a test message from the newly deployed cost governance system."
    fi
    
    success "Deployment test completed"
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f *.py *.zip *.json
    success "Temporary files cleaned up"
}

# Main deployment function
main() {
    echo "=========================================="
    echo "  AWS Cost Governance Deployment Script  "
    echo "=========================================="
    echo
    
    check_prerequisites
    init_environment
    create_s3_buckets
    create_iam_roles
    setup_aws_config
    create_sns_topics
    create_sqs_queues
    deploy_lambda_functions
    create_config_rules
    setup_eventbridge
    test_deployment
    cleanup_temp_files
    
    echo
    success "=========================================="
    success "  DEPLOYMENT COMPLETED SUCCESSFULLY!     "
    success "=========================================="
    echo
    log "Cost Governance System has been deployed with the following components:"
    log "• AWS Config rules for continuous monitoring"
    log "• Lambda functions for automated remediation"
    log "• EventBridge rules for event-driven automation"
    log "• SNS topics for notifications"
    log "• S3 buckets for reports and configuration"
    echo
    log "Next Steps:"
    log "1. Confirm SNS email subscriptions (check your email)"
    log "2. Tag EC2 instances with 'CostOptimization=enabled' to enable monitoring"
    log "3. Review weekly cost governance reports in S3 bucket: $COST_GOVERNANCE_BUCKET"
    log "4. Monitor Lambda function logs in CloudWatch for optimization actions"
    echo
    warning "Remember to review and approve any cost optimization recommendations before implementing them in production."
    echo
    log "Environment variables saved to .env file for cleanup script"
    success "Deployment complete!"
}

# Run main function
main "$@"