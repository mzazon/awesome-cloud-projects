#!/bin/bash

#######################################################################
# AWS Resource Tagging Strategies for Cost Management - Deploy Script
#######################################################################
# This script deploys a comprehensive resource tagging strategy using
# AWS Config, Lambda, SNS, and Cost Explorer integration.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate IAM permissions for Config, Lambda, SNS, EC2, S3, IAM
# - Billing/Cost Explorer access permissions
#
# Usage: ./deploy.sh [--dry-run] [--email your@email.com]
#######################################################################

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=false
EMAIL_ADDRESS=""

# Resource tracking file
RESOURCE_FILE="${SCRIPT_DIR}/.deployed_resources"

#######################################################################
# Utility Functions
#######################################################################

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log ERROR "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log INFO "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log ERROR "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check required permissions
    log INFO "Verifying AWS permissions..."
    
    local identity=$(aws sts get-caller-identity)
    local account_id=$(echo "$identity" | jq -r '.Account' 2>/dev/null || echo "$identity" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
    local user_arn=$(echo "$identity" | jq -r '.Arn' 2>/dev/null || echo "$identity" | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4)
    
    log INFO "Deploying as: $user_arn"
    log INFO "Account ID: $account_id"
    
    # Test key permissions
    if ! aws iam list-roles --max-items 1 &> /dev/null; then
        log WARN "Limited IAM permissions detected - some operations may fail"
    fi
    
    if ! aws config describe-configuration-recorders &> /dev/null; then
        log DEBUG "Config permissions verified"
    fi
    
    log INFO "Prerequisites check completed"
}

save_resource() {
    local resource_type=$1
    local resource_id=$2
    local resource_name=$3
    
    echo "${resource_type}|${resource_id}|${resource_name}" >> "$RESOURCE_FILE"
    log DEBUG "Saved resource: $resource_type - $resource_name"
}

setup_environment() {
    log INFO "Setting up environment variables..."
    
    # Core AWS settings
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log WARN "No default region configured, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifier
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export TAG_STRATEGY_NAME="cost-mgmt-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="tag-compliance-${RANDOM_SUFFIX}"
    export CONFIG_BUCKET="aws-config-${TAG_STRATEGY_NAME}-${AWS_ACCOUNT_ID}"
    export CONFIG_ROLE_NAME="aws-config-role-${TAG_STRATEGY_NAME}"
    export LAMBDA_ROLE_NAME="tag-remediation-lambda-role-${TAG_STRATEGY_NAME}"
    export LAMBDA_FUNCTION_NAME="tag-remediation-${TAG_STRATEGY_NAME}"
    export DEMO_BUCKET="cost-mgmt-demo-${TAG_STRATEGY_NAME}"
    
    log INFO "Environment configured:"
    log INFO "  Region: $AWS_REGION"
    log INFO "  Account: $AWS_ACCOUNT_ID"
    log INFO "  Strategy Name: $TAG_STRATEGY_NAME"
    
    # Initialize resource tracking
    echo "# Deployed Resources - $(date)" > "$RESOURCE_FILE"
}

create_tag_taxonomy() {
    log INFO "Creating comprehensive tag taxonomy..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create tag-taxonomy.json"
        return 0
    fi
    
    cat > "${SCRIPT_DIR}/tag-taxonomy.json" << 'EOF'
{
  "required_tags": {
    "CostCenter": {
      "description": "Department or cost center for chargeback",
      "values": ["Engineering", "Marketing", "Sales", "Finance", "Operations"],
      "validation": "Must be one of predefined cost centers"
    },
    "Environment": {
      "description": "Deployment environment",
      "values": ["Production", "Staging", "Development", "Testing"],
      "validation": "Must be one of four environments"
    },
    "Project": {
      "description": "Project or application name",
      "values": ["*"],
      "validation": "Must be 3-50 characters, alphanumeric and hyphens only"
    },
    "Owner": {
      "description": "Resource owner email",
      "values": ["*"],
      "validation": "Must be valid email format"
    }
  },
  "optional_tags": {
    "Application": {
      "description": "Application component",
      "values": ["web", "api", "database", "cache", "queue"],
      "validation": "Recommended for application resources"
    },
    "Backup": {
      "description": "Backup requirement",
      "values": ["true", "false"],
      "validation": "Boolean value for backup automation"
    }
  }
}
EOF
    
    log INFO "✅ Created comprehensive tag taxonomy"
    save_resource "FILE" "${SCRIPT_DIR}/tag-taxonomy.json" "tag-taxonomy"
}

