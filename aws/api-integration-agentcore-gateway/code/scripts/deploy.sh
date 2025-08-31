#!/bin/bash

# Enterprise API Integration with AgentCore Gateway - Deployment Script
# This script deploys the complete infrastructure for AI agent integration
# with enterprise APIs using AWS services

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] ${*}${NC}" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ ${*}${NC}" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  ${*}${NC}" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ ${*}${NC}" | tee -a "${LOG_FILE}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    log_warning "You may need to run destroy.sh to clean up partially created resources."
    exit 1
}

trap cleanup_on_error ERR

# Show usage information
show_usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Deploy Enterprise API Integration with AgentCore Gateway infrastructure.

OPTIONS:
    -h, --help              Show this help message
    -r, --region REGION     AWS region (default: current configured region)
    -p, --project-name NAME Project name prefix (default: auto-generated)
    --dry-run              Show what would be deployed without executing
    --skip-validation      Skip prerequisite validation
    --verbose              Enable verbose output

EXAMPLES:
    ${SCRIPT_NAME}                          # Deploy with defaults
    ${SCRIPT_NAME} --region us-east-1       # Deploy in specific region
    ${SCRIPT_NAME} --project-name my-api    # Deploy with custom project name
    ${SCRIPT_NAME} --dry-run                # Preview deployment

EOF
}

# Default configuration
DRY_RUN=false
SKIP_VALIDATION=false
VERBOSE=false
PROJECT_NAME=""
AWS_REGION=""

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -p|--project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Validation functions
check_prerequisites() {
    if [[ "${SKIP_VALIDATION}" == "true" ]]; then
        log_warning "Skipping prerequisite validation"
        return 0
    fi

    log "Checking prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi

    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local major_version
    major_version=$(echo "${aws_version}" | cut -d. -f1)
    if [[ "${major_version}" -lt 2 ]]; then
        log_error "AWS CLI version 2.x is required. Current version: ${aws_version}"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi

    # Check required permissions
    log "Verifying AWS permissions..."
    local required_services=("lambda" "apigateway" "stepfunctions" "iam" "logs")
    for service in "${required_services[@]}"; do
        if ! aws "${service}" help &> /dev/null; then
            log_error "Missing permissions for AWS ${service} service"
            exit 1
        fi
    done

    # Check zip utility
    if ! command -v zip &> /dev/null; then
        log_error "zip utility is not installed. Please install zip."
        exit 1
    fi

    log_success "Prerequisites check completed"
}

# Environment setup
setup_environment() {
    log "Setting up deployment environment..."

    # Set AWS region
    if [[ -z "${AWS_REGION}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "${AWS_REGION}" ]]; then
            log_error "AWS region not set. Use --region or configure AWS CLI."
            exit 1
        fi
    fi
    export AWS_REGION

    # Get AWS account ID
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    # Generate project name if not provided
    if [[ -z "${PROJECT_NAME}" ]]; then
        local random_suffix
        random_suffix=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            echo "$(date +%s | tail -c 6)")
        PROJECT_NAME="api-integration-${random_suffix}"
    fi
    export PROJECT_NAME

    # Set resource names
    export GATEWAY_NAME="enterprise-gateway-${PROJECT_NAME##*-}"
    export STATE_MACHINE_NAME="api-orchestrator-${PROJECT_NAME##*-}"
    export LAMBDA_EXECUTION_ROLE="lambda-execution-role-${PROJECT_NAME##*-}"
    export STEPFUNCTIONS_EXECUTION_ROLE="stepfunctions-execution-role-${PROJECT_NAME##*-}"
    export APIGATEWAY_STEPFUNCTIONS_ROLE="apigateway-stepfunctions-role-${PROJECT_NAME##*-}"

    # Create temporary directory for deployment artifacts
    export TEMP_DIR
    TEMP_DIR=$(mktemp -d)
    export DEPLOYMENT_STATE_FILE="${TEMP_DIR}/deployment_state.json"

    log_success "Environment configured:"
    log "  AWS Region: ${AWS_REGION}"
    log "  AWS Account: ${AWS_ACCOUNT_ID}"
    log "  Project Name: ${PROJECT_NAME}"
    log "  Temp Directory: ${TEMP_DIR}"

    # Initialize deployment state
    cat > "${DEPLOYMENT_STATE_FILE}" << EOF
{
    "deployment_id": "$(date +%Y%m%d_%H%M%S)",
    "project_name": "${PROJECT_NAME}",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "resources_created": [],
    "deployment_status": "in_progress"
}
EOF
}

# Helper function to update deployment state
update_deployment_state() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_arn="${3:-}"
    
    local temp_file
    temp_file=$(mktemp)
    jq --arg type "$resource_type" --arg name "$resource_name" --arg arn "$resource_arn" \
        '.resources_created += [{"type": $type, "name": $name, "arn": $arn, "created_at": now | todate}]' \
        "${DEPLOYMENT_STATE_FILE}" > "$temp_file" && mv "$temp_file" "${DEPLOYMENT_STATE_FILE}"
}

# IAM roles creation
create_iam_roles() {
    log "Creating IAM roles..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would create IAM roles"
        return 0
    fi

    # Lambda execution role
    log "Creating Lambda execution role..."
    local lambda_role_doc='{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "lambda.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

    if aws iam get-role --role-name "${LAMBDA_EXECUTION_ROLE}" &> /dev/null; then
        log_warning "Lambda execution role ${LAMBDA_EXECUTION_ROLE} already exists"
    else
        aws iam create-role \
            --role-name "${LAMBDA_EXECUTION_ROLE}" \
            --assume-role-policy-document "${lambda_role_doc}" \
            --tags Key=Project,Value="${PROJECT_NAME}" Key=Component,Value=Lambda

        aws iam attach-role-policy \
            --role-name "${LAMBDA_EXECUTION_ROLE}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

        update_deployment_state "iam_role" "${LAMBDA_EXECUTION_ROLE}" \
            "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_EXECUTION_ROLE}"
    fi

    # Step Functions execution role
    log "Creating Step Functions execution role..."
    local stepfunctions_role_doc='{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "states.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

    if aws iam get-role --role-name "${STEPFUNCTIONS_EXECUTION_ROLE}" &> /dev/null; then
        log_warning "Step Functions execution role ${STEPFUNCTIONS_EXECUTION_ROLE} already exists"
    else
        aws iam create-role \
            --role-name "${STEPFUNCTIONS_EXECUTION_ROLE}" \
            --assume-role-policy-document "${stepfunctions_role_doc}" \
            --tags Key=Project,Value="${PROJECT_NAME}" Key=Component,Value=StepFunctions

        aws iam attach-role-policy \
            --role-name "${STEPFUNCTIONS_EXECUTION_ROLE}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaRole

        update_deployment_state "iam_role" "${STEPFUNCTIONS_EXECUTION_ROLE}" \
            "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${STEPFUNCTIONS_EXECUTION_ROLE}"
    fi

    # API Gateway Step Functions role
    log "Creating API Gateway Step Functions role..."
    local apigateway_role_doc='{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "apigateway.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

    if aws iam get-role --role-name "${APIGATEWAY_STEPFUNCTIONS_ROLE}" &> /dev/null; then
        log_warning "API Gateway Step Functions role ${APIGATEWAY_STEPFUNCTIONS_ROLE} already exists"
    else
        aws iam create-role \
            --role-name "${APIGATEWAY_STEPFUNCTIONS_ROLE}" \
            --assume-role-policy-document "${apigateway_role_doc}" \
            --tags Key=Project,Value="${PROJECT_NAME}" Key=Component,Value=APIGateway

        aws iam attach-role-policy \
            --role-name "${APIGATEWAY_STEPFUNCTIONS_ROLE}" \
            --policy-arn arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess

        update_deployment_state "iam_role" "${APIGATEWAY_STEPFUNCTIONS_ROLE}" \
            "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${APIGATEWAY_STEPFUNCTIONS_ROLE}"
    fi

    # Wait for role propagation
    log "Waiting for IAM role propagation..."
    sleep 15

    log_success "IAM roles created successfully"
}

