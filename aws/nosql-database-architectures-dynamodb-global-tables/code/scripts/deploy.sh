#!/bin/bash

# =============================================================================
# DynamoDB Global Tables Deployment Script
# =============================================================================
# This script deploys a complete DynamoDB Global Tables architecture
# following the recipe: Architecting NoSQL Databases with DynamoDB Global Tables
# =============================================================================

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# =============================================================================
# Configuration Variables
# =============================================================================

# Default regions (can be overridden)
PRIMARY_REGION=${PRIMARY_REGION:-"us-east-1"}
SECONDARY_REGION=${SECONDARY_REGION:-"eu-west-1"}
TERTIARY_REGION=${TERTIARY_REGION:-"ap-southeast-1"}

# Resource naming
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

TABLE_NAME="global-app-data-${RANDOM_SUFFIX}"
IAM_ROLE_NAME="DynamoDBGlobalTableRole-${RANDOM_SUFFIX}"
KMS_KEY_ALIAS="alias/dynamodb-global-${RANDOM_SUFFIX}"
LAMBDA_FUNCTION_NAME="global-table-test-${RANDOM_SUFFIX}"
BACKUP_VAULT_NAME="DynamoDB-Global-Backup-${RANDOM_SUFFIX}"

# File paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/dynamodb-global-deployment-$$"
LOG_FILE="${SCRIPT_DIR}/deployment.log"

# =============================================================================
# Helper Functions
# =============================================================================

# Check if required tools are installed
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
    
    # Check Python for scripts
    if ! command -v python3 &> /dev/null; then
        error "Python3 is not installed. Please install it first."
        exit 1
    fi
    
    # Check pip for boto3
    if ! python3 -c "import boto3" &> /dev/null; then
        warn "boto3 not found. Installing..."
        pip3 install boto3 || {
            error "Failed to install boto3. Please install it manually."
            exit 1
        }
    fi
    
    # Get AWS Account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log "✅ Prerequisites check completed"
    info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    info "Primary Region: ${PRIMARY_REGION}"
    info "Secondary Region: ${SECONDARY_REGION}"
    info "Tertiary Region: ${TERTIARY_REGION}"
}

# Create temporary directory for files
setup_temp_directory() {
    mkdir -p "${TEMP_DIR}"
    log "Created temporary directory: ${TEMP_DIR}"
}

# Cleanup temporary files
cleanup_temp_files() {
    if [ -d "${TEMP_DIR}" ]; then
        rm -rf "${TEMP_DIR}"
        log "Cleaned up temporary directory"
    fi
}

# Wait for resource to be ready
wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local region=$3
    local max_attempts=${4:-30}
    local attempt=0
    
    log "Waiting for ${resource_type} ${resource_name} in ${region}..."
    
    while [ $attempt -lt $max_attempts ]; do
        case $resource_type in
            "table")
                if aws dynamodb describe-table --region "$region" --table-name "$resource_name" --query 'Table.TableStatus' --output text 2>/dev/null | grep -q "ACTIVE"; then
                    log "✅ Table ${resource_name} is active in ${region}"
                    return 0
                fi
                ;;
            "global-table")
                if aws dynamodb describe-global-table --region "$region" --global-table-name "$resource_name" --query 'GlobalTableDescription.GlobalTableStatus' --output text 2>/dev/null | grep -q "ACTIVE"; then
                    log "✅ Global Table ${resource_name} is active"
                    return 0
                fi
                ;;
        esac
        
        sleep 10
        ((attempt++))
        info "Attempt ${attempt}/${max_attempts}..."
    done
    
    error "Timeout waiting for ${resource_type} ${resource_name}"
    return 1
}

# =============================================================================
# IAM Role Creation
# =============================================================================

create_iam_role() {
    log "Creating IAM role for DynamoDB Global Tables..."
    
    # Create trust policy
    cat > "${TEMP_DIR}/dynamodb-trust-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": [
                    "lambda.amazonaws.com",
                    "ec2.amazonaws.com"
                ]
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
        --assume-role-policy-document file://"${TEMP_DIR}/dynamodb-trust-policy.json" \
        --description "Role for DynamoDB Global Tables access" \
        >> "${LOG_FILE}" 2>&1
    
    # Create permissions policy
    cat > "${TEMP_DIR}/dynamodb-global-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Query",
                "dynamodb:Scan",
                "dynamodb:BatchGetItem",
                "dynamodb:BatchWriteItem",
                "dynamodb:ConditionCheckItem"
            ],
            "Resource": [
                "arn:aws:dynamodb:*:${AWS_ACCOUNT_ID}:table/${TABLE_NAME}",
                "arn:aws:dynamodb:*:${AWS_ACCOUNT_ID}:table/${TABLE_NAME}/index/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:DescribeTable",
                "dynamodb:DescribeStream",
                "dynamodb:ListStreams"
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
    
    # Create and attach policy
    aws iam create-policy \
        --policy-name "${IAM_ROLE_NAME}-Policy" \
        --policy-document file://"${TEMP_DIR}/dynamodb-global-policy.json" \
        --description "Policy for DynamoDB Global Tables operations" \
        >> "${LOG_FILE}" 2>&1
    
    local policy_arn=$(aws iam list-policies \
        --query "Policies[?PolicyName=='${IAM_ROLE_NAME}-Policy'].Arn" \
        --output text)
    
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn "${policy_arn}" \
        >> "${LOG_FILE}" 2>&1
    
    # Wait for role to be ready
    sleep 10
    
    local role_arn=$(aws iam get-role --role-name "${IAM_ROLE_NAME}" --query 'Role.Arn' --output text)
    log "✅ Created IAM role: ${role_arn}"
    
    export IAM_ROLE_ARN="${role_arn}"
}

# =============================================================================
# KMS Key Creation
# =============================================================================

create_kms_keys() {
    log "Creating KMS keys for encryption in each region..."
    
    # Primary region
    local primary_key_id=$(aws kms create-key \
        --region "${PRIMARY_REGION}" \
        --description "DynamoDB Global Table encryption key for ${PRIMARY_REGION}" \
        --key-usage ENCRYPT_DECRYPT \
        --key-spec SYMMETRIC_DEFAULT \
        --query 'KeyMetadata.KeyId' --output text)
    
    aws kms create-alias \
        --region "${PRIMARY_REGION}" \
        --alias-name "${KMS_KEY_ALIAS}-${PRIMARY_REGION}" \
        --target-key-id "${primary_key_id}" \
        >> "${LOG_FILE}" 2>&1
    
    # Secondary region
    local secondary_key_id=$(aws kms create-key \
        --region "${SECONDARY_REGION}" \
        --description "DynamoDB Global Table encryption key for ${SECONDARY_REGION}" \
        --key-usage ENCRYPT_DECRYPT \
        --key-spec SYMMETRIC_DEFAULT \
        --query 'KeyMetadata.KeyId' --output text)
    
    aws kms create-alias \
        --region "${SECONDARY_REGION}" \
        --alias-name "${KMS_KEY_ALIAS}-${SECONDARY_REGION}" \
        --target-key-id "${secondary_key_id}" \
        >> "${LOG_FILE}" 2>&1
    
    # Tertiary region
    local tertiary_key_id=$(aws kms create-key \
        --region "${TERTIARY_REGION}" \
        --description "DynamoDB Global Table encryption key for ${TERTIARY_REGION}" \
        --key-usage ENCRYPT_DECRYPT \
        --key-spec SYMMETRIC_DEFAULT \
        --query 'KeyMetadata.KeyId' --output text)
    
    aws kms create-alias \
        --region "${TERTIARY_REGION}" \
        --alias-name "${KMS_KEY_ALIAS}-${TERTIARY_REGION}" \
        --target-key-id "${tertiary_key_id}" \
        >> "${LOG_FILE}" 2>&1
    
    log "✅ Created KMS keys in all regions"
    info "Primary Key: ${primary_key_id}"
    info "Secondary Key: ${secondary_key_id}"
    info "Tertiary Key: ${tertiary_key_id}"
    
    export PRIMARY_KEY_ID="${primary_key_id}"
    export SECONDARY_KEY_ID="${secondary_key_id}"
    export TERTIARY_KEY_ID="${tertiary_key_id}"
}

# =============================================================================
# DynamoDB Table Creation
# =============================================================================

create_dynamodb_table() {
    log "Creating DynamoDB table in primary region..."
    
    aws dynamodb create-table \
        --region "${PRIMARY_REGION}" \
        --table-name "${TABLE_NAME}" \
        --attribute-definitions \
            AttributeName=PK,AttributeType=S \
            AttributeName=SK,AttributeType=S \
            AttributeName=GSI1PK,AttributeType=S \
            AttributeName=GSI1SK,AttributeType=S \
        --key-schema \
            AttributeName=PK,KeyType=HASH \
            AttributeName=SK,KeyType=RANGE \
        --global-secondary-indexes \
            IndexName=GSI1,KeySchema=[{AttributeName=GSI1PK,KeyType=HASH},{AttributeName=GSI1SK,KeyType=RANGE}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=5,WriteCapacityUnits=5} \
        --provisioned-throughput \
            ReadCapacityUnits=10,WriteCapacityUnits=10 \
        --stream-specification \
            StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
        --sse-specification \
            Enabled=true,SSEType=KMS,KMSMasterKeyId="${KMS_KEY_ALIAS}-${PRIMARY_REGION}" \
        --point-in-time-recovery-specification \
            PointInTimeRecoveryEnabled=true \
        --deletion-protection-enabled \
        >> "${LOG_FILE}" 2>&1
    
    wait_for_resource "table" "${TABLE_NAME}" "${PRIMARY_REGION}"
    log "✅ Created primary DynamoDB table"
}

# =============================================================================
# Global Tables Configuration
# =============================================================================

create_global_tables() {
    log "Creating Global Tables configuration..."
    
    # Create global table with secondary region
    aws dynamodb create-global-table \
        --region "${PRIMARY_REGION}" \
        --global-table-name "${TABLE_NAME}" \
        --replication-group RegionName="${PRIMARY_REGION}" RegionName="${SECONDARY_REGION}" \
        >> "${LOG_FILE}" 2>&1
    
    sleep 30
    
    # Add tertiary region
    aws dynamodb update-global-table \
        --region "${PRIMARY_REGION}" \
        --global-table-name "${TABLE_NAME}" \
        --replica-updates Create={RegionName="${TERTIARY_REGION}"} \
        >> "${LOG_FILE}" 2>&1
    
    sleep 30
    
    # Configure encryption for replica tables
    aws dynamodb update-table \
        --region "${SECONDARY_REGION}" \
        --table-name "${TABLE_NAME}" \
        --sse-specification \
            Enabled=true,SSEType=KMS,KMSMasterKeyId="${KMS_KEY_ALIAS}-${SECONDARY_REGION}" \
        >> "${LOG_FILE}" 2>&1
    
    aws dynamodb update-table \
        --region "${TERTIARY_REGION}" \
        --table-name "${TABLE_NAME}" \
        --sse-specification \
            Enabled=true,SSEType=KMS,KMSMasterKeyId="${KMS_KEY_ALIAS}-${TERTIARY_REGION}" \
        >> "${LOG_FILE}" 2>&1
    
    # Enable point-in-time recovery for replicas
    aws dynamodb update-continuous-backups \
        --region "${SECONDARY_REGION}" \
        --table-name "${TABLE_NAME}" \
        --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true \
        >> "${LOG_FILE}" 2>&1
    
    aws dynamodb update-continuous-backups \
        --region "${TERTIARY_REGION}" \
        --table-name "${TABLE_NAME}" \
        --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true \
        >> "${LOG_FILE}" 2>&1
    
    wait_for_resource "global-table" "${TABLE_NAME}" "${PRIMARY_REGION}"
    log "✅ Created Global Tables configuration"
}

# =============================================================================
# Sample Data and Lambda Function
# =============================================================================

create_sample_data() {
    log "Creating sample data and Lambda function..."
    
    # Create sample data insertion script
    cat > "${TEMP_DIR}/insert-sample-data.py" << 'EOF'
import boto3
import json
import time
import uuid
from datetime import datetime, timezone
import os

def insert_sample_data(region, table_name):
    dynamodb = boto3.resource('dynamodb', region_name=region)
    table = dynamodb.Table(table_name)
    
    sample_items = [
        {
            'PK': 'USER#user1',
            'SK': 'PROFILE',
            'GSI1PK': 'PROFILE#ACTIVE',
            'GSI1SK': 'USER#user1',
            'email': 'user1@example.com',
            'name': 'John Doe',
            'region': region,
            'created_at': datetime.now(timezone.utc).isoformat(),
            'status': 'active'
        },
        {
            'PK': 'USER#user1',
            'SK': 'ORDER#' + str(uuid.uuid4()),
            'GSI1PK': 'ORDER#PENDING',
            'GSI1SK': datetime.now(timezone.utc).isoformat(),
            'amount': 99.99,
            'currency': 'USD',
            'items': ['item1', 'item2'],
            'region': region,
            'status': 'pending'
        },
        {
            'PK': 'PRODUCT#prod1',
            'SK': 'DETAILS',
            'GSI1PK': 'PRODUCT#ELECTRONICS',
            'GSI1SK': 'PRODUCT#prod1',
            'name': 'Wireless Headphones',
            'price': 79.99,
            'category': 'electronics',
            'inventory': 100,
            'region': region,
            'updated_at': datetime.now(timezone.utc).isoformat()
        }
    ]
    
    print(f"Inserting sample data in {region}...")
    for item in sample_items:
        try:
            table.put_item(Item=item)
            print(f"  Inserted: {item['PK']}#{item['SK']}")
        except Exception as e:
            print(f"  Error inserting {item['PK']}: {e}")
    
    return len(sample_items)

if __name__ == '__main__':
    table_name = os.environ.get('TABLE_NAME')
    primary_region = os.environ.get('PRIMARY_REGION')
    
    if not table_name or not primary_region:
        print("Please set TABLE_NAME and PRIMARY_REGION environment variables")
        exit(1)
    
    count = insert_sample_data(primary_region, table_name)
    print(f"Inserted {count} items in {primary_region}")
EOF
    
    # Insert sample data
    export TABLE_NAME="${TABLE_NAME}"
    export PRIMARY_REGION="${PRIMARY_REGION}"
    python3 "${TEMP_DIR}/insert-sample-data.py"
    
    # Create Lambda function
    cat > "${TEMP_DIR}/global-table-test-function.py" << 'EOF'
import json
import boto3
import os
from datetime import datetime, timezone
import uuid

def lambda_handler(event, context):
    table_name = os.environ['TABLE_NAME']
    regions = os.environ['REGIONS'].split(',')
    
    results = {}
    
    for region in regions:
        try:
            dynamodb = boto3.resource('dynamodb', region_name=region)
            table = dynamodb.Table(table_name)
            
            test_item = {
                'PK': f'TEST#{uuid.uuid4()}',
                'SK': 'LAMBDA_TEST',
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'region': region,
                'test_data': f'Test from Lambda in {region}'
            }
            
            table.put_item(Item=test_item)
            
            response = table.scan(
                FilterExpression='attribute_exists(#r)',
                ExpressionAttributeNames={'#r': 'region'},
                Limit=5
            )
            
            results[region] = {
                'write_success': True,
                'items_count': response['Count'],
                'sample_items': response['Items'][:2]
            }
            
        except Exception as e:
            results[region] = {
                'error': str(e),
                'write_success': False
            }
    
    return {
        'statusCode': 200,
        'body': json.dumps(results, default=str)
    }
EOF
    
    # Create Lambda deployment package
    cd "${TEMP_DIR}"
    zip -r global-table-test.zip global-table-test-function.py
    
    # Deploy Lambda function
    aws lambda create-function \
        --region "${PRIMARY_REGION}" \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "${IAM_ROLE_ARN}" \
        --handler global-table-test-function.lambda_handler \
        --zip-file fileb://global-table-test.zip \
        --environment Variables="{TABLE_NAME=${TABLE_NAME},REGIONS=${PRIMARY_REGION},${SECONDARY_REGION},${TERTIARY_REGION}}" \
        --timeout 60 \
        --description "Test function for DynamoDB Global Tables" \
        >> "${LOG_FILE}" 2>&1
    
    cd - > /dev/null
    log "✅ Created sample data and Lambda function"
}

# =============================================================================
# Monitoring and Backup
# =============================================================================

create_monitoring() {
    log "Creating CloudWatch monitoring..."
    
    create_cloudwatch_alarms() {
        local region=$1
        
        # Read throttling alarm
        aws cloudwatch put-metric-alarm \
            --region "${region}" \
            --alarm-name "${TABLE_NAME}-ReadThrottles-${region}" \
            --alarm-description "High read throttling on ${TABLE_NAME} in ${region}" \
            --metric-name ReadThrottledEvents \
            --namespace AWS/DynamoDB \
            --statistic Sum \
            --period 300 \
            --threshold 5 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 2 \
            --dimensions Name=TableName,Value="${TABLE_NAME}" \
            >> "${LOG_FILE}" 2>&1
        
        # Write throttling alarm
        aws cloudwatch put-metric-alarm \
            --region "${region}" \
            --alarm-name "${TABLE_NAME}-WriteThrottles-${region}" \
            --alarm-description "High write throttling on ${TABLE_NAME} in ${region}" \
            --metric-name WriteThrottledEvents \
            --namespace AWS/DynamoDB \
            --statistic Sum \
            --period 300 \
            --threshold 5 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 2 \
            --dimensions Name=TableName,Value="${TABLE_NAME}" \
            >> "${LOG_FILE}" 2>&1
        
        # Replication lag alarm
        aws cloudwatch put-metric-alarm \
            --region "${region}" \
            --alarm-name "${TABLE_NAME}-ReplicationLag-${region}" \
            --alarm-description "High replication lag on ${TABLE_NAME} in ${region}" \
            --metric-name ReplicationDelay \
            --namespace AWS/DynamoDB \
            --statistic Average \
            --period 300 \
            --threshold 1000 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 2 \
            --dimensions Name=TableName,Value="${TABLE_NAME}" Name=ReceivingRegion,Value="${region}" \
            >> "${LOG_FILE}" 2>&1
    }
    
    # Create alarms for all regions
    create_cloudwatch_alarms "${PRIMARY_REGION}"
    create_cloudwatch_alarms "${SECONDARY_REGION}"
    create_cloudwatch_alarms "${TERTIARY_REGION}"
    
    log "✅ Created CloudWatch monitoring"
}

create_backup_configuration() {
    log "Creating backup configuration..."
    
    # Create backup vault
    aws backup create-backup-vault \
        --region "${PRIMARY_REGION}" \
        --backup-vault-name "${BACKUP_VAULT_NAME}" \
        --encryption-key-arn "arn:aws:kms:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:alias/aws/backup" \
        >> "${LOG_FILE}" 2>&1
    
    # Create backup plan
    cat > "${TEMP_DIR}/backup-plan.json" << EOF
{
    "BackupPlanName": "DynamoDB-Global-Backup-Plan-${RANDOM_SUFFIX}",
    "Rules": [
        {
            "RuleName": "DailyBackups",
            "TargetBackupVaultName": "${BACKUP_VAULT_NAME}",
            "ScheduleExpression": "cron(0 2 ? * * *)",
            "StartWindowMinutes": 60,
            "CompletionWindowMinutes": 120,
            "Lifecycle": {
                "DeleteAfterDays": 30
            },
            "RecoveryPointTags": {
                "Environment": "Production",
                "Application": "GlobalApp"
            }
        }
    ]
}
EOF
    
    local backup_plan_id=$(aws backup create-backup-plan \
        --region "${PRIMARY_REGION}" \
        --backup-plan file://"${TEMP_DIR}/backup-plan.json" \
        --query 'BackupPlanId' --output text)
    
    # Create backup selection
    cat > "${TEMP_DIR}/backup-selection.json" << EOF
{
    "SelectionName": "DynamoDB-Global-Selection",
    "IamRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/service-role/AWSBackupDefaultServiceRole",
    "Resources": [
        "arn:aws:dynamodb:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:table/${TABLE_NAME}"
    ],
    "Conditions": {
        "StringEquals": {
            "aws:ResourceTag/Environment": ["Production"]
        }
    }
}
EOF
    
    aws backup create-backup-selection \
        --region "${PRIMARY_REGION}" \
        --backup-plan-id "${backup_plan_id}" \
        --backup-selection file://"${TEMP_DIR}/backup-selection.json" \
        >> "${LOG_FILE}" 2>&1
    
    log "✅ Created backup configuration"
    export BACKUP_PLAN_ID="${backup_plan_id}"
}

# =============================================================================
# Deployment Summary
# =============================================================================

create_deployment_summary() {
    log "Creating deployment summary..."
    
    cat > "${SCRIPT_DIR}/deployment-summary.json" << EOF
{
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "table_name": "${TABLE_NAME}",
    "regions": {
        "primary": "${PRIMARY_REGION}",
        "secondary": "${SECONDARY_REGION}",
        "tertiary": "${TERTIARY_REGION}"
    },
    "resources": {
        "iam_role": "${IAM_ROLE_NAME}",
        "lambda_function": "${LAMBDA_FUNCTION_NAME}",
        "backup_vault": "${BACKUP_VAULT_NAME}",
        "kms_keys": {
            "primary": "${PRIMARY_KEY_ID}",
            "secondary": "${SECONDARY_KEY_ID}",
            "tertiary": "${TERTIARY_KEY_ID}"
        }
    },
    "backup_plan_id": "${BACKUP_PLAN_ID}",
    "random_suffix": "${RANDOM_SUFFIX}"
}
EOF
    
    log "✅ Deployment summary created at: ${SCRIPT_DIR}/deployment-summary.json"
}

# =============================================================================
# Main Deployment Function
# =============================================================================

main() {
    log "Starting DynamoDB Global Tables deployment..."
    log "=================================================="
    
    # Initialize logging
    echo "Deployment started at $(date)" > "${LOG_FILE}"
    
    # Setup
    check_prerequisites
    setup_temp_directory
    
    # Trap to cleanup on exit
    trap cleanup_temp_files EXIT
    
    # Deploy infrastructure
    create_iam_role
    create_kms_keys
    create_dynamodb_table
    create_global_tables
    create_sample_data
    create_monitoring
    create_backup_configuration
    create_deployment_summary
    
    log "=================================================="
    log "🎉 DynamoDB Global Tables deployment completed successfully!"
    log "=================================================="
    
    info "Table Name: ${TABLE_NAME}"
    info "Regions: ${PRIMARY_REGION}, ${SECONDARY_REGION}, ${TERTIARY_REGION}"
    info "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    info "Summary: ${SCRIPT_DIR}/deployment-summary.json"
    info "Logs: ${LOG_FILE}"
    
    log "Next steps:"
    log "1. Test the deployment with: aws dynamodb describe-global-table --region ${PRIMARY_REGION} --global-table-name ${TABLE_NAME}"
    log "2. Test Lambda function: aws lambda invoke --region ${PRIMARY_REGION} --function-name ${LAMBDA_FUNCTION_NAME} response.json"
    log "3. Monitor with CloudWatch dashboards"
    log "4. Use destroy.sh to clean up resources when done"
}

# =============================================================================
# Script Execution
# =============================================================================

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo "Deploy DynamoDB Global Tables architecture"
        echo ""
        echo "Environment Variables:"
        echo "  PRIMARY_REGION     Primary AWS region (default: us-east-1)"
        echo "  SECONDARY_REGION   Secondary AWS region (default: eu-west-1)"
        echo "  TERTIARY_REGION    Tertiary AWS region (default: ap-southeast-1)"
        echo ""
        echo "Options:"
        echo "  -h, --help         Show this help message"
        echo "  --dry-run          Show what would be deployed without executing"
        echo ""
        exit 0
        ;;
    --dry-run)
        log "DRY RUN MODE - No resources will be created"
        check_prerequisites
        log "Would deploy:"
        log "  - IAM Role: ${IAM_ROLE_NAME}"
        log "  - DynamoDB Table: ${TABLE_NAME}"
        log "  - KMS Keys in regions: ${PRIMARY_REGION}, ${SECONDARY_REGION}, ${TERTIARY_REGION}"
        log "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
        log "  - CloudWatch Alarms and Backup Configuration"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac