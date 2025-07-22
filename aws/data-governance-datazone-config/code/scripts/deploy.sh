#!/bin/bash

# Data Governance Pipelines with DataZone
# Deployment Script
# Recipe ID: 4e7b2c1a

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
ERROR_LOG="${SCRIPT_DIR}/deployment_errors.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${ERROR_LOG}" | tee -a "${LOG_FILE}"
}

# Error handling
handle_error() {
    local line_number=$1
    local error_code=$2
    log_error "Error occurred in script at line ${line_number}: exit code ${error_code}"
    log_error "Check ${ERROR_LOG} for detailed error information"
    exit "${error_code}"
}

trap 'handle_error ${LINENO} $?' ERR

# Cleanup function
cleanup() {
    if [[ -f "governance_function.py" ]]; then
        rm -f governance_function.py
    fi
    if [[ -f "governance_function.zip" ]]; then
        rm -f governance_function.zip
    fi
}

trap cleanup EXIT

# Initialize logging
echo "Deployment started at $(date)" > "${LOG_FILE}"
echo "Error log for deployment at $(date)" > "${ERROR_LOG}"

log_info "Starting deployment of Data Governance Pipeline with Amazon DataZone and AWS Config"

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check jq for JSON parsing (nice to have)
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some output formatting may be limited."
    fi
    
    # Check required permissions by attempting to list services
    local services=("datazone" "config" "events" "lambda" "iam" "s3" "sns" "cloudwatch")
    for service in "${services[@]}"; do
        if ! aws ${service} help &> /dev/null; then
            log_error "Unable to access AWS ${service} service. Check permissions."
            exit 1
        fi
    done
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "No region configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export DATAZONE_DOMAIN_NAME="governance-domain-${RANDOM_SUFFIX}"
    export CONFIG_ROLE_NAME="DataGovernanceConfigRole-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="data-governance-processor-${RANDOM_SUFFIX}"
    export EVENT_RULE_NAME="data-governance-events-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="DataGovernanceLambdaRole-${RANDOM_SUFFIX}"
    export CONFIG_BUCKET="aws-config-bucket-${AWS_ACCOUNT_ID}-${RANDOM_SUFFIX}"
    
    # Create state file to track resources
    cat > "${SCRIPT_DIR}/deployment_state.json" << EOF
{
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "random_suffix": "${RANDOM_SUFFIX}",
    "datazone_domain_name": "${DATAZONE_DOMAIN_NAME}",
    "config_role_name": "${CONFIG_ROLE_NAME}",
    "lambda_function_name": "${LAMBDA_FUNCTION_NAME}",
    "event_rule_name": "${EVENT_RULE_NAME}",
    "lambda_role_name": "${LAMBDA_ROLE_NAME}",
    "config_bucket": "${CONFIG_BUCKET}",
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log_success "Environment setup completed"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log_info "Resource Suffix: ${RANDOM_SUFFIX}"
}

# Create IAM roles for Config
setup_config_role() {
    log_info "Creating IAM role for AWS Config..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${CONFIG_ROLE_NAME}" &> /dev/null; then
        log_warning "Config role ${CONFIG_ROLE_NAME} already exists, skipping creation"
        return 0
    fi
    
    # Create IAM role for AWS Config
    aws iam create-role \
        --role-name "${CONFIG_ROLE_NAME}" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {"Service": "config.amazonaws.com"},
                    "Action": "sts:AssumeRole"
                }
            ]
        }' >> "${LOG_FILE}" 2>> "${ERROR_LOG}"
    
    # Attach managed policy for Config service
    aws iam attach-role-policy \
        --role-name "${CONFIG_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole \
        >> "${LOG_FILE}" 2>> "${ERROR_LOG}"
    
    log_success "Config IAM role created: ${CONFIG_ROLE_NAME}"
}

# Create DataZone domain
create_datazone_domain() {
    log_info "Creating Amazon DataZone domain..."
    
    # Check if DataZone service role exists, create if needed
    if ! aws iam get-role --role-name AmazonDataZoneServiceRole &> /dev/null; then
        log_info "Creating DataZone service-linked role..."
        aws iam create-service-linked-role \
            --aws-service-name datazone.amazonaws.com \
            >> "${LOG_FILE}" 2>> "${ERROR_LOG}"
        sleep 10
    fi
    
    # Create DataZone domain
    DATAZONE_DOMAIN_ID=$(aws datazone create-domain \
        --name "${DATAZONE_DOMAIN_NAME}" \
        --description "Automated data governance domain" \
        --domain-execution-role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/AmazonDataZoneServiceRole" \
        --query 'id' --output text 2>> "${ERROR_LOG}")
    
    if [[ -z "${DATAZONE_DOMAIN_ID}" ]]; then
        log_error "Failed to create DataZone domain"
        exit 1
    fi
    
    # Update state file with domain ID
    jq --arg domain_id "${DATAZONE_DOMAIN_ID}" \
        '.datazone_domain_id = $domain_id' \
        "${SCRIPT_DIR}/deployment_state.json" > "${SCRIPT_DIR}/deployment_state.tmp" && \
        mv "${SCRIPT_DIR}/deployment_state.tmp" "${SCRIPT_DIR}/deployment_state.json"
    
    # Wait for domain creation to complete
    log_info "Waiting for DataZone domain creation..."
    local max_attempts=20
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        local status=$(aws datazone get-domain \
            --identifier "${DATAZONE_DOMAIN_ID}" \
            --query 'status' --output text 2>/dev/null || echo "CREATING")
        
        if [[ "${status}" == "AVAILABLE" ]]; then
            break
        elif [[ "${status}" == "FAILED" ]]; then
            log_error "DataZone domain creation failed"
            exit 1
        fi
        
        log_info "Domain status: ${status} (attempt ${attempt}/${max_attempts})"
        sleep 30
        ((attempt++))
    done
    
    if [[ ${attempt} -gt ${max_attempts} ]]; then
        log_error "Timeout waiting for DataZone domain creation"
        exit 1
    fi
    
    export DATAZONE_DOMAIN_ID
    log_success "DataZone domain created: ${DATAZONE_DOMAIN_ID}"
}

# Configure AWS Config
setup_aws_config() {
    log_info "Configuring AWS Config..."
    
    # Create S3 bucket for Config delivery channel
    if ! aws s3api head-bucket --bucket "${CONFIG_BUCKET}" &> /dev/null; then
        aws s3 mb "s3://${CONFIG_BUCKET}" --region "${AWS_REGION}" \
            >> "${LOG_FILE}" 2>> "${ERROR_LOG}"
        
        # Apply bucket policy for Config service access
        aws s3api put-bucket-policy \
            --bucket "${CONFIG_BUCKET}" \
            --policy '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Sid": "AWSConfigBucketPermissionsCheck",
                        "Effect": "Allow",
                        "Principal": {"Service": "config.amazonaws.com"},
                        "Action": "s3:GetBucketAcl",
                        "Resource": "arn:aws:s3:::'${CONFIG_BUCKET}'",
                        "Condition": {
                            "StringEquals": {
                                "AWS:SourceAccount": "'${AWS_ACCOUNT_ID}'"
                            }
                        }
                    },
                    {
                        "Sid": "AWSConfigBucketExistenceCheck",
                        "Effect": "Allow",
                        "Principal": {"Service": "config.amazonaws.com"},
                        "Action": "s3:ListBucket",
                        "Resource": "arn:aws:s3:::'${CONFIG_BUCKET}'",
                        "Condition": {
                            "StringEquals": {
                                "AWS:SourceAccount": "'${AWS_ACCOUNT_ID}'"
                            }
                        }
                    },
                    {
                        "Sid": "AWSConfigBucketDelivery",
                        "Effect": "Allow",
                        "Principal": {"Service": "config.amazonaws.com"},
                        "Action": "s3:PutObject",
                        "Resource": "arn:aws:s3:::'${CONFIG_BUCKET}'/AWSLogs/'${AWS_ACCOUNT_ID}'/Config/*",
                        "Condition": {
                            "StringEquals": {
                                "s3:x-amz-acl": "bucket-owner-full-control",
                                "AWS:SourceAccount": "'${AWS_ACCOUNT_ID}'"
                            }
                        }
                    }
                ]
            }' >> "${LOG_FILE}" 2>> "${ERROR_LOG}"
    else
        log_warning "Config S3 bucket ${CONFIG_BUCKET} already exists"
    fi
    
    # Enable AWS Config configuration recorder
    if ! aws configservice describe-configuration-recorders \
        --configuration-recorder-names default &> /dev/null; then
        
        aws configservice put-configuration-recorder \
            --configuration-recorder '{
                "name": "default",
                "roleARN": "arn:aws:iam::'${AWS_ACCOUNT_ID}':role/'${CONFIG_ROLE_NAME}'",
                "recordingGroup": {
                    "allSupported": true,
                    "includeGlobalResourceTypes": true,
                    "recordingModeOverrides": []
                }
            }' >> "${LOG_FILE}" 2>> "${ERROR_LOG}"
    else
        log_warning "Config recorder already exists"
    fi
    
    # Create delivery channel for Config data
    if ! aws configservice describe-delivery-channels \
        --delivery-channel-names default &> /dev/null; then
        
        aws configservice put-delivery-channel \
            --delivery-channel '{
                "name": "default",
                "s3BucketName": "'${CONFIG_BUCKET}'"
            }' >> "${LOG_FILE}" 2>> "${ERROR_LOG}"
    else
        log_warning "Config delivery channel already exists"
    fi
    
    # Start configuration recorder
    aws configservice start-configuration-recorder \
        --configuration-recorder-name default \
        >> "${LOG_FILE}" 2>> "${ERROR_LOG}" || true
    
    log_success "AWS Config enabled with S3 delivery to: ${CONFIG_BUCKET}"
}

# Deploy Config rules
deploy_config_rules() {
    log_info "Deploying data governance Config rules..."
    
    local rules=(
        "s3-bucket-server-side-encryption-enabled:S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED:AWS::S3::Bucket"
        "rds-storage-encrypted:RDS_STORAGE_ENCRYPTED:AWS::RDS::DBInstance"
        "s3-bucket-public-read-prohibited:S3_BUCKET_PUBLIC_READ_PROHIBITED:AWS::S3::Bucket"
    )
    
    for rule_info in "${rules[@]}"; do
        IFS=':' read -r rule_name source_identifier resource_type <<< "${rule_info}"
        
        if aws configservice describe-config-rules \
            --config-rule-names "${rule_name}" &> /dev/null; then
            log_warning "Config rule ${rule_name} already exists, skipping"
            continue
        fi
        
        aws configservice put-config-rule \
            --config-rule '{
                "ConfigRuleName": "'${rule_name}'",
                "Description": "Data governance rule for '${rule_name}'",
                "Source": {
                    "Owner": "AWS",
                    "SourceIdentifier": "'${source_identifier}'"
                },
                "Scope": {
                    "ComplianceResourceTypes": ["'${resource_type}'"]
                }
            }' >> "${LOG_FILE}" 2>> "${ERROR_LOG}"
        
        log_success "Created Config rule: ${rule_name}"
    done
    
    sleep 10
}

# Create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function for governance automation..."
    
    # Check if Lambda role already exists
    if ! aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &> /dev/null; then
        # Create IAM role for Lambda function
        aws iam create-role \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {"Service": "lambda.amazonaws.com"},
                        "Action": "sts:AssumeRole"
                    }
                ]
            }' >> "${LOG_FILE}" 2>> "${ERROR_LOG}"
        
        # Attach basic execution policy for CloudWatch logs
        aws iam attach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
            >> "${LOG_FILE}" 2>> "${ERROR_LOG}"
        
        # Create custom policy for governance services access
        aws iam put-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-name DataGovernancePolicy \
            --policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Action": [
                            "datazone:Get*",
                            "datazone:List*",
                            "datazone:Search*",
                            "datazone:UpdateAsset",
                            "config:GetComplianceDetailsByConfigRule",
                            "config:GetResourceConfigHistory",
                            "config:GetComplianceDetailsByResource",
                            "sns:Publish",
                            "logs:CreateLogGroup",
                            "logs:CreateLogStream",
                            "logs:PutLogEvents"
                        ],
                        "Resource": "*"
                    }
                ]
            }' >> "${LOG_FILE}" 2>> "${ERROR_LOG}"
        
        # Wait for IAM role to propagate
        sleep 10
    else
        log_warning "Lambda role ${LAMBDA_ROLE_NAME} already exists"
    fi
    
    # Check if Lambda function already exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} already exists, skipping creation"
        return 0
    fi
    
    # Create Lambda function code
    cat > governance_function.py << 'EOF'
import json
import boto3
import logging
from datetime import datetime
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Process governance events and update DataZone metadata"""
    
    try:
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # Parse EventBridge event structure
        detail = event.get('detail', {})
        config_item = detail.get('configurationItem', {})
        compliance_result = detail.get('newEvaluationResult', {})
        compliance_type = compliance_result.get('complianceType', 'UNKNOWN')
        
        resource_type = config_item.get('resourceType', '')
        resource_id = config_item.get('resourceId', '')
        resource_arn = config_item.get('arn', '')
        
        logger.info(f"Processing governance event for {resource_type}: {resource_id}")
        logger.info(f"Compliance status: {compliance_type}")
        
        # Initialize AWS clients with error handling
        try:
            datazone_client = boto3.client('datazone')
            config_client = boto3.client('config')
            sns_client = boto3.client('sns')
        except Exception as e:
            logger.error(f"Failed to initialize AWS clients: {str(e)}")
            raise
        
        # Create governance metadata
        governance_metadata = {
            'resourceId': resource_id,
            'resourceType': resource_type,
            'resourceArn': resource_arn,
            'complianceStatus': compliance_type,
            'evaluationTimestamp': compliance_result.get('resultRecordedTime', ''),
            'configRuleName': compliance_result.get('configRuleName', ''),
            'awsAccountId': detail.get('awsAccountId', ''),
            'awsRegion': detail.get('awsRegion', ''),
            'processedAt': datetime.utcnow().isoformat()
        }
        
        # Log governance event for audit trail
        logger.info(f"Governance metadata: {json.dumps(governance_metadata, default=str)}")
        
        # Process compliance violations
        if compliance_type == 'NON_COMPLIANT':
            logger.warning(f"Compliance violation detected for {resource_type}: {resource_id}")
            
            violation_summary = {
                'violationType': 'COMPLIANCE_VIOLATION',
                'severity': 'HIGH' if 'encryption' in compliance_result.get('configRuleName', '') else 'MEDIUM',
                'resource': resource_id,
                'rule': compliance_result.get('configRuleName', ''),
                'requiresAttention': True
            }
            
            logger.info(f"Violation summary: {json.dumps(violation_summary)}")
        
        # Prepare response
        response_body = {
            'statusCode': 200,
            'message': 'Governance event processed successfully',
            'metadata': governance_metadata,
            'processedResources': 1
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(response_body, default=str)
        }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"AWS service error ({error_code}): {error_message}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'AWS service error: {error_code}',
                'message': error_message
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error processing governance event: {str(e)}", exc_info=True)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal processing error',
                'message': str(e)
            })
        }
EOF
    
    # Create deployment package
    zip governance_function.zip governance_function.py >> "${LOG_FILE}" 2>> "${ERROR_LOG}"
    
    # Deploy Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.11 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" \
        --handler governance_function.lambda_handler \
        --zip-file fileb://governance_function.zip \
        --timeout 300 \
        --memory-size 512 \
        --description "Data governance automation processor" \
        --environment Variables='{
            "LOG_LEVEL":"INFO",
            "AWS_ACCOUNT_ID":"'${AWS_ACCOUNT_ID}'",
            "AWS_REGION":"'${AWS_REGION}'"
        }' >> "${LOG_FILE}" 2>> "${ERROR_LOG}"
    
    log_success "Lambda function deployed: ${LAMBDA_FUNCTION_NAME}"
}

# Configure EventBridge
setup_eventbridge() {
    log_info "Configuring EventBridge for automated event processing..."
    
    # Check if EventBridge rule already exists
    if aws events describe-rule --name "${EVENT_RULE_NAME}" &> /dev/null; then
        log_warning "EventBridge rule ${EVENT_RULE_NAME} already exists, skipping creation"
    else
        # Create EventBridge rule for Config compliance changes
        aws events put-rule \
            --name "${EVENT_RULE_NAME}" \
            --description "Route data governance events to Lambda processor" \
            --event-pattern '{
                "source": ["aws.config"],
                "detail-type": ["Config Rules Compliance Change"],
                "detail": {
                    "newEvaluationResult": {
                        "complianceType": ["NON_COMPLIANT", "COMPLIANT"]
                    },
                    "configRuleName": [
                        "s3-bucket-server-side-encryption-enabled",
                        "rds-storage-encrypted",
                        "s3-bucket-public-read-prohibited"
                    ]
                }
            }' \
            --state ENABLED >> "${LOG_FILE}" 2>> "${ERROR_LOG}"
        
        log_success "EventBridge rule created: ${EVENT_RULE_NAME}"
    fi
    
    # Add Lambda function as target
    aws events put-targets \
        --rule "${EVENT_RULE_NAME}" \
        --targets '[{
            "Id": "1",
            "Arn": "arn:aws:lambda:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':function:'${LAMBDA_FUNCTION_NAME}'"
        }]' >> "${LOG_FILE}" 2>> "${ERROR_LOG}"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id "governance-eventbridge-invoke" \
        --action "lambda:InvokeFunction" \
        --principal "events.amazonaws.com" \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENT_RULE_NAME}" \
        >> "${LOG_FILE}" 2>> "${ERROR_LOG}" || true
    
    log_success "EventBridge configured for governance automation"
}

# Create DataZone project
create_datazone_project() {
    log_info "Creating DataZone project and environment..."
    
    # Wait for DataZone domain to be fully available
    local max_attempts=20
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        local status=$(aws datazone get-domain \
            --identifier "${DATAZONE_DOMAIN_ID}" \
            --query 'status' --output text 2>/dev/null || echo "CREATING")
        
        if [[ "${status}" == "AVAILABLE" ]]; then
            break
        fi
        
        log_info "Waiting for DataZone domain to be available... (attempt ${attempt}/${max_attempts})"
        sleep 30
        ((attempt++))
    done
    
    # Create DataZone project for governance workflows
    PROJECT_ID=$(aws datazone create-project \
        --domain-identifier "${DATAZONE_DOMAIN_ID}" \
        --name "governance-project-${RANDOM_SUFFIX}" \
        --description "Automated data governance and compliance project" \
        --query 'id' --output text 2>> "${ERROR_LOG}")
    
    if [[ -n "${PROJECT_ID}" ]]; then
        # Update state file with project ID
        jq --arg project_id "${PROJECT_ID}" \
            '.datazone_project_id = $project_id' \
            "${SCRIPT_DIR}/deployment_state.json" > "${SCRIPT_DIR}/deployment_state.tmp" && \
            mv "${SCRIPT_DIR}/deployment_state.tmp" "${SCRIPT_DIR}/deployment_state.json"
        
        export DATAZONE_PROJECT_ID="${PROJECT_ID}"
        log_success "DataZone project created: ${PROJECT_ID}"
    else
        log_warning "DataZone project creation may have failed, check logs"
    fi
}

# Setup monitoring
setup_monitoring() {
    log_info "Setting up governance monitoring and alerting..."
    
    # Create SNS topic for governance alerts
    GOVERNANCE_TOPIC_ARN=$(aws sns create-topic \
        --name "data-governance-alerts-${RANDOM_SUFFIX}" \
        --query 'TopicArn' --output text 2>> "${ERROR_LOG}")
    
    if [[ -n "${GOVERNANCE_TOPIC_ARN}" ]]; then
        # Update state file with SNS topic ARN
        jq --arg topic_arn "${GOVERNANCE_TOPIC_ARN}" \
            '.governance_topic_arn = $topic_arn' \
            "${SCRIPT_DIR}/deployment_state.json" > "${SCRIPT_DIR}/deployment_state.tmp" && \
            mv "${SCRIPT_DIR}/deployment_state.tmp" "${SCRIPT_DIR}/deployment_state.json"
        
        # Create CloudWatch alarms
        local alarms=(
            "DataGovernanceErrors-${RANDOM_SUFFIX}:Errors:GreaterThanOrEqualToThreshold:1:Monitor Lambda function errors"
            "DataGovernanceDuration-${RANDOM_SUFFIX}:Duration:GreaterThanThreshold:240000:Monitor Lambda execution duration"
        )
        
        for alarm_info in "${alarms[@]}"; do
            IFS=':' read -r alarm_name metric_name operator threshold description <<< "${alarm_info}"
            
            aws cloudwatch put-metric-alarm \
                --alarm-name "${alarm_name}" \
                --alarm-description "${description}" \
                --metric-name "${metric_name}" \
                --namespace "AWS/Lambda" \
                --statistic "$(if [[ ${metric_name} == "Errors" ]]; then echo "Sum"; else echo "Average"; fi)" \
                --period 300 \
                --threshold "${threshold}" \
                --comparison-operator "${operator}" \
                --evaluation-periods "$(if [[ ${metric_name} == "Errors" ]]; then echo "1"; else echo "2"; fi)" \
                --alarm-actions "${GOVERNANCE_TOPIC_ARN}" \
                --dimensions Name=FunctionName,Value="${LAMBDA_FUNCTION_NAME}" \
                --treat-missing-data "notBreaching" \
                >> "${LOG_FILE}" 2>> "${ERROR_LOG}"
            
            log_success "Created CloudWatch alarm: ${alarm_name}"
        done
        
        log_success "Monitoring configured with SNS topic: ${GOVERNANCE_TOPIC_ARN}"
    else
        log_warning "Failed to create SNS topic for monitoring"
    fi
}

# Validation
validate_deployment() {
    log_info "Validating deployment..."
    
    local validation_errors=0
    
    # Check DataZone domain
    if aws datazone get-domain --identifier "${DATAZONE_DOMAIN_ID}" \
        --query 'status' --output text 2>/dev/null | grep -q "AVAILABLE"; then
        log_success "DataZone domain is available"
    else
        log_error "DataZone domain validation failed"
        ((validation_errors++))
    fi
    
    # Check Config recorder
    if aws configservice describe-configuration-recorders \
        --configuration-recorder-names default \
        --query 'ConfigurationRecorders[0].recordingGroup' &> /dev/null; then
        log_success "Config recorder is active"
    else
        log_error "Config recorder validation failed"
        ((validation_errors++))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" \
        --query 'Configuration.State' --output text 2>/dev/null | grep -q "Active"; then
        log_success "Lambda function is active"
    else
        log_error "Lambda function validation failed"
        ((validation_errors++))
    fi
    
    # Check EventBridge rule
    if aws events describe-rule --name "${EVENT_RULE_NAME}" \
        --query 'State' --output text 2>/dev/null | grep -q "ENABLED"; then
        log_success "EventBridge rule is enabled"
    else
        log_error "EventBridge rule validation failed"
        ((validation_errors++))
    fi
    
    if [[ ${validation_errors} -eq 0 ]]; then
        log_success "All components validated successfully"
        return 0
    else
        log_error "Validation failed with ${validation_errors} errors"
        return 1
    fi
}

# Print deployment summary
print_summary() {
    log_info "Deployment Summary"
    echo "================================"
    echo "AWS Region: ${AWS_REGION}"
    echo "AWS Account ID: ${AWS_ACCOUNT_ID}"
    echo "DataZone Domain: ${DATAZONE_DOMAIN_NAME} (${DATAZONE_DOMAIN_ID:-'Not created'})"
    echo "Config Bucket: ${CONFIG_BUCKET}"
    echo "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "EventBridge Rule: ${EVENT_RULE_NAME}"
    echo "State File: ${SCRIPT_DIR}/deployment_state.json"
    echo "Logs: ${LOG_FILE}"
    echo "================================"
    
    if [[ -f "${SCRIPT_DIR}/deployment_state.json" ]]; then
        log_info "Deployment state saved to: ${SCRIPT_DIR}/deployment_state.json"
    fi
}

# Main execution
main() {
    log_info "Starting deployment process..."
    
    check_prerequisites
    setup_environment
    setup_config_role
    create_datazone_domain
    setup_aws_config
    deploy_config_rules
    create_lambda_function
    setup_eventbridge
    create_datazone_project
    setup_monitoring
    
    if validate_deployment; then
        print_summary
        log_success "Deployment completed successfully!"
        log_info "You can now access the DataZone portal in the AWS Console to manage your data governance."
        log_info "Monitor compliance through AWS Config console and CloudWatch for governance events."
    else
        log_error "Deployment completed with validation errors. Check logs for details."
        exit 1
    fi
}

# Run main function
main "$@"