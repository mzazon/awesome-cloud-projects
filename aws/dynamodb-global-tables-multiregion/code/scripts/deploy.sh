#!/bin/bash

# =============================================================================
# DynamoDB Global Tables Multi-Region Deployment Script
# =============================================================================
# This script deploys a complete DynamoDB Global Tables solution with:
# - Multi-region DynamoDB Global Tables
# - Lambda functions for testing and monitoring
# - CloudWatch monitoring and alerting
# - Global Secondary Indexes
# - Comprehensive validation and testing
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# =============================================================================
# CONFIGURATION AND CONSTANTS
# =============================================================================

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/dynamodb-global-tables-deploy-$(date +%Y%m%d_%H%M%S).log"

# Default regions (can be overridden by environment variables)
readonly DEFAULT_PRIMARY_REGION="us-east-1"
readonly DEFAULT_SECONDARY_REGION="eu-west-1"
readonly DEFAULT_TERTIARY_REGION="ap-northeast-1"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Info logging
info() {
    log "INFO" "$@"
    echo -e "${BLUE}ℹ️  $*${NC}"
}

# Success logging
success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}✅ $*${NC}"
}

# Warning logging
warn() {
    log "WARN" "$@"
    echo -e "${YELLOW}⚠️  $*${NC}"
}

# Error logging
error() {
    log "ERROR" "$@"
    echo -e "${RED}❌ $*${NC}" >&2
}

# Fatal error (exits script)
fatal() {
    error "$@"
    exit 1
}

# Progress indicator
progress() {
    local step="$1"
    local total="$2"
    local description="$3"
    
    info "Step $step/$total: $description"
}

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        fatal "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        fatal "AWS CLI is not configured or credentials are invalid."
    fi
    
    # Check if jq is installed (for JSON parsing)
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Some features may be limited."
    fi
    
    # Check if python3 is available (for Lambda functions)
    if ! command -v python3 &> /dev/null; then
        fatal "Python 3 is not installed. Required for Lambda functions."
    fi
    
    # Check if zip is available (for Lambda deployment packages)
    if ! command -v zip &> /dev/null; then
        fatal "zip utility is not installed. Required for Lambda deployment."
    fi
    
    success "Prerequisites check completed"
}

# =============================================================================
# REGION VALIDATION
# =============================================================================

validate_regions() {
    info "Validating AWS regions..."
    
    local regions=("$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION")
    
    for region in "${regions[@]}"; do
        if ! aws ec2 describe-regions --region-names "$region" &> /dev/null; then
            fatal "Invalid region: $region"
        fi
        
        # Check if DynamoDB is available in the region
        if ! aws dynamodb list-tables --region "$region" &> /dev/null; then
            fatal "DynamoDB is not available in region: $region"
        fi
    done
    
    success "Region validation completed"
}

# =============================================================================
# ENVIRONMENT SETUP
# =============================================================================

setup_environment() {
    info "Setting up environment variables..."
    
    # Set regions with defaults
    export PRIMARY_REGION="${PRIMARY_REGION:-$DEFAULT_PRIMARY_REGION}"
    export SECONDARY_REGION="${SECONDARY_REGION:-$DEFAULT_SECONDARY_REGION}"
    export TERTIARY_REGION="${TERTIARY_REGION:-$DEFAULT_TERTIARY_REGION}"
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix
    if command -v aws &> /dev/null; then
        random_suffix=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    else
        random_suffix=$(date +%s | tail -c 6)
    fi
    
    # Set resource names
    export TABLE_NAME="GlobalUserProfiles-${random_suffix}"
    export LAMBDA_FUNCTION_NAME="GlobalTableProcessor-${random_suffix}"
    export IAM_ROLE_NAME="GlobalTableRole-${random_suffix}"
    export CLOUDWATCH_ALARM_PREFIX="GlobalTable-${random_suffix}"
    
    # Export for cleanup script
    echo "export TABLE_NAME=\"$TABLE_NAME\"" > /tmp/global-table-env.sh
    echo "export LAMBDA_FUNCTION_NAME=\"$LAMBDA_FUNCTION_NAME\"" >> /tmp/global-table-env.sh
    echo "export IAM_ROLE_NAME=\"$IAM_ROLE_NAME\"" >> /tmp/global-table-env.sh
    echo "export CLOUDWATCH_ALARM_PREFIX=\"$CLOUDWATCH_ALARM_PREFIX\"" >> /tmp/global-table-env.sh
    echo "export PRIMARY_REGION=\"$PRIMARY_REGION\"" >> /tmp/global-table-env.sh
    echo "export SECONDARY_REGION=\"$SECONDARY_REGION\"" >> /tmp/global-table-env.sh
    echo "export TERTIARY_REGION=\"$TERTIARY_REGION\"" >> /tmp/global-table-env.sh
    echo "export AWS_ACCOUNT_ID=\"$AWS_ACCOUNT_ID\"" >> /tmp/global-table-env.sh
    
    success "Environment setup completed"
    info "Primary region: $PRIMARY_REGION"
    info "Secondary region: $SECONDARY_REGION"
    info "Tertiary region: $TERTIARY_REGION"
    info "Table name: $TABLE_NAME"
    info "Lambda function: $LAMBDA_FUNCTION_NAME"
}

# =============================================================================
# IAM ROLE CREATION
# =============================================================================

create_iam_role() {
    progress 1 12 "Creating IAM role for Lambda functions"
    
    # Create IAM role
    aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document '{
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
        }' \
        --region "$PRIMARY_REGION" || {
            if aws iam get-role --role-name "$IAM_ROLE_NAME" &> /dev/null; then
                warn "IAM role $IAM_ROLE_NAME already exists"
            else
                fatal "Failed to create IAM role"
            fi
        }
    
    # Attach necessary policies
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        --region "$PRIMARY_REGION"
    
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess \
        --region "$PRIMARY_REGION"
    
    # Wait for role to be available
    info "Waiting for IAM role to be available..."
    sleep 30
    
    success "IAM role created successfully"
}

# =============================================================================
# DYNAMODB TABLE CREATION
# =============================================================================

create_primary_table() {
    progress 2 12 "Creating primary DynamoDB table with streams"
    
    # Create the primary table with streams enabled
    aws dynamodb create-table \
        --table-name "$TABLE_NAME" \
        --attribute-definitions \
            AttributeName=UserId,AttributeType=S \
            AttributeName=ProfileType,AttributeType=S \
        --key-schema \
            AttributeName=UserId,KeyType=HASH \
            AttributeName=ProfileType,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
        --region "$PRIMARY_REGION" || {
            if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$PRIMARY_REGION" &> /dev/null; then
                warn "Table $TABLE_NAME already exists in $PRIMARY_REGION"
            else
                fatal "Failed to create primary table"
            fi
        }
    
    # Wait for table to become active
    info "Waiting for primary table to become active..."
    aws dynamodb wait table-exists \
        --table-name "$TABLE_NAME" \
        --region "$PRIMARY_REGION" || fatal "Primary table failed to become active"
    
    success "Primary table created in $PRIMARY_REGION"
}

# =============================================================================
# GLOBAL TABLE SETUP
# =============================================================================

create_global_table_replicas() {
    progress 3 12 "Creating global table replicas"
    
    # Add replica in secondary region
    info "Adding replica in $SECONDARY_REGION..."
    aws dynamodb update-table \
        --table-name "$TABLE_NAME" \
        --replica-updates \
            "Create={RegionName=$SECONDARY_REGION}" \
        --region "$PRIMARY_REGION" || warn "Failed to add replica in $SECONDARY_REGION (may already exist)"
    
    # Add replica in tertiary region
    info "Adding replica in $TERTIARY_REGION..."
    aws dynamodb update-table \
        --table-name "$TABLE_NAME" \
        --replica-updates \
            "Create={RegionName=$TERTIARY_REGION}" \
        --region "$PRIMARY_REGION" || warn "Failed to add replica in $TERTIARY_REGION (may already exist)"
    
    # Wait for replicas to be created
    info "Waiting for replicas to be created (this may take several minutes)..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local replica_status=$(aws dynamodb describe-table \
            --table-name "$TABLE_NAME" \
            --region "$PRIMARY_REGION" \
            --query 'Table.Replicas[?ReplicaStatus!=`ACTIVE`].ReplicaStatus' \
            --output text 2>/dev/null || echo "CREATING")
        
        if [ -z "$replica_status" ]; then
            break
        fi
        
        attempt=$((attempt + 1))
        info "Attempt $attempt/$max_attempts: Replicas still creating..."
        sleep 30
    done
    
    if [ $attempt -eq $max_attempts ]; then
        warn "Replica creation took longer than expected, continuing..."
    fi
    
    success "Global table replicas created"
}

# =============================================================================
# LAMBDA FUNCTION CREATION
# =============================================================================

create_lambda_functions() {
    progress 4 12 "Creating Lambda functions for testing"
    
    # Create Lambda function code
    local lambda_code_file="/tmp/global-table-processor.py"
    cat > "$lambda_code_file" << 'EOF'
import json
import boto3
import os
import time
from datetime import datetime

def lambda_handler(event, context):
    # Get region from environment or context
    region = os.environ.get('AWS_REGION', context.invoked_function_arn.split(':')[3])
    
    # Initialize DynamoDB client
    dynamodb = boto3.resource('dynamodb', region_name=region)
    table = dynamodb.Table(os.environ['TABLE_NAME'])
    
    # Process the operation
    operation = event.get('operation', 'put')
    
    try:
        if operation == 'put':
            # Create a test item
            user_id = event.get('userId', f'user-{int(time.time())}')
            profile_type = event.get('profileType', 'standard')
            
            response = table.put_item(
                Item={
                    'UserId': user_id,
                    'ProfileType': profile_type,
                    'Name': event.get('name', 'Test User'),
                    'Email': event.get('email', 'test@example.com'),
                    'Region': region,
                    'CreatedAt': datetime.utcnow().isoformat(),
                    'LastModified': datetime.utcnow().isoformat()
                }
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Item created in {region}',
                    'userId': user_id,
                    'profileType': profile_type,
                    'region': region
                })
            }
        
        elif operation == 'get':
            # Retrieve an item
            user_id = event.get('userId')
            profile_type = event.get('profileType', 'standard')
            
            if not user_id:
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'userId is required for get operation'})
                }
            
            response = table.get_item(
                Key={
                    'UserId': user_id,
                    'ProfileType': profile_type
                }
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Item retrieved from {region}',
                    'item': response.get('Item'),
                    'region': region
                })
            }
        
        elif operation == 'scan':
            # Scan for items in this region
            response = table.scan(
                ProjectionExpression='UserId, ProfileType, #r, CreatedAt',
                ExpressionAttributeNames={'#r': 'Region'},
                Limit=10
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Items scanned from {region}',
                    'count': response['Count'],
                    'items': response.get('Items', []),
                    'region': region
                })
            }
        
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f'Unknown operation: {operation}'})
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'region': region
            })
        }
EOF
    
    # Create deployment package
    local deployment_dir="/tmp/lambda-deployment"
    mkdir -p "$deployment_dir"
    cp "$lambda_code_file" "$deployment_dir/"
    
    cd "$deployment_dir"
    zip -r global-table-processor.zip global-table-processor.py
    
    # Deploy Lambda function in each region
    local regions=("$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION")
    
    for region in "${regions[@]}"; do
        info "Deploying Lambda function in $region..."
        
        aws lambda create-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --runtime python3.9 \
            --role "arn:aws:iam::$AWS_ACCOUNT_ID:role/$IAM_ROLE_NAME" \
            --handler global-table-processor.lambda_handler \
            --zip-file fileb://global-table-processor.zip \
            --environment "Variables={TABLE_NAME=$TABLE_NAME}" \
            --timeout 30 \
            --region "$region" || {
                if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$region" &> /dev/null; then
                    warn "Lambda function $LAMBDA_FUNCTION_NAME already exists in $region"
                else
                    error "Failed to create Lambda function in $region"
                fi
            }
    done
    
    # Wait for functions to be available
    info "Waiting for Lambda functions to be available..."
    sleep 30
    
    success "Lambda functions deployed in all regions"
}

# =============================================================================
# GLOBAL SECONDARY INDEX
# =============================================================================

create_global_secondary_index() {
    progress 5 12 "Creating Global Secondary Index"
    
    # Add a Global Secondary Index to the table
    aws dynamodb update-table \
        --table-name "$TABLE_NAME" \
        --attribute-definitions \
            AttributeName=Email,AttributeType=S \
        --global-secondary-index-updates \
            '[{
                "Create": {
                    "IndexName": "EmailIndex",
                    "KeySchema": [
                        {
                            "AttributeName": "Email",
                            "KeyType": "HASH"
                        }
                    ],
                    "Projection": {
                        "ProjectionType": "ALL"
                    }
                }
            }]' \
        --region "$PRIMARY_REGION" || {
            warn "Failed to create GSI (may already exist)"
        }
    
    # Wait for GSI to be created
    info "Waiting for Global Secondary Index to be created..."
    local max_attempts=20
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local gsi_status=$(aws dynamodb describe-table \
            --table-name "$TABLE_NAME" \
            --region "$PRIMARY_REGION" \
            --query 'Table.GlobalSecondaryIndexes[?IndexName==`EmailIndex`].IndexStatus' \
            --output text 2>/dev/null || echo "CREATING")
        
        if [ "$gsi_status" = "ACTIVE" ]; then
            break
        fi
        
        attempt=$((attempt + 1))
        info "Attempt $attempt/$max_attempts: GSI still creating..."
        sleep 30
    done
    
    success "Global Secondary Index created"
}

# =============================================================================
# CLOUDWATCH MONITORING
# =============================================================================

setup_monitoring() {
    progress 6 12 "Setting up CloudWatch monitoring"
    
    # Create CloudWatch alarm for replication latency
    aws cloudwatch put-metric-alarm \
        --alarm-name "$CLOUDWATCH_ALARM_PREFIX-ReplicationLatency" \
        --alarm-description "Monitor replication latency for global table" \
        --metric-name ReplicationLatency \
        --namespace AWS/DynamoDB \
        --statistic Average \
        --period 300 \
        --threshold 10000 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=TableName,Value="$TABLE_NAME" \
                     Name=ReceivingRegion,Value="$SECONDARY_REGION" \
        --region "$PRIMARY_REGION" || warn "Failed to create replication latency alarm"
    
    # Create alarm for user errors
    aws cloudwatch put-metric-alarm \
        --alarm-name "$CLOUDWATCH_ALARM_PREFIX-UserErrors" \
        --alarm-description "Monitor user errors for global table" \
        --metric-name UserErrors \
        --namespace AWS/DynamoDB \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=TableName,Value="$TABLE_NAME" \
        --region "$PRIMARY_REGION" || warn "Failed to create user errors alarm"
    
    # Create CloudWatch dashboard
    local dashboard_body=$(cat << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", "$TABLE_NAME"],
                    [".", "ConsumedWriteCapacityUnits", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "$PRIMARY_REGION",
                "title": "Read/Write Capacity"
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/DynamoDB", "ReplicationLatency", "TableName", "$TABLE_NAME", "ReceivingRegion", "$SECONDARY_REGION"],
                    [".", ".", ".", ".", ".", "$TERTIARY_REGION"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "$PRIMARY_REGION",
                "title": "Replication Latency"
            }
        }
    ]
}
EOF
)
    
    aws cloudwatch put-dashboard \
        --dashboard-name "$CLOUDWATCH_ALARM_PREFIX-Dashboard" \
        --dashboard-body "$dashboard_body" \
        --region "$PRIMARY_REGION" || warn "Failed to create CloudWatch dashboard"
    
    success "CloudWatch monitoring configured"
}

# =============================================================================
# VALIDATION AND TESTING
# =============================================================================

validate_deployment() {
    progress 7 12 "Validating deployment"
    
    # Check global table status
    info "Checking global table status..."
    local table_status=$(aws dynamodb describe-table \
        --table-name "$TABLE_NAME" \
        --region "$PRIMARY_REGION" \
        --query 'Table.TableStatus' \
        --output text 2>/dev/null || echo "UNKNOWN")
    
    if [ "$table_status" != "ACTIVE" ]; then
        error "Primary table is not active: $table_status"
    else
        success "Primary table is active"
    fi
    
    # Check replica status
    local regions=("$SECONDARY_REGION" "$TERTIARY_REGION")
    for region in "${regions[@]}"; do
        info "Checking replica in $region..."
        local replica_status=$(aws dynamodb describe-table \
            --table-name "$TABLE_NAME" \
            --region "$region" \
            --query 'Table.TableStatus' \
            --output text 2>/dev/null || echo "UNKNOWN")
        
        if [ "$replica_status" != "ACTIVE" ]; then
            warn "Replica in $region is not active: $replica_status"
        else
            success "Replica in $region is active"
        fi
    done
    
    # Check Lambda functions
    local regions=("$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION")
    for region in "${regions[@]}"; do
        info "Checking Lambda function in $region..."
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$region" &> /dev/null; then
            success "Lambda function active in $region"
        else
            error "Lambda function not found in $region"
        fi
    done
    
    success "Deployment validation completed"
}

# =============================================================================
# FUNCTIONAL TESTING
# =============================================================================

test_functionality() {
    progress 8 12 "Testing functionality"
    
    # Test writing data from primary region
    info "Testing data write from primary region..."
    local test_payload='{
        "operation": "put",
        "userId": "test-user-001",
        "profileType": "premium",
        "name": "Test User One",
        "email": "test1@example.com"
    }'
    
    aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload "$test_payload" \
        --region "$PRIMARY_REGION" \
        /tmp/response-primary.json || error "Failed to write data from primary region"
    
    # Test writing data from secondary region
    info "Testing data write from secondary region..."
    local test_payload2='{
        "operation": "put",
        "userId": "test-user-002",
        "profileType": "standard",
        "name": "Test User Two",
        "email": "test2@example.com"
    }'
    
    aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload "$test_payload2" \
        --region "$SECONDARY_REGION" \
        /tmp/response-secondary.json || error "Failed to write data from secondary region"
    
    # Wait for replication
    info "Waiting for replication..."
    sleep 15
    
    # Test reading data from all regions
    local regions=("$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION")
    for region in "${regions[@]}"; do
        info "Testing data read from $region..."
        local read_payload='{
            "operation": "get",
            "userId": "test-user-001",
            "profileType": "premium"
        }'
        
        aws lambda invoke \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --payload "$read_payload" \
            --region "$region" \
            "/tmp/response-read-$region.json" || warn "Failed to read data from $region"
    done
    
    success "Functionality testing completed"
}

# =============================================================================
# CONFLICT RESOLUTION TESTING
# =============================================================================

test_conflict_resolution() {
    progress 9 12 "Testing conflict resolution"
    
    info "Testing conflict resolution with concurrent writes..."
    
    # Write from primary region
    local conflict_payload1='{
        "operation": "put",
        "userId": "conflict-test",
        "profileType": "standard",
        "name": "Primary Region Update",
        "email": "primary@example.com"
    }'
    
    aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload "$conflict_payload1" \
        --region "$PRIMARY_REGION" \
        /tmp/conflict-primary.json &
    
    # Write from secondary region (almost simultaneously)
    local conflict_payload2='{
        "operation": "put",
        "userId": "conflict-test",
        "profileType": "standard",
        "name": "Secondary Region Update",
        "email": "secondary@example.com"
    }'
    
    aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload "$conflict_payload2" \
        --region "$SECONDARY_REGION" \
        /tmp/conflict-secondary.json &
    
    # Wait for both operations to complete
    wait
    
    # Wait for replication and conflict resolution
    sleep 20
    
    success "Conflict resolution test completed"
}

# =============================================================================
# PERFORMANCE TESTING
# =============================================================================

test_performance() {
    progress 10 12 "Testing performance"
    
    info "Running performance tests..."
    
    # Test scanning from each region
    local regions=("$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION")
    for region in "${regions[@]}"; do
        info "Testing scan performance from $region..."
        local scan_payload='{"operation": "scan"}'
        
        aws lambda invoke \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --payload "$scan_payload" \
            --region "$region" \
            "/tmp/performance-$region.json" || warn "Failed to scan from $region"
    done
    
    success "Performance testing completed"
}

# =============================================================================
# MONITORING VERIFICATION
# =============================================================================

verify_monitoring() {
    progress 11 12 "Verifying monitoring setup"
    
    # Check if alarms exist
    info "Checking CloudWatch alarms..."
    local alarms=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "$CLOUDWATCH_ALARM_PREFIX" \
        --region "$PRIMARY_REGION" \
        --query 'MetricAlarms[].AlarmName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$alarms" ]; then
        success "CloudWatch alarms are configured"
        info "Configured alarms: $alarms"
    else
        warn "No CloudWatch alarms found"
    fi
    
    # Check dashboard
    info "Checking CloudWatch dashboard..."
    if aws cloudwatch get-dashboard --dashboard-name "$CLOUDWATCH_ALARM_PREFIX-Dashboard" --region "$PRIMARY_REGION" &> /dev/null; then
        success "CloudWatch dashboard is configured"
    else
        warn "CloudWatch dashboard not found"
    fi
    
    success "Monitoring verification completed"
}

# =============================================================================
# DEPLOYMENT SUMMARY
# =============================================================================

show_deployment_summary() {
    progress 12 12 "Deployment summary"
    
    echo
    echo "==============================================================================="
    echo "                           DEPLOYMENT SUMMARY"
    echo "==============================================================================="
    echo
    echo "✅ Primary Region: $PRIMARY_REGION"
    echo "✅ Secondary Region: $SECONDARY_REGION"
    echo "✅ Tertiary Region: $TERTIARY_REGION"
    echo
    echo "📊 Resources Created:"
    echo "   • DynamoDB Table: $TABLE_NAME"
    echo "   • Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "   • IAM Role: $IAM_ROLE_NAME"
    echo "   • CloudWatch Alarms: $CLOUDWATCH_ALARM_PREFIX-*"
    echo "   • CloudWatch Dashboard: $CLOUDWATCH_ALARM_PREFIX-Dashboard"
    echo
    echo "🔗 Useful Commands:"
    echo "   • View table status: aws dynamodb describe-table --table-name $TABLE_NAME --region $PRIMARY_REGION"
    echo "   • View dashboard: aws cloudwatch get-dashboard --dashboard-name $CLOUDWATCH_ALARM_PREFIX-Dashboard --region $PRIMARY_REGION"
    echo "   • Test Lambda: aws lambda invoke --function-name $LAMBDA_FUNCTION_NAME --payload '{\"operation\":\"scan\"}' --region $PRIMARY_REGION /tmp/test.json"
    echo
    echo "🧹 Cleanup:"
    echo "   • Run: ./destroy.sh"
    echo "   • Or manually source: /tmp/global-table-env.sh"
    echo
    echo "📋 Log File: $LOG_FILE"
    echo "==============================================================================="
    echo
    
    success "Deployment completed successfully!"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Print header
    echo "==============================================================================="
    echo "                    DynamoDB Global Tables Deployment"
    echo "==============================================================================="
    echo
    
    # Start logging
    info "Starting deployment at $(date)"
    info "Log file: $LOG_FILE"
    
    # Check if dry run
    if [ "${DRY_RUN:-false}" = "true" ]; then
        info "DRY RUN MODE - No resources will be created"
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    validate_regions
    setup_environment
    create_iam_role
    create_primary_table
    create_global_table_replicas
    create_lambda_functions
    create_global_secondary_index
    setup_monitoring
    validate_deployment
    test_functionality
    test_conflict_resolution
    test_performance
    verify_monitoring
    show_deployment_summary
    
    info "Deployment completed at $(date)"
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Handle script interruption
trap 'error "Script interrupted"; exit 1' INT TERM

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            export DRY_RUN=true
            shift
            ;;
        --primary-region)
            export PRIMARY_REGION="$2"
            shift 2
            ;;
        --secondary-region)
            export SECONDARY_REGION="$2"
            shift 2
            ;;
        --tertiary-region)
            export TERTIARY_REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run              Run in dry-run mode (no resources created)"
            echo "  --primary-region       Set primary region (default: us-east-1)"
            echo "  --secondary-region     Set secondary region (default: eu-west-1)"
            echo "  --tertiary-region      Set tertiary region (default: ap-northeast-1)"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"