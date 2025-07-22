#!/bin/bash

#==============================================================================
# AWS Config Compliance Monitoring - Deployment Script
#==============================================================================
# This script deploys a comprehensive compliance monitoring system using:
# - AWS Config for continuous configuration tracking
# - Config Rules for compliance evaluation
# - Lambda functions for custom rules and remediation
# - EventBridge for event-driven automation
# - CloudWatch for monitoring and alerting
# - SNS for notifications
#==============================================================================

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/config-compliance-deploy-$(date +%Y%m%d-%H%M%S).log"
readonly DRY_RUN=${DRY_RUN:-false}

# Global variables for resource tracking
declare -a CREATED_RESOURCES=()
declare -a CREATED_FILES=()

#==============================================================================
# Logging and Output Functions
#==============================================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

#==============================================================================
# Error Handling and Cleanup
#==============================================================================

cleanup_on_error() {
    error "Deployment failed. Starting cleanup of created resources..."
    
    # Cleanup Lambda functions
    for resource in "${CREATED_RESOURCES[@]}"; do
        if [[ "$resource" == lambda:* ]]; then
            local function_name="${resource#lambda:}"
            info "Cleaning up Lambda function: $function_name"
            aws lambda delete-function --function-name "$function_name" 2>/dev/null || true
        fi
    done
    
    # Cleanup temporary files
    for file in "${CREATED_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            info "Removed temporary file: $file"
        fi
    done
    
    error "Cleanup completed. Check $LOG_FILE for details."
    exit 1
}

trap cleanup_on_error ERR

#==============================================================================
# Prerequisites and Validation
#==============================================================================

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    info "AWS CLI version: $aws_version"
    
    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some features may not work optimally."
    fi
    
    # Verify AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid."
        error "Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check AWS permissions
    local caller_info
    caller_info=$(aws sts get-caller-identity)
    info "AWS Account: $(echo "$caller_info" | jq -r '.Account' 2>/dev/null || echo 'Unknown')"
    info "AWS User/Role: $(echo "$caller_info" | jq -r '.Arn' 2>/dev/null || echo 'Unknown')"
    
    # Verify required permissions by testing a safe operation
    if ! aws configservice describe-configuration-recorders &> /dev/null; then
        error "Insufficient permissions for AWS Config operations."
        exit 1
    fi
    
    success "Prerequisites check completed successfully."
}

validate_region() {
    info "Validating AWS region..."
    
    local region
    region=$(aws configure get region)
    if [[ -z "$region" ]]; then
        error "AWS region not configured. Please set a default region."
        exit 1
    fi
    
    # Verify region supports AWS Config
    if ! aws configservice describe-configuration-recorders --region "$region" &> /dev/null; then
        error "AWS Config is not available in region: $region"
        exit 1
    fi
    
    info "Using AWS region: $region"
    export AWS_REGION="$region"
}

estimate_costs() {
    info "Estimating deployment costs..."
    cat << EOF

ESTIMATED MONTHLY COSTS:
========================
• AWS Config Service: \$2.00 per configuration item recorded
• Config Rules: \$0.001 per rule evaluation
• Lambda Functions: \$0.20 per 1M requests + compute time
• CloudWatch Logs: \$0.50 per GB ingested
• SNS: \$0.50 per 1M requests
• S3 Storage: \$0.023 per GB (varies by region)

ESTIMATED TOTAL: \$10-30 per month (depends on resource count and activity)

Note: Costs vary by region and actual usage patterns.
EOF
}

#==============================================================================
# Environment Setup
#==============================================================================

