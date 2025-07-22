#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    warn "Running in dry-run mode - no resources will be created"
fi

# Function to execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${BLUE}[DRY-RUN] Would execute: $cmd${NC}"
    else
        log "$description"
        eval "$cmd"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check required services are available in region
    local region=$(aws configure get region)
    if [[ -z "$region" ]]; then
        error "AWS region is not configured."
        exit 1
    fi
    
    # Check if IoT Analytics is supported in the region
    if ! aws iotanalytics list-channels --region "$region" &> /dev/null; then
        error "IoT Analytics is not available in region $region or you don't have sufficient permissions."
        exit 1
    fi
    
    log "Prerequisites check passed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export CHANNEL_NAME="iot-sensor-channel-${RANDOM_SUFFIX}"
    export PIPELINE_NAME="iot-sensor-pipeline-${RANDOM_SUFFIX}"
    export DATASTORE_NAME="iot-sensor-datastore-${RANDOM_SUFFIX}"
    export DATASET_NAME="iot-sensor-dataset-${RANDOM_SUFFIX}"
    export KINESIS_STREAM_NAME="iot-sensor-stream-${RANDOM_SUFFIX}"
    export TIMESTREAM_DATABASE_NAME="iot-sensor-db-${RANDOM_SUFFIX}"
    export TIMESTREAM_TABLE_NAME="sensor-data"
    export IOT_ANALYTICS_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/IoTAnalyticsServiceRole"
    export LAMBDA_TIMESTREAM_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/LambdaTimestreamRole"
    
    log "Environment variables configured"
    log "Region: $AWS_REGION"
    log "Account ID: $AWS_ACCOUNT_ID"
    log "Resource suffix: $RANDOM_SUFFIX"
}

# Function to create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Create IoT Analytics service role
    execute_cmd "aws iam create-role \
        --role-name IoTAnalyticsServiceRole \
        --assume-role-policy-document '{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Effect\": \"Allow\",
                    \"Principal\": {
                        \"Service\": \"iotanalytics.amazonaws.com\"
                    },
                    \"Action\": \"sts:AssumeRole\"
                }
            ]
        }' --output table" "Creating IoT Analytics service role"
    
    # Attach policy to IoT Analytics role
    execute_cmd "aws iam attach-role-policy \
        --role-name IoTAnalyticsServiceRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSIoTAnalyticsServiceRole" "Attaching policy to IoT Analytics role"
    
    # Create Lambda execution role
    execute_cmd "aws iam create-role \
        --role-name LambdaTimestreamRole \
        --assume-role-policy-document '{
            \"Version\": \"2012-10-17\",
            \"Statement\": [
                {
                    \"Effect\": \"Allow\",
                    \"Principal\": {
                        \"Service\": \"lambda.amazonaws.com\"
                    },
                    \"Action\": \"sts:AssumeRole\"
                }
            ]
        }' --output table" "Creating Lambda execution role"
    
    # Attach policies to Lambda role
    execute_cmd "aws iam attach-role-policy \
        --role-name LambdaTimestreamRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" "Attaching basic execution policy to Lambda role"
    
    execute_cmd "aws iam attach-role-policy \
        --role-name LambdaTimestreamRole \
        --policy-arn arn:aws:iam::aws:policy/AmazonTimestreamFullAccess" "Attaching Timestream policy to Lambda role"
    
    execute_cmd "aws iam attach-role-policy \
        --role-name LambdaTimestreamRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole" "Attaching Kinesis execution policy to Lambda role"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for IAM roles to propagate..."
        sleep 10
    fi
}

# Function to create IoT Analytics resources
create_iot_analytics_resources() {
    log "Creating IoT Analytics resources..."
    
    # Create channel
    execute_cmd "aws iotanalytics create-channel \
        --channel-name $CHANNEL_NAME \
        --retention-period unlimited=true \
        --output table" "Creating IoT Analytics channel"
    
    # Create datastore
    execute_cmd "aws iotanalytics create-datastore \
        --datastore-name $DATASTORE_NAME \
        --retention-period unlimited=true \
        --output table" "Creating IoT Analytics datastore"
    
    # Create pipeline
    execute_cmd "aws iotanalytics create-pipeline \
        --pipeline-name $PIPELINE_NAME \
        --pipeline-activities '[
            {
                \"channel\": {
                    \"name\": \"ChannelActivity\",
                    \"channelName\": \"'$CHANNEL_NAME'\",
                    \"next\": \"FilterActivity\"
                }
            },
            {
                \"filter\": {
                    \"name\": \"FilterActivity\",
                    \"filter\": \"temperature > 0 AND temperature < 100\",
                    \"next\": \"MathActivity\"
                }
            },
            {
                \"math\": {
                    \"name\": \"MathActivity\",
                    \"math\": \"temperature_celsius\",
                    \"attribute\": \"temperature_celsius\",
                    \"next\": \"AddAttributesActivity\"
                }
            },
            {
                \"addAttributes\": {
                    \"name\": \"AddAttributesActivity\",
                    \"attributes\": {
                        \"location\": \"factory_floor_1\",
                        \"device_type\": \"temperature_sensor\"
                    },
                    \"next\": \"DatastoreActivity\"
                }
            },
            {
                \"datastore\": {
                    \"name\": \"DatastoreActivity\",
                    \"datastoreName\": \"'$DATASTORE_NAME'\"
                }
            }
        ]' --output table" "Creating IoT Analytics pipeline"
    
    # Create dataset
    execute_cmd "aws iotanalytics create-dataset \
        --dataset-name $DATASET_NAME \
        --actions '[
            {
                \"actionName\": \"SqlAction\",
                \"queryAction\": {
                    \"sqlQuery\": \"SELECT * FROM '${DATASTORE_NAME}' WHERE temperature_celsius > 25 ORDER BY timestamp DESC LIMIT 100\"
                }
            }
        ]' \
        --triggers '[
            {
                \"schedule\": {
                    \"expression\": \"rate(1 hour)\"
                }
            }
        ]' --output table" "Creating IoT Analytics dataset"
    
    # Create IoT rule
    execute_cmd "aws iot create-topic-rule \
        --rule-name IoTAnalyticsRule \
        --topic-rule-payload '{
            \"sql\": \"SELECT * FROM \\\"topic/sensor/data\\\"\",
            \"description\": \"Route sensor data to IoT Analytics\",
            \"actions\": [
                {
                    \"iotAnalytics\": {
                        \"channelName\": \"'$CHANNEL_NAME'\"
                    }
                }
            ]
        }' --output table" "Creating IoT rule"
}

# Function to create modern alternative resources
create_modern_resources() {
    log "Creating modern alternative resources (Kinesis + Timestream)..."
    
    # Create Kinesis stream
    execute_cmd "aws kinesis create-stream \
        --stream-name $KINESIS_STREAM_NAME \
        --shard-count 1 \
        --output table" "Creating Kinesis Data Stream"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for Kinesis stream to become active..."
        aws kinesis wait stream-exists --stream-name $KINESIS_STREAM_NAME
    fi
    
    # Create Timestream database
    execute_cmd "aws timestream-write create-database \
        --database-name $TIMESTREAM_DATABASE_NAME \
        --output table" "Creating Timestream database"
    
    # Create Timestream table
    execute_cmd "aws timestream-write create-table \
        --database-name $TIMESTREAM_DATABASE_NAME \
        --table-name $TIMESTREAM_TABLE_NAME \
        --retention-properties '{
            \"MemoryStoreRetentionPeriodInHours\": 24,
            \"MagneticStoreRetentionPeriodInDays\": 365
        }' --output table" "Creating Timestream table"
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function for data processing..."
    
    # Create Lambda function code
    cat > /tmp/lambda_function.py << 'EOF'
import json
import boto3
import time
import base64
from datetime import datetime

timestream = boto3.client('timestream-write')

def lambda_handler(event, context):
    database_name = os.environ['TIMESTREAM_DATABASE_NAME']
    table_name = os.environ['TIMESTREAM_TABLE_NAME']
    
    records = []
    
    for record in event['Records']:
        # Parse Kinesis record
        try:
            # Decode base64 data
            data = base64.b64decode(record['kinesis']['data']).decode('utf-8')
            payload = json.loads(data)
            
            # Prepare Timestream record
            current_time = str(int(time.time() * 1000))
            
            timestream_record = {
                'Time': current_time,
                'TimeUnit': 'MILLISECONDS',
                'Dimensions': [
                    {
                        'Name': 'DeviceId',
                        'Value': payload.get('deviceId', 'unknown')
                    },
                    {
                        'Name': 'Location',
                        'Value': 'factory_floor_1'
                    }
                ],
                'MeasureName': 'temperature',
                'MeasureValue': str(payload.get('temperature', 0)),
                'MeasureValueType': 'DOUBLE'
            }
            
            records.append(timestream_record)
            
        except Exception as e:
            print(f"Error processing record: {e}")
            continue
    
    # Write to Timestream
    if records:
        try:
            timestream.write_records(
                DatabaseName=database_name,
                TableName=table_name,
                Records=records
            )
            print(f"Successfully wrote {len(records)} records to Timestream")
        except Exception as e:
            print(f"Error writing to Timestream: {e}")
            raise
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Processed {len(records)} records')
    }
EOF

    if [[ "$DRY_RUN" == "false" ]]; then
        # Create zip file
        cd /tmp
        zip lambda_function.zip lambda_function.py
        cd - > /dev/null
    fi
    
    # Create Lambda function
    execute_cmd "aws lambda create-function \
        --function-name ProcessIoTData \
        --runtime python3.9 \
        --role $LAMBDA_TIMESTREAM_ROLE_ARN \
        --handler lambda_function.lambda_handler \
        --zip-file fileb:///tmp/lambda_function.zip \
        --timeout 60 \
        --environment Variables='{
            \"TIMESTREAM_DATABASE_NAME\": \"'$TIMESTREAM_DATABASE_NAME'\",
            \"TIMESTREAM_TABLE_NAME\": \"'$TIMESTREAM_TABLE_NAME'\"
        }' \
        --output table" "Creating Lambda function"
    
    # Create event source mapping
    execute_cmd "aws lambda create-event-source-mapping \
        --event-source-arn arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/${KINESIS_STREAM_NAME} \
        --function-name ProcessIoTData \
        --starting-position LATEST \
        --output table" "Creating event source mapping"
    
    # Clean up temporary files
    if [[ "$DRY_RUN" == "false" ]]; then
        rm -f /tmp/lambda_function.py /tmp/lambda_function.zip
    fi
}

# Function to send test data
send_test_data() {
    log "Sending test data to verify deployment..."
    
    # Send test data to IoT Analytics
    execute_cmd "aws iotanalytics batch-put-message \
        --channel-name $CHANNEL_NAME \
        --messages '[
            {
                \"messageId\": \"msg001\",
                \"payload\": \"'$(echo -n '{"timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'", "deviceId": "sensor001", "temperature": 23.5, "humidity": 65.2}' | base64)'\"
            },
            {
                \"messageId\": \"msg002\", 
                \"payload\": \"'$(echo -n '{"timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'", "deviceId": "sensor002", "temperature": 28.7, "humidity": 58.9}' | base64)'\"
            }
        ]' --output table" "Sending test data to IoT Analytics"
    
    # Send test data to Kinesis
    execute_cmd "aws kinesis put-record \
        --stream-name $KINESIS_STREAM_NAME \
        --partition-key sensor001 \
        --data '{\"timestamp\": \"'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'\", \"deviceId\": \"sensor001\", \"temperature\": 26.3, \"humidity\": 60.1}' \
        --output table" "Sending test data to Kinesis"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "==================="
    echo "AWS Region: $AWS_REGION"
    echo "Account ID: $AWS_ACCOUNT_ID"
    echo ""
    echo "IoT Analytics Resources:"
    echo "- Channel: $CHANNEL_NAME"
    echo "- Pipeline: $PIPELINE_NAME"
    echo "- Datastore: $DATASTORE_NAME"
    echo "- Dataset: $DATASET_NAME"
    echo ""
    echo "Modern Alternative Resources:"
    echo "- Kinesis Stream: $KINESIS_STREAM_NAME"
    echo "- Timestream Database: $TIMESTREAM_DATABASE_NAME"
    echo "- Timestream Table: $TIMESTREAM_TABLE_NAME"
    echo "- Lambda Function: ProcessIoTData"
    echo ""
    echo "IAM Roles:"
    echo "- IoT Analytics Service Role: IoTAnalyticsServiceRole"
    echo "- Lambda Timestream Role: LambdaTimestreamRole"
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        warn "Important: AWS IoT Analytics reaches end-of-support on December 15, 2025"
        warn "Consider migrating to the modern alternative (Kinesis + Timestream) for production workloads"
        echo ""
        log "Deployment completed successfully!"
        echo "You can now test the IoT Analytics pipeline by sending data to the 'topic/sensor/data' MQTT topic"
        echo "Use the destroy.sh script to clean up resources when done testing"
    else
        log "Dry-run completed successfully!"
    fi
}

# Main deployment function
main() {
    log "Starting IoT Analytics Pipeline deployment..."
    
    check_prerequisites
    setup_environment
    create_iam_roles
    create_iot_analytics_resources
    create_modern_resources
    create_lambda_function
    
    if [[ "$DRY_RUN" == "false" ]]; then
        send_test_data
    fi
    
    display_summary
}

# Error handling
trap 'error "Deployment failed on line $LINENO. Exit code: $?"; exit 1' ERR

# Run main function
main "$@"