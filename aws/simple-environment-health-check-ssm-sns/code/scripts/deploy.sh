#!/bin/bash

# Deploy script for Simple Environment Health Check with Systems Manager and SNS
# This script deploys automated environment health monitoring using AWS Systems Manager
# Compliance, SNS notifications, Lambda functions, and EventBridge scheduling.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_NAME="environment-health-check"
STACK_NAME=""
RANDOM_SUFFIX=""
NOTIFICATION_EMAIL=""
AWS_REGION=""
AWS_ACCOUNT_ID=""
TOPIC_ARN=""
INSTANCE_ID=""

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}

# Function to print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Simple Environment Health Check infrastructure.

OPTIONS:
    -e, --email EMAIL       Email address for notifications (required)
    -r, --region REGION     AWS region (defaults to current CLI region)
    -n, --name NAME         Deployment name prefix (default: environment-health-check)
    --dry-run              Show what would be deployed without making changes
    -h, --help             Show this help message

EXAMPLES:
    $0 --email ops-team@company.com
    $0 --email admin@company.com --region us-west-2
    $0 --email alerts@company.com --name prod-health-check
    DRY_RUN=true $0 --email test@company.com

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--email)
                NOTIFICATION_EMAIL="$2"
                shift 2
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -n|--name)
                DEPLOYMENT_NAME="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if zip command is available
    if ! command -v zip &> /dev/null; then
        log_error "zip command is not available. Please install zip utility."
        exit 1
    fi
    
    # Validate email parameter
    if [[ -z "${NOTIFICATION_EMAIL}" ]]; then
        log_error "Email address is required. Use -e or --email option."
        usage
        exit 1
    fi
    
    # Email format validation
    if [[ ! "${NOTIFICATION_EMAIL}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log_error "Invalid email format: ${NOTIFICATION_EMAIL}"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region
    if [[ -z "${AWS_REGION}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "${AWS_REGION}" ]]; then
            log_error "AWS region not set. Use --region option or configure AWS CLI."
            exit 1
        fi
    fi
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
        --query Account --output text)
    
    # Generate random suffix for resource names
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Set stack name
    STACK_NAME="${DEPLOYMENT_NAME}-${RANDOM_SUFFIX}"
    
    log_info "AWS Region: ${AWS_REGION}"
    log_info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log_info "Deployment Name: ${DEPLOYMENT_NAME}"
    log_info "Random Suffix: ${RANDOM_SUFFIX}"
    log_info "Notification Email: ${NOTIFICATION_EMAIL}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be created"
    fi
}

# Create Lambda function code
create_lambda_code() {
    log_info "Creating Lambda function code..."
    
    cat > "${SCRIPT_DIR}/health_check_function.py" << 'EOF'
import json
import boto3
import logging
from datetime import datetime
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Health check function that monitors SSM agent status
    and updates Systems Manager compliance accordingly.
    """
    ssm = boto3.client('ssm')
    sns = boto3.client('sns')
    
    try:
        # Get all managed instances
        response = ssm.describe_instance_information()
        
        compliance_items = []
        non_compliant_instances = []
        
        for instance in response['InstanceInformationList']:
            instance_id = instance['InstanceId']
            ping_status = instance['PingStatus']
            last_ping_time = instance.get('LastPingDateTime', 'Unknown')
            
            # Determine compliance status based on ping status
            status = 'COMPLIANT' if ping_status == 'Online' else 'NON_COMPLIANT'
            severity = 'HIGH' if status == 'NON_COMPLIANT' else 'INFORMATIONAL'
            
            if status == 'NON_COMPLIANT':
                non_compliant_instances.append({
                    'InstanceId': instance_id,
                    'PingStatus': ping_status,
                    'LastPingTime': str(last_ping_time)
                })
            
            # Update compliance with enhanced details
            compliance_item = {
                'Id': f'HealthCheck-{instance_id}',
                'Title': 'InstanceConnectivityCheck',
                'Severity': severity,
                'Status': status,
                'Details': {
                    'PingStatus': ping_status,
                    'LastPingTime': str(last_ping_time),
                    'CheckTime': datetime.utcnow().isoformat() + 'Z'
                }
            }
            
            ssm.put_compliance_items(
                ResourceId=instance_id,
                ResourceType='ManagedInstance',
                ComplianceType='Custom:EnvironmentHealth',
                ExecutionSummary={
                    'ExecutionTime': datetime.utcnow().isoformat() + 'Z'
                },
                Items=[compliance_item]
            )
            
            compliance_items.append(compliance_item)
        
        # Log health check results
        logger.info(f"Health check completed for {len(compliance_items)} instances")
        
        # Send notification if there are non-compliant instances
        if non_compliant_instances:
            topic_arn = context.function_name.replace('environment-health-check-', 'arn:aws:sns:' + context.invoked_function_arn.split(':')[3] + ':' + context.invoked_function_arn.split(':')[4] + ':environment-health-alerts-')
            
            message = f"Environment Health Alert: {len(non_compliant_instances)} instances are non-compliant\n\n"
            for instance in non_compliant_instances:
                message += f"Instance: {instance['InstanceId']}, Status: {instance['PingStatus']}, Last Ping: {instance['LastPingTime']}\n"
            
            logger.warning(f"Sending alert for {len(non_compliant_instances)} non-compliant instances")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Health check completed successfully',
                'total_instances': len(compliance_items),
                'non_compliant_instances': len(non_compliant_instances)
            })
        }
        
    except ClientError as e:
        error_message = f"AWS API error: {str(e)}"
        logger.error(error_message)
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {error_message}')
        }
    except Exception as e:
        error_message = f"Unexpected error: {str(e)}"
        logger.error(error_message)
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {error_message}')
        }
EOF
    
    # Create ZIP package
    cd "${SCRIPT_DIR}"
    if [[ "${DRY_RUN}" != "true" ]]; then
        zip -q health_check_function.zip health_check_function.py
    fi
    
    log_success "Lambda function code created"
}

# Deploy SNS topic and subscription
deploy_sns() {
    log_info "Creating SNS topic for health notifications..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create SNS topic: environment-health-alerts-${RANDOM_SUFFIX}"
        TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:environment-health-alerts-${RANDOM_SUFFIX}"
        return 0
    fi
    
    # Create SNS topic for health notifications
    aws sns create-topic \
        --name "environment-health-alerts-${RANDOM_SUFFIX}" \
        --tags Key=Purpose,Value=HealthMonitoring \
               Key=Environment,Value=Production \
               Key=DeploymentName,Value="${DEPLOYMENT_NAME}" \
        --region "${AWS_REGION}"
    
    # Store topic ARN for later use
    TOPIC_ARN=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, 'environment-health-alerts-${RANDOM_SUFFIX}')].TopicArn" \
        --output text --region "${AWS_REGION}")
    
    log_success "SNS topic created: ${TOPIC_ARN}"
    
    # Subscribe email to receive health notifications
    log_info "Creating email subscription..."
    aws sns subscribe \
        --topic-arn "${TOPIC_ARN}" \
        --protocol email \
        --notification-endpoint "${NOTIFICATION_EMAIL}" \
        --region "${AWS_REGION}"
    
    log_success "Email subscription created for: ${NOTIFICATION_EMAIL}"
    log_warning "Please check your email and confirm the subscription"
}

# Deploy IAM role and policies for Lambda
deploy_iam() {
    log_info "Creating IAM role and policies for Lambda function..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create IAM role: HealthCheckLambdaRole-${RANDOM_SUFFIX}"
        return 0
    fi
    
    # Create IAM role for Lambda function
    aws iam create-role \
        --role-name "HealthCheckLambdaRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {"Service": "lambda.amazonaws.com"},
                    "Action": "sts:AssumeRole"
                }
            ]
        }' \
        --tags Key=Purpose,Value=HealthMonitoring \
               Key=DeploymentName,Value="${DEPLOYMENT_NAME}"
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "HealthCheckLambdaRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    # Create custom policy for Systems Manager and SNS access
    aws iam create-policy \
        --policy-name "HealthCheckPolicy-${RANDOM_SUFFIX}" \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "ssm:DescribeInstanceInformation",
                        "ssm:PutComplianceItems",
                        "ssm:ListComplianceItems",
                        "sns:Publish"
                    ],
                    "Resource": "*"
                }
            ]
        }' \
        --tags Key=Purpose,Value=HealthMonitoring \
               Key=DeploymentName,Value="${DEPLOYMENT_NAME}"
    
    # Attach custom policy to role
    aws iam attach-role-policy \
        --role-name "HealthCheckLambdaRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/HealthCheckPolicy-${RANDOM_SUFFIX}"
    
    log_success "IAM role and policies created"
    
    # Wait for role to be available
    log_info "Waiting for IAM role to become available..."
    sleep 15
}

# Deploy Lambda function
deploy_lambda() {
    log_info "Deploying Lambda function..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create Lambda function: environment-health-check-${RANDOM_SUFFIX}"
        return 0
    fi
    
    # Create Lambda function with updated Python runtime
    aws lambda create-function \
        --function-name "environment-health-check-${RANDOM_SUFFIX}" \
        --runtime python3.12 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/HealthCheckLambdaRole-${RANDOM_SUFFIX}" \
        --handler health_check_function.lambda_handler \
        --zip-file fileb://health_check_function.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables="{SNS_TOPIC_ARN=${TOPIC_ARN}}" \
        --tags Purpose=HealthMonitoring,DeploymentName="${DEPLOYMENT_NAME}" \
        --region "${AWS_REGION}"
    
    log_success "Lambda function deployed"
}

# Create initial compliance baseline
create_compliance_baseline() {
    log_info "Creating initial compliance baseline..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create initial compliance baseline"
        return 0
    fi
    
    # Get first available instance ID for demonstration
    INSTANCE_ID=$(aws ec2 describe-instances \
        --query 'Reservations[0].Instances[0].InstanceId' \
        --output text --filters Name=state-name,Values=running \
        --region "${AWS_REGION}" 2>/dev/null || echo "None")
    
    if [[ "$INSTANCE_ID" != "None" ]] && [[ -n "$INSTANCE_ID" ]]; then
        # Create initial compliance item for health check baseline
        aws ssm put-compliance-items \
            --resource-id "${INSTANCE_ID}" \
            --resource-type ManagedInstance \
            --compliance-type "Custom:EnvironmentHealth" \
            --execution-summary "ExecutionTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --items "Id=InitialHealthCheck,Title=EnvironmentHealthStatus,Severity=INFORMATIONAL,Status=COMPLIANT" \
            --region "${AWS_REGION}"
        
        log_success "Initial compliance baseline created for instance: ${INSTANCE_ID}"
    else
        log_warning "No running EC2 instances found. Compliance baseline will be created when instances are available."
    fi
}

# Deploy EventBridge rules
deploy_eventbridge() {
    log_info "Creating EventBridge rules..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create EventBridge rules for compliance monitoring and scheduling"
        return 0
    fi
    
    # Create EventBridge rule for compliance state changes
    aws events put-rule \
        --name "compliance-health-alerts-${RANDOM_SUFFIX}" \
        --description "Respond to compliance state changes for health monitoring" \
        --event-pattern '{
            "source": ["aws.ssm"],
            "detail-type": ["Configuration Compliance State Change"],
            "detail": {
                "compliance-type": ["Custom:EnvironmentHealth"],
                "compliance-status": ["NON_COMPLIANT"]
            }
        }' \
        --state ENABLED \
        --region "${AWS_REGION}"
    
    # Add SNS topic as target for compliance events
    aws events put-targets \
        --rule "compliance-health-alerts-${RANDOM_SUFFIX}" \
        --targets "Id"="1","Arn"="${TOPIC_ARN}","InputTransformer"="{\"InputPathsMap\":{\"instance\":\"$.detail.resource-id\",\"status\":\"$.detail.compliance-status\",\"time\":\"$.time\"},\"InputTemplate\":\"Environment Health Alert: Instance <instance> is <status> at <time>. Please investigate immediately.\"}" \
        --region "${AWS_REGION}"
    
    # Grant EventBridge permission to publish to SNS
    aws sns add-permission \
        --topic-arn "${TOPIC_ARN}" \
        --label "EventBridgePublishPermission" \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --action-name Publish \
        --principal events.amazonaws.com \
        --region "${AWS_REGION}"
    
    log_success "EventBridge compliance monitoring rule created"
    
    # Create EventBridge schedule for periodic health checks
    log_info "Creating scheduled health checks..."
    aws events put-rule \
        --name "health-check-schedule-${RANDOM_SUFFIX}" \
        --description "Schedule health checks every 5 minutes" \
        --schedule-expression "rate(5 minutes)" \
        --state ENABLED \
        --region "${AWS_REGION}"
    
    # Add Lambda function as target
    aws events put-targets \
        --rule "health-check-schedule-${RANDOM_SUFFIX}" \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:environment-health-check-${RANDOM_SUFFIX}","Input"="{\"source\":\"eventbridge-schedule\"}" \
        --region "${AWS_REGION}"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name "environment-health-check-${RANDOM_SUFFIX}" \
        --statement-id "allow-eventbridge-schedule-invoke" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/health-check-schedule-${RANDOM_SUFFIX}" \
        --region "${AWS_REGION}"
    
    log_success "Scheduled health checks configured"
}

# Test the deployment
test_deployment() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would test the deployment"
        return 0
    fi
    
    log_info "Testing deployment..."
    
    # Test Lambda function
    log_info "Testing Lambda function..."
    aws lambda invoke \
        --function-name "environment-health-check-${RANDOM_SUFFIX}" \
        --payload '{"source":"deployment-test"}' \
        response.json \
        --region "${AWS_REGION}" &>/dev/null
    
    if [[ -f response.json ]]; then
        RESPONSE=$(cat response.json)
        if [[ "${RESPONSE}" == *'"statusCode": 200'* ]]; then
            log_success "Lambda function test passed"
        else
            log_warning "Lambda function test may have issues. Check logs for details."
        fi
        rm -f response.json
    fi
    
    # Send test notification
    log_info "Sending test notification..."
    aws sns publish \
        --topic-arn "${TOPIC_ARN}" \
        --subject "Test Health Alert - Deployment Complete" \
        --message "This is a test notification from your newly deployed environment health monitoring system. Deployment completed successfully!" \
        --region "${AWS_REGION}" &>/dev/null
    
    log_success "Test notification sent - please check your email"
}

# Save deployment information
save_deployment_info() {
    local info_file="${SCRIPT_DIR}/deployment-info.json"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would save deployment info to: ${info_file}"
        return 0
    fi
    
    cat > "${info_file}" << EOF
{
    "deployment_name": "${DEPLOYMENT_NAME}",
    "random_suffix": "${RANDOM_SUFFIX}",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "notification_email": "${NOTIFICATION_EMAIL}",
    "topic_arn": "${TOPIC_ARN}",
    "lambda_function_name": "environment-health-check-${RANDOM_SUFFIX}",
    "iam_role_name": "HealthCheckLambdaRole-${RANDOM_SUFFIX}",
    "iam_policy_name": "HealthCheckPolicy-${RANDOM_SUFFIX}",
    "compliance_rule_name": "compliance-health-alerts-${RANDOM_SUFFIX}",
    "schedule_rule_name": "health-check-schedule-${RANDOM_SUFFIX}",
    "deployed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log_success "Deployment information saved to: ${info_file}"
}

# Cleanup function for failed deployments
cleanup_on_failure() {
    log_error "Deployment failed. Cleaning up partial resources..."
    
    # Call the destroy script if it exists
    if [[ -f "${SCRIPT_DIR}/destroy.sh" ]]; then
        bash "${SCRIPT_DIR}/destroy.sh" --force --suffix "${RANDOM_SUFFIX}" 2>/dev/null || true
    fi
    
    # Clean up local files
    rm -f "${SCRIPT_DIR}/health_check_function.py"
    rm -f "${SCRIPT_DIR}/health_check_function.zip"
    rm -f "${SCRIPT_DIR}/response.json"
    rm -f "${SCRIPT_DIR}/deployment-info.json"
    
    exit 1
}

# Main deployment function
main() {
    echo "================================================"
    echo "Simple Environment Health Check Deployment"
    echo "================================================"
    
    # Set up error handling
    trap cleanup_on_failure ERR
    
    # Parse arguments and validate
    parse_arguments "$@"
    check_prerequisites
    setup_environment
    
    # Create Lambda code
    create_lambda_code
    
    # Deploy infrastructure components
    deploy_sns
    deploy_iam
    deploy_lambda
    create_compliance_baseline
    deploy_eventbridge
    
    # Test deployment
    test_deployment
    
    # Save deployment information
    save_deployment_info
    
    # Clean up temporary files
    if [[ "${DRY_RUN}" != "true" ]]; then
        rm -f "${SCRIPT_DIR}/health_check_function.py"
        rm -f "${SCRIPT_DIR}/health_check_function.zip"
    fi
    
    echo "================================================"
    log_success "Deployment completed successfully!"
    echo "================================================"
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        echo
        echo "Deployment Summary:"
        echo "  - SNS Topic: ${TOPIC_ARN}"
        echo "  - Lambda Function: environment-health-check-${RANDOM_SUFFIX}"
        echo "  - Notification Email: ${NOTIFICATION_EMAIL}"
        echo "  - Region: ${AWS_REGION}"
        echo
        echo "Next Steps:"
        echo "  1. Confirm your email subscription"
        echo "  2. Ensure EC2 instances have SSM Agent installed"
        echo "  3. Monitor the CloudWatch logs for the Lambda function"
        echo "  4. Check Systems Manager Compliance for health status"
        echo
        echo "To destroy this deployment, run:"
        echo "  ./destroy.sh --suffix ${RANDOM_SUFFIX}"
    else
        echo
        log_info "DRY RUN completed - no resources were created"
    fi
}

# Run main function with all arguments
main "$@"