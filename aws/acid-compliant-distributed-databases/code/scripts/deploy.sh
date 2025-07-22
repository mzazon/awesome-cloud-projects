#!/bin/bash

# Amazon QLDB Deployment Script
# Building ACID-Compliant Distributed Databases with Amazon QLDB
# Author: DevOps Engineer
# Version: 1.0

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI version 2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    info "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set appropriate environment variables."
        exit 1
    fi
    
    # Get and display current AWS identity
    CALLER_IDENTITY=$(aws sts get-caller-identity)
    AWS_ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account')
    AWS_USER_ARN=$(echo "$CALLER_IDENTITY" | jq -r '.Arn')
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    info "AWS User/Role: $AWS_USER_ARN"
    
    # Check required permissions (basic check)
    info "Checking basic AWS permissions..."
    if ! aws qldb list-ledgers &> /dev/null; then
        error "Insufficient permissions for QLDB operations. Please ensure you have QLDB permissions."
        exit 1
    fi
    
    log "Prerequisites check completed successfully."
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "No default region configured, using us-east-1"
    fi
    info "AWS Region: $AWS_REGION"
    
    # Get AWS Account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export LEDGER_NAME="financial-ledger-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="qldb-stream-role-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="qldb-exports-${RANDOM_SUFFIX}"
    export KINESIS_STREAM_NAME="qldb-journal-stream-${RANDOM_SUFFIX}"
    
    # Create deployment state file
    STATE_FILE="deployment-state.json"
    cat > "$STATE_FILE" << EOF
{
    "ledger_name": "$LEDGER_NAME",
    "iam_role_name": "$IAM_ROLE_NAME",
    "s3_bucket_name": "$S3_BUCKET_NAME",
    "kinesis_stream_name": "$KINESIS_STREAM_NAME",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    info "Resource names:"
    info "  Ledger: $LEDGER_NAME"
    info "  IAM Role: $IAM_ROLE_NAME"
    info "  S3 Bucket: $S3_BUCKET_NAME"
    info "  Kinesis Stream: $KINESIS_STREAM_NAME"
    
    log "Environment setup completed."
}

# Function to create S3 bucket and Kinesis stream
create_foundational_resources() {
    log "Creating foundational resources..."
    
    # Create S3 bucket for journal exports
    info "Creating S3 bucket: $S3_BUCKET_NAME"
    if aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION} 2>/dev/null; then
        info "S3 bucket created successfully"
    else
        warn "S3 bucket creation failed, it may already exist"
        # Check if bucket exists and is accessible
        if aws s3 ls s3://${S3_BUCKET_NAME} &> /dev/null; then
            info "S3 bucket already exists and is accessible"
        else
            error "Failed to create or access S3 bucket"
            exit 1
        fi
    fi
    
    # Create Kinesis stream for real-time journal streaming
    info "Creating Kinesis stream: $KINESIS_STREAM_NAME"
    if aws kinesis create-stream \
        --stream-name ${KINESIS_STREAM_NAME} \
        --shard-count 1 2>/dev/null; then
        info "Kinesis stream creation initiated"
    else
        warn "Kinesis stream creation failed, it may already exist"
    fi
    
    # Wait for Kinesis stream to be active
    info "Waiting for Kinesis stream to be active..."
    local max_attempts=30
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        STREAM_STATUS=$(aws kinesis describe-stream \
            --stream-name ${KINESIS_STREAM_NAME} \
            --query 'StreamDescription.StreamStatus' \
            --output text 2>/dev/null || echo "UNKNOWN")
        
        if [ "$STREAM_STATUS" = "ACTIVE" ]; then
            info "Kinesis stream is now active"
            break
        elif [ "$STREAM_STATUS" = "CREATING" ]; then
            info "Kinesis stream is still being created... (attempt $attempt/$max_attempts)"
            sleep 10
            ((attempt++))
        else
            error "Unexpected Kinesis stream status: $STREAM_STATUS"
            exit 1
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        error "Kinesis stream did not become active within expected time"
        exit 1
    fi
    
    log "Foundational resources created successfully."
}

