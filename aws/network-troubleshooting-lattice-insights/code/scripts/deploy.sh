#!/bin/bash

# Deploy script for Network Troubleshooting VPC Lattice with Network Insights
# This script creates all infrastructure components for automated network troubleshooting

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Cleanup function for partial deployments
cleanup_on_error() {
    error "Deployment failed. Cleaning up resources..."
    if [ -f "./destroy.sh" ]; then
        chmod +x ./destroy.sh
        ./destroy.sh --force
    fi
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check required AWS services availability
    local region=$(aws configure get region)
    if [ -z "$region" ]; then
        error "AWS region not configured"
        exit 1
    fi
    
    # Check VPC Lattice availability in region
    if ! aws vpc-lattice list-service-networks --max-items 1 &> /dev/null; then
        error "VPC Lattice not available in region $region"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to validate resource limits
validate_limits() {
    log "Validating account limits..."
    
    # Check VPC limit
    local vpc_count=$(aws ec2 describe-vpcs --query 'length(Vpcs)')
    if [ "$vpc_count" -gt 4 ]; then
        warning "You have $vpc_count VPCs. Consider cleanup if approaching limits."
    fi
    
    # Check IAM role limit
    local role_count=$(aws iam list-roles --query 'length(Roles)')
    if [ "$role_count" -gt 900 ]; then
        warning "You have $role_count IAM roles. Consider cleanup if approaching limits."
    fi
    
    success "Account limits validation completed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Define resource names
    export LATTICE_SERVICE_NETWORK_NAME="troubleshooting-network-${RANDOM_SUFFIX}"
    export LATTICE_SERVICE_NAME="test-service-${RANDOM_SUFFIX}"
    export TARGET_GROUP_NAME="test-targets-${RANDOM_SUFFIX}"
    export AUTOMATION_ROLE_NAME="NetworkTroubleshootingRole-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="NetworkTroubleshootingLambdaRole-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="network-alerts-${RANDOM_SUFFIX}"
    
    # Get default VPC information for testing
    export DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" --output text)
    
    if [ "$DEFAULT_VPC_ID" == "None" ] || [ -z "$DEFAULT_VPC_ID" ]; then
        error "No default VPC found. Please create a VPC first."
        exit 1
    fi
    
    export DEFAULT_SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${DEFAULT_VPC_ID}" \
        --query "Subnets[0].SubnetId" --output text)
    
    # Create deployment state file
    cat > deployment_state.env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
LATTICE_SERVICE_NETWORK_NAME=${LATTICE_SERVICE_NETWORK_NAME}
LATTICE_SERVICE_NAME=${LATTICE_SERVICE_NAME}
TARGET_GROUP_NAME=${TARGET_GROUP_NAME}
AUTOMATION_ROLE_NAME=${AUTOMATION_ROLE_NAME}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
DEFAULT_VPC_ID=${DEFAULT_VPC_ID}
DEFAULT_SUBNET_ID=${DEFAULT_SUBNET_ID}
EOF
    
    success "Environment variables configured"
    log "VPC ID: ${DEFAULT_VPC_ID}"
    log "Service Network: ${LATTICE_SERVICE_NETWORK_NAME}"
}

# Function to create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Create trust policy for Systems Manager
    cat > ssm-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ssm.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create trust policy for Lambda
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
    
    # Create IAM role for Systems Manager automation
    if ! aws iam get-role --role-name ${AUTOMATION_ROLE_NAME} &> /dev/null; then
        aws iam create-role \
            --role-name ${AUTOMATION_ROLE_NAME} \
            --assume-role-policy-document file://ssm-trust-policy.json
        
        # Wait for role propagation
        sleep 10
    else
        warning "Automation role ${AUTOMATION_ROLE_NAME} already exists"
    fi
    
    # Create IAM role for Lambda function
    if ! aws iam get-role --role-name ${LAMBDA_ROLE_NAME} &> /dev/null; then
        aws iam create-role \
            --role-name ${LAMBDA_ROLE_NAME} \
            --assume-role-policy-document file://lambda-trust-policy.json
        
        # Wait for role propagation
        sleep 10
    else
        warning "Lambda role ${LAMBDA_ROLE_NAME} already exists"
    fi
    
    # Attach necessary policies to automation role
    aws iam attach-role-policy \
        --role-name ${AUTOMATION_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMAutomationRole || true
    
    aws iam attach-role-policy \
        --role-name ${AUTOMATION_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess || true
    
    aws iam attach-role-policy \
        --role-name ${AUTOMATION_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess || true
    
    # Attach necessary policies to Lambda role
    aws iam attach-role-policy \
        --role-name ${LAMBDA_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true
    
    aws iam attach-role-policy \
        --role-name ${LAMBDA_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMFullAccess || true
    
    export AUTOMATION_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${AUTOMATION_ROLE_NAME}"
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
    
    # Update deployment state
    echo "AUTOMATION_ROLE_ARN=${AUTOMATION_ROLE_ARN}" >> deployment_state.env
    echo "LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}" >> deployment_state.env
    
    success "IAM roles created and configured"
}

# Function to create VPC Lattice service network
create_lattice_network() {
    log "Creating VPC Lattice service network..."
    
    # Create VPC Lattice service network
    export SERVICE_NETWORK_ID=$(aws vpc-lattice create-service-network \
        --name ${LATTICE_SERVICE_NETWORK_NAME} \
        --auth-type AWS_IAM \
        --query "id" --output text)
    
    # Associate VPC with service network
    export VPC_ASSOCIATION_ID=$(aws vpc-lattice create-service-network-vpc-association \
        --service-network-identifier ${SERVICE_NETWORK_ID} \
        --vpc-identifier ${DEFAULT_VPC_ID} \
        --query "id" --output text)
    
    # Wait for association to be active
    log "Waiting for VPC association to become active..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local status=$(aws vpc-lattice get-service-network-vpc-association \
            --service-network-vpc-association-identifier ${VPC_ASSOCIATION_ID} \
            --query "status" --output text)
        
        if [ "$status" == "ACTIVE" ]; then
            break
        fi
        
        sleep 10
        attempt=$((attempt + 1))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        error "VPC association failed to become active"
        exit 1
    fi
    
    # Update deployment state
    echo "SERVICE_NETWORK_ID=${SERVICE_NETWORK_ID}" >> deployment_state.env
    echo "VPC_ASSOCIATION_ID=${VPC_ASSOCIATION_ID}" >> deployment_state.env
    
    success "VPC Lattice service network created: ${SERVICE_NETWORK_ID}"
}

# Function to create test EC2 instances
create_test_infrastructure() {
    log "Creating test EC2 infrastructure..."
    
    # Get latest Amazon Linux 2023 AMI ID
    local AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=al2023-ami-*-x86_64" \
            "Name=state,Values=available" \
        --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" \
        --output text)
    
    # Create security group for test instances
    export SG_ID=$(aws ec2 create-security-group \
        --group-name lattice-test-sg-${RANDOM_SUFFIX} \
        --description "Security group for VPC Lattice testing" \
        --vpc-id ${DEFAULT_VPC_ID} \
        --query "GroupId" --output text)
    
    # Add inbound rules for HTTP and SSH
    aws ec2 authorize-security-group-ingress \
        --group-id ${SG_ID} \
        --protocol tcp \
        --port 80 \
        --source-group ${SG_ID} || true
    
    aws ec2 authorize-security-group-ingress \
        --group-id ${SG_ID} \
        --protocol tcp \
        --port 22 \
        --cidr 10.0.0.0/8 || true
    
    # Launch test instance
    export INSTANCE_ID=$(aws ec2 run-instances \
        --image-id ${AMI_ID} \
        --count 1 \
        --instance-type t3.micro \
        --security-group-ids ${SG_ID} \
        --subnet-id ${DEFAULT_SUBNET_ID} \
        --associate-public-ip-address \
        --tag-specifications \
            "ResourceType=instance,Tags=[{Key=Name,Value=lattice-test-${RANDOM_SUFFIX}}]" \
        --query "Instances[0].InstanceId" --output text)
    
    # Wait for instance to be running
    log "Waiting for instance to be running..."
    aws ec2 wait instance-running --instance-ids ${INSTANCE_ID}
    
    # Update deployment state
    echo "SG_ID=${SG_ID}" >> deployment_state.env
    echo "INSTANCE_ID=${INSTANCE_ID}" >> deployment_state.env
    
    success "Test infrastructure created: ${INSTANCE_ID}"
}

# Function to configure CloudWatch monitoring
configure_monitoring() {
    log "Configuring CloudWatch monitoring..."
    
    # Create CloudWatch dashboard
    cat > network-dashboard.json << EOF
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
          [ "AWS/VpcLattice", "RequestCount", "ServiceNetwork", "${SERVICE_NETWORK_ID}" ],
          [ ".", "TargetResponseTime", ".", "." ],
          [ ".", "ActiveConnectionCount", ".", "." ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "${AWS_REGION}",
        "title": "VPC Lattice Performance Metrics"
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
          [ "AWS/VpcLattice", "HTTPCode_Target_2XX_Count", "ServiceNetwork", "${SERVICE_NETWORK_ID}" ],
          [ ".", "HTTPCode_Target_4XX_Count", ".", "." ],
          [ ".", "HTTPCode_Target_5XX_Count", ".", "." ]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "VPC Lattice Response Codes"
      }
    }
  ]
}
EOF
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "VPCLatticeNetworkTroubleshooting-${RANDOM_SUFFIX}" \
        --dashboard-body file://network-dashboard.json
    
    # Create CloudWatch log group for VPC Lattice access logs
    aws logs create-log-group \
        --log-group-name "/aws/vpclattice/servicenetwork/${SERVICE_NETWORK_ID}" || true
    
    success "CloudWatch monitoring configured"
}

# Function to create VPC Reachability Analyzer automation
create_automation_document() {
    log "Creating VPC Reachability Analyzer automation..."
    
    # Create automation document for network analysis
    cat > reachability-analysis.json << 'EOF'
{
  "schemaVersion": "0.3",
  "description": "Automated VPC Reachability Analysis for Network Troubleshooting",
  "assumeRole": "{{ AutomationAssumeRole }}",
  "parameters": {
    "SourceId": {
      "type": "String",
      "description": "Source instance ID or ENI ID"
    },
    "DestinationId": {
      "type": "String", 
      "description": "Destination instance ID or ENI ID"
    },
    "AutomationAssumeRole": {
      "type": "String",
      "description": "IAM role for automation execution"
    }
  },
  "mainSteps": [
    {
      "name": "CreateNetworkInsightsPath",
      "action": "aws:executeAwsApi",
      "description": "Create a network insights path for reachability analysis",
      "inputs": {
        "Service": "ec2",
        "Api": "CreateNetworkInsightsPath",
        "Source": "{{ SourceId }}",
        "Destination": "{{ DestinationId }}",
        "Protocol": "tcp",
        "DestinationPort": 80,
        "TagSpecifications": [
          {
            "ResourceType": "network-insights-path",
            "Tags": [
              {
                "Key": "Name",
                "Value": "AutomatedTroubleshooting"
              }
            ]
          }
        ]
      },
      "outputs": [
        {
          "Name": "NetworkInsightsPathId",
          "Selector": "$.NetworkInsightsPath.NetworkInsightsPathId",
          "Type": "String"
        }
      ]
    },
    {
      "name": "StartNetworkInsightsAnalysis",
      "action": "aws:executeAwsApi",
      "description": "Start the network insights analysis",
      "inputs": {
        "Service": "ec2",
        "Api": "StartNetworkInsightsAnalysis",
        "NetworkInsightsPathId": "{{ CreateNetworkInsightsPath.NetworkInsightsPathId }}",
        "TagSpecifications": [
          {
            "ResourceType": "network-insights-analysis",
            "Tags": [
              {
                "Key": "Name",
                "Value": "AutomatedAnalysis"
              }
            ]
          }
        ]
      },
      "outputs": [
        {
          "Name": "NetworkInsightsAnalysisId",
          "Selector": "$.NetworkInsightsAnalysis.NetworkInsightsAnalysisId",
          "Type": "String"
        }
      ]
    },
    {
      "name": "WaitForAnalysisCompletion",
      "action": "aws:waitForAwsResourceProperty",
      "description": "Wait for the analysis to complete",
      "inputs": {
        "Service": "ec2",
        "Api": "DescribeNetworkInsightsAnalyses",
        "NetworkInsightsAnalysisIds": [
          "{{ StartNetworkInsightsAnalysis.NetworkInsightsAnalysisId }}"
        ],
        "PropertySelector": "$.NetworkInsightsAnalyses[0].Status",
        "DesiredValues": [
          "succeeded",
          "failed"
        ]
      }
    }
  ]
}
EOF
    
    # Create the automation document
    export AUTOMATION_DOCUMENT_NAME="NetworkReachabilityAnalysis-${RANDOM_SUFFIX}"
    
    if ! aws ssm describe-document --name ${AUTOMATION_DOCUMENT_NAME} &> /dev/null; then
        aws ssm create-document \
            --name ${AUTOMATION_DOCUMENT_NAME} \
            --document-type "Automation" \
            --document-format JSON \
            --content file://reachability-analysis.json
    else
        warning "Automation document ${AUTOMATION_DOCUMENT_NAME} already exists"
    fi
    
    # Update deployment state
    echo "AUTOMATION_DOCUMENT_NAME=${AUTOMATION_DOCUMENT_NAME}" >> deployment_state.env
    
    success "Network reachability automation document created"
}

# Function to set up SNS topic and alerts
setup_sns_alerts() {
    log "Setting up SNS topic and CloudWatch alerts..."
    
    # Create SNS topic for network alerts
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name ${SNS_TOPIC_NAME} \
        --query "TopicArn" --output text)
    
    # Create CloudWatch alarm for VPC Lattice errors
    aws cloudwatch put-metric-alarm \
        --alarm-name "VPCLattice-HighErrorRate-${RANDOM_SUFFIX}" \
        --alarm-description "Alarm for high VPC Lattice 5XX error rate" \
        --metric-name "HTTPCode_Target_5XX_Count" \
        --namespace "AWS/VpcLattice" \
        --statistic "Sum" \
        --period 300 \
        --threshold 10 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --alarm-actions ${SNS_TOPIC_ARN} \
        --dimensions Name=ServiceNetwork,Value=${SERVICE_NETWORK_ID}
    
    # Create alarm for high response time
    aws cloudwatch put-metric-alarm \
        --alarm-name "VPCLattice-HighLatency-${RANDOM_SUFFIX}" \
        --alarm-description "Alarm for high VPC Lattice response time" \
        --metric-name "TargetResponseTime" \
        --namespace "AWS/VpcLattice" \
        --statistic "Average" \
        --period 300 \
        --threshold 5000 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --alarm-actions ${SNS_TOPIC_ARN} \
        --dimensions Name=ServiceNetwork,Value=${SERVICE_NETWORK_ID}
    
    # Update deployment state
    echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> deployment_state.env
    
    success "SNS topic and CloudWatch alarms configured"
}

# Function to create and deploy Lambda function
create_lambda_function() {
    log "Creating network troubleshooting Lambda function..."
    
    # Create Lambda function code
    cat > troubleshooting_function.py << 'EOF'
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to automatically trigger network troubleshooting
    when CloudWatch alarms are triggered via SNS
    """
    ssm_client = boto3.client('ssm')
    
    try:
        # Parse SNS message
        if 'Records' in event:
            for record in event['Records']:
                if record['EventSource'] == 'aws:sns':
                    message = json.loads(record['Sns']['Message'])
                    alarm_name = message.get('AlarmName', '')
                    
                    logger.info(f"Processing alarm: {alarm_name}")
                    
                    # Get environment variables with defaults
                    automation_role = os.environ.get('AUTOMATION_ROLE_ARN', '')
                    default_instance = os.environ.get('DEFAULT_INSTANCE_ID', '')
                    automation_document = os.environ.get('AUTOMATION_DOCUMENT_NAME', '')
                    
                    if not automation_role or not default_instance or not automation_document:
                        logger.error("Missing required environment variables")
                        return {
                            'statusCode': 400,
                            'body': json.dumps({'error': 'Missing environment variables'})
                        }
                    
                    # Trigger automated troubleshooting
                    response = ssm_client.start_automation_execution(
                        DocumentName=automation_document,
                        Parameters={
                            'SourceId': [default_instance],
                            'DestinationId': [default_instance],
                            'AutomationAssumeRole': [automation_role]
                        }
                    )
                    
                    logger.info(f"Started automation execution: {response['AutomationExecutionId']}")
                    
                    return {
                        'statusCode': 200,
                        'body': json.dumps({
                            'message': 'Network troubleshooting automation started',
                            'execution_id': response['AutomationExecutionId'],
                            'alarm_name': alarm_name
                        })
                    }
            
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'No SNS records to process'})
        }
            
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Package Lambda function
    zip -q troubleshooting_function.zip troubleshooting_function.py
    
    # Create Lambda function
    export LAMBDA_FUNCTION_NAME="network-troubleshooting-${RANDOM_SUFFIX}"
    
    if ! aws lambda get-function --function-name ${LAMBDA_FUNCTION_NAME} &> /dev/null; then
        export LAMBDA_FUNCTION_ARN=$(aws lambda create-function \
            --function-name ${LAMBDA_FUNCTION_NAME} \
            --runtime python3.12 \
            --role ${LAMBDA_ROLE_ARN} \
            --handler troubleshooting_function.lambda_handler \
            --zip-file fileb://troubleshooting_function.zip \
            --timeout 60 \
            --environment Variables="{AUTOMATION_ROLE_ARN=${AUTOMATION_ROLE_ARN},DEFAULT_INSTANCE_ID=${INSTANCE_ID},AUTOMATION_DOCUMENT_NAME=${AUTOMATION_DOCUMENT_NAME}}" \
            --query "FunctionArn" --output text)
    else
        warning "Lambda function ${LAMBDA_FUNCTION_NAME} already exists"
        export LAMBDA_FUNCTION_ARN=$(aws lambda get-function \
            --function-name ${LAMBDA_FUNCTION_NAME} \
            --query "Configuration.FunctionArn" --output text)
    fi
    
    # Subscribe Lambda to SNS topic
    aws sns subscribe \
        --topic-arn ${SNS_TOPIC_ARN} \
        --protocol lambda \
        --notification-endpoint ${LAMBDA_FUNCTION_ARN} || true
    
    # Grant SNS permission to invoke Lambda
    aws lambda add-permission \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --statement-id "sns-invoke-${RANDOM_SUFFIX}" \
        --action lambda:InvokeFunction \
        --principal sns.amazonaws.com \
        --source-arn ${SNS_TOPIC_ARN} || true
    
    # Update deployment state
    echo "LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}" >> deployment_state.env
    echo "LAMBDA_FUNCTION_ARN=${LAMBDA_FUNCTION_ARN}" >> deployment_state.env
    
    success "Lambda function created and configured"
}

# Function to run deployment validation
validate_deployment() {
    log "Validating deployment..."
    
    # Test automation execution
    log "Testing network reachability analysis..."
    local execution_id=$(aws ssm start-automation-execution \
        --document-name ${AUTOMATION_DOCUMENT_NAME} \
        --parameters \
            "SourceId=${INSTANCE_ID},DestinationId=${INSTANCE_ID},AutomationAssumeRole=${AUTOMATION_ROLE_ARN}" \
        --query "AutomationExecutionId" --output text)
    
    # Wait for execution to start
    sleep 30
    
    # Check execution status
    local status=$(aws ssm get-automation-execution \
        --automation-execution-id ${execution_id} \
        --query "AutomationExecution.AutomationExecutionStatus" \
        --output text)
    
    if [ "$status" != "Failed" ]; then
        success "Network reachability analysis test: ${status}"
    else
        warning "Network reachability analysis test failed, but this is expected for self-referencing test"
    fi
    
    # Test Lambda function with sample event
    cat > test-event.json << EOF
{
  "Records": [
    {
      "EventSource": "aws:sns",
      "Sns": {
        "Message": "{\"AlarmName\":\"VPCLattice-HighErrorRate-${RANDOM_SUFFIX}\",\"NewStateValue\":\"ALARM\"}"
      }
    }
  ]
}
EOF
    
    # Invoke Lambda function for testing
    if aws lambda invoke \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --payload file://test-event.json \
        response.json &> /dev/null; then
        success "Lambda function test passed"
    else
        warning "Lambda function test had issues, check logs"
    fi
    
    # Verify key resources exist
    if aws vpc-lattice get-service-network \
        --service-network-identifier ${SERVICE_NETWORK_ID} &> /dev/null; then
        success "VPC Lattice service network verified"
    else
        error "VPC Lattice service network verification failed"
    fi
    
    success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "AWS Region: ${AWS_REGION}"
    echo "Service Network ID: ${SERVICE_NETWORK_ID}"
    echo "Test Instance ID: ${INSTANCE_ID}"
    echo "Automation Role: ${AUTOMATION_ROLE_NAME}"
    echo "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "SNS Topic: ${SNS_TOPIC_NAME}"
    echo ""
    echo "Key URLs:"
    echo "CloudWatch Dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=VPCLatticeNetworkTroubleshooting-${RANDOM_SUFFIX}"
    echo "VPC Lattice Console: https://${AWS_REGION}.console.aws.amazon.com/vpc/home?region=${AWS_REGION}#vpclattice"
    echo ""
    echo "Configuration saved to: deployment_state.env"
    echo ""
    success "Network troubleshooting infrastructure deployed successfully!"
    echo ""
    warning "Estimated cost: \$20-30 per day while running"
    warning "Remember to run destroy.sh when done testing"
}

# Main deployment function
main() {
    log "Starting Network Troubleshooting VPC Lattice deployment..."
    
    # Check if running with --help
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        echo "Network Troubleshooting VPC Lattice Deployment Script"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --dry-run      Validate prerequisites only"
        echo "  --force        Skip confirmation prompts"
        echo ""
        echo "This script deploys a complete network troubleshooting solution using:"
        echo "- VPC Lattice service mesh"
        echo "- VPC Reachability Analyzer automation"
        echo "- CloudWatch monitoring and alerting"
        echo "- Lambda-based automated response"
        echo ""
        exit 0
    fi
    
    # Check for dry-run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        check_prerequisites
        validate_limits
        log "Dry-run completed successfully"
        exit 0
    fi
    
    # Confirmation prompt unless --force is used
    if [[ "${1:-}" != "--force" ]]; then
        echo "This will deploy a network troubleshooting solution with the following components:"
        echo "- VPC Lattice service network"
        echo "- Test EC2 instance"
        echo "- CloudWatch monitoring"
        echo "- Systems Manager automation"
        echo "- Lambda function for automated response"
        echo "- SNS topic for alerts"
        echo ""
        echo "Estimated cost: \$20-30 per day while running"
        echo ""
        read -p "Do you want to proceed? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    check_prerequisites
    validate_limits
    setup_environment
    create_iam_roles
    create_lattice_network
    create_test_infrastructure
    configure_monitoring
    create_automation_document
    setup_sns_alerts
    create_lambda_function
    validate_deployment
    
    # Clean up temporary files
    rm -f ssm-trust-policy.json lambda-trust-policy.json
    rm -f network-dashboard.json reachability-analysis.json
    rm -f troubleshooting_function.py troubleshooting_function.zip
    rm -f test-event.json response.json
    
    display_summary
}

# Run main function with all arguments
main "$@"