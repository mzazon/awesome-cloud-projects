#!/bin/bash

# Deploy script for IoT Device Shadows State Management
# This script implements the complete deployment workflow for AWS IoT Device Shadows
# with Lambda processing and DynamoDB state history storage

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script metadata
SCRIPT_NAME="IoT Device Shadows Deployment"
SCRIPT_VERSION="1.0"
RECIPE_NAME="iot-device-shadows-state-management"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

log_step() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Error handling function
handle_error() {
    local line_number=$1
    log_error "Script failed at line $line_number"
    log_error "Deployment incomplete. Run destroy.sh to clean up partial resources."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Help function
show_help() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -d, --dry-run          Show what would be deployed without making changes
    --skip-validation      Skip prerequisite validation
    --region REGION        Override AWS region (default: from AWS CLI config)

DESCRIPTION:
    Deploys a complete IoT Device Shadows solution including:
    - IoT Thing and security certificates
    - Device Shadow with bidirectional state management
    - Lambda function for real-time shadow processing
    - DynamoDB table for state history storage
    - IoT Rules for event-driven processing

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - IAM permissions for IoT Core, Lambda, DynamoDB, and IAM
    - jq command-line JSON processor

ESTIMATED COST:
    \$5-10 per month for moderate device activity

EOF
}

# Parse command line arguments
VERBOSE=false
DRY_RUN=false
SKIP_VALIDATION=false
CUSTOM_REGION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        --region)
            CUSTOM_REGION="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validation functions
check_prerequisites() {
    log_step "Checking Prerequisites"
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $aws_version"
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check AWS permissions
    log_info "Validating AWS permissions..."
    local caller_identity=$(aws sts get-caller-identity)
    local account_id=$(echo "$caller_identity" | jq -r '.Account')
    local user_arn=$(echo "$caller_identity" | jq -r '.Arn')
    
    log_info "Deploying as: $user_arn"
    log_info "Account ID: $account_id"
    
    log_success "Prerequisites validation completed"
}

# Environment setup
setup_environment() {
    log_step "Setting Up Environment Variables"
    
    # Set AWS region
    if [[ -n "$CUSTOM_REGION" ]]; then
        export AWS_REGION="$CUSTOM_REGION"
        log_info "Using custom region: $AWS_REGION"
    else
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            export AWS_REGION="us-east-1"
            log_warning "No region configured, defaulting to us-east-1"
        fi
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Export resource names
    export THING_NAME="smart-thermostat-${random_suffix}"
    export POLICY_NAME="SmartThermostatPolicy-${random_suffix}"
    export RULE_NAME="ShadowUpdateRule-${random_suffix}"
    export LAMBDA_FUNCTION="ProcessShadowUpdate-${random_suffix}"
    export TABLE_NAME="DeviceStateHistory-${random_suffix}"
    
    # Create deployment state file for cleanup
    cat > deployment-state.json << EOF
{
    "deployment_id": "${random_suffix}",
    "thing_name": "${THING_NAME}",
    "policy_name": "${POLICY_NAME}",
    "rule_name": "${RULE_NAME}",
    "lambda_function": "${LAMBDA_FUNCTION}",
    "table_name": "${TABLE_NAME}",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "deployment_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log_success "Environment configured:"
    log_info "  Thing Name: $THING_NAME"
    log_info "  AWS Region: $AWS_REGION"
    log_info "  Account ID: $AWS_ACCOUNT_ID"
}

# Step 1: Create IoT Thing and Certificate
create_iot_thing() {
    log_step "Creating IoT Thing and Certificate"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create IoT Thing: $THING_NAME"
        return
    fi
    
    # Create the IoT Thing
    log_info "Creating IoT Thing: $THING_NAME"
    aws iot create-thing \
        --thing-name "$THING_NAME" \
        --thing-type-name "Thermostat" \
        --attribute-payload attributes='{"manufacturer":"SmartHome","model":"TH-2024"}' \
        --region "$AWS_REGION"
    
    # Generate device certificate and keys
    log_info "Generating device certificate and keys..."
    local cert_response=$(aws iot create-keys-and-certificate \
        --set-as-active \
        --output json \
        --region "$AWS_REGION")
    
    export CERT_ARN=$(echo "$cert_response" | jq -r '.certificateArn')
    export CERT_ID=$(echo "$cert_response" | jq -r '.certificateId')
    
    # Save certificate info to state file
    jq --arg cert_arn "$CERT_ARN" --arg cert_id "$CERT_ID" \
        '. + {cert_arn: $cert_arn, cert_id: $cert_id}' \
        deployment-state.json > temp.json && mv temp.json deployment-state.json
    
    log_success "IoT Thing and certificate created"
    log_info "Certificate ARN: $CERT_ARN"
}

# Step 2: Create and attach IoT policy
create_iot_policy() {
    log_step "Creating IoT Policy for Device Permissions"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create IoT policy: $POLICY_NAME"
        return
    fi
    
    # Create policy document
    log_info "Creating IoT policy document..."
    cat > device-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iot:Connect"
      ],
      "Resource": "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:client/\${iot:Connection.Thing.ThingName}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iot:Subscribe",
        "iot:Receive"
      ],
      "Resource": [
        "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topicfilter/\$aws/things/\${iot:Connection.Thing.ThingName}/shadow/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "iot:Publish"
      ],
      "Resource": [
        "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topic/\$aws/things/\${iot:Connection.Thing.ThingName}/shadow/*"
      ]
    }
  ]
}
EOF
    
    # Create the IoT policy
    log_info "Creating IoT policy: $POLICY_NAME"
    aws iot create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document file://device-policy.json \
        --region "$AWS_REGION"
    
    # Attach policy to certificate
    log_info "Attaching policy to certificate..."
    aws iot attach-policy \
        --policy-name "$POLICY_NAME" \
        --target "$CERT_ARN" \
        --region "$AWS_REGION"
    
    # Attach certificate to Thing
    log_info "Attaching certificate to Thing..."
    aws iot attach-thing-principal \
        --thing-name "$THING_NAME" \
        --principal "$CERT_ARN" \
        --region "$AWS_REGION"
    
    log_success "IoT policy created and attached"
}

# Step 3: Create DynamoDB table
create_dynamodb_table() {
    log_step "Creating DynamoDB Table for State History"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create DynamoDB table: $TABLE_NAME"
        return
    fi
    
    log_info "Creating DynamoDB table: $TABLE_NAME"
    aws dynamodb create-table \
        --table-name "$TABLE_NAME" \
        --attribute-definitions \
            AttributeName=ThingName,AttributeType=S \
            AttributeName=Timestamp,AttributeType=N \
        --key-schema \
            AttributeName=ThingName,KeyType=HASH \
            AttributeName=Timestamp,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Application,Value=IoTShadowDemo Key=Recipe,Value="$RECIPE_NAME" \
        --region "$AWS_REGION"
    
    # Wait for table to become active
    log_info "Waiting for DynamoDB table to become active..."
    aws dynamodb wait table-exists --table-name "$TABLE_NAME" --region "$AWS_REGION"
    
    log_success "DynamoDB table created and active"
}

# Step 4: Create Lambda function
create_lambda_function() {
    log_step "Creating Lambda Function for Shadow Processing"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Lambda function: $LAMBDA_FUNCTION"
        return
    fi
    
    # Create Lambda function code
    log_info "Creating Lambda function code..."
    cat > lambda-function.py << 'EOF'
import json
import boto3
import time
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        # Parse the shadow update event
        thing_name = event['thingName']
        shadow_data = event['state']
        
        # Store state change in DynamoDB
        table = dynamodb.Table(os.environ['TABLE_NAME'])
        
        # Convert float to Decimal for DynamoDB
        def convert_floats(obj):
            if isinstance(obj, float):
                return Decimal(str(obj))
            elif isinstance(obj, dict):
                return {k: convert_floats(v) for k, v in obj.items()}
            elif isinstance(obj, list):
                return [convert_floats(v) for v in obj]
            return obj
        
        item = {
            'ThingName': thing_name,
            'Timestamp': int(time.time()),
            'ShadowState': convert_floats(shadow_data),
            'EventType': 'shadow_update'
        }
        
        table.put_item(Item=item)
        
        print(f"Processed shadow update for {thing_name}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed shadow update')
        }
        
    except Exception as e:
        print(f"Error processing shadow update: {str(e)}")
        raise
EOF
    
    # Package the function
    log_info "Packaging Lambda function..."
    zip lambda-function.zip lambda-function.py
    
    # Create IAM role for Lambda
    log_info "Creating IAM role for Lambda execution..."
    create_lambda_iam_role
    
    # Wait for IAM role propagation
    sleep 10
    
    # Create Lambda function
    log_info "Creating Lambda function: $LAMBDA_FUNCTION"
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_FUNCTION}-role" \
        --handler lambda-function.lambda_handler \
        --zip-file fileb://lambda-function.zip \
        --timeout 30 \
        --memory-size 128 \
        --environment Variables="{TABLE_NAME=${TABLE_NAME}}" \
        --tags Recipe="$RECIPE_NAME",Application=IoTShadowDemo \
        --region "$AWS_REGION"
    
    export LAMBDA_ARN=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION" \
        --query 'Configuration.FunctionArn' --output text \
        --region "$AWS_REGION")
    
    # Save Lambda ARN to state file
    jq --arg lambda_arn "$LAMBDA_ARN" \
        '. + {lambda_arn: $lambda_arn}' \
        deployment-state.json > temp.json && mv temp.json deployment-state.json
    
    log_success "Lambda function created successfully"
    log_info "Function ARN: $LAMBDA_ARN"
}

# Helper function to create Lambda IAM role
create_lambda_iam_role() {
    # Create trust policy for Lambda
    cat > lambda-trust-policy.json << EOF
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
    
    # Create execution policy for Lambda
    cat > lambda-execution-policy.json << EOF
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
      "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:UpdateItem"
      ],
      "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${TABLE_NAME}"
    }
  ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name "${LAMBDA_FUNCTION}-role" \
        --assume-role-policy-document file://lambda-trust-policy.json \
        --tags Key=Recipe,Value="$RECIPE_NAME" Key=Application,Value=IoTShadowDemo
    
    # Create and attach policy
    aws iam create-policy \
        --policy-name "${LAMBDA_FUNCTION}-policy" \
        --policy-document file://lambda-execution-policy.json \
        --tags Key=Recipe,Value="$RECIPE_NAME" Key=Application,Value=IoTShadowDemo
    
    export POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_FUNCTION}-policy"
    
    aws iam attach-role-policy \
        --role-name "${LAMBDA_FUNCTION}-role" \
        --policy-arn "$POLICY_ARN"
    
    # Save policy ARN to state file
    jq --arg policy_arn "$POLICY_ARN" \
        '. + {policy_arn: $policy_arn}' \
        deployment-state.json > temp.json && mv temp.json deployment-state.json
}

# Step 5: Create IoT Rule
create_iot_rule() {
    log_step "Creating IoT Rule for Shadow Updates"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create IoT rule: $RULE_NAME"
        return
    fi
    
    # Create IoT rule for shadow updates
    log_info "Creating IoT rule configuration..."
    cat > iot-rule.json << EOF
{
  "sql": "SELECT * FROM '\$aws/things/+/shadow/update/accepted'",
  "description": "Process Device Shadow updates",
  "actions": [
    {
      "lambda": {
        "functionArn": "${LAMBDA_ARN}"
      }
    }
  ],
  "ruleDisabled": false
}
EOF
    
    # Create the IoT rule
    log_info "Creating IoT rule: $RULE_NAME"
    aws iot create-topic-rule \
        --rule-name "$RULE_NAME" \
        --topic-rule-payload file://iot-rule.json \
        --region "$AWS_REGION"
    
    # Grant IoT permission to invoke Lambda
    log_info "Granting IoT permission to invoke Lambda function..."
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION" \
        --statement-id "AllowIoTInvoke" \
        --action lambda:InvokeFunction \
        --principal iot.amazonaws.com \
        --source-arn "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${RULE_NAME}" \
        --region "$AWS_REGION"
    
    log_success "IoT rule created for shadow processing"
}

