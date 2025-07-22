#!/bin/bash

# CloudFront Real-time Monitoring and Analytics - Deployment Script
# This script deploys a comprehensive real-time monitoring solution for CloudFront
# including Kinesis streams, Lambda processing, OpenSearch analytics, and dashboards

set -e  # Exit on any error

# Colors for output
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

# Error handling
handle_error() {
    log_error "Deployment failed at line $1"
    log_error "To clean up partial deployment, run: ./destroy.sh"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION" | cut -d. -f1) -lt 2 ]]; then
        log_error "AWS CLI version 2.x is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check required tools
    local required_tools=("jq" "curl" "zip")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed. Please install $tool to continue."
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 8)")
    
    export PROJECT_NAME="cf-monitoring-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="cf-logs-${RANDOM_SUFFIX}"
    export S3_CONTENT_BUCKET="cf-content-${RANDOM_SUFFIX}"
    export KINESIS_STREAM_NAME="cf-realtime-logs-${RANDOM_SUFFIX}"
    export OPENSEARCH_DOMAIN="cf-analytics-${RANDOM_SUFFIX}"
    export METRICS_TABLE_NAME="${PROJECT_NAME}-metrics"
    
    # Save environment to file for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
PROJECT_NAME=${PROJECT_NAME}
S3_BUCKET_NAME=${S3_BUCKET_NAME}
S3_CONTENT_BUCKET=${S3_CONTENT_BUCKET}
KINESIS_STREAM_NAME=${KINESIS_STREAM_NAME}
OPENSEARCH_DOMAIN=${OPENSEARCH_DOMAIN}
METRICS_TABLE_NAME=${METRICS_TABLE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment variables configured"
    log_info "Project Name: ${PROJECT_NAME}"
    log_info "AWS Region: ${AWS_REGION}"
}

# Create S3 buckets and upload content
setup_s3_buckets() {
    log_info "Creating S3 buckets and uploading sample content..."
    
    # Create S3 buckets
    aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION} || true
    aws s3 mb s3://${S3_CONTENT_BUCKET} --region ${AWS_REGION} || true
    
    # Create sample content directory
    mkdir -p /tmp/content/{css,js,images,api}
    
    # Create sample HTML content
    cat > /tmp/content/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>CloudFront Monitoring Demo</title>
    <link rel="stylesheet" href="/css/style.css">
    <script src="/js/app.js"></script>
</head>
<body>
    <h1>Welcome to CloudFront Monitoring Demo</h1>
    <p>This page generates traffic for monitoring analysis.</p>
    <img src="/images/demo.jpg" alt="Demo Image" width="300">
    <div id="content"></div>
</body>
</html>
EOF
    
    # Create CSS file
    echo 'body { font-family: Arial, sans-serif; margin: 40px; }' > /tmp/content/css/style.css
    
    # Create JavaScript file
    echo 'console.log("Page loaded"); fetch("/api/data").then(r => r.json()).then(d => document.getElementById("content").innerHTML = JSON.stringify(d));' > /tmp/content/js/app.js
    
    # Create API response
    echo '{"message": "Hello from API", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'", "version": "1.0"}' > /tmp/content/api/data
    
    # Create a small sample image (1x1 pixel PNG)
    echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==" | base64 -d > /tmp/content/images/demo.jpg
    
    # Upload content to S3
    aws s3 cp /tmp/content s3://${S3_CONTENT_BUCKET}/ --recursive \
        --cache-control "max-age=3600"
    
    log_success "S3 buckets created and content uploaded"
}

# Create Kinesis Data Streams
create_kinesis_streams() {
    log_info "Creating Kinesis Data Streams..."
    
    # Create primary stream for real-time logs
    if ! aws kinesis describe-stream --stream-name ${KINESIS_STREAM_NAME} &>/dev/null; then
        aws kinesis create-stream \
            --stream-name ${KINESIS_STREAM_NAME} \
            --shard-count 2
        log_info "Waiting for primary Kinesis stream to be active..."
        aws kinesis wait stream-exists --stream-name ${KINESIS_STREAM_NAME}
    else
        log_warning "Primary Kinesis stream already exists"
    fi
    
    # Create processed data stream
    if ! aws kinesis describe-stream --stream-name ${KINESIS_STREAM_NAME}-processed &>/dev/null; then
        aws kinesis create-stream \
            --stream-name ${KINESIS_STREAM_NAME}-processed \
            --shard-count 1
        log_info "Waiting for processed Kinesis stream to be active..."
        aws kinesis wait stream-exists --stream-name ${KINESIS_STREAM_NAME}-processed
    else
        log_warning "Processed Kinesis stream already exists"
    fi
    
    log_success "Kinesis Data Streams created"
}

# Create OpenSearch domain
create_opensearch_domain() {
    log_info "Creating OpenSearch domain (this may take 10-15 minutes)..."
    
    # Check if domain already exists
    if aws opensearch describe-domain --domain-name ${OPENSEARCH_DOMAIN} &>/dev/null; then
        log_warning "OpenSearch domain already exists"
        return
    fi
    
    # Create access policy
    cat > /tmp/opensearch-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Action": "es:*",
            "Resource": "arn:aws:es:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/${OPENSEARCH_DOMAIN}/*",
            "Condition": {
                "IpAddress": {
                    "aws:SourceIp": ["0.0.0.0/0"]
                }
            }
        }
    ]
}
EOF
    
    # Create OpenSearch domain
    aws opensearch create-domain \
        --domain-name ${OPENSEARCH_DOMAIN} \
        --engine-version "OpenSearch_2.3" \
        --cluster-config '{
            "InstanceType": "t3.small.search",
            "InstanceCount": 1,
            "DedicatedMasterEnabled": false
        }' \
        --ebs-options '{
            "EBSEnabled": true,
            "VolumeType": "gp3",
            "VolumeSize": 20
        }' \
        --access-policies file:///tmp/opensearch-policy.json \
        --domain-endpoint-options '{
            "EnforceHTTPS": true,
            "TLSSecurityPolicy": "Policy-Min-TLS-1-2-2019-07"
        }' \
        --node-to-node-encryption-options '{
            "Enabled": true
        }' \
        --encryption-at-rest-options '{
            "Enabled": true
        }'
    
    log_success "OpenSearch domain creation initiated"
}

# Create DynamoDB table
create_dynamodb_table() {
    log_info "Creating DynamoDB table for metrics storage..."
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name ${METRICS_TABLE_NAME} &>/dev/null; then
        log_warning "DynamoDB table already exists"
        return
    fi
    
    aws dynamodb create-table \
        --table-name ${METRICS_TABLE_NAME} \
        --attribute-definitions \
            AttributeName=MetricId,AttributeType=S \
            AttributeName=Timestamp,AttributeType=S \
        --key-schema \
            AttributeName=MetricId,KeyType=HASH \
            AttributeName=Timestamp,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST
    
    log_info "Waiting for DynamoDB table to be active..."
    aws dynamodb wait table-exists --table-name ${METRICS_TABLE_NAME}
    
    log_success "DynamoDB table created"
}

# Create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function for log processing..."
    
    # Create Lambda function directory
    mkdir -p /tmp/lambda-log-processor
    
    # Create package.json
    cat > /tmp/lambda-log-processor/package.json << 'EOF'
{
    "name": "cloudfront-log-processor",
    "version": "1.0.0",
    "description": "Real-time CloudFront log processor",
    "dependencies": {
        "aws-sdk": "^2.1000.0",
        "geoip-lite": "^1.4.0"
    }
}
EOF
    
    # Create Lambda function code
    cat > /tmp/lambda-log-processor/index.js << 'EOF'
const AWS = require('aws-sdk');
const geoip = require('geoip-lite');

const cloudwatch = new AWS.CloudWatch();
const dynamodb = new AWS.DynamoDB.DocumentClient();
const kinesis = new AWS.Kinesis();

const METRICS_TABLE = process.env.METRICS_TABLE;
const PROCESSED_STREAM = process.env.PROCESSED_STREAM;

exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    const processedRecords = [];
    const metrics = {
        totalRequests: 0,
        totalBytes: 0,
        errors4xx: 0,
        errors5xx: 0,
        cacheMisses: 0,
        regionCounts: {},
        statusCodes: {},
        userAgents: {}
    };
    
    for (const record of event.Records) {
        try {
            // Decode Kinesis data
            const data = Buffer.from(record.kinesis.data, 'base64').toString('utf-8');
            const logEntries = data.trim().split('\n');
            
            for (const logEntry of logEntries) {
                const processedLog = await processLogEntry(logEntry, metrics);
                if (processedLog) {
                    processedRecords.push(processedLog);
                }
            }
        } catch (error) {
            console.error('Error processing record:', error);
        }
    }
    
    // Send processed records to output stream
    if (processedRecords.length > 0) {
        await sendToKinesis(processedRecords);
    }
    
    // Store aggregated metrics
    await storeMetrics(metrics);
    
    // Send CloudWatch metrics
    await sendCloudWatchMetrics(metrics);
    
    return {
        statusCode: 200,
        processedRecords: processedRecords.length
    };
};

async function processLogEntry(logEntry, metrics) {
    try {
        // Parse CloudFront log format (tab-separated)
        const fields = logEntry.split('\t');
        
        if (fields.length < 20) {
            return null; // Invalid log entry
        }
        
        const timestamp = `${fields[0]} ${fields[1]}`;
        const edgeLocation = fields[2];
        const bytesDownloaded = parseInt(fields[3]) || 0;
        const clientIp = fields[4];
        const method = fields[5];
        const host = fields[6];
        const uri = fields[7];
        const status = parseInt(fields[8]) || 0;
        const referer = fields[9];
        const userAgent = fields[10];
        const queryString = fields[11];
        const cookie = fields[12];
        const edgeResultType = fields[13];
        const edgeRequestId = fields[14];
        const hostHeader = fields[15];
        const protocol = fields[16];
        const bytesUploaded = parseInt(fields[17]) || 0;
        const timeTaken = parseFloat(fields[18]) || 0;
        const forwardedFor = fields[19];
        
        // Geo-locate client IP
        const geoData = geoip.lookup(clientIp) || {};
        
        // Update metrics
        metrics.totalRequests++;
        metrics.totalBytes += bytesDownloaded;
        
        if (status >= 400 && status < 500) {
            metrics.errors4xx++;
        } else if (status >= 500) {
            metrics.errors5xx++;
        }
        
        if (edgeResultType === 'Miss') {
            metrics.cacheMisses++;
        }
        
        // Count by region
        const region = geoData.region || 'Unknown';
        metrics.regionCounts[region] = (metrics.regionCounts[region] || 0) + 1;
        
        // Count status codes
        metrics.statusCodes[status] = (metrics.statusCodes[status] || 0) + 1;
        
        // Simplified user agent tracking
        const uaCategory = categorizeUserAgent(userAgent);
        metrics.userAgents[uaCategory] = (metrics.userAgents[uaCategory] || 0) + 1;
        
        // Create enriched log entry
        const enrichedLog = {
            timestamp: new Date(timestamp).toISOString(),
            edgeLocation,
            clientIp,
            method,
            host,
            uri,
            status,
            bytesDownloaded,
            bytesUploaded,
            timeTaken,
            edgeResultType,
            userAgent: uaCategory,
            country: geoData.country || 'Unknown',
            region: geoData.region || 'Unknown',
            city: geoData.city || 'Unknown',
            referer: referer !== '-' ? referer : null,
            queryString: queryString !== '-' ? queryString : null,
            protocol,
            edgeRequestId,
            cacheHit: edgeResultType !== 'Miss',
            isError: status >= 400,
            responseSize: bytesDownloaded,
            requestSize: bytesUploaded,
            processingTime: Date.now()
        };
        
        return enrichedLog;
        
    } catch (error) {
        console.error('Error parsing log entry:', error);
        return null;
    }
}

function categorizeUserAgent(userAgent) {
    if (!userAgent || userAgent === '-') return 'Unknown';
    
    const ua = userAgent.toLowerCase();
    if (ua.includes('chrome')) return 'Chrome';
    if (ua.includes('firefox')) return 'Firefox';
    if (ua.includes('safari') && !ua.includes('chrome')) return 'Safari';
    if (ua.includes('edge')) return 'Edge';
    if (ua.includes('bot') || ua.includes('crawler')) return 'Bot';
    if (ua.includes('mobile')) return 'Mobile';
    
    return 'Other';
}

async function sendToKinesis(records) {
    const batchSize = 500; // Kinesis limit
    
    for (let i = 0; i < records.length; i += batchSize) {
        const batch = records.slice(i, i + batchSize);
        const kinesisRecords = batch.map(record => ({
            Data: JSON.stringify(record),
            PartitionKey: record.edgeLocation || 'default'
        }));
        
        try {
            await kinesis.putRecords({
                StreamName: PROCESSED_STREAM,
                Records: kinesisRecords
            }).promise();
        } catch (error) {
            console.error('Error sending to Kinesis:', error);
        }
    }
}

async function storeMetrics(metrics) {
    const timestamp = new Date().toISOString();
    const ttl = Math.floor(Date.now() / 1000) + (7 * 24 * 60 * 60); // 7 days
    
    try {
        await dynamodb.put({
            TableName: METRICS_TABLE,
            Item: {
                MetricId: `metrics-${Date.now()}`,
                Timestamp: timestamp,
                TotalRequests: metrics.totalRequests,
                TotalBytes: metrics.totalBytes,
                Errors4xx: metrics.errors4xx,
                Errors5xx: metrics.errors5xx,
                CacheMisses: metrics.cacheMisses,
                RegionCounts: metrics.regionCounts,
                StatusCodes: metrics.statusCodes,
                UserAgents: metrics.userAgents,
                TTL: ttl
            }
        }).promise();
    } catch (error) {
        console.error('Error storing metrics:', error);
    }
}

async function sendCloudWatchMetrics(metrics) {
    const metricData = [
        {
            MetricName: 'RequestCount',
            Value: metrics.totalRequests,
            Unit: 'Count',
            Timestamp: new Date()
        },
        {
            MetricName: 'BytesDownloaded',
            Value: metrics.totalBytes,
            Unit: 'Bytes',
            Timestamp: new Date()
        },
        {
            MetricName: 'ErrorRate4xx',
            Value: metrics.totalRequests > 0 ? (metrics.errors4xx / metrics.totalRequests) * 100 : 0,
            Unit: 'Percent',
            Timestamp: new Date()
        },
        {
            MetricName: 'ErrorRate5xx',
            Value: metrics.totalRequests > 0 ? (metrics.errors5xx / metrics.totalRequests) * 100 : 0,
            Unit: 'Percent',
            Timestamp: new Date()
        },
        {
            MetricName: 'CacheMissRate',
            Value: metrics.totalRequests > 0 ? (metrics.cacheMisses / metrics.totalRequests) * 100 : 0,
            Unit: 'Percent',
            Timestamp: new Date()
        }
    ];
    
    try {
        await cloudwatch.putMetricData({
            Namespace: 'CloudFront/RealTime',
            MetricData: metricData
        }).promise();
    } catch (error) {
        console.error('Error sending CloudWatch metrics:', error);
    }
}
EOF
    
    # Install dependencies and create deployment package
    cd /tmp/lambda-log-processor
    if command -v npm &> /dev/null; then
        npm install --production
    else
        log_warning "npm not found. Lambda function may not work properly without dependencies."
    fi
    zip -r lambda-log-processor.zip .
    cd - > /dev/null
    
    # Create IAM role for Lambda function
    if ! aws iam get-role --role-name ${PROJECT_NAME}-lambda-role &>/dev/null; then
        cat > /tmp/lambda-trust-policy.json << 'EOF'
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
            --role-name ${PROJECT_NAME}-lambda-role \
            --assume-role-policy-document file:///tmp/lambda-trust-policy.json
        
        # Create custom policy for the Lambda function
        cat > /tmp/lambda-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "kinesis:DescribeStream",
                "kinesis:GetRecords",
                "kinesis:GetShardIterator",
                "kinesis:ListStreams",
                "kinesis:PutRecord",
                "kinesis:PutRecords"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${METRICS_TABLE_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
        
        aws iam put-role-policy \
            --role-name ${PROJECT_NAME}-lambda-role \
            --policy-name CloudFrontLogProcessingPolicy \
            --policy-document file:///tmp/lambda-policy.json
        
        aws iam attach-role-policy \
            --role-name ${PROJECT_NAME}-lambda-role \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        log_info "Waiting for IAM role to propagate..."
        sleep 10
    else
        log_warning "Lambda IAM role already exists"
    fi
    
    # Create or update Lambda function
    if ! aws lambda get-function --function-name ${PROJECT_NAME}-log-processor &>/dev/null; then
        aws lambda create-function \
            --function-name ${PROJECT_NAME}-log-processor \
            --runtime nodejs18.x \
            --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-role \
            --handler index.handler \
            --zip-file fileb:///tmp/lambda-log-processor/lambda-log-processor.zip \
            --timeout 300 \
            --memory-size 512 \
            --environment Variables="{
                \"METRICS_TABLE\":\"${METRICS_TABLE_NAME}\",
                \"PROCESSED_STREAM\":\"${KINESIS_STREAM_NAME}-processed\"
            }"
    else
        log_warning "Lambda function already exists"
    fi
    
    log_success "Lambda function created"
}

# Create Kinesis Data Firehose
create_firehose_delivery_stream() {
    log_info "Creating Kinesis Data Firehose for data delivery..."
    
    # Wait for OpenSearch domain to be available
    log_info "Waiting for OpenSearch domain to be ready..."
    aws opensearch wait domain-available --domain-name ${OPENSEARCH_DOMAIN}
    
    # Create IAM role for Kinesis Data Firehose
    if ! aws iam get-role --role-name ${PROJECT_NAME}-firehose-role &>/dev/null; then
        cat > /tmp/firehose-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "firehose.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
        
        aws iam create-role \
            --role-name ${PROJECT_NAME}-firehose-role \
            --assume-role-policy-document file:///tmp/firehose-trust-policy.json
        
        # Create policy for Firehose
        cat > /tmp/firehose-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:AbortMultipartUpload",
                "s3:GetBucketLocation",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:ListBucketMultipartUploads",
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::${S3_BUCKET_NAME}",
                "arn:aws:s3:::${S3_BUCKET_NAME}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "es:DescribeElasticsearchDomain",
                "es:DescribeElasticsearchDomains",
                "es:DescribeElasticsearchDomainConfig",
                "es:ESHttpPost",
                "es:ESHttpPut"
            ],
            "Resource": "arn:aws:es:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/${OPENSEARCH_DOMAIN}/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
        
        aws iam put-role-policy \
            --role-name ${PROJECT_NAME}-firehose-role \
            --policy-name FirehoseDeliveryPolicy \
            --policy-document file:///tmp/firehose-policy.json
        
        log_info "Waiting for Firehose IAM role to propagate..."
        sleep 10
    else
        log_warning "Firehose IAM role already exists"
    fi
    
    # Create Kinesis Data Firehose delivery stream
    if ! aws firehose describe-delivery-stream --delivery-stream-name ${PROJECT_NAME}-logs-to-s3-opensearch &>/dev/null; then
        aws firehose create-delivery-stream \
            --delivery-stream-name ${PROJECT_NAME}-logs-to-s3-opensearch \
            --delivery-stream-type KinesisStreamAsSource \
            --kinesis-stream-source-configuration "{
                \"KinesisStreamARN\": \"arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/${KINESIS_STREAM_NAME}-processed\",
                \"RoleARN\": \"arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-firehose-role\"
            }" \
            --extended-s3-destination-configuration "{
                \"RoleARN\": \"arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-firehose-role\",
                \"BucketARN\": \"arn:aws:s3:::${S3_BUCKET_NAME}\",
                \"Prefix\": \"cloudfront-logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/\",
                \"BufferingHints\": {
                    \"SizeInMBs\": 5,
                    \"IntervalInSeconds\": 60
                },
                \"CompressionFormat\": \"GZIP\",
                \"ProcessingConfiguration\": {
                    \"Enabled\": false
                },
                \"CloudWatchLoggingOptions\": {
                    \"Enabled\": true,
                    \"LogGroupName\": \"/aws/kinesisfirehose/${PROJECT_NAME}\",
                    \"LogStreamName\": \"S3Delivery\"
                }
            }"
    else
        log_warning "Firehose delivery stream already exists"
    fi
    
    log_success "Kinesis Data Firehose created"
}

# Create Lambda event source mapping
create_event_source_mapping() {
    log_info "Creating Lambda event source mapping..."
    
    # Check if mapping already exists
    EXISTING_MAPPINGS=$(aws lambda list-event-source-mappings \
        --function-name ${PROJECT_NAME}-log-processor \
        --query 'EventSourceMappings[?EventSourceArn==`arn:aws:kinesis:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':stream/'${KINESIS_STREAM_NAME}'`].UUID' \
        --output text)
    
    if [[ -z "$EXISTING_MAPPINGS" ]]; then
        aws lambda create-event-source-mapping \
            --event-source-arn arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/${KINESIS_STREAM_NAME} \
            --function-name ${PROJECT_NAME}-log-processor \
            --starting-position LATEST \
            --batch-size 100 \
            --maximum-batching-window-in-seconds 5
    else
        log_warning "Lambda event source mapping already exists"
    fi
    
    log_success "Lambda event source mapping created"
}

# Create CloudFront distribution
create_cloudfront_distribution() {
    log_info "Creating CloudFront distribution..."
    
    # Create Origin Access Control for S3
    OAC_OUTPUT=$(aws cloudfront create-origin-access-control \
        --origin-access-control-config "{
            \"Name\": \"${PROJECT_NAME}-oac\",
            \"Description\": \"Origin Access Control for monitoring demo\",
            \"SigningProtocol\": \"sigv4\",
            \"SigningBehavior\": \"always\",
            \"OriginAccessControlOriginType\": \"s3\"
        }" 2>/dev/null || echo '{"OriginAccessControl":{"Id":"existing"}}')
    
    OAC_ID=$(echo $OAC_OUTPUT | jq -r '.OriginAccessControl.Id')
    
    # Create CloudFront distribution configuration
    cat > /tmp/cloudfront-config.json << EOF
{
    "CallerReference": "${PROJECT_NAME}-$(date +%s)",
    "Comment": "CloudFront distribution for real-time monitoring demo",
    "Enabled": true,
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "S3Origin",
                "DomainName": "${S3_CONTENT_BUCKET}.s3.amazonaws.com",
                "OriginPath": "",
                "CustomHeaders": {
                    "Quantity": 0
                },
                "S3OriginConfig": {
                    "OriginAccessIdentity": ""
                },
                "OriginAccessControlId": "${OAC_ID}",
                "ConnectionAttempts": 3,
                "ConnectionTimeout": 10
            }
        ]
    },
    "DefaultCacheBehavior": {
        "TargetOriginId": "S3Origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "TrustedKeyGroups": {
            "Enabled": false,
            "Quantity": 0
        },
        "AllowedMethods": {
            "Quantity": 7,
            "Items": ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        },
        "SmoothStreaming": false,
        "Compress": true,
        "LambdaFunctionAssociations": {
            "Quantity": 0
        },
        "FunctionAssociations": {
            "Quantity": 0
        },
        "FieldLevelEncryptionId": "",
        "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    },
    "CacheBehaviors": {
        "Quantity": 1,
        "Items": [
            {
                "PathPattern": "/api/*",
                "TargetOriginId": "S3Origin",
                "ViewerProtocolPolicy": "https-only",
                "TrustedSigners": {
                    "Enabled": false,
                    "Quantity": 0
                },
                "TrustedKeyGroups": {
                    "Enabled": false,
                    "Quantity": 0
                },
                "AllowedMethods": {
                    "Quantity": 7,
                    "Items": ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"],
                    "CachedMethods": {
                        "Quantity": 2,
                        "Items": ["GET", "HEAD"]
                    }
                },
                "SmoothStreaming": false,
                "Compress": true,
                "LambdaFunctionAssociations": {
                    "Quantity": 0
                },
                "FunctionAssociations": {
                    "Quantity": 0
                },
                "FieldLevelEncryptionId": "",
                "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
            }
        ]
    },
    "CustomErrorResponses": {
        "Quantity": 0
    },
    "PriceClass": "PriceClass_100",
    "ViewerCertificate": {
        "CloudFrontDefaultCertificate": true,
        "MinimumProtocolVersion": "TLSv1.2_2021",
        "CertificateSource": "cloudfront"
    },
    "Restrictions": {
        "GeoRestriction": {
            "RestrictionType": "none",
            "Quantity": 0
        }
    },
    "HttpVersion": "http2",
    "IsIPV6Enabled": true,
    "DefaultRootObject": "index.html"
}
EOF
    
    # Create CloudFront distribution
    CF_OUTPUT=$(aws cloudfront create-distribution \
        --distribution-config file:///tmp/cloudfront-config.json)
    
    export CF_DISTRIBUTION_ID=$(echo $CF_OUTPUT | jq -r '.Distribution.Id')
    export CF_DOMAIN_NAME=$(echo $CF_OUTPUT | jq -r '.Distribution.DomainName')
    
    # Save distribution info to .env file
    echo "CF_DISTRIBUTION_ID=${CF_DISTRIBUTION_ID}" >> .env
    echo "CF_DOMAIN_NAME=${CF_DOMAIN_NAME}" >> .env
    
    log_success "CloudFront distribution created: ${CF_DISTRIBUTION_ID}"
    log_success "CloudFront domain: ${CF_DOMAIN_NAME}"
}

# Configure S3 bucket policy and real-time logs
configure_realtime_logs() {
    log_info "Configuring S3 bucket policy and real-time logs..."
    
    # Configure S3 bucket policy for CloudFront access
    cat > /tmp/s3-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowCloudFrontServicePrincipal",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudfront.amazonaws.com"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${S3_CONTENT_BUCKET}/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "arn:aws:cloudfront::${AWS_ACCOUNT_ID}:distribution/${CF_DISTRIBUTION_ID}"
                }
            }
        }
    ]
}
EOF
    
    aws s3api put-bucket-policy \
        --bucket ${S3_CONTENT_BUCKET} \
        --policy file:///tmp/s3-policy.json
    
    # Create IAM role for CloudFront real-time logs
    if ! aws iam get-role --role-name ${PROJECT_NAME}-realtime-logs-role &>/dev/null; then
        cat > /tmp/realtime-logs-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudfront.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
        
        aws iam create-role \
            --role-name ${PROJECT_NAME}-realtime-logs-role \
            --assume-role-policy-document file:///tmp/realtime-logs-trust-policy.json
        
        # Create policy for real-time logs
        cat > /tmp/realtime-logs-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "kinesis:PutRecords",
                "kinesis:PutRecord"
            ],
            "Resource": "arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/${KINESIS_STREAM_NAME}"
        }
    ]
}
EOF
        
        aws iam put-role-policy \
            --role-name ${PROJECT_NAME}-realtime-logs-role \
            --policy-name KinesisAccess \
            --policy-document file:///tmp/realtime-logs-policy.json
        
        log_info "Waiting for real-time logs IAM role to propagate..."
        sleep 10
    else
        log_warning "Real-time logs IAM role already exists"
    fi
    
    # Create real-time log configuration
    if ! aws cloudfront get-realtime-log-config --name "${PROJECT_NAME}-realtime-logs" &>/dev/null; then
        aws cloudfront create-realtime-log-config \
            --name "${PROJECT_NAME}-realtime-logs" \
            --end-points StreamType=Kinesis,StreamArn=arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/${KINESIS_STREAM_NAME},RoleArn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-realtime-logs-role \
            --fields timestamp c-ip sc-status cs-method cs-uri-stem cs-uri-query cs-referer cs-user-agent cs-cookie x-edge-location x-edge-request-id x-host-header cs-protocol cs-bytes sc-bytes time-taken x-forwarded-for ssl-protocol ssl-cipher x-edge-response-result-type cs-protocol-version fle-status fle-encrypted-fields c-port time-to-first-byte x-edge-detailed-result-type sc-content-type sc-content-len sc-range-start sc-range-end
    else
        log_warning "Real-time log configuration already exists"
    fi
    
    log_success "Real-time logging configured"
}

# Create CloudWatch dashboard
create_cloudwatch_dashboard() {
    log_info "Creating CloudWatch monitoring dashboard..."
    
    # Create CloudWatch dashboard
    cat > /tmp/dashboard-config.json << EOF
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
                    ["CloudFront/RealTime", "RequestCount"],
                    [".", "BytesDownloaded"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Real-time Traffic Volume"
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
                    ["CloudFront/RealTime", "ErrorRate4xx"],
                    [".", "ErrorRate5xx"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Real-time Error Rates"
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["CloudFront/RealTime", "CacheMissRate"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Cache Performance"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Lambda", "Duration", "FunctionName", "${PROJECT_NAME}-log-processor"],
                    [".", "Invocations", ".", "."],
                    [".", "Errors", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Log Processing Performance"
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 12,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Kinesis", "IncomingRecords", "StreamName", "${KINESIS_STREAM_NAME}"],
                    [".", "OutgoingRecords", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Kinesis Stream Activity"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 12,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/CloudFront", "Requests", "DistributionId", "${CF_DISTRIBUTION_ID}"],
                    [".", "BytesDownloaded", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "us-east-1",
                "title": "CloudFront Standard Metrics"
            }
        }
    ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "CloudFront-RealTime-Analytics-${RANDOM_SUFFIX}" \
        --dashboard-body file:///tmp/dashboard-config.json
    
    echo "DASHBOARD_NAME=CloudFront-RealTime-Analytics-${RANDOM_SUFFIX}" >> .env
    
    log_success "CloudWatch dashboard created"
}

# Clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    rm -rf /tmp/content /tmp/lambda-log-processor
    rm -f /tmp/*.json
    log_success "Temporary files cleaned up"
}

# Display deployment summary
show_deployment_summary() {
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    log_info "Deployment Summary:"
    echo "  Project Name: ${PROJECT_NAME}"
    echo "  AWS Region: ${AWS_REGION}"
    echo "  CloudFront Distribution ID: ${CF_DISTRIBUTION_ID}"
    echo "  CloudFront Domain: ${CF_DOMAIN_NAME}"
    echo "  OpenSearch Domain: ${OPENSEARCH_DOMAIN}"
    echo "  DynamoDB Table: ${METRICS_TABLE_NAME}"
    echo "  Kinesis Stream: ${KINESIS_STREAM_NAME}"
    echo "  Dashboard: CloudFront-RealTime-Analytics-${RANDOM_SUFFIX}"
    echo
    log_info "Next Steps:"
    echo "  1. Wait for CloudFront distribution to deploy (5-10 minutes)"
    echo "  2. Test the monitoring by visiting: https://${CF_DOMAIN_NAME}"
    echo "  3. View metrics in CloudWatch dashboard"
    echo "  4. Check OpenSearch dashboards when domain is ready"
    echo
    log_warning "Important: This deployment may incur AWS charges."
    log_warning "Run ./destroy.sh to clean up resources when testing is complete."
    echo
    log_info "Environment variables saved to .env file for cleanup script"
}

# Main deployment function
main() {
    log_info "Starting CloudFront Real-time Monitoring and Analytics deployment..."
    
    check_prerequisites
    setup_environment
    setup_s3_buckets
    create_kinesis_streams
    create_opensearch_domain
    create_dynamodb_table
    create_lambda_function
    create_firehose_delivery_stream
    create_event_source_mapping
    create_cloudfront_distribution
    configure_realtime_logs
    create_cloudwatch_dashboard
    cleanup_temp_files
    show_deployment_summary
}

# Run main function
main "$@"