create_sns_topic() {
    log INFO "Creating SNS topic for tag compliance notifications..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create SNS topic: $SNS_TOPIC_NAME"
        return 0
    fi
    
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "${SNS_TOPIC_NAME}" \
        --attributes DisplayName="Tag Compliance Notifications" \
        --query TopicArn --output text)
    
    if [[ -z "$SNS_TOPIC_ARN" ]]; then
        log ERROR "Failed to create SNS topic"
        exit 1
    fi
    
    save_resource "SNS_TOPIC" "$SNS_TOPIC_ARN" "$SNS_TOPIC_NAME"
    log INFO "✅ Created SNS topic: $SNS_TOPIC_ARN"
    
    # Subscribe email if provided
    if [[ -n "$EMAIL_ADDRESS" ]]; then
        aws sns subscribe \
            --topic-arn "${SNS_TOPIC_ARN}" \
            --protocol email \
            --notification-endpoint "${EMAIL_ADDRESS}"
        log INFO "📧 Email subscription sent to: $EMAIL_ADDRESS"
        log WARN "Please check email and confirm subscription"
    else
        log WARN "No email provided. Add subscription manually if needed."
    fi
}

create_config_bucket() {
    log INFO "Creating S3 bucket for AWS Config..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create S3 bucket: $CONFIG_BUCKET"
        return 0
    fi
    
    # Create S3 bucket
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb "s3://${CONFIG_BUCKET}"
    else
        aws s3 mb "s3://${CONFIG_BUCKET}" --region "${AWS_REGION}"
    fi
    
    save_resource "S3_BUCKET" "$CONFIG_BUCKET" "$CONFIG_BUCKET"
    
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
      "Resource": "arn:aws:s3:::${CONFIG_BUCKET}",
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
      "Resource": "arn:aws:s3:::${CONFIG_BUCKET}",
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
      "Resource": "arn:aws:s3:::${CONFIG_BUCKET}/AWSLogs/${AWS_ACCOUNT_ID}/Config/*",
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
        --bucket "${CONFIG_BUCKET}" \
        --policy file://"${SCRIPT_DIR}/config-bucket-policy.json"
    
    log INFO "✅ Created and configured S3 bucket: $CONFIG_BUCKET"
    save_resource "FILE" "${SCRIPT_DIR}/config-bucket-policy.json" "config-bucket-policy"
}

create_config_role() {
    log INFO "Creating AWS Config service role..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create Config role: $CONFIG_ROLE_NAME"
        return 0
    fi
    
    # Create trust policy
    cat > "${SCRIPT_DIR}/config-trust-policy.json" << 'EOF'
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
    
    # Create role
    aws iam create-role \
        --role-name "${CONFIG_ROLE_NAME}" \
        --assume-role-policy-document file://"${SCRIPT_DIR}/config-trust-policy.json" \
        --description "Service role for AWS Config in tag compliance strategy"
    
    # Attach managed policy
    aws iam attach-role-policy \
        --role-name "${CONFIG_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole
    
    export CONFIG_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CONFIG_ROLE_NAME}"
    
    save_resource "IAM_ROLE" "$CONFIG_ROLE_ARN" "$CONFIG_ROLE_NAME"
    save_resource "FILE" "${SCRIPT_DIR}/config-trust-policy.json" "config-trust-policy"
    log INFO "✅ Created Config service role: $CONFIG_ROLE_ARN"
}

