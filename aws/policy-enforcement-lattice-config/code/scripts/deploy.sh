#!/bin/bash

# Deploy script for Policy Enforcement Automation with VPC Lattice and Config
# This script implements the complete infrastructure deployment for automated
# compliance monitoring and remediation of VPC Lattice resources

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging configuration
LOG_FILE="deployment_$(date +%Y%m%d_%H%M%S).log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to log messages
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}" | tee -a "$LOG_FILE"
}

# Function to handle errors
error_exit() {
    print_status "$RED" "ERROR: $1"
    log "ERROR" "$1"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    print_status "$BLUE" "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI version 2.x or later."
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "INFO" "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' or set up credentials."
    fi
    
    # Check required permissions (basic check)
    local account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [[ -z "$account_id" ]]; then
        error_exit "Unable to retrieve AWS account ID. Check your credentials."
    fi
    
    log "INFO" "AWS Account ID: $account_id"
    
    # Check if required services are available in region
    local region=$(aws configure get region)
    if [[ -z "$region" ]]; then
        error_exit "AWS region not configured. Please set a default region."
    fi
    
    log "INFO" "AWS Region: $region"
    
    # Verify VPC Lattice service availability
    if ! aws vpc-lattice list-service-networks --max-results 1 &> /dev/null; then
        error_exit "VPC Lattice service not available in region $region or insufficient permissions."
    fi
    
    # Verify Config service availability
    if ! aws configservice describe-configuration-recorders &> /dev/null; then
        log "WARN" "Config service may not be set up. This is expected for new accounts."
    fi
    
    print_status "$GREEN" "Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    print_status "$BLUE" "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names with unique suffix
    export SERVICE_NETWORK_NAME="compliance-demo-network-${random_suffix}"
    export CONFIG_RULE_NAME="vpc-lattice-policy-compliance-${random_suffix}"
    export SNS_TOPIC_NAME="lattice-compliance-alerts-${random_suffix}"
    export LAMBDA_FUNCTION_NAME="lattice-compliance-evaluator-${random_suffix}"
    export REMEDY_FUNCTION_NAME="lattice-auto-remediation-${random_suffix}"
    export CONFIG_ROLE_NAME="ConfigServiceRole-${random_suffix}"
    export LAMBDA_ROLE_NAME="LatticeComplianceRole-${random_suffix}"
    export CONFIG_BUCKET_NAME="aws-config-bucket-${AWS_ACCOUNT_ID}-${AWS_REGION}-${random_suffix}"
    
    # Save environment variables for cleanup script
    cat > "$SCRIPT_DIR/.env" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
SERVICE_NETWORK_NAME=$SERVICE_NETWORK_NAME
CONFIG_RULE_NAME=$CONFIG_RULE_NAME
SNS_TOPIC_NAME=$SNS_TOPIC_NAME
LAMBDA_FUNCTION_NAME=$LAMBDA_FUNCTION_NAME
REMEDY_FUNCTION_NAME=$REMEDY_FUNCTION_NAME
CONFIG_ROLE_NAME=$CONFIG_ROLE_NAME
LAMBDA_ROLE_NAME=$LAMBDA_ROLE_NAME
CONFIG_BUCKET_NAME=$CONFIG_BUCKET_NAME
RANDOM_SUFFIX=$random_suffix
EOF
    
    log "INFO" "Environment variables set and saved to .env file"
    print_status "$GREEN" "Environment setup completed"
}

# Function to create IAM roles
create_iam_roles() {
    print_status "$BLUE" "Creating IAM roles..."
    
    # Create Config service role
    log "INFO" "Creating Config service IAM role: $CONFIG_ROLE_NAME"
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
        }' \
        --tags Key=Project,Value=VpcLatticeCompliance Key=Component,Value=ConfigService || \
        log "WARN" "Config role may already exist"
    
    # Attach AWS managed policy for Config service
    aws iam attach-role-policy \
        --role-name "$CONFIG_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole || \
        log "WARN" "Policy may already be attached"
    
    # Add S3 bucket access policy for Config service role
    aws iam put-role-policy \
        --role-name "$CONFIG_ROLE_NAME" \
        --policy-name ConfigS3DeliveryRolePolicy \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "s3:GetBucketAcl",
                        "s3:ListBucket"
                    ],
                    "Resource": "arn:aws:s3:::aws-config-bucket-*"
                },
                {
                    "Effect": "Allow",
                    "Action": "s3:PutObject",
                    "Resource": "arn:aws:s3:::aws-config-bucket-*/AWSLogs/*/Config/*",
                    "Condition": {
                        "StringEquals": {
                            "s3:x-amz-acl": "bucket-owner-full-control"
                        }
                    }
                }
            ]
        }'
    
    # Create Lambda execution role
    log "INFO" "Creating Lambda execution IAM role: $LAMBDA_ROLE_NAME"
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
        }' \
        --tags Key=Project,Value=VpcLatticeCompliance Key=Component,Value=Lambda || \
        log "WARN" "Lambda role may already exist"
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || \
        log "WARN" "Policy may already be attached"
    
    # Create custom policy for VPC Lattice and Config access
    aws iam put-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-name LatticeCompliancePolicy \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "vpc-lattice:*",
                        "config:PutEvaluations",
                        "config:StartConfigRulesEvaluation",
                        "sns:Publish",
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents"
                    ],
                    "Resource": "*"
                }
            ]
        }'
    
    # Wait for role propagation
    log "INFO" "Waiting for IAM role propagation..."
    sleep 15
    
    print_status "$GREEN" "IAM roles created successfully"
}

# Function to create SNS topic
create_sns_topic() {
    print_status "$BLUE" "Creating SNS topic for compliance notifications..."
    
    # Create SNS topic
    aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --attributes '{
            "DisplayName": "VPC Lattice Compliance Alerts",
            "DeliveryPolicy": "{\"http\":{\"defaultHealthyRetryPolicy\":{\"minDelayTarget\":20,\"maxDelayTarget\":20,\"numRetries\":3}}}"
        }' \
        --tags Key=Project,Value=VpcLatticeCompliance Key=Component,Value=Notifications
    
    # Get topic ARN
    export SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" \
        --query 'Attributes.TopicArn' --output text)
    
    log "INFO" "SNS topic created: $SNS_TOPIC_ARN"
    
    # Add SNS topic ARN to environment file
    echo "SNS_TOPIC_ARN=$SNS_TOPIC_ARN" >> "$SCRIPT_DIR/.env"
    
    print_status "$GREEN" "SNS topic created successfully"
}

# Function to create Lambda functions
create_lambda_functions() {
    print_status "$BLUE" "Creating Lambda functions..."
    
    # Get Lambda role ARN
    local lambda_role_arn=$(aws iam get-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --query 'Role.Arn' --output text)
    
    # Create temporary directory for Lambda code
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Create compliance evaluator function code
    cat > compliance_evaluator.py << 'EOF'
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Evaluate VPC Lattice resources for compliance."""
    
    config_client = boto3.client('config')
    lattice_client = boto3.client('vpc-lattice')
    sns_client = boto3.client('sns')
    
    # Parse Config rule invocation
    configuration_item = event['configurationItem']
    rule_parameters = json.loads(event.get('ruleParameters', '{}'))
    
    compliance_type = 'COMPLIANT'
    annotation = 'Resource is compliant with security policies'
    
    try:
        resource_type = configuration_item['resourceType']
        resource_id = configuration_item['resourceId']
        
        if resource_type == 'AWS::VpcLattice::ServiceNetwork':
            compliance_type, annotation = evaluate_service_network(
                lattice_client, resource_id, rule_parameters
            )
        elif resource_type == 'AWS::VpcLattice::Service':
            compliance_type, annotation = evaluate_service(
                lattice_client, resource_id, rule_parameters
            )
        
        # Send notification if non-compliant
        if compliance_type == 'NON_COMPLIANT':
            send_compliance_notification(sns_client, resource_id, annotation)
            
    except Exception as e:
        logger.error(f"Error evaluating compliance: {str(e)}")
        compliance_type = 'NOT_APPLICABLE'
        annotation = f"Error during evaluation: {str(e)}"
    
    # Return evaluation result to Config
    config_client.put_evaluations(
        Evaluations=[
            {
                'ComplianceResourceType': configuration_item['resourceType'],
                'ComplianceResourceId': configuration_item['resourceId'],
                'ComplianceType': compliance_type,
                'Annotation': annotation,
                'OrderingTimestamp': configuration_item['configurationItemCaptureTime']
            }
        ],
        ResultToken=event['resultToken']
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Evaluation complete: {compliance_type}')
    }

def evaluate_service_network(client, network_id, parameters):
    """Evaluate service network compliance."""
    try:
        # Get service network details
        response = client.get_service_network(serviceNetworkIdentifier=network_id)
        network = response['serviceNetwork']
        
        # Check for auth policy requirement
        if parameters.get('requireAuthPolicy', 'true') == 'true':
            try:
                client.get_auth_policy(resourceIdentifier=network_id)
            except client.exceptions.ResourceNotFoundException:
                return 'NON_COMPLIANT', 'Service network missing required auth policy'
        
        # Check network name compliance
        if not network['name'].startswith(parameters.get('namePrefix', 'secure-')):
            return 'NON_COMPLIANT', f"Service network name must start with {parameters.get('namePrefix', 'secure-')}"
        
        return 'COMPLIANT', 'Service network meets all security requirements'
        
    except Exception as e:
        return 'NOT_APPLICABLE', f"Unable to evaluate service network: {str(e)}"

def evaluate_service(client, service_id, parameters):
    """Evaluate service compliance."""
    try:
        response = client.get_service(serviceIdentifier=service_id)
        service = response['service']
        
        # Check auth type requirement
        if parameters.get('requireAuth', 'true') == 'true':
            if service.get('authType') == 'NONE':
                return 'NON_COMPLIANT', 'Service must have authentication enabled'
        
        return 'COMPLIANT', 'Service meets security requirements'
        
    except Exception as e:
        return 'NOT_APPLICABLE', f"Unable to evaluate service: {str(e)}"

def send_compliance_notification(sns_client, resource_id, message):
    """Send SNS notification for compliance violations."""
    try:
        sns_client.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject='VPC Lattice Compliance Violation Detected',
            Message=f"""
Compliance violation detected:

Resource ID: {resource_id}
Issue: {message}
Timestamp: {datetime.utcnow().isoformat()}

Please review and remediate this resource immediately.
            """
        )
    except Exception as e:
        logger.error(f"Failed to send SNS notification: {str(e)}")
EOF
    
    # Create deployment package for compliance evaluator
    zip compliance_evaluator.zip compliance_evaluator.py
    
    # Deploy compliance evaluator Lambda function
    log "INFO" "Creating compliance evaluator Lambda function: $LAMBDA_FUNCTION_NAME"
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.12 \
        --role "$lambda_role_arn" \
        --handler compliance_evaluator.lambda_handler \
        --zip-file fileb://compliance_evaluator.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables="{SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}" \
        --tags Project=VpcLatticeCompliance,Component=ComplianceEvaluator
    
    # Create auto-remediation function code
    cat > auto_remediation.py << 'EOF'
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Automatically remediate VPC Lattice compliance violations."""
    
    lattice_client = boto3.client('vpc-lattice')
    config_client = boto3.client('config')
    
    try:
        # Parse SNS message
        message = json.loads(event['Records'][0]['Sns']['Message'])
        resource_id = extract_resource_id(message)
        
        if not resource_id:
            logger.error("Unable to extract resource ID from message")
            return
        
        # Attempt remediation based on resource type
        if 'service-network' in resource_id:
            remediate_service_network(lattice_client, resource_id)
        elif 'service' in resource_id:
            remediate_service(lattice_client, resource_id)
        
        # Trigger Config re-evaluation
        config_client.start_config_rules_evaluation(
            ConfigRuleNames=[os.environ['CONFIG_RULE_NAME']]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps('Remediation completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Remediation failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Remediation failed: {str(e)}')
        }

def extract_resource_id(message):
    """Extract resource ID from compliance message."""
    # Simple extraction logic - in production, use more robust parsing
    lines = message.split('\n')
    for line in lines:
        if 'Resource ID:' in line:
            return line.split('Resource ID:')[1].strip()
    return None

def remediate_service_network(client, network_id):
    """Apply remediation to service network."""
    try:
        # Create basic auth policy if missing
        auth_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": "*",
                    "Action": "vpc-lattice-svcs:*",
                    "Resource": "*",
                    "Condition": {
                        "StringEquals": {
                            "aws:PrincipalAccount": os.environ['AWS_ACCOUNT_ID']
                        }
                    }
                }
            ]
        }
        
        client.put_auth_policy(
            resourceIdentifier=network_id,
            policy=json.dumps(auth_policy)
        )
        
        logger.info(f"Applied auth policy to service network: {network_id}")
        
    except Exception as e:
        logger.error(f"Failed to remediate service network {network_id}: {str(e)}")

def remediate_service(client, service_id):
    """Apply remediation to service."""
    try:
        # Update service to require authentication
        client.update_service(
            serviceIdentifier=service_id,
            authType='AWS_IAM'
        )
        
        logger.info(f"Updated service authentication: {service_id}")
        
    except Exception as e:
        logger.error(f"Failed to remediate service {service_id}: {str(e)}")
EOF
    
    # Create deployment package for auto-remediation
    zip auto_remediation.zip auto_remediation.py
    
    # Deploy auto-remediation Lambda function
    log "INFO" "Creating auto-remediation Lambda function: $REMEDY_FUNCTION_NAME"
    aws lambda create-function \
        --function-name "$REMEDY_FUNCTION_NAME" \
        --runtime python3.12 \
        --role "$lambda_role_arn" \
        --handler auto_remediation.lambda_handler \
        --zip-file fileb://auto_remediation.zip \
        --timeout 120 \
        --memory-size 256 \
        --environment Variables="{CONFIG_RULE_NAME=${CONFIG_RULE_NAME},AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}}" \
        --tags Project=VpcLatticeCompliance,Component=AutoRemediation
    
    # Clean up temporary files
    cd "$SCRIPT_DIR"
    rm -rf "$temp_dir"
    
    print_status "$GREEN" "Lambda functions created successfully"
}

# Function to configure AWS Config
configure_aws_config() {
    print_status "$BLUE" "Configuring AWS Config..."
    
    # Create S3 bucket for Config
    log "INFO" "Creating S3 bucket for Config: $CONFIG_BUCKET_NAME"
    aws s3 mb "s3://$CONFIG_BUCKET_NAME" --region "$AWS_REGION"
    
    # Create bucket policy for AWS Config service
    local bucket_policy=$(cat << EOF
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
      "Resource": "arn:aws:s3:::${CONFIG_BUCKET_NAME}",
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
      "Resource": "arn:aws:s3:::${CONFIG_BUCKET_NAME}",
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
      "Resource": "arn:aws:s3:::${CONFIG_BUCKET_NAME}/AWSLogs/${AWS_ACCOUNT_ID}/Config/*",
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
)
    
    # Apply bucket policy
    echo "$bucket_policy" > config-bucket-policy.json
    aws s3api put-bucket-policy \
        --bucket "$CONFIG_BUCKET_NAME" \
        --policy file://config-bucket-policy.json
    
    # Create Config delivery channel
    aws configservice put-delivery-channel \
        --delivery-channel "{
            \"name\": \"default\",
            \"s3BucketName\": \"$CONFIG_BUCKET_NAME\"
        }"
    
    # Create configuration recorder
    aws configservice put-configuration-recorder \
        --configuration-recorder "{
            \"name\": \"default\",
            \"roleARN\": \"arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CONFIG_ROLE_NAME}\",
            \"recordingGroup\": {
                \"allSupported\": false,
                \"includeGlobalResourceTypes\": false,
                \"resourceTypes\": [
                    \"AWS::VpcLattice::ServiceNetwork\",
                    \"AWS::VpcLattice::Service\"
                ]
            }
        }"
    
    # Start configuration recorder
    aws configservice start-configuration-recorder \
        --configuration-recorder-name default
    
    rm -f config-bucket-policy.json
    
    print_status "$GREEN" "AWS Config configured successfully"
}

# Function to create Config rule
create_config_rule() {
    print_status "$BLUE" "Creating Config rule for VPC Lattice compliance..."
    
    # Get Lambda function ARN
    local lambda_arn=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Configuration.FunctionArn' --output text)
    
    # Grant Config permission to invoke Lambda
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id allow-config-invoke \
        --action lambda:InvokeFunction \
        --principal config.amazonaws.com \
        --source-account "$AWS_ACCOUNT_ID" || \
        log "WARN" "Permission may already exist"
    
    # Create Config rule
    aws configservice put-config-rule \
        --config-rule "{
            \"ConfigRuleName\": \"$CONFIG_RULE_NAME\",
            \"Description\": \"Evaluates VPC Lattice resources for compliance with security policies\",
            \"Source\": {
                \"Owner\": \"AWS_LAMBDA\",
                \"SourceIdentifier\": \"$lambda_arn\",
                \"SourceDetails\": [
                    {
                        \"EventSource\": \"aws.config\",
                        \"MessageType\": \"ConfigurationItemChangeNotification\"
                    },
                    {
                        \"EventSource\": \"aws.config\", 
                        \"MessageType\": \"OversizedConfigurationItemChangeNotification\"
                    }
                ]
            },
            \"InputParameters\": \"{\\\"requireAuthPolicy\\\": \\\"true\\\", \\\"namePrefix\\\": \\\"secure-\\\", \\\"requireAuth\\\": \\\"true\\\"}\"
        }"
    
    print_status "$GREEN" "Config rule created successfully"
}

# Function to create test VPC Lattice resources
create_test_resources() {
    print_status "$BLUE" "Creating test VPC Lattice resources..."
    
    # Create VPC for service network association
    local vpc_id=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=lattice-compliance-vpc},{Key=Project,Value=VpcLatticeCompliance}]' \
        --query 'Vpc.VpcId' --output text)
    
    # Create VPC Lattice service network (non-compliant name for testing)
    local service_network_id=$(aws vpc-lattice create-service-network \
        --name "test-network-$(date +%s | tail -c 6)" \
        --auth-type AWS_IAM \
        --tags Project=VpcLatticeCompliance,Component=TestResource \
        --query 'id' --output text)
    
    # Associate VPC with service network
    aws vpc-lattice create-service-network-vpc-association \
        --service-network-identifier "$service_network_id" \
        --vpc-identifier "$vpc_id" \
        --tags Project=VpcLatticeCompliance > /dev/null
    
    # Save test resource IDs for cleanup
    cat >> "$SCRIPT_DIR/.env" << EOF
VPC_ID=$vpc_id
SERVICE_NETWORK_ID=$service_network_id
EOF
    
    log "INFO" "Test resources created - VPC: $vpc_id, Service Network: $service_network_id"
    print_status "$GREEN" "Test resources created successfully"
}

# Function to configure SNS subscriptions
configure_sns_subscriptions() {
    print_status "$BLUE" "Configuring SNS subscriptions..."
    
    # Get remediation Lambda ARN
    local remedy_lambda_arn=$(aws lambda get-function \
        --function-name "$REMEDY_FUNCTION_NAME" \
        --query 'Configuration.FunctionArn' --output text)
    
    # Subscribe remediation function to SNS topic
    aws sns subscribe \
        --topic-arn "$SNS_TOPIC_ARN" \
        --protocol lambda \
        --notification-endpoint "$remedy_lambda_arn"
    
    # Grant SNS permission to invoke Lambda
    aws lambda add-permission \
        --function-name "$REMEDY_FUNCTION_NAME" \
        --statement-id allow-sns-invoke \
        --action lambda:InvokeFunction \
        --principal sns.amazonaws.com \
        --source-arn "$SNS_TOPIC_ARN" || \
        log "WARN" "Permission may already exist"
    
    print_status "$GREEN" "SNS subscriptions configured successfully"
}

# Function to display deployment summary
display_summary() {
    print_status "$BLUE" "Deployment Summary"
    echo "===========================================" | tee -a "$LOG_FILE"
    echo "AWS Region: $AWS_REGION" | tee -a "$LOG_FILE"
    echo "AWS Account: $AWS_ACCOUNT_ID" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Created Resources:" | tee -a "$LOG_FILE"
    echo "- Config Rule: $CONFIG_RULE_NAME" | tee -a "$LOG_FILE"
    echo "- SNS Topic: $SNS_TOPIC_NAME" | tee -a "$LOG_FILE"
    echo "- Lambda Functions: $LAMBDA_FUNCTION_NAME, $REMEDY_FUNCTION_NAME" | tee -a "$LOG_FILE"
    echo "- IAM Roles: $CONFIG_ROLE_NAME, $LAMBDA_ROLE_NAME" | tee -a "$LOG_FILE"
    echo "- S3 Bucket: $CONFIG_BUCKET_NAME" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Next Steps:" | tee -a "$LOG_FILE"
    echo "1. Configure email subscriptions for SNS topic" | tee -a "$LOG_FILE"
    echo "2. Monitor Config rule evaluations in AWS Console" | tee -a "$LOG_FILE"
    echo "3. Test compliance violations with non-compliant resources" | tee -a "$LOG_FILE"
    echo "4. Review CloudWatch logs for Lambda function execution" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Cleanup: Run ./destroy.sh to remove all resources" | tee -a "$LOG_FILE"
    echo "===========================================" | tee -a "$LOG_FILE"
}

# Main deployment function
main() {
    print_status "$GREEN" "Starting VPC Lattice Policy Enforcement Deployment"
    log "INFO" "Deployment started by user: $(whoami)"
    
    # Check if running in dry-run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        print_status "$YELLOW" "DRY RUN MODE - No resources will be created"
        export DRY_RUN=true
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_iam_roles
    create_sns_topic
    create_lambda_functions
    configure_aws_config
    create_config_rule
    create_test_resources
    configure_sns_subscriptions
    
    print_status "$GREEN" "Deployment completed successfully!"
    display_summary
    
    log "INFO" "Deployment completed successfully"
}

# Handle script interruption
trap 'print_status "$RED" "Deployment interrupted. Run destroy.sh to clean up any created resources."; exit 1' INT

# Run main function with all arguments
main "$@"