setup_environment() {
    info "Setting up environment variables..."
    
    # Core AWS configuration
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION
    AWS_REGION=$(aws configure get region)
    
    # Generate unique identifiers
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Resource names
    export CONFIG_BUCKET_NAME="config-bucket-${AWS_ACCOUNT_ID}-${random_suffix}"
    export CONFIG_TOPIC_NAME="config-compliance-topic-${random_suffix}"
    export CONFIG_ROLE_NAME="ConfigServiceRole-${random_suffix}"
    export REMEDIATION_ROLE_NAME="ConfigRemediationRole-${random_suffix}"
    export LAMBDA_ROLE_NAME="ConfigLambdaRole-${random_suffix}"
    export SECURITY_GROUP_LAMBDA_NAME="ConfigSecurityGroupRule-${random_suffix}"
    export REMEDIATION_LAMBDA_NAME="ConfigRemediation-${random_suffix}"
    export EVENTBRIDGE_RULE_NAME="ConfigComplianceRule-${random_suffix}"
    export DASHBOARD_NAME="ConfigComplianceDashboard-${random_suffix}"
    
    # Derived values
    export CONFIG_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CONFIG_ROLE_NAME}"
    export REMEDIATION_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${REMEDIATION_ROLE_NAME}"
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
    
    success "Environment setup completed."
    info "Config bucket: $CONFIG_BUCKET_NAME"
    info "Config topic: $CONFIG_TOPIC_NAME"
}

#==============================================================================
# IAM Roles and Policies
#==============================================================================

create_iam_roles() {
    info "Creating IAM roles and policies..."
    
    # Create Config service role
    info "Creating Config service role..."
    aws iam create-role \
        --role-name "$CONFIG_ROLE_NAME" \
        --assume-role-policy-document '{
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
        }' &>/dev/null
    
    CREATED_RESOURCES+=("iam-role:$CONFIG_ROLE_NAME")
    
    # Attach AWS managed policy
    aws iam attach-role-policy \
        --role-name "$CONFIG_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole
    
    # Create S3 policy for Config
    local s3_policy_arn
    s3_policy_arn=$(aws iam create-policy \
        --policy-name "ConfigS3Policy-${CONFIG_ROLE_NAME}" \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "s3:GetBucketAcl",
                        "s3:GetBucketLocation",
                        "s3:GetBucketPolicy",
                        "s3:ListBucket",
                        "s3:PutObject",
                        "s3:GetObject",
                        "s3:DeleteObject"
                    ],
                    "Resource": [
                        "arn:aws:s3:::'"$CONFIG_BUCKET_NAME"'",
                        "arn:aws:s3:::'"$CONFIG_BUCKET_NAME"'/*"
                    ]
                }
            ]
        }' --query 'Policy.Arn' --output text)
    
    CREATED_RESOURCES+=("iam-policy:$s3_policy_arn")
    
    aws iam attach-role-policy \
        --role-name "$CONFIG_ROLE_NAME" \
        --policy-arn "$s3_policy_arn"
    
    # Create Lambda execution role for Config rules
    info "Creating Lambda execution role..."
    aws iam create-role \
        --role-name "$LAMBDA_ROLE_NAME" \
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
        }' &>/dev/null
    
    CREATED_RESOURCES+=("iam-role:$LAMBDA_ROLE_NAME")
    
    # Attach policies to Lambda role
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSConfigRulesExecutionRole
    
    # Create remediation role
    info "Creating remediation role..."
    aws iam create-role \
        --role-name "$REMEDIATION_ROLE_NAME" \
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
        }' &>/dev/null
    
    CREATED_RESOURCES+=("iam-role:$REMEDIATION_ROLE_NAME")
    
    # Create remediation policy
    local remediation_policy_arn
    remediation_policy_arn=$(aws iam create-policy \
        --policy-name "ConfigRemediationPolicy-${REMEDIATION_ROLE_NAME}" \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "ec2:DescribeInstances",
                        "ec2:CreateTags",
                        "ec2:AuthorizeSecurityGroupIngress",
                        "ec2:RevokeSecurityGroupIngress",
                        "ec2:DescribeSecurityGroups",
                        "s3:PutBucketPublicAccessBlock",
                        "s3:GetBucketPublicAccessBlock"
                    ],
                    "Resource": "*"
                }
            ]
        }' --query 'Policy.Arn' --output text)
    
    CREATED_RESOURCES+=("iam-policy:$remediation_policy_arn")
    
    aws iam attach-role-policy \
        --role-name "$REMEDIATION_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam attach-role-policy \
        --role-name "$REMEDIATION_ROLE_NAME" \
        --policy-arn "$remediation_policy_arn"
    
    # Wait for role propagation
    info "Waiting for IAM role propagation..."
    sleep 10
    
    success "IAM roles and policies created successfully."
}

#==============================================================================
# S3 and SNS Setup
#==============================================================================

create_s3_sns_resources() {
    info "Creating S3 bucket and SNS topic..."
    
    # Create S3 bucket for Config data
    if aws s3api head-bucket --bucket "$CONFIG_BUCKET_NAME" 2>/dev/null; then
        warning "S3 bucket $CONFIG_BUCKET_NAME already exists"
    else
        aws s3 mb "s3://$CONFIG_BUCKET_NAME" --region "$AWS_REGION"
        CREATED_RESOURCES+=("s3-bucket:$CONFIG_BUCKET_NAME")
    fi
    
    # Create SNS topic
    export CONFIG_TOPIC_ARN
    CONFIG_TOPIC_ARN=$(aws sns create-topic \
        --name "$CONFIG_TOPIC_NAME" \
        --query 'TopicArn' --output text)
    
    CREATED_RESOURCES+=("sns-topic:$CONFIG_TOPIC_ARN")
    
    success "S3 bucket and SNS topic created successfully."
    info "S3 Bucket: $CONFIG_BUCKET_NAME"
    info "SNS Topic: $CONFIG_TOPIC_ARN"
}

#==============================================================================
# AWS Config Setup
#==============================================================================

setup_aws_config() {
    info "Setting up AWS Config service..."
    
    # Create delivery channel configuration
    local delivery_channel_config="/tmp/delivery-channel-${RANDOM}.json"
    cat > "$delivery_channel_config" << EOF
{
    "name": "default",
    "s3BucketName": "$CONFIG_BUCKET_NAME",
    "snsTopicARN": "$CONFIG_TOPIC_ARN",
    "configSnapshotDeliveryProperties": {
        "deliveryFrequency": "TwentyFour_Hours"
    }
}
EOF
    
    CREATED_FILES+=("$delivery_channel_config")
    
    # Create delivery channel
    if aws configservice describe-delivery-channels --delivery-channel-names default &>/dev/null; then
        warning "Config delivery channel already exists, updating..."
        aws configservice put-delivery-channel \
            --delivery-channel "file://$delivery_channel_config"
    else
        aws configservice put-delivery-channel \
            --delivery-channel "file://$delivery_channel_config"
        CREATED_RESOURCES+=("config-delivery-channel:default")
    fi
    
    # Create configuration recorder
    if aws configservice describe-configuration-recorders --configuration-recorder-names default &>/dev/null; then
        warning "Config recorder already exists, updating..."
    else
        aws configservice put-configuration-recorder \
            --configuration-recorder "name=default,roleARN=$CONFIG_ROLE_ARN" \
            --recording-group "allSupported=true,includeGlobalResourceTypes=true"
        CREATED_RESOURCES+=("config-recorder:default")
    fi
    
    # Start configuration recorder
    aws configservice start-configuration-recorder \
        --configuration-recorder-name default
    
    success "AWS Config service configured successfully."
}

#==============================================================================
# Config Rules Setup
#==============================================================================

create_config_rules() {
    info "Creating AWS Config rules..."
    
    # S3 bucket public access rule
    aws configservice put-config-rule \
        --config-rule '{
            "ConfigRuleName": "s3-bucket-public-access-prohibited",
            "Description": "Checks that S3 buckets do not allow public access",
            "Source": {
                "Owner": "AWS",
                "SourceIdentifier": "S3_BUCKET_PUBLIC_ACCESS_PROHIBITED"
            },
            "Scope": {
                "ComplianceResourceTypes": ["AWS::S3::Bucket"]
            }
        }' &>/dev/null
    
    CREATED_RESOURCES+=("config-rule:s3-bucket-public-access-prohibited")
    
    # Encrypted EBS volumes rule
    aws configservice put-config-rule \
        --config-rule '{
            "ConfigRuleName": "encrypted-volumes",
            "Description": "Checks whether EBS volumes are encrypted",
            "Source": {
                "Owner": "AWS",
                "SourceIdentifier": "ENCRYPTED_VOLUMES"
            },
            "Scope": {
                "ComplianceResourceTypes": ["AWS::EC2::Volume"]
            }
        }' &>/dev/null
    
    CREATED_RESOURCES+=("config-rule:encrypted-volumes")
    
    # Root access key check
    aws configservice put-config-rule \
        --config-rule '{
            "ConfigRuleName": "root-access-key-check",
            "Description": "Checks whether root access keys exist",
            "Source": {
                "Owner": "AWS",
                "SourceIdentifier": "ROOT_ACCESS_KEY_CHECK"
            }
        }' &>/dev/null
    
    CREATED_RESOURCES+=("config-rule:root-access-key-check")
    
    # Required tags rule
    aws configservice put-config-rule \
        --config-rule '{
            "ConfigRuleName": "required-tags-ec2",
            "Description": "Checks whether EC2 instances have required tags",
            "Source": {
                "Owner": "AWS",
                "SourceIdentifier": "REQUIRED_TAGS"
            },
            "Scope": {
                "ComplianceResourceTypes": ["AWS::EC2::Instance"]
            },
            "InputParameters": "{\"tag1Key\":\"Environment\",\"tag2Key\":\"Owner\"}"
        }' &>/dev/null
    
    CREATED_RESOURCES+=("config-rule:required-tags-ec2")
    
    success "AWS managed Config rules created successfully."
}

#==============================================================================
# Lambda Functions
#==============================================================================

create_lambda_functions() {
    info "Creating Lambda functions..."
    
    # Create custom security group rule function
    local sg_function_file="/tmp/sg-rule-function-${RANDOM}.py"
    cat > "$sg_function_file" << 'EOF'
import boto3
import json

def lambda_handler(event, context):
    # Initialize AWS Config client
    config = boto3.client('config')
    
    # Get configuration item from event
    configuration_item = event['configurationItem']
    
    # Initialize compliance status
    compliance_status = 'COMPLIANT'
    
    # Check if resource is a Security Group
    if configuration_item['resourceType'] == 'AWS::EC2::SecurityGroup':
        # Get security group configuration
        sg_config = configuration_item['configuration']
        
        # Check for overly permissive ingress rules
        for rule in sg_config.get('ipPermissions', []):
            for ip_range in rule.get('ipRanges', []):
                if ip_range.get('cidrIp') == '0.0.0.0/0':
                    # Check if it's not port 80 or 443
                    if rule.get('fromPort') not in [80, 443]:
                        compliance_status = 'NON_COMPLIANT'
                        break
            if compliance_status == 'NON_COMPLIANT':
                break
    
    # Put evaluation result
    config.put_evaluations(
        Evaluations=[
            {
                'ComplianceResourceType': configuration_item['resourceType'],
                'ComplianceResourceId': configuration_item['resourceId'],
                'ComplianceType': compliance_status,
                'OrderingTimestamp': configuration_item['configurationItemCaptureTime']
            }
        ],
        ResultToken=event['resultToken']
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps('Config rule evaluation completed')
    }
EOF
    
    CREATED_FILES+=("$sg_function_file")
    
    # Create deployment package for security group function
    local sg_zip_file="/tmp/sg-rule-function-${RANDOM}.zip"
    (cd "$(dirname "$sg_function_file")" && zip "$sg_zip_file" "$(basename "$sg_function_file")")
    CREATED_FILES+=("$sg_zip_file")
    
    # Deploy security group Lambda function
    export SECURITY_GROUP_LAMBDA_ARN
    SECURITY_GROUP_LAMBDA_ARN=$(aws lambda create-function \
        --function-name "$SECURITY_GROUP_LAMBDA_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler "$(basename "$sg_function_file" .py).lambda_handler" \
        --zip-file "fileb://$sg_zip_file" \
        --timeout 60 \
        --query 'FunctionArn' --output text)
    
    CREATED_RESOURCES+=("lambda:$SECURITY_GROUP_LAMBDA_NAME")
    
    # Create remediation function
    local remediation_function_file="/tmp/remediation-function-${RANDOM}.py"
    cat > "$remediation_function_file" << 'EOF'
import boto3
import json

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    s3 = boto3.client('s3')
    
    # Parse the event
    detail = event['detail']
    config_rule_name = detail['configRuleName']
    compliance_type = detail['newEvaluationResult']['complianceType']
    resource_type = detail['resourceType']
    resource_id = detail['resourceId']
    
    if compliance_type == 'NON_COMPLIANT':
        if config_rule_name == 'required-tags-ec2' and resource_type == 'AWS::EC2::Instance':
            # Add missing tags to EC2 instance
            ec2.create_tags(
                Resources=[resource_id],
                Tags=[
                    {'Key': 'Environment', 'Value': 'Unknown'},
                    {'Key': 'Owner', 'Value': 'Unknown'}
                ]
            )
            print(f"Added missing tags to EC2 instance {resource_id}")
        
        elif config_rule_name == 's3-bucket-public-access-prohibited' and resource_type == 'AWS::S3::Bucket':
            # Block public access on S3 bucket
            s3.put_public_access_block(
                Bucket=resource_id,
                PublicAccessBlockConfiguration={
                    'BlockPublicAcls': True,
                    'IgnorePublicAcls': True,
                    'BlockPublicPolicy': True,
                    'RestrictPublicBuckets': True
                }
            )
            print(f"Blocked public access on S3 bucket {resource_id}")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Remediation completed')
    }
