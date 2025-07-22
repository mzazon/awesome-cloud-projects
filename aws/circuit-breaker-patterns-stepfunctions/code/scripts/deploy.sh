#!/bin/bash

#################################################################################
# Circuit Breaker Patterns with Step Functions - Deployment Script
# 
# This script deploys the complete circuit breaker pattern infrastructure using
# AWS CLI commands. It creates all necessary resources including DynamoDB table,
# Lambda functions, Step Functions state machine, IAM roles, and CloudWatch alarms.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate AWS permissions for Step Functions, Lambda, DynamoDB, CloudWatch
# - jq installed for JSON processing
#
# Usage: ./deploy.sh [--dry-run] [--skip-confirmation]
#################################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Default options
DRY_RUN=false
SKIP_CONFIRMATION=false

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

#################################################################################
# Utility Functions
#################################################################################

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$LOG_FILE"
}

cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        source "$DEPLOYMENT_STATE_FILE"
        "${SCRIPT_DIR}/destroy.sh" --auto-confirm || true
    fi
}

# Set trap for cleanup
trap cleanup_on_error ERR

save_deployment_state() {
    cat > "$DEPLOYMENT_STATE_FILE" << EOF
# Circuit Breaker Deployment State
# Generated: $(date)
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
export CIRCUIT_BREAKER_TABLE="$CIRCUIT_BREAKER_TABLE"
export DOWNSTREAM_SERVICE_FUNCTION="$DOWNSTREAM_SERVICE_FUNCTION"
export FALLBACK_SERVICE_FUNCTION="$FALLBACK_SERVICE_FUNCTION"
export HEALTH_CHECK_FUNCTION="$HEALTH_CHECK_FUNCTION"
export CIRCUIT_BREAKER_ROLE="$CIRCUIT_BREAKER_ROLE"
export LAMBDA_EXECUTION_ROLE="$LAMBDA_EXECUTION_ROLE"
export STATE_MACHINE_ARN="$STATE_MACHINE_ARN"
export DEPLOYMENT_TIMESTAMP="$(date -u +%Y%m%d_%H%M%S)"
EOF
    log_success "Deployment state saved to $DEPLOYMENT_STATE_FILE"
}

#################################################################################
# Validation Functions
#################################################################################

validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local major_version
    major_version=$(echo "$aws_version" | cut -d. -f1)
    if [[ "$major_version" -lt 2 ]]; then
        log_warning "AWS CLI version $aws_version detected. Version 2.x is recommended."
    fi
    
    log_success "Prerequisites validation completed"
}

validate_permissions() {
    log "Validating AWS permissions..."
    
    local required_services=("iam" "lambda" "stepfunctions" "dynamodb" "cloudwatch")
    
    for service in "${required_services[@]}"; do
        case $service in
            "iam")
                if ! aws iam list-roles --max-items 1 &> /dev/null; then
                    log_error "Missing IAM permissions for listing roles"
                    exit 1
                fi
                ;;
            "lambda")
                if ! aws lambda list-functions --max-items 1 &> /dev/null; then
                    log_error "Missing Lambda permissions"
                    exit 1
                fi
                ;;
            "stepfunctions")
                if ! aws stepfunctions list-state-machines --max-results 1 &> /dev/null; then
                    log_error "Missing Step Functions permissions"
                    exit 1
                fi
                ;;
            "dynamodb")
                if ! aws dynamodb list-tables &> /dev/null; then
                    log_error "Missing DynamoDB permissions"
                    exit 1
                fi
                ;;
            "cloudwatch")
                if ! aws cloudwatch list-metrics --max-records 1 &> /dev/null; then
                    log_error "Missing CloudWatch permissions"
                    exit 1
                fi
                ;;
        esac
    done
    
    log_success "AWS permissions validation completed"
}

check_existing_resources() {
    log "Checking for existing resources with potential naming conflicts..."
    
    # Check for existing tables with our naming pattern
    local existing_tables
    existing_tables=$(aws dynamodb list-tables --query 'TableNames[?contains(@, `circuit-breaker-state`)]' --output text)
    if [[ -n "$existing_tables" ]]; then
        log_warning "Found existing DynamoDB tables with circuit-breaker naming: $existing_tables"
    fi
    
    # Check for existing Lambda functions
    local existing_functions
    existing_functions=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `circuit`) || contains(FunctionName, `downstream`) || contains(FunctionName, `fallback`) || contains(FunctionName, `health-check`)].FunctionName' --output text)
    if [[ -n "$existing_functions" ]]; then
        log_warning "Found existing Lambda functions with similar names: $existing_functions"
    fi
    
    log_success "Resource conflict check completed"
}

#################################################################################
# Resource Creation Functions
#################################################################################

setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION
    AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        AWS_REGION="us-east-1"
        log_warning "No default region configured, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    export RANDOM_SUFFIX
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export CIRCUIT_BREAKER_TABLE="circuit-breaker-state-${RANDOM_SUFFIX}"
    export DOWNSTREAM_SERVICE_FUNCTION="downstream-service-${RANDOM_SUFFIX}"
    export FALLBACK_SERVICE_FUNCTION="fallback-service-${RANDOM_SUFFIX}"
    export HEALTH_CHECK_FUNCTION="health-check-${RANDOM_SUFFIX}"
    export CIRCUIT_BREAKER_ROLE="circuit-breaker-role-${RANDOM_SUFFIX}"
    export LAMBDA_EXECUTION_ROLE="lambda-execution-role-${RANDOM_SUFFIX}"
    
    log_success "Environment setup completed"
    log "AWS Region: $AWS_REGION"
    log "AWS Account: $AWS_ACCOUNT_ID"
    log "Resource Suffix: $RANDOM_SUFFIX"
}

create_iam_roles() {
    log "Creating IAM roles..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create IAM roles"
        return 0
    fi
    
    # Create IAM role for Step Functions
    aws iam create-role \
        --role-name "$CIRCUIT_BREAKER_ROLE" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "states.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' > /dev/null
    
    # Create IAM role for Lambda functions
    aws iam create-role \
        --role-name "$LAMBDA_EXECUTION_ROLE" \
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
        }' > /dev/null
    
    # Wait for role propagation
    log "Waiting for IAM role propagation..."
    sleep 15
    
    log_success "IAM roles created successfully"
}

create_dynamodb_table() {
    log "Creating DynamoDB table for circuit breaker state..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create DynamoDB table $CIRCUIT_BREAKER_TABLE"
        return 0
    fi
    
    aws dynamodb create-table \
        --table-name "$CIRCUIT_BREAKER_TABLE" \
        --attribute-definitions \
            AttributeName=ServiceName,AttributeType=S \
        --key-schema \
            AttributeName=ServiceName,KeyType=HASH \
        --provisioned-throughput \
            ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --tags Key=Purpose,Value=CircuitBreaker,Key=Environment,Value=Demo > /dev/null
    
    # Wait for table to be active
    log "Waiting for DynamoDB table to become active..."
    aws dynamodb wait table-exists --table-name "$CIRCUIT_BREAKER_TABLE"
    
    log_success "DynamoDB table created: $CIRCUIT_BREAKER_TABLE"
}

create_lambda_functions() {
    log "Creating Lambda functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create Lambda functions"
        return 0
    fi
    
    # Create temporary directory for Lambda code
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create downstream service Lambda function
    cat > "$temp_dir/downstream-service.py" << 'EOF'
import json
import random
import time
import os

def lambda_handler(event, context):
    # Simulate service behavior based on environment variable
    failure_rate = float(os.environ.get('FAILURE_RATE', '0.3'))
    latency_ms = int(os.environ.get('LATENCY_MS', '100'))
    
    # Simulate latency
    time.sleep(latency_ms / 1000)
    
    # Simulate failures
    if random.random() < failure_rate:
        raise Exception("Service temporarily unavailable")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Service response successful',
            'timestamp': context.aws_request_id
        })
    }
EOF
    
    # Create fallback service Lambda function
    cat > "$temp_dir/fallback-service.py" << 'EOF'
import json
import boto3
from datetime import datetime

def lambda_handler(event, context):
    # Provide fallback response when primary service is unavailable
    fallback_data = {
        'message': 'Fallback service response',
        'timestamp': datetime.utcnow().isoformat(),
        'source': 'fallback-service',
        'original_request': event.get('original_request', {}),
        'fallback_reason': 'Circuit breaker is open'
    }
    
    return {
        'statusCode': 200,
        'body': json.dumps(fallback_data)
    }
EOF
    
    # Create health check Lambda function
    cat > "$temp_dir/health-check.py" << 'EOF'
import json
import boto3
from datetime import datetime, timedelta

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    table_name = event['table_name']
    service_name = event['service_name']
    
    table = dynamodb.Table(table_name)
    
    try:
        # Get current circuit breaker state
        response = table.get_item(
            Key={'ServiceName': service_name}
        )
        
        if 'Item' not in response:
            # Initialize circuit breaker state
            table.put_item(
                Item={
                    'ServiceName': service_name,
                    'State': 'CLOSED',
                    'FailureCount': 0,
                    'LastFailureTime': None,
                    'LastSuccessTime': datetime.utcnow().isoformat()
                }
            )
            state = 'CLOSED'
            failure_count = 0
        else:
            item = response['Item']
            state = item['State']
            failure_count = item.get('FailureCount', 0)
        
        # Simulate health check (in real implementation, call actual service)
        import random
        health_check_success = random.random() > 0.3
        
        if health_check_success:
            # Reset circuit breaker to CLOSED on successful health check
            table.put_item(
                Item={
                    'ServiceName': service_name,
                    'State': 'CLOSED',
                    'FailureCount': 0,
                    'LastFailureTime': None,
                    'LastSuccessTime': datetime.utcnow().isoformat()
                }
            )
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'service_name': service_name,
                    'health_status': 'healthy',
                    'circuit_state': 'CLOSED'
                })
            }
        else:
            return {
                'statusCode': 503,
                'body': json.dumps({
                    'service_name': service_name,
                    'health_status': 'unhealthy',
                    'circuit_state': state
                })
            }
    
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
EOF
    
    # Create deployment packages
    (cd "$temp_dir" && zip -q downstream-service.zip downstream-service.py)
    (cd "$temp_dir" && zip -q fallback-service.zip fallback-service.py)
    (cd "$temp_dir" && zip -q health-check.zip health-check.py)
    
    # Deploy downstream service function
    aws lambda create-function \
        --function-name "$DOWNSTREAM_SERVICE_FUNCTION" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_EXECUTION_ROLE}" \
        --handler downstream-service.lambda_handler \
        --zip-file "fileb://${temp_dir}/downstream-service.zip" \
        --timeout 30 \
        --environment Variables='{
            "FAILURE_RATE": "0.5",
            "LATENCY_MS": "200"
        }' > /dev/null
    
    # Deploy fallback service function
    aws lambda create-function \
        --function-name "$FALLBACK_SERVICE_FUNCTION" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_EXECUTION_ROLE}" \
        --handler fallback-service.lambda_handler \
        --zip-file "fileb://${temp_dir}/fallback-service.zip" \
        --timeout 30 > /dev/null
    
    # Deploy health check function
    aws lambda create-function \
        --function-name "$HEALTH_CHECK_FUNCTION" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_EXECUTION_ROLE}" \
        --handler health-check.lambda_handler \
        --zip-file "fileb://${temp_dir}/health-check.zip" \
        --timeout 30 > /dev/null
    
    # Cleanup temporary files
    rm -rf "$temp_dir"
    
    log_success "Lambda functions created successfully"
}

attach_iam_policies() {
    log "Attaching IAM policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would attach IAM policies"
        return 0
    fi
    
    # Attach policies to Step Functions role
    aws iam attach-role-policy \
        --role-name "$CIRCUIT_BREAKER_ROLE" \
        --policy-arn arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess
    
    aws iam attach-role-policy \
        --role-name "$CIRCUIT_BREAKER_ROLE" \
        --policy-arn arn:aws:iam::aws:policy/AWSLambdaRole
    
    # Create custom policy for DynamoDB access
    aws iam put-role-policy \
        --role-name "$CIRCUIT_BREAKER_ROLE" \
        --policy-name DynamoDBCircuitBreakerPolicy \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "dynamodb:GetItem",
                        "dynamodb:PutItem",
                        "dynamodb:UpdateItem",
                        "dynamodb:DeleteItem"
                    ],
                    "Resource": "arn:aws:dynamodb:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':table/'${CIRCUIT_BREAKER_TABLE}'"
                }
            ]
        }'
    
    # Attach policies to Lambda execution role
    aws iam attach-role-policy \
        --role-name "$LAMBDA_EXECUTION_ROLE" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam put-role-policy \
        --role-name "$LAMBDA_EXECUTION_ROLE" \
        --policy-name DynamoDBLambdaPolicy \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "dynamodb:GetItem",
                        "dynamodb:PutItem",
                        "dynamodb:UpdateItem"
                    ],
                    "Resource": "arn:aws:dynamodb:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':table/'${CIRCUIT_BREAKER_TABLE}'"
                }
            ]
        }'
    
    log_success "IAM policies attached successfully"
}

