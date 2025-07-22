#!/bin/bash

# CloudFront Cache Invalidation Strategies - Deployment Script
# This script deploys the complete infrastructure for intelligent CloudFront cache invalidation

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Starting cleanup of partially created resources..."
    
    # Clean up resources that might have been created
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME" 2>/dev/null || true
    fi
    
    if [[ -n "${EVENTBRIDGE_BUS_NAME:-}" ]]; then
        aws events delete-event-bus --name "$EVENTBRIDGE_BUS_NAME" 2>/dev/null || true
    fi
    
    if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
        aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive 2>/dev/null || true
        aws s3 rb "s3://${S3_BUCKET_NAME}" 2>/dev/null || true
    fi
    
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions
    info "Checking AWS permissions..."
    local required_services=("cloudfront" "lambda" "events" "s3" "dynamodb" "sqs" "iam" "logs")
    
    for service in "${required_services[@]}"; do
        if ! aws "${service}" help &> /dev/null; then
            error "Missing permissions for AWS ${service}. Please check your IAM policies."
            exit 1
        fi
    done
    
    log "Prerequisites check completed successfully"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warn "No region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 8)")
    
    export PROJECT_NAME="cf-invalidation-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="cf-origin-content-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="cf-invalidation-processor-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_BUS_NAME="cf-invalidation-events-${RANDOM_SUFFIX}"
    export DDB_TABLE_NAME="cf-invalidation-log-${RANDOM_SUFFIX}"
    
    # Create deployment state file
    cat > ".deployment_state" << EOF
PROJECT_NAME=${PROJECT_NAME}
S3_BUCKET_NAME=${S3_BUCKET_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
EVENTBRIDGE_BUS_NAME=${EVENTBRIDGE_BUS_NAME}
DDB_TABLE_NAME=${DDB_TABLE_NAME}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
DEPLOYMENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    log "Environment variables configured"
    info "Project Name: ${PROJECT_NAME}"
    info "AWS Region: ${AWS_REGION}"
    info "AWS Account ID: ${AWS_ACCOUNT_ID}"
}

# Function to create S3 bucket and upload content
create_s3_resources() {
    log "Creating S3 bucket and uploading content..."
    
    # Create S3 bucket
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
        warn "S3 bucket ${S3_BUCKET_NAME} already exists"
    else
        aws s3 mb "s3://${S3_BUCKET_NAME}" --region "$AWS_REGION"
        log "S3 bucket created: ${S3_BUCKET_NAME}"
    fi
    
    # Create sample content structure
    local content_dir="/tmp/cf-invalidation-content"
    mkdir -p "${content_dir}"/{images,css,js,api}
    
    # Create sample files
    cat > "${content_dir}/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>CloudFront Cache Invalidation Demo</title>
    <link rel="stylesheet" href="/css/style.css">
</head>
<body>
    <h1>Home Page</h1>
    <p>Version 1.0 - Cache Invalidation Demo</p>
    <script src="/js/app.js"></script>
</body>
</html>
EOF
    
    cat > "${content_dir}/css/style.css" << 'EOF'
body {
    font-family: Arial, sans-serif;
    background-color: #f0f0f0;
    margin: 0;
    padding: 20px;
}
h1 {
    color: #333;
    text-align: center;
}
p {
    color: #666;
    text-align: center;
}
EOF
    
    cat > "${content_dir}/js/app.js" << 'EOF'
console.log("CloudFront Cache Invalidation Demo v1.0");
document.addEventListener('DOMContentLoaded', function() {
    console.log("Page loaded successfully");
});
EOF
    
    cat > "${content_dir}/api/status.json" << 'EOF'
{
    "status": "active",
    "version": "1.0",
    "timestamp": "2025-01-09T00:00:00Z",
    "features": ["basic-invalidation", "monitoring"]
}
EOF
    
    # Upload content to S3
    aws s3 cp "${content_dir}" "s3://${S3_BUCKET_NAME}/" --recursive
    
    # Clean up local content
    rm -rf "${content_dir}"
    
    log "S3 content uploaded successfully"
}

# Function to create DynamoDB table
create_dynamodb_table() {
    log "Creating DynamoDB table for invalidation logging..."
    
    aws dynamodb create-table \
        --table-name "$DDB_TABLE_NAME" \
        --attribute-definitions \
            AttributeName=InvalidationId,AttributeType=S \
            AttributeName=Timestamp,AttributeType=S \
        --key-schema \
            AttributeName=InvalidationId,KeyType=HASH \
            AttributeName=Timestamp,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
        --tags Key=Project,Value="$PROJECT_NAME" Key=Purpose,Value="InvalidationLogging"
    
    # Wait for table to be active
    log "Waiting for DynamoDB table to be active..."
    aws dynamodb wait table-exists --table-name "$DDB_TABLE_NAME"
    
    log "DynamoDB table created: ${DDB_TABLE_NAME}"
}

# Function to create SQS queues
create_sqs_queues() {
    log "Creating SQS queues for batch processing..."
    
    # Create main queue
    aws sqs create-queue \
        --queue-name "${PROJECT_NAME}-batch-queue" \
        --attributes '{
            "VisibilityTimeoutSeconds": "300",
            "MessageRetentionPeriod": "1209600",
            "MaxReceiveCount": "3",
            "ReceiveMessageWaitTimeSeconds": "20"
        }' \
        --tags "Project=${PROJECT_NAME},Purpose=BatchProcessing"
    
    export QUEUE_URL=$(aws sqs get-queue-url \
        --queue-name "${PROJECT_NAME}-batch-queue" \
        --query 'QueueUrl' --output text)
    
    # Create dead letter queue
    aws sqs create-queue \
        --queue-name "${PROJECT_NAME}-dlq" \
        --attributes '{"MessageRetentionPeriod": "1209600"}' \
        --tags "Project=${PROJECT_NAME},Purpose=DeadLetter"
    
    local DLQ_URL=$(aws sqs get-queue-url \
        --queue-name "${PROJECT_NAME}-dlq" \
        --query 'QueueUrl' --output text)
    
    # Configure dead letter queue policy
    local DLQ_ARN="arn:aws:sqs:${AWS_REGION}:${AWS_ACCOUNT_ID}:${PROJECT_NAME}-dlq"
    
    aws sqs set-queue-attributes \
        --queue-url "$QUEUE_URL" \
        --attributes "{
            \"RedrivePolicy\": \"{\\\"deadLetterTargetArn\\\":\\\"${DLQ_ARN}\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"
        }"
    
    # Update deployment state
    echo "QUEUE_URL=${QUEUE_URL}" >> .deployment_state
    echo "DLQ_URL=${DLQ_URL}" >> .deployment_state
    
    log "SQS queues created successfully"
}

# Function to create EventBridge resources
create_eventbridge_resources() {
    log "Creating EventBridge custom bus and rules..."
    
    # Create custom event bus
    aws events create-event-bus --name "$EVENTBRIDGE_BUS_NAME"
    
    # Create event rule for S3 content changes
    cat > "/tmp/s3-rule.json" << EOF
{
    "Name": "${PROJECT_NAME}-s3-rule",
    "EventPattern": {
        "source": ["aws.s3"],
        "detail-type": ["Object Created", "Object Deleted"],
        "detail": {
            "bucket": {
                "name": ["${S3_BUCKET_NAME}"]
            }
        }
    },
    "State": "ENABLED",
    "EventBusName": "${EVENTBRIDGE_BUS_NAME}"
}
EOF
    
    aws events put-rule --cli-input-json file:///tmp/s3-rule.json
    
    # Create event rule for deployment events
    cat > "/tmp/deploy-rule.json" << EOF
{
    "Name": "${PROJECT_NAME}-deploy-rule",
    "EventPattern": {
        "source": ["aws.codedeploy", "custom.app"],
        "detail-type": ["Deployment State-change Notification", "Application Deployment"]
    },
    "State": "ENABLED",
    "EventBusName": "${EVENTBRIDGE_BUS_NAME}"
}
EOF
    
    aws events put-rule --cli-input-json file:///tmp/deploy-rule.json
    
    # Clean up temp files
    rm -f /tmp/s3-rule.json /tmp/deploy-rule.json
    
    log "EventBridge bus and rules created"
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function for intelligent invalidation..."
    
    # Create Lambda function directory
    local lambda_dir="/tmp/lambda-invalidation"
    mkdir -p "$lambda_dir"
    
    # Create package.json
    cat > "${lambda_dir}/package.json" << 'EOF'
{
    "name": "cloudfront-invalidation",
    "version": "1.0.0",
    "description": "Intelligent CloudFront cache invalidation",
    "dependencies": {
        "aws-sdk": "^2.1000.0"
    }
}
EOF
    
    # Create Lambda function code
    cat > "${lambda_dir}/index.js" << 'EOF'
const AWS = require('aws-sdk');
const cloudfront = new AWS.CloudFront();
const dynamodb = new AWS.DynamoDB.DocumentClient();
const sqs = new AWS.SQS();

const TABLE_NAME = process.env.DDB_TABLE_NAME;
const QUEUE_URL = process.env.QUEUE_URL;
const DISTRIBUTION_ID = process.env.DISTRIBUTION_ID;
const BATCH_SIZE = 10; // CloudFront allows max 15 paths per invalidation

exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    try {
        // Process different event sources
        let invalidationPaths = [];
        
        if (event.source === 'aws.s3') {
            invalidationPaths = await processS3Event(event);
        } else if (event.source === 'aws.codedeploy' || event.source === 'custom.app') {
            invalidationPaths = await processDeploymentEvent(event);
        } else if (event.Records) {
            // SQS batch processing
            invalidationPaths = await processSQSBatch(event);
        }
        
        if (invalidationPaths.length === 0) {
            console.log('No invalidation paths to process');
            return { statusCode: 200, body: 'No invalidation needed' };
        }
        
        // Optimize paths using intelligent grouping
        const optimizedPaths = optimizeInvalidationPaths(invalidationPaths);
        
        // Create invalidation batches
        const batches = createBatches(optimizedPaths, BATCH_SIZE);
        
        const results = [];
        for (const batch of batches) {
            const result = await createInvalidation(batch);
            results.push(result);
            
            // Log invalidation to DynamoDB
            await logInvalidation(result.Invalidation.Id, batch, event);
        }
        
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Invalidations created successfully',
                invalidations: results.length,
                paths: optimizedPaths.length
            })
        };
        
    } catch (error) {
        console.error('Error processing invalidation:', error);
        
        // Send failed paths to DLQ for retry
        if (event.source && invalidationPaths.length > 0) {
            await sendToDeadLetterQueue(invalidationPaths, error);
        }
        
        throw error;
    }
};

async function processS3Event(event) {
    const paths = [];
    
    if (event.detail && event.detail.object) {
        const objectKey = event.detail.object.key;
        const eventName = event['detail-type'];
        
        // Smart path invalidation based on content type
        if (objectKey.endsWith('.html')) {
            paths.push(`/${objectKey}`);
            // Also invalidate directory index
            if (objectKey.includes('/')) {
                const dir = objectKey.substring(0, objectKey.lastIndexOf('/'));
                paths.push(`/${dir}/`);
            }
        } else if (objectKey.match(/\.(css|js|json)$/)) {
            // Invalidate specific asset
            paths.push(`/${objectKey}`);
            
            // For CSS/JS changes, also invalidate HTML pages that might reference them
            if (objectKey.includes('css/') || objectKey.includes('js/')) {
                paths.push('/index.html');
                paths.push('/');
            }
        } else if (objectKey.match(/\.(jpg|jpeg|png|gif|webp|svg)$/)) {
            // Image invalidation
            paths.push(`/${objectKey}`);
        }
    }
    
    return [...new Set(paths)]; // Remove duplicates
}

async function processDeploymentEvent(event) {
    // For deployment events, invalidate common paths
    const deploymentPaths = [
        '/',
        '/index.html',
        '/css/*',
        '/js/*',
        '/api/*'
    ];
    
    // If deployment includes specific file changes, add them
    if (event.detail && event.detail.changedFiles) {
        event.detail.changedFiles.forEach(file => {
            deploymentPaths.push(`/${file}`);
        });
    }
    
    return deploymentPaths;
}

async function processSQSBatch(event) {
    const paths = [];
    
    for (const record of event.Records) {
        try {
            const body = JSON.parse(record.body);
            if (body.paths && Array.isArray(body.paths)) {
                paths.push(...body.paths);
            }
        } catch (error) {
            console.error('Error parsing SQS message:', error);
        }
    }
    
    return [...new Set(paths)];
}

function optimizeInvalidationPaths(paths) {
    // Remove redundant paths and optimize patterns
    const optimized = new Set();
    const sorted = paths.sort();
    
    for (const path of sorted) {
        let isRedundant = false;
        
        // Check if this path is covered by an existing wildcard
        for (const existing of optimized) {
            if (existing.endsWith('/*') && path.startsWith(existing.slice(0, -1))) {
                isRedundant = true;
                break;
            }
        }
        
        if (!isRedundant) {
            optimized.add(path);
        }
    }
    
    return Array.from(optimized);
}

function createBatches(paths, batchSize) {
    const batches = [];
    for (let i = 0; i < paths.length; i += batchSize) {
        batches.push(paths.slice(i, i + batchSize));
    }
    return batches;
}

async function createInvalidation(paths) {
    const params = {
        DistributionId: DISTRIBUTION_ID,
        InvalidationBatch: {
            Paths: {
                Quantity: paths.length,
                Items: paths
            },
            CallerReference: `invalidation-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`
        }
    };
    
    console.log('Creating invalidation for paths:', paths);
    return await cloudfront.createInvalidation(params).promise();
}

async function logInvalidation(invalidationId, paths, originalEvent) {
    const params = {
        TableName: TABLE_NAME,
        Item: {
            InvalidationId: invalidationId,
            Timestamp: new Date().toISOString(),
            Paths: paths,
            PathCount: paths.length,
            Source: originalEvent.source || 'unknown',
            EventType: originalEvent['detail-type'] || 'unknown',
            Status: 'InProgress',
            TTL: Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60) // 30 days
        }
    };
    
    await dynamodb.put(params).promise();
}

async function sendToDeadLetterQueue(paths, error) {
    const message = {
        paths: paths,
        error: error.message,
        timestamp: new Date().toISOString()
    };
    
    const params = {
        QueueUrl: QUEUE_URL.replace(QUEUE_URL.split('/').pop(), QUEUE_URL.split('/').pop().replace('batch-queue', 'dlq')),
        MessageBody: JSON.stringify(message)
    };
    
    await sqs.sendMessage(params).promise();
}
EOF
    
    # Install dependencies and create deployment package
    cd "$lambda_dir"
    npm install --production --silent
    zip -r lambda-invalidation.zip . > /dev/null
    cd - > /dev/null
    
    log "Lambda function package created"
}

# Function to create IAM role for Lambda
create_lambda_iam_role() {
    log "Creating IAM role for Lambda function..."
    
    # Create trust policy
    cat > "/tmp/lambda-trust-policy.json" << 'EOF'
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
    
    # Create the role
    aws iam create-role \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
        --tags Key=Project,Value="$PROJECT_NAME"
    
    # Create custom policy
    cat > "/tmp/lambda-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudfront:CreateInvalidation",
                "cloudfront:GetInvalidation",
                "cloudfront:ListInvalidations"
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
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DDB_TABLE_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sqs:SendMessage",
                "sqs:ReceiveMessage",
                "sqs:DeleteMessage",
                "sqs:GetQueueAttributes"
            ],
            "Resource": "arn:aws:sqs:${AWS_REGION}:${AWS_ACCOUNT_ID}:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        }
    ]
}
EOF
    
    # Attach policies to role
    aws iam put-role-policy \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --policy-name CloudFrontInvalidationPolicy \
        --policy-document file:///tmp/lambda-policy.json
    
    aws iam attach-role-policy \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Wait for role to be available
    sleep 10
    
    # Clean up temp files
    rm -f /tmp/lambda-trust-policy.json /tmp/lambda-policy.json
    
    log "IAM role created and configured"
}

# Function to create CloudFront distribution
create_cloudfront_distribution() {
    log "Creating CloudFront distribution..."
    
    # Create Origin Access Control
    cat > "/tmp/oac-config.json" << EOF
{
    "Name": "${PROJECT_NAME}-oac",
    "OriginAccessControlConfig": {
        "Name": "${PROJECT_NAME}-oac",
        "Description": "Origin Access Control for invalidation demo",
        "SigningProtocol": "sigv4",
        "SigningBehavior": "always",
        "OriginAccessControlOriginType": "s3"
    }
}
EOF
    
    local OAC_ID=$(aws cloudfront create-origin-access-control \
        --origin-access-control-config file:///tmp/oac-config.json \
        --query 'OriginAccessControl.Id' --output text)
    
    # Create distribution configuration
    cat > "/tmp/distribution-config.json" << EOF
{
    "CallerReference": "${PROJECT_NAME}-$(date +%s)",
    "Comment": "CloudFront distribution for invalidation demo",
    "Enabled": true,
    "Origins": {
        "Quantity": 1,
        "Items": [
            {
                "Id": "S3Origin",
                "DomainName": "${S3_BUCKET_NAME}.s3.amazonaws.com",
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
            "Quantity": 2,
            "Items": ["GET", "HEAD"],
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
        "Quantity": 2,
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
                    "Quantity": 2,
                    "Items": ["GET", "HEAD"],
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
            {
                "PathPattern": "/css/*",
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
                    "Quantity": 2,
                    "Items": ["GET", "HEAD"],
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
                "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6"
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
    
    # Create distribution
    local DISTRIBUTION_OUTPUT=$(aws cloudfront create-distribution \
        --distribution-config file:///tmp/distribution-config.json)
    
    export DISTRIBUTION_ID=$(echo "$DISTRIBUTION_OUTPUT" | jq -r '.Distribution.Id')
    export DISTRIBUTION_DOMAIN=$(echo "$DISTRIBUTION_OUTPUT" | jq -r '.Distribution.DomainName')
    
    # Update deployment state
    echo "DISTRIBUTION_ID=${DISTRIBUTION_ID}" >> .deployment_state
    echo "DISTRIBUTION_DOMAIN=${DISTRIBUTION_DOMAIN}" >> .deployment_state
    echo "OAC_ID=${OAC_ID}" >> .deployment_state
    
    # Clean up temp files
    rm -f /tmp/oac-config.json /tmp/distribution-config.json
    
    log "CloudFront distribution created: ${DISTRIBUTION_ID}"
    log "Distribution domain: ${DISTRIBUTION_DOMAIN}"
}

# Function to deploy Lambda function
deploy_lambda_function() {
    log "Deploying Lambda function..."
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime nodejs18.x \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_FUNCTION_NAME}-role" \
        --handler index.handler \
        --zip-file fileb:///tmp/lambda-invalidation/lambda-invalidation.zip \
        --timeout 300 \
        --memory-size 256 \
        --environment Variables="{
            \"DDB_TABLE_NAME\":\"${DDB_TABLE_NAME}\",
            \"QUEUE_URL\":\"${QUEUE_URL}\",
            \"DISTRIBUTION_ID\":\"${DISTRIBUTION_ID}\"
        }" \
        --tags "Project=${PROJECT_NAME},Purpose=InvalidationProcessing"
    
    local LAMBDA_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}"
    
    # Add EventBridge permission to Lambda
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id eventbridge-invoke \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_BUS_NAME}/*"
    
    # Add SQS trigger for batch processing
    aws lambda create-event-source-mapping \
        --event-source-arn "arn:aws:sqs:${AWS_REGION}:${AWS_ACCOUNT_ID}:${PROJECT_NAME}-batch-queue" \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --batch-size 5 \
        --maximum-batching-window-in-seconds 30
    
    # Update deployment state
    echo "LAMBDA_ARN=${LAMBDA_ARN}" >> .deployment_state
    
    # Clean up Lambda package
    rm -rf /tmp/lambda-invalidation
    
    log "Lambda function deployed with triggers"
}

# Function to configure EventBridge targets
configure_eventbridge_targets() {
    log "Configuring EventBridge targets..."
    
    local LAMBDA_ARN="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}"
    
    # Add Lambda target to S3 rule
    aws events put-targets \
        --rule "${PROJECT_NAME}-s3-rule" \
        --event-bus-name "$EVENTBRIDGE_BUS_NAME" \
        --targets "[{
            \"Id\": \"1\",
            \"Arn\": \"${LAMBDA_ARN}\"
        }]"
    
    # Add Lambda target to deployment rule
    aws events put-targets \
        --rule "${PROJECT_NAME}-deploy-rule" \
        --event-bus-name "$EVENTBRIDGE_BUS_NAME" \
        --targets "[{
            \"Id\": \"1\",
            \"Arn\": \"${LAMBDA_ARN}\"
        }]"
    
    log "EventBridge targets configured"
}

# Function to configure S3 notifications
configure_s3_notifications() {
    log "Configuring S3 event notifications..."
    
    # Configure S3 bucket policy for CloudFront access
    cat > "/tmp/s3-policy.json" << EOF
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
            "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "arn:aws:cloudfront::${AWS_ACCOUNT_ID}:distribution/${DISTRIBUTION_ID}"
                }
            }
        }
    ]
}
EOF
    
    aws s3api put-bucket-policy \
        --bucket "$S3_BUCKET_NAME" \
        --policy file:///tmp/s3-policy.json
    
    # Configure S3 event notifications to EventBridge
    aws s3api put-bucket-notification-configuration \
        --bucket "$S3_BUCKET_NAME" \
        --notification-configuration "{
            \"EventBridgeConfiguration\": {}
        }"
    
    # Clean up temp files
    rm -f /tmp/s3-policy.json
    
    log "S3 event notifications configured"
}

# Function to create CloudWatch dashboard
create_cloudwatch_dashboard() {
    log "Creating CloudWatch dashboard..."
    
    cat > "/tmp/dashboard-config.json" << EOF
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
                    ["AWS/CloudFront", "Requests", "DistributionId", "${DISTRIBUTION_ID}"],
                    [".", "CacheHitRate", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "us-east-1",
                "title": "CloudFront Performance"
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
                    ["AWS/Lambda", "Duration", "FunctionName", "${LAMBDA_FUNCTION_NAME}"],
                    [".", "Invocations", ".", "."],
                    [".", "Errors", ".", "."]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Invalidation Function Performance"
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
                    ["AWS/Events", "MatchedEvents", "EventBusName", "${EVENTBRIDGE_BUS_NAME}"],
                    ["AWS/SQS", "NumberOfMessagesSent", "QueueName", "${PROJECT_NAME}-batch-queue"],
                    [".", "NumberOfMessagesReceived", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Event Processing Volume"
            }
        }
    ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "CloudFront-Invalidation-${RANDOM_SUFFIX}" \
        --dashboard-body file:///tmp/dashboard-config.json
    
    # Update deployment state
    echo "DASHBOARD_NAME=CloudFront-Invalidation-${RANDOM_SUFFIX}" >> .deployment_state
    
    # Clean up temp files
    rm -f /tmp/dashboard-config.json
    
    log "CloudWatch dashboard created"
}

# Function to display deployment summary
display_deployment_summary() {
    log "Deployment completed successfully!"
    
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project Name: ${PROJECT_NAME}"
    echo "AWS Region: ${AWS_REGION}"
    echo "CloudFront Distribution ID: ${DISTRIBUTION_ID}"
    echo "CloudFront Domain: ${DISTRIBUTION_DOMAIN}"
    echo "S3 Bucket: ${S3_BUCKET_NAME}"
    echo "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "DynamoDB Table: ${DDB_TABLE_NAME}"
    echo "EventBridge Bus: ${EVENTBRIDGE_BUS_NAME}"
    echo "SQS Queue: ${PROJECT_NAME}-batch-queue"
    echo "CloudWatch Dashboard: CloudFront-Invalidation-${RANDOM_SUFFIX}"
    echo ""
    echo "Next Steps:"
    echo "1. Wait for CloudFront distribution to deploy (may take 15-20 minutes)"
    echo "2. Test the invalidation system by uploading files to the S3 bucket"
    echo "3. Monitor invalidation activity in the CloudWatch dashboard"
    echo "4. Check DynamoDB for invalidation logs"
    echo ""
    echo "Testing Commands:"
    echo "# Wait for distribution deployment"
    echo "aws cloudfront wait distribution-deployed --id ${DISTRIBUTION_ID}"
    echo ""
    echo "# Test content access"
    echo "curl -I https://${DISTRIBUTION_DOMAIN}/"
    echo ""
    echo "# Update content to trigger invalidation"
    echo "aws s3 cp new-file.html s3://${S3_BUCKET_NAME}/index.html"
    echo ""
    echo "Estimated monthly cost: \$20-50 (varies by usage)"
    echo "Use destroy.sh to clean up all resources when done testing."
}

# Main execution
main() {
    log "Starting CloudFront Cache Invalidation Strategy deployment..."
    
    # Check if deployment state file exists
    if [[ -f ".deployment_state" ]]; then
        warn "Deployment state file exists. This may indicate a previous deployment."
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Deployment cancelled."
            exit 0
        fi
    fi
    
    check_prerequisites
    setup_environment
    create_s3_resources
    create_dynamodb_table
    create_sqs_queues
    create_eventbridge_resources
    create_lambda_function
    create_lambda_iam_role
    create_cloudfront_distribution
    deploy_lambda_function
    configure_eventbridge_targets
    configure_s3_notifications
    create_cloudwatch_dashboard
    display_deployment_summary
    
    log "Deployment script completed successfully!"
}

# Run main function
main "$@"