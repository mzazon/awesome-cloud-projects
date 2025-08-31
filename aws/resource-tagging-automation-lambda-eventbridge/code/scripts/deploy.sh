#!/bin/bash

##############################################################################
# AWS Resource Tagging Automation Deployment Script
# 
# This script deploys an automated resource tagging solution using:
# - Lambda function for tagging logic
# - EventBridge for capturing resource creation events
# - IAM roles and policies for permissions
# - Resource Groups for organization
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - CloudTrail enabled in your AWS account
# - Administrative permissions for IAM, Lambda, EventBridge, and Resource Groups
##############################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION" | cut -d. -f1) -lt 2 ]]; then
        error "AWS CLI version 2.x is required. Current version: $AWS_CLI_VERSION"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid. Run 'aws configure' first."
    fi
    
    # Check if running in CloudShell (different Python path)
    if [[ -n "${AWS_EXECUTION_ENV:-}" ]]; then
        log "Running in AWS CloudShell environment"
    fi
    
    success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # AWS configuration
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "No default region set, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 7))
    
    # Resource names with unique suffix
    export LAMBDA_FUNCTION_NAME="auto-tagger-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="AutoTaggerRole-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_RULE_NAME="resource-creation-rule-${RANDOM_SUFFIX}"
    export RESOURCE_GROUP_NAME="auto-tagged-resources-${RANDOM_SUFFIX}"
    
    # Create deployment log
    export DEPLOYMENT_LOG="deployment-$(date +%Y%m%d-%H%M%S).log"
    
    success "Environment configured"
    log "AWS Region: ${AWS_REGION}"
    log "AWS Account: ${AWS_ACCOUNT_ID}"
    log "Resource suffix: ${RANDOM_SUFFIX}"
    log "Deployment log: ${DEPLOYMENT_LOG}"
}

# Create IAM role and policies
create_iam_resources() {
    log "Creating IAM role and policies..."
    
    # Create trust policy
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
    aws iam create-role \
        --role-name ${IAM_ROLE_NAME} \
        --assume-role-policy-document file://trust-policy.json \
        --description "Role for automated resource tagging Lambda function" \
        >> ${DEPLOYMENT_LOG} 2>&1
    
    # Store role ARN
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name ${IAM_ROLE_NAME} \
        --query 'Role.Arn' --output text)
    
    success "IAM role created: ${LAMBDA_ROLE_ARN}"
    
    # Create permissions policy
    cat > tagging-policy.json << 'EOF'
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
        "ec2:DescribeInstances",
        "ec2:DescribeImages",
        "ec2:DescribeVolumes",
        "s3:PutBucketTagging",
        "s3:GetBucketTagging",
        "rds:AddTagsToResource",
        "rds:ListTagsForResource",
        "lambda:TagResource",
        "lambda:ListTags"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "resource-groups:Tag",
        "resource-groups:GetTags",
        "tag:GetResources",
        "tag:TagResources"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    # Attach policy to role
    aws iam put-role-policy \
        --role-name ${IAM_ROLE_NAME} \
        --policy-name AutoTaggingPolicy \
        --policy-document file://tagging-policy.json \
        >> ${DEPLOYMENT_LOG} 2>&1
    
    success "IAM permissions policy attached"
    
    # Wait for IAM role to propagate
    log "Waiting for IAM role to propagate..."
    sleep 10
}