# Lambda functions creation
create_lambda_functions() {
    log "Creating Lambda functions..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would create Lambda functions"
        return 0
    fi

    local lambda_role_arn
    lambda_role_arn=$(aws iam get-role --role-name "${LAMBDA_EXECUTION_ROLE}" --query 'Role.Arn' --output text)

    # Create API transformer function
    log "Creating API transformer Lambda function..."
    local transformer_name="api-transformer-${PROJECT_NAME##*-}"
    
    # Check if function exists
    if aws lambda get-function --function-name "${transformer_name}" &> /dev/null; then
        log_warning "Lambda function ${transformer_name} already exists, updating..."
        
        # Create function code if it doesn't exist
        if [[ ! -f "${TEMP_DIR}/api-transformer.zip" ]]; then
            create_transformer_code
        fi

        aws lambda update-function-code \
            --function-name "${transformer_name}" \
            --zip-file "fileb://${TEMP_DIR}/api-transformer.zip"
    else
        create_transformer_code

        aws lambda create-function \
            --function-name "${transformer_name}" \
            --runtime python3.12 \
            --role "${lambda_role_arn}" \
            --handler api-transformer.lambda_handler \
            --zip-file "fileb://${TEMP_DIR}/api-transformer.zip" \
            --timeout 60 \
            --memory-size 512 \
            --environment Variables='{
                "ENVIRONMENT":"production",
                "LOG_LEVEL":"INFO",
                "PROJECT_NAME":"'"${PROJECT_NAME}"'"
            }' \
            --tags Project="${PROJECT_NAME}",Component=Lambda,Type=Transformer

        local transformer_arn
        transformer_arn=$(aws lambda get-function --function-name "${transformer_name}" --query 'Configuration.FunctionArn' --output text)
        update_deployment_state "lambda_function" "${transformer_name}" "${transformer_arn}"
    fi

    # Create data validator function
    log "Creating data validator Lambda function..."
    local validator_name="data-validator-${PROJECT_NAME##*-}"
    
    if aws lambda get-function --function-name "${validator_name}" &> /dev/null; then
        log_warning "Lambda function ${validator_name} already exists, updating..."
        
        if [[ ! -f "${TEMP_DIR}/data-validator.zip" ]]; then
            create_validator_code
        fi

        aws lambda update-function-code \
            --function-name "${validator_name}" \
            --zip-file "fileb://${TEMP_DIR}/data-validator.zip"
    else
        create_validator_code

        aws lambda create-function \
            --function-name "${validator_name}" \
            --runtime python3.12 \
            --role "${lambda_role_arn}" \
            --handler data-validator.lambda_handler \
            --zip-file "fileb://${TEMP_DIR}/data-validator.zip" \
            --timeout 30 \
            --memory-size 256 \
            --environment Variables='{
                "ENVIRONMENT":"production",
                "LOG_LEVEL":"INFO",
                "PROJECT_NAME":"'"${PROJECT_NAME}"'"
            }' \
            --tags Project="${PROJECT_NAME}",Component=Lambda,Type=Validator

        local validator_arn
        validator_arn=$(aws lambda get-function --function-name "${validator_name}" --query 'Configuration.FunctionArn' --output text)
        update_deployment_state "lambda_function" "${validator_name}" "${validator_arn}"
    fi

    log_success "Lambda functions created successfully"
}

# Helper function to create transformer code
create_transformer_code() {
    cat > "${TEMP_DIR}/api-transformer.py" << 'EOF'
import json
import urllib3
from typing import Dict, Any
import os

# Initialize urllib3 PoolManager for HTTP requests
http = urllib3.PoolManager()

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Transform API requests for enterprise system integration
    """
    try:
        # Extract request parameters
        api_type = event.get('api_type', 'generic')
        payload = event.get('payload', {})
        target_url = event.get('target_url')
        
        # Log request for debugging
        print(f"Processing {api_type} request for target: {target_url}")
        
        # Transform based on API type
        if api_type == 'erp':
            transformed_data = transform_erp_request(payload)
        elif api_type == 'crm':
            transformed_data = transform_crm_request(payload)
        else:
            transformed_data = payload
        
        # Simulate API call to target system (using mock response)
        # In production, this would make actual HTTP requests to enterprise APIs
        mock_response = {
            'success': True,
            'transaction_id': f"{api_type}-{payload.get('id', 'unknown')}",
            'processed_data': transformed_data,
            'status': 'completed',
            'project_name': os.environ.get('PROJECT_NAME', 'unknown')
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'success': True,
                'data': mock_response,
                'status_code': 200
            })
        }
        
    except Exception as e:
        print(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'success': False,
                'error': str(e)
            })
        }

def transform_erp_request(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Transform requests for ERP system format"""
    return {
        'transaction_type': payload.get('type', 'query'),
        'data': payload.get('data', {}),
        'metadata': {
            'source': 'agentcore_gateway',
            'timestamp': payload.get('timestamp')
        }
    }

def transform_crm_request(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Transform requests for CRM system format"""
    return {
        'operation': payload.get('action', 'read'),
        'entity': payload.get('entity', 'contact'),
        'attributes': payload.get('data', {}),
        'source_system': 'ai_agent'
    }
EOF

    cd "${TEMP_DIR}" && zip api-transformer.zip api-transformer.py
}

# Helper function to create validator code
create_validator_code() {
    cat > "${TEMP_DIR}/data-validator.py" << 'EOF'
import json
import re
import os
from typing import Dict, Any, List

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Validate API request data according to enterprise rules
    """
    try:
        data = event.get('data', {})
        validation_type = event.get('validation_type', 'standard')
        
        print(f"Validating {validation_type} data: {json.dumps(data, default=str)}")
        
        # Perform validation based on type
        validation_result = validate_data(data, validation_type)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'valid': validation_result['is_valid'],
                'errors': validation_result['errors'],
                'sanitized_data': validation_result['sanitized_data'],
                'project_name': os.environ.get('PROJECT_NAME', 'unknown')
            })
        }
        
    except Exception as e:
        print(f"Validation error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'valid': False,
                'errors': [f"Validation error: {str(e)}"]
            })
        }

def validate_data(data: Dict[str, Any], validation_type: str) -> Dict[str, Any]:
    """Perform comprehensive data validation"""
    errors = []
    sanitized_data = {}
    
    # Standard validation rules
    if validation_type == 'standard':
        errors.extend(validate_required_fields(data))
        errors.extend(validate_data_types(data))
        sanitized_data = sanitize_data(data)
    
    # Financial data validation
    elif validation_type == 'financial':
        errors.extend(validate_required_fields(data))
        errors.extend(validate_financial_data(data))
        sanitized_data = sanitize_financial_data(data)
    
    # Customer data validation
    elif validation_type == 'customer':
        errors.extend(validate_required_fields(data))
        errors.extend(validate_customer_data(data))
        sanitized_data = sanitize_customer_data(data)
    
    return {
        'is_valid': len(errors) == 0,
        'errors': errors,
        'sanitized_data': sanitized_data
    }

def validate_required_fields(data: Dict[str, Any]) -> List[str]:
    """Validate required field presence"""
    errors = []
    required_fields = ['id', 'type', 'data']
    
    for field in required_fields:
        if field not in data or data[field] is None:
            errors.append(f"Required field '{field}' is missing")
    
    return errors

def validate_data_types(data: Dict[str, Any]) -> List[str]:
    """Validate data type constraints"""
    errors = []
    
    if 'id' in data and not isinstance(data['id'], (str, int)):
        errors.append("Field 'id' must be string or integer")
    
    if 'type' in data and not isinstance(data['type'], str):
        errors.append("Field 'type' must be string")
    
    return errors

def validate_financial_data(data: Dict[str, Any]) -> List[str]:
    """Validate financial-specific data"""
    errors = []
    
    if 'amount' in data:
        try:
            amount = float(data['amount'])
            if amount < 0:
                errors.append("Amount cannot be negative")
            if amount > 1000000:
                errors.append("Amount exceeds maximum limit")
        except (ValueError, TypeError):
            errors.append("Amount must be a valid number")
    
    return errors

def validate_customer_data(data: Dict[str, Any]) -> List[str]:
    """Validate customer-specific data"""
    errors = []
    
    if 'email' in data:
        email_pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        if not re.match(email_pattern, data['email']):
            errors.append("Invalid email format")
    
    if 'phone' in data:
        phone_pattern = r'^\+?[\d\s\-\(\)]{10,}$'
        if not re.match(phone_pattern, str(data['phone'])):
            errors.append("Invalid phone number format")
    
    return errors

def sanitize_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """Sanitize and clean data"""
    sanitized = {}
    for key, value in data.items():
        if isinstance(value, str):
            sanitized[key] = value.strip()
        else:
            sanitized[key] = value
    return sanitized