# Function to create IAM role for QLDB operations
create_iam_role() {
    log "Creating IAM role for QLDB operations..."
    
    # Create trust policy for QLDB
    cat > qldb-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "qldb.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    info "Creating IAM role: $IAM_ROLE_NAME"
    if aws iam create-role \
        --role-name ${IAM_ROLE_NAME} \
        --assume-role-policy-document file://qldb-trust-policy.json 2>/dev/null; then
        info "IAM role created successfully"
    else
        warn "IAM role creation failed, it may already exist"
    fi
    
    # Create policy for S3 and Kinesis access
    cat > qldb-permissions-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${S3_BUCKET_NAME}",
                "arn:aws:s3:::${S3_BUCKET_NAME}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "kinesis:PutRecord",
                "kinesis:PutRecords",
                "kinesis:DescribeStream"
            ],
            "Resource": "arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/${KINESIS_STREAM_NAME}"
        }
    ]
}
EOF
    
    # Attach policy to role
    info "Attaching permissions policy to IAM role"
    if aws iam put-role-policy \
        --role-name ${IAM_ROLE_NAME} \
        --policy-name QLDBStreamPolicy \
        --policy-document file://qldb-permissions-policy.json; then
        info "IAM policy attached successfully"
    else
        error "Failed to attach IAM policy"
        exit 1
    fi
    
    # Wait for IAM role to be ready
    info "Waiting for IAM role to be ready..."
    sleep 10
    
    log "IAM role created successfully."
}

# Function to create QLDB ledger
create_qldb_ledger() {
    log "Creating QLDB ledger..."
    
    # Create QLDB ledger with standard permissions mode
    info "Creating QLDB ledger: $LEDGER_NAME"
    if aws qldb create-ledger \
        --name ${LEDGER_NAME} \
        --permissions-mode STANDARD \
        --deletion-protection \
        --tags Environment=Production,Application=Financial 2>/dev/null; then
        info "QLDB ledger creation initiated"
    else
        warn "QLDB ledger creation failed, it may already exist"
    fi
    
    # Wait for ledger to be active
    info "Waiting for ledger to be active..."
    local max_attempts=30
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        LEDGER_STATE=$(aws qldb describe-ledger \
            --name ${LEDGER_NAME} \
            --query 'State' --output text 2>/dev/null || echo "UNKNOWN")
        
        if [ "$LEDGER_STATE" = "ACTIVE" ]; then
            info "QLDB ledger is now active"
            break
        elif [ "$LEDGER_STATE" = "CREATING" ]; then
            info "QLDB ledger is still being created... (attempt $attempt/$max_attempts)"
            sleep 10
            ((attempt++))
        else
            error "Unexpected QLDB ledger state: $LEDGER_STATE"
            exit 1
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        error "QLDB ledger did not become active within expected time"
        exit 1
    fi
    
    # Get and display ledger details
    aws qldb describe-ledger --name ${LEDGER_NAME}
    
    log "QLDB ledger created successfully."
}

# Function to setup journal streaming
setup_journal_streaming() {
    log "Setting up journal streaming to Kinesis..."
    
    # Get IAM role ARN
    ROLE_ARN=$(aws iam get-role \
        --role-name ${IAM_ROLE_NAME} \
        --query 'Role.Arn' --output text)
    
    # Get Kinesis stream ARN
    KINESIS_ARN=$(aws kinesis describe-stream \
        --stream-name ${KINESIS_STREAM_NAME} \
        --query 'StreamDescription.StreamARN' --output text)
    
    # Create Kinesis configuration
    cat > kinesis-config.json << EOF
{
    "StreamArn": "${KINESIS_ARN}",
    "AggregationEnabled": true
}
EOF
    
    # Start journal streaming
    info "Starting journal streaming"
    STREAM_ID=$(aws qldb stream-journal-to-kinesis \
        --ledger-name ${LEDGER_NAME} \
        --role-arn ${ROLE_ARN} \
        --kinesis-configuration file://kinesis-config.json \
        --stream-name ${LEDGER_NAME}-journal-stream \
        --inclusive-start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
        --query 'StreamId' --output text 2>/dev/null || echo "FAILED")
    
    if [ "$STREAM_ID" != "FAILED" ]; then
        info "Journal streaming started with Stream ID: $STREAM_ID"
        
        # Save stream ID to state file
        jq --arg stream_id "$STREAM_ID" '.stream_id = $stream_id' "$STATE_FILE" > tmp.json && mv tmp.json "$STATE_FILE"
    else
        warn "Failed to start journal streaming"
    fi
    
    log "Journal streaming setup completed."
}