# Step 6: Initialize Device Shadow
initialize_device_shadow() {
    log_step "Initializing Device Shadow"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would initialize device shadow for: $THING_NAME"
        return
    fi
    
    # Create initial shadow document
    log_info "Creating initial shadow document..."
    cat > initial-shadow.json << EOF
{
  "state": {
    "reported": {
      "temperature": 22.5,
      "humidity": 45,
      "hvac_mode": "heat",
      "target_temperature": 23.0,
      "firmware_version": "1.2.3",
      "connectivity": "online"
    },
    "desired": {
      "target_temperature": 23.0,
      "hvac_mode": "auto"
    }
  }
}
EOF
    
    # Update the device shadow
    log_info "Updating device shadow..."
    aws iot-data update-thing-shadow \
        --thing-name "$THING_NAME" \
        --payload file://initial-shadow.json \
        initial-shadow-response.json \
        --region "$AWS_REGION"
    
    log_success "Device shadow initialized"
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Initial shadow state:"
        cat initial-shadow-response.json | jq '.'
    fi
}

# Validation function
validate_deployment() {
    log_step "Validating Deployment"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate deployment"
        return
    fi
    
    local validation_errors=0
    
    # Check IoT Thing
    log_info "Validating IoT Thing..."
    if aws iot describe-thing --thing-name "$THING_NAME" --region "$AWS_REGION" &>/dev/null; then
        log_success "IoT Thing validation passed"
    else
        log_error "IoT Thing validation failed"
        ((validation_errors++))
    fi
    
    # Check DynamoDB table
    log_info "Validating DynamoDB table..."
    local table_status=$(aws dynamodb describe-table --table-name "$TABLE_NAME" --query 'Table.TableStatus' --output text --region "$AWS_REGION" 2>/dev/null || echo "ERROR")
    if [[ "$table_status" == "ACTIVE" ]]; then
        log_success "DynamoDB table validation passed"
    else
        log_error "DynamoDB table validation failed (Status: $table_status)"
        ((validation_errors++))
    fi
    
    # Check Lambda function
    log_info "Validating Lambda function..."
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION" --region "$AWS_REGION" &>/dev/null; then
        log_success "Lambda function validation passed"
    else
        log_error "Lambda function validation failed"
        ((validation_errors++))
    fi
    
    # Check IoT rule
    log_info "Validating IoT rule..."
    if aws iot get-topic-rule --rule-name "$RULE_NAME" --region "$AWS_REGION" &>/dev/null; then
        log_success "IoT rule validation passed"
    else
        log_error "IoT rule validation failed"
        ((validation_errors++))
    fi
    
    # Check device shadow
    log_info "Validating device shadow..."
    if aws iot-data get-thing-shadow --thing-name "$THING_NAME" shadow-validation.json --region "$AWS_REGION" &>/dev/null; then
        log_success "Device shadow validation passed"
        rm -f shadow-validation.json
    else
        log_error "Device shadow validation failed"
        ((validation_errors++))
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log_success "All validations passed"
    else
        log_error "$validation_errors validation(s) failed"
        return 1
    fi
}

# Cleanup temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    rm -f device-policy.json lambda-trust-policy.json lambda-execution-policy.json
    rm -f iot-rule.json initial-shadow.json lambda-function.py lambda-function.zip
    rm -f initial-shadow-response.json shadow-validation.json
}

# Main deployment function
main() {
    log_info "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    log_info "Recipe: $RECIPE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be created"
    fi
    
    # Run deployment steps
    if [[ "$SKIP_VALIDATION" != "true" ]]; then
        check_prerequisites
    fi
    
    setup_environment
    create_iot_thing
    create_iot_policy
    create_dynamodb_table
    create_lambda_function
    create_iot_rule
    initialize_device_shadow
    
    if [[ "$DRY_RUN" != "true" ]]; then
        validate_deployment
    fi
    
    cleanup_temp_files
    
    # Display completion message
    log_success "Deployment completed successfully!"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo
        log_info "Deployment Summary:"
        log_info "  IoT Thing: $THING_NAME"
        log_info "  DynamoDB Table: $TABLE_NAME"
        log_info "  Lambda Function: $LAMBDA_FUNCTION"
        log_info "  IoT Rule: $RULE_NAME"
        log_info "  AWS Region: $AWS_REGION"
        echo
        log_info "Test your deployment:"
        log_info "  aws iot-data get-thing-shadow --thing-name $THING_NAME shadow-test.json --region $AWS_REGION"
        echo
        log_info "To clean up resources, run: ./destroy.sh"
        echo
        log_warning "Estimated monthly cost: \$5-10 for moderate device activity"
    fi
}

# Run main function
main "$@"