EOF
    
    CREATED_FILES+=("$remediation_function_file")
    
    # Create deployment package for remediation function
    local remediation_zip_file="/tmp/remediation-function-${RANDOM}.zip"
    (cd "$(dirname "$remediation_function_file")" && zip "$remediation_zip_file" "$(basename "$remediation_function_file")")
    CREATED_FILES+=("$remediation_zip_file")
    
    # Deploy remediation Lambda function
    export REMEDIATION_LAMBDA_ARN
    REMEDIATION_LAMBDA_ARN=$(aws lambda create-function \
        --function-name "$REMEDIATION_LAMBDA_NAME" \
        --runtime python3.9 \
        --role "$REMEDIATION_ROLE_ARN" \
        --handler "$(basename "$remediation_function_file" .py).lambda_handler" \
        --zip-file "fileb://$remediation_zip_file" \
        --timeout 60 \
        --query 'FunctionArn' --output text)
    
    CREATED_RESOURCES+=("lambda:$REMEDIATION_LAMBDA_NAME")
    
    success "Lambda functions created successfully."
    info "Security Group Lambda: $SECURITY_GROUP_LAMBDA_ARN"
    info "Remediation Lambda: $REMEDIATION_LAMBDA_ARN"
}

#==============================================================================
# Custom Config Rule
#==============================================================================

create_custom_config_rule() {
    info "Creating custom Config rule with Lambda..."
    
    # Add permission for Config to invoke Lambda
    aws lambda add-permission \
        --function-name "$SECURITY_GROUP_LAMBDA_NAME" \
        --statement-id ConfigPermission \
        --action lambda:InvokeFunction \
        --principal config.amazonaws.com \
        --source-account "$AWS_ACCOUNT_ID" &>/dev/null
    
    # Create custom Config rule
    aws configservice put-config-rule \
        --config-rule '{
            "ConfigRuleName": "security-group-restricted-ingress",
            "Description": "Checks that security groups do not allow unrestricted ingress except for ports 80 and 443",
            "Source": {
                "Owner": "CUSTOM_LAMBDA",
                "SourceIdentifier": "'"$SECURITY_GROUP_LAMBDA_ARN"'",
                "SourceDetails": [
                    {
                        "EventSource": "aws.config",
                        "MessageType": "ConfigurationItemChangeNotification"
                    }
                ]
            },
            "Scope": {
                "ComplianceResourceTypes": ["AWS::EC2::SecurityGroup"]
            }
        }' &>/dev/null
    
    CREATED_RESOURCES+=("config-rule:security-group-restricted-ingress")
    
    success "Custom Config rule created successfully."
}

#==============================================================================
# EventBridge Setup
#==============================================================================

setup_eventbridge() {
    info "Setting up EventBridge for automated remediation..."
    
    # Create EventBridge rule
    aws events put-rule \
        --name "$EVENTBRIDGE_RULE_NAME" \
        --event-pattern '{
            "source": ["aws.config"],
            "detail-type": ["Config Rules Compliance Change"],
            "detail": {
                "newEvaluationResult": {
                    "complianceType": ["NON_COMPLIANT"]
                }
            }
        }' \
        --state ENABLED &>/dev/null
    
    CREATED_RESOURCES+=("eventbridge-rule:$EVENTBRIDGE_RULE_NAME")
    
    # Add Lambda permission for EventBridge
    aws lambda add-permission \
        --function-name "$REMEDIATION_LAMBDA_NAME" \
        --statement-id EventBridgePermission \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:$AWS_REGION:$AWS_ACCOUNT_ID:rule/$EVENTBRIDGE_RULE_NAME" &>/dev/null
    
    # Add Lambda as target for EventBridge rule
    aws events put-targets \
        --rule "$EVENTBRIDGE_RULE_NAME" \
        --targets "Id=1,Arn=$REMEDIATION_LAMBDA_ARN" &>/dev/null
    
    success "EventBridge rule created successfully."
}

#==============================================================================
# CloudWatch Setup
#==============================================================================

setup_cloudwatch() {
    info "Setting up CloudWatch dashboard and alarms..."
    
    # Create CloudWatch dashboard
    local dashboard_config="/tmp/dashboard-${RANDOM}.json"
    cat > "$dashboard_config" << EOF
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
                    ["AWS/Config", "ComplianceByConfigRule", "ConfigRuleName", "s3-bucket-public-access-prohibited"],
                    [".", ".", ".", "encrypted-volumes"],
                    [".", ".", ".", "root-access-key-check"],
                    [".", ".", ".", "required-tags-ec2"],
                    [".", ".", ".", "security-group-restricted-ingress"]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "$AWS_REGION",
                "title": "Config Rule Compliance Status",
                "period": 300,
                "stat": "Average"
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
                    ["AWS/Lambda", "Invocations", "FunctionName", "$REMEDIATION_LAMBDA_NAME"],
                    [".", "Errors", ".", "."],
                    [".", "Duration", ".", "."]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "$AWS_REGION",
                "title": "Remediation Function Metrics",
                "period": 300
            }
        }
    ]
}
EOF
    
    CREATED_FILES+=("$dashboard_config")
    
    aws cloudwatch put-dashboard \
        --dashboard-name "$DASHBOARD_NAME" \
        --dashboard-body "file://$dashboard_config" &>/dev/null
    
    CREATED_RESOURCES+=("cloudwatch-dashboard:$DASHBOARD_NAME")
    
    # Create CloudWatch alarms
    aws cloudwatch put-metric-alarm \
        --alarm-name "ConfigNonCompliantResources-${AWS_REGION}" \
        --alarm-description "Alert when non-compliant resources are detected" \
        --metric-name ComplianceByConfigRule \
        --namespace AWS/Config \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 2 \
        --alarm-actions "$CONFIG_TOPIC_ARN" &>/dev/null
    
    CREATED_RESOURCES+=("cloudwatch-alarm:ConfigNonCompliantResources-${AWS_REGION}")
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "ConfigRemediationErrors-${AWS_REGION}" \
        --alarm-description "Alert when remediation function encounters errors" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --dimensions Name=FunctionName,Value="$REMEDIATION_LAMBDA_NAME" \
        --alarm-actions "$CONFIG_TOPIC_ARN" &>/dev/null
    
    CREATED_RESOURCES+=("cloudwatch-alarm:ConfigRemediationErrors-${AWS_REGION}")
    
    success "CloudWatch dashboard and alarms created successfully."
}

#==============================================================================
# Validation and Testing
#==============================================================================

validate_deployment() {
    info "Validating deployment..."
    
    # Check Config service status
    local config_status
    config_status=$(aws configservice get-status --query 'ConfigurationRecordersStatus[0].recording' --output text 2>/dev/null || echo "false")
    
    if [[ "$config_status" == "true" ]]; then
        success "Config service is recording configurations"
    else
        warning "Config service recording status: $config_status"
    fi
    
    # Check Config rules
    local rule_count
    rule_count=$(aws configservice describe-config-rules --query 'length(ConfigRules)' --output text 2>/dev/null || echo "0")
    info "Config rules created: $rule_count"
    
    # Check Lambda functions
    for lambda_name in "$SECURITY_GROUP_LAMBDA_NAME" "$REMEDIATION_LAMBDA_NAME"; do
        if aws lambda get-function --function-name "$lambda_name" &>/dev/null; then
            success "Lambda function $lambda_name is deployed"
        else
            error "Lambda function $lambda_name deployment failed"
        fi
    done
    
    # Check EventBridge rule
    if aws events describe-rule --name "$EVENTBRIDGE_RULE_NAME" &>/dev/null; then
        success "EventBridge rule $EVENTBRIDGE_RULE_NAME is active"
    else
        error "EventBridge rule deployment failed"
    fi
    
    success "Deployment validation completed."
}

#==============================================================================
# Main Deployment Function
#==============================================================================

main() {
    info "Starting AWS Config Compliance Monitoring deployment..."
    
    # Pre-deployment checks
    check_prerequisites
    validate_region
    estimate_costs
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN MODE: Would deploy compliance monitoring system"
        exit 0
    fi
    
    # Environment setup
    setup_environment
    
    # Core infrastructure deployment
    create_iam_roles
    create_s3_sns_resources
    setup_aws_config
    create_config_rules
    create_lambda_functions
    create_custom_config_rule
    setup_eventbridge
    setup_cloudwatch
    
    # Validation
    validate_deployment
    
    # Clean up temporary files
    for file in "${CREATED_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
        fi
    done
    
    # Deployment summary
    cat << EOF

${GREEN}===============================================================================${NC}
${GREEN}DEPLOYMENT COMPLETED SUCCESSFULLY${NC}
${GREEN}===============================================================================${NC}

AWS Config Compliance Monitoring System has been deployed successfully!

${BLUE}RESOURCES CREATED:${NC}
• S3 Bucket: $CONFIG_BUCKET_NAME
• SNS Topic: $CONFIG_TOPIC_ARN
• Config Service Role: $CONFIG_ROLE_NAME
• Lambda Functions: $SECURITY_GROUP_LAMBDA_NAME, $REMEDIATION_LAMBDA_NAME
• CloudWatch Dashboard: $DASHBOARD_NAME
• EventBridge Rule: $EVENTBRIDGE_RULE_NAME

${BLUE}NEXT STEPS:${NC}
1. View the CloudWatch dashboard: https://console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:name=$DASHBOARD_NAME
2. Monitor Config rules: https://console.aws.amazon.com/config/home?region=$AWS_REGION#/rules
3. Check compliance status: aws configservice get-compliance-summary-by-config-rule
4. Test the system by creating non-compliant resources

${BLUE}CLEANUP:${NC}
To remove all resources, run: ./destroy.sh

${YELLOW}LOG FILE:${NC} $LOG_FILE

EOF
}

#==============================================================================
# Script Execution
#==============================================================================

# Show usage if help requested
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    cat << EOF
AWS Config Compliance Monitoring - Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help      Show this help message
    --dry-run       Show what would be deployed without making changes

ENVIRONMENT VARIABLES:
    DRY_RUN         Set to 'true' for dry run mode
    AWS_REGION      Override default AWS region
    AWS_PROFILE     Use specific AWS profile

EXAMPLES:
    $0                      # Deploy with default settings
    $0 --dry-run           # Preview deployment
    DRY_RUN=true $0        # Preview using environment variable
    AWS_REGION=us-west-2 $0 # Deploy to specific region

EOF
    exit 0
fi

# Handle command line arguments
if [[ "${1:-}" == "--dry-run" ]]; then
    export DRY_RUN=true
fi

# Execute main function
main "$@"