# Function to generate cryptographic digest
generate_digest() {
    log "Generating cryptographic digest..."
    
    # Request a digest from the ledger
    info "Requesting digest from QLDB ledger"
    DIGEST_OUTPUT=$(aws qldb get-digest --name ${LEDGER_NAME} 2>/dev/null || echo "{}")
    
    if [ "$DIGEST_OUTPUT" != "{}" ]; then
        # Extract digest and tip address
        DIGEST=$(echo ${DIGEST_OUTPUT} | jq -r '.Digest // "N/A"')
        DIGEST_TIP=$(echo ${DIGEST_OUTPUT} | jq -r '.DigestTipAddress.IonText // "N/A"')
        
        info "Digest: $DIGEST"
        info "Digest Tip Address: $DIGEST_TIP"
        
        # Save digest information
        echo ${DIGEST_OUTPUT} > current-digest.json
        info "Digest saved to current-digest.json"
    else
        warn "Failed to generate cryptographic digest"
    fi
    
    log "Cryptographic digest generation completed."
}

# Function to create sample data files
create_sample_data() {
    log "Creating sample data files..."
    
    # Create sample accounts data
    cat > accounts.json << EOF
[
    {
        "accountId": "ACC-001",
        "accountNumber": "1234567890",
        "accountType": "CHECKING",
        "balance": 10000.00,
        "currency": "USD",
        "customerId": "CUST-001",
        "createdAt": "2024-01-01T00:00:00Z",
        "status": "ACTIVE"
    },
    {
        "accountId": "ACC-002",
        "accountNumber": "0987654321",
        "accountType": "SAVINGS",
        "balance": 25000.00,
        "currency": "USD",
        "customerId": "CUST-002",
        "createdAt": "2024-01-01T00:00:00Z",
        "status": "ACTIVE"
    }
]
EOF
    
    # Create sample transactions data
    cat > transactions.json << EOF
[
    {
        "transactionId": "TXN-001",
        "fromAccountId": "ACC-001",
        "toAccountId": "ACC-002",
        "amount": 500.00,
        "currency": "USD",
        "transactionType": "TRANSFER",
        "timestamp": "2024-01-15T10:30:00Z",
        "description": "Monthly transfer",
        "status": "COMPLETED"
    },
    {
        "transactionId": "TXN-002",
        "fromAccountId": "ACC-002",
        "toAccountId": "ACC-001",
        "amount": 1000.00,
        "currency": "USD",
        "transactionType": "TRANSFER",
        "timestamp": "2024-01-20T14:15:00Z",
        "description": "Loan payment",
        "status": "COMPLETED"
    }
]
EOF
    
    # Create PartiQL script for table creation
    cat > create-tables.sql << EOF
CREATE TABLE Accounts;
CREATE TABLE Transactions;
CREATE TABLE AuditLog;

CREATE INDEX ON Accounts (accountId);
CREATE INDEX ON Transactions (transactionId);
CREATE INDEX ON Transactions (fromAccountId);
CREATE INDEX ON Transactions (toAccountId);
CREATE INDEX ON AuditLog (timestamp);
EOF
    
    # Create audit query scripts
    cat > audit-queries.sql << EOF
-- Query all transactions for a specific account
SELECT * FROM Transactions 
WHERE fromAccountId = 'ACC-001' OR toAccountId = 'ACC-001';

-- Query transactions within a date range
SELECT * FROM Transactions 
WHERE timestamp BETWEEN '2024-01-01T00:00:00Z' AND '2024-01-31T23:59:59Z';

-- Query account balance history
SELECT accountId, balance, metadata.txTime 
FROM history(Accounts) AS a
WHERE a.data.accountId = 'ACC-001';

-- Query transaction history with metadata
SELECT t.*, metadata.txTime, metadata.txId
FROM history(Transactions) AS t
WHERE t.data.transactionId = 'TXN-001';
EOF
    
    info "Sample data files created:"
    info "  - accounts.json"
    info "  - transactions.json"
    info "  - create-tables.sql"
    info "  - audit-queries.sql"
    
    log "Sample data creation completed."
}

# Function to export journal data to S3
export_journal_to_s3() {
    log "Exporting journal data to S3..."
    
    # Get IAM role ARN
    ROLE_ARN=$(aws iam get-role \
        --role-name ${IAM_ROLE_NAME} \
        --query 'Role.Arn' --output text)
    
    # Create S3 export configuration
    cat > s3-export-config.json << EOF
{
    "Bucket": "${S3_BUCKET_NAME}",
    "Prefix": "journal-exports/",
    "EncryptionConfiguration": {
        "ObjectEncryptionType": "SSE_S3"
    }
}
EOF
    
    # Start journal export
    info "Starting journal export to S3"
    EXPORT_ID=$(aws qldb export-journal-to-s3 \
        --name ${LEDGER_NAME} \
        --inclusive-start-time $(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ) \
        --exclusive-end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
        --role-arn ${ROLE_ARN} \
        --s3-export-configuration file://s3-export-config.json \
        --query 'ExportId' --output text 2>/dev/null || echo "FAILED")
    
    if [ "$EXPORT_ID" != "FAILED" ]; then
        info "Journal export started with Export ID: $EXPORT_ID"
        
        # Save export ID to state file
        jq --arg export_id "$EXPORT_ID" '.export_id = $export_id' "$STATE_FILE" > tmp.json && mv tmp.json "$STATE_FILE"
    else
        warn "Failed to start journal export"
    fi
    
    log "Journal export setup completed."
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check ledger status
    info "Validating QLDB ledger status"
    LEDGER_STATUS=$(aws qldb describe-ledger \
        --name ${LEDGER_NAME} \
        --query 'State' --output text 2>/dev/null || echo "UNKNOWN")
    
    if [ "$LEDGER_STATUS" = "ACTIVE" ]; then
        info "✅ QLDB ledger is active"
    else
        warn "❌ QLDB ledger status: $LEDGER_STATUS"
    fi
    
    # Check IAM role
    info "Validating IAM role"
    if aws iam get-role --role-name ${IAM_ROLE_NAME} &> /dev/null; then
        info "✅ IAM role exists"
    else
        warn "❌ IAM role not found"
    fi
    
    # Check S3 bucket
    info "Validating S3 bucket"
    if aws s3 ls s3://${S3_BUCKET_NAME} &> /dev/null; then
        info "✅ S3 bucket is accessible"
    else
        warn "❌ S3 bucket not accessible"
    fi
    
    # Check Kinesis stream
    info "Validating Kinesis stream"
    KINESIS_STATUS=$(aws kinesis describe-stream \
        --stream-name ${KINESIS_STREAM_NAME} \
        --query 'StreamDescription.StreamStatus' \
        --output text 2>/dev/null || echo "UNKNOWN")
    
    if [ "$KINESIS_STATUS" = "ACTIVE" ]; then
        info "✅ Kinesis stream is active"
    else
        warn "❌ Kinesis stream status: $KINESIS_STATUS"
    fi
    
    # Check journal streaming (if configured)
    if [ -f "$STATE_FILE" ] && jq -e '.stream_id' "$STATE_FILE" &> /dev/null; then
        STREAM_ID=$(jq -r '.stream_id' "$STATE_FILE")
        info "Validating journal streaming"
        STREAM_STATUS=$(aws qldb describe-journal-kinesis-stream \
            --ledger-name ${LEDGER_NAME} \
            --stream-id ${STREAM_ID} \
            --query 'Stream.Status' --output text 2>/dev/null || echo "UNKNOWN")
        
        if [ "$STREAM_STATUS" = "ACTIVE" ]; then
            info "✅ Journal streaming is active"
        else
            warn "❌ Journal streaming status: $STREAM_STATUS"
        fi
    fi
    
    log "Deployment validation completed."
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo ""
    info "AWS Region: $AWS_REGION"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    echo ""
    info "Resources Created:"
    info "  QLDB Ledger: $LEDGER_NAME"
    info "  IAM Role: $IAM_ROLE_NAME"
    info "  S3 Bucket: $S3_BUCKET_NAME"
    info "  Kinesis Stream: $KINESIS_STREAM_NAME"
    echo ""
    
    if [ -f "$STATE_FILE" ]; then
        info "Deployment state saved to: $STATE_FILE"
        if jq -e '.stream_id' "$STATE_FILE" &> /dev/null; then
            STREAM_ID=$(jq -r '.stream_id' "$STATE_FILE")
            info "  Journal Stream ID: $STREAM_ID"
        fi
        if jq -e '.export_id' "$STATE_FILE" &> /dev/null; then
            EXPORT_ID=$(jq -r '.export_id' "$STATE_FILE")
            info "  S3 Export ID: $EXPORT_ID"
        fi
    fi
    
    echo ""
    info "Next Steps:"
    info "  1. Review the created resources in the AWS Console"
    info "  2. Examine sample data files for QLDB usage patterns"
    info "  3. Execute PartiQL queries using the AWS CLI or SDK"
    info "  4. Monitor journal streaming in Kinesis"
    info "  5. Check S3 for exported journal data"
    echo ""
    warn "Remember to clean up resources when done to avoid ongoing charges."
    info "Run './destroy.sh' to clean up all resources."
}

