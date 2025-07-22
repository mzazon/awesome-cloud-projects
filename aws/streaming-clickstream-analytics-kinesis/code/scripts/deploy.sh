#!/bin/bash

# Real-time Clickstream Analytics Deployment Script
# This script deploys the complete clickstream analytics pipeline
# including Kinesis Data Streams, Lambda functions, and DynamoDB tables

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TEMP_DIR="${SCRIPT_DIR}/../temp"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "${LOG_FILE}" >&2
    exit 1
}

warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" | tee -a "${LOG_FILE}"
}

# Cleanup function for graceful exit
cleanup() {
    if [[ -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
}
trap cleanup EXIT

# Banner
echo "=========================================="
echo "Real-time Clickstream Analytics Deployment"
echo "=========================================="
echo ""

log "Starting deployment of clickstream analytics pipeline"

# Prerequisites check
log "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    error "AWS CLI not found. Please install and configure AWS CLI v2"
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please run 'aws configure'"
fi

# Check Node.js for Lambda packaging
if ! command -v node &> /dev/null; then
    error "Node.js not found. Please install Node.js 18+ for Lambda function packaging"
fi

# Check jq for JSON processing
if ! command -v jq &> /dev/null; then
    warning "jq not found. Installing via package manager recommended for better output formatting"
fi

log "Prerequisites check completed successfully"

# Environment setup
log "Setting up environment variables..."

export AWS_REGION=$(aws configure get region)
if [[ -z "${AWS_REGION}" ]]; then
    export AWS_REGION="us-east-1"
    warning "No default region found, using us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

export STREAM_NAME="clickstream-events-${RANDOM_SUFFIX}"
export TABLE_PREFIX="clickstream-${RANDOM_SUFFIX}"
export BUCKET_NAME="clickstream-archive-${RANDOM_SUFFIX}"

log "Environment configured:"
log "  AWS Region: ${AWS_REGION}"
log "  Account ID: ${AWS_ACCOUNT_ID}"
log "  Stream Name: ${STREAM_NAME}"
log "  Table Prefix: ${TABLE_PREFIX}"
log "  Bucket Name: ${BUCKET_NAME}"

# Create working directory
mkdir -p "${TEMP_DIR}"
cd "${TEMP_DIR}"

# Step 1: Create S3 bucket for archiving
log "Creating S3 bucket for raw data archiving..."
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
    warning "Bucket ${BUCKET_NAME} already exists, skipping creation"
else
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
        aws s3 mb "s3://${BUCKET_NAME}"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
    fi
    log "✅ Created S3 bucket: ${BUCKET_NAME}"
fi

# Step 2: Create Kinesis Data Stream
log "Creating Kinesis Data Stream..."
if aws kinesis describe-stream --stream-name "${STREAM_NAME}" &>/dev/null; then
    warning "Stream ${STREAM_NAME} already exists, skipping creation"
    STREAM_ARN=$(aws kinesis describe-stream --stream-name "${STREAM_NAME}" \
        --query 'StreamDescription.StreamARN' --output text)
else
    aws kinesis create-stream \
        --stream-name "${STREAM_NAME}" \
        --shard-count 2

    log "Waiting for stream to become active..."
    aws kinesis wait stream-exists --stream-name "${STREAM_NAME}"

    STREAM_ARN=$(aws kinesis describe-stream --stream-name "${STREAM_NAME}" \
        --query 'StreamDescription.StreamARN' --output text)
    
    log "✅ Created Kinesis stream: ${STREAM_NAME}"
fi

# Step 3: Create DynamoDB tables
log "Creating DynamoDB tables..."

# Page metrics table
if aws dynamodb describe-table --table-name "${TABLE_PREFIX}-page-metrics" &>/dev/null; then
    warning "Table ${TABLE_PREFIX}-page-metrics already exists, skipping creation"
else
    aws dynamodb create-table \
        --table-name "${TABLE_PREFIX}-page-metrics" \
        --attribute-definitions \
            AttributeName=page_url,AttributeType=S \
            AttributeName=timestamp_hour,AttributeType=S \
        --key-schema \
            AttributeName=page_url,KeyType=HASH \
            AttributeName=timestamp_hour,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST
    log "✅ Created page-metrics table"
fi

# Session metrics table
if aws dynamodb describe-table --table-name "${TABLE_PREFIX}-session-metrics" &>/dev/null; then
    warning "Table ${TABLE_PREFIX}-session-metrics already exists, skipping creation"
else
    aws dynamodb create-table \
        --table-name "${TABLE_PREFIX}-session-metrics" \
        --attribute-definitions \
            AttributeName=session_id,AttributeType=S \
        --key-schema \
            AttributeName=session_id,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST
    log "✅ Created session-metrics table"
fi

# Counters table
if aws dynamodb describe-table --table-name "${TABLE_PREFIX}-counters" &>/dev/null; then
    warning "Table ${TABLE_PREFIX}-counters already exists, skipping creation"
else
    aws dynamodb create-table \
        --table-name "${TABLE_PREFIX}-counters" \
        --attribute-definitions \
            AttributeName=metric_name,AttributeType=S \
            AttributeName=time_window,AttributeType=S \
        --key-schema \
            AttributeName=metric_name,KeyType=HASH \
            AttributeName=time_window,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST
    log "✅ Created counters table"
fi

# Step 4: Create IAM role for Lambda functions
log "Creating IAM role for Lambda functions..."

ROLE_NAME="ClickstreamProcessorRole-${RANDOM_SUFFIX}"

if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
    warning "IAM role ${ROLE_NAME} already exists, skipping creation"
else
    # Create trust policy
    cat > lambda-trust-policy.json << 'EOF'
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

    aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document file://lambda-trust-policy.json

    # Create and attach permissions policy
    cat > lambda-permissions.json << EOF
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
                "kinesis:DescribeStream",
                "kinesis:GetShardIterator",
                "kinesis:GetRecords",
                "kinesis:ListStreams"
            ],
            "Resource": "${STREAM_ARN}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:GetItem",
                "dynamodb:Query"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${TABLE_PREFIX}-*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        }
    ]
}
EOF

    aws iam put-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-name ClickstreamProcessorPolicy \
        --policy-document file://lambda-permissions.json

    log "✅ Created IAM role: ${ROLE_NAME}"
fi

export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

# Wait for IAM role propagation
log "Waiting for IAM role propagation..."
sleep 10

# Step 5: Create Lambda function for event processing
log "Creating event processor Lambda function..."

mkdir -p lambda-functions/event-processor

cat > lambda-functions/event-processor/index.js << 'EOF'
const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();
const s3 = new AWS.S3();
const cloudwatch = new AWS.CloudWatch();

const TABLE_PREFIX = process.env.TABLE_PREFIX;
const BUCKET_NAME = process.env.BUCKET_NAME;

exports.handler = async (event) => {
    console.log('Processing', event.Records.length, 'records');
    
    const promises = event.Records.map(async (record) => {
        try {
            // Decode the Kinesis data
            const payload = Buffer.from(record.kinesis.data, 'base64').toString('utf-8');
            const clickEvent = JSON.parse(payload);
            
            // Process different event types
            await Promise.all([
                processPageView(clickEvent),
                updateSessionMetrics(clickEvent),
                updateRealTimeCounters(clickEvent),
                archiveRawEvent(clickEvent),
                publishMetrics(clickEvent)
            ]);
            
        } catch (error) {
            console.error('Error processing record:', error);
            throw error;
        }
    });
    
    await Promise.all(promises);
    return { statusCode:200, body: 'Successfully processed events' };
};

async function processPageView(event) {
    if (event.event_type !== 'page_view') return;
    
    const hour = new Date(event.timestamp).toISOString().slice(0, 13);
    
    const params = {
        TableName: `${TABLE_PREFIX}-page-metrics`,
        Key: {
            page_url: event.page_url,
            timestamp_hour: hour
        },
        UpdateExpression: 'ADD view_count :inc SET last_updated = :now',
        ExpressionAttributeValues: {
            ':inc': 1,
            ':now': Date.now()
        }
    };
    
    await dynamodb.update(params).promise();
}

async function updateSessionMetrics(event) {
    const params = {
        TableName: `${TABLE_PREFIX}-session-metrics`,
        Key: { session_id: event.session_id },
        UpdateExpression: 'SET last_activity = :now, user_agent = :ua ADD event_count :inc',
        ExpressionAttributeValues: {
            ':now': event.timestamp,
            ':ua': event.user_agent || 'unknown',
            ':inc': 1
        }
    };
    
    await dynamodb.update(params).promise();
}

async function updateRealTimeCounters(event) {
    const minute = new Date(event.timestamp).toISOString().slice(0, 16);
    
    const params = {
        TableName: `${TABLE_PREFIX}-counters`,
        Key: {
            metric_name: `events_per_minute_${event.event_type}`,
            time_window: minute
        },
        UpdateExpression: 'ADD event_count :inc SET ttl = :ttl',
        ExpressionAttributeValues: {
            ':inc': 1,
            ':ttl': Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hour TTL
        }
    };
    
    await dynamodb.update(params).promise();
}

async function archiveRawEvent(event) {
    const date = new Date(event.timestamp);
    const key = `year=${date.getFullYear()}/month=${date.getMonth() + 1}/day=${date.getDate()}/hour=${date.getHours()}/${event.session_id}-${Date.now()}.json`;
    
    const params = {
        Bucket: BUCKET_NAME,
        Key: key,
        Body: JSON.stringify(event),
        ContentType: 'application/json'
    };
    
    await s3.putObject(params).promise();
}

async function publishMetrics(event) {
    const params = {
        Namespace: 'Clickstream/Events',
        MetricData: [
            {
                MetricName: 'EventsProcessed',
                Value: 1,
                Unit: 'Count',
                Dimensions: [
                    {
                        Name: 'EventType',
                        Value: event.event_type
                    }
                ]
            }
        ]
    };
    
    await cloudwatch.putMetricData(params).promise();
}
EOF

cat > lambda-functions/event-processor/package.json << 'EOF'
{
    "name": "clickstream-event-processor",
    "version": "1.0",
    "main": "index.js",
    "dependencies": {
        "aws-sdk": "^2.1000.0"
    }
}
EOF

cd lambda-functions/event-processor
zip -r ../event-processor.zip .
cd ../..

PROCESSOR_FUNCTION_NAME="clickstream-event-processor-${RANDOM_SUFFIX}"

if aws lambda get-function --function-name "${PROCESSOR_FUNCTION_NAME}" &>/dev/null; then
    warning "Lambda function ${PROCESSOR_FUNCTION_NAME} already exists, updating code"
    aws lambda update-function-code \
        --function-name "${PROCESSOR_FUNCTION_NAME}" \
        --zip-file fileb://lambda-functions/event-processor.zip
else
    aws lambda create-function \
        --function-name "${PROCESSOR_FUNCTION_NAME}" \
        --runtime nodejs18.x \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler index.handler \
        --zip-file fileb://lambda-functions/event-processor.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables="{TABLE_PREFIX=${TABLE_PREFIX},BUCKET_NAME=${BUCKET_NAME}}"
    
    log "✅ Created event processor Lambda function"
fi

PROCESSOR_FUNCTION_ARN=$(aws lambda get-function \
    --function-name "${PROCESSOR_FUNCTION_NAME}" \
    --query 'Configuration.FunctionArn' --output text)

# Step 6: Create anomaly detection Lambda function
log "Creating anomaly detection Lambda function..."

mkdir -p lambda-functions/anomaly-detector

cat > lambda-functions/anomaly-detector/index.js << 'EOF'
const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();
const sns = new AWS.SNS();

const TABLE_PREFIX = process.env.TABLE_PREFIX;
const SNS_TOPIC_ARN = process.env.SNS_TOPIC_ARN;

exports.handler = async (event) => {
    console.log('Checking for anomalies in', event.Records.length, 'records');
    
    for (const record of event.Records) {
        try {
            const payload = Buffer.from(record.kinesis.data, 'base64').toString('utf-8');
            const clickEvent = JSON.parse(payload);
            
            await checkForAnomalies(clickEvent);
            
        } catch (error) {
            console.error('Error processing record for anomaly detection:', error);
        }
    }
    
    return { statusCode: 200 };
};

async function checkForAnomalies(event) {
    // Check for suspicious patterns
    const checks = await Promise.all([
        checkHighFrequencyClicks(event),
        checkSuspiciousUserAgent(event),
        checkUnusualPageSequence(event)
    ]);
    
    const anomalies = checks.filter(check => check.isAnomaly);
    
    if (anomalies.length > 0) {
        await sendAlert(event, anomalies);
    }
}

async function checkHighFrequencyClicks(event) {
    const minute = new Date(event.timestamp).toISOString().slice(0, 16);
    
    const params = {
        TableName: `${TABLE_PREFIX}-counters`,
        Key: {
            metric_name: `session_events_${event.session_id}`,
            time_window: minute
        }
    };
    
    const result = await dynamodb.get(params).promise();
    const eventCount = result.Item ? result.Item.event_count : 0;
    
    // Flag if more than 50 events per minute from same session
    return {
        isAnomaly: eventCount > 50,
        type: 'high_frequency_clicks',
        details: `${eventCount} events in one minute`
    };
}

async function checkSuspiciousUserAgent(event) {
    const suspiciousPatterns = ['bot', 'crawler', 'spider', 'scraper'];
    const userAgent = (event.user_agent || '').toLowerCase();
    
    const isSuspicious = suspiciousPatterns.some(pattern => 
        userAgent.includes(pattern)
    );
    
    return {
        isAnomaly: isSuspicious,
        type: 'suspicious_user_agent',
        details: event.user_agent
    };
}

async function checkUnusualPageSequence(event) {
    // Simple check for direct access to checkout without viewing products
    if (event.page_url && event.page_url.includes('/checkout')) {
        const params = {
            TableName: `${TABLE_PREFIX}-session-metrics`,
            Key: { session_id: event.session_id }
        };
        
        const result = await dynamodb.get(params).promise();
        const eventCount = result.Item ? result.Item.event_count : 0;
        
        // Flag if going to checkout with very few page views
        return {
            isAnomaly: eventCount < 3,
            type: 'unusual_page_sequence',
            details: `Direct checkout access with only ${eventCount} page views`
        };
    }
    
    return { isAnomaly: false };
}

async function sendAlert(event, anomalies) {
    if (!SNS_TOPIC_ARN) return;
    
    const message = {
        timestamp: event.timestamp,
        session_id: event.session_id,
        anomalies: anomalies,
        event_details: event
    };
    
    const params = {
        TopicArn: SNS_TOPIC_ARN,
        Message: JSON.stringify(message, null, 2),
        Subject: 'Clickstream Anomaly Detected'
    };
    
    await sns.publish(params).promise();
    console.log('Alert sent for anomalies:', anomalies.map(a => a.type));
}
EOF

cat > lambda-functions/anomaly-detector/package.json << 'EOF'
{
    "name": "anomaly-detector",
    "version": "1.0.0",
    "main": "index.js",
    "dependencies": {
        "aws-sdk": "^2.1000.0"
    }
}
EOF

cd lambda-functions/anomaly-detector
zip -r ../anomaly-detector.zip .
cd ../..

ANOMALY_FUNCTION_NAME="clickstream-anomaly-detector-${RANDOM_SUFFIX}"

if aws lambda get-function --function-name "${ANOMALY_FUNCTION_NAME}" &>/dev/null; then
    warning "Lambda function ${ANOMALY_FUNCTION_NAME} already exists, updating code"
    aws lambda update-function-code \
        --function-name "${ANOMALY_FUNCTION_NAME}" \
        --zip-file fileb://lambda-functions/anomaly-detector.zip
else
    aws lambda create-function \
        --function-name "${ANOMALY_FUNCTION_NAME}" \
        --runtime nodejs18.x \
        --role "${LAMBDA_ROLE_ARN}" \
        --handler index.handler \
        --zip-file fileb://lambda-functions/anomaly-detector.zip \
        --timeout 30 \
        --memory-size 128 \
        --environment Variables="{TABLE_PREFIX=${TABLE_PREFIX}}"
    
    log "✅ Created anomaly detection Lambda function"
fi

# Step 7: Create event source mappings
log "Creating event source mappings..."

# Check if event source mapping already exists for processor function
EXISTING_MAPPING=$(aws lambda list-event-source-mappings \
    --function-name "${PROCESSOR_FUNCTION_NAME}" \
    --query "EventSourceMappings[?EventSourceArn=='${STREAM_ARN}'].UUID" \
    --output text)

if [[ -n "${EXISTING_MAPPING}" ]]; then
    warning "Event source mapping already exists for processor function"
else
    aws lambda create-event-source-mapping \
        --event-source-arn "${STREAM_ARN}" \
        --function-name "${PROCESSOR_FUNCTION_NAME}" \
        --starting-position LATEST \
        --batch-size 100 \
        --maximum-batching-window-in-seconds 5
    
    log "✅ Created event source mapping for processor function"
fi

# Check if event source mapping already exists for anomaly function
EXISTING_ANOMALY_MAPPING=$(aws lambda list-event-source-mappings \
    --function-name "${ANOMALY_FUNCTION_NAME}" \
    --query "EventSourceMappings[?EventSourceArn=='${STREAM_ARN}'].UUID" \
    --output text)

if [[ -n "${EXISTING_ANOMALY_MAPPING}" ]]; then
    warning "Event source mapping already exists for anomaly function"
else
    aws lambda create-event-source-mapping \
        --event-source-arn "${STREAM_ARN}" \
        --function-name "${ANOMALY_FUNCTION_NAME}" \
        --starting-position LATEST \
        --batch-size 50 \
        --maximum-batching-window-in-seconds 10
    
    log "✅ Created event source mapping for anomaly function"
fi

# Step 8: Create CloudWatch dashboard
log "Creating CloudWatch dashboard..."

DASHBOARD_NAME="Clickstream-Analytics-${RANDOM_SUFFIX}"

cat > dashboard-config.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "Clickstream/Events", "EventsProcessed", "EventType", "page_view" ],
                    [ "...", "click" ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Events Processed by Type"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/Lambda", "Duration", "FunctionName", "${PROCESSOR_FUNCTION_NAME}" ],
                    [ ".", "Errors", ".", "." ],
                    [ ".", "Invocations", ".", "." ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Lambda Performance"
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/Kinesis", "IncomingRecords", "StreamName", "${STREAM_NAME}" ],
                    [ ".", "OutgoingRecords", ".", "." ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Kinesis Stream Throughput"
            }
        }
    ]
}
EOF

aws cloudwatch put-dashboard \
    --dashboard-name "${DASHBOARD_NAME}" \
    --dashboard-body file://dashboard-config.json

log "✅ Created CloudWatch dashboard: ${DASHBOARD_NAME}"

# Step 9: Create test client
log "Creating test client for generating sample events..."

mkdir -p test-client

cat > test-client/generate-events.js << 'EOF'
const AWS = require('aws-sdk');
const kinesis = new AWS.Kinesis();

const STREAM_NAME = process.env.STREAM_NAME;
const USER_AGENTS = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36'
];

const PAGES = [
    '/home',
    '/products',
    '/product/123',
    '/cart',
    '/checkout',
    '/about',
    '/contact'
];

function generateSessionId() {
    return 'session_' + Math.random().toString(36).substr(2, 9);
}

function generateEvent(sessionId) {
    return {
        event_type: Math.random() > 0.1 ? 'page_view' : 'click',
        session_id: sessionId,
        user_id: 'user_' + Math.floor(Math.random() * 1000),
        timestamp: new Date().toISOString(),
        page_url: PAGES[Math.floor(Math.random() * PAGES.length)],
        user_agent: USER_AGENTS[Math.floor(Math.random() * USER_AGENTS.length)],
        ip_address: `192.168.1.${Math.floor(Math.random() * 255)}`,
        referrer: Math.random() > 0.5 ? 'https://google.com' : null
    };
}

async function sendEvents() {
    const sessionId = generateSessionId();
    const eventsPerSession = Math.floor(Math.random() * 10) + 1;
    
    console.log(`Generating ${eventsPerSession} events for session ${sessionId}`);
    
    for (let i = 0; i < eventsPerSession; i++) {
        const event = generateEvent(sessionId);
        
        const params = {
            StreamName: STREAM_NAME,
            Data: JSON.stringify(event),
            PartitionKey: sessionId
        };
        
        try {
            await kinesis.putRecord(params).promise();
            console.log('Sent event:', event.event_type, event.page_url);
            
            // Small delay between events
            await new Promise(resolve => setTimeout(resolve, 100));
        } catch (error) {
            console.error('Error sending event:', error);
        }
    }
}

// Generate events continuously
async function main() {
    console.log('Starting event generation...');
    
    while (true) {
        await sendEvents();
        // Wait 2-5 seconds between sessions
        await new Promise(resolve => 
            setTimeout(resolve, 2000 + Math.random() * 3000)
        );
    }
}

main().catch(console.error);
EOF

cat > test-client/package.json << 'EOF'
{
    "name": "clickstream-test-client",
    "version": "1.0",
    "main": "generate-events.js",
    "dependencies": {
        "aws-sdk": "^2.1000.0"
    }
}
EOF

log "✅ Created test client"

# Save configuration for cleanup script
cat > "${SCRIPT_DIR}/deployment-config.env" << EOF
# Deployment configuration for cleanup
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export STREAM_NAME="${STREAM_NAME}"
export TABLE_PREFIX="${TABLE_PREFIX}"
export BUCKET_NAME="${BUCKET_NAME}"
export PROCESSOR_FUNCTION_NAME="${PROCESSOR_FUNCTION_NAME}"
export ANOMALY_FUNCTION_NAME="${ANOMALY_FUNCTION_NAME}"
export ROLE_NAME="${ROLE_NAME}"
export DASHBOARD_NAME="${DASHBOARD_NAME}"
EOF

log "✅ Saved deployment configuration"

# Deployment summary
echo ""
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
echo "✅ Kinesis Data Stream: ${STREAM_NAME}"
echo "✅ DynamoDB Tables: ${TABLE_PREFIX}-*"
echo "✅ S3 Bucket: ${BUCKET_NAME}"
echo "✅ Lambda Functions: ${PROCESSOR_FUNCTION_NAME}, ${ANOMALY_FUNCTION_NAME}"
echo "✅ IAM Role: ${ROLE_NAME}"
echo "✅ CloudWatch Dashboard: ${DASHBOARD_NAME}"
echo ""
echo "📊 Dashboard URL: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
echo ""
echo "🧪 To test the system:"
echo "cd ${TEMP_DIR}/test-client"
echo "npm install"
echo "STREAM_NAME=${STREAM_NAME} node generate-events.js"
echo ""
echo "📋 Configuration saved to: ${SCRIPT_DIR}/deployment-config.env"
echo "🗑️  To cleanup: ${SCRIPT_DIR}/destroy.sh"
echo ""

log "Deployment completed successfully!"