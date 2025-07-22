#!/bin/bash

# Deploy script for Video Conferencing Solutions with Amazon Chime SDK
# This script deploys the complete infrastructure for custom video conferencing
# Author: AWS Recipes Project
# Version: 1.0

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_BASE_NAME="video-conferencing"
DEPLOYMENT_TIMEOUT=900  # 15 minutes
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-name)
            PROJECT_BASE_NAME="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --project-name NAME    Set project name prefix (default: video-conferencing)"
            echo "  --region REGION        Set AWS region (default: from AWS CLI config)"
            echo "  --dry-run              Show what would be deployed without executing"
            echo "  --help, -h             Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Get account information
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not set. Please specify with --region or configure default region."
        exit 1
    fi
    
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "AWS Region: $AWS_REGION"
    
    # Check if Node.js is installed (for Lambda packaging)
    if ! command -v node &> /dev/null; then
        error "Node.js is not installed. Please install Node.js 18+ for Lambda function packaging."
        exit 1
    fi
    
    NODE_VERSION=$(node --version)
    log "Node.js version: $NODE_VERSION"
    
    # Check if npm is installed
    if ! command -v npm &> /dev/null; then
        error "npm is not installed. Please install npm."
        exit 1
    fi
    
    # Check required permissions
    log "Checking AWS permissions..."
    
    local required_services=("chime" "lambda" "apigateway" "dynamodb" "s3" "sns" "iam")
    for service in "${required_services[@]}"; do
        case $service in
            "chime")
                if ! aws chime list-meetings --region us-east-1 &> /dev/null && ! aws logs describe-log-groups --limit 1 &> /dev/null; then
                    warn "Unable to verify Chime SDK permissions. Ensure you have chime:* permissions."
                fi
                ;;
            "lambda")
                if ! aws lambda list-functions --region "$AWS_REGION" &> /dev/null; then
                    error "Missing Lambda permissions. Required: lambda:*"
                    exit 1
                fi
                ;;
            "apigateway")
                if ! aws apigateway get-rest-apis --region "$AWS_REGION" &> /dev/null; then
                    error "Missing API Gateway permissions. Required: apigateway:*"
                    exit 1
                fi
                ;;
            "dynamodb")
                if ! aws dynamodb list-tables --region "$AWS_REGION" &> /dev/null; then
                    error "Missing DynamoDB permissions. Required: dynamodb:*"
                    exit 1
                fi
                ;;
            "s3")
                if ! aws s3 ls &> /dev/null; then
                    error "Missing S3 permissions. Required: s3:*"
                    exit 1
                fi
                ;;
            "sns")
                if ! aws sns list-topics --region "$AWS_REGION" &> /dev/null; then
                    error "Missing SNS permissions. Required: sns:*"
                    exit 1
                fi
                ;;
            "iam")
                if ! aws iam list-roles --max-items 1 &> /dev/null; then
                    error "Missing IAM permissions. Required: iam:*"
                    exit 1
                fi
                ;;
        esac
    done
    
    success "Prerequisites check completed successfully"
}

# Function to generate unique resource names
generate_resource_names() {
    log "Generating unique resource names..."
    
    # Generate random suffix for uniqueness
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    
    export PROJECT_NAME="${PROJECT_BASE_NAME}-${RANDOM_SUFFIX}"
    export BUCKET_NAME="${PROJECT_NAME}-recordings"
    export TABLE_NAME="${PROJECT_NAME}-meetings"
    export SNS_TOPIC_NAME="${PROJECT_NAME}-events"
    export LAMBDA_ROLE_NAME="${PROJECT_NAME}-lambda-role"
    export MEETING_LAMBDA_NAME="${PROJECT_NAME}-meeting-handler"
    export ATTENDEE_LAMBDA_NAME="${PROJECT_NAME}-attendee-handler"
    export API_NAME="${PROJECT_NAME}-api"
    
    log "Project Name: $PROJECT_NAME"
    log "S3 Bucket: $BUCKET_NAME"
    log "DynamoDB Table: $TABLE_NAME"
    log "SNS Topic: $SNS_TOPIC_NAME"
}

# Function to create foundation resources
create_foundation_resources() {
    log "Creating foundation resources..."
    
    # Create S3 bucket for recordings
    log "Creating S3 bucket: $BUCKET_NAME"
    if $DRY_RUN; then
        log "DRY RUN: Would create S3 bucket $BUCKET_NAME"
    else
        if aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION"; then
            success "S3 bucket created: $BUCKET_NAME"
            
            # Enable versioning and encryption
            aws s3api put-bucket-versioning \
                --bucket "$BUCKET_NAME" \
                --versioning-configuration Status=Enabled
            
            aws s3api put-bucket-encryption \
                --bucket "$BUCKET_NAME" \
                --server-side-encryption-configuration '{
                    "Rules": [{
                        "ApplyServerSideEncryptionByDefault": {
                            "SSEAlgorithm": "AES256"
                        }
                    }]
                }'
        else
            error "Failed to create S3 bucket: $BUCKET_NAME"
            exit 1
        fi
    fi
    
    # Create DynamoDB table
    log "Creating DynamoDB table: $TABLE_NAME"
    if $DRY_RUN; then
        log "DRY RUN: Would create DynamoDB table $TABLE_NAME"
    else
        if aws dynamodb create-table \
            --table-name "$TABLE_NAME" \
            --attribute-definitions \
                AttributeName=MeetingId,AttributeType=S \
                AttributeName=CreatedAt,AttributeType=S \
            --key-schema \
                AttributeName=MeetingId,KeyType=HASH \
                AttributeName=CreatedAt,KeyType=RANGE \
            --provisioned-throughput \
                ReadCapacityUnits=5,WriteCapacityUnits=5 \
            --region "$AWS_REGION" > /dev/null; then
            
            success "DynamoDB table created: $TABLE_NAME"
            
            # Wait for table to be active
            log "Waiting for DynamoDB table to become active..."
            aws dynamodb wait table-exists --table-name "$TABLE_NAME" --region "$AWS_REGION"
        else
            error "Failed to create DynamoDB table: $TABLE_NAME"
            exit 1
        fi
    fi
    
    # Create SNS topic
    log "Creating SNS topic: $SNS_TOPIC_NAME"
    if $DRY_RUN; then
        log "DRY RUN: Would create SNS topic $SNS_TOPIC_NAME"
        export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    else
        if aws sns create-topic \
            --name "$SNS_TOPIC_NAME" \
            --region "$AWS_REGION" > /dev/null; then
            
            export SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
                --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" \
                --query 'Attributes.TopicArn' --output text)
            
            success "SNS topic created: $SNS_TOPIC_ARN"
        else
            error "Failed to create SNS topic: $SNS_TOPIC_NAME"
            exit 1
        fi
    fi
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for Lambda functions..."
    
    if $DRY_RUN; then
        log "DRY RUN: Would create IAM role $LAMBDA_ROLE_NAME"
        export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
        return
    fi
    
    # Create trust policy
    cat > /tmp/lambda-trust-policy.json << EOF
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
    
    # Create IAM role
    if aws iam create-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json > /dev/null; then
        
        success "IAM role created: $LAMBDA_ROLE_NAME"
    else
        error "Failed to create IAM role: $LAMBDA_ROLE_NAME"
        exit 1
    fi
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for Chime SDK and other services
    cat > /tmp/chime-sdk-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "chime:CreateMeeting",
                "chime:DeleteMeeting",
                "chime:GetMeeting",
                "chime:ListMeetings",
                "chime:CreateAttendee",
                "chime:DeleteAttendee",
                "chime:GetAttendee",
                "chime:ListAttendees",
                "chime:BatchCreateAttendee",
                "chime:BatchDeleteAttendee",
                "chime:StartMeetingTranscription",
                "chime:StopMeetingTranscription"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${TABLE_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject"
            ],
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "${SNS_TOPIC_ARN}"
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-name ChimeSDKPolicy \
        --policy-document file:///tmp/chime-sdk-policy.json
    
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --query 'Role.Arn' --output text)
    
    # Wait for role to be available
    log "Waiting for IAM role to be available..."
    sleep 10
    
    success "IAM role configured: $LAMBDA_ROLE_ARN"
}

# Function to create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    if $DRY_RUN; then
        log "DRY RUN: Would create Lambda functions"
        return
    fi
    
    # Create temp directory for Lambda code
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Create meeting handler Lambda
    log "Creating meeting handler Lambda function..."
    
    cat > meeting-handler.js << 'EOF'
const AWS = require('aws-sdk');
const { v4: uuidv4 } = require('uuid');

const chime = new AWS.ChimeSDKMeetings({
    region: process.env.AWS_REGION,
    endpoint: `https://meetings-chime.${process.env.AWS_REGION}.amazonaws.com`
});

const dynamodb = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event) => {
    const { httpMethod, path, body } = event;
    
    try {
        switch (httpMethod) {
            case 'POST':
                if (path === '/meetings') {
                    return await createMeeting(JSON.parse(body));
                }
                break;
            case 'GET':
                if (path.startsWith('/meetings/')) {
                    const meetingId = path.split('/')[2];
                    return await getMeeting(meetingId);
                }
                break;
            case 'DELETE':
                if (path.startsWith('/meetings/')) {
                    const meetingId = path.split('/')[2];
                    return await deleteMeeting(meetingId);
                }
                break;
        }
        
        return {
            statusCode: 404,
            body: JSON.stringify({ error: 'Not found' })
        };
    } catch (error) {
        console.error('Error:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: 'Internal server error' })
        };
    }
};

async function createMeeting(requestBody) {
    const { externalMeetingId, mediaRegion, meetingHostId } = requestBody;
    
    const meetingRequest = {
        ClientRequestToken: uuidv4(),
        ExternalMeetingId: externalMeetingId || uuidv4(),
        MediaRegion: mediaRegion || process.env.AWS_REGION,
        MeetingHostId: meetingHostId,
        NotificationsConfiguration: {
            SnsTopicArn: process.env.SNS_TOPIC_ARN
        },
        MeetingFeatures: {
            Audio: {
                EchoReduction: 'AVAILABLE'
            },
            Video: {
                MaxResolution: 'HD'
            },
            Content: {
                MaxResolution: 'FHD'
            }
        }
    };
    
    const meeting = await chime.createMeeting(meetingRequest).promise();
    
    // Store meeting metadata in DynamoDB
    await dynamodb.put({
        TableName: process.env.TABLE_NAME,
        Item: {
            MeetingId: meeting.Meeting.MeetingId,
            CreatedAt: new Date().toISOString(),
            ExternalMeetingId: meeting.Meeting.ExternalMeetingId,
            MediaRegion: meeting.Meeting.MediaRegion,
            Status: 'ACTIVE'
        }
    }).promise();
    
    return {
        statusCode: 201,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
            Meeting: meeting.Meeting
        })
    };
}

async function getMeeting(meetingId) {
    const meeting = await chime.getMeeting({ MeetingId: meetingId }).promise();
    
    return {
        statusCode: 200,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
            Meeting: meeting.Meeting
        })
    };
}

async function deleteMeeting(meetingId) {
    await chime.deleteMeeting({ MeetingId: meetingId }).promise();
    
    // Update meeting status in DynamoDB
    await dynamodb.update({
        TableName: process.env.TABLE_NAME,
        Key: { MeetingId: meetingId },
        UpdateExpression: 'SET #status = :status, UpdatedAt = :updatedAt',
        ExpressionAttributeNames: {
            '#status': 'Status'
        },
        ExpressionAttributeValues: {
            ':status': 'DELETED',
            ':updatedAt': new Date().toISOString()
        }
    }).promise();
    
    return {
        statusCode: 204,
        headers: {
            'Access-Control-Allow-Origin': '*'
        }
    };
}
EOF
    
    # Create attendee handler Lambda
    log "Creating attendee handler Lambda function..."
    
    cat > attendee-handler.js << 'EOF'
const AWS = require('aws-sdk');
const { v4: uuidv4 } = require('uuid');

const chime = new AWS.ChimeSDKMeetings({
    region: process.env.AWS_REGION,
    endpoint: `https://meetings-chime.${process.env.AWS_REGION}.amazonaws.com`
});

exports.handler = async (event) => {
    const { httpMethod, path, body } = event;
    
    try {
        switch (httpMethod) {
            case 'POST':
                if (path.startsWith('/meetings/') && path.endsWith('/attendees')) {
                    const meetingId = path.split('/')[2];
                    return await createAttendee(meetingId, JSON.parse(body));
                }
                break;
            case 'GET':
                if (path.includes('/attendees/')) {
                    const pathParts = path.split('/');
                    const meetingId = pathParts[2];
                    const attendeeId = pathParts[4];
                    return await getAttendee(meetingId, attendeeId);
                }
                break;
            case 'DELETE':
                if (path.includes('/attendees/')) {
                    const pathParts = path.split('/');
                    const meetingId = pathParts[2];
                    const attendeeId = pathParts[4];
                    return await deleteAttendee(meetingId, attendeeId);
                }
                break;
        }
        
        return {
            statusCode: 404,
            body: JSON.stringify({ error: 'Not found' })
        };
    } catch (error) {
        console.error('Error:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: 'Internal server error' })
        };
    }
};

async function createAttendee(meetingId, requestBody) {
    const { externalUserId, capabilities } = requestBody;
    
    const attendeeRequest = {
        MeetingId: meetingId,
        ExternalUserId: externalUserId || uuidv4(),
        Capabilities: capabilities || {
            Audio: 'SendReceive',
            Video: 'SendReceive',
            Content: 'SendReceive'
        }
    };
    
    const attendee = await chime.createAttendee(attendeeRequest).promise();
    
    return {
        statusCode: 201,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
            Attendee: attendee.Attendee
        })
    };
}

async function getAttendee(meetingId, attendeeId) {
    const attendee = await chime.getAttendee({
        MeetingId: meetingId,
        AttendeeId: attendeeId
    }).promise();
    
    return {
        statusCode: 200,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
            Attendee: attendee.Attendee
        })
    };
}

async function deleteAttendee(meetingId, attendeeId) {
    await chime.deleteAttendee({
        MeetingId: meetingId,
        AttendeeId: attendeeId
    }).promise();
    
    return {
        statusCode: 204,
        headers: {
            'Access-Control-Allow-Origin': '*'
        }
    };
}
EOF
    
    # Initialize npm project
    npm init -y > /dev/null
    npm install aws-sdk uuid > /dev/null
    
    # Create deployment packages
    zip -r meeting-handler.zip meeting-handler.js node_modules/ package.json > /dev/null
    zip -r attendee-handler.zip attendee-handler.js node_modules/ package.json > /dev/null
    
    # Deploy meeting handler Lambda
    aws lambda create-function \
        --function-name "$MEETING_LAMBDA_NAME" \
        --runtime nodejs18.x \
        --role "$LAMBDA_ROLE_ARN" \
        --handler meeting-handler.handler \
        --zip-file fileb://meeting-handler.zip \
        --environment Variables="{
            TABLE_NAME=${TABLE_NAME},
            SNS_TOPIC_ARN=${SNS_TOPIC_ARN}
        }" \
        --timeout 30 > /dev/null
    
    success "Meeting handler Lambda created: $MEETING_LAMBDA_NAME"
    
    # Deploy attendee handler Lambda
    aws lambda create-function \
        --function-name "$ATTENDEE_LAMBDA_NAME" \
        --runtime nodejs18.x \
        --role "$LAMBDA_ROLE_ARN" \
        --handler attendee-handler.handler \
        --zip-file fileb://attendee-handler.zip \
        --timeout 30 > /dev/null
    
    success "Attendee handler Lambda created: $ATTENDEE_LAMBDA_NAME"
    
    # Clean up temp directory
    cd "$SCRIPT_DIR"
    rm -rf "$TEMP_DIR"
    rm -f /tmp/lambda-trust-policy.json /tmp/chime-sdk-policy.json
}

# Function to create API Gateway
create_api_gateway() {
    log "Creating API Gateway..."
    
    if $DRY_RUN; then
        log "DRY RUN: Would create API Gateway"
        export API_ENDPOINT="https://api-id.execute-api.${AWS_REGION}.amazonaws.com/prod"
        return
    fi
    
    # Create REST API
    export API_ID=$(aws apigateway create-rest-api \
        --name "$API_NAME" \
        --description "Video Conferencing API with Chime SDK" \
        --query 'id' --output text)
    
    # Get root resource ID
    export ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "$API_ID" \
        --query 'items[0].id' --output text)
    
    # Create resource hierarchy
    export MEETINGS_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "$API_ID" \
        --parent-id "$ROOT_RESOURCE_ID" \
        --path-part meetings \
        --query 'id' --output text)
    
    export MEETING_ID_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "$API_ID" \
        --parent-id "$MEETINGS_RESOURCE_ID" \
        --path-part '{meetingId}' \
        --query 'id' --output text)
    
    export ATTENDEES_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "$API_ID" \
        --parent-id "$MEETING_ID_RESOURCE_ID" \
        --path-part attendees \
        --query 'id' --output text)
    
    export ATTENDEE_ID_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "$API_ID" \
        --parent-id "$ATTENDEES_RESOURCE_ID" \
        --path-part '{attendeeId}' \
        --query 'id' --output text)
    
    # Get Lambda function ARNs
    export MEETING_LAMBDA_ARN=$(aws lambda get-function \
        --function-name "$MEETING_LAMBDA_NAME" \
        --query 'Configuration.FunctionArn' --output text)
    
    export ATTENDEE_LAMBDA_ARN=$(aws lambda get-function \
        --function-name "$ATTENDEE_LAMBDA_NAME" \
        --query 'Configuration.FunctionArn' --output text)
    
    # Configure methods and integrations for meetings
    configure_api_methods
    
    # Grant permissions
    aws lambda add-permission \
        --function-name "$MEETING_LAMBDA_NAME" \
        --statement-id apigateway-invoke-meeting \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*" > /dev/null
    
    aws lambda add-permission \
        --function-name "$ATTENDEE_LAMBDA_NAME" \
        --statement-id apigateway-invoke-attendee \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*" > /dev/null
    
    # Deploy API
    aws apigateway create-deployment \
        --rest-api-id "$API_ID" \
        --stage-name prod > /dev/null
    
    export API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
    
    success "API Gateway created: $API_ENDPOINT"
}

# Function to configure API methods
configure_api_methods() {
    log "Configuring API Gateway methods..."
    
    # Meeting endpoints
    for method in POST GET DELETE; do
        if [ "$method" = "POST" ]; then
            resource_id="$MEETINGS_RESOURCE_ID"
        else
            resource_id="$MEETING_ID_RESOURCE_ID"
        fi
        
        aws apigateway put-method \
            --rest-api-id "$API_ID" \
            --resource-id "$resource_id" \
            --http-method "$method" \
            --authorization-type NONE > /dev/null
        
        aws apigateway put-integration \
            --rest-api-id "$API_ID" \
            --resource-id "$resource_id" \
            --http-method "$method" \
            --type AWS_PROXY \
            --integration-http-method POST \
            --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${MEETING_LAMBDA_ARN}/invocations" > /dev/null
    done
    
    # Attendee endpoints
    for method in POST GET DELETE; do
        if [ "$method" = "POST" ]; then
            resource_id="$ATTENDEES_RESOURCE_ID"
        else
            resource_id="$ATTENDEE_ID_RESOURCE_ID"
        fi
        
        aws apigateway put-method \
            --rest-api-id "$API_ID" \
            --resource-id "$resource_id" \
            --http-method "$method" \
            --authorization-type NONE > /dev/null
        
        aws apigateway put-integration \
            --rest-api-id "$API_ID" \
            --resource-id "$resource_id" \
            --http-method "$method" \
            --type AWS_PROXY \
            --integration-http-method POST \
            --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${ATTENDEE_LAMBDA_ARN}/invocations" > /dev/null
    done
}

# Function to save deployment state
save_deployment_state() {
    log "Saving deployment state..."
    
    local state_file="${SCRIPT_DIR}/../.deployment_state"
    
    cat > "$state_file" << EOF
# Deployment state for Video Conferencing with Chime SDK
# Generated on $(date)
PROJECT_NAME=$PROJECT_NAME
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
BUCKET_NAME=$BUCKET_NAME
TABLE_NAME=$TABLE_NAME
SNS_TOPIC_NAME=$SNS_TOPIC_NAME
SNS_TOPIC_ARN=$SNS_TOPIC_ARN
LAMBDA_ROLE_NAME=$LAMBDA_ROLE_NAME
LAMBDA_ROLE_ARN=$LAMBDA_ROLE_ARN
MEETING_LAMBDA_NAME=$MEETING_LAMBDA_NAME
ATTENDEE_LAMBDA_NAME=$ATTENDEE_LAMBDA_NAME
API_NAME=$API_NAME
API_ID=$API_ID
API_ENDPOINT=$API_ENDPOINT
EOF
    
    success "Deployment state saved to: $state_file"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================================="
    echo "Project Name: $PROJECT_NAME"
    echo "AWS Region: $AWS_REGION"
    echo "S3 Bucket: $BUCKET_NAME"
    echo "DynamoDB Table: $TABLE_NAME"
    echo "SNS Topic: $SNS_TOPIC_ARN"
    echo "Lambda Role: $LAMBDA_ROLE_ARN"
    echo "Meeting Lambda: $MEETING_LAMBDA_NAME"
    echo "Attendee Lambda: $ATTENDEE_LAMBDA_NAME"
    echo "API Endpoint: $API_ENDPOINT"
    echo "=================================="
    
    echo ""
    echo "Next Steps:"
    echo "1. Test the API endpoints using curl or Postman"
    echo "2. Deploy the web client to test video conferencing"
    echo "3. Configure authentication and authorization as needed"
    echo "4. Set up monitoring and logging for production use"
    echo ""
    echo "Example API call:"
    echo "curl -X POST \"$API_ENDPOINT/meetings\" \\"
    echo "  -H \"Content-Type: application/json\" \\"
    echo "  -d '{\"externalMeetingId\": \"test-meeting\", \"mediaRegion\": \"$AWS_REGION\"}'"
}

# Main deployment function
main() {
    log "Starting deployment of Video Conferencing with Amazon Chime SDK"
    
    if $DRY_RUN; then
        warn "Running in DRY RUN mode - no resources will be created"
    fi
    
    check_prerequisites
    generate_resource_names
    create_foundation_resources
    create_iam_role
    create_lambda_functions
    create_api_gateway
    
    if ! $DRY_RUN; then
        save_deployment_state
    fi
    
    display_summary
    
    success "Deployment completed successfully!"
    
    if $DRY_RUN; then
        warn "This was a DRY RUN - no actual resources were created"
    fi
}

# Error handling
trap 'error "Deployment failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"