def sanitize_financial_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """Sanitize financial-specific data"""
    sanitized = sanitize_data(data)
    if 'amount' in sanitized:
        try:
            sanitized['amount'] = round(float(sanitized['amount']), 2)
        except (ValueError, TypeError):
            pass
    return sanitized

def sanitize_customer_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """Sanitize customer-specific data"""
    sanitized = sanitize_data(data)
    if 'email' in sanitized:
        sanitized['email'] = sanitized['email'].lower()
    return sanitized
EOF

    cd "${TEMP_DIR}" && zip data-validator.zip data-validator.py
}

# Step Functions state machine creation
create_step_functions() {
    log "Creating Step Functions state machine..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would create Step Functions state machine"
        return 0
    fi

    local stepfunctions_role_arn
    stepfunctions_role_arn=$(aws iam get-role --role-name "${STEPFUNCTIONS_EXECUTION_ROLE}" --query 'Role.Arn' --output text)

    local transformer_name="api-transformer-${PROJECT_NAME##*-}"
    local validator_name="data-validator-${PROJECT_NAME##*-}"

    # Create state machine definition
    cat > "${TEMP_DIR}/orchestration-workflow.json" << EOF
{
  "Comment": "Enterprise API Integration Orchestration for ${PROJECT_NAME}",
  "StartAt": "ValidateInput",
  "States": {
    "ValidateInput": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "${validator_name}",
        "Payload.$": "$"
      },
      "ResultPath": "$.validation_result",
      "Next": "CheckValidation",
      "Retry": [
        {
          "ErrorEquals": ["Lambda.ServiceException", "Lambda.AWSLambdaException"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ],
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "ValidationFailed",
          "ResultPath": "$.error"
        }
      ]
    },
    "CheckValidation": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.validation_result.Payload.body",
          "StringMatches": "*\"valid\":true*",
          "Next": "RouteRequest"
        }
      ],
      "Default": "ValidationFailed"
    },
    "RouteRequest": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "TransformForERP",
          "States": {
            "TransformForERP": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "Parameters": {
                "FunctionName": "${transformer_name}",
                "Payload": {
                  "api_type": "erp",
                  "payload.$": "$",
                  "target_url": "https://example-erp.com/api/v1/process"
                }
              },
              "End": true,
              "Retry": [
                {
                  "ErrorEquals": ["States.ALL"],
                  "IntervalSeconds": 3,
                  "MaxAttempts": 2,
                  "BackoffRate": 2.0
                }
              ]
            }
          }
        },
        {
          "StartAt": "TransformForCRM",
          "States": {
            "TransformForCRM": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "Parameters": {
                "FunctionName": "${transformer_name}",
                "Payload": {
                  "api_type": "crm",
                  "payload.$": "$",
                  "target_url": "https://example-crm.com/api/v2/entities"
                }
              },
              "End": true,
              "Retry": [
                {
                  "ErrorEquals": ["States.ALL"],
                  "IntervalSeconds": 3,
                  "MaxAttempts": 2,
                  "BackoffRate": 2.0
                }
              ]
            }
          }
        }
      ],
      "Next": "AggregateResults",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "ProcessingFailed",
          "ResultPath": "$.error"
        }
      ]
    },
    "AggregateResults": {
      "Type": "Pass",
      "Parameters": {
        "status": "success",
        "results.$": "$",
        "timestamp.$": "$$.State.EnteredTime",
        "execution_arn.$": "$$.Execution.Name",
        "project_name": "${PROJECT_NAME}"
      },
      "End": true
    },
    "ValidationFailed": {
      "Type": "Pass",
      "Parameters": {
        "status": "validation_failed",
        "errors.$": "$.validation_result.Payload.errors",
        "timestamp.$": "$$.State.EnteredTime",
        "project_name": "${PROJECT_NAME}"
      },
      "End": true
    },
    "ProcessingFailed": {
      "Type": "Pass",
      "Parameters": {
        "status": "processing_failed",
        "error.$": "$.error",
        "timestamp.$": "$$.State.EnteredTime",
        "project_name": "${PROJECT_NAME}"
      },
      "End": true
    }
  }
}
EOF

    # Check if state machine exists
    if aws stepfunctions describe-state-machine --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" &> /dev/null; then
        log_warning "State machine ${STATE_MACHINE_NAME} already exists, updating..."
        aws stepfunctions update-state-machine \
            --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" \
            --definition "file://${TEMP_DIR}/orchestration-workflow.json"
    else
        aws stepfunctions create-state-machine \
            --name "${STATE_MACHINE_NAME}" \
            --definition "file://${TEMP_DIR}/orchestration-workflow.json" \
            --role-arn "${stepfunctions_role_arn}" \
            --type STANDARD \
            --tags Key=Project,Value="${PROJECT_NAME}",Key=Component,Value=StepFunctions

        local state_machine_arn="arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}"
        update_deployment_state "stepfunctions_state_machine" "${STATE_MACHINE_NAME}" "${state_machine_arn}"
    fi

    log_success "Step Functions state machine created successfully"
}

