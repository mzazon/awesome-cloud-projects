#!/bin/bash
set -e

# AWS Cost Optimization Automation - Deployment Script
# This script deploys the complete cost optimization system using Lambda and Trusted Advisor APIs

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
DEPLOYMENT_LOG="deployment_$(date +%Y%m%d_%H%M%S).log"
LAMBDA_DIR="lambda-functions"
TEMP_DIR="temp_deployment"

# Function to log messages
log_message() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message"
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$DEPLOYMENT_LOG"
}

# Function to check prerequisites
check_prerequisites() {
    log_message "INFO" "Checking prerequisites..."
    
    # Check AWS CLI installation
    if ! command -v aws &> /dev/null; then
        log_message "ERROR" "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | grep -oE 'aws-cli/[0-9]+\.[0-9]+\.[0-9]+' | cut -d'/' -f2)
    log_message "INFO" "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_message "ERROR" "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check support plan for Trusted Advisor API access
    local support_plan=$(aws support describe-trusted-advisor-checks --language en --query 'checks[0].name' --output text 2>/dev/null || echo "NO_ACCESS")
    if [[ "$support_plan" == "NO_ACCESS" ]]; then
        log_message "ERROR" "Business or Enterprise support plan required for Trusted Advisor API access."
        log_message "ERROR" "Please upgrade your AWS support plan: https://aws.amazon.com/premiumsupport/plans/"
        exit 1
    fi
    
    # Check required tools
    local required_tools=("zip" "jq" "python3")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_message "ERROR" "$tool is not installed. Please install $tool."
            exit 1
        fi
    done
    
    # Check Python version
    local python_version=$(python3 --version 2>&1 | grep -oE '[0-9]+\.[0-9]+')
    local major_version=$(echo "$python_version" | cut -d'.' -f1)
    local minor_version=$(echo "$python_version" | cut -d'.' -f2)
    
    if [[ "$major_version" -lt 3 || ("$major_version" -eq 3 && "$minor_version" -lt 9) ]]; then
        log_message "ERROR" "Python 3.9 or higher is required. Current version: $python_version"
        exit 1
    fi
    
    log_message "INFO" "Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    log_message "INFO" "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log_message "WARN" "AWS region not configured, using default: $AWS_REGION"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export COST_OPT_BUCKET="cost-optimization-reports-${random_suffix}"
    export COST_OPT_TABLE="cost-optimization-tracking-${random_suffix}"
    export COST_OPT_TOPIC="cost-optimization-alerts-${random_suffix}"
    export COST_OPT_ROLE="CostOptimizationLambdaRole"
    export COST_OPT_POLICY="CostOptimizationPolicy"
    
    log_message "INFO" "Environment variables set:"
    log_message "INFO" "  AWS_REGION: $AWS_REGION"
    log_message "INFO" "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
    log_message "INFO" "  COST_OPT_BUCKET: $COST_OPT_BUCKET"
    log_message "INFO" "  COST_OPT_TABLE: $COST_OPT_TABLE"
    log_message "INFO" "  COST_OPT_TOPIC: $COST_OPT_TOPIC"
    
    # Save environment variables for cleanup script
    cat > deployment_env.txt << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
COST_OPT_BUCKET=$COST_OPT_BUCKET
COST_OPT_TABLE=$COST_OPT_TABLE
COST_OPT_TOPIC=$COST_OPT_TOPIC
COST_OPT_ROLE=$COST_OPT_ROLE
COST_OPT_POLICY=$COST_OPT_POLICY
EOF
}

# Function to create IAM role and policy
create_iam_resources() {
    log_message "INFO" "Creating IAM role and policy..."
    
    # Create IAM role trust policy
    cat > trust-policy.json << 'EOF'
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
    if aws iam get-role --role-name "$COST_OPT_ROLE" &> /dev/null; then
        log_message "WARN" "IAM role $COST_OPT_ROLE already exists, skipping creation"
    else
        aws iam create-role \
            --role-name "$COST_OPT_ROLE" \
            --assume-role-policy-document file://trust-policy.json
        log_message "INFO" "IAM role $COST_OPT_ROLE created"
    fi
    
    # Create comprehensive policy for cost optimization
    cat > cost-optimization-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "support:DescribeTrustedAdvisorChecks",
                "support:DescribeTrustedAdvisorCheckResult",
                "support:RefreshTrustedAdvisorCheck",
                "ce:GetCostAndUsage",
                "ce:GetDimensionValues",
                "ce:GetUsageReport",
                "ce:GetReservationCoverage",
                "ce:GetReservationPurchaseRecommendation",
                "ce:GetReservationUtilization",
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query",
                "dynamodb:Scan",
                "sns:Publish",
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "ec2:DescribeInstances",
                "ec2:StopInstances",
                "ec2:TerminateInstances",
                "ec2:ModifyInstanceAttribute",
                "ec2:DescribeVolumes",
                "ec2:ModifyVolume",
                "ec2:CreateSnapshot",
                "rds:DescribeDBInstances",
                "rds:ModifyDBInstance",
                "rds:StopDBInstance",
                "lambda:InvokeFunction",
                "scheduler:*"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Attach policy to role
    aws iam put-role-policy \
        --role-name "$COST_OPT_ROLE" \
        --policy-name "$COST_OPT_POLICY" \
        --policy-document file://cost-optimization-policy.json
    
    log_message "INFO" "IAM policy attached to role"
    
    # Wait for role to be available
    log_message "INFO" "Waiting for IAM role to be available..."
    sleep 10
}