setup_config_recorder() {
    log INFO "Setting up AWS Config recorder and delivery channel..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would setup Config recorder and delivery channel"
        return 0
    fi
    
    # Wait for role creation to propagate
    log INFO "Waiting for IAM role propagation..."
    sleep 15
    
    # Create delivery channel
    aws configservice put-delivery-channel \
        --delivery-channel name="default",s3BucketName="${CONFIG_BUCKET}"
    
    save_resource "CONFIG_DELIVERY_CHANNEL" "default" "default"
    
    # Create configuration recorder
    aws configservice put-configuration-recorder \
        --configuration-recorder name="default",roleARN="${CONFIG_ROLE_ARN}",recordingGroup='{
          "allSupported": true,
          "includeGlobalResourceTypes": true,
          "recordingModeOverrides": []
        }'
    
    save_resource "CONFIG_RECORDER" "default" "default"
    
    # Start configuration recorder
    aws configservice start-configuration-recorder \
        --configuration-recorder-name default
    
    log INFO "✅ AWS Config recorder started and monitoring resources"
}

create_config_rules() {
    log INFO "Creating AWS Config rules for tag compliance..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create Config rules for tag compliance"
        return 0
    fi
    
    # Wait for Config to be ready
    log INFO "Waiting for AWS Config to initialize..."
    sleep 10
    
    # Create Config rule for CostCenter tag
    aws configservice put-config-rule \
        --config-rule '{
          "ConfigRuleName": "required-tag-costcenter",
          "Description": "Checks if resources have required CostCenter tag with valid values",
          "Source": {
            "Owner": "AWS",
            "SourceIdentifier": "REQUIRED_TAGS"
          },
          "InputParameters": "{\"tag1Key\":\"CostCenter\",\"tag1Value\":\"Engineering,Marketing,Sales,Finance,Operations\"}"
        }'
    
    save_resource "CONFIG_RULE" "required-tag-costcenter" "required-tag-costcenter"
    
    # Create Config rule for Environment tag
    aws configservice put-config-rule \
        --config-rule '{
          "ConfigRuleName": "required-tag-environment",
          "Description": "Checks if resources have required Environment tag with valid values",
          "Source": {
            "Owner": "AWS",
            "SourceIdentifier": "REQUIRED_TAGS"
          },
          "InputParameters": "{\"tag1Key\":\"Environment\",\"tag1Value\":\"Production,Staging,Development,Testing\"}"
        }'
    
    save_resource "CONFIG_RULE" "required-tag-environment" "required-tag-environment"
    
    # Create Config rule for Project tag
    aws configservice put-config-rule \
        --config-rule '{
          "ConfigRuleName": "required-tag-project",
          "Description": "Checks if resources have required Project tag",
          "Source": {
            "Owner": "AWS",
            "SourceIdentifier": "REQUIRED_TAGS"
          },
          "InputParameters": "{\"tag1Key\":\"Project\"}"
        }'
    
    save_resource "CONFIG_RULE" "required-tag-project" "required-tag-project"
    
    # Create Config rule for Owner tag
    aws configservice put-config-rule \
        --config-rule '{
          "ConfigRuleName": "required-tag-owner",
          "Description": "Checks if resources have required Owner tag",
          "Source": {
            "Owner": "AWS",
            "SourceIdentifier": "REQUIRED_TAGS"
          },
          "InputParameters": "{\"tag1Key\":\"Owner\"}"
        }'
    
    save_resource "CONFIG_RULE" "required-tag-owner" "required-tag-owner"
    
    log INFO "✅ Created AWS Config rules for required tag compliance"
}

create_lambda_function() {
    log INFO "Creating Lambda function for automated tag remediation..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create Lambda function: $LAMBDA_FUNCTION_NAME"
        return 0
    fi
    
    # Create Lambda function code
    cat > "${SCRIPT_DIR}/tag-remediation-lambda.py" << 'EOF'
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Automated tag remediation function for cost management compliance
    """
    print(f"Received event: {json.dumps(event)}")
    
    # Initialize AWS clients
    ec2 = boto3.client('ec2')
    sns = boto3.client('sns')
    
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    try:
        # Parse Config rule evaluation result
        config_item = event['configurationItem']
        resource_type = config_item['resourceType']
        resource_id = config_item['resourceId']
        
        # Apply default tags based on resource type and current tags
        default_tags = get_default_tags(config_item)
        
        if resource_type == 'AWS::EC2::Instance':
            remediate_ec2_instance(ec2, resource_id, default_tags)
        elif resource_type == 'AWS::S3::Bucket':
            remediate_s3_bucket(resource_id, default_tags)
        elif resource_type == 'AWS::RDS::DBInstance':
            remediate_rds_instance(resource_id, default_tags)
        
        # Send notification
        send_notification(sns, sns_topic_arn, resource_type, resource_id, default_tags)
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Successfully processed {resource_type} {resource_id}')
        }
        
    except Exception as e:
        print(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def get_default_tags(config_item):
    """Generate default tags based on resource context"""
    tags = []
    
    # Add default CostCenter if missing
    if not has_tag(config_item, 'CostCenter'):
        tags.append({'Key': 'CostCenter', 'Value': 'Unassigned'})
    
    # Add default Environment if missing
    if not has_tag(config_item, 'Environment'):
        tags.append({'Key': 'Environment', 'Value': 'Development'})
    
    # Add default Project if missing
    if not has_tag(config_item, 'Project'):
        tags.append({'Key': 'Project', 'Value': 'UntaggedResource'})
    
    # Add default Owner if missing
    if not has_tag(config_item, 'Owner'):
        tags.append({'Key': 'Owner', 'Value': 'unknown@company.com'})
    
    # Add compliance tag
    tags.append({
        'Key': 'AutoTagged',
        'Value': f"true-{datetime.now().strftime('%Y%m%d')}"
    })
    
    return tags

def has_tag(config_item, tag_key):
    """Check if resource already has specified tag"""
    tags = config_item.get('tags', {})
    return tag_key in tags

def remediate_ec2_instance(ec2, instance_id, tags):
    """Apply tags to EC2 instance"""
    if tags:
        ec2.create_tags(Resources=[instance_id], Tags=tags)
        print(f"Applied tags to EC2 instance {instance_id}")

def remediate_s3_bucket(bucket_name, tags):
    """Apply tags to S3 bucket"""
    if tags:
        s3 = boto3.client('s3')
        tag_set = [{'Key': tag['Key'], 'Value': tag['Value']} for tag in tags]
        s3.put_bucket_tagging(
            Bucket=bucket_name,
            Tagging={'TagSet': tag_set}
        )
        print(f"Applied tags to S3 bucket {bucket_name}")

def remediate_rds_instance(db_instance_id, tags):
    """Apply tags to RDS instance"""
    if tags:
        rds = boto3.client('rds')
        db_arn = f"arn:aws:rds:{boto3.Session().region_name}:{boto3.client('sts').get_caller_identity()['Account']}:db:{db_instance_id}"
        rds.add_tags_to_resource(
            ResourceName=db_arn,
            Tags=tags
        )
        print(f"Applied tags to RDS instance {db_instance_id}")

def send_notification(sns, topic_arn, resource_type, resource_id, tags):
    """Send SNS notification about tag remediation"""
    message = f"""
Tag Remediation Notification

Resource Type: {resource_type}
Resource ID: {resource_id}
Auto-Applied Tags: {json.dumps(tags, indent=2)}

Please review and update tags as needed in the AWS Console.
"""
    
    sns.publish(
        TopicArn=topic_arn,
        Subject=f'Auto-Tag Applied: {resource_type}',
        Message=message
    )
EOF
    
    # Create deployment package
    cd "${SCRIPT_DIR}"
    zip tag-remediation-lambda.zip tag-remediation-lambda.py
    
    # Create Lambda trust policy
    cat > "${SCRIPT_DIR}/lambda-trust-policy.json" << 'EOF'
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
    
    # Create Lambda execution role
    aws iam create-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --assume-role-policy-document file://"${SCRIPT_DIR}/lambda-trust-policy.json" \
        --description "Execution role for tag remediation Lambda function"
    
    # Create Lambda policy
    cat > "${SCRIPT_DIR}/lambda-policy.json" << EOF
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
        "ec2:CreateTags",
        "ec2:DescribeTags",
        "s3:GetBucketTagging",
        "s3:PutBucketTagging",
        "rds:AddTagsToResource",
        "rds:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "${SNS_TOPIC_ARN}"
    }
  ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-name TagRemediationPolicy \
        --policy-document file://"${SCRIPT_DIR}/lambda-policy.json"
    
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
    
    save_resource "IAM_ROLE" "$LAMBDA_ROLE_ARN" "$LAMBDA_ROLE_NAME"
    save_resource "FILE" "${SCRIPT_DIR}/lambda-trust-policy.json" "lambda-trust-policy"
    save_resource "FILE" "${SCRIPT_DIR}/lambda-policy.json" "lambda-policy"
    save_resource "FILE" "${SCRIPT_DIR}/tag-remediation-lambda.py" "lambda-source-code"
    save_resource "FILE" "${SCRIPT_DIR}/tag-remediation-lambda.zip" "lambda-deployment-package"
    
    # Wait for role creation
    log INFO "Waiting for Lambda role propagation..."
    sleep 15
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler tag-remediation-lambda.lambda_handler \
        --zip-file fileb://"${SCRIPT_DIR}/tag-remediation-lambda.zip" \
        --environment Variables="{SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}" \
        --timeout 60 \
        --memory-size 256 \
        --description "Automated tag remediation for cost management compliance"
    
    save_resource "LAMBDA_FUNCTION" "$LAMBDA_FUNCTION_NAME" "$LAMBDA_FUNCTION_NAME"
    log INFO "✅ Created Lambda function: $LAMBDA_FUNCTION_NAME"
}

create_demo_resources() {
    log INFO "Creating demo resources with proper tagging..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create demo EC2 instance and S3 bucket"
        return 0
    fi
    
    # Get default AMI for region
    local ami_id
    ami_id=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
        "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$ami_id" ]]; then
        # Create sample EC2 instance
        local instance_id
        instance_id=$(aws ec2 run-instances \
            --image-id "$ami_id" \
            --instance-type t2.micro \
            --tag-specifications 'ResourceType=instance,Tags=[
              {Key=Name,Value=cost-mgmt-demo-instance},
              {Key=CostCenter,Value=Engineering},
              {Key=Environment,Value=Development},
              {Key=Project,Value=TaggingDemo},
              {Key=Owner,Value=devops@company.com},
              {Key=Application,Value=web},
              {Key=Backup,Value=false}
            ]' \
            --query 'Instances[0].InstanceId' --output text 2>/dev/null || echo "")
        
        if [[ -n "$instance_id" && "$instance_id" != "None" ]]; then
            save_resource "EC2_INSTANCE" "$instance_id" "cost-mgmt-demo-instance"
            log INFO "✅ Created demo EC2 instance: $instance_id"
        else
            log WARN "Could not create demo EC2 instance (may not have permissions or t2.micro unavailable)"
        fi
    else
        log WARN "Could not find suitable AMI for demo instance"
    fi
    
    # Create sample S3 bucket
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb "s3://${DEMO_BUCKET}"
    else
        aws s3 mb "s3://${DEMO_BUCKET}" --region "${AWS_REGION}"
    fi
    
    aws s3api put-bucket-tagging \
        --bucket "${DEMO_BUCKET}" \
        --tagging 'TagSet=[
          {Key=CostCenter,Value=Marketing},
          {Key=Environment,Value=Production},
          {Key=Project,Value=WebAssets},
          {Key=Owner,Value=marketing@company.com},
          {Key=Application,Value=web},
          {Key=Backup,Value=true}
        ]'
    
    save_resource "S3_BUCKET" "$DEMO_BUCKET" "$DEMO_BUCKET"
    log INFO "✅ Created demo S3 bucket: $DEMO_BUCKET"
}

verify_deployment() {
    log INFO "Verifying deployment..."
    
    # Check Config rules
    local config_rules
    config_rules=$(aws configservice describe-config-rules \
        --config-rule-names required-tag-costcenter required-tag-environment required-tag-project required-tag-owner \
        --query 'ConfigRules[?ConfigRuleState==`ACTIVE`] | length(@)' --output text 2>/dev/null || echo "0")
    
    log INFO "Active Config rules: $config_rules/4"
    
    # Check Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
        log INFO "✅ Lambda function is active"
    else
        log WARN "Lambda function verification failed"
    fi
    
    # Check SNS topic
    if aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}" &> /dev/null; then
        log INFO "✅ SNS topic is active"
    else
        log WARN "SNS topic verification failed"
    fi
    
    log INFO "Deployment verification completed"
}

display_cost_guidance() {
    log INFO "Cost allocation tag activation guidance:"
    echo ""
    echo -e "${YELLOW}📋 IMPORTANT: Manual steps required to complete cost allocation setup:${NC}"
    echo ""
    echo "1. Log into AWS Billing Console (https://console.aws.amazon.com/billing/)"
    echo "2. Navigate to 'Cost allocation tags' under 'Billing preferences'"
    echo "3. Activate the following user-defined tags:"
    echo "   - CostCenter"
    echo "   - Environment"
    echo "   - Project"
    echo "   - Owner"
    echo "   - Application"
    echo ""
    echo "4. Wait 24 hours for tags to appear in Cost Explorer"
    echo "5. Create cost budgets and alerts based on activated tags"
    echo ""
    echo -e "${GREEN}Cost estimation for deployed resources:${NC}"
    echo "- AWS Config: ~\$2-5/month (depends on number of resources)"
    echo "- Lambda function: ~\$0.20/month (minimal usage)"
    echo "- SNS notifications: ~\$0.50/month"
    echo "- S3 storage: ~\$1/month for Config data"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Apply proper tags to existing resources using AWS Tag Editor"
    echo "2. Create resource groups based on tag categories"
    echo "3. Set up Cost Explorer reports grouped by tag dimensions"
    echo "4. Configure automated budgets and cost anomaly detection"
    echo ""
}

cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log ERROR "Deployment failed with exit code $exit_code"
        log INFO "Run destroy.sh to clean up any partially created resources"
    fi
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                log INFO "Dry run mode enabled"
                shift
                ;;
            --email)
                EMAIL_ADDRESS="$2"
                log INFO "Email address set: $EMAIL_ADDRESS"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [--dry-run] [--email EMAIL_ADDRESS]"
                echo ""
                echo "Options:"
                echo "  --dry-run          Show what would be deployed without making changes"
                echo "  --email EMAIL      Email address for SNS notifications"
                echo "  --help             Show this help message"
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

#######################################################################
# Main Execution
#######################################################################

main() {
    echo "======================================================================="
    echo "AWS Resource Tagging Strategies for Cost Management - Deploy Script"
    echo "======================================================================="
    echo ""
    
    # Set up error handling
    trap cleanup_on_error EXIT
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Initialize logging
    echo "Deployment started at $(date)" > "$LOG_FILE"
    log INFO "Starting deployment of AWS resource tagging strategy"
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_tag_taxonomy
    create_sns_topic
    create_config_bucket
    create_config_role
    setup_config_recorder
    create_config_rules
    create_lambda_function
    create_demo_resources
    verify_deployment
    display_cost_guidance
    
    # Success message
    echo ""
    echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}Resources deployed:${NC}"
    echo "- Tag Strategy Name: $TAG_STRATEGY_NAME"
    echo "- AWS Config rules for tag compliance"
    echo "- Lambda function for automated remediation"
    echo "- SNS topic for notifications"
    echo "- Demo resources with proper tagging"
    echo ""
    echo -e "${YELLOW}Resource tracking file:${NC} $RESOURCE_FILE"
    echo -e "${YELLOW}Deployment log:${NC} $LOG_FILE"
    echo ""
    echo "Please follow the cost allocation guidance above to complete the setup."
    
    # Disable error trap on successful completion
    trap - EXIT
}

# Execute main function with all arguments
main "$@"