# Main deployment function
main() {
    log "Starting Amazon QLDB deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_foundational_resources
    create_iam_role
    create_qldb_ledger
    setup_journal_streaming
    generate_digest
    create_sample_data
    export_journal_to_s3
    validate_deployment
    display_summary
    
    log "Amazon QLDB deployment completed successfully!"
    echo ""
    info "Total estimated cost for this deployment: \$10-50 for 4 hours of usage"
    warn "Monitor your AWS billing dashboard for actual costs."
}

# Cleanup function for script interruption
cleanup_on_error() {
    error "Deployment interrupted or failed. Cleaning up temporary files..."
    rm -f qldb-trust-policy.json
    rm -f qldb-permissions-policy.json
    rm -f kinesis-config.json
    rm -f s3-export-config.json
    exit 1
}

# Set trap for cleanup on script exit
trap cleanup_on_error ERR INT TERM

# Check if running in dry-run mode
if [ "${1:-}" = "--dry-run" ]; then
    log "DRY RUN MODE - No resources will be created"
    check_prerequisites
    setup_environment
    info "Dry run completed successfully"
    exit 0
fi

# Check for help flag
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Amazon QLDB Deployment Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Run prerequisite checks without creating resources"
    echo "  --help, -h   Show this help message"
    echo ""
    echo "This script deploys a complete Amazon QLDB solution including:"
    echo "  - QLDB Ledger with encryption and deletion protection"
    echo "  - IAM roles for streaming and export operations"
    echo "  - S3 bucket for journal exports"
    echo "  - Kinesis stream for real-time journal streaming"
    echo "  - Sample data files and query examples"
    echo ""
    echo "Prerequisites:"
    echo "  - AWS CLI v2 installed and configured"
    echo "  - jq installed for JSON processing"
    echo "  - Appropriate AWS permissions for QLDB, IAM, S3, and Kinesis"
    echo ""
    exit 0
fi

# Run main deployment
main "$@"