# Function to create foundation resources
create_foundation_resources() {
    log_message "INFO" "Creating foundation resources..."
    
    # Create S3 bucket for reports and Lambda deployment
    if aws s3api head-bucket --bucket "$COST_OPT_BUCKET" &> /dev/null; then
        log_message "WARN" "S3 bucket $COST_OPT_BUCKET already exists, skipping creation"
    else
        aws s3 mb "s3://$COST_OPT_BUCKET" --region "$AWS_REGION"
        log_message "INFO" "S3 bucket $COST_OPT_BUCKET created"
    fi
    
    # Create DynamoDB table for tracking optimization actions
    if aws dynamodb describe-table --table-name "$COST_OPT_TABLE" &> /dev/null; then
        log_message "WARN" "DynamoDB table $COST_OPT_TABLE already exists, skipping creation"
    else
        aws dynamodb create-table \
            --table-name "$COST_OPT_TABLE" \
            --attribute-definitions \
                AttributeName=ResourceId,AttributeType=S \
                AttributeName=CheckId,AttributeType=S \
            --key-schema \
                AttributeName=ResourceId,KeyType=HASH \
                AttributeName=CheckId,KeyType=RANGE \
            --provisioned-throughput \
                ReadCapacityUnits=5,WriteCapacityUnits=5 \
            --region "$AWS_REGION"
        
        log_message "INFO" "DynamoDB table $COST_OPT_TABLE created"
        
        # Wait for table to be active
        log_message "INFO" "Waiting for DynamoDB table to be active..."
        aws dynamodb wait table-exists --table-name "$COST_OPT_TABLE"
    fi
    
    # Create SNS topic for notifications
    if aws sns get-topic-attributes --topic-arn "arn:aws:sns:$AWS_REGION:$AWS_ACCOUNT_ID:$COST_OPT_TOPIC" &> /dev/null; then
        log_message "WARN" "SNS topic $COST_OPT_TOPIC already exists, skipping creation"
        export COST_OPT_TOPIC_ARN="arn:aws:sns:$AWS_REGION:$AWS_ACCOUNT_ID:$COST_OPT_TOPIC"
    else
        aws sns create-topic --name "$COST_OPT_TOPIC" --region "$AWS_REGION"
        export COST_OPT_TOPIC_ARN=$(aws sns list-topics \
            --query "Topics[?contains(TopicArn, '$COST_OPT_TOPIC')].TopicArn" \
            --output text)
        log_message "INFO" "SNS topic $COST_OPT_TOPIC created with ARN: $COST_OPT_TOPIC_ARN"
    fi
    
    # Update environment file with topic ARN
    echo "COST_OPT_TOPIC_ARN=$COST_OPT_TOPIC_ARN" >> deployment_env.txt
}

# Function to create Lambda function code
create_lambda_code() {
    log_message "INFO" "Creating Lambda function code..."
    
    # Create directory structure
    mkdir -p "$LAMBDA_DIR"/{cost-analysis,remediation}
    
    # Create cost analysis Lambda function
    cat > "$LAMBDA_DIR/cost-analysis/lambda_function.py" << 'EOF'
import json
import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal

def lambda_handler(event, context):
    """
    Main handler for cost analysis using Trusted Advisor APIs
    """
    print("Starting cost optimization analysis...")
    
    # Initialize AWS clients
    support_client = boto3.client('support', region_name='us-east-1')
    ce_client = boto3.client('ce')
    dynamodb = boto3.resource('dynamodb')
    lambda_client = boto3.client('lambda')
    
    # Get environment variables
    table_name = os.environ['COST_OPT_TABLE']
    remediation_function = os.environ['REMEDIATION_FUNCTION_NAME']
    
    table = dynamodb.Table(table_name)
    
    try:
        # Get list of cost optimization checks
        cost_checks = get_cost_optimization_checks(support_client)
        
        # Process each check
        optimization_opportunities = []
        for check in cost_checks:
            print(f"Processing check: {check['name']}")
            
            # Get check results
            check_result = support_client.describe_trusted_advisor_check_result(
                checkId=check['id'],
                language='en'
            )
            
            # Process flagged resources
            flagged_resources = check_result['result']['flaggedResources']
            
            for resource in flagged_resources:
                opportunity = {
                    'check_id': check['id'],
                    'check_name': check['name'],
                    'resource_id': resource['resourceId'],
                    'status': resource['status'],
                    'metadata': resource['metadata'],
                    'estimated_savings': extract_estimated_savings(resource),
                    'timestamp': datetime.now().isoformat()
                }
                
                # Store in DynamoDB
                store_optimization_opportunity(table, opportunity)
                
                # Add to opportunities list
                optimization_opportunities.append(opportunity)
        
        # Get additional cost insights from Cost Explorer
        cost_insights = get_cost_explorer_insights(ce_client)
        
        # Trigger remediation for auto-approved actions
        auto_remediation_results = []
        for opportunity in optimization_opportunities:
            if should_auto_remediate(opportunity):
                print(f"Triggering auto-remediation for: {opportunity['resource_id']}")
                
                remediation_payload = {
                    'opportunity': opportunity,
                    'action': 'auto_remediate'
                }
                
                response = lambda_client.invoke(
                    FunctionName=remediation_function,
                    InvocationType='Event',
                    Payload=json.dumps(remediation_payload)
                )
                
                auto_remediation_results.append({
                    'resource_id': opportunity['resource_id'],
                    'remediation_triggered': True
                })
        
        # Generate summary report
        report = generate_cost_optimization_report(
            optimization_opportunities, 
            cost_insights, 
            auto_remediation_results
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost optimization analysis completed successfully',
                'opportunities_found': len(optimization_opportunities),
                'auto_remediations_triggered': len(auto_remediation_results),
                'total_potential_savings': calculate_total_savings(optimization_opportunities),
                'report': report
            }, default=str)
        }
        
    except Exception as e:
        print(f"Error in cost analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

def get_cost_optimization_checks(support_client):
    """Get all cost optimization related Trusted Advisor checks"""
    response = support_client.describe_trusted_advisor_checks(language='en')
    
    cost_checks = []
    for check in response['checks']:
        if 'cost' in check['category'].lower():
            cost_checks.append({
                'id': check['id'],
                'name': check['name'],
                'category': check['category'],
                'description': check['description']
            })
    
    return cost_checks

def extract_estimated_savings(resource):
    """Extract estimated savings from resource metadata"""
    try:
        # Trusted Advisor stores savings in different metadata positions
        # depending on the check type
        metadata = resource.get('metadata', [])
        
        # Common patterns for savings extraction
        for item in metadata:
            if '$' in str(item) and any(keyword in str(item).lower() 
                                     for keyword in ['save', 'saving', 'cost']):
                # Extract numeric value
                import re
                savings_match = re.search(r'\$[\d,]+\.?\d*', str(item))
                if savings_match:
                    return float(savings_match.group().replace('$', '').replace(',', ''))
        
        return 0.0
    except:
        return 0.0

def store_optimization_opportunity(table, opportunity):
    """Store optimization opportunity in DynamoDB"""
    table.put_item(
        Item={
            'ResourceId': opportunity['resource_id'],
            'CheckId': opportunity['check_id'],
            'CheckName': opportunity['check_name'],
            'Status': opportunity['status'],
            'EstimatedSavings': Decimal(str(opportunity['estimated_savings'])),
            'Timestamp': opportunity['timestamp'],
            'Metadata': json.dumps(opportunity['metadata'])
        }
    )

def get_cost_explorer_insights(ce_client):
    """Get additional cost insights from Cost Explorer"""
    end_date = datetime.now()
    start_date = end_date - timedelta(days=30)
    
    try:
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'}
            ]
        )
        
        return response['ResultsByTime']
    except Exception as e:
        print(f"Error getting Cost Explorer insights: {str(e)}")
        return []

def should_auto_remediate(opportunity):
    """Determine if opportunity should be auto-remediated"""
    auto_remediate_checks = [
        'EC2 instances stopped',
        'EBS volumes unattached',
        'RDS idle DB instances'
    ]
    
    # Only auto-remediate for specific checks with high confidence
    return (opportunity['check_name'] in auto_remediate_checks and 
            opportunity['status'] == 'warning')

def generate_cost_optimization_report(opportunities, cost_insights, auto_remediations):
    """Generate comprehensive cost optimization report"""
    report = {
        'summary': {
            'total_opportunities': len(opportunities),
            'total_potential_savings': calculate_total_savings(opportunities),
            'auto_remediations_applied': len(auto_remediations),
            'analysis_date': datetime.now().isoformat()
        },
        'top_opportunities': sorted(opportunities, 
                                  key=lambda x: x['estimated_savings'], 
                                  reverse=True)[:10],
        'savings_by_category': categorize_savings(opportunities),
        'cost_trends': cost_insights
    }
    
    return report

def calculate_total_savings(opportunities):
    """Calculate total potential savings"""
    return sum(op['estimated_savings'] for op in opportunities)

def categorize_savings(opportunities):
    """Categorize savings by service type"""
    categories = {}
    for op in opportunities:
        service = extract_service_from_check(op['check_name'])
        if service not in categories:
            categories[service] = {'count': 0, 'total_savings': 0}
        categories[service]['count'] += 1
        categories[service]['total_savings'] += op['estimated_savings']
    
    return categories

def extract_service_from_check(check_name):
    """Extract AWS service from check name"""
    if 'EC2' in check_name:
        return 'EC2'
    elif 'RDS' in check_name:
        return 'RDS'
    elif 'EBS' in check_name:
        return 'EBS'
    elif 'S3' in check_name:
        return 'S3'
    elif 'ElastiCache' in check_name:
        return 'ElastiCache'
    else:
        return 'Other'
EOF
    
    # Create remediation Lambda function
    cat > "$LAMBDA_DIR/remediation/lambda_function.py" << 'EOF'
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Handle cost optimization remediation actions
    """
    print("Starting cost optimization remediation...")
    
    # Initialize AWS clients
    ec2_client = boto3.client('ec2')
    rds_client = boto3.client('rds')
    s3_client = boto3.client('s3')
    sns_client = boto3.client('sns')
    dynamodb = boto3.resource('dynamodb')
    
    # Get environment variables
    table_name = os.environ['COST_OPT_TABLE']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    table = dynamodb.Table(table_name)
    
    try:
        # Parse the incoming opportunity
        opportunity = event['opportunity']
        action = event.get('action', 'manual')
        
        print(f"Processing remediation for: {opportunity['resource_id']}")
        print(f"Check: {opportunity['check_name']}")
        
        # Route to appropriate remediation handler
        remediation_result = None
        
        if 'EC2' in opportunity['check_name']:
            remediation_result = handle_ec2_remediation(
                ec2_client, opportunity, action
            )
        elif 'RDS' in opportunity['check_name']:
            remediation_result = handle_rds_remediation(
                rds_client, opportunity, action
            )
        elif 'EBS' in opportunity['check_name']:
            remediation_result = handle_ebs_remediation(
                ec2_client, opportunity, action
            )
        elif 'S3' in opportunity['check_name']:
            remediation_result = handle_s3_remediation(
                s3_client, opportunity, action
            )
        else:
            remediation_result = {
                'status': 'skipped',
                'message': f"No automated remediation available for: {opportunity['check_name']}"
            }
        
        # Update tracking record
        update_remediation_tracking(table, opportunity, remediation_result)
        
        # Send notification
        send_remediation_notification(
            sns_client, sns_topic_arn, opportunity, remediation_result
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Remediation completed',
                'resource_id': opportunity['resource_id'],
                'remediation_result': remediation_result
            }, default=str)
        }
        
    except Exception as e:
        print(f"Error in remediation: {str(e)}")
        
        # Send error notification
        error_notification = {
            'resource_id': opportunity.get('resource_id', 'unknown'),
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }
        
        sns_client.publish(
            TopicArn=sns_topic_arn,
            Message=json.dumps(error_notification, indent=2),
            Subject='Cost Optimization Remediation Error'
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

def handle_ec2_remediation(ec2_client, opportunity, action):
    """Handle EC2-related cost optimization remediation"""
    resource_id = opportunity['resource_id']
    check_name = opportunity['check_name']
    
    try:
        if 'stopped' in check_name.lower():
            # For stopped instances, consider termination after validation
            instance_info = ec2_client.describe_instances(
                InstanceIds=[resource_id]
            )
            
            instance = instance_info['Reservations'][0]['Instances'][0]
            
            # Check if instance has been stopped for more than 30 days
            if should_terminate_stopped_instance(instance):
                if action == 'auto_remediate':
                    # Create snapshot before termination
                    create_instance_snapshot(ec2_client, resource_id)
                    
                    # Terminate instance
                    ec2_client.terminate_instances(InstanceIds=[resource_id])
                    
                    return {
                        'status': 'remediated',
                        'action': 'terminated',
                        'message': f'Terminated long-stopped instance {resource_id}',
                        'estimated_savings': opportunity['estimated_savings']
                    }
                else:
                    return {
                        'status': 'recommendation',
                        'action': 'terminate',
                        'message': f'Recommend terminating stopped instance {resource_id}',
                        'estimated_savings': opportunity['estimated_savings']
                    }
            
        elif 'underutilized' in check_name.lower():
            # For underutilized instances, recommend downsizing
            return {
                'status': 'recommendation',
                'action': 'downsize',
                'message': f'Recommend downsizing underutilized instance {resource_id}',
                'estimated_savings': opportunity['estimated_savings']
            }
        
        return {
            'status': 'analyzed',
            'message': f'No automatic remediation for {check_name}'
        }
        
    except Exception as e:
        return {
            'status': 'error',
            'message': f'Error handling EC2 remediation: {str(e)}'
        }

def handle_rds_remediation(rds_client, opportunity, action):
    """Handle RDS-related cost optimization remediation"""
    resource_id = opportunity['resource_id']
    check_name = opportunity['check_name']
    
    try:
        if 'idle' in check_name.lower():
            # For idle RDS instances, recommend stopping or deletion
            if action == 'auto_remediate':
                # Stop the RDS instance
                rds_client.stop_db_instance(
                    DBInstanceIdentifier=resource_id
                )
                
                return {
                    'status': 'remediated',
                    'action': 'stopped',
                    'message': f'Stopped idle RDS instance {resource_id}',
                    'estimated_savings': opportunity['estimated_savings']
                }
            else:
                return {
                    'status': 'recommendation',
                    'action': 'stop',
                    'message': f'Recommend stopping idle RDS instance {resource_id}',
                    'estimated_savings': opportunity['estimated_savings']
                }
        
        return {
            'status': 'analyzed',
            'message': f'No automatic remediation for {check_name}'
        }
        
    except Exception as e:
        return {
            'status': 'error',
            'message': f'Error handling RDS remediation: {str(e)}'
        }

def handle_ebs_remediation(ec2_client, opportunity, action):
    """Handle EBS-related cost optimization remediation"""
    resource_id = opportunity['resource_id']
    check_name = opportunity['check_name']
    
    try:
        if 'unattached' in check_name.lower():
            # For unattached volumes, create snapshot and delete
            if action == 'auto_remediate':
                # Create snapshot before deletion
                snapshot_response = ec2_client.create_snapshot(
                    VolumeId=resource_id,
                    Description=f'Automated snapshot before deleting unattached volume {resource_id}'
                )
                
                # Delete unattached volume
                ec2_client.delete_volume(VolumeId=resource_id)
                
                return {
                    'status': 'remediated',
                    'action': 'deleted',
                    'message': f'Deleted unattached EBS volume {resource_id}, snapshot: {snapshot_response["SnapshotId"]}',
                    'estimated_savings': opportunity['estimated_savings']
                }
            else:
                return {
                    'status': 'recommendation',
                    'action': 'delete',
                    'message': f'Recommend deleting unattached EBS volume {resource_id}',
                    'estimated_savings': opportunity['estimated_savings']
                }
        
        return {
            'status': 'analyzed',
            'message': f'No automatic remediation for {check_name}'
        }
        
    except Exception as e:
        return {
            'status': 'error',
            'message': f'Error handling EBS remediation: {str(e)}'
        }

def handle_s3_remediation(s3_client, opportunity, action):
    """Handle S3-related cost optimization remediation"""
    resource_id = opportunity['resource_id']
    check_name = opportunity['check_name']
    
    try:
        if 'lifecycle' in check_name.lower():
            # For S3 lifecycle issues, recommend lifecycle policies
            return {
                'status': 'recommendation',
                'action': 'configure_lifecycle',
                'message': f'Recommend configuring lifecycle policy for S3 bucket {resource_id}',
                'estimated_savings': opportunity['estimated_savings']
            }
        
        return {
            'status': 'analyzed',
            'message': f'No automatic remediation for {check_name}'
        }
        
    except Exception as e:
        return {
            'status': 'error',
            'message': f'Error handling S3 remediation: {str(e)}'
        }

def should_terminate_stopped_instance(instance):
    """Check if stopped instance should be terminated"""
    from datetime import datetime, timedelta
    
    # Check if instance has been stopped for more than 30 days
    if instance['State']['Name'] == 'stopped':
        # This is a simplified check - in practice, you'd want to check
        # CloudTrail logs or use custom tags to track stop duration
        return True
    
    return False

def create_instance_snapshot(ec2_client, instance_id):
    """Create snapshots of instance volumes before termination"""
    try:
        # Get instance volumes
        instance_info = ec2_client.describe_instances(
            InstanceIds=[instance_id]
        )
        
        instance = instance_info['Reservations'][0]['Instances'][0]
        
        # Create snapshots for all attached volumes
        for mapping in instance.get('BlockDeviceMappings', []):
            if 'Ebs' in mapping:
                volume_id = mapping['Ebs']['VolumeId']
                ec2_client.create_snapshot(
                    VolumeId=volume_id,
                    Description=f'Automated snapshot before terminating instance {instance_id}'
                )
        
    except Exception as e:
        print(f"Error creating snapshots: {str(e)}")

def update_remediation_tracking(table, opportunity, remediation_result):
    """Update DynamoDB tracking record with remediation results"""
    table.update_item(
        Key={
            'ResourceId': opportunity['resource_id'],
            'CheckId': opportunity['check_id']
        },
        UpdateExpression='SET RemediationStatus = :status, RemediationResult = :result, RemediationTimestamp = :timestamp',
        ExpressionAttributeValues={
            ':status': remediation_result['status'],
            ':result': json.dumps(remediation_result),
            ':timestamp': datetime.now().isoformat()
        }
    )

def send_remediation_notification(sns_client, topic_arn, opportunity, remediation_result):
    """Send notification about remediation action"""
    notification = {
        'resource_id': opportunity['resource_id'],
        'check_name': opportunity['check_name'],
        'remediation_status': remediation_result['status'],
        'remediation_action': remediation_result.get('action', 'none'),
        'estimated_savings': opportunity['estimated_savings'],
        'message': remediation_result.get('message', ''),
        'timestamp': datetime.now().isoformat()
    }
    
    subject = f"Cost Optimization: {remediation_result['status'].title()} - {opportunity['check_name']}"
    
    sns_client.publish(
        TopicArn=topic_arn,
        Message=json.dumps(notification, indent=2),
        Subject=subject
    )
EOF
    
    log_message "INFO" "Lambda function code created successfully"
}

# Function to deploy Lambda functions
deploy_lambda_functions() {
    log_message "INFO" "Deploying Lambda functions..."
    
    # Create temporary directory for deployment
    mkdir -p "$TEMP_DIR"
    
    # Package and deploy cost analysis function
    cd "$LAMBDA_DIR/cost-analysis"
    zip -r "../../$TEMP_DIR/cost-analysis-function.zip" .
    cd - > /dev/null
    
    # Deploy cost analysis function
    if aws lambda get-function --function-name cost-optimization-analysis &> /dev/null; then
        log_message "WARN" "Cost analysis function already exists, updating..."
        aws lambda update-function-code \
            --function-name cost-optimization-analysis \
            --zip-file "fileb://$TEMP_DIR/cost-analysis-function.zip"
    else
        aws lambda create-function \
            --function-name cost-optimization-analysis \
            --runtime python3.9 \
            --role "arn:aws:iam::$AWS_ACCOUNT_ID:role/$COST_OPT_ROLE" \
            --handler lambda_function.lambda_handler \
            --zip-file "fileb://$TEMP_DIR/cost-analysis-function.zip" \
            --timeout 300 \
            --memory-size 512 \
            --environment Variables="{
                COST_OPT_TABLE=$COST_OPT_TABLE,
                REMEDIATION_FUNCTION_NAME=cost-optimization-remediation
            }"
        log_message "INFO" "Cost analysis function deployed"
    fi
    
    # Package and deploy remediation function
    cd "$LAMBDA_DIR/remediation"
    zip -r "../../$TEMP_DIR/remediation-function.zip" .
    cd - > /dev/null
    
    # Deploy remediation function
    if aws lambda get-function --function-name cost-optimization-remediation &> /dev/null; then
        log_message "WARN" "Remediation function already exists, updating..."
        aws lambda update-function-code \
            --function-name cost-optimization-remediation \
            --zip-file "fileb://$TEMP_DIR/remediation-function.zip"
    else
        aws lambda create-function \
            --function-name cost-optimization-remediation \
            --runtime python3.9 \
            --role "arn:aws:iam::$AWS_ACCOUNT_ID:role/$COST_OPT_ROLE" \
            --handler lambda_function.lambda_handler \
            --zip-file "fileb://$TEMP_DIR/remediation-function.zip" \
            --timeout 300 \
            --memory-size 512 \
            --environment Variables="{
                COST_OPT_TABLE=$COST_OPT_TABLE,
                SNS_TOPIC_ARN=$COST_OPT_TOPIC_ARN
            }"
        log_message "INFO" "Remediation function deployed"
    fi
    
    # Wait for functions to be active
    log_message "INFO" "Waiting for Lambda functions to be active..."
    aws lambda wait function-active --function-name cost-optimization-analysis
    aws lambda wait function-active --function-name cost-optimization-remediation
}

# Function to create EventBridge schedules
create_eventbridge_schedules() {
    log_message "INFO" "Creating EventBridge schedules..."
    
    # Create EventBridge schedule group
    if aws scheduler get-schedule-group --name cost-optimization-schedules &> /dev/null; then
        log_message "WARN" "EventBridge schedule group already exists, skipping creation"
    else
        aws scheduler create-schedule-group --name cost-optimization-schedules
        log_message "INFO" "EventBridge schedule group created"
    fi
    
    # Create schedule for daily cost analysis
    if aws scheduler get-schedule --name daily-cost-analysis --group-name cost-optimization-schedules &> /dev/null; then
        log_message "WARN" "Daily cost analysis schedule already exists, skipping creation"
    else
        aws scheduler create-schedule \
            --name daily-cost-analysis \
            --group-name cost-optimization-schedules \
            --schedule-expression "rate(1 day)" \
            --target "{
                \"Arn\": \"arn:aws:lambda:$AWS_REGION:$AWS_ACCOUNT_ID:function:cost-optimization-analysis\",
                \"RoleArn\": \"arn:aws:iam::$AWS_ACCOUNT_ID:role/$COST_OPT_ROLE\"
            }" \
            --flexible-time-window '{"Mode": "OFF"}'
        log_message "INFO" "Daily cost analysis schedule created"
    fi
    
    # Create schedule for weekly comprehensive analysis
    if aws scheduler get-schedule --name weekly-comprehensive-analysis --group-name cost-optimization-schedules &> /dev/null; then
        log_message "WARN" "Weekly comprehensive analysis schedule already exists, skipping creation"
    else
        aws scheduler create-schedule \
            --name weekly-comprehensive-analysis \
            --group-name cost-optimization-schedules \
            --schedule-expression "rate(7 days)" \
            --target "{
                \"Arn\": \"arn:aws:lambda:$AWS_REGION:$AWS_ACCOUNT_ID:function:cost-optimization-analysis\",
                \"RoleArn\": \"arn:aws:iam::$AWS_ACCOUNT_ID:role/$COST_OPT_ROLE\",
                \"Input\": \"{\\\"comprehensive_analysis\\\": true}\"
            }" \
            --flexible-time-window '{"Mode": "OFF"}'
        log_message "INFO" "Weekly comprehensive analysis schedule created"
    fi
}

# Function to create CloudWatch dashboard
create_cloudwatch_dashboard() {
    log_message "INFO" "Creating CloudWatch dashboard..."
    
    # Create CloudWatch dashboard configuration
    cat > dashboard-config.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/Lambda", "Duration", "FunctionName", "cost-optimization-analysis"],
                    ["AWS/Lambda", "Invocations", "FunctionName", "cost-optimization-analysis"],
                    ["AWS/Lambda", "Errors", "FunctionName", "cost-optimization-analysis"],
                    ["AWS/Lambda", "Duration", "FunctionName", "cost-optimization-remediation"],
                    ["AWS/Lambda", "Invocations", "FunctionName", "cost-optimization-remediation"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$AWS_REGION",
                "title": "Cost Optimization Lambda Metrics"
            }
        },
        {
            "type": "log",
            "properties": {
                "query": "SOURCE '/aws/lambda/cost-optimization-analysis'\n| fields @timestamp, @message\n| filter @message like /optimization/\n| sort @timestamp desc\n| limit 100",
                "region": "$AWS_REGION",
                "title": "Cost Optimization Analysis Logs"
            }
        }
    ]
}
EOF
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "CostOptimization" \
        --dashboard-body file://dashboard-config.json
    
    log_message "INFO" "CloudWatch dashboard created"
}

# Function to setup SNS notifications
setup_sns_notifications() {
    log_message "INFO" "Setting up SNS notifications..."
    
    # Prompt for email address
    read -p "Enter your email address for cost optimization alerts (press Enter to skip): " EMAIL_ADDRESS
    
    if [[ -n "$EMAIL_ADDRESS" ]]; then
        # Subscribe email to SNS topic
        aws sns subscribe \
            --topic-arn "$COST_OPT_TOPIC_ARN" \
            --protocol email \
            --notification-endpoint "$EMAIL_ADDRESS"
        
        log_message "INFO" "Email subscription created for $EMAIL_ADDRESS"
        log_message "WARN" "Please check your email and confirm the subscription"
    else
        log_message "WARN" "Email subscription skipped"
    fi
    
    # Prompt for Slack webhook (optional)
    read -p "Enter Slack webhook URL (optional, press Enter to skip): " SLACK_WEBHOOK
    
    if [[ -n "$SLACK_WEBHOOK" ]]; then
        # Subscribe Slack webhook to SNS topic
        aws sns subscribe \
            --topic-arn "$COST_OPT_TOPIC_ARN" \
            --protocol https \
            --notification-endpoint "$SLACK_WEBHOOK"
        
        log_message "INFO" "Slack webhook subscription created"
    else
        log_message "INFO" "Slack webhook subscription skipped"
    fi
}

# Function to run validation tests
run_validation_tests() {
    log_message "INFO" "Running validation tests..."
    
    # Test Lambda function deployment
    log_message "INFO" "Testing Lambda function deployment..."
    local analysis_status=$(aws lambda get-function \
        --function-name cost-optimization-analysis \
        --query 'Configuration.State' --output text)
    
    local remediation_status=$(aws lambda get-function \
        --function-name cost-optimization-remediation \
        --query 'Configuration.State' --output text)
    
    if [[ "$analysis_status" == "Active" && "$remediation_status" == "Active" ]]; then
        log_message "INFO" "Lambda functions are active and ready"
    else
        log_message "ERROR" "Lambda functions are not active: Analysis=$analysis_status, Remediation=$remediation_status"
        return 1
    fi
    
    # Test Trusted Advisor API access
    log_message "INFO" "Testing Trusted Advisor API access..."
    local ta_test=$(aws support describe-trusted-advisor-checks \
        --language en \
        --query 'checks[?category==`cost_optimizing`].[name,id]' \
        --output text 2>/dev/null)
    
    if [[ -n "$ta_test" ]]; then
        log_message "INFO" "Trusted Advisor API access confirmed"
    else
        log_message "ERROR" "Trusted Advisor API access test failed"
        return 1
    fi
    
    # Test DynamoDB table
    log_message "INFO" "Testing DynamoDB table..."
    local table_status=$(aws dynamodb describe-table \
        --table-name "$COST_OPT_TABLE" \
        --query 'Table.TableStatus' --output text)
    
    if [[ "$table_status" == "ACTIVE" ]]; then
        log_message "INFO" "DynamoDB table is active"
    else
        log_message "ERROR" "DynamoDB table is not active: $table_status"
        return 1
    fi
    
    # Test SNS topic
    log_message "INFO" "Testing SNS topic..."
    local topic_exists=$(aws sns get-topic-attributes \
        --topic-arn "$COST_OPT_TOPIC_ARN" \
        --query 'Attributes.TopicArn' --output text 2>/dev/null)
    
    if [[ -n "$topic_exists" ]]; then
        log_message "INFO" "SNS topic is accessible"
    else
        log_message "ERROR" "SNS topic is not accessible"
        return 1
    fi
    
    # Test Lambda function invocation
    log_message "INFO" "Testing Lambda function invocation..."
    local test_result=$(aws lambda invoke \
        --function-name cost-optimization-analysis \
        --payload '{"test": true}' \
        test-response.json 2>/dev/null)
    
    if [[ -f "test-response.json" ]]; then
        local status_code=$(cat test-response.json | jq -r '.statusCode' 2>/dev/null)
        if [[ "$status_code" == "200" ]]; then
            log_message "INFO" "Lambda function test invocation successful"
        else
            log_message "WARN" "Lambda function test invocation returned non-200 status: $status_code"
        fi
        rm -f test-response.json
    else
        log_message "ERROR" "Lambda function test invocation failed"
        return 1
    fi
    
    log_message "INFO" "All validation tests passed successfully"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log_message "INFO" "Cleaning up temporary files..."
    
    # Remove temporary files
    rm -f trust-policy.json
    rm -f cost-optimization-policy.json
    rm -f dashboard-config.json
    rm -f test-response.json
    
    # Remove temporary directory
    rm -rf "$TEMP_DIR"
    
    log_message "INFO" "Temporary files cleaned up"
}

# Function to display deployment summary
display_deployment_summary() {
    log_message "INFO" "Deployment completed successfully!"
    
    echo
    echo "========================================="
    echo "         DEPLOYMENT SUMMARY"
    echo "========================================="
    echo
    echo "Resources created:"
    echo "  • IAM Role: $COST_OPT_ROLE"
    echo "  • S3 Bucket: $COST_OPT_BUCKET"
    echo "  • DynamoDB Table: $COST_OPT_TABLE"
    echo "  • SNS Topic: $COST_OPT_TOPIC"
    echo "  • Lambda Functions:"
    echo "    - cost-optimization-analysis"
    echo "    - cost-optimization-remediation"
    echo "  • EventBridge Schedules:"
    echo "    - daily-cost-analysis"
    echo "    - weekly-comprehensive-analysis"
    echo "  • CloudWatch Dashboard: CostOptimization"
    echo
    echo "Next steps:"
    echo "  1. Confirm email subscription if you provided one"
    echo "  2. Review the CloudWatch dashboard for system metrics"
    echo "  3. Monitor Lambda function logs for cost optimization activities"
    echo "  4. Check DynamoDB table for cost optimization opportunities"
    echo
    echo "Dashboard URL:"
    echo "  https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=CostOptimization"
    echo
    echo "To clean up resources, run: ./destroy.sh"
    echo "Deployment log saved to: $DEPLOYMENT_LOG"
    echo "========================================="
}

# Main deployment function
main() {
    log_message "INFO" "Starting AWS Cost Optimization Automation deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_iam_resources
    create_foundation_resources
    create_lambda_code
    deploy_lambda_functions
    create_eventbridge_schedules
    create_cloudwatch_dashboard
    setup_sns_notifications
    run_validation_tests
    cleanup_temp_files
    display_deployment_summary
    
    log_message "INFO" "Deployment completed successfully!"
}

# Handle script interruption
trap 'log_message "ERROR" "Deployment interrupted by user"; cleanup_temp_files; exit 1' INT TERM

# Run main function
main "$@"