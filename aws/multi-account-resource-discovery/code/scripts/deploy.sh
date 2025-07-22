#!/bin/bash

# Multi-Account Resource Discovery Deployment Script
# Deploys AWS Resource Explorer, Config, EventBridge, and Lambda for automated governance

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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
AWS_REGION_DEFAULT="us-east-1"
TIMEOUT_SECONDS=300
DRY_RUN=false

# Help function
show_help() {
    cat << EOF
Multi-Account Resource Discovery Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -r, --region REGION     AWS region for deployment (default: $AWS_REGION_DEFAULT)
    -n, --dry-run           Show what would be deployed without making changes
    -t, --timeout SECONDS   Timeout for resource creation (default: $TIMEOUT_SECONDS)
    -v, --verbose           Enable verbose logging

EXAMPLES:
    $0                           # Deploy with default settings
    $0 -r us-west-2             # Deploy in specific region
    $0 --dry-run                # Preview deployment without changes
    $0 -r eu-west-1 --verbose   # Deploy with verbose logging

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - AWS Organizations enabled with management account access
    - Administrator privileges in AWS account
    - Multiple AWS accounts in organization (minimum 2)

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -t|--timeout)
            TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Set default region if not provided
AWS_REGION="${AWS_REGION:-$AWS_REGION_DEFAULT}"

log "Starting Multi-Account Resource Discovery deployment"
log "Region: $AWS_REGION"
log "Dry run: $DRY_RUN"

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | awk '{print $1}' | cut -d/ -f2 | cut -d. -f1)
    if [[ "$AWS_CLI_VERSION" -lt 2 ]]; then
        error "AWS CLI v2 is required. Current version: $(aws --version)"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check if running in management account
    if ! aws organizations describe-organization &> /dev/null; then
        error "This script must be run from the AWS Organizations management account."
    fi
    
    success "Prerequisites check passed"
}

# Generate unique identifiers
generate_identifiers() {
    log "Generating unique identifiers..."
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export ORG_ID=$(aws organizations describe-organization --query Organization.Id --output text)
    
    # Generate random suffix for unique naming
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Set project naming convention
    export PROJECT_NAME="multi-account-discovery-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="${PROJECT_NAME}-processor"
    export CONFIG_AGGREGATOR_NAME="${PROJECT_NAME}-aggregator"
    export CONFIG_BUCKET_NAME="aws-config-bucket-${AWS_ACCOUNT_ID}-${AWS_REGION}"
    
    log "Project name: $PROJECT_NAME"
    log "Organization ID: $ORG_ID"
    log "Account ID: $AWS_ACCOUNT_ID"
}

# Enable trusted access for AWS services
enable_trusted_access() {
    log "Enabling trusted access for AWS services..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would enable trusted access for Resource Explorer and Config"
        return 0
    fi
    
    # Enable trusted access for Resource Explorer
    aws organizations enable-aws-service-access \
        --service-principal resource-explorer-2.amazonaws.com \
        --region $AWS_REGION || warning "Resource Explorer trusted access may already be enabled"
    
    # Enable trusted access for Config
    aws organizations enable-aws-service-access \
        --service-principal config.amazonaws.com \
        --region $AWS_REGION || warning "Config trusted access may already be enabled"
    
    # Verify trusted access configuration
    aws organizations list-aws-service-access-for-organization \
        --query 'EnabledServicePrincipals[?ServicePrincipal==`resource-explorer-2.amazonaws.com` || ServicePrincipal==`config.amazonaws.com`]' \
        --region $AWS_REGION > /dev/null
    
    success "Trusted access enabled for AWS services"
}

# Create service-linked roles and S3 bucket
create_service_resources() {
    log "Creating service-linked roles and S3 bucket..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create service-linked roles and Config S3 bucket"
        return 0
    fi
    
    # Create service-linked role for Resource Explorer
    aws iam create-service-linked-role \
        --aws-service-name resource-explorer-2.amazonaws.com \
        2>/dev/null || log "Resource Explorer service-linked role already exists"
    
    # Create service-linked role for Config
    aws iam create-service-linked-role \
        --aws-service-name config.amazonaws.com \
        2>/dev/null || log "Config service-linked role already exists"
    
    # Create S3 bucket for Config data
    if aws s3api head-bucket --bucket "$CONFIG_BUCKET_NAME" 2>/dev/null; then
        log "Config bucket already exists: $CONFIG_BUCKET_NAME"
    else
        aws s3 mb "s3://${CONFIG_BUCKET_NAME}" --region "$AWS_REGION"
        success "Created Config S3 bucket: $CONFIG_BUCKET_NAME"
    fi
    
    # Create and apply bucket policy for Config service
    cat > "$PROJECT_DIR/config-bucket-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "config.amazonaws.com"
            },
            "Action": "s3:GetBucketAcl",
            "Resource": "arn:aws:s3:::${CONFIG_BUCKET_NAME}"
        },
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "config.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${CONFIG_BUCKET_NAME}/*",
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
        --bucket "$CONFIG_BUCKET_NAME" \
        --policy "file://$PROJECT_DIR/config-bucket-policy.json"
    
    success "Service-linked roles and Config bucket configured"
}

# Configure Resource Explorer
configure_resource_explorer() {
    log "Configuring AWS Resource Explorer..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would configure Resource Explorer aggregated index and view"
        return 0
    fi
    
    # Check if index already exists
    if aws resource-explorer-2 get-index --region "$AWS_REGION" 2>/dev/null | grep -q "ACTIVE\|CREATING"; then
        log "Resource Explorer index already exists in region $AWS_REGION"
    else
        # Create aggregated index in management account
        aws resource-explorer-2 create-index \
            --type AGGREGATOR \
            --region "$AWS_REGION"
        
        log "Waiting for Resource Explorer index creation..."
        sleep 30
        success "Resource Explorer index created"
    fi
    
    # Create default view for multi-account search
    VIEW_NAME="organization-view-${RANDOM_SUFFIX}"
    aws resource-explorer-2 create-view \
        --view-name "$VIEW_NAME" \
        --included-properties '{
            "IncludeCompliance": true,
            "IncludeResourceMetadata": true
        }' \
        --region "$AWS_REGION" 2>/dev/null || log "View may already exist"
    
    # Get and associate the default view
    VIEW_ARN=$(aws resource-explorer-2 list-views \
        --region "$AWS_REGION" \
        --query "Views[?ViewName=='$VIEW_NAME'].ViewArn | [0]" \
        --output text 2>/dev/null)
    
    if [[ "$VIEW_ARN" != "None" && "$VIEW_ARN" != "" ]]; then
        aws resource-explorer-2 associate-default-view \
            --view-arn "$VIEW_ARN" \
            --region "$AWS_REGION" 2>/dev/null || log "Default view already associated"
    fi
    
    success "Resource Explorer multi-account search configured"
}

# Set up Config aggregator
setup_config_aggregator() {
    log "Setting up AWS Config organization aggregator..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would setup Config recorder, delivery channel, and aggregator"
        return 0
    fi
    
    # Enable Config service
    aws configservice put-configuration-recorder \
        --configuration-recorder "name=${PROJECT_NAME}-recorder,roleARN=arn:aws:iam::${AWS_ACCOUNT_ID}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig,recordingGroup={
            \"allSupported\": true,
            \"includeGlobalResourceTypes\": true,
            \"resourceTypes\": []
        }" \
        --region "$AWS_REGION" 2>/dev/null || log "Configuration recorder may already exist"
    
    # Create delivery channel
    aws configservice put-delivery-channel \
        --delivery-channel "name=${PROJECT_NAME}-channel,s3BucketName=${CONFIG_BUCKET_NAME},configSnapshotDeliveryProperties={
            \"deliveryFrequency\": \"TwentyFour_Hours\"
        }" \
        --region "$AWS_REGION" 2>/dev/null || log "Delivery channel may already exist"
    
    # Start configuration recorder
    aws configservice start-configuration-recorder \
        --configuration-recorder-name "${PROJECT_NAME}-recorder" \
        --region "$AWS_REGION" 2>/dev/null || log "Configuration recorder may already be started"
    
    # Create organizational aggregator
    aws configservice put-configuration-aggregator \
        --configuration-aggregator-name "$CONFIG_AGGREGATOR_NAME" \
        --organization-aggregation-source "{
            \"RoleArn\": \"arn:aws:iam::${AWS_ACCOUNT_ID}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig\",
            \"AwsRegions\": [\"${AWS_REGION}\"],
            \"AllAwsRegions\": false
        }" \
        --region "$AWS_REGION"
    
    success "Config aggregator created for organizational compliance monitoring"
}

# Create Lambda function
create_lambda_function() {
    log "Creating Lambda function for automated processing..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Lambda function and IAM role"
        return 0
    fi
    
    # Create trust policy
    cat > "$PROJECT_DIR/trust-policy.json" << 'EOF'
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
        --role-name "${PROJECT_NAME}-lambda-role" \
        --assume-role-policy-document "file://$PROJECT_DIR/trust-policy.json" \
        --region "$AWS_REGION" 2>/dev/null || log "Lambda role may already exist"
    
    # Create custom policy
    cat > "$PROJECT_DIR/lambda-policy.json" << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "config:GetComplianceDetailsByConfigRule",
                "config:GetAggregateComplianceDetailsByConfigRule",
                "resource-explorer-2:Search",
                "resource-explorer-2:GetIndex",
                "sns:Publish",
                "organizations:ListAccounts"
            ],
            "Resource": "*"
        }
    ]
}
EOF

    aws iam put-role-policy \
        --role-name "${PROJECT_NAME}-lambda-role" \
        --policy-name "${PROJECT_NAME}-lambda-policy" \
        --policy-document "file://$PROJECT_DIR/lambda-policy.json" \
        --region "$AWS_REGION"
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "${PROJECT_NAME}-lambda-role" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        --region "$AWS_REGION"
    
    # Create Lambda function code
    cat > "$PROJECT_DIR/lambda_function.py" << 'EOF'
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

config_client = boto3.client('config')
resource_explorer_client = boto3.client('resource-explorer-2')
organizations_client = boto3.client('organizations')

def lambda_handler(event, context):
    """Main handler for multi-account resource discovery events"""
    logger.info(f"Processing event: {json.dumps(event, default=str)}")
    
    try:
        # Process Config compliance events
        if event.get('source') == 'aws.config':
            return process_config_event(event)
        
        # Process Resource Explorer events
        elif event.get('source') == 'aws.resource-explorer-2':
            return process_resource_explorer_event(event)
        
        # Handle scheduled discovery tasks
        elif event.get('source') == 'aws.events' and 'Scheduled Event' in event.get('detail-type', ''):
            return process_scheduled_discovery()
        
        else:
            logger.warning(f"Unknown event source: {event.get('source')}")
            
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        raise
    
    return {
        'statusCode': 200,
        'body': json.dumps('Event processed successfully')
    }

def process_config_event(event):
    """Process AWS Config compliance events with enhanced logging"""
    detail = event.get('detail', {})
    compliance_type = detail.get('newEvaluationResult', {}).get('complianceType')
    resource_type = detail.get('resourceType')
    resource_id = detail.get('resourceId')
    account_id = detail.get('awsAccountId')
    
    logger.info(f"Config event - Resource: {resource_type}, "
                f"ID: {resource_id}, Account: {account_id}, "
                f"Compliance: {compliance_type}")
    
    if compliance_type == 'NON_COMPLIANT':
        logger.warning(f"Non-compliant resource detected: {resource_type} in account {account_id}")
        handle_compliance_violation(detail)
    
    return {'statusCode': 200, 'compliance_processed': True}

def process_resource_explorer_event(event):
    """Process Resource Explorer events for resource discovery"""
    logger.info("Processing Resource Explorer event for cross-account discovery")
    
    try:
        response = resource_explorer_client.search(
            QueryString="service:ec2",
            MaxResults=10
        )
        
        resource_count = len(response.get('Resources', []))
        logger.info(f"Discovered {resource_count} EC2 resources across accounts")
        
    except Exception as e:
        logger.error(f"Error in resource discovery: {str(e)}")
    
    return {'statusCode': 200, 'discovery_processed': True}

def handle_compliance_violation(detail):
    """Handle compliance violations with detailed logging"""
    resource_type = detail.get('resourceType')
    resource_id = detail.get('resourceId')
    config_rule_name = detail.get('configRuleName')
    
    logger.warning(f"Compliance violation detected:")
    logger.warning(f"  Rule: {config_rule_name}")
    logger.warning(f"  Resource Type: {resource_type}")
    logger.warning(f"  Resource ID: {resource_id}")

def process_scheduled_discovery():
    """Process scheduled resource discovery tasks"""
    logger.info("Processing scheduled resource discovery scan")
    
    try:
        # Get organization accounts
        accounts = organizations_client.list_accounts()
        active_accounts = [acc for acc in accounts['Accounts'] if acc['Status'] == 'ACTIVE']
        
        logger.info(f"Monitoring {len(active_accounts)} active accounts")
        
        # Perform cross-account resource search
        search_results = resource_explorer_client.search(
            QueryString="*",
            MaxResults=100
        )
        
        logger.info(f"Total resources discovered: {len(search_results.get('Resources', []))}")
        
    except Exception as e:
        logger.error(f"Error in scheduled discovery: {str(e)}")
    
    return {'statusCode': 200, 'scheduled_discovery_complete': True}
EOF

    # Create deployment package
    cd "$PROJECT_DIR"
    zip lambda-deployment.zip lambda_function.py
    
    # Wait for IAM role propagation
    log "Waiting for IAM role propagation..."
    sleep 15
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-role" \
        --handler lambda_function.lambda_handler \
        --zip-file "fileb://lambda-deployment.zip" \
        --timeout 300 \
        --memory-size 512 \
        --description "Multi-account resource discovery and compliance processor" \
        --region "$AWS_REGION"
    
    success "Lambda function created for automated governance processing"
}

# Configure EventBridge rules
configure_eventbridge() {
    log "Configuring EventBridge rules for automation..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would configure EventBridge rules and targets"
        return 0
    fi
    
    # Create EventBridge rule for Config compliance events
    aws events put-rule \
        --name "${PROJECT_NAME}-config-rule" \
        --event-pattern '{
            "source": ["aws.config"],
            "detail-type": ["Config Rules Compliance Change"],
            "detail": {
                "newEvaluationResult": {
                    "complianceType": ["NON_COMPLIANT"]
                }
            }
        }' \
        --description "Route Config compliance violations to Lambda processor" \
        --state ENABLED \
        --region "$AWS_REGION"
    
    # Create scheduled rule for periodic discovery
    aws events put-rule \
        --name "${PROJECT_NAME}-discovery-schedule" \
        --schedule-expression "rate(1 day)" \
        --description "Scheduled resource discovery across accounts" \
        --state ENABLED \
        --region "$AWS_REGION"
    
    # Add Lambda targets to both rules
    aws events put-targets \
        --rule "${PROJECT_NAME}-config-rule" \
        --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}" \
        --region "$AWS_REGION"
    
    aws events put-targets \
        --rule "${PROJECT_NAME}-discovery-schedule" \
        --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}" \
        --region "$AWS_REGION"
    
    # Grant EventBridge permissions to invoke Lambda
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id config-events \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${PROJECT_NAME}-config-rule" \
        --region "$AWS_REGION"
    
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id discovery-schedule \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${PROJECT_NAME}-discovery-schedule" \
        --region "$AWS_REGION"
    
    success "EventBridge automation rules configured"
}

# Deploy Config rules
deploy_config_rules() {
    log "Deploying Config rules for compliance monitoring..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would deploy comprehensive Config compliance rules"
        return 0
    fi
    
    # Deploy comprehensive compliance rules
    RULES=(
        "${PROJECT_NAME}-s3-bucket-public-access-prohibited:S3_BUCKET_PUBLIC_ACCESS_PROHIBITED:Checks that S3 buckets do not allow public access"
        "${PROJECT_NAME}-ec2-security-group-attached-to-eni:EC2_SECURITY_GROUP_ATTACHED_TO_ENI:Checks that security groups are attached to EC2 instances"
        "${PROJECT_NAME}-root-access-key-check:ROOT_ACCESS_KEY_CHECK:Checks whether root access key exists"
        "${PROJECT_NAME}-encrypted-volumes:ENCRYPTED_VOLUMES:Checks whether EBS volumes are encrypted"
    )
    
    for rule_config in "${RULES[@]}"; do
        IFS=':' read -r rule_name source_identifier description <<< "$rule_config"
        
        aws configservice put-config-rule \
            --config-rule "{
                \"ConfigRuleName\": \"$rule_name\",
                \"Description\": \"$description\",
                \"Source\": {
                    \"Owner\": \"AWS\",
                    \"SourceIdentifier\": \"$source_identifier\"
                }
            }" \
            --region "$AWS_REGION" || warning "Failed to create rule: $rule_name"
    done
    
    # Wait for rules to be active
    log "Waiting for Config rules to become active..."
    sleep 15
    
    success "Comprehensive compliance monitoring rules deployed"
}

# Create member account template
create_member_template() {
    log "Creating member account deployment template..."
    
    cat > "$PROJECT_DIR/member-account-template.yaml" << EOF
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Resource Explorer and Config setup for member accounts'
Resources:
  ResourceExplorerIndex:
    Type: AWS::ResourceExplorer2::Index
    Properties:
      Type: LOCAL
      Tags:
        - Key: Purpose
          Value: MultiAccountDiscovery
        - Key: ManagedBy
          Value: ${PROJECT_NAME}
  
  ConfigServiceRole:
    Type: AWS::IAM::ServiceLinkedRole
    Properties:
      AWSServiceName: config.amazonaws.com
      Description: Service-linked role for AWS Config
EOF

    success "Member account template created: member-account-template.yaml"
    log "Deploy this template using AWS StackSets to member accounts"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would validate all deployed resources"
        return 0
    fi
    
    # Check Resource Explorer
    INDEX_STATE=$(aws resource-explorer-2 get-index \
        --region "$AWS_REGION" \
        --query 'State' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$INDEX_STATE" == "ACTIVE" ]]; then
        success "Resource Explorer index is active"
    else
        warning "Resource Explorer index state: $INDEX_STATE"
    fi
    
    # Check Config aggregator
    AGGREGATOR_STATE=$(aws configservice describe-configuration-aggregators \
        --configuration-aggregator-names "$CONFIG_AGGREGATOR_NAME" \
        --region "$AWS_REGION" \
        --query 'ConfigurationAggregators[0].ConfigurationAggregatorArn' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$AGGREGATOR_STATE" != "NOT_FOUND" && "$AGGREGATOR_STATE" != "None" ]]; then
        success "Config aggregator is configured"
    else
        warning "Config aggregator not found"
    fi
    
    # Check Lambda function
    LAMBDA_STATE=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --region "$AWS_REGION" \
        --query 'Configuration.State' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$LAMBDA_STATE" == "Active" ]]; then
        success "Lambda function is active"
    else
        warning "Lambda function state: $LAMBDA_STATE"
    fi
    
    # Check EventBridge rules
    CONFIG_RULE_STATE=$(aws events describe-rule \
        --name "${PROJECT_NAME}-config-rule" \
        --region "$AWS_REGION" \
        --query 'State' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$CONFIG_RULE_STATE" == "ENABLED" ]]; then
        success "EventBridge rules are enabled"
    else
        warning "EventBridge rule state: $CONFIG_RULE_STATE"
    fi
}

# Save deployment info
save_deployment_info() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    cat > "$PROJECT_DIR/deployment-info.json" << EOF
{
    "project_name": "$PROJECT_NAME",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "organization_id": "$ORG_ID",
    "lambda_function_name": "$LAMBDA_FUNCTION_NAME",
    "config_aggregator_name": "$CONFIG_AGGREGATOR_NAME",
    "config_bucket_name": "$CONFIG_BUCKET_NAME",
    "deployment_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "random_suffix": "$RANDOM_SUFFIX"
}
EOF
    
    log "Deployment information saved to deployment-info.json"
}

# Main execution
main() {
    log "=========================================="
    log "Multi-Account Resource Discovery Deployment"
    log "=========================================="
    
    check_prerequisites
    generate_identifiers
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "========== DRY RUN MODE =========="
        log "The following actions would be performed:"
        log "1. Enable trusted access for AWS services"
        log "2. Create service-linked roles and S3 bucket"
        log "3. Configure Resource Explorer with aggregated index"
        log "4. Set up Config organization aggregator"
        log "5. Create Lambda function for automated processing"
        log "6. Configure EventBridge rules for automation"
        log "7. Deploy Config rules for compliance monitoring"
        log "8. Create member account deployment template"
        log "9. Validate deployment"
        log "=================================="
    fi
    
    enable_trusted_access
    create_service_resources
    configure_resource_explorer
    setup_config_aggregator
    create_lambda_function
    configure_eventbridge
    deploy_config_rules
    create_member_template
    validate_deployment
    save_deployment_info
    
    log "=========================================="
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY RUN COMPLETED - No resources were created"
    else
        success "DEPLOYMENT COMPLETED SUCCESSFULLY!"
        log "Project: $PROJECT_NAME"
        log "Region: $AWS_REGION"
        log "Lambda Function: $LAMBDA_FUNCTION_NAME"
        log ""
        log "Next Steps:"
        log "1. Deploy member-account-template.yaml to member accounts using StackSets"
        log "2. Test resource discovery: aws resource-explorer-2 search --query-string 'service:ec2'"
        log "3. Monitor Lambda logs: aws logs tail /aws/lambda/$LAMBDA_FUNCTION_NAME --follow"
        log "4. Review compliance: aws configservice get-aggregate-compliance-summary --configuration-aggregator-name $CONFIG_AGGREGATOR_NAME"
    fi
    log "=========================================="
}

# Execute main function
main "$@"