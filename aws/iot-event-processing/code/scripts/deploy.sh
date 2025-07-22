#!/bin/bash

# IoT Rules Engine Event Processing - Deployment Script
# This script deploys the complete IoT Rules Engine infrastructure for factory event processing

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TEMP_DIR="/tmp/iot-rules-deployment-$$"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1" | tee -a "$LOG_FILE"
    fi
}

# Cleanup function for temporary files
cleanup() {
    log_debug "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    log_debug "Cleanup completed"
}

# Error handler
error_handler() {
    local line_number=$1
    log_error "Script failed at line $line_number"
    log_error "Check the log file for details: $LOG_FILE"
    cleanup
    exit 1
}

# Set up error handling
trap 'error_handler ${LINENO}' ERR
trap cleanup EXIT

# Help function
show_help() {
    cat << EOF
IoT Rules Engine Event Processing - Deployment Script

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -d, --debug         Enable debug logging
    -y, --yes           Skip confirmation prompts
    -p, --prefix PREFIX Custom resource prefix (default: factory)
    --dry-run          Show what would be deployed without creating resources

EXAMPLES:
    $0                  # Deploy with default settings
    $0 -d -y            # Deploy with debug logging, skip confirmations
    $0 --prefix myorg   # Deploy with custom prefix
    $0 --dry-run        # Show deployment plan without creating resources

EOF
}

# Parse command line arguments
DRY_RUN=false
DEBUG=false
SKIP_CONFIRM=false
RESOURCE_PREFIX="factory"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRM=true
            shift
            ;;
        -p|--prefix)
            RESOURCE_PREFIX="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Initialize logging
echo "=== IoT Rules Engine Event Processing Deployment ===" > "$LOG_FILE"
echo "Started at: $(date)" >> "$LOG_FILE"
echo "Script: $0" >> "$LOG_FILE"
echo "Arguments: $*" >> "$LOG_FILE"
echo "User: $(whoami)" >> "$LOG_FILE"
echo "Working directory: $(pwd)" >> "$LOG_FILE"

log "Starting IoT Rules Engine deployment..."

# Create temporary directory
mkdir -p "$TEMP_DIR"
log_debug "Created temporary directory: $TEMP_DIR"

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | head -n1 | awk '{print $1}' | cut -d/ -f2)
    log_debug "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check required permissions (basic check)
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region)
    
    if [[ -z "$region" ]]; then
        log_error "AWS region not configured. Please run 'aws configure'."
        exit 1
    fi
    
    log "Prerequisites check passed"
    log "AWS Account ID: $account_id"
    log "AWS Region: $region"
    
    # Export for use in script
    export AWS_ACCOUNT_ID="$account_id"
    export AWS_REGION="$region"
}

# Generate unique resource identifiers
generate_resource_names() {
    log "Generating unique resource identifiers..."
    
    # Generate random suffix for uniqueness
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Export resource names
    export IOT_THING_NAME="${RESOURCE_PREFIX}-sensor-${random_suffix}"
    export IOT_POLICY_NAME="${RESOURCE_PREFIX}-iot-policy-${random_suffix}"
    export IOT_ROLE_NAME="${RESOURCE_PREFIX}-iot-rules-role-${random_suffix}"
    export LAMBDA_FUNCTION_NAME="${RESOURCE_PREFIX}-event-processor-${random_suffix}"
    export DDB_TABLE_NAME="${RESOURCE_PREFIX}-telemetry-${random_suffix}"
    export SNS_TOPIC_NAME="${RESOURCE_PREFIX}-alerts-${random_suffix}"
    
    log "Resource names generated:"
    log "  IoT Thing: $IOT_THING_NAME"
    log "  IoT Policy: $IOT_POLICY_NAME"
    log "  IoT Role: $IOT_ROLE_NAME"
    log "  Lambda Function: $LAMBDA_FUNCTION_NAME"
    log "  DynamoDB Table: $DDB_TABLE_NAME"
    log "  SNS Topic: $SNS_TOPIC_NAME"
}

# Create DynamoDB table
create_dynamodb_table() {
    log "Creating DynamoDB table: $DDB_TABLE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create DynamoDB table $DDB_TABLE_NAME"
        return 0
    fi
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name "$DDB_TABLE_NAME" &>/dev/null; then
        log_warn "DynamoDB table $DDB_TABLE_NAME already exists"
        return 0
    fi
    
    aws dynamodb create-table \
        --table-name "$DDB_TABLE_NAME" \
        --attribute-definitions \
            AttributeName=deviceId,AttributeType=S \
            AttributeName=timestamp,AttributeType=N \
        --key-schema \
            AttributeName=deviceId,KeyType=HASH \
            AttributeName=timestamp,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Project,Value=IoTRulesEngine \
               Key=Environment,Value=Production \
               Key=ManagedBy,Value=IoTRulesDeploymentScript
    
    # Wait for table to be active
    log "Waiting for DynamoDB table to be active..."
    aws dynamodb wait table-exists --table-name "$DDB_TABLE_NAME"
    
    log "✅ DynamoDB table created successfully: $DDB_TABLE_NAME"
}

# Create SNS topic
create_sns_topic() {
    log "Creating SNS topic: $SNS_TOPIC_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create SNS topic $SNS_TOPIC_NAME"
        export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
        return 0
    fi
    
    local topic_arn=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --attributes DisplayName="Factory Alerts" \
        --tags Key=Project,Value=IoTRulesEngine \
               Key=Environment,Value=Production \
               Key=ManagedBy,Value=IoTRulesDeploymentScript \
        --query TopicArn --output text)
    
    export SNS_TOPIC_ARN="$topic_arn"
    
    log "✅ SNS topic created successfully: $SNS_TOPIC_ARN"
}

# Create IAM role for IoT Rules Engine
create_iot_role() {
    log "Creating IAM role for IoT Rules Engine: $IOT_ROLE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create IAM role $IOT_ROLE_NAME"
        export IOT_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IOT_ROLE_NAME}"
        return 0
    fi
    
    # Create trust policy
    cat > "$TEMP_DIR/iot-trust-policy.json" << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "iot.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Check if role already exists
    if aws iam get-role --role-name "$IOT_ROLE_NAME" &>/dev/null; then
        log_warn "IAM role $IOT_ROLE_NAME already exists"
        local role_arn=$(aws iam get-role --role-name "$IOT_ROLE_NAME" --query Role.Arn --output text)
        export IOT_ROLE_ARN="$role_arn"
        return 0
    fi
    
    # Create IAM role
    aws iam create-role \
        --role-name "$IOT_ROLE_NAME" \
        --assume-role-policy-document file://"$TEMP_DIR/iot-trust-policy.json" \
        --tags Key=Project,Value=IoTRulesEngine \
               Key=Environment,Value=Production \
               Key=ManagedBy,Value=IoTRulesDeploymentScript
    
    # Get role ARN
    local role_arn=$(aws iam get-role --role-name "$IOT_ROLE_NAME" --query Role.Arn --output text)
    export IOT_ROLE_ARN="$role_arn"
    
    log "✅ IAM role created successfully: $IOT_ROLE_ARN"
}

# Create IAM policy for IoT Rules Engine
create_iot_policy() {
    log "Creating IAM policy for IoT Rules Engine actions"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create IAM policy ${IOT_ROLE_NAME}-policy"
        return 0
    fi
    
    # Create policy document
    cat > "$TEMP_DIR/iot-rules-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:GetItem",
                "dynamodb:Query"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DDB_TABLE_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "${SNS_TOPIC_ARN}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction"
            ],
            "Resource": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}"
        }
    ]
}
EOF
    
    # Check if policy already exists
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IOT_ROLE_NAME}-policy"
    if aws iam get-policy --policy-arn "$policy_arn" &>/dev/null; then
        log_warn "IAM policy ${IOT_ROLE_NAME}-policy already exists"
    else
        # Create policy
        aws iam create-policy \
            --policy-name "${IOT_ROLE_NAME}-policy" \
            --policy-document file://"$TEMP_DIR/iot-rules-policy.json" \
            --tags Key=Project,Value=IoTRulesEngine \
                   Key=Environment,Value=Production \
                   Key=ManagedBy,Value=IoTRulesDeploymentScript
        
        log "✅ IAM policy created successfully"
    fi
    
    # Attach policy to role
    aws iam attach-role-policy \
        --role-name "$IOT_ROLE_NAME" \
        --policy-arn "$policy_arn"
    
    log "✅ IAM policy attached to role"
}

# Create Lambda execution role
create_lambda_role() {
    log "Creating Lambda execution role"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create Lambda execution role"
        return 0
    fi
    
    local lambda_role_name="${IOT_ROLE_NAME}-lambda-execution"
    
    # Create trust policy for Lambda
    cat > "$TEMP_DIR/lambda-trust-policy.json" << 'EOF'
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
    
    # Check if role already exists
    if aws iam get-role --role-name "$lambda_role_name" &>/dev/null; then
        log_warn "Lambda execution role $lambda_role_name already exists"
        local lambda_role_arn=$(aws iam get-role --role-name "$lambda_role_name" --query Role.Arn --output text)
        export LAMBDA_ROLE_ARN="$lambda_role_arn"
        return 0
    fi
    
    # Create Lambda execution role
    aws iam create-role \
        --role-name "$lambda_role_name" \
        --assume-role-policy-document file://"$TEMP_DIR/lambda-trust-policy.json" \
        --tags Key=Project,Value=IoTRulesEngine \
               Key=Environment,Value=Production \
               Key=ManagedBy,Value=IoTRulesDeploymentScript
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "$lambda_role_name" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    # Get role ARN
    local lambda_role_arn=$(aws iam get-role --role-name "$lambda_role_name" --query Role.Arn --output text)
    export LAMBDA_ROLE_ARN="$lambda_role_arn"
    
    log "✅ Lambda execution role created successfully: $LAMBDA_ROLE_ARN"
}