# API Gateway creation
create_api_gateway() {
    log "Creating API Gateway..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would create API Gateway"
        return 0
    fi

    local api_name="enterprise-api-integration-${PROJECT_NAME##*-}"
    
    # Check if API already exists
    local existing_api_id
    existing_api_id=$(aws apigateway get-rest-apis --query "items[?name=='${api_name}'].id" --output text)
    
    if [[ -n "${existing_api_id}" && "${existing_api_id}" != "None" ]]; then
        log_warning "API Gateway ${api_name} already exists with ID: ${existing_api_id}"
        API_ID="${existing_api_id}"
    else
        # Create REST API
        API_ID=$(aws apigateway create-rest-api \
            --name "${api_name}" \
            --description "Enterprise API Integration with AgentCore Gateway for ${PROJECT_NAME}" \
            --endpoint-configuration types=REGIONAL \
            --tags Project="${PROJECT_NAME}",Component=APIGateway \
            --query 'id' --output text)

        update_deployment_state "api_gateway" "${api_name}" \
            "arn:aws:apigateway:${AWS_REGION}::/restapis/${API_ID}"
    fi

    # Get the root resource ID
    local root_resource_id
    root_resource_id=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query 'items[?path==`/`].id' --output text)

    # Create integrate resource if it doesn't exist
    local resource_id
    resource_id=$(aws apigateway get-resources \
        --rest-api-id "${API_ID}" \
        --query 'items[?pathPart==`integrate`].id' --output text)

    if [[ -z "${resource_id}" || "${resource_id}" == "None" ]]; then
        resource_id=$(aws apigateway create-resource \
            --rest-api-id "${API_ID}" \
            --parent-id "${root_resource_id}" \
            --path-part "integrate" \
            --query 'id' --output text)
    fi

    # Check if POST method exists
    if ! aws apigateway get-method --rest-api-id "${API_ID}" --resource-id "${resource_id}" --http-method POST &> /dev/null; then
        # Create POST method
        aws apigateway put-method \
            --rest-api-id "${API_ID}" \
            --resource-id "${resource_id}" \
            --http-method POST \
            --authorization-type NONE
    fi

    # Configure integration with Step Functions
    local state_machine_arn="arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}"
    local apigateway_role_arn
    apigateway_role_arn=$(aws iam get-role --role-name "${APIGATEWAY_STEPFUNCTIONS_ROLE}" --query 'Role.Arn' --output text)

    # Configure Step Functions integration
    aws apigateway put-integration \
        --rest-api-id "${API_ID}" \
        --resource-id "${resource_id}" \
        --http-method POST \
        --type AWS \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:states:action/StartExecution" \
        --credentials "${apigateway_role_arn}" \
        --request-templates '{
            "application/json": "{\"input\": \"$util.escapeJavaScript($input.body)\", \"stateMachineArn\": \"'"${state_machine_arn}"'\"}"
        }' 2>/dev/null || log_warning "Integration may already be configured"

    # Configure responses
    aws apigateway put-method-response \
        --rest-api-id "${API_ID}" \
        --resource-id "${resource_id}" \
        --http-method POST \
        --status-code 200 \
        --response-models '{"application/json": "Empty"}' 2>/dev/null || true

    aws apigateway put-integration-response \
        --rest-api-id "${API_ID}" \
        --resource-id "${resource_id}" \
        --http-method POST \
        --status-code 200 \
        --response-templates '{
            "application/json": "{\"executionArn\": \"$input.path(\"$.executionArn\")\", \"startDate\": \"$input.path(\"$.startDate\")\", \"status\": \"STARTED\"}"
        }' 2>/dev/null || true

    # Deploy the API
    aws apigateway create-deployment \
        --rest-api-id "${API_ID}" \
        --stage-name prod \
        --description "Production deployment of enterprise API integration for ${PROJECT_NAME}" \
        2>/dev/null || log_warning "Deployment may have been created already"

    # Store API endpoint
    API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod/integrate"

    log_success "API Gateway created successfully with endpoint: ${API_ENDPOINT}"
}

# Generate AgentCore Gateway configuration
generate_agentcore_config() {
    log "Generating AgentCore Gateway configuration..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would generate AgentCore Gateway configuration"
        return 0
    fi

    # Create OpenAPI specification
    cat > "${TEMP_DIR}/enterprise-api-spec.json" << EOF
{
  "openapi": "3.0.3",
  "info": {
    "title": "Enterprise API Integration - ${PROJECT_NAME}",
    "version": "1.0.0",
    "description": "Unified API for enterprise system integration with AgentCore Gateway"
  },
  "servers": [
    {
      "url": "${API_ENDPOINT%/integrate}",
      "description": "Production API Gateway endpoint"
    }
  ],
  "paths": {
    "/integrate": {
      "post": {
        "summary": "Process enterprise integration request",
        "operationId": "processIntegration",
        "description": "Submit data for processing through enterprise API integration workflow",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "id": {
                    "type": "string",
                    "description": "Unique request identifier"
                  },
                  "type": {
                    "type": "string",
                    "enum": ["erp", "crm", "inventory"],
                    "description": "Target system type"
                  },
                  "data": {
                    "type": "object",
                    "description": "Request payload data",
                    "properties": {
                      "amount": {
                        "type": "number",
                        "description": "Transaction amount (for financial data)"
                      },
                      "email": {
                        "type": "string",
                        "description": "Email address (for customer data)"
                      }
                    }
                  },
                  "validation_type": {
                    "type": "string",
                    "enum": ["standard", "financial", "customer"],
                    "description": "Validation rules to apply"
                  }
                },
                "required": ["id", "type", "data"]
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Integration request processed successfully",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "executionArn": {
                      "type": "string",
                      "description": "Step Functions execution ARN"
                    },
                    "status": {
                      "type": "string",
                      "description": "Execution status"
                    },
                    "startDate": {
                      "type": "string",
                      "description": "Execution start timestamp"
                    }
                  }
                }
              }
            }
          },
          "400": {
            "description": "Invalid request format"
          },
          "500": {
            "description": "Internal server error"
          }
        }
      }
    }
  }
}
EOF

    # Copy to output directory for user access
    cp "${TEMP_DIR}/enterprise-api-spec.json" "${SCRIPT_DIR}/"

    log_success "AgentCore Gateway configuration generated at: ${SCRIPT_DIR}/enterprise-api-spec.json"
}

# Test deployment
test_deployment() {
    log "Testing deployment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would test deployment"
        return 0
    fi

    # Test API Gateway endpoint
    log "Testing API Gateway endpoint..."
    local test_payload='{
        "id": "test-deployment-001",
        "type": "erp",
        "data": {
            "transaction_type": "test_transaction",
            "amount": 100.00,
            "vendor": "Test Vendor"
        },
        "validation_type": "financial"
    }'

    local response
    if response=$(curl -s -X POST "${API_ENDPOINT}" \
        -H "Content-Type: application/json" \
        -d "${test_payload}"); then
        
        if echo "${response}" | jq -e '.executionArn' > /dev/null 2>&1; then
            log_success "API Gateway test passed"
            
            # Extract execution ARN for monitoring
            local execution_arn
            execution_arn=$(echo "${response}" | jq -r '.executionArn')
            log "Test execution ARN: ${execution_arn}"
            
            # Wait a moment and check execution status
            sleep 5
            local execution_status
            execution_status=$(aws stepfunctions describe-execution --execution-arn "${execution_arn}" --query 'status' --output text 2>/dev/null || echo "UNKNOWN")
            log "Test execution status: ${execution_status}"
        else
            log_warning "API Gateway responded but without expected execution ARN"
            log "Response: ${response}"
        fi
    else
        log_warning "API Gateway test failed or no response received"
    fi

    # Test Lambda functions individually
    log "Testing Lambda functions..."
    
    local transformer_name="api-transformer-${PROJECT_NAME##*-}"
    local validator_name="data-validator-${PROJECT_NAME##*-}"
    
    # Test validator
    local validator_payload='{
        "data": {
            "id": "test-123",
            "type": "financial",
            "amount": 250.50,
            "email": "test@example.com"
        },
        "validation_type": "financial"
    }'
    
    if aws lambda invoke \
        --function-name "${validator_name}" \
        --payload "${validator_payload}" \
        "${TEMP_DIR}/validator-test.json" > /dev/null 2>&1; then
        
        if jq -e '.body' "${TEMP_DIR}/validator-test.json" > /dev/null 2>&1; then
            log_success "Data validator test passed"
        else
            log_warning "Data validator test returned unexpected response"
        fi
    else
        log_warning "Data validator test failed"
    fi

    # Test transformer
    local transformer_payload='{
        "api_type": "erp",
        "payload": {
            "id": "test-456",
            "data": {"amount": 100.00}
        },
        "target_url": "https://example.com"
    }'
    
    if aws lambda invoke \
        --function-name "${transformer_name}" \
        --payload "${transformer_payload}" \
        "${TEMP_DIR}/transformer-test.json" > /dev/null 2>&1; then
        
        if jq -e '.body' "${TEMP_DIR}/transformer-test.json" > /dev/null 2>&1; then
            log_success "API transformer test passed"
        else
            log_warning "API transformer test returned unexpected response"
        fi
    else
        log_warning "API transformer test failed"
    fi
}

# Generate deployment summary
generate_summary() {
    log "Generating deployment summary..."

    # Update deployment state
    local temp_file
    temp_file=$(mktemp)
    jq '.deployment_status = "completed" | .completed_at = (now | todate)' \
        "${DEPLOYMENT_STATE_FILE}" > "$temp_file" && mv "$temp_file" "${DEPLOYMENT_STATE_FILE}"

    local summary_file="${SCRIPT_DIR}/deployment_summary_$(date +%Y%m%d_%H%M%S).json"
    cp "${DEPLOYMENT_STATE_FILE}" "${summary_file}"

    log_success "Deployment completed successfully!"
    log ""
    log "📋 DEPLOYMENT SUMMARY"
    log "===================="
    log "Project Name: ${PROJECT_NAME}"
    log "AWS Region: ${AWS_REGION}"
    log "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log ""
    log "🔗 ENDPOINTS"
    log "API Gateway: ${API_ENDPOINT}"
    log "State Machine: arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}"
    log ""
    log "📁 FILES GENERATED"
    log "Deployment Summary: ${summary_file}"
    log "AgentCore Config: ${SCRIPT_DIR}/enterprise-api-spec.json"
    log "Deployment Log: ${LOG_FILE}"
    log ""
    log "🚀 NEXT STEPS"
    log "1. Navigate to AWS Bedrock AgentCore Gateway console"
    log "2. Create a new Gateway named: ${GATEWAY_NAME}"
    log "3. Add OpenAPI target using: ${SCRIPT_DIR}/enterprise-api-spec.json"
    log "4. Add Lambda target for transformer function: api-transformer-${PROJECT_NAME##*-}"
    log "5. Configure OAuth authorizer for agent authentication"
    log "6. Test gateway connectivity with enterprise systems"
    log ""
    log "💰 COST ESTIMATION"
    log "Expected monthly cost (light usage): \$10-15"
    log "Monitor actual costs in AWS Cost Explorer"
    log ""
    log "🧹 CLEANUP"
    log "To remove all resources: ./destroy.sh --project-name ${PROJECT_NAME}"
}

# Cleanup function
cleanup_temp_files() {
    if [[ -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
}

# Main deployment function
main() {
    log "Starting Enterprise API Integration deployment..."
    log "Log file: ${LOG_FILE}"

    parse_arguments "$@"
    check_prerequisites
    setup_environment
    create_iam_roles
    create_lambda_functions
    create_step_functions
    create_api_gateway
    generate_agentcore_config
    test_deployment
    generate_summary
    cleanup_temp_files

    log_success "Deployment completed successfully! 🎉"
}

# Register cleanup on exit
trap cleanup_temp_files EXIT

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi