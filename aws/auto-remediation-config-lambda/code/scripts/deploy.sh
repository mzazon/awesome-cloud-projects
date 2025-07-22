#!/bin/bash

# AWS Config Auto-Remediation Deployment Script
# This script deploys the complete auto-remediation infrastructure
# including AWS Config, Lambda functions, and monitoring components.

set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
STACK_NAME="aws-config-auto-remediation"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        ERROR)
            echo -e "${RED}[ERROR] $message${NC}" >&2
            echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS] $message${NC}"
            echo "[$timestamp] [SUCCESS] $message" >> "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN] $message${NC}"
            echo "[$timestamp] [WARN] $message" >> "$LOG_FILE"
            ;;
        INFO)
            echo -e "${BLUE}[INFO] $message${NC}"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
    esac
}

# Error handler
error_exit() {
    log ERROR "Deployment failed: $1"
    log ERROR "Check logs at: $LOG_FILE"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log WARN "Cleaning up partial deployment due to error..."
    
    # Remove test resources if they exist
    if [ -n "${TEST_SG_ID:-}" ]; then
        aws ec2 delete-security-group --group-id "$TEST_SG_ID" 2>/dev/null || true
    fi
    
    # Note: We don't auto-cleanup main resources to avoid data loss
    log WARN "Some resources may need manual cleanup. Check AWS Console."
}

# Trap errors
trap cleanup_on_error ERR

# Print header
echo "================================================"
echo "AWS Config Auto-Remediation Deployment Script"
echo "Timestamp: $TIMESTAMP"
echo "Log file: $LOG_FILE"
echo "================================================"
echo

# Check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | head -n1 | awk '{print $1}' | cut -d/ -f2 | cut -d. -f1)
    if [ "$aws_version" -lt 2 ]; then
        error_exit "AWS CLI v2 is required. Found version: $(aws --version)"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials are not configured or invalid. Run 'aws configure' first."
    fi
    
    # Check required permissions (attempt basic operations)
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || \
        error_exit "Cannot retrieve AWS account ID. Check IAM permissions."
    
    # Verify Config service is available in region
    local region
    region=$(aws configure get region 2>/dev/null) || \
        error_exit "AWS region is not configured. Run 'aws configure' first."
    
    # Check if Config is supported in region
    if ! aws configservice describe-configuration-recorders --region "$region" &> /dev/null; then
        error_exit "AWS Config service is not available in region: $region"
    fi
    
    log SUCCESS "Prerequisites check passed"
    log INFO "Account ID: $account_id"
    log INFO "Region: $region"
}

# Generate unique resource names
generate_resource_names() {
    log INFO "Generating unique resource names..."
    
    # Generate random suffix
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null) || \
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for resource names
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export CONFIG_ROLE_NAME="AWSConfigRole-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="ConfigRemediationRole-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="aws-config-bucket-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="config-compliance-alerts-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="SecurityGroupRemediation-${RANDOM_SUFFIX}"
    export SSM_DOCUMENT_NAME="S3-RemediatePublicAccess-${RANDOM_SUFFIX}"
    export DASHBOARD_NAME="Config-Compliance-Dashboard-${RANDOM_SUFFIX}"
    
    log SUCCESS "Resource names generated with suffix: $RANDOM_SUFFIX"
    
    # Save configuration for cleanup
    cat > "${SCRIPT_DIR}/deployment-config.env" << EOF
# Deployment configuration - $(date)
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
CONFIG_ROLE_NAME=$CONFIG_ROLE_NAME
LAMBDA_ROLE_NAME=$LAMBDA_ROLE_NAME
S3_BUCKET_NAME=$S3_BUCKET_NAME
SNS_TOPIC_NAME=$SNS_TOPIC_NAME
LAMBDA_FUNCTION_NAME=$LAMBDA_FUNCTION_NAME
SSM_DOCUMENT_NAME=$SSM_DOCUMENT_NAME
DASHBOARD_NAME=$DASHBOARD_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
DEPLOYMENT_TIMESTAMP=$TIMESTAMP
EOF
}

# Setup S3 bucket for Config
setup_config_s3_bucket() {
    log INFO "Setting up S3 bucket for AWS Config..."
    
    # Create S3 bucket
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
        log WARN "S3 bucket $S3_BUCKET_NAME already exists"
    else
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3api create-bucket --bucket "$S3_BUCKET_NAME" || \
                error_exit "Failed to create S3 bucket"
        else
            aws s3api create-bucket \
                --bucket "$S3_BUCKET_NAME" \
                --create-bucket-configuration LocationConstraint="$AWS_REGION" || \
                error_exit "Failed to create S3 bucket"
        fi
        log SUCCESS "Created S3 bucket: $S3_BUCKET_NAME"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$S3_BUCKET_NAME" \
        --versioning-configuration Status=Enabled || \
        error_exit "Failed to enable S3 bucket versioning"
    
    # Create bucket policy
    cat > "${SCRIPT_DIR}/config-bucket-policy.json" << EOF
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
            "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceAccount": "${AWS_ACCOUNT_ID}"
                }
            }
        },
        {
            "Sid": "AWSConfigBucketExistenceCheck",
            "Effect": "Allow",
            "Principal": {
                "Service": "config.amazonaws.com"
            },
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceAccount": "${AWS_ACCOUNT_ID}"
                }
            }
        },
        {
            "Sid": "AWSConfigBucketDelivery",
            "Effect": "Allow",
            "Principal": {
                "Service": "config.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/AWSLogs/${AWS_ACCOUNT_ID}/Config/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-acl": "bucket-owner-full-control",
                    "AWS:SourceAccount": "${AWS_ACCOUNT_ID}"
                }
            }
        }
    ]
}
EOF
    
    aws s3api put-bucket-policy \
        --bucket "$S3_BUCKET_NAME" \
        --policy file://"${SCRIPT_DIR}/config-bucket-policy.json" || \
        error_exit "Failed to set S3 bucket policy"
    
    log SUCCESS "S3 bucket configured for AWS Config"
}

# Create IAM roles
create_iam_roles() {
    log INFO "Creating IAM roles..."
    
    # Create Config service role
    cat > "${SCRIPT_DIR}/config-trust-policy.json" << EOF
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
    
    # Check if Config role exists
    if aws iam get-role --role-name "$CONFIG_ROLE_NAME" &>/dev/null; then
        log WARN "Config role $CONFIG_ROLE_NAME already exists"
    else
        aws iam create-role \
            --role-name "$CONFIG_ROLE_NAME" \
            --assume-role-policy-document file://"${SCRIPT_DIR}/config-trust-policy.json" \
            --tags Key=Purpose,Value=AWSConfig Key=Project,Value=AutoRemediation || \
            error_exit "Failed to create Config role"
        
        # Wait for role to be available
        sleep 10
        log SUCCESS "Created Config role: $CONFIG_ROLE_NAME"
    fi
    
    # Attach AWS managed policy
    aws iam attach-role-policy \
        --role-name "$CONFIG_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole || \
        error_exit "Failed to attach Config role policy"
    
    # Create Lambda execution role
    cat > "${SCRIPT_DIR}/lambda-trust-policy.json" << EOF
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
    
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
        log WARN "Lambda role $LAMBDA_ROLE_NAME already exists"
    else
        aws iam create-role \
            --role-name "$LAMBDA_ROLE_NAME" \
            --assume-role-policy-document file://"${SCRIPT_DIR}/lambda-trust-policy.json" \
            --tags Key=Purpose,Value=AutoRemediation Key=Project,Value=ConfigCompliance || \
            error_exit "Failed to create Lambda role"
        
        sleep 10
        log SUCCESS "Created Lambda role: $LAMBDA_ROLE_NAME"
    fi
    
    # Create custom policy for Lambda
    cat > "${SCRIPT_DIR}/lambda-remediation-policy.json" << EOF
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
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeSecurityGroups",
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:AuthorizeSecurityGroupEgress",
                "ec2:RevokeSecurityGroupEgress",
                "ec2:CreateTags"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetBucketAcl",
                "s3:GetBucketPolicy",
                "s3:PutBucketAcl",
                "s3:PutBucketPolicy",
                "s3:DeleteBucketPolicy",
                "s3:PutPublicAccessBlock"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "config:PutEvaluations"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    local policy_arn
    policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_ROLE_NAME}-Policy"
    
    # Check if policy exists
    if aws iam get-policy --policy-arn "$policy_arn" &>/dev/null; then
        log WARN "Lambda policy already exists"
    else
        aws iam create-policy \
            --policy-name "${LAMBDA_ROLE_NAME}-Policy" \
            --policy-document file://"${SCRIPT_DIR}/lambda-remediation-policy.json" \
            --tags Key=Purpose,Value=AutoRemediation || \
            error_exit "Failed to create Lambda policy"
        log SUCCESS "Created Lambda policy"
    fi
    
    # Attach policy to role
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn "$policy_arn" || \
        error_exit "Failed to attach Lambda policy"
    
    log SUCCESS "IAM roles created and configured"
}

# Setup AWS Config
setup_aws_config() {
    log INFO "Setting up AWS Config..."
    
    local config_role_arn
    config_role_arn=$(aws iam get-role --role-name "$CONFIG_ROLE_NAME" --query 'Role.Arn' --output text)
    
    # Check if configuration recorder exists
    if aws configservice describe-configuration-recorders --query 'ConfigurationRecorders[?name==`default`]' --output text | grep -q default; then
        log WARN "Config recorder 'default' already exists"
    else
        # Create configuration recorder
        aws configservice put-configuration-recorder \
            --configuration-recorder '{
                "name": "default",
                "roleARN": "'$config_role_arn'",
                "recordingGroup": {
                    "allSupported": true,
                    "includeGlobalResourceTypes": true
                }
            }' || error_exit "Failed to create configuration recorder"
        log SUCCESS "Created configuration recorder"
    fi
    
    # Check if delivery channel exists
    if aws configservice describe-delivery-channels --query 'DeliveryChannels[?name==`default`]' --output text | grep -q default; then
        log WARN "Config delivery channel 'default' already exists"
    else
        # Create delivery channel
        aws configservice put-delivery-channel \
            --delivery-channel '{
                "name": "default",
                "s3BucketName": "'$S3_BUCKET_NAME'"
            }' || error_exit "Failed to create delivery channel"
        log SUCCESS "Created delivery channel"
    fi
    
    # Start configuration recorder
    aws configservice start-configuration-recorder \
        --configuration-recorder-name default || \
        error_exit "Failed to start configuration recorder"
    
    log SUCCESS "AWS Config setup completed"
}

