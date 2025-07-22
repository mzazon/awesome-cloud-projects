#!/bin/bash

# ACID-Compliant Distributed Databases with Amazon QLDB - Deployment Script
# This script deploys the complete QLDB infrastructure including ledger, IAM roles, 
# S3 bucket, Kinesis stream, and sets up journal streaming

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=${DRY_RUN:-false}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

error() {
    log "${RED}ERROR: $1${NC}" >&2
    exit 1
}

warn() {
    log "${YELLOW}WARNING: $1${NC}"
}

info() {
    log "${BLUE}INFO: $1${NC}"
}

success() {
    log "${GREEN}SUCCESS: $1${NC}"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy ACID-compliant distributed database infrastructure using Amazon QLDB

OPTIONS:
    -r, --region REGION     AWS region (default: from AWS config)
    -p, --prefix PREFIX     Resource name prefix (default: qldb-demo)
    -d, --dry-run          Show what would be deployed without executing
    -h, --help             Show this help message
    -v, --verbose          Enable verbose logging

ENVIRONMENT VARIABLES:
    DRY_RUN                Set to 'true' for dry run mode
    AWS_REGION             Override AWS region
    RESOURCE_PREFIX        Override resource prefix

EXAMPLES:
    $0                      # Deploy with defaults
    $0 --region us-west-2   # Deploy in specific region
    $0 --prefix my-qldb     # Deploy with custom prefix
    $0 --dry-run            # Show what would be deployed

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -p|--prefix)
                RESOURCE_PREFIX="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2"
    fi

    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION" | cut -d. -f1) -lt 2 ]]; then
        warn "AWS CLI v1 detected. AWS CLI v2 is recommended"
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first"
    fi

    # Check jq availability
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Some features may not work correctly"
    fi

    # Check required permissions
    info "Checking AWS permissions..."
    local required_services=("qldb" "iam" "s3" "kinesis")
    for service in "${required_services[@]}"; do
        case $service in
            qldb)
                if ! aws qldb list-ledgers &> /dev/null; then
                    error "Missing QLDB permissions. Ensure you have qldb:* permissions"
                fi
                ;;
            iam)
                if ! aws iam list-roles --max-items 1 &> /dev/null; then
                    error "Missing IAM permissions. Ensure you have iam:* permissions"
                fi
                ;;
            s3)
                if ! aws s3 ls &> /dev/null; then
                    error "Missing S3 permissions. Ensure you have s3:* permissions"
                fi
                ;;
            kinesis)
                if ! aws kinesis list-streams &> /dev/null; then
                    error "Missing Kinesis permissions. Ensure you have kinesis:* permissions"
                fi
                ;;
        esac
    done

    success "Prerequisites check completed"
}

# Set environment variables
set_environment() {
    info "Setting up environment variables..."

    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "${AWS_REGION}" ]]; then
        error "AWS region not set. Use --region option or configure AWS CLI"
    fi

    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    # Set resource prefix
    export RESOURCE_PREFIX=${RESOURCE_PREFIX:-"qldb-demo"}

    # Generate unique suffix
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

    # Set resource names
    export LEDGER_NAME="${RESOURCE_PREFIX}-ledger-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="${RESOURCE_PREFIX}-stream-role-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="${RESOURCE_PREFIX}-exports-${RANDOM_SUFFIX}"
    export KINESIS_STREAM_NAME="${RESOURCE_PREFIX}-journal-stream-${RANDOM_SUFFIX}"

    # Save environment to file for destroy script
    cat > "${SCRIPT_DIR}/environment.sh" << EOF
# Environment variables for QLDB deployment
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export RESOURCE_PREFIX="${RESOURCE_PREFIX}"
export LEDGER_NAME="${LEDGER_NAME}"
export IAM_ROLE_NAME="${IAM_ROLE_NAME}"
export S3_BUCKET_NAME="${S3_BUCKET_NAME}"
export KINESIS_STREAM_NAME="${KINESIS_STREAM_NAME}"
EOF

    info "Environment configured:"
    info "  AWS Region: ${AWS_REGION}"
    info "  AWS Account: ${AWS_ACCOUNT_ID}"
    info "  Ledger Name: ${LEDGER_NAME}"
    info "  S3 Bucket: ${S3_BUCKET_NAME}"
    info "  Kinesis Stream: ${KINESIS_STREAM_NAME}"
}

# Execute command with dry run support
execute() {
    local cmd="$1"
    local description="$2"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would execute: ${description}"
        info "[DRY RUN] Command: ${cmd}"
        return 0
    else
        info "Executing: ${description}"
        eval "${cmd}"
    fi
}

# Create S3 bucket
create_s3_bucket() {
    info "Creating S3 bucket for journal exports..."
    
    # Check if bucket already exists
    if aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
        warn "S3 bucket ${S3_BUCKET_NAME} already exists"
        return 0
    fi

    local create_cmd="aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION}"
    execute "${create_cmd}" "Create S3 bucket ${S3_BUCKET_NAME}"

    # Enable versioning
    local versioning_cmd="aws s3api put-bucket-versioning --bucket ${S3_BUCKET_NAME} --versioning-configuration Status=Enabled"
    execute "${versioning_cmd}" "Enable S3 bucket versioning"

    # Enable server-side encryption
    local encryption_cmd="aws s3api put-bucket-encryption --bucket ${S3_BUCKET_NAME} --server-side-encryption-configuration '{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"AES256\"}}]}'"
    execute "${encryption_cmd}" "Enable S3 bucket encryption"

    success "S3 bucket created and configured"
}

# Create Kinesis stream
create_kinesis_stream() {
    info "Creating Kinesis stream for journal streaming..."

    # Check if stream already exists
    if aws kinesis describe-stream --stream-name "${KINESIS_STREAM_NAME}" &> /dev/null; then
        warn "Kinesis stream ${KINESIS_STREAM_NAME} already exists"
        return 0
    fi

    local create_cmd="aws kinesis create-stream --stream-name ${KINESIS_STREAM_NAME} --shard-count 1"
    execute "${create_cmd}" "Create Kinesis stream ${KINESIS_STREAM_NAME}"

    if [[ "${DRY_RUN}" != "true" ]]; then
        info "Waiting for Kinesis stream to be active..."
        aws kinesis wait stream-exists --stream-name "${KINESIS_STREAM_NAME}"
        success "Kinesis stream is active"
    fi
}

# Create IAM role
create_iam_role() {
    info "Creating IAM role for QLDB operations..."

    # Check if role already exists
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        warn "IAM role ${IAM_ROLE_NAME} already exists"
        return 0
    fi

    # Create trust policy
    cat > "${SCRIPT_DIR}/qldb-trust-policy.json" << EOF
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

    local create_role_cmd="aws iam create-role --role-name ${IAM_ROLE_NAME} --assume-role-policy-document file://${SCRIPT_DIR}/qldb-trust-policy.json"
    execute "${create_role_cmd}" "Create IAM role ${IAM_ROLE_NAME}"

    # Create permissions policy
    cat > "${SCRIPT_DIR}/qldb-permissions-policy.json" << EOF
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

    local attach_policy_cmd="aws iam put-role-policy --role-name ${IAM_ROLE_NAME} --policy-name QLDBStreamPolicy --policy-document file://${SCRIPT_DIR}/qldb-permissions-policy.json"
    execute "${attach_policy_cmd}" "Attach policy to IAM role"

    success "IAM role created and configured"
}

# Create QLDB ledger
create_qldb_ledger() {
    info "Creating QLDB ledger..."

    # Check if ledger already exists
    if aws qldb describe-ledger --name "${LEDGER_NAME}" &> /dev/null; then
        warn "QLDB ledger ${LEDGER_NAME} already exists"
        return 0
    fi

    local create_cmd="aws qldb create-ledger --name ${LEDGER_NAME} --permissions-mode STANDARD --deletion-protection --tags Environment=Production,Application=Financial,ManagedBy=DeployScript"
    execute "${create_cmd}" "Create QLDB ledger ${LEDGER_NAME}"

    if [[ "${DRY_RUN}" != "true" ]]; then
        info "Waiting for ledger to be active..."
        local max_attempts=30
        local attempt=0
        
        while [[ $attempt -lt $max_attempts ]]; do
            local state=$(aws qldb describe-ledger --name "${LEDGER_NAME}" --query 'State' --output text)
            if [[ "$state" == "ACTIVE" ]]; then
                success "QLDB ledger is active"
                return 0
            fi
            info "Ledger state: ${state}, waiting..."
            sleep 10
            ((attempt++))
        done
        
        error "Ledger failed to become active within expected time"
    fi
}

# Setup journal streaming
setup_journal_streaming() {
    info "Setting up journal streaming to Kinesis..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would setup journal streaming"
        return 0
    fi

    # Get IAM role ARN
    local role_arn=$(aws iam get-role --role-name "${IAM_ROLE_NAME}" --query 'Role.Arn' --output text)
    
    # Get Kinesis stream ARN
    local kinesis_arn=$(aws kinesis describe-stream --stream-name "${KINESIS_STREAM_NAME}" --query 'StreamDescription.StreamARN' --output text)

    # Create Kinesis configuration
    cat > "${SCRIPT_DIR}/kinesis-config.json" << EOF
{
    "StreamArn": "${kinesis_arn}",
    "AggregationEnabled": true
}
EOF

    # Start journal streaming
    local stream_cmd="aws qldb stream-journal-to-kinesis --ledger-name ${LEDGER_NAME} --role-arn ${role_arn} --kinesis-configuration file://${SCRIPT_DIR}/kinesis-config.json --stream-name ${LEDGER_NAME}-journal-stream --inclusive-start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)"
    
    local stream_id=$(eval "${stream_cmd}" --query 'StreamId' --output text)
    
    # Save stream ID for cleanup
    echo "export STREAM_ID=\"${stream_id}\"" >> "${SCRIPT_DIR}/environment.sh"
    
    success "Journal streaming configured with Stream ID: ${stream_id}"
}

# Create sample data files
create_sample_data() {
    info "Creating sample data files..."

    # Create accounts sample data
    cat > "${SCRIPT_DIR}/accounts.json" << EOF
[
    {
        "accountId": "ACC-001",
        "accountNumber": "1234567890",
        "accountType": "CHECKING",
        "balance": 10000.00,
        "currency": "USD",
        "customerId": "CUST-001",
        "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "status": "ACTIVE"
    },
    {
        "accountId": "ACC-002",
        "accountNumber": "0987654321",
        "accountType": "SAVINGS",
        "balance": 25000.00,
        "currency": "USD",
        "customerId": "CUST-002",
        "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "status": "ACTIVE"
    }
]
EOF

    # Create transactions sample data
    cat > "${SCRIPT_DIR}/transactions.json" << EOF
[
    {
        "transactionId": "TXN-001",
        "fromAccountId": "ACC-001",
        "toAccountId": "ACC-002",
        "amount": 500.00,
        "currency": "USD",
        "transactionType": "TRANSFER",
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
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
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "description": "Loan payment",
        "status": "COMPLETED"
    }
]
EOF

    # Create audit queries
    cat > "${SCRIPT_DIR}/audit-queries.sql" << EOF
-- Query all transactions for a specific account
SELECT * FROM Transactions 
WHERE fromAccountId = 'ACC-001' OR toAccountId = 'ACC-001';

-- Query transactions within a date range
SELECT * FROM Transactions 
WHERE timestamp BETWEEN '2024-01-01T00:00:00Z' AND '2024-12-31T23:59:59Z';

-- Query account balance history
SELECT accountId, balance, metadata.txTime 
FROM history(Accounts) AS a
WHERE a.data.accountId = 'ACC-001';

-- Query transaction history with metadata
SELECT t.*, metadata.txTime, metadata.txId
FROM history(Transactions) AS t
WHERE t.data.transactionId = 'TXN-001';
EOF

    success "Sample data files created"
}

# Generate deployment summary
generate_summary() {
    info "Generating deployment summary..."

    cat > "${SCRIPT_DIR}/deployment-summary.txt" << EOF
QLDB Deployment Summary
======================

Deployment Date: $(date)
AWS Region: ${AWS_REGION}
AWS Account: ${AWS_ACCOUNT_ID}

Resources Created:
- QLDB Ledger: ${LEDGER_NAME}
- S3 Bucket: ${S3_BUCKET_NAME}
- Kinesis Stream: ${KINESIS_STREAM_NAME}
- IAM Role: ${IAM_ROLE_NAME}

Next Steps:
1. Access the QLDB ledger using AWS Console or CLI
2. Create tables and insert data using PartiQL
3. Monitor journal streaming in Kinesis
4. Export journal data to S3 for compliance

To clean up resources, run: ./destroy.sh

Configuration files:
- environment.sh: Environment variables
- accounts.json: Sample account data
- transactions.json: Sample transaction data
- audit-queries.sql: Sample audit queries

For more information, refer to the recipe documentation.
EOF

    success "Deployment summary generated"
}

# Cleanup temporary files
cleanup_temp_files() {
    info "Cleaning up temporary files..."
    rm -f "${SCRIPT_DIR}/qldb-trust-policy.json"
    rm -f "${SCRIPT_DIR}/qldb-permissions-policy.json"
    rm -f "${SCRIPT_DIR}/kinesis-config.json"
}

# Main deployment function
main() {
    log "Starting QLDB infrastructure deployment..."
    
    parse_args "$@"
    check_prerequisites
    set_environment
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        warn "Running in DRY RUN mode - no resources will be created"
    fi

    # Deploy infrastructure
    create_s3_bucket
    create_kinesis_stream
    create_iam_role
    create_qldb_ledger
    setup_journal_streaming
    create_sample_data
    generate_summary
    cleanup_temp_files

    if [[ "${DRY_RUN}" == "true" ]]; then
        info "Dry run completed - no resources were created"
    else
        success "QLDB infrastructure deployment completed successfully!"
        info "Check deployment-summary.txt for details"
        info "Environment variables saved to environment.sh"
    fi
}

# Run main function with all arguments
main "$@"