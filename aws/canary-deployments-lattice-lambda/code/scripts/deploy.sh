#!/bin/bash

# Canary Deployments with VPC Lattice and Lambda - Deployment Script
# This script deploys a complete canary deployment infrastructure using VPC Lattice
# for progressive traffic routing between Lambda function versions

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
RESOURCE_PREFIX="canary-demo"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

# Error handler
error_exit() {
    log ERROR "$1"
    log ERROR "Deployment failed. Check $LOG_FILE for details."
    exit 1
}

# Cleanup on script exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log ERROR "Script exited with error code $exit_code"
        log INFO "Consider running ./destroy.sh to clean up any partially created resources"
    fi
}
trap cleanup_on_exit EXIT

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    log INFO "Checking AWS CLI authentication..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error_exit "AWS CLI is not configured or authentication failed. Please run 'aws configure' or set AWS credentials."
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region || echo "us-east-1")
    log INFO "✅ Authenticated to AWS Account: $account_id, Region: $region"
}

# Function to check required AWS permissions
check_aws_permissions() {
    log INFO "Checking AWS permissions..."
    
    local required_services=(
        "vpc-lattice"
        "lambda"
        "iam"
        "cloudwatch"
        "sns"
        "logs"
    )
    
    for service in "${required_services[@]}"; do
        case $service in
            "vpc-lattice")
                if ! aws vpc-lattice list-service-networks --max-results 1 >/dev/null 2>&1; then
                    error_exit "Missing VPC Lattice permissions. Ensure your IAM user/role has VPCLatticeFullAccess or equivalent permissions."
                fi
                ;;
            "lambda")
                if ! aws lambda list-functions --max-items 1 >/dev/null 2>&1; then
                    error_exit "Missing Lambda permissions. Ensure your IAM user/role has AWSLambda_FullAccess or equivalent permissions."
                fi
                ;;
            "iam")
                if ! aws iam list-roles --max-items 1 >/dev/null 2>&1; then
                    error_exit "Missing IAM permissions. Ensure your IAM user/role has IAMFullAccess or equivalent permissions."
                fi
                ;;
            "cloudwatch")
                if ! aws cloudwatch list-metrics --max-records 1 >/dev/null 2>&1; then
                    error_exit "Missing CloudWatch permissions. Ensure your IAM user/role has CloudWatchFullAccess or equivalent permissions."
                fi
                ;;
            "sns")
                if ! aws sns list-topics >/dev/null 2>&1; then
                    error_exit "Missing SNS permissions. Ensure your IAM user/role has AmazonSNSFullAccess or equivalent permissions."
                fi
                ;;
            "logs")
                if ! aws logs describe-log-groups --limit 1 >/dev/null 2>&1; then
                    error_exit "Missing CloudWatch Logs permissions. Ensure your IAM user/role has CloudWatchLogsFullAccess or equivalent permissions."
                fi
                ;;
        esac
    done
    
    log INFO "✅ All required AWS permissions verified"
}

# Function to validate prerequisites
validate_prerequisites() {
    log INFO "Validating prerequisites..."
    
    # Check required commands
    local required_commands=("aws" "jq" "zip" "curl")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            error_exit "Required command '$cmd' not found. Please install it and try again."
        fi
    done
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local required_version="2.0.0"
    if [[ $(printf '%s\n' "$required_version" "$aws_version" | sort -V | head -n1) != "$required_version" ]]; then
        error_exit "AWS CLI version $aws_version is too old. Please upgrade to version $required_version or later."
    fi
    
    check_aws_auth
    check_aws_permissions
    
    log INFO "✅ All prerequisites validated successfully"
}

# Function to generate unique resource identifiers
generate_unique_suffix() {
    log INFO "Generating unique resource identifiers..."
    
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export SERVICE_NAME="${RESOURCE_PREFIX}-service-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="${RESOURCE_PREFIX}-function-${RANDOM_SUFFIX}"
    export SERVICE_NETWORK_NAME="${RESOURCE_PREFIX}-network-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="lambda-canary-execution-role-${RANDOM_SUFFIX}"
    export ROLLBACK_FUNCTION_NAME="canary-rollback-${RANDOM_SUFFIX}"
    
    log INFO "✅ Resource identifiers generated with suffix: $RANDOM_SUFFIX"
}

# Function to create IAM role for Lambda
create_iam_role() {
    log INFO "Creating IAM execution role for Lambda functions..."
    
    # Create the assume role policy document
    local assume_role_policy='{
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
    }'
    
    # Create IAM role
    if aws iam create-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --assume-role-policy-document "$assume_role_policy" \
        --description "Execution role for canary deployment Lambda functions" \
        >/dev/null 2>&1; then
        log INFO "✅ IAM role created: $LAMBDA_ROLE_NAME"
    else
        log WARN "IAM role may already exist, continuing..."
    fi
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        >/dev/null 2>&1 || log WARN "Basic execution policy may already be attached"
    
    # Attach VPC Lattice access policy
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/VPCLatticeServiceAccess \
        >/dev/null 2>&1 || log WARN "VPC Lattice policy may already be attached"
    
    # Wait for role to be available
    log INFO "Waiting for IAM role to be available..."
    sleep 10
    
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --query 'Role.Arn' --output text)
    
    log INFO "✅ IAM role ready: $LAMBDA_ROLE_ARN"
}

# Function to create Lambda function version 1 (Production)
create_lambda_v1() {
    log INFO "Creating Lambda function version 1 (Production)..."
    
    # Create temporary directory for Lambda code
    local temp_dir=$(mktemp -d)
    
    # Create Lambda function code for version 1
    cat > "$temp_dir/lambda-v1.py" << 'EOF'
import json
import time

def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json'
        },
        'body': json.dumps({
            'version': 'v1.0.0',
            'message': 'Hello from production version',
            'timestamp': int(time.time()),
            'environment': 'production'
        })
    }
EOF
    
    # Package the function
    (cd "$temp_dir" && zip -q lambda-v1.zip lambda-v1.py)
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$FUNCTION_NAME" \
        --runtime python3.11 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler lambda-v1.lambda_handler \
        --zip-file "fileb://$temp_dir/lambda-v1.zip" \
        --timeout 30 \
        --memory-size 256 \
        --description "Production version for canary deployment demo" \
        >/dev/null || error_exit "Failed to create Lambda function"
    
    # Wait for function to be active
    log INFO "Waiting for Lambda function to be active..."
    aws lambda wait function-active --function-name "$FUNCTION_NAME" || error_exit "Lambda function failed to become active"
    
    # Publish version 1
    export LAMBDA_VERSION_1=$(aws lambda publish-version \
        --function-name "$FUNCTION_NAME" \
        --description "Production version 1.0.0" \
        --query 'Version' --output text) || error_exit "Failed to publish Lambda version 1"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log INFO "✅ Lambda function version 1 created: $LAMBDA_VERSION_1"
}

# Function to create Lambda function version 2 (Canary)
create_lambda_v2() {
    log INFO "Creating Lambda function version 2 (Canary)..."
    
    # Create temporary directory for Lambda code
    local temp_dir=$(mktemp -d)
    
    # Create enhanced Lambda function code for version 2
    cat > "$temp_dir/lambda-v2.py" << 'EOF'
import json
import time
import random

def lambda_handler(event, context):
    # Simulate enhanced features in canary version
    features = ['feature-a', 'feature-b', 'enhanced-logging']
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'X-Version': 'v2.0.0'
        },
        'body': json.dumps({
            'version': 'v2.0.0',
            'message': 'Hello from canary version',
            'timestamp': int(time.time()),
            'environment': 'canary',
            'features': features,
            'response_time': random.randint(50, 200)
        })
    }
EOF
    
    # Package the function
    (cd "$temp_dir" && zip -q lambda-v2.zip lambda-v2.py)
    
    # Update function code
    aws lambda update-function-code \
        --function-name "$FUNCTION_NAME" \
        --zip-file "fileb://$temp_dir/lambda-v2.zip" \
        >/dev/null || error_exit "Failed to update Lambda function code"
    
    # Wait for update to complete
    aws lambda wait function-updated --function-name "$FUNCTION_NAME" || error_exit "Lambda function update failed"
    
    # Publish version 2
    export LAMBDA_VERSION_2=$(aws lambda publish-version \
        --function-name "$FUNCTION_NAME" \
        --description "Canary version 2.0.0 with enhanced features" \
        --query 'Version' --output text) || error_exit "Failed to publish Lambda version 2"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log INFO "✅ Lambda function version 2 created: $LAMBDA_VERSION_2"
}

# Function to create VPC Lattice service network
create_service_network() {
    log INFO "Creating VPC Lattice service network..."
    
    export SERVICE_NETWORK_ID=$(aws vpc-lattice create-service-network \
        --name "$SERVICE_NETWORK_NAME" \
        --auth-type "NONE" \
        --query 'id' --output text) || error_exit "Failed to create VPC Lattice service network"
    
    # Wait for service network to be active
    log INFO "Waiting for service network to be active..."
    local status=""
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        status=$(aws vpc-lattice get-service-network \
            --service-network-identifier "$SERVICE_NETWORK_ID" \
            --query 'status' --output text 2>/dev/null || echo "")
        
        if [[ "$status" == "ACTIVE" ]]; then
            break
        fi
        
        log DEBUG "Service network status: $status (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [[ "$status" != "ACTIVE" ]]; then
        error_exit "Service network failed to become active within expected time"
    fi
    
    log INFO "✅ VPC Lattice service network created: $SERVICE_NETWORK_ID"
}

# Function to create target groups
create_target_groups() {
    log INFO "Creating VPC Lattice target groups..."
    
    # Create target group for production version (v1)
    export PROD_TARGET_GROUP_ID=$(aws vpc-lattice create-target-group \
        --name "prod-targets-${RANDOM_SUFFIX}" \
        --type "LAMBDA" \
        --query 'id' --output text) || error_exit "Failed to create production target group"
    
    # Register Lambda version 1 with production target group
    aws vpc-lattice register-targets \
        --target-group-identifier "$PROD_TARGET_GROUP_ID" \
        --targets "id=${FUNCTION_NAME}:${LAMBDA_VERSION_1}" \
        >/dev/null || error_exit "Failed to register Lambda v1 with production target group"
    
    # Create target group for canary version (v2)
    export CANARY_TARGET_GROUP_ID=$(aws vpc-lattice create-target-group \
        --name "canary-targets-${RANDOM_SUFFIX}" \
        --type "LAMBDA" \
        --query 'id' --output text) || error_exit "Failed to create canary target group"
    
    # Register Lambda version 2 with canary target group
    aws vpc-lattice register-targets \
        --target-group-identifier "$CANARY_TARGET_GROUP_ID" \
        --targets "id=${FUNCTION_NAME}:${LAMBDA_VERSION_2}" \
        >/dev/null || error_exit "Failed to register Lambda v2 with canary target group"
    
    log INFO "✅ Target groups created - Production: $PROD_TARGET_GROUP_ID"
    log INFO "✅ Target groups created - Canary: $CANARY_TARGET_GROUP_ID"
}

# Function to create VPC Lattice service with weighted routing
create_lattice_service() {
    log INFO "Creating VPC Lattice service with weighted routing..."
    
    # Create VPC Lattice service
    export SERVICE_ID=$(aws vpc-lattice create-service \
        --name "$SERVICE_NAME" \
        --auth-type "NONE" \
        --query 'id' --output text) || error_exit "Failed to create VPC Lattice service"
    
    # Create default action for weighted routing
    local default_action='{
        "forward": {
            "targetGroups": [
                {
                    "targetGroupIdentifier": "'$PROD_TARGET_GROUP_ID'",
                    "weight": 90
                },
                {
                    "targetGroupIdentifier": "'$CANARY_TARGET_GROUP_ID'",
                    "weight": 10
                }
            ]
        }
    }'
    
    # Create HTTP listener with weighted routing
    export LISTENER_ID=$(aws vpc-lattice create-listener \
        --service-identifier "$SERVICE_ID" \
        --name "canary-listener" \
        --protocol "HTTP" \
        --port 80 \
        --default-action "$default_action" \
        --query 'id' --output text) || error_exit "Failed to create VPC Lattice listener"
    
    # Associate service with service network
    aws vpc-lattice create-service-network-service-association \
        --service-network-identifier "$SERVICE_NETWORK_ID" \
        --service-identifier "$SERVICE_ID" \
        >/dev/null || error_exit "Failed to associate service with service network"
    
    log INFO "✅ VPC Lattice service created with 90/10 traffic split"
    log INFO "✅ Service ID: $SERVICE_ID"
    log INFO "✅ Listener ID: $LISTENER_ID"
}

# Function to configure CloudWatch monitoring
configure_monitoring() {
    log INFO "Configuring CloudWatch monitoring and alarms..."
    
    # Create CloudWatch alarm for Lambda errors in canary version
    aws cloudwatch put-metric-alarm \
        --alarm-name "canary-lambda-errors-${RANDOM_SUFFIX}" \
        --alarm-description "Monitor errors in canary Lambda version" \
        --metric-name "Errors" \
        --namespace "AWS/Lambda" \
        --statistic "Sum" \
        --period 300 \
        --evaluation-periods 2 \
        --threshold 5 \
        --comparison-operator "GreaterThanThreshold" \
        --dimensions "Name=FunctionName,Value=${FUNCTION_NAME}" \
                     "Name=Resource,Value=${FUNCTION_NAME}:${LAMBDA_VERSION_2}" \
        >/dev/null || error_exit "Failed to create CloudWatch error alarm"
    
    # Create CloudWatch alarm for Lambda duration in canary version
    aws cloudwatch put-metric-alarm \
        --alarm-name "canary-lambda-duration-${RANDOM_SUFFIX}" \
        --alarm-description "Monitor duration in canary Lambda version" \
        --metric-name "Duration" \
        --namespace "AWS/Lambda" \
        --statistic "Average" \
        --period 300 \
        --evaluation-periods 2 \
        --threshold 5000 \
        --comparison-operator "GreaterThanThreshold" \
        --dimensions "Name=FunctionName,Value=${FUNCTION_NAME}" \
                     "Name=Resource,Value=${FUNCTION_NAME}:${LAMBDA_VERSION_2}" \
        >/dev/null || error_exit "Failed to create CloudWatch duration alarm"
    
    log INFO "✅ CloudWatch alarms configured for canary monitoring"
}

# Function to create rollback infrastructure
create_rollback_infrastructure() {
    log INFO "Creating automatic rollback infrastructure..."
    
    # Create SNS topic for rollback notifications
    export ROLLBACK_TOPIC_ARN=$(aws sns create-topic \
        --name "canary-rollback-${RANDOM_SUFFIX}" \
        --query 'TopicArn' --output text) || error_exit "Failed to create SNS topic"
    
    # Create temporary directory for rollback function code
    local temp_dir=$(mktemp -d)
    
    # Create Lambda function for automatic rollback
    cat > "$temp_dir/rollback-function.py" << 'EOF'
import boto3
import json
import os

def lambda_handler(event, context):
    lattice = boto3.client('vpc-lattice')
    
    # Parse CloudWatch alarm
    message = json.loads(event['Records'][0]['Sns']['Message'])
    alarm_name = message['AlarmName']
    
    if 'canary' in alarm_name and message['NewStateValue'] == 'ALARM':
        # Rollback to 100% production traffic
        try:
            lattice.update_listener(
                serviceIdentifier=os.environ['SERVICE_ID'],
                listenerIdentifier=os.environ['LISTENER_ID'],
                defaultAction={
                    'forward': {
                        'targetGroups': [
                            {
                                'targetGroupIdentifier': os.environ['PROD_TARGET_GROUP_ID'],
                                'weight': 100
                            }
                        ]
                    }
                }
            )
            print(f"Automatic rollback triggered by alarm: {alarm_name}")
            return {'statusCode': 200, 'body': 'Rollback successful'}
        except Exception as e:
            print(f"Rollback failed: {str(e)}")
            return {'statusCode': 500, 'body': f'Rollback failed: {str(e)}'}
    
    return {'statusCode': 200, 'body': 'No action required'}
EOF
    
    # Package the rollback function
    (cd "$temp_dir" && zip -q rollback-function.zip rollback-function.py)
    
    # Create rollback Lambda function
    aws lambda create-function \
        --function-name "$ROLLBACK_FUNCTION_NAME" \
        --runtime python3.11 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler rollback-function.lambda_handler \
        --zip-file "fileb://$temp_dir/rollback-function.zip" \
        --environment "Variables={SERVICE_ID=$SERVICE_ID,LISTENER_ID=$LISTENER_ID,PROD_TARGET_GROUP_ID=$PROD_TARGET_GROUP_ID}" \
        --description "Automatic rollback function for canary deployments" \
        >/dev/null || error_exit "Failed to create rollback Lambda function"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log INFO "✅ Automatic rollback function created: $ROLLBACK_FUNCTION_NAME"
}