# Create Lambda function
create_lambda_function() {
    log INFO "Creating Lambda remediation function..."
    
    # Create Lambda function code
    cat > "${SCRIPT_DIR}/sg-remediation-function.py" << 'EOF'
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client('ec2')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Remediate security groups that allow unrestricted access (0.0.0.0/0)
    """
    
    try:
        # Parse the Config rule evaluation
        config_item = event['configurationItem']
        resource_id = config_item['resourceId']
        resource_type = config_item['resourceType']
        
        logger.info(f"Processing remediation for {resource_type}: {resource_id}")
        
        if resource_type != 'AWS::EC2::SecurityGroup':
            return {
                'statusCode': 400,
                'body': json.dumps('This function only handles Security Groups')
            }
        
        # Get security group details
        try:
            response = ec2.describe_security_groups(GroupIds=[resource_id])
            security_group = response['SecurityGroups'][0]
        except Exception as e:
            logger.error(f"Failed to describe security group {resource_id}: {e}")
            return {
                'statusCode': 404,
                'body': json.dumps(f'Security group not found: {resource_id}')
            }
        
        remediation_actions = []
        
        # Check inbound rules for unrestricted access
        for rule in security_group['IpPermissions']:
            for ip_range in rule.get('IpRanges', []):
                if ip_range.get('CidrIp') == '0.0.0.0/0':
                    # Remove unrestricted inbound rule
                    try:
                        ec2.revoke_security_group_ingress(
                            GroupId=resource_id,
                            IpPermissions=[rule]
                        )
                        remediation_actions.append(f"Removed unrestricted inbound rule: {rule}")
                        logger.info(f"Removed unrestricted inbound rule from {resource_id}")
                    except Exception as e:
                        logger.error(f"Failed to remove inbound rule: {e}")
        
        # Add tag to indicate remediation
        try:
            ec2.create_tags(
                Resources=[resource_id],
                Tags=[
                    {
                        'Key': 'AutoRemediated',
                        'Value': 'true'
                    },
                    {
                        'Key': 'RemediationDate',
                        'Value': datetime.now().isoformat()
                    }
                ]
            )
        except Exception as e:
            logger.error(f"Failed to add tags: {e}")
        
        # Send notification if remediation occurred
        if remediation_actions:
            message = {
                'resource_id': resource_id,
                'resource_type': resource_type,
                'remediation_actions': remediation_actions,
                'timestamp': datetime.now().isoformat()
            }
            
            # Publish to SNS topic (if configured)
            topic_arn = os.environ.get('SNS_TOPIC_ARN')
            if topic_arn:
                try:
                    sns.publish(
                        TopicArn=topic_arn,
                        Subject=f'Security Group Auto-Remediation: {resource_id}',
                        Message=json.dumps(message, indent=2)
                    )
                except Exception as e:
                    logger.error(f"Failed to publish SNS notification: {e}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Remediation completed',
                'resource_id': resource_id,
                'actions_taken': len(remediation_actions)
            })
        }
        
    except Exception as e:
        logger.error(f"Error in remediation: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
EOF
    
    # Create deployment package
    cd "${SCRIPT_DIR}"
    zip -q sg-remediation-function.zip sg-remediation-function.py || \
        error_exit "Failed to create Lambda deployment package"
    
    local lambda_role_arn
    lambda_role_arn=$(aws iam get-role --role-name "$LAMBDA_ROLE_NAME" --query 'Role.Arn' --output text)
    
    # Check if Lambda function exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log WARN "Lambda function $LAMBDA_FUNCTION_NAME already exists, updating..."
        aws lambda update-function-code \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --zip-file fileb://sg-remediation-function.zip || \
            error_exit "Failed to update Lambda function"
    else
        # Create Lambda function
        aws lambda create-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --runtime python3.9 \
            --role "$lambda_role_arn" \
            --handler sg-remediation-function.lambda_handler \
            --zip-file fileb://sg-remediation-function.zip \
            --timeout 60 \
            --description "Auto-remediate security groups with unrestricted access" \
            --tags Purpose=AutoRemediation,Project=ConfigCompliance || \
            error_exit "Failed to create Lambda function"
        log SUCCESS "Created Lambda function: $LAMBDA_FUNCTION_NAME"
    fi
    
    # Wait for function to be ready
    sleep 10
}

# Setup SNS and notifications
setup_sns_notifications() {
    log INFO "Setting up SNS notifications..."
    
    # Create SNS topic
    local topic_arn
    if aws sns get-topic-attributes --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" &>/dev/null; then
        topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
        log WARN "SNS topic already exists: $SNS_TOPIC_NAME"
    else
        topic_arn=$(aws sns create-topic --name "$SNS_TOPIC_NAME" --query 'TopicArn' --output text) || \
            error_exit "Failed to create SNS topic"
        log SUCCESS "Created SNS topic: $SNS_TOPIC_NAME"
    fi
    
    # Update Lambda function with SNS topic ARN
    aws lambda update-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --environment Variables="{SNS_TOPIC_ARN=${topic_arn}}" || \
        error_exit "Failed to update Lambda environment variables"
    
    log SUCCESS "SNS notifications configured"
}

# Create Config rules
create_config_rules() {
    log INFO "Creating Config rules..."
    
    # Security group SSH rule
    if aws configservice describe-config-rules --config-rule-names "security-group-ssh-restricted" &>/dev/null; then
        log WARN "Config rule 'security-group-ssh-restricted' already exists"
    else
        aws configservice put-config-rule \
            --config-rule '{
                "ConfigRuleName": "security-group-ssh-restricted",
                "Description": "Checks if security groups allow unrestricted SSH access",
                "Source": {
                    "Owner": "AWS",
                    "SourceIdentifier": "INCOMING_SSH_DISABLED"
                },
                "Scope": {
                    "ComplianceResourceTypes": [
                        "AWS::EC2::SecurityGroup"
                    ]
                }
            }' || error_exit "Failed to create security group Config rule"
        log SUCCESS "Created Config rule: security-group-ssh-restricted"
    fi
    
    # S3 bucket public access rule
    if aws configservice describe-config-rules --config-rule-names "s3-bucket-public-access-prohibited" &>/dev/null; then
        log WARN "Config rule 's3-bucket-public-access-prohibited' already exists"
    else
        aws configservice put-config-rule \
            --config-rule '{
                "ConfigRuleName": "s3-bucket-public-access-prohibited",
                "Description": "Checks if S3 buckets allow public access",
                "Source": {
                    "Owner": "AWS",
                    "SourceIdentifier": "S3_BUCKET_PUBLIC_ACCESS_PROHIBITED"
                },
                "Scope": {
                    "ComplianceResourceTypes": [
                        "AWS::S3::Bucket"
                    ]
                }
            }' || error_exit "Failed to create S3 Config rule"
        log SUCCESS "Created Config rule: s3-bucket-public-access-prohibited"
    fi
    
    sleep 30  # Wait for rules to be active
}

# Setup CloudWatch dashboard
setup_cloudwatch_dashboard() {
    log INFO "Creating CloudWatch dashboard..."
    
    cat > "${SCRIPT_DIR}/compliance-dashboard.json" << EOF
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
                    [ "AWS/Config", "ComplianceByConfigRule", "ConfigRuleName", "security-group-ssh-restricted", "ComplianceType", "COMPLIANT" ],
                    [ "...", "NON_COMPLIANT" ],
                    [ "...", "s3-bucket-public-access-prohibited", ".", "COMPLIANT" ],
                    [ "...", "NON_COMPLIANT" ]
                ],
                "period": 300,
                "stat": "Maximum",
                "region": "${AWS_REGION}",
                "title": "Config Rule Compliance Status",
                "view": "timeSeries"
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/Lambda", "Invocations", "FunctionName", "${LAMBDA_FUNCTION_NAME}" ],
                    [ ".", "Errors", ".", "." ],
                    [ ".", "Duration", ".", "." ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Remediation Function Metrics",
                "view": "timeSeries"
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 12,
            "width": 24,
            "height": 6,
            "properties": {
                "query": "SOURCE '/aws/lambda/${LAMBDA_FUNCTION_NAME}'\n| fields @timestamp, @message\n| filter @message like /remediation/\n| sort @timestamp desc\n| limit 100",
                "region": "${AWS_REGION}",
                "title": "Recent Remediation Activity",
                "view": "table"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "$DASHBOARD_NAME" \
        --dashboard-body file://"${SCRIPT_DIR}/compliance-dashboard.json" || \
        error_exit "Failed to create CloudWatch dashboard"
    
    log SUCCESS "Created CloudWatch dashboard: $DASHBOARD_NAME"
}

# Verification function
verify_deployment() {
    log INFO "Verifying deployment..."
    
    # Check Config recorder status
    local recorder_status
    recorder_status=$(aws configservice describe-configuration-recorder-status \
        --query 'ConfigurationRecordersStatus[0].recording' --output text)
    
    if [ "$recorder_status" = "True" ]; then
        log SUCCESS "Config recorder is active"
    else
        log ERROR "Config recorder is not active"
        return 1
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log SUCCESS "Lambda function is deployed"
    else
        log ERROR "Lambda function not found"
        return 1
    fi
    
    # Check Config rules
    local rule_count
    rule_count=$(aws configservice describe-config-rules \
        --query 'length(ConfigRules[?ConfigRuleName==`security-group-ssh-restricted` || ConfigRuleName==`s3-bucket-public-access-prohibited`])' \
        --output text)
    
    if [ "$rule_count" -eq 2 ]; then
        log SUCCESS "Config rules are deployed"
    else
        log ERROR "Config rules are missing"
        return 1
    fi
    
    log SUCCESS "Deployment verification completed"
}

# Main deployment flow
main() {
    log INFO "Starting AWS Config Auto-Remediation deployment..."
    
    check_prerequisites
    generate_resource_names
    setup_config_s3_bucket
    create_iam_roles
    setup_aws_config
    create_lambda_function
    setup_sns_notifications
    create_config_rules
    setup_cloudwatch_dashboard
    verify_deployment
    
    # Print summary
    echo
    echo "================================================"
    echo "Deployment Summary"
    echo "================================================"
    echo "✅ S3 Bucket: $S3_BUCKET_NAME"
    echo "✅ Config Role: $CONFIG_ROLE_NAME"
    echo "✅ Lambda Role: $LAMBDA_ROLE_NAME"
    echo "✅ Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "✅ SNS Topic: $SNS_TOPIC_NAME"
    echo "✅ CloudWatch Dashboard: $DASHBOARD_NAME"
    echo "✅ Config Rules: security-group-ssh-restricted, s3-bucket-public-access-prohibited"
    echo
    echo "🔗 Dashboard URL: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
    echo
    echo "📋 Configuration saved to: ${SCRIPT_DIR}/deployment-config.env"
    echo "📋 Deployment log: $LOG_FILE"
    echo
    echo "⚠️  To clean up resources, run: ./destroy.sh"
    echo "================================================"
    
    log SUCCESS "Auto-remediation deployment completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --dry-run)
        log INFO "Dry run mode - checking prerequisites only"
        check_prerequisites
        generate_resource_names
        echo "Dry run completed. Resources would be created with suffix: $RANDOM_SUFFIX"
        exit 0
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo "Options:"
        echo "  --dry-run    Check prerequisites and show resource names without deploying"
        echo "  --help       Show this help message"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac