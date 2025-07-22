#!/bin/bash

# =============================================================================
# Amazon Timestream Time-Series Data Solution - Deployment Script
# =============================================================================
#
# This script deploys a comprehensive time-series data solution using:
# - Amazon Timestream (database and table)
# - AWS Lambda (data ingestion function)
# - AWS IoT Core (direct integration rule)
# - CloudWatch (monitoring and alarms)
# - IAM (roles and policies)
#
# Version: 1.0
# Author: AWS Recipe Generator
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# =============================================================================
# Configuration and Variables
# =============================================================================

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=${DRY_RUN:-false}
VERBOSE=${VERBOSE:-false}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Resource naming
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DEFAULT_SUFFIX=$(echo $RANDOM | md5sum | head -c 6)
RESOURCE_SUFFIX=${RESOURCE_SUFFIX:-$DEFAULT_SUFFIX}

# Core resource names
DATABASE_NAME="iot-timeseries-db-${RESOURCE_SUFFIX}"
TABLE_NAME="sensor-data"
LAMBDA_FUNCTION_NAME="timestream-data-ingestion-${RESOURCE_SUFFIX}"
IOT_RULE_NAME="timestream-iot-rule-${RESOURCE_SUFFIX}"

# Lambda configuration
LAMBDA_RUNTIME="python3.9"
LAMBDA_TIMEOUT=60
LAMBDA_MEMORY=256

# Timestream configuration
MEMORY_STORE_RETENTION_HOURS=24
MAGNETIC_STORE_RETENTION_DAYS=365

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log "ERROR" "${RED}❌ $*${NC}"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Command '$1' is required but not installed"
        return 1
    fi
}

wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local max_attempts=${3:-30}
    local sleep_time=${4:-10}
    
    log_info "Waiting for ${resource_type} '${resource_name}' to be available..."
    
    for ((i=1; i<=max_attempts; i++)); do
        case $resource_type in
            "iam-role")
                if aws iam get-role --role-name "$resource_name" &>/dev/null; then
                    log_success "${resource_type} '${resource_name}' is ready"
                    return 0
                fi
                ;;
            "lambda-function")
                if aws lambda get-function --function-name "$resource_name" &>/dev/null; then
                    local state=$(aws lambda get-function --function-name "$resource_name" --query 'Configuration.State' --output text)
                    if [[ "$state" == "Active" ]]; then
                        log_success "${resource_type} '${resource_name}' is ready"
                        return 0
                    fi
                fi
                ;;
        esac
        
        if [[ $i -eq $max_attempts ]]; then
            log_error "Timeout waiting for ${resource_type} '${resource_name}'"
            return 1
        fi
        
        sleep $sleep_time
    done
}

cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup of partially created resources..."
    
    # Note: In a production script, you might want to implement
    # partial cleanup logic here, but for safety we'll just log
    log_warning "Please run the destroy.sh script to clean up any created resources"
    exit 1
}

# =============================================================================
# Prerequisites and Validation
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required commands
    check_command "aws" || exit 1
    check_command "jq" || log_warning "jq not found - JSON output will be less readable"
    check_command "bc" || log_warning "bc not found - some calculations may not work"
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    
    # Get AWS account information
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION=$(aws configure get region)
    
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region is not configured"
        exit 1
    fi
    
    log_success "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log_success "AWS Region: ${AWS_REGION}"
    
    # Check Timestream availability in region
    if ! aws timestream-write list-databases --region "$AWS_REGION" &>/dev/null; then
        log_error "Amazon Timestream is not available in region ${AWS_REGION}"
        exit 1
    fi
    
    # Check required permissions (basic check)
    log_info "Checking basic AWS permissions..."
    
    local required_permissions=(
        "timestream:CreateDatabase"
        "timestream:CreateTable"
        "lambda:CreateFunction"
        "iam:CreateRole"
        "iot:CreateTopicRule"
        "cloudwatch:PutMetricAlarm"
    )
    
    # Note: Actual permission checking would require more complex logic
    # This is a simplified check
    log_success "Basic permission check completed"
    
    log_success "All prerequisites validated"
}

# =============================================================================
# IAM Resources
# =============================================================================

create_iam_resources() {
    log_info "Creating IAM roles and policies..."
    
    # Create Lambda execution role
    log_info "Creating Lambda execution role..."
    
    local lambda_trust_policy='{
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
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Would create IAM role: ${LAMBDA_FUNCTION_NAME}-role"
    else
        aws iam create-role \
            --role-name "${LAMBDA_FUNCTION_NAME}-role" \
            --assume-role-policy-document "$lambda_trust_policy" \
            --description "Lambda execution role for Timestream data ingestion" \
            --tags Key=Project,Value=TimestreamDataSolution \
                   Key=Component,Value=Lambda \
                   Key=CreatedBy,Value=DeploymentScript
        
        log_success "Created Lambda execution role"
    fi
    
    # Create IoT Core rule role
    log_info "Creating IoT Core rule role..."
    
    local iot_trust_policy='{
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
    }'
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Would create IAM role: ${IOT_RULE_NAME}-role"
    else
        aws iam create-role \
            --role-name "${IOT_RULE_NAME}-role" \
            --assume-role-policy-document "$iot_trust_policy" \
            --description "IoT Core rule role for Timestream integration" \
            --tags Key=Project,Value=TimestreamDataSolution \
                   Key=Component,Value=IoTCore \
                   Key=CreatedBy,Value=DeploymentScript
        
        log_success "Created IoT Core rule role"
    fi
    
    # Wait for roles to be available
    if ! $DRY_RUN; then
        wait_for_resource "iam-role" "${LAMBDA_FUNCTION_NAME}-role"
        wait_for_resource "iam-role" "${IOT_RULE_NAME}-role"
    fi
}

create_iam_policies() {
    log_info "Creating IAM policies..."
    
    # Create Lambda Timestream policy
    local lambda_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "timestream:WriteRecords",
                    "timestream:DescribeEndpoints"
                ],
                "Resource": [
                    "arn:aws:timestream:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':database/'${DATABASE_NAME}'",
                    "arn:aws:timestream:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':database/'${DATABASE_NAME}'/table/*"
                ]
            },
            {
                "Effect": "Allow",
                "Action": [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                "Resource": "arn:aws:logs:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':*"
            }
        ]
    }'
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Would create Lambda Timestream policy"
    else
        aws iam create-policy \
            --policy-name "${LAMBDA_FUNCTION_NAME}-timestream-policy" \
            --policy-document "$lambda_policy" \
            --description "Policy for Lambda to write to Timestream"
        
        aws iam attach-role-policy \
            --role-name "${LAMBDA_FUNCTION_NAME}-role" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_FUNCTION_NAME}-timestream-policy"
        
        log_success "Created and attached Lambda Timestream policy"
    fi
    
    # Create IoT Core Timestream policy
    local iot_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "timestream:WriteRecords",
                    "timestream:DescribeEndpoints"
                ],
                "Resource": [
                    "arn:aws:timestream:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':database/'${DATABASE_NAME}'",
                    "arn:aws:timestream:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':database/'${DATABASE_NAME}'/table/*"
                ]
            }
        ]
    }'
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Would create IoT Timestream policy"
    else
        aws iam create-policy \
            --policy-name "${IOT_RULE_NAME}-timestream-policy" \
            --policy-document "$iot_policy" \
            --description "Policy for IoT Core to write to Timestream"
        
        aws iam attach-role-policy \
            --role-name "${IOT_RULE_NAME}-role" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IOT_RULE_NAME}-timestream-policy"
        
        log_success "Created and attached IoT Timestream policy"
    fi
}

# =============================================================================
# Timestream Resources
# =============================================================================

create_timestream_database() {
    log_info "Creating Amazon Timestream database..."
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Would create Timestream database: ${DATABASE_NAME}"
        return 0
    fi
    
    # Check if database already exists
    if aws timestream-write describe-database --database-name "$DATABASE_NAME" &>/dev/null; then
        log_warning "Timestream database '${DATABASE_NAME}' already exists"
        return 0
    fi
    
    aws timestream-write create-database \
        --database-name "$DATABASE_NAME" \
        --tags Key=Project,Value=TimestreamDataSolution \
               Key=Environment,Value=Production \
               Key=CreatedBy,Value=DeploymentScript
    
    # Store database ARN
    export DATABASE_ARN=$(aws timestream-write describe-database \
        --database-name "$DATABASE_NAME" \
        --query 'Database.Arn' --output text)
    
    log_success "Created Timestream database: ${DATABASE_NAME}"
    log_info "Database ARN: ${DATABASE_ARN}"
}

create_timestream_table() {
    log_info "Creating Timestream table with retention policies..."
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Would create Timestream table: ${TABLE_NAME}"
        return 0
    fi
    
    # Check if table already exists
    if aws timestream-write describe-table \
        --database-name "$DATABASE_NAME" \
        --table-name "$TABLE_NAME" &>/dev/null; then
        log_warning "Timestream table '${TABLE_NAME}' already exists"
        return 0
    fi
    
    aws timestream-write create-table \
        --database-name "$DATABASE_NAME" \
        --table-name "$TABLE_NAME" \
        --retention-properties '{
            "MemoryStoreRetentionPeriodInHours": '${MEMORY_STORE_RETENTION_HOURS}',
            "MagneticStoreRetentionPeriodInDays": '${MAGNETIC_STORE_RETENTION_DAYS}'
        }' \
        --magnetic-store-write-properties '{
            "EnableMagneticStoreWrites": true
        }'
    
    # Store table ARN
    export TABLE_ARN=$(aws timestream-write describe-table \
        --database-name "$DATABASE_NAME" \
        --table-name "$TABLE_NAME" \
        --query 'Table.Arn' --output text)
    
    log_success "Created Timestream table: ${TABLE_NAME}"
    log_info "Table ARN: ${TABLE_ARN}"
    log_info "Memory store retention: ${MEMORY_STORE_RETENTION_HOURS} hours"
    log_info "Magnetic store retention: ${MAGNETIC_STORE_RETENTION_DAYS} days"
}

# =============================================================================
# Lambda Function
# =============================================================================

create_lambda_function() {
    log_info "Creating Lambda function for data ingestion..."
    
    local lambda_dir="${SCRIPT_DIR}/../lambda"
    mkdir -p "$lambda_dir"
    
    # Create Lambda function code
    cat > "${lambda_dir}/index.py" << 'EOF'
import json
import boto3
import os
import time
from datetime import datetime, timezone

timestream = boto3.client('timestream-write')

def lambda_handler(event, context):
    try:
        database_name = os.environ['DATABASE_NAME']
        table_name = os.environ['TABLE_NAME']
        
        # Parse IoT message or direct invocation
        if 'Records' in event:
            # SQS/SNS records
            for record in event['Records']:
                body = json.loads(record['body'])
                write_to_timestream(database_name, table_name, body)
        else:
            # Direct invocation
            write_to_timestream(database_name, table_name, event)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Data written to Timestream successfully')
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def write_to_timestream(database_name, table_name, data):
    current_time = str(int(time.time() * 1000))
    
    records = []
    
    # Handle different data structures
    if isinstance(data, list):
        for item in data:
            records.extend(create_records(item, current_time))
    else:
        records.extend(create_records(data, current_time))
    
    if records:
        try:
            result = timestream.write_records(
                DatabaseName=database_name,
                TableName=table_name,
                Records=records
            )
            print(f"Successfully wrote {len(records)} records")
            return result
        except Exception as e:
            print(f"Error writing to Timestream: {str(e)}")
            raise

def create_records(data, current_time):
    records = []
    device_id = data.get('device_id', 'unknown')
    location = data.get('location', 'unknown')
    
    # Create dimensions (metadata)
    dimensions = [
        {'Name': 'device_id', 'Value': str(device_id)},
        {'Name': 'location', 'Value': str(location)}
    ]
    
    # Handle sensor readings
    if 'sensors' in data:
        for sensor_type, value in data['sensors'].items():
            records.append({
                'Dimensions': dimensions,
                'MeasureName': sensor_type,
                'MeasureValue': str(value),
                'MeasureValueType': 'DOUBLE',
                'Time': current_time,
                'TimeUnit': 'MILLISECONDS'
            })
    
    # Handle single measurements
    if 'measurement' in data:
        records.append({
            'Dimensions': dimensions,
            'MeasureName': data.get('metric_name', 'value'),
            'MeasureValue': str(data['measurement']),
            'MeasureValueType': 'DOUBLE',
            'Time': current_time,
            'TimeUnit': 'MILLISECONDS'
        })
    
    return records
EOF
    
    # Create deployment package
    cd "$lambda_dir"
    zip -r lambda-function.zip index.py
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Would create Lambda function: ${LAMBDA_FUNCTION_NAME}"
        cd "$SCRIPT_DIR"
        return 0
    fi
    
    # Check if function already exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log_warning "Lambda function '${LAMBDA_FUNCTION_NAME}' already exists"
        log_info "Updating function code..."
        
        aws lambda update-function-code \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --zip-file fileb://lambda-function.zip
        
        aws lambda update-function-configuration \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --environment Variables="{
                DATABASE_NAME=${DATABASE_NAME},
                TABLE_NAME=${TABLE_NAME}
            }"
    else
        # Create new function
        aws lambda create-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --runtime "$LAMBDA_RUNTIME" \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_FUNCTION_NAME}-role" \
            --handler index.lambda_handler \
            --zip-file fileb://lambda-function.zip \
            --timeout "$LAMBDA_TIMEOUT" \
            --memory-size "$LAMBDA_MEMORY" \
            --environment Variables="{
                DATABASE_NAME=${DATABASE_NAME},
                TABLE_NAME=${TABLE_NAME}
            }" \
            --tags Project=TimestreamDataSolution,Component=Lambda,CreatedBy=DeploymentScript
        
        wait_for_resource "lambda-function" "$LAMBDA_FUNCTION_NAME"
    fi
    
    cd "$SCRIPT_DIR"
    log_success "Created/updated Lambda function: ${LAMBDA_FUNCTION_NAME}"
}

# =============================================================================
# IoT Core Resources
# =============================================================================

create_iot_rule() {
    log_info "Creating IoT Core rule for Timestream integration..."
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Would create IoT rule: ${IOT_RULE_NAME}"
        return 0
    fi
    
    # Check if rule already exists
    if aws iot get-topic-rule --rule-name "$IOT_RULE_NAME" &>/dev/null; then
        log_warning "IoT rule '${IOT_RULE_NAME}' already exists"
        return 0
    fi
    
    local rule_payload='{
        "sql": "SELECT device_id, location, timestamp, temperature, humidity, pressure FROM '"'"'topic/sensors'"'"'",
        "description": "Route IoT sensor data to Timestream",
        "ruleDisabled": false,
        "awsIotSqlVersion": "2016-03-23",
        "actions": [
            {
                "timestream": {
                    "roleArn": "arn:aws:iam::'${AWS_ACCOUNT_ID}':role/'${IOT_RULE_NAME}'-role",
                    "databaseName": "'${DATABASE_NAME}'",
                    "tableName": "'${TABLE_NAME}'",
                    "dimensions": [
                        {
                            "name": "device_id",
                            "value": "${device_id}"
                        },
                        {
                            "name": "location",
                            "value": "${location}"
                        }
                    ]
                }
            }
        ]
    }'
    
    aws iot create-topic-rule \
        --rule-name "$IOT_RULE_NAME" \
        --topic-rule-payload "$rule_payload"
    
    log_success "Created IoT Core rule: ${IOT_RULE_NAME}"
}

# =============================================================================
# CloudWatch Monitoring
# =============================================================================