# Function to save deployment state
save_deployment_state() {
    log INFO "Saving deployment state..."
    
    local state_file="${SCRIPT_DIR}/deployment-state.json"
    
    cat > "$state_file" << EOF
{
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "random_suffix": "$RANDOM_SUFFIX",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "service_name": "$SERVICE_NAME",
    "function_name": "$FUNCTION_NAME",
    "service_network_name": "$SERVICE_NETWORK_NAME",
    "lambda_role_name": "$LAMBDA_ROLE_NAME",
    "rollback_function_name": "$ROLLBACK_FUNCTION_NAME",
    "lambda_role_arn": "$LAMBDA_ROLE_ARN",
    "lambda_version_1": "$LAMBDA_VERSION_1",
    "lambda_version_2": "$LAMBDA_VERSION_2",
    "service_network_id": "$SERVICE_NETWORK_ID",
    "prod_target_group_id": "$PROD_TARGET_GROUP_ID",
    "canary_target_group_id": "$CANARY_TARGET_GROUP_ID",
    "service_id": "$SERVICE_ID",
    "listener_id": "$LISTENER_ID",
    "rollback_topic_arn": "$ROLLBACK_TOPIC_ARN"
}
EOF
    
    log INFO "✅ Deployment state saved to: $state_file"
}

# Function to display deployment summary
display_summary() {
    log INFO "Deployment completed successfully!"
    echo ""
    echo -e "${GREEN}=== DEPLOYMENT SUMMARY ===${NC}"
    echo -e "${BLUE}Service DNS:${NC} $(aws vpc-lattice get-service --service-identifier "$SERVICE_ID" --query 'dnsEntry.domainName' --output text 2>/dev/null || echo 'N/A')"
    echo -e "${BLUE}Lambda Function:${NC} $FUNCTION_NAME"
    echo -e "${BLUE}Production Version:${NC} $LAMBDA_VERSION_1 (90% traffic)"
    echo -e "${BLUE}Canary Version:${NC} $LAMBDA_VERSION_2 (10% traffic)"
    echo -e "${BLUE}Service Network:${NC} $SERVICE_NETWORK_ID"
    echo -e "${BLUE}VPC Lattice Service:${NC} $SERVICE_ID"
    echo ""
    echo -e "${GREEN}=== TESTING ===${NC}"
    echo "You can test the canary deployment by making HTTP requests to the service DNS endpoint."
    echo "Approximately 90% of requests will go to v1.0.0 (production) and 10% to v2.0.0 (canary)."
    echo ""
    echo -e "${GREEN}=== CLEANUP ===${NC}"
    echo "To remove all resources, run: ./destroy.sh"
    echo ""
    echo -e "${GREEN}=== MONITORING ===${NC}"
    echo "CloudWatch alarms have been configured to monitor the canary deployment:"
    echo "- canary-lambda-errors-${RANDOM_SUFFIX}"
    echo "- canary-lambda-duration-${RANDOM_SUFFIX}"
    echo ""
}

# Main deployment function
main() {
    log INFO "Starting canary deployment infrastructure setup..."
    echo "Log file: $LOG_FILE"
    
    validate_prerequisites
    generate_unique_suffix
    create_iam_role
    create_lambda_v1
    create_lambda_v2
    create_service_network
    create_target_groups
    create_lattice_service
    configure_monitoring
    create_rollback_infrastructure
    save_deployment_state
    display_summary
    
    log INFO "Deployment completed successfully! Total time: ${SECONDS}s"
}

# Check if running in dry-run mode
if [[ "${1:-}" == "--dry-run" ]]; then
    log INFO "Running in dry-run mode - no resources will be created"
    validate_prerequisites
    generate_unique_suffix
    log INFO "Dry-run completed successfully!"
    exit 0
fi

# Run main deployment
main "$@"