create_step_functions_state_machine() {
    log "Creating Step Functions state machine..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create Step Functions state machine"
        return 0
    fi
    
    # Create the circuit breaker state machine definition
    local state_machine_def
    state_machine_def=$(cat << EOF
{
  "Comment": "Circuit Breaker Pattern Implementation",
  "StartAt": "CheckCircuitBreakerState",
  "States": {
    "CheckCircuitBreakerState": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:getItem",
      "Parameters": {
        "TableName": "$CIRCUIT_BREAKER_TABLE",
        "Key": {
          "ServiceName": {
            "S.\$": "\$.service_name"
          }
        }
      },
      "ResultPath": "\$.circuit_state",
      "Next": "EvaluateCircuitState",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "InitializeCircuitBreaker"
        }
      ]
    },
    "InitializeCircuitBreaker": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:putItem",
      "Parameters": {
        "TableName": "$CIRCUIT_BREAKER_TABLE",
        "Item": {
          "ServiceName": {
            "S.\$": "\$.service_name"
          },
          "State": {
            "S": "CLOSED"
          },
          "FailureCount": {
            "N": "0"
          },
          "LastFailureTime": {
            "NULL": true
          },
          "LastSuccessTime": {
            "S.\$": "\$\$.State.EnteredTime"
          }
        }
      },
      "Next": "CallDownstreamService"
    },
    "EvaluateCircuitState": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "\$.circuit_state.Item.State.S",
          "StringEquals": "OPEN",
          "Next": "CheckIfHalfOpenTime"
        },
        {
          "Variable": "\$.circuit_state.Item.State.S",
          "StringEquals": "HALF_OPEN",
          "Next": "CallDownstreamService"
        },
        {
          "Variable": "\$.circuit_state.Item.State.S",
          "StringEquals": "CLOSED",
          "Next": "CallDownstreamService"
        }
      ],
      "Default": "CallDownstreamService"
    },
    "CheckIfHalfOpenTime": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "$HEALTH_CHECK_FUNCTION",
        "Payload": {
          "table_name": "$CIRCUIT_BREAKER_TABLE",
          "service_name.\$": "\$.service_name"
        }
      },
      "ResultPath": "\$.health_check_result",
      "Next": "EvaluateHealthCheck",
      "Retry": [
        {
          "ErrorEquals": ["States.ALL"],
          "IntervalSeconds": 2,
          "MaxAttempts": 3,
          "BackoffRate": 2.0
        }
      ]
    },
    "EvaluateHealthCheck": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "\$.health_check_result.Payload.statusCode",
          "NumericEquals": 200,
          "Next": "CallDownstreamService"
        }
      ],
      "Default": "CallFallbackService"
    },
    "CallDownstreamService": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "$DOWNSTREAM_SERVICE_FUNCTION",
        "Payload.\$": "\$.request_payload"
      },
      "ResultPath": "\$.service_result",
      "Next": "RecordSuccess",
      "Catch": [
        {
          "ErrorEquals": ["States.ALL"],
          "Next": "RecordFailure",
          "ResultPath": "\$.error"
        }
      ],
      "Retry": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "IntervalSeconds": 1,
          "MaxAttempts": 2,
          "BackoffRate": 2.0
        }
      ]
    },
    "RecordSuccess": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:updateItem",
      "Parameters": {
        "TableName": "$CIRCUIT_BREAKER_TABLE",
        "Key": {
          "ServiceName": {
            "S.\$": "\$.service_name"
          }
        },
        "UpdateExpression": "SET #state = :closed_state, FailureCount = :zero, LastSuccessTime = :timestamp",
        "ExpressionAttributeNames": {
          "#state": "State"
        },
        "ExpressionAttributeValues": {
          ":closed_state": {
            "S": "CLOSED"
          },
          ":zero": {
            "N": "0"
          },
          ":timestamp": {
            "S.\$": "\$\$.State.EnteredTime"
          }
        }
      },
      "Next": "ReturnSuccess"
    },
    "RecordFailure": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:updateItem",
      "Parameters": {
        "TableName": "$CIRCUIT_BREAKER_TABLE",
        "Key": {
          "ServiceName": {
            "S.\$": "\$.service_name"
          }
        },
        "UpdateExpression": "SET FailureCount = FailureCount + :inc, LastFailureTime = :timestamp",
        "ExpressionAttributeValues": {
          ":inc": {
            "N": "1"
          },
          ":timestamp": {
            "S.\$": "\$\$.State.EnteredTime"
          }
        }
      },
      "ResultPath": "\$.update_result",
      "Next": "CheckFailureThreshold"
    },
    "CheckFailureThreshold": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:getItem",
      "Parameters": {
        "TableName": "$CIRCUIT_BREAKER_TABLE",
        "Key": {
          "ServiceName": {
            "S.\$": "\$.service_name"
          }
        }
      },
      "ResultPath": "\$.current_state",
      "Next": "EvaluateFailureCount"
    },
    "EvaluateFailureCount": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "\$.current_state.Item.FailureCount.N",
          "NumericGreaterThanEquals": 3,
          "Next": "TripCircuitBreaker"
        }
      ],
      "Default": "CallFallbackService"
    },
    "TripCircuitBreaker": {
      "Type": "Task",
      "Resource": "arn:aws:states:::dynamodb:updateItem",
      "Parameters": {
        "TableName": "$CIRCUIT_BREAKER_TABLE",
        "Key": {
          "ServiceName": {
            "S.\$": "\$.service_name"
          }
        },
        "UpdateExpression": "SET #state = :open_state",
        "ExpressionAttributeNames": {
          "#state": "State"
        },
        "ExpressionAttributeValues": {
          ":open_state": {
            "S": "OPEN"
          }
        }
      },
      "Next": "CallFallbackService"
    },
    "CallFallbackService": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "$FALLBACK_SERVICE_FUNCTION",
        "Payload": {
          "original_request.\$": "\$.request_payload",
          "circuit_breaker_state.\$": "\$.circuit_state.Item.State.S"
        }
      },
      "ResultPath": "\$.fallback_result",
      "Next": "ReturnFallback"
    },
    "ReturnSuccess": {
      "Type": "Pass",
      "Parameters": {
        "statusCode": 200,
        "body.\$": "\$.service_result.Payload.body",
        "circuit_breaker_state": "CLOSED"
      },
      "End": true
    },
    "ReturnFallback": {
      "Type": "Pass",
      "Parameters": {
        "statusCode": 200,
        "body.\$": "\$.fallback_result.Payload.body",
        "circuit_breaker_state": "OPEN",
        "fallback_used": true
      },
      "End": true
    }
  }
}
EOF
)
    
    # Create the Step Functions state machine
    local state_machine_response
    state_machine_response=$(aws stepfunctions create-state-machine \
        --name "CircuitBreakerStateMachine-${RANDOM_SUFFIX}" \
        --definition "$state_machine_def" \
        --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CIRCUIT_BREAKER_ROLE}")
    
    # Store the state machine ARN
    export STATE_MACHINE_ARN
    STATE_MACHINE_ARN=$(echo "$state_machine_response" | jq -r '.stateMachineArn')
    
    log_success "Step Functions state machine created: $STATE_MACHINE_ARN"
}

create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create CloudWatch alarms"
        return 0
    fi
    
    # Create CloudWatch alarm for circuit breaker state changes
    aws cloudwatch put-metric-alarm \
        --alarm-name "CircuitBreakerOpenAlarm-${RANDOM_SUFFIX}" \
        --alarm-description "Circuit breaker has been tripped to OPEN state" \
        --metric-name "CircuitBreakerOpen" \
        --namespace "CircuitBreaker" \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 > /dev/null
    
    # Create CloudWatch alarm for service failures
    aws cloudwatch put-metric-alarm \
        --alarm-name "ServiceFailureRateAlarm-${RANDOM_SUFFIX}" \
        --alarm-description "High failure rate detected in downstream service" \
        --metric-name "ServiceFailures" \
        --namespace "CircuitBreaker" \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 2 > /dev/null
    
    log_success "CloudWatch alarms created successfully"
}

#################################################################################
# Testing Functions
#################################################################################

run_deployment_tests() {
    log "Running deployment validation tests..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would run deployment tests"
        return 0
    fi
    
    # Test 1: Verify DynamoDB table exists
    if aws dynamodb describe-table --table-name "$CIRCUIT_BREAKER_TABLE" &> /dev/null; then
        log_success "✓ DynamoDB table verification passed"
    else
        log_error "✗ DynamoDB table verification failed"
        return 1
    fi
    
    # Test 2: Verify Lambda functions exist
    local functions=("$DOWNSTREAM_SERVICE_FUNCTION" "$FALLBACK_SERVICE_FUNCTION" "$HEALTH_CHECK_FUNCTION")
    for func in "${functions[@]}"; do
        if aws lambda get-function --function-name "$func" &> /dev/null; then
            log_success "✓ Lambda function $func verification passed"
        else
            log_error "✗ Lambda function $func verification failed"
            return 1
        fi
    done
    
    # Test 3: Verify Step Functions state machine exists
    if aws stepfunctions describe-state-machine --state-machine-arn "$STATE_MACHINE_ARN" &> /dev/null; then
        log_success "✓ Step Functions state machine verification passed"
    else
        log_error "✗ Step Functions state machine verification failed"
        return 1
    fi
    
    # Test 4: Test circuit breaker with sample input
    local test_input='{
        "service_name": "test-service",
        "request_payload": {
            "test": "data"
        }
    }'
    
    local execution_arn
    execution_arn=$(aws stepfunctions start-execution \
        --state-machine-arn "$STATE_MACHINE_ARN" \
        --name "test-execution-$(date +%s)" \
        --input "$test_input" \
        --query executionArn --output text)
    
    if [[ -n "$execution_arn" ]]; then
        log_success "✓ Test execution started: $execution_arn"
        
        # Wait for execution to complete
        local max_wait=60
        local wait_count=0
        while [[ $wait_count -lt $max_wait ]]; do
            local status
            status=$(aws stepfunctions describe-execution \
                --execution-arn "$execution_arn" \
                --query 'status' --output text)
            
            if [[ "$status" == "SUCCEEDED" ]]; then
                log_success "✓ Test execution completed successfully"
                break
            elif [[ "$status" == "FAILED" ]]; then
                log_error "✗ Test execution failed"
                return 1
            fi
            
            sleep 2
            ((wait_count += 2))
        done
        
        if [[ $wait_count -ge $max_wait ]]; then
            log_warning "⚠️  Test execution timeout - check execution manually"
        fi
    else
        log_error "✗ Failed to start test execution"
        return 1
    fi
    
    log_success "All deployment tests passed"
}

#################################################################################
# Main Deployment Flow
#################################################################################

show_usage() {
    cat << EOF
Circuit Breaker Patterns with Step Functions - Deployment Script

Usage: $0 [OPTIONS]

Options:
    --dry-run              Show what would be deployed without making changes
    --skip-confirmation    Skip deployment confirmation prompt
    --help                 Show this help message

Examples:
    $0                     # Interactive deployment
    $0 --dry-run          # Preview deployment actions
    $0 --skip-confirmation # Deploy without confirmation prompt

EOF
}

confirm_deployment() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo
    log "Deployment Summary:"
    echo "  AWS Region: $AWS_REGION"
    echo "  AWS Account: $AWS_ACCOUNT_ID"
    echo "  Resource Suffix: $RANDOM_SUFFIX"
    echo
    echo "Resources to be created:"
    echo "  • DynamoDB Table: $CIRCUIT_BREAKER_TABLE"
    echo "  • Lambda Functions: 3 functions"
    echo "  • Step Functions State Machine: CircuitBreakerStateMachine-${RANDOM_SUFFIX}"
    echo "  • IAM Roles: 2 roles with policies"
    echo "  • CloudWatch Alarms: 2 alarms"
    echo
    
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
}

main() {
    # Initialize log file
    echo "Circuit Breaker Deployment Log - $(date)" > "$LOG_FILE"
    
    log "Starting Circuit Breaker Pattern deployment..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-confirmation)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validation phase
    validate_prerequisites
    validate_permissions
    setup_environment
    check_existing_resources
    
    # Show deployment summary and get confirmation
    confirm_deployment
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "=== DRY RUN MODE - No resources will be created ==="
    fi
    
    # Deployment phase
    log "Starting resource deployment..."
    
    create_iam_roles
    create_dynamodb_table
    create_lambda_functions
    attach_iam_policies
    create_step_functions_state_machine
    create_cloudwatch_alarms
    
    # Save deployment state for cleanup
    save_deployment_state
    
    # Validation phase
    run_deployment_tests
    
    # Success summary
    echo
    log_success "🎉 Circuit Breaker Pattern deployment completed successfully!"
    echo
    echo "Deployment Summary:"
    echo "  State Machine ARN: $STATE_MACHINE_ARN"
    echo "  DynamoDB Table: $CIRCUIT_BREAKER_TABLE"
    echo "  Deployment State: $DEPLOYMENT_STATE_FILE"
    echo
    echo "Next Steps:"
    echo "  1. Test the circuit breaker with the Step Functions console"
    echo "  2. Monitor CloudWatch alarms for circuit breaker activity"
    echo "  3. Review Lambda function logs for debugging"
    echo "  4. Use ./destroy.sh to clean up resources when done"
    echo
    echo "Estimated monthly cost: \$10-50 depending on usage"
    echo
    
    log "Deployment completed at $(date)"
}

# Execute main function with all arguments
main "$@"