# Create Lambda function
create_lambda_function() {
    log "Creating Lambda function..."
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import boto3
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process CloudTrail events and apply tags to newly created resources
    """
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        event_name = detail.get('eventName', '')
        source_ip_address = detail.get('sourceIPAddress', 'unknown')
        user_identity = detail.get('userIdentity', {})
        user_name = user_identity.get('userName', user_identity.get('type', 'unknown'))
        
        logger.info(f"Processing event: {event_name} by user: {user_name}")
        
        # Define standard tags to apply
        standard_tags = {
            'AutoTagged': 'true',
            'Environment': 'production',
            'CostCenter': 'engineering',
            'CreatedBy': user_name,
            'CreatedDate': datetime.now().strftime('%Y-%m-%d'),
            'ManagedBy': 'automation'
        }
        
        # Process different resource types
        resources_tagged = 0
        
        if event_name == 'RunInstances':
            resources_tagged += tag_ec2_instances(detail, standard_tags)
        elif event_name == 'CreateBucket':
            resources_tagged += tag_s3_bucket(detail, standard_tags)
        elif event_name == 'CreateDBInstance':
            resources_tagged += tag_rds_instance(detail, standard_tags)  
        elif event_name == 'CreateFunction20150331':
            resources_tagged += tag_lambda_function(detail, standard_tags)
        
        logger.info(f"Successfully tagged {resources_tagged} resources")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Tagged {resources_tagged} resources',
                'event': event_name
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

def tag_ec2_instances(detail, tags):
    """Tag EC2 instances"""
    ec2 = boto3.client('ec2')
    instance_ids = []
    
    # Extract instance IDs from response elements
    response_elements = detail.get('responseElements', {})
    instances = response_elements.get('instancesSet', {}).get('items', [])
    
    for instance in instances:
        instance_ids.append(instance.get('instanceId'))
    
    if instance_ids:
        tag_list = [{'Key': k, 'Value': v} for k, v in tags.items()]
        ec2.create_tags(Resources=instance_ids, Tags=tag_list)
        logger.info(f"Tagged EC2 instances: {instance_ids}")
        return len(instance_ids)
    
    return 0

def tag_s3_bucket(detail, tags):
    """Tag S3 bucket"""
    s3 = boto3.client('s3')
    
    # Extract bucket name
    request_params = detail.get('requestParameters', {})
    bucket_name = request_params.get('bucketName')
    
    if bucket_name:
        tag_set = [{'Key': k, 'Value': v} for k, v in tags.items()]
        s3.put_bucket_tagging(
            Bucket=bucket_name,
            Tagging={'TagSet': tag_set}
        )
        logger.info(f"Tagged S3 bucket: {bucket_name}")
        return 1
    
    return 0

def tag_rds_instance(detail, tags):
    """Tag RDS instance"""
    rds = boto3.client('rds')
    
    # Extract DB instance identifier
    response_elements = detail.get('responseElements', {})
    db_instance = response_elements.get('dBInstance', {})
    db_instance_arn = db_instance.get('dBInstanceArn')
    
    if db_instance_arn:
        tag_list = [{'Key': k, 'Value': v} for k, v in tags.items()]
        rds.add_tags_to_resource(
            ResourceName=db_instance_arn,
            Tags=tag_list
        )
        logger.info(f"Tagged RDS instance: {db_instance_arn}")
        return 1
    
    return 0

def tag_lambda_function(detail, tags):
    """Tag Lambda function"""
    lambda_client = boto3.client('lambda')
    
    # Extract function name
    response_elements = detail.get('responseElements', {})
    function_arn = response_elements.get('functionArn')
    
    if function_arn:
        lambda_client.tag_resource(
            Resource=function_arn,
            Tags=tags
        )
        logger.info(f"Tagged Lambda function: {function_arn}")
        return 1
    
    return 0
EOF
    
    # Package Lambda function
    zip -r lambda-deployment.zip lambda_function.py >> ${DEPLOYMENT_LOG} 2>&1
    
    # Create Lambda function
    aws lambda create-function \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --runtime python3.12 \
        --role ${LAMBDA_ROLE_ARN} \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://lambda-deployment.zip \
        --timeout 60 \
        --memory-size 256 \
        --description "Automated resource tagging function" \
        >> ${DEPLOYMENT_LOG} 2>&1
    
    # Store Lambda function ARN
    export LAMBDA_FUNCTION_ARN=$(aws lambda get-function \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --query 'Configuration.FunctionArn' --output text)
    
    success "Lambda function created: ${LAMBDA_FUNCTION_NAME}"
    log "Lambda function ARN: ${LAMBDA_FUNCTION_ARN}"
}

# Create EventBridge rule and configure targets
create_eventbridge_resources() {
    log "Creating EventBridge rule and targets..."
    
    # Create event pattern
    cat > event-pattern.json << 'EOF'
{
  "source": ["aws.ec2", "aws.s3", "aws.rds", "aws.lambda"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventName": [
      "RunInstances",
      "CreateBucket", 
      "CreateDBInstance",
      "CreateFunction20150331"
    ],
    "eventSource": [
      "ec2.amazonaws.com",
      "s3.amazonaws.com",
      "rds.amazonaws.com",
      "lambda.amazonaws.com"
    ]
  }
}
EOF
    
    # Create EventBridge rule
    aws events put-rule \
        --name ${EVENTBRIDGE_RULE_NAME} \
        --event-pattern file://event-pattern.json \
        --state ENABLED \
        --description "Trigger tagging for new AWS resources" \
        >> ${DEPLOYMENT_LOG} 2>&1
    
    success "EventBridge rule created: ${EVENTBRIDGE_RULE_NAME}"
    
    # Add Lambda function as target
    aws events put-targets \
        --rule ${EVENTBRIDGE_RULE_NAME} \
        --targets Id=1,Arn=${LAMBDA_FUNCTION_ARN} \
        >> ${DEPLOYMENT_LOG} 2>&1
    
    # Grant EventBridge permission to invoke Lambda function
    aws lambda add-permission \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --statement-id allow-eventbridge \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}" \
        >> ${DEPLOYMENT_LOG} 2>&1
    
    success "Lambda function configured as EventBridge target"
}

# Create Resource Group
create_resource_group() {
    log "Creating Resource Group for tagged resources..."
    
    # Create resource group query
    cat > resource-group-query.json << 'EOF'
{
  "Type": "TAG_FILTERS_1_0",
  "Query": {
    "ResourceTypeFilters": ["AWS::AllSupported"],
    "TagFilters": [
      {
        "Key": "AutoTagged",
        "Values": ["true"]
      }
    ]
  }
}
EOF
    
    # Create Resource Group
    aws resource-groups create-group \
        --name ${RESOURCE_GROUP_NAME} \
        --description "Resources automatically tagged by Lambda function" \
        --resource-query file://resource-group-query.json \
        --tags Environment=production,Purpose=automation \
        >> ${DEPLOYMENT_LOG} 2>&1
    
    success "Resource Group created: ${RESOURCE_GROUP_NAME}"
}

# Test the deployment
test_deployment() {
    log "Testing automated tagging deployment..."
    
    # Verify EventBridge rule
    RULE_STATE=$(aws events describe-rule \
        --name ${EVENTBRIDGE_RULE_NAME} \
        --query 'State' --output text)
    
    if [[ "$RULE_STATE" != "ENABLED" ]]; then
        error "EventBridge rule is not enabled"
    fi
    
    # Verify Lambda function
    FUNCTION_STATE=$(aws lambda get-function \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --query 'Configuration.State' --output text)
    
    if [[ "$FUNCTION_STATE" != "Active" ]]; then
        error "Lambda function is not active"
    fi
    
    # Check if CloudTrail is enabled
    TRAIL_COUNT=$(aws cloudtrail describe-trails \
        --query 'length(trailList[?IsLogging==`true`])' --output text)
    
    if [[ "$TRAIL_COUNT" -eq 0 ]]; then
        warning "No active CloudTrail trails found. This solution requires CloudTrail to be enabled."
    fi
    
    success "Deployment validation completed"
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > deployment-info.json << EOF
{
  "deployment_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "aws_region": "${AWS_REGION}",
  "aws_account_id": "${AWS_ACCOUNT_ID}",
  "resources": {
    "lambda_function_name": "${LAMBDA_FUNCTION_NAME}",
    "lambda_function_arn": "${LAMBDA_FUNCTION_ARN}",
    "iam_role_name": "${IAM_ROLE_NAME}",
    "iam_role_arn": "${LAMBDA_ROLE_ARN}",
    "eventbridge_rule_name": "${EVENTBRIDGE_RULE_NAME}",
    "resource_group_name": "${RESOURCE_GROUP_NAME}"
  },
  "cleanup_command": "./destroy.sh"
}
EOF
    
    success "Deployment information saved to deployment-info.json"
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f trust-policy.json tagging-policy.json event-pattern.json
    rm -f resource-group-query.json lambda_function.py lambda-deployment.zip
    
    success "Temporary files cleaned up"
}

# Display final instructions
display_final_instructions() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo -e "${GREEN}🎉 AWS Resource Tagging Automation Successfully Deployed!${NC}"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    echo -e "${BLUE}📋 Deployment Summary:${NC}"
    echo "  • Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  • EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    echo "  • IAM Role: ${IAM_ROLE_NAME}"
    echo "  • Resource Group: ${RESOURCE_GROUP_NAME}"
    echo ""
    echo -e "${BLUE}📊 Monitoring:${NC}"
    echo "  • CloudWatch Logs: /aws/lambda/${LAMBDA_FUNCTION_NAME}"
    echo "  • EventBridge Rule State: ENABLED"
    echo "  • Resource Group: ${RESOURCE_GROUP_NAME}"
    echo ""
    echo -e "${BLUE}🔍 Next Steps:${NC}"
    echo "  1. Create test resources (EC2, S3, RDS, Lambda) to verify tagging"
    echo "  2. Monitor CloudWatch logs for Lambda function execution"
    echo "  3. Check Resource Group for automatically tagged resources"
    echo "  4. Verify tags in AWS Cost Explorer for cost tracking"
    echo ""
    echo -e "${YELLOW}⚠️  Important Notes:${NC}"
    echo "  • CloudTrail must be enabled for event capture"
    echo "  • Tags are applied immediately upon resource creation"
    echo "  • Monthly cost estimate: \$0.50-\$2.00"
    echo ""
    echo -e "${BLUE}🧹 Cleanup:${NC}"
    echo "  • Run: ./destroy.sh"
    echo "  • Or delete CloudFormation stack if used"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
}

# Main deployment function
main() {
    echo "🚀 Starting AWS Resource Tagging Automation Deployment..."
    echo ""
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_iam_resources
    create_lambda_function
    create_eventbridge_resources
    create_resource_group
    test_deployment
    save_deployment_info
    cleanup_temp_files
    display_final_instructions
    
    echo ""
    success "Deployment completed successfully!"
    echo "Deployment log saved to: ${DEPLOYMENT_LOG}"
}

# Check if running as source or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi