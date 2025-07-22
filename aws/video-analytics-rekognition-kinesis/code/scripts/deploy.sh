#!/bin/bash

# Real-Time Video Analytics with Rekognition and Kinesis - Deployment Script
# This script deploys the complete video analytics infrastructure including:
# - Kinesis Video Streams for video ingestion
# - Rekognition face collections and stream processors
# - Lambda functions for analytics processing
# - DynamoDB tables for metadata storage
# - API Gateway for query interface
# - SNS for alerting

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check required tools
    for tool in zip python3 curl; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is not installed. Please install $tool."
            exit 1
        fi
    done
    
    success "All prerequisites met"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No default region set, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export PROJECT_NAME="video-analytics-${RANDOM_SUFFIX}"
    export STREAM_NAME="security-stream-${RANDOM_SUFFIX}"
    export ROLE_NAME="VideoAnalyticsRole-${RANDOM_SUFFIX}"
    export COLLECTION_NAME="security-faces-${RANDOM_SUFFIX}"
    
    log "Project Name: $PROJECT_NAME"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    
    # Save environment variables for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
PROJECT_NAME=${PROJECT_NAME}
STREAM_NAME=${STREAM_NAME}
ROLE_NAME=${ROLE_NAME}
COLLECTION_NAME=${COLLECTION_NAME}
EOF
    
    success "Environment variables configured"
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for video analytics..."
    
    cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "lambda.amazonaws.com",
          "rekognition.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    if aws iam get-role --role-name ${ROLE_NAME} &> /dev/null; then
        warning "IAM role ${ROLE_NAME} already exists, skipping creation"
    else
        aws iam create-role \
            --role-name ${ROLE_NAME} \
            --assume-role-policy-document file://trust-policy.json
        
        log "Waiting for IAM role to be available..."
        sleep 10
    fi
    
    # Attach required policies
    for policy in \
        "arn:aws:iam::aws:policy/AmazonRekognitionFullAccess" \
        "arn:aws:iam::aws:policy/AmazonKinesisVideoStreamsFullAccess" \
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess" \
        "arn:aws:iam::aws:policy/AmazonKinesisFullAccess" \
        "arn:aws:iam::aws:policy/AmazonSNSFullAccess"; do
        
        if aws iam list-attached-role-policies --role-name ${ROLE_NAME} --query "AttachedPolicies[?PolicyArn=='$policy']" --output text | grep -q "$policy"; then
            warning "Policy $policy already attached to role ${ROLE_NAME}"
        else
            aws iam attach-role-policy \
                --role-name ${ROLE_NAME} \
                --policy-arn $policy
        fi
    done
    
    export ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
    echo "ROLE_ARN=${ROLE_ARN}" >> .env
    
    success "IAM role created and configured"
}

# Function to create Kinesis Video Stream
create_video_stream() {
    log "Creating Kinesis Video Stream..."
    
    if aws kinesisvideo describe-stream --stream-name ${STREAM_NAME} &> /dev/null; then
        warning "Kinesis Video Stream ${STREAM_NAME} already exists"
    else
        aws kinesisvideo create-stream \
            --stream-name ${STREAM_NAME} \
            --data-retention-in-hours 24 \
            --media-type "video/h264"
    fi
    
    # Get stream information
    STREAM_ARN=$(aws kinesisvideo describe-stream \
        --stream-name ${STREAM_NAME} \
        --query 'StreamInfo.StreamARN' \
        --output text)
    
    echo "STREAM_ARN=${STREAM_ARN}" >> .env
    
    success "Kinesis Video Stream created: ${STREAM_ARN}"
}

# Function to create face collection
create_face_collection() {
    log "Creating Rekognition face collection..."
    
    if aws rekognition describe-collection --collection-id ${COLLECTION_NAME} &> /dev/null; then
        warning "Face collection ${COLLECTION_NAME} already exists"
    else
        aws rekognition create-collection --collection-id ${COLLECTION_NAME}
    fi
    
    success "Face collection created: ${COLLECTION_NAME}"
}

# Function to create data stream
create_data_stream() {
    log "Creating Kinesis Data Stream for analytics..."
    
    if aws kinesis describe-stream --stream-name "${PROJECT_NAME}-analytics" &> /dev/null; then
        warning "Kinesis Data Stream ${PROJECT_NAME}-analytics already exists"
    else
        aws kinesis create-stream \
            --stream-name "${PROJECT_NAME}-analytics" \
            --shard-count 2
        
        log "Waiting for data stream to become active..."
        aws kinesis wait stream-exists \
            --stream-name "${PROJECT_NAME}-analytics"
    fi
    
    DATA_STREAM_ARN="arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/${PROJECT_NAME}-analytics"
    echo "DATA_STREAM_ARN=${DATA_STREAM_ARN}" >> .env
    
    success "Analytics data stream created: ${DATA_STREAM_ARN}"
}

# Function to create DynamoDB tables
create_dynamodb_tables() {
    log "Creating DynamoDB tables..."
    
    # Create detections table
    if aws dynamodb describe-table --table-name "${PROJECT_NAME}-detections" &> /dev/null; then
        warning "DynamoDB table ${PROJECT_NAME}-detections already exists"
    else
        aws dynamodb create-table \
            --table-name "${PROJECT_NAME}-detections" \
            --attribute-definitions \
                AttributeName=StreamName,AttributeType=S \
                AttributeName=Timestamp,AttributeType=N \
            --key-schema \
                AttributeName=StreamName,KeyType=HASH \
                AttributeName=Timestamp,KeyType=RANGE \
            --provisioned-throughput \
                ReadCapacityUnits=5,WriteCapacityUnits=5
        
        log "Waiting for detections table to be active..."
        aws dynamodb wait table-exists \
            --table-name "${PROJECT_NAME}-detections"
    fi
    
    # Create faces table
    if aws dynamodb describe-table --table-name "${PROJECT_NAME}-faces" &> /dev/null; then
        warning "DynamoDB table ${PROJECT_NAME}-faces already exists"
    else
        aws dynamodb create-table \
            --table-name "${PROJECT_NAME}-faces" \
            --attribute-definitions \
                AttributeName=FaceId,AttributeType=S \
                AttributeName=Timestamp,AttributeType=N \
            --key-schema \
                AttributeName=FaceId,KeyType=HASH \
                AttributeName=Timestamp,KeyType=RANGE \
            --provisioned-throughput \
                ReadCapacityUnits=5,WriteCapacityUnits=5
        
        log "Waiting for faces table to be active..."
        aws dynamodb wait table-exists \
            --table-name "${PROJECT_NAME}-faces"
    fi
    
    success "DynamoDB tables created"
}

# Function to create Lambda function for analytics processing
create_analytics_lambda() {
    log "Creating analytics processing Lambda function..."
    
    cat > analytics_processor.py << 'EOF'
import json
import boto3
import base64
from datetime import datetime
import os

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
rekognition = boto3.client('rekognition')

DETECTIONS_TABLE = os.environ['DETECTIONS_TABLE']
FACES_TABLE = os.environ['FACES_TABLE']
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')

def lambda_handler(event, context):
    for record in event['Records']:
        # Decode Kinesis data
        payload = base64.b64decode(record['kinesis']['data'])
        data = json.loads(payload)
        
        try:
            process_detection_event(data)
        except Exception as e:
            print(f"Error processing record: {str(e)}")
            
    return {'statusCode': 200}

def process_detection_event(data):
    timestamp = datetime.now().timestamp()
    stream_name = data.get('StreamName', 'unknown')
    
    # Process face detections
    if 'FaceSearchResponse' in data:
        process_face_detection(data['FaceSearchResponse'], stream_name, timestamp)
    
    # Process label detections
    if 'LabelDetectionResponse' in data:
        process_label_detection(data['LabelDetectionResponse'], stream_name, timestamp)
    
    # Process person tracking
    if 'PersonTrackingResponse' in data:
        process_person_tracking(data['PersonTrackingResponse'], stream_name, timestamp)

def process_face_detection(face_data, stream_name, timestamp):
    table = dynamodb.Table(FACES_TABLE)
    
    for face_match in face_data.get('FaceMatches', []):
        face_id = face_match['Face']['FaceId']
        confidence = face_match['Face']['Confidence']
        similarity = face_match['Similarity']
        
        # Store face detection event
        table.put_item(
            Item={
                'FaceId': face_id,
                'Timestamp': int(timestamp * 1000),
                'StreamName': stream_name,
                'Confidence': str(confidence),
                'Similarity': str(similarity),
                'BoundingBox': face_match['Face']['BoundingBox']
            }
        )
        
        # Send alert for high-confidence matches
        if similarity > 90:
            send_alert(f"High confidence face match detected: {face_id}", 
                      f"Similarity: {similarity}%, Stream: {stream_name}")

def process_label_detection(label_data, stream_name, timestamp):
    table = dynamodb.Table(DETECTIONS_TABLE)
    
    for label in label_data.get('Labels', []):
        label_name = label['Label']['Name']
        confidence = label['Label']['Confidence']
        
        # Store detection event
        table.put_item(
            Item={
                'StreamName': stream_name,
                'Timestamp': int(timestamp * 1000),
                'DetectionType': 'Label',
                'Label': label_name,
                'Confidence': str(confidence),
                'BoundingBox': json.dumps(label['Label'].get('BoundingBox', {}))
            }
        )
        
        # Check for security-relevant objects
        security_objects = ['Weapon', 'Gun', 'Knife', 'Person', 'Car', 'Motorcycle']
        if label_name in security_objects and confidence > 80:
            send_alert(f"Security object detected: {label_name}", 
                      f"Confidence: {confidence}%, Stream: {stream_name}")

def process_person_tracking(person_data, stream_name, timestamp):
    table = dynamodb.Table(DETECTIONS_TABLE)
    
    for person in person_data.get('Persons', []):
        person_id = person.get('Index', 'unknown')
        
        # Store person tracking event
        table.put_item(
            Item={
                'StreamName': stream_name,
                'Timestamp': int(timestamp * 1000),
                'DetectionType': 'Person',
                'PersonId': str(person_id),
                'BoundingBox': json.dumps(person.get('BoundingBox', {}))
            }
        )

def send_alert(subject, message):
    if SNS_TOPIC_ARN:
        try:
            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject=subject,
                Message=message
            )
        except Exception as e:
            print(f"Failed to send alert: {str(e)}")
EOF
    
    # Create deployment package
    zip analytics_processor.zip analytics_processor.py
    
    # Create or update Lambda function
    if aws lambda get-function --function-name "${PROJECT_NAME}-analytics-processor" &> /dev/null; then
        warning "Lambda function ${PROJECT_NAME}-analytics-processor already exists, updating code"
        aws lambda update-function-code \
            --function-name "${PROJECT_NAME}-analytics-processor" \
            --zip-file fileb://analytics_processor.zip
    else
        aws lambda create-function \
            --function-name "${PROJECT_NAME}-analytics-processor" \
            --runtime python3.9 \
            --role ${ROLE_ARN} \
            --handler analytics_processor.lambda_handler \
            --zip-file fileb://analytics_processor.zip \
            --timeout 60 \
            --environment Variables="{DETECTIONS_TABLE=${PROJECT_NAME}-detections,FACES_TABLE=${PROJECT_NAME}-faces}"
    fi
    
    success "Analytics processing Lambda function created"
}

# Function to create stream processor
create_stream_processor() {
    log "Creating Rekognition stream processor..."
    
    # Source environment variables
    source .env
    
    cat > stream_processor_config.json << EOF
{
  "Name": "${PROJECT_NAME}-processor",
  "Input": {
    "KinesisVideoStream": {
      "Arn": "${STREAM_ARN}"
    }
  },
  "Output": {
    "KinesisDataStream": {
      "Arn": "${DATA_STREAM_ARN}"
    }
  },
  "RoleArn": "${ROLE_ARN}",
  "Settings": {
    "FaceSearch": {
      "CollectionId": "${COLLECTION_NAME}",
      "FaceMatchThreshold": 80.0
    }
  }
}
EOF
    
    if aws rekognition describe-stream-processor --name "${PROJECT_NAME}-processor" &> /dev/null; then
        warning "Stream processor ${PROJECT_NAME}-processor already exists"
    else
        aws rekognition create-stream-processor \
            --cli-input-json file://stream_processor_config.json
        
        log "Starting stream processor..."
        sleep 5
        aws rekognition start-stream-processor \
            --name "${PROJECT_NAME}-processor"
    fi
    
    success "Rekognition stream processor created and started"
}

# Function to configure Lambda trigger
configure_lambda_trigger() {
    log "Configuring Lambda trigger for data stream..."
    
    # Source environment variables
    source .env
    
    # Check if event source mapping already exists
    EXISTING_MAPPING=$(aws lambda list-event-source-mappings \
        --function-name "${PROJECT_NAME}-analytics-processor" \
        --query "EventSourceMappings[?EventSourceArn=='${DATA_STREAM_ARN}'].UUID" \
        --output text)
    
    if [ -n "$EXISTING_MAPPING" ]; then
        warning "Event source mapping already exists for Lambda function"
    else
        aws lambda create-event-source-mapping \
            --function-name "${PROJECT_NAME}-analytics-processor" \
            --event-source-arn ${DATA_STREAM_ARN} \
            --starting-position LATEST \
            --batch-size 10
    fi
    
    success "Lambda trigger configured for analytics processing"
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic for security alerts..."
    
    TOPIC_ARN=$(aws sns create-topic \
        --name "${PROJECT_NAME}-security-alerts" \
        --query 'TopicArn' --output text)
    
    echo "TOPIC_ARN=${TOPIC_ARN}" >> .env
    
    # Update Lambda environment with SNS topic
    aws lambda update-function-configuration \
        --function-name "${PROJECT_NAME}-analytics-processor" \
        --environment Variables="{DETECTIONS_TABLE=${PROJECT_NAME}-detections,FACES_TABLE=${PROJECT_NAME}-faces,SNS_TOPIC_ARN=${TOPIC_ARN}}"
    
    log "SNS topic created: ${TOPIC_ARN}"
    log "To receive email alerts, subscribe to the topic:"
    log "aws sns subscribe --topic-arn ${TOPIC_ARN} --protocol email --notification-endpoint your-email@example.com"
    
    success "SNS topic created and Lambda function updated"
}

# Function to create query API
create_query_api() {
    log "Creating API for video analytics queries..."
    
    cat > query_api.py << 'EOF'
import json
import boto3
from boto3.dynamodb.conditions import Key
from datetime import datetime, timedelta

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        # Parse request
        http_method = event['httpMethod']
        path = event['path']
        query_params = event.get('queryStringParameters', {}) or {}
        
        if path == '/detections' and http_method == 'GET':
            return get_detections(query_params)
        elif path == '/faces' and http_method == 'GET':
            return get_face_detections(query_params)
        elif path == '/stats' and http_method == 'GET':
            return get_statistics(query_params)
        else:
            return {
                'statusCode': 404,
                'body': json.dumps({'error': 'Not found'})
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_detections(params):
    table = dynamodb.Table(f"{params.get('project', 'video-analytics')}-detections")
    
    stream_name = params.get('stream')
    hours_back = int(params.get('hours', 24))
    
    if not stream_name:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'stream parameter required'})
        }
    
    # Query recent detections
    start_time = int((datetime.now() - timedelta(hours=hours_back)).timestamp() * 1000)
    
    response = table.query(
        KeyConditionExpression=Key('StreamName').eq(stream_name) & 
                             Key('Timestamp').gte(start_time),
        ScanIndexForward=False,
        Limit=100
    )
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'detections': response['Items'],
            'count': len(response['Items'])
        })
    }

def get_face_detections(params):
    table = dynamodb.Table(f"{params.get('project', 'video-analytics')}-faces")
    
    # Scan recent face detections (in production, use GSI for better performance)
    response = table.scan(
        Limit=50
    )
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'faces': response['Items'],
            'count': len(response['Items'])
        })
    }

def get_statistics(params):
    # Simple statistics - in production, use ElasticSearch or analytics service
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'message': 'Statistics endpoint - implement with your analytics requirements',
            'timestamp': datetime.now().isoformat()
        })
    }
EOF
    
    # Create deployment package
    zip query_api.zip query_api.py
    
    # Create or update API Lambda function
    if aws lambda get-function --function-name "${PROJECT_NAME}-query-api" &> /dev/null; then
        warning "Lambda function ${PROJECT_NAME}-query-api already exists, updating code"
        aws lambda update-function-code \
            --function-name "${PROJECT_NAME}-query-api" \
            --zip-file fileb://query_api.zip
    else
        aws lambda create-function \
            --function-name "${PROJECT_NAME}-query-api" \
            --runtime python3.9 \
            --role ${ROLE_ARN} \
            --handler query_api.lambda_handler \
            --zip-file fileb://query_api.zip \
            --timeout 30
    fi
    
    # Create API Gateway
    API_ID=$(aws apigatewayv2 create-api \
        --name "${PROJECT_NAME}-api" \
        --protocol-type HTTP \
        --target "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-query-api" \
        --query 'ApiId' --output text)
    
    echo "API_ID=${API_ID}" >> .env
    
    # Add Lambda permission for API Gateway
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-query-api" \
        --statement-id api-gateway-invoke \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*" \
        2>/dev/null || warning "Lambda permission may already exist"
    
    # Get API endpoint
    API_ENDPOINT=$(aws apigatewayv2 get-api \
        --api-id ${API_ID} \
        --query 'ApiEndpoint' --output text)
    
    echo "API_ENDPOINT=${API_ENDPOINT}" >> .env
    
    success "Query API created: ${API_ENDPOINT}"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Source environment variables
    source .env
    
    # Check stream processor status
    PROCESSOR_STATUS=$(aws rekognition describe-stream-processor \
        --name "${PROJECT_NAME}-processor" \
        --query 'Status' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$PROCESSOR_STATUS" = "RUNNING" ]; then
        success "Stream processor is running"
    else
        warning "Stream processor status: $PROCESSOR_STATUS"
    fi
    
    # Check data stream status
    STREAM_STATUS=$(aws kinesis describe-stream \
        --stream-name "${PROJECT_NAME}-analytics" \
        --query 'StreamDescription.StreamStatus' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$STREAM_STATUS" = "ACTIVE" ]; then
        success "Analytics data stream is active"
    else
        warning "Analytics data stream status: $STREAM_STATUS"
    fi
    
    # Test API endpoints
    if [ -n "$API_ENDPOINT" ]; then
        log "Testing API endpoints..."
        
        # Test stats endpoint
        STATS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "${API_ENDPOINT}/stats" || echo "000")
        if [ "$STATS_RESPONSE" = "200" ]; then
            success "API stats endpoint is responding"
        else
            warning "API stats endpoint returned status: $STATS_RESPONSE"
        fi
    fi
    
    log "Deployment validation complete"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f trust-policy.json stream_processor_config.json \
          analytics_processor.py analytics_processor.zip \
          query_api.py query_api.zip
    success "Temporary files cleaned up"
}

# Main deployment function
main() {
    log "Starting Real-Time Video Analytics deployment..."
    log "This will create AWS resources that may incur charges."
    
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
    
    check_prerequisites
    setup_environment
    create_iam_role
    create_video_stream
    create_face_collection
    create_data_stream
    create_dynamodb_tables
    create_analytics_lambda
    create_stream_processor
    configure_lambda_trigger
    create_sns_topic
    create_query_api
    validate_deployment
    cleanup_temp_files
    
    success "Deployment completed successfully!"
    
    echo
    log "=== DEPLOYMENT SUMMARY ==="
    log "Project Name: $PROJECT_NAME"
    log "Stream Name: $STREAM_NAME"
    log "Face Collection: $COLLECTION_NAME"
    source .env
    log "API Endpoint: $API_ENDPOINT"
    log "SNS Topic: $TOPIC_ARN"
    echo
    log "=== NEXT STEPS ==="
    log "1. Subscribe to SNS alerts:"
    log "   aws sns subscribe --topic-arn $TOPIC_ARN --protocol email --notification-endpoint your-email@example.com"
    log "2. Send test video to Kinesis Video Stream: $STREAM_NAME"
    log "3. Monitor DynamoDB tables for detection results"
    log "4. Query API endpoints for analytics data"
    echo
    warning "Remember to run ./destroy.sh when done to avoid ongoing charges!"
}

# Handle script interruption
trap 'error "Script interrupted"; cleanup_temp_files; exit 1' INT TERM

# Run main function
main