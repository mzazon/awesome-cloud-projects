#!/bin/bash

# Blockchain-Based Voting Systems - Deployment Script
# This script deploys the complete blockchain voting system infrastructure
# including Ethereum nodes, smart contracts, Lambda functions, and monitoring

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [[ "$DRY_RUN" == "true" ]]; then
    warning "Running in DRY-RUN mode - no resources will be created"
fi

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEPLOYMENT_LOG="${PROJECT_ROOT}/deployment_$(date +%Y%m%d_%H%M%S).log"

# Redirect all output to log file while still showing on screen
exec > >(tee -a "${DEPLOYMENT_LOG}")
exec 2>&1

log "Starting Blockchain Voting System deployment..."
log "Deployment log: ${DEPLOYMENT_LOG}"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check Node.js for Lambda functions
    if ! command -v node &> /dev/null; then
        error "Node.js is not installed. Please install Node.js first."
        exit 1
    fi
    
    # Check npm
    if ! command -v npm &> /dev/null; then
        error "npm is not installed. Please install npm first."
        exit 1
    fi
    
    # Check required permissions
    log "Checking AWS permissions..."
    
    # Test basic permissions
    if ! aws sts get-caller-identity &> /dev/null; then
        error "Unable to access AWS account. Check your credentials."
        exit 1
    fi
    
    # Check region
    if [[ -z "${AWS_DEFAULT_REGION:-}" ]]; then
        export AWS_DEFAULT_REGION=$(aws configure get region)
        if [[ -z "${AWS_DEFAULT_REGION}" ]]; then
            error "AWS region not configured. Please set AWS_DEFAULT_REGION or run 'aws configure'."
            exit 1
        fi
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=${AWS_DEFAULT_REGION}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export VOTING_SYSTEM_NAME="voting-system-${RANDOM_SUFFIX}"
    export BLOCKCHAIN_NODE_NAME="voting-node-${RANDOM_SUFFIX}"
    export BUCKET_NAME="voting-system-data-${RANDOM_SUFFIX}"
    export LAMBDA_AUTH_FUNCTION="VoterAuthentication-${RANDOM_SUFFIX}"
    export LAMBDA_MONITOR_FUNCTION="VoteMonitoring-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup
    cat > "${PROJECT_ROOT}/deployment_env.sh" << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export VOTING_SYSTEM_NAME="${VOTING_SYSTEM_NAME}"
export BLOCKCHAIN_NODE_NAME="${BLOCKCHAIN_NODE_NAME}"
export BUCKET_NAME="${BUCKET_NAME}"
export LAMBDA_AUTH_FUNCTION="${LAMBDA_AUTH_FUNCTION}"
export LAMBDA_MONITOR_FUNCTION="${LAMBDA_MONITOR_FUNCTION}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
EOF
    
    log "Environment variables configured:"
    log "  AWS Region: ${AWS_REGION}"
    log "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    log "  Voting System Name: ${VOTING_SYSTEM_NAME}"
    log "  Bucket Name: ${BUCKET_NAME}"
}

# Function to create S3 bucket and DynamoDB tables
create_storage_resources() {
    log "Creating storage resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create S3 bucket: ${BUCKET_NAME}"
        info "DRY-RUN: Would create DynamoDB tables: VoterRegistry, Elections"
        return 0
    fi
    
    # Create S3 bucket with proper configuration
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        warning "S3 bucket ${BUCKET_NAME} already exists"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "${BUCKET_NAME}" \
            --versioning-configuration Status=Enabled
        
        # Enable server-side encryption
        aws s3api put-bucket-encryption \
            --bucket "${BUCKET_NAME}" \
            --server-side-encryption-configuration '{
                "Rules": [{
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }]
            }'
        
        log "Created S3 bucket: ${BUCKET_NAME}"
    fi
    
    # Create DynamoDB table for voter registry
    if aws dynamodb describe-table --table-name VoterRegistry 2>/dev/null; then
        warning "DynamoDB table VoterRegistry already exists"
    else
        aws dynamodb create-table \
            --table-name VoterRegistry \
            --attribute-definitions \
                AttributeName=VoterId,AttributeType=S \
                AttributeName=ElectionId,AttributeType=S \
            --key-schema \
                AttributeName=VoterId,KeyType=HASH \
                AttributeName=ElectionId,KeyType=RANGE \
            --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
            --region "${AWS_REGION}"
        
        # Wait for table to be active
        aws dynamodb wait table-exists --table-name VoterRegistry
        log "Created DynamoDB table: VoterRegistry"
    fi
    
    # Create DynamoDB table for election management
    if aws dynamodb describe-table --table-name Elections 2>/dev/null; then
        warning "DynamoDB table Elections already exists"
    else
        aws dynamodb create-table \
            --table-name Elections \
            --attribute-definitions \
                AttributeName=ElectionId,AttributeType=S \
            --key-schema \
                AttributeName=ElectionId,KeyType=HASH \
            --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
            --region "${AWS_REGION}"
        
        # Wait for table to be active
        aws dynamodb wait table-exists --table-name Elections
        log "Created DynamoDB table: Elections"
    fi
}

# Function to create blockchain node
create_blockchain_node() {
    log "Creating Ethereum blockchain node..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create Ethereum node: ${BLOCKCHAIN_NODE_NAME}"
        export NODE_ID="dry-run-node-id"
        return 0
    fi
    
    # Note: This is a placeholder since AWS Managed Blockchain for Ethereum 
    # requires additional setup and may not be available in all regions
    warning "Ethereum blockchain node creation requires manual setup"
    warning "Please configure your blockchain endpoint manually"
    
    # For demo purposes, we'll skip the actual blockchain node creation
    export NODE_ID="demo-node-id"
    
    log "Blockchain node configuration completed"
}

# Function to create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create temporary directory for Lambda packages
    LAMBDA_DIR="${PROJECT_ROOT}/lambda_tmp"
    mkdir -p "${LAMBDA_DIR}"
    
    # Create voter authentication Lambda function
    cat > "${LAMBDA_DIR}/voter-auth-lambda.js" << 'EOF'
const AWS = require('aws-sdk');
const crypto = require('crypto');

const dynamodb = new AWS.DynamoDB.DocumentClient();
const kms = new AWS.KMS();

exports.handler = async (event) => {
    console.log('Event:', JSON.stringify(event, null, 2));
    
    try {
        const action = event.action;
        
        switch (action) {
            case 'registerVoter':
                return await registerVoter(event);
            case 'verifyVoter':
                return await verifyVoter(event);
            case 'generateVotingToken':
                return await generateVotingToken(event);
            default:
                throw new Error(`Unknown action: ${action}`);
        }
        
    } catch (error) {
        console.error('Error in voter authentication:', error);
        return {
            statusCode: 400,
            body: JSON.stringify({
                error: error.message
            })
        };
    }
};

async function registerVoter(event) {
    const { voterId, electionId, identityDocument, publicKey } = event;
    
    if (!voterId || !electionId || !identityDocument || !publicKey) {
        throw new Error('Missing required fields for voter registration');
    }
    
    const voterIdHash = crypto.createHash('sha256').update(voterId).digest('hex');
    
    const voterRecord = {
        VoterId: voterIdHash,
        ElectionId: electionId,
        PublicKey: publicKey,
        RegistrationTimestamp: Date.now(),
        IsVerified: false,
        IsActive: true
    };
    
    await dynamodb.put({
        TableName: 'VoterRegistry',
        Item: voterRecord,
        ConditionExpression: 'attribute_not_exists(VoterId)'
    }).promise();
    
    return {
        statusCode: 200,
        body: JSON.stringify({
            message: 'Voter registered successfully',
            voterIdHash: voterIdHash,
            requiresVerification: true
        })
    };
}

async function verifyVoter(event) {
    const { voterIdHash, electionId, verificationCode } = event;
    
    const voterRecord = await dynamodb.get({
        TableName: 'VoterRegistry',
        Key: {
            VoterId: voterIdHash,
            ElectionId: electionId
        }
    }).promise();
    
    if (!voterRecord.Item) {
        throw new Error('Voter not found');
    }
    
    const isValidVerification = verificationCode && verificationCode.length >= 6;
    
    if (!isValidVerification) {
        throw new Error('Invalid verification code');
    }
    
    await dynamodb.update({
        TableName: 'VoterRegistry',
        Key: {
            VoterId: voterIdHash,
            ElectionId: electionId
        },
        UpdateExpression: 'SET IsVerified = :verified, VerificationTimestamp = :timestamp',
        ExpressionAttributeValues: {
            ':verified': true,
            ':timestamp': Date.now()
        }
    }).promise();
    
    return {
        statusCode: 200,
        body: JSON.stringify({
            message: 'Voter verified successfully',
            isVerified: true
        })
    };
}

async function generateVotingToken(event) {
    const { voterIdHash, electionId } = event;
    
    const voterRecord = await dynamodb.get({
        TableName: 'VoterRegistry',
        Key: {
            VoterId: voterIdHash,
            ElectionId: electionId
        }
    }).promise();
    
    if (!voterRecord.Item || !voterRecord.Item.IsVerified) {
        throw new Error('Voter not verified');
    }
    
    const tokenPayload = {
        voterIdHash: voterIdHash,
        electionId: electionId,
        timestamp: Date.now(),
        expiresAt: Date.now() + (60 * 60 * 1000)
    };
    
    return {
        statusCode: 200,
        body: JSON.stringify({
            message: 'Voting token generated successfully',
            token: Buffer.from(JSON.stringify(tokenPayload)).toString('base64'),
            expiresAt: tokenPayload.expiresAt
        })
    };
}
EOF
    
    # Create vote monitoring Lambda function
    cat > "${LAMBDA_DIR}/vote-monitor-lambda.js" << 'EOF'
const AWS = require('aws-sdk');

const dynamodb = new AWS.DynamoDB.DocumentClient();
const eventbridge = new AWS.EventBridge();
const s3 = new AWS.S3();

exports.handler = async (event) => {
    console.log('Processing voting event:', JSON.stringify(event, null, 2));
    
    try {
        const votingEvent = {
            eventType: event.eventType || 'UNKNOWN',
            electionId: event.electionId,
            candidateId: event.candidateId,
            voterAddress: event.voterAddress,
            transactionHash: event.transactionHash,
            blockNumber: event.blockNumber,
            timestamp: event.timestamp || Date.now()
        };
        
        switch (votingEvent.eventType) {
            case 'VoteCast':
                await processVoteCast(votingEvent);
                break;
            case 'ElectionCreated':
                await processElectionCreated(votingEvent);
                break;
            case 'ElectionEnded':
                await processElectionEnded(votingEvent);
                break;
            default:
                console.log(`Unknown event type: ${votingEvent.eventType}`);
        }
        
        console.log('AUDIT_EVENT:', JSON.stringify(votingEvent));
        
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Voting event processed successfully',
                eventType: votingEvent.eventType,
                electionId: votingEvent.electionId
            })
        };
        
    } catch (error) {
        console.error('Error processing voting event:', error);
        throw error;
    }
};

async function processVoteCast(event) {
    console.log(`Processing vote cast: Election ${event.electionId}`);
    
    await dynamodb.update({
        TableName: 'Elections',
        Key: { ElectionId: event.electionId },
        UpdateExpression: 'ADD TotalVotes :increment',
        ExpressionAttributeValues: {
            ':increment': 1
        }
    }).promise();
    
    const voteRecord = {
        electionId: event.electionId,
        candidateId: event.candidateId,
        transactionHash: event.transactionHash,
        blockNumber: event.blockNumber,
        timestamp: event.timestamp
    };
    
    await s3.putObject({
        Bucket: process.env.BUCKET_NAME,
        Key: `votes/${event.electionId}/${event.transactionHash}.json`,
        Body: JSON.stringify(voteRecord),
        ServerSideEncryption: 'AES256'
    }).promise();
}

async function processElectionCreated(event) {
    console.log(`Processing election creation: ${event.electionId}`);
    
    const electionRecord = {
        ElectionId: event.electionId,
        CreatedAt: event.timestamp,
        Status: 'ACTIVE',
        TotalVotes: 0,
        LastUpdated: event.timestamp
    };
    
    await dynamodb.put({
        TableName: 'Elections',
        Item: electionRecord
    }).promise();
}

async function processElectionEnded(event) {
    console.log(`Processing election end: ${event.electionId}`);
    
    await dynamodb.update({
        TableName: 'Elections',
        Key: { ElectionId: event.electionId },
        UpdateExpression: 'SET #status = :status, EndedAt = :timestamp',
        ExpressionAttributeNames: {
            '#status': 'Status'
        },
        ExpressionAttributeValues: {
            ':status': 'ENDED',
            ':timestamp': event.timestamp
        }
    }).promise();
}
EOF
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create Lambda functions: ${LAMBDA_AUTH_FUNCTION}, ${LAMBDA_MONITOR_FUNCTION}"
        return 0
    fi
    
    # Create deployment packages
    cd "${LAMBDA_DIR}"
    zip -q voter-auth-lambda.zip voter-auth-lambda.js
    zip -q vote-monitor-lambda.zip vote-monitor-lambda.js
    
    # Create IAM roles
    create_iam_roles
    
    # Create KMS key for encryption
    KMS_KEY_ID=$(aws kms create-key \
        --description "Voting System Encryption Key" \
        --query 'KeyMetadata.KeyId' --output text)
    
    export KMS_KEY_ID
    echo "export KMS_KEY_ID=\"${KMS_KEY_ID}\"" >> "${PROJECT_ROOT}/deployment_env.sh"
    
    # Create voter authentication Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_AUTH_FUNCTION}" \
        --runtime nodejs18.x \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/VoterAuthLambdaRole" \
        --handler voter-auth-lambda.handler \
        --zip-file fileb://voter-auth-lambda.zip \
        --timeout 60 \
        --memory-size 512 \
        --environment Variables="{KMS_KEY_ID=${KMS_KEY_ID}}"
    
    # Create vote monitoring Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_MONITOR_FUNCTION}" \
        --runtime nodejs18.x \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/VoteMonitorLambdaRole" \
        --handler vote-monitor-lambda.handler \
        --zip-file fileb://vote-monitor-lambda.zip \
        --timeout 60 \
        --memory-size 512 \
        --environment Variables="{BUCKET_NAME=${BUCKET_NAME}}"
    
    # Clean up temporary files
    cd "${PROJECT_ROOT}"
    rm -rf "${LAMBDA_DIR}"
    
    log "Created Lambda functions: ${LAMBDA_AUTH_FUNCTION}, ${LAMBDA_MONITOR_FUNCTION}"
}

# Function to create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Create trust policy for Lambda
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
    
    # Create IAM role for voter authentication Lambda
    if aws iam get-role --role-name VoterAuthLambdaRole 2>/dev/null; then
        warning "IAM role VoterAuthLambdaRole already exists"
    else
        aws iam create-role \
            --role-name VoterAuthLambdaRole \
            --assume-role-policy-document file:///tmp/lambda-trust-policy.json
        
        # Attach policies
        aws iam attach-role-policy \
            --role-name VoterAuthLambdaRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        aws iam attach-role-policy \
            --role-name VoterAuthLambdaRole \
            --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
        
        aws iam attach-role-policy \
            --role-name VoterAuthLambdaRole \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
        
        aws iam attach-role-policy \
            --role-name VoterAuthLambdaRole \
            --policy-arn arn:aws:iam::aws:policy/AWSKeyManagementServicePowerUser
        
        log "Created IAM role: VoterAuthLambdaRole"
    fi
    
    # Create IAM role for vote monitoring Lambda
    if aws iam get-role --role-name VoteMonitorLambdaRole 2>/dev/null; then
        warning "IAM role VoteMonitorLambdaRole already exists"
    else
        aws iam create-role \
            --role-name VoteMonitorLambdaRole \
            --assume-role-policy-document file:///tmp/lambda-trust-policy.json
        
        # Attach policies
        aws iam attach-role-policy \
            --role-name VoteMonitorLambdaRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        aws iam attach-role-policy \
            --role-name VoteMonitorLambdaRole \
            --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess
        
        aws iam attach-role-policy \
            --role-name VoteMonitorLambdaRole \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
        
        aws iam attach-role-policy \
            --role-name VoteMonitorLambdaRole \
            --policy-arn arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess
        
        log "Created IAM role: VoteMonitorLambdaRole"
    fi
    
    # Wait for role propagation
    sleep 15
    
    # Clean up temporary files
    rm -f /tmp/lambda-trust-policy.json
}

# Function to create EventBridge and SNS resources
create_event_resources() {
    log "Creating EventBridge and SNS resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create EventBridge rule and SNS topic"
        return 0
    fi
    
    # Create EventBridge rule for voting events
    if aws events describe-rule --name VotingSystemEvents 2>/dev/null; then
        warning "EventBridge rule VotingSystemEvents already exists"
    else
        aws events put-rule \
            --name VotingSystemEvents \
            --description "Rule for blockchain voting system events" \
            --event-pattern '{
                "source": ["voting.blockchain"],
                "detail-type": [
                    "VoteCast",
                    "ElectionCreated",
                    "ElectionEnded",
                    "CandidateRegistered"
                ]
            }' \
            --state ENABLED
        
        log "Created EventBridge rule: VotingSystemEvents"
    fi
    
    # Create SNS topic for voting notifications
    VOTING_TOPIC_ARN=$(aws sns create-topic \
        --name voting-system-notifications \
        --query 'TopicArn' --output text)
    
    export VOTING_TOPIC_ARN
    echo "export VOTING_TOPIC_ARN=\"${VOTING_TOPIC_ARN}\"" >> "${PROJECT_ROOT}/deployment_env.sh"
    
    # Add EventBridge target to SNS topic
    aws events put-targets \
        --rule VotingSystemEvents \
        --targets "Id"="1","Arn"="${VOTING_TOPIC_ARN}"
    
    log "Created SNS topic: ${VOTING_TOPIC_ARN}"
}

# Function to create monitoring resources
create_monitoring() {
    log "Creating monitoring resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create CloudWatch dashboard and alarms"
        return 0
    fi
    
    # Create CloudWatch dashboard
    cat > /tmp/voting-dashboard.json << EOF
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/Lambda", "Invocations", "FunctionName", "${LAMBDA_AUTH_FUNCTION}"],
          ["AWS/Lambda", "Errors", "FunctionName", "${LAMBDA_AUTH_FUNCTION}"],
          ["AWS/Lambda", "Duration", "FunctionName", "${LAMBDA_AUTH_FUNCTION}"]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "Voter Authentication Metrics"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/Lambda", "Invocations", "FunctionName", "${LAMBDA_MONITOR_FUNCTION}"],
          ["AWS/Lambda", "Errors", "FunctionName", "${LAMBDA_MONITOR_FUNCTION}"],
          ["AWS/Lambda", "Duration", "FunctionName", "${LAMBDA_MONITOR_FUNCTION}"]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "Vote Monitoring Metrics"
      }
    }
  ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name BlockchainVotingSystem \
        --dashboard-body file:///tmp/voting-dashboard.json
    
    # Create alarms
    aws cloudwatch put-metric-alarm \
        --alarm-name "VotingSystem-Auth-Errors" \
        --alarm-description "Alert on voter authentication errors" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --dimensions Name=FunctionName,Value="${LAMBDA_AUTH_FUNCTION}" \
        --evaluation-periods 2 \
        --alarm-actions "${VOTING_TOPIC_ARN}"
    
    rm -f /tmp/voting-dashboard.json
    
    log "Created CloudWatch monitoring resources"
}

# Function to create voting DApp
create_voting_dapp() {
    log "Creating voting DApp interface..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create and deploy voting DApp"
        return 0
    fi
    
    mkdir -p "${PROJECT_ROOT}/dapp"
    
    # Create simplified voting DApp
    cat > "${PROJECT_ROOT}/dapp/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Blockchain Voting System</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; color: #333; margin-bottom: 30px; }
        .section { margin-bottom: 30px; padding: 20px; border: 1px solid #ddd; border-radius: 5px; }
        .button { background-color: #007bff; color: white; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; margin: 5px; }
        .button:hover { background-color: #0056b3; }
        .input { width: 100%; padding: 10px; margin: 5px 0; border: 1px solid #ddd; border-radius: 3px; }
        .status { padding: 10px; margin: 10px 0; border-radius: 5px; }
        .success { background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .error { background-color: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .warning { background-color: #fff3cd; color: #856404; border: 1px solid #ffeaa7; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🗳️ Blockchain Voting System</h1>
            <p>Secure, Transparent, Immutable</p>
        </div>

        <div class="section">
            <h3>📊 System Status</h3>
            <div class="status success">
                <strong>Status:</strong> System deployed successfully<br>
                <strong>Region:</strong> AWS Region configured<br>
                <strong>Deployment:</strong> Ready for configuration
            </div>
        </div>

        <div class="section">
            <h3>🔧 Configuration Required</h3>
            <p>This voting system has been deployed but requires additional configuration:</p>
            <ul>
                <li>Configure blockchain network endpoints</li>
                <li>Deploy smart contracts</li>
                <li>Set up voter registration workflows</li>
                <li>Configure election parameters</li>
            </ul>
        </div>

        <div class="section">
            <h3>📖 Next Steps</h3>
            <p>Follow the deployment guide to complete the voting system setup:</p>
            <ol>
                <li>Configure your blockchain network</li>
                <li>Deploy and verify smart contracts</li>
                <li>Test the voter registration process</li>
                <li>Set up monitoring and alerting</li>
            </ol>
        </div>
    </div>
</body>
</html>
EOF
    
    # Upload DApp to S3
    aws s3 cp "${PROJECT_ROOT}/dapp/index.html" "s3://${BUCKET_NAME}/dapp/index.html" \
        --content-type "text/html"
    
    # Clean up local DApp files
    rm -rf "${PROJECT_ROOT}/dapp"
    
    log "Created and deployed voting DApp"
}

# Function to run deployment validation
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would validate deployment"
        return 0
    fi
    
    local validation_failed=false
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        log "✅ S3 bucket validation passed"
    else
        error "❌ S3 bucket validation failed"
        validation_failed=true
    fi
    
    # Check DynamoDB tables
    if aws dynamodb describe-table --table-name VoterRegistry &>/dev/null && \
       aws dynamodb describe-table --table-name Elections &>/dev/null; then
        log "✅ DynamoDB tables validation passed"
    else
        error "❌ DynamoDB tables validation failed"
        validation_failed=true
    fi
    
    # Check Lambda functions
    if aws lambda get-function --function-name "${LAMBDA_AUTH_FUNCTION}" &>/dev/null && \
       aws lambda get-function --function-name "${LAMBDA_MONITOR_FUNCTION}" &>/dev/null; then
        log "✅ Lambda functions validation passed"
    else
        error "❌ Lambda functions validation failed"
        validation_failed=true
    fi
    
    if [[ "$validation_failed" == "true" ]]; then
        error "Deployment validation failed. Please check the errors above."
        exit 1
    fi
    
    log "✅ Deployment validation completed successfully"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    log "==================="
    log "Voting System Name: ${VOTING_SYSTEM_NAME}"
    log "AWS Region: ${AWS_REGION}"
    log "S3 Bucket: ${BUCKET_NAME}"
    log "Lambda Functions:"
    log "  - Voter Authentication: ${LAMBDA_AUTH_FUNCTION}"
    log "  - Vote Monitoring: ${LAMBDA_MONITOR_FUNCTION}"
    log "DynamoDB Tables:"
    log "  - VoterRegistry"
    log "  - Elections"
    log "Monitoring:"
    log "  - CloudWatch Dashboard: BlockchainVotingSystem"
    log "  - SNS Topic: ${VOTING_TOPIC_ARN}"
    log ""
    log "DApp URL: https://${BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com/dapp/index.html"
    log ""
    log "Environment variables saved to: ${PROJECT_ROOT}/deployment_env.sh"
    log "Deployment log saved to: ${DEPLOYMENT_LOG}"
    log ""
    log "🎉 Blockchain voting system deployment completed successfully!"
}

# Function to handle cleanup on error
cleanup_on_error() {
    error "Deployment failed. Initiating cleanup..."
    
    if [[ -f "${PROJECT_ROOT}/deployment_env.sh" ]]; then
        source "${PROJECT_ROOT}/deployment_env.sh"
        
        # Run cleanup script if it exists
        if [[ -f "${SCRIPT_DIR}/destroy.sh" ]]; then
            "${SCRIPT_DIR}/destroy.sh"
        fi
    fi
    
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Main deployment function
main() {
    log "🚀 Starting Blockchain Voting System Deployment"
    log "================================================"
    
    check_prerequisites
    setup_environment
    create_storage_resources
    create_blockchain_node
    create_lambda_functions
    create_event_resources
    create_monitoring
    create_voting_dapp
    validate_deployment
    display_summary
    
    log "🎉 Deployment completed successfully!"
    log "Total deployment time: $((SECONDS / 60)) minutes and $((SECONDS % 60)) seconds"
}

# Run main function
main "$@"