# Create Lambda function
create_lambda_function() {
    log "Creating Lambda function: $LAMBDA_FUNCTION_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create Lambda function $LAMBDA_FUNCTION_NAME"
        return 0
    fi
    
    # Check if function already exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log_warn "Lambda function $LAMBDA_FUNCTION_NAME already exists"
        return 0
    fi
    
    # Create Lambda function code
    cat > "$TEMP_DIR/lambda-function.py" << 'EOF'
import json
import boto3
from datetime import datetime

def lambda_handler(event, context):
    """
    Process IoT events and perform custom business logic
    """
    try:
        # Parse the incoming IoT message
        device_id = event.get('deviceId', 'unknown')
        temperature = event.get('temperature', 0)
        timestamp = event.get('timestamp', int(datetime.now().timestamp()))
        
        # Custom processing logic
        severity = 'normal'
        if temperature > 85:
            severity = 'critical'
        elif temperature > 75:
            severity = 'warning'
        
        # Log the processed event
        print(f"Processing event from {device_id}: temp={temperature}°C, severity={severity}")
        
        # Return enriched data
        return {
            'statusCode': 200,
            'body': json.dumps({
                'deviceId': device_id,
                'temperature': temperature,
                'severity': severity,
                'processedAt': timestamp,
                'message': f'Temperature {temperature}°C processed with severity {severity}'
            })
        }
        
    except Exception as e:
        print(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Create deployment package
    cd "$TEMP_DIR"
    zip lambda-function.zip lambda-function.py
    cd - > /dev/null
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler lambda-function.lambda_handler \
        --zip-file fileb://"$TEMP_DIR/lambda-function.zip" \
        --timeout 30 \
        --tags Project=IoTRulesEngine,Environment=Production,ManagedBy=IoTRulesDeploymentScript
    
    log "✅ Lambda function created successfully: $LAMBDA_FUNCTION_NAME"
}

# Create IoT rules
create_iot_rules() {
    log "Creating IoT Rules..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create IoT Rules"
        return 0
    fi
    
    # Create temperature monitoring rule
    cat > "$TEMP_DIR/temperature-rule.json" << EOF
{
    "sql": "SELECT deviceId, temperature, timestamp() as timestamp FROM 'factory/temperature' WHERE temperature > 70",
    "description": "Monitor temperature sensors and trigger alerts for high temperatures",
    "ruleDisabled": false,
    "awsIotSqlVersion": "2016-03-23",
    "actions": [
        {
            "dynamodb": {
                "tableName": "${DDB_TABLE_NAME}",
                "roleArn": "${IOT_ROLE_ARN}",
                "hashKeyField": "deviceId",
                "hashKeyValue": "\${deviceId}",
                "rangeKeyField": "timestamp", 
                "rangeKeyValue": "\${timestamp}",
                "payloadField": "data"
            }
        },
        {
            "sns": {
                "topicArn": "${SNS_TOPIC_ARN}",
                "roleArn": "${IOT_ROLE_ARN}",
                "messageFormat": "JSON"
            }
        }
    ]
}
EOF
    
    # Create temperature rule
    if aws iot get-topic-rule --rule-name "TemperatureAlertRule" &>/dev/null; then
        log_warn "IoT rule TemperatureAlertRule already exists"
    else
        aws iot create-topic-rule \
            --rule-name "TemperatureAlertRule" \
            --topic-rule-payload file://"$TEMP_DIR/temperature-rule.json"
        log "✅ Temperature monitoring rule created"
    fi
    
    # Create motor status monitoring rule
    cat > "$TEMP_DIR/motor-rule.json" << EOF
{
    "sql": "SELECT deviceId, motorStatus, vibration, timestamp() as timestamp FROM 'factory/motors' WHERE motorStatus = 'error' OR vibration > 5.0",
    "description": "Monitor motor controllers for errors and excessive vibration",
    "ruleDisabled": false,
    "awsIotSqlVersion": "2016-03-23",
    "actions": [
        {
            "dynamodb": {
                "tableName": "${DDB_TABLE_NAME}",
                "roleArn": "${IOT_ROLE_ARN}",
                "hashKeyField": "deviceId",
                "hashKeyValue": "\${deviceId}",
                "rangeKeyField": "timestamp",
                "rangeKeyValue": "\${timestamp}",
                "payloadField": "data"
            }
        },
        {
            "lambda": {
                "functionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}",
                "invocationType": "Event"
            }
        }
    ]
}
EOF
    
    # Create motor rule
    if aws iot get-topic-rule --rule-name "MotorStatusRule" &>/dev/null; then
        log_warn "IoT rule MotorStatusRule already exists"
    else
        aws iot create-topic-rule \
            --rule-name "MotorStatusRule" \
            --topic-rule-payload file://"$TEMP_DIR/motor-rule.json"
        log "✅ Motor status monitoring rule created"
    fi
    
    # Create security event rule
    cat > "$TEMP_DIR/security-rule.json" << EOF
{
    "sql": "SELECT deviceId, eventType, severity, location, timestamp() as timestamp FROM 'factory/security' WHERE eventType IN ('intrusion', 'unauthorized_access', 'door_breach')",
    "description": "Process security events and trigger immediate alerts",
    "ruleDisabled": false,
    "awsIotSqlVersion": "2016-03-23",
    "actions": [
        {
            "sns": {
                "topicArn": "${SNS_TOPIC_ARN}",
                "roleArn": "${IOT_ROLE_ARN}",
                "messageFormat": "JSON"
            }
        },
        {
            "dynamodb": {
                "tableName": "${DDB_TABLE_NAME}",
                "roleArn": "${IOT_ROLE_ARN}",
                "hashKeyField": "deviceId",
                "hashKeyValue": "\${deviceId}",
                "rangeKeyField": "timestamp",
                "rangeKeyValue": "\${timestamp}",
                "payloadField": "data"
            }
        }
    ]
}
EOF
    
    # Create security rule
    if aws iot get-topic-rule --rule-name "SecurityEventRule" &>/dev/null; then
        log_warn "IoT rule SecurityEventRule already exists"
    else
        aws iot create-topic-rule \
            --rule-name "SecurityEventRule" \
            --topic-rule-payload file://"$TEMP_DIR/security-rule.json"
        log "✅ Security event monitoring rule created"
    fi
    
    # Create data archival rule
    cat > "$TEMP_DIR/archival-rule.json" << EOF
{
    "sql": "SELECT * FROM 'factory/+' WHERE timestamp() % 300 = 0",
    "description": "Archive all factory data every 5 minutes for historical analysis",
    "ruleDisabled": false,
    "awsIotSqlVersion": "2016-03-23",
    "actions": [
        {
            "dynamodb": {
                "tableName": "${DDB_TABLE_NAME}",
                "roleArn": "${IOT_ROLE_ARN}",
                "hashKeyField": "deviceId",
                "hashKeyValue": "\${deviceId}",
                "rangeKeyField": "timestamp",
                "rangeKeyValue": "\${timestamp}",
                "payloadField": "data"
            }
        }
    ]
}
EOF
    
    # Create archival rule
    if aws iot get-topic-rule --rule-name "DataArchivalRule" &>/dev/null; then
        log_warn "IoT rule DataArchivalRule already exists"
    else
        aws iot create-topic-rule \
            --rule-name "DataArchivalRule" \
            --topic-rule-payload file://"$TEMP_DIR/archival-rule.json"
        log "✅ Data archival rule created"
    fi
}

# Grant Lambda permissions for IoT Rules
grant_lambda_permissions() {
    log "Granting Lambda permissions for IoT Rules..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would grant Lambda permissions"
        return 0
    fi
    
    # Grant IoT permission to invoke Lambda function
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id "iot-rules-permission" \
        --action "lambda:InvokeFunction" \
        --principal "iot.amazonaws.com" \
        --source-arn "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/MotorStatusRule" \
        2>/dev/null || log_warn "Lambda permission may already exist"
    
    log "✅ Lambda permissions configured for IoT Rules"
}

# Set up CloudWatch logging
setup_cloudwatch_logging() {
    log "Setting up CloudWatch logging for IoT Rules Engine..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would set up CloudWatch logging"
        return 0
    fi
    
    # Create log group
    aws logs create-log-group \
        --log-group-name "/aws/iot/rules" \
        --tags Project=IoTRulesEngine,Environment=Production,ManagedBy=IoTRulesDeploymentScript \
        2>/dev/null || log_warn "CloudWatch log group may already exist"
    
    # Create IAM role for CloudWatch logging
    local cloudwatch_role_name="${IOT_ROLE_NAME}-logging"
    
    cat > "$TEMP_DIR/cloudwatch-trust-policy.json" << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "iot.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create logging role if it doesn't exist
    if ! aws iam get-role --role-name "$cloudwatch_role_name" &>/dev/null; then
        aws iam create-role \
            --role-name "$cloudwatch_role_name" \
            --assume-role-policy-document file://"$TEMP_DIR/cloudwatch-trust-policy.json" \
            --tags Key=Project,Value=IoTRulesEngine \
                   Key=Environment,Value=Production \
                   Key=ManagedBy,Value=IoTRulesDeploymentScript
        
        # Attach CloudWatch logs policy
        aws iam attach-role-policy \
            --role-name "$cloudwatch_role_name" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSIoTLogsRole"
    else
        log_warn "CloudWatch logging role already exists"
    fi
    
    log "✅ CloudWatch logging configured for IoT Rules Engine"
}

# Display deployment summary
display_summary() {
    log "=== Deployment Summary ==="
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "AWS Region: $AWS_REGION"
    log "Resource Prefix: $RESOURCE_PREFIX"
    log ""
    log "Created Resources:"
    log "  DynamoDB Table: $DDB_TABLE_NAME"
    log "  SNS Topic: $SNS_TOPIC_ARN"
    log "  IAM Role: $IOT_ROLE_ARN"
    log "  Lambda Function: $LAMBDA_FUNCTION_NAME"
    log "  IoT Rules: TemperatureAlertRule, MotorStatusRule, SecurityEventRule, DataArchivalRule"
    log "  CloudWatch Log Group: /aws/iot/rules"
    log ""
    log "Next Steps:"
    log "1. Subscribe to SNS topic for alerts: aws sns subscribe --topic-arn $SNS_TOPIC_ARN --protocol email --notification-endpoint your-email@example.com"
    log "2. Test the deployment by publishing test messages to IoT topics"
    log "3. Monitor CloudWatch logs for rule execution"
    log ""
    log "To clean up resources, run: ./destroy.sh"
}

# Confirmation prompt
confirm_deployment() {
    if [[ "$SKIP_CONFIRM" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "This will deploy the following resources:"
    echo "  - DynamoDB table for telemetry storage"
    echo "  - SNS topic for alerts"
    echo "  - IAM roles and policies"
    echo "  - Lambda function for event processing"
    echo "  - IoT Rules for event routing"
    echo "  - CloudWatch log group"
    echo ""
    echo "Estimated monthly cost: $5-15 for testing workloads"
    echo ""
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
}

# Main deployment function
main() {
    log "Starting IoT Rules Engine deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Generate resource names
    generate_resource_names
    
    # Show deployment plan and confirm
    confirm_deployment
    
    # Deploy resources in correct order
    create_dynamodb_table
    create_sns_topic
    create_iot_role
    create_iot_policy
    create_lambda_role
    create_lambda_function
    create_iot_rules
    grant_lambda_permissions
    setup_cloudwatch_logging
    
    # Display summary
    display_summary
    
    log "✅ IoT Rules Engine deployment completed successfully!"
    log "Deployment log saved to: $LOG_FILE"
}

# Run main function
main "$@"