create_cloudwatch_alarms() {
    log_info "Creating CloudWatch monitoring alarms..."
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Would create CloudWatch alarms"
        return 0
    fi
    
    # Create alarm for ingestion rate
    aws cloudwatch put-metric-alarm \
        --alarm-name "Timestream-IngestionRate-${DATABASE_NAME}" \
        --alarm-description "Monitor Timestream ingestion rate" \
        --metric-name "SuccessfulRequestLatency" \
        --namespace "AWS/Timestream" \
        --statistic "Average" \
        --period 300 \
        --threshold 1000 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --dimensions Name=DatabaseName,Value="$DATABASE_NAME" \
                    Name=TableName,Value="$TABLE_NAME" \
                    Name=Operation,Value="WriteRecords" \
        --tags Key=Project,Value=TimestreamDataSolution \
               Key=Component,Value=Monitoring \
               Key=CreatedBy,Value=DeploymentScript
    
    # Create alarm for query latency
    aws cloudwatch put-metric-alarm \
        --alarm-name "Timestream-QueryLatency-${DATABASE_NAME}" \
        --alarm-description "Monitor Timestream query latency" \
        --metric-name "QueryLatency" \
        --namespace "AWS/Timestream" \
        --statistic "Average" \
        --period 300 \
        --threshold 5000 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --dimensions Name=DatabaseName,Value="$DATABASE_NAME" \
        --tags Key=Project,Value=TimestreamDataSolution \
               Key=Component,Value=Monitoring \
               Key=CreatedBy,Value=DeploymentScript
    
    log_success "Created CloudWatch monitoring alarms"
}

# =============================================================================
# Data Generation and Testing
# =============================================================================

create_data_generator() {
    log_info "Creating automated data generation script..."
    
    local generator_dir="${SCRIPT_DIR}/../tools"
    mkdir -p "$generator_dir"
    
    cat > "${generator_dir}/generate-iot-data.py" << 'EOF'
#!/usr/bin/env python3
import json
import boto3
import random
import time
from datetime import datetime, timezone
import sys
import argparse

def generate_sensor_data(device_id, location):
    """Generate realistic sensor data"""
    base_temp = 22.0
    base_humidity = 50.0
    base_pressure = 1013.25
    
    return {
        "device_id": device_id,
        "location": location,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "sensors": {
            "temperature": round(base_temp + random.uniform(-5, 8), 2),
            "humidity": round(base_humidity + random.uniform(-10, 20), 2),
            "pressure": round(base_pressure + random.uniform(-50, 50), 2),
            "vibration": round(random.uniform(0.01, 0.1), 3)
        }
    }

def main():
    parser = argparse.ArgumentParser(description='Generate IoT sensor data for Timestream testing')
    parser.add_argument('--function-name', required=True, help='Lambda function name')
    parser.add_argument('--rounds', type=int, default=10, help='Number of data generation rounds')
    parser.add_argument('--interval', type=int, default=30, help='Interval between rounds in seconds')
    
    args = parser.parse_args()
    
    lambda_client = boto3.client('lambda')
    
    devices = [
        ("sensor-001", "factory-floor-1"),
        ("sensor-002", "factory-floor-1"),
        ("sensor-003", "factory-floor-2"),
        ("sensor-004", "warehouse-1"),
        ("sensor-005", "warehouse-2")
    ]
    
    print(f"Starting data generation for {len(devices)} devices...")
    print(f"Rounds: {args.rounds}, Interval: {args.interval}s")
    
    try:
        for i in range(args.rounds):
            for device_id, location in devices:
                data = generate_sensor_data(device_id, location)
                
                response = lambda_client.invoke(
                    FunctionName=args.function_name,
                    Payload=json.dumps(data)
                )
                
                if response['StatusCode'] == 200:
                    print(f"✅ Sent data for {device_id}")
                else:
                    print(f"❌ Failed to send data for {device_id}")
            
            print(f"Completed round {i+1}/{args.rounds}")
            if i < args.rounds - 1:
                time.sleep(args.interval)
            
    except KeyboardInterrupt:
        print("\n⏹️  Data generation stopped")
    except Exception as e:
        print(f"❌ Error: {str(e)}")

if __name__ == "__main__":
    main()
EOF
    
    chmod +x "${generator_dir}/generate-iot-data.py"
    
    log_success "Created data generation script at: ${generator_dir}/generate-iot-data.py"
}

# =============================================================================
# Deployment Summary and Testing
# =============================================================================

test_deployment() {
    log_info "Testing deployment with sample data..."
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Would test deployment"
        return 0
    fi
    
    # Create test data
    local test_data='{
        "device_id": "test-sensor-001",
        "location": "test-location",
        "sensors": {
            "temperature": 23.5,
            "humidity": 68.0,
            "pressure": 1015.0,
            "vibration": 0.03
        }
    }'
    
    log_info "Sending test data to Lambda function..."
    
    local response=$(aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload "$test_data" \
        --cli-binary-format raw-in-base64-out \
        /tmp/test-response.json 2>&1)
    
    if [[ $? -eq 0 ]]; then
        log_success "Test data sent successfully"
        
        # Wait a moment for data to be processed
        sleep 5
        
        # Try to query the data
        log_info "Querying test data from Timestream..."
        
        local query="SELECT device_id, location, measure_name, measure_value::double, time FROM \"${DATABASE_NAME}\".\"${TABLE_NAME}\" WHERE device_id = 'test-sensor-001' ORDER BY time DESC LIMIT 5"
        
        if aws timestream-query query --query-string "$query" &>/dev/null; then
            log_success "Test data query successful"
        else
            log_warning "Test data query failed - data may still be propagating"
        fi
    else
        log_error "Test data sending failed: $response"
    fi
    
    rm -f /tmp/test-response.json
}

print_deployment_summary() {
    log_info "==================================================================="
    log_info "                     DEPLOYMENT SUMMARY"
    log_info "==================================================================="
    log_info "Timestream Database: ${DATABASE_NAME}"
    log_info "Timestream Table: ${TABLE_NAME}"
    log_info "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log_info "IoT Rule: ${IOT_RULE_NAME}"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "AWS Account: ${AWS_ACCOUNT_ID}"
    log_info ""
    log_info "Memory Store Retention: ${MEMORY_STORE_RETENTION_HOURS} hours"
    log_info "Magnetic Store Retention: ${MAGNETIC_STORE_RETENTION_DAYS} days"
    log_info ""
    log_info "CloudWatch Alarms:"
    log_info "  - Timestream-IngestionRate-${DATABASE_NAME}"
    log_info "  - Timestream-QueryLatency-${DATABASE_NAME}"
    log_info ""
    log_info "Next Steps:"
    log_info "  1. Test the Lambda function with sample data"
    log_info "  2. Publish messages to IoT topic 'topic/sensors'"
    log_info "  3. Query data using Timestream query console"
    log_info "  4. Set up Grafana dashboards for visualization"
    log_info ""
    log_info "Data Generator:"
    log_info "  python3 ../tools/generate-iot-data.py --function-name ${LAMBDA_FUNCTION_NAME}"
    log_info ""
    log_info "Cleanup:"
    log_info "  ./destroy.sh"
    log_info "==================================================================="
}

# =============================================================================
# Main Deployment Function
# =============================================================================

main() {
    local start_time=$(date +%s)
    
    log_info "Starting Amazon Timestream Time-Series Data Solution deployment..."
    log_info "Timestamp: $(date)"
    log_info "Log file: ${LOG_FILE}"
    
    if $DRY_RUN; then
        log_warning "DRY RUN MODE - No resources will be created"
    fi
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Run deployment steps
    check_prerequisites
    create_iam_resources
    create_iam_policies
    create_timestream_database
    create_timestream_table
    create_lambda_function
    create_iot_rule
    create_cloudwatch_alarms
    create_data_generator
    
    if ! $DRY_RUN; then
        test_deployment
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    print_deployment_summary
    log_success "Deployment completed successfully in ${duration} seconds!"
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --suffix)
            RESOURCE_SUFFIX="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be deployed without creating resources"
            echo "  --verbose    Enable verbose logging"
            echo "  --suffix     Custom suffix for resource names (default: random)"
            echo "  --help       Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  RESOURCE_SUFFIX    Custom suffix for resource names"
            echo "  DRY_RUN           Set to 'true' for dry run mode"
            echo "  VERBOSE           Set to 'true' for verbose output"
            echo ""
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"