#!/bin/bash

# =============================================================================
# AWS Proactive Application Resilience Monitoring Deployment Script
# 
# This script deploys AWS Resilience Hub with EventBridge integration for
# proactive application resilience monitoring and automated remediation.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate AWS permissions for Resilience Hub, EventBridge, etc.
# - Valid AWS credentials configured
# =============================================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Cleaning up partial resources..."
    # Note: Add specific cleanup logic here if needed
    exit 1
}

# Set error trap
trap cleanup_on_error ERR

# =============================================================================
# Prerequisites Check
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    info "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check required services availability
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region)
    
    if [[ -z "$region" ]]; then
        error "AWS region not configured. Please set a default region."
        exit 1
    fi
    
    info "AWS Account: $account_id"
    info "AWS Region: $region"
    
    # Check Resilience Hub service availability
    if ! aws resiliencehub list-apps --max-results 1 &> /dev/null; then
        error "AWS Resilience Hub is not available in region $region or you lack permissions."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# =============================================================================
# Environment Setup
# =============================================================================

setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export APP_NAME="resilience-demo-app-${RANDOM_SUFFIX}"
    export POLICY_NAME="resilience-policy-${RANDOM_SUFFIX}"
    export AUTOMATION_ROLE_NAME="ResilienceAutomationRole-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="resilience-processor-${RANDOM_SUFFIX}"
    
    # Store variables for cleanup script
    cat > .deployment_vars << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
APP_NAME=${APP_NAME}
POLICY_NAME=${POLICY_NAME}
AUTOMATION_ROLE_NAME=${AUTOMATION_ROLE_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    info "Environment configured with unique suffix: $RANDOM_SUFFIX"
    log "Environment setup completed successfully"
}

# =============================================================================
# IAM Role Creation
# =============================================================================

create_iam_role() {
    log "Creating IAM role for automation..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${AUTOMATION_ROLE_NAME}" &> /dev/null; then
        warn "IAM role ${AUTOMATION_ROLE_NAME} already exists, skipping creation"
        return 0
    fi
    
    # Create IAM role for automation
    aws iam create-role \
        --role-name "${AUTOMATION_ROLE_NAME}" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": ["ssm.amazonaws.com", "lambda.amazonaws.com"]
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' \
        --tags Key=Purpose,Value=ResilienceMonitoring Key=CreatedBy,Value=deployment-script
    
    # Attach necessary policies
    aws iam attach-role-policy \
        --role-name "${AUTOMATION_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMAutomationRole
    
    aws iam attach-role-policy \
        --role-name "${AUTOMATION_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam attach-role-policy \
        --role-name "${AUTOMATION_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
    
    # Wait for role to propagate
    sleep 10
    
    log "IAM role created successfully"
}

# =============================================================================
# Application Infrastructure
# =============================================================================

create_application_infrastructure() {
    log "Creating sample application infrastructure..."
    
    # Create VPC
    local vpc_id=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications \
        'ResourceType=vpc,Tags=[{Key=Name,Value=resilience-demo-vpc},{Key=Purpose,Value=ResilienceDemo}]' \
        --query 'Vpc.VpcId' --output text)
    
    info "Created VPC: $vpc_id"
    
    # Create subnets
    local subnet_id_1=$(aws ec2 create-subnet \
        --vpc-id "${vpc_id}" \
        --cidr-block 10.0.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications \
        'ResourceType=subnet,Tags=[{Key=Name,Value=resilience-demo-subnet-1},{Key=Purpose,Value=ResilienceDemo}]' \
        --query 'Subnet.SubnetId' --output text)
    
    local subnet_id_2=$(aws ec2 create-subnet \
        --vpc-id "${vpc_id}" \
        --cidr-block 10.0.2.0/24 \
        --availability-zone "${AWS_REGION}b" \
        --tag-specifications \
        'ResourceType=subnet,Tags=[{Key=Name,Value=resilience-demo-subnet-2},{Key=Purpose,Value=ResilienceDemo}]' \
        --query 'Subnet.SubnetId' --output text)
    
    info "Created subnets: $subnet_id_1, $subnet_id_2"
    
    # Create and attach internet gateway
    local igw_id=$(aws ec2 create-internet-gateway \
        --tag-specifications \
        'ResourceType=internet-gateway,Tags=[{Key=Name,Value=resilience-demo-igw},{Key=Purpose,Value=ResilienceDemo}]' \
        --query 'InternetGateway.InternetGatewayId' --output text)
    
    aws ec2 attach-internet-gateway \
        --vpc-id "${vpc_id}" \
        --internet-gateway-id "${igw_id}"
    
    # Create security group
    local sg_id=$(aws ec2 create-security-group \
        --group-name "resilience-demo-sg-${RANDOM_SUFFIX}" \
        --description "Security group for resilience demo" \
        --vpc-id "${vpc_id}" \
        --tag-specifications \
        'ResourceType=security-group,Tags=[{Key=Name,Value=resilience-demo-sg},{Key=Purpose,Value=ResilienceDemo}]' \
        --query 'GroupId' --output text)
    
    aws ec2 authorize-security-group-ingress \
        --group-id "${sg_id}" \
        --protocol tcp \
        --port 3306 \
        --source-group "${sg_id}"
    
    # Launch EC2 instance
    local ami_id=$(aws ec2 describe-images \
        --owners amazon \
        --filters 'Name=name,Values=amzn2-ami-hvm-*' \
                  'Name=architecture,Values=x86_64' \
                  'Name=state,Values=available' \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    local instance_id=$(aws ec2 run-instances \
        --image-id "${ami_id}" \
        --instance-type t3.micro \
        --subnet-id "${subnet_id_1}" \
        --security-group-ids "${sg_id}" \
        --tag-specifications \
        'ResourceType=instance,Tags=[{Key=Name,Value=resilience-demo-instance},{Key=Environment,Value=demo},{Key=Purpose,Value=ResilienceDemo}]' \
        --user-data '#!/bin/bash
yum update -y
yum install -y amazon-cloudwatch-agent' \
        --query 'Instances[0].InstanceId' --output text)
    
    # Wait for instance to be running
    info "Waiting for EC2 instance to be running..."
    aws ec2 wait instance-running --instance-ids "${instance_id}"
    
    # Create RDS subnet group and database
    aws rds create-db-subnet-group \
        --db-subnet-group-name "resilience-demo-subnet-group-${RANDOM_SUFFIX}" \
        --db-subnet-group-description "Subnet group for resilience demo" \
        --subnet-ids "${subnet_id_1}" "${subnet_id_2}" \
        --tags Key=Purpose,Value=ResilienceDemo
    
    info "Creating RDS database (this may take several minutes)..."
    aws rds create-db-instance \
        --db-instance-identifier "resilience-demo-db-${RANDOM_SUFFIX}" \
        --db-instance-class db.t3.micro \
        --engine mysql \
        --master-username admin \
        --master-user-password TempPassword123! \
        --allocated-storage 20 \
        --vpc-security-group-ids "${sg_id}" \
        --db-subnet-group-name "resilience-demo-subnet-group-${RANDOM_SUFFIX}" \
        --backup-retention-period 7 \
        --storage-encrypted \
        --multi-az \
        --auto-minor-version-upgrade \
        --tags Key=Environment,Value=demo Key=Purpose,Value=resilience-testing
    
    # Store infrastructure IDs for cleanup
    cat >> .deployment_vars << EOF
VPC_ID=${vpc_id}
SUBNET_ID_1=${subnet_id_1}
SUBNET_ID_2=${subnet_id_2}
IGW_ID=${igw_id}
SG_ID=${sg_id}
INSTANCE_ID=${instance_id}
EOF
    
    log "Application infrastructure created successfully"
}

# =============================================================================
# Resilience Hub Configuration
# =============================================================================

configure_resilience_hub() {
    log "Configuring AWS Resilience Hub..."
    
    # Wait for RDS to be available
    info "Waiting for RDS database to be available (this may take 10-15 minutes)..."
    aws rds wait db-instance-available \
        --db-instance-identifier "resilience-demo-db-${RANDOM_SUFFIX}"
    
    # Create resilience policy
    cat > resilience-policy.json << EOF
{
    "policyName": "${POLICY_NAME}",
    "policyDescription": "Mission-critical resilience policy for demo application monitoring",
    "tier": "MissionCritical",
    "policy": {
        "AZ": {
            "rtoInSecs": 300,
            "rpoInSecs": 60
        },
        "Hardware": {
            "rtoInSecs": 600,
            "rpoInSecs": 300
        },
        "Software": {
            "rtoInSecs": 300,
            "rpoInSecs": 60
        },
        "Region": {
            "rtoInSecs": 3600,
            "rpoInSecs": 1800
        }
    },
    "tags": {
        "Environment": "demo",
        "Purpose": "resilience-monitoring"
    }
}
EOF
    
    # Create the resilience policy
    aws resiliencehub create-resiliency-policy \
        --cli-input-json file://resilience-policy.json
    
    # Create application template
    cat > app-template.json << EOF
{
    "AWSTemplateFormatVersion": "2010-09-09",
    "Description": "Resilience Hub application template for demo application",
    "Resources": {
        "WebTierInstance": {
            "Type": "AWS::EC2::Instance",
            "Properties": {
                "InstanceId": "${INSTANCE_ID}"
            }
        },
        "DatabaseInstance": {
            "Type": "AWS::RDS::DBInstance",
            "Properties": {
                "DBInstanceIdentifier": "resilience-demo-db-${RANDOM_SUFFIX}"
            }
        }
    }
}
EOF
    
    # Create application in Resilience Hub
    local app_arn=$(aws resiliencehub create-app \
        --app-name "${APP_NAME}" \
        --description "Demo application for proactive resilience monitoring" \
        --tags Environment=demo,Purpose=resilience-monitoring \
        --query 'app.appArn' --output text)
    
    # Get policy ARN
    local policy_arn=$(aws resiliencehub list-resiliency-policies \
        --query "resiliencyPolicies[?policyName=='${POLICY_NAME}'].policyArn" \
        --output text)
    
    # Import resources and associate policy
    aws resiliencehub import-resources-to-draft-app-version \
        --app-arn "${app_arn}" \
        --source-arns "arn:aws:ec2:${AWS_REGION}:${AWS_ACCOUNT_ID}:instance/${INSTANCE_ID}" \
                      "arn:aws:rds:${AWS_REGION}:${AWS_ACCOUNT_ID}:db:resilience-demo-db-${RANDOM_SUFFIX}"
    
    aws resiliencehub put-draft-app-version-template \
        --app-arn "${app_arn}" \
        --app-template-body file://app-template.json
    
    # Store ARNs for cleanup
    cat >> .deployment_vars << EOF
APP_ARN=${app_arn}
POLICY_ARN=${policy_arn}
EOF
    
    log "Resilience Hub configured successfully"
}

# =============================================================================
# Lambda and EventBridge Setup
# =============================================================================

setup_lambda_eventbridge() {
    log "Setting up Lambda function and EventBridge..."
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    logger.info(f"Received resilience event: {json.dumps(event)}")
    
    ssm = boto3.client('ssm')
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        # Parse EventBridge event
        event_detail = event.get('detail', {})
        app_name = event_detail.get('applicationName', 'unknown')
        assessment_status = event_detail.get('assessmentStatus', 'UNKNOWN')
        resilience_score = event_detail.get('resilienceScore', 0)
        
        # Log resilience metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='ResilienceHub/Monitoring',
            MetricData=[
                {
                    'MetricName': 'ResilienceScore',
                    'Dimensions': [
                        {
                            'Name': 'ApplicationName',
                            'Value': app_name
                        }
                    ],
                    'Value': resilience_score,
                    'Unit': 'Percent',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'AssessmentEvents',
                    'Dimensions': [
                        {
                            'Name': 'ApplicationName',
                            'Value': app_name
                        },
                        {
                            'Name': 'Status',
                            'Value': assessment_status
                        }
                    ],
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        # Log action based on score
        if resilience_score < 80:
            logger.info(f"Resilience score {resilience_score}% below threshold, remediation recommended")
        else:
            logger.info(f"Resilience score {resilience_score}% above threshold, no action required")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Event processed successfully',
                'application': app_name,
                'resilience_score': resilience_score,
                'assessment_status': assessment_status
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        
        # Log error metric
        cloudwatch.put_metric_data(
            Namespace='ResilienceHub/Monitoring',
            MetricData=[
                {
                    'MetricName': 'ProcessingErrors',
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        raise e
EOF
    
    # Package Lambda function
    zip lambda_function.zip lambda_function.py
    
    # Create Lambda function
    local lambda_arn=$(aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${AUTOMATION_ROLE_NAME}" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://lambda_function.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables='{LOG_LEVEL=INFO}' \
        --tags Purpose=ResilienceMonitoring,Environment=demo \
        --query 'FunctionArn' --output text)
    
    # Create EventBridge rule
    aws events put-rule \
        --name "ResilienceHubAssessmentRule-${RANDOM_SUFFIX}" \
        --description "Rule for Resilience Hub assessment events" \
        --event-pattern '{
            "source": ["aws.resiliencehub"],
            "detail-type": [
                "Resilience Assessment State Change",
                "Application Assessment Completed"
            ]
        }' \
        --state ENABLED \
        --tags Key=Purpose,Value=ResilienceMonitoring
    
    # Add Lambda as target
    aws events put-targets \
        --rule "ResilienceHubAssessmentRule-${RANDOM_SUFFIX}" \
        --targets "Id"="1","Arn"="${lambda_arn}"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id "AllowEventBridgeInvoke" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn \
        "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/ResilienceHubAssessmentRule-${RANDOM_SUFFIX}"
    
    # Store Lambda ARN for cleanup
    cat >> .deployment_vars << EOF
LAMBDA_ARN=${lambda_arn}
EOF
    
    log "Lambda function and EventBridge setup completed successfully"
}

# =============================================================================
# CloudWatch Configuration
# =============================================================================

setup_cloudwatch() {
    log "Setting up CloudWatch monitoring..."
    
    # Create SNS topic for alerts
    local topic_arn=$(aws sns create-topic \
        --name "resilience-alerts-${RANDOM_SUFFIX}" \
        --attributes '{
            "DisplayName": "Resilience Monitoring Alerts"
        }' \
        --tags Key=Purpose,Value=ResilienceMonitoring \
        --query 'TopicArn' --output text)
    
    # Create CloudWatch alarms
    aws cloudwatch put-metric-alarm \
        --alarm-name "Critical-Low-Resilience-Score-${RANDOM_SUFFIX}" \
        --alarm-description "Critical alert when resilience score drops below 70%" \
        --metric-name ResilienceScore \
        --namespace ResilienceHub/Monitoring \
        --statistic Average \
        --period 300 \
        --threshold 70 \
        --comparison-operator LessThanThreshold \
        --datapoints-to-alarm 1 \
        --evaluation-periods 1 \
        --alarm-actions "${topic_arn}" \
        --ok-actions "${topic_arn}" \
        --dimensions Name=ApplicationName,Value="${APP_NAME}" \
        --tags Key=Purpose,Value=ResilienceMonitoring
    
    # Create dashboard
    cat > dashboard-config.json << EOF
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
                    ["ResilienceHub/Monitoring", "ResilienceScore", "ApplicationName", "${APP_NAME}"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Application Resilience Score Trend",
                "yAxis": {
                    "left": {
                        "min": 0,
                        "max": 100
                    }
                }
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "query": "SOURCE '/aws/lambda/${LAMBDA_FUNCTION_NAME}' | fields @timestamp, @message | filter @message like /resilience/ | sort @timestamp desc | limit 50",
                "region": "${AWS_REGION}",
                "title": "Recent Resilience Events"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "Application-Resilience-Monitoring-${RANDOM_SUFFIX}" \
        --dashboard-body file://dashboard-config.json
    
    # Store CloudWatch resources for cleanup
    cat >> .deployment_vars << EOF
TOPIC_ARN=${topic_arn}
EOF
    
    log "CloudWatch monitoring setup completed successfully"
}

# =============================================================================
# Initial Assessment
# =============================================================================

run_initial_assessment() {
    log "Running initial resilience assessment..."
    
    # Publish application version
    aws resiliencehub publish-app-version \
        --app-arn "${APP_ARN}"
    
    # Start assessment
    local assessment_arn=$(aws resiliencehub start-app-assessment \
        --app-arn "${APP_ARN}" \
        --app-version $(aws resiliencehub describe-app \
            --app-arn "${APP_ARN}" \
            --query 'app.appVersion' --output text) \
        --assessment-name "initial-assessment-$(date +%Y%m%d-%H%M%S)" \
        --tags Environment=demo,Purpose=baseline-assessment \
        --query 'assessment.assessmentArn' --output text)
    
    info "Assessment started with ARN: $assessment_arn"
    info "Assessment will complete in 5-15 minutes"
    
    # Store assessment ARN
    cat >> .deployment_vars << EOF
ASSESSMENT_ARN=${assessment_arn}
EOF
    
    log "Initial assessment initiated successfully"
}

# =============================================================================
# Main Deployment Function
# =============================================================================

main() {
    log "Starting AWS Proactive Application Resilience Monitoring deployment..."
    
    check_prerequisites
    setup_environment
    create_iam_role
    create_application_infrastructure
    configure_resilience_hub
    setup_lambda_eventbridge
    setup_cloudwatch
    run_initial_assessment
    
    # Cleanup temporary files
    rm -f resilience-policy.json app-template.json dashboard-config.json
    rm -f lambda_function.py lambda_function.zip
    
    log "Deployment completed successfully!"
    echo ""
    echo "=========================================="
    echo "DEPLOYMENT SUMMARY"
    echo "=========================================="
    echo "Application Name: ${APP_NAME}"
    echo "AWS Region: ${AWS_REGION}"
    echo "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo ""
    echo "Next Steps:"
    echo "1. Monitor the assessment progress (5-15 minutes)"
    echo "2. Check CloudWatch dashboard for metrics"
    echo "3. Review Lambda logs for event processing"
    echo ""
    echo "Dashboard URL:"
    echo "https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=Application-Resilience-Monitoring-${RANDOM_SUFFIX}"
    echo ""
    echo "Cleanup: Run ./destroy.sh when testing is complete"
    echo "=========================================="
}

# Execute main function
main "$@"