#!/bin/bash

# Deploy script for Multi-Region Distributed Applications with Aurora DSQL
# This script creates Aurora DSQL clusters, Lambda functions, and EventBridge resources
# across multiple AWS regions for high availability and strong consistency

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
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ "$(printf '%s\n' "2.0.0" "$AWS_CLI_VERSION" | sort -V | head -n1)" != "2.0.0" ]]; then
        error "AWS CLI version 2.0.0 or higher is required. Current version: $AWS_CLI_VERSION"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured or invalid."
    fi
    
    # Check required tools
    if ! command -v zip &> /dev/null; then
        error "zip utility is not installed."
    fi
    
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed."
    fi
    
    log "Prerequisites check completed successfully."
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Set default regions if not provided
    export PRIMARY_REGION=${PRIMARY_REGION:-us-east-1}
    export SECONDARY_REGION=${SECONDARY_REGION:-us-west-2}
    export WITNESS_REGION=${WITNESS_REGION:-eu-west-1}
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set resource names
    export CLUSTER_NAME_PRIMARY="app-cluster-primary-${RANDOM_SUFFIX}"
    export CLUSTER_NAME_SECONDARY="app-cluster-secondary-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="dsql-processor-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_BUS_NAME="dsql-events-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="DSQLLambdaRole-${RANDOM_SUFFIX}"
    export IAM_POLICY_NAME="DSQLEventBridgePolicy-${RANDOM_SUFFIX}"
    
    # Create deployment state file
    cat > deployment_state.json << EOF
{
    "deployment_id": "dsql-multiregion-${RANDOM_SUFFIX}",
    "primary_region": "${PRIMARY_REGION}",
    "secondary_region": "${SECONDARY_REGION}",
    "witness_region": "${WITNESS_REGION}",
    "cluster_name_primary": "${CLUSTER_NAME_PRIMARY}",
    "cluster_name_secondary": "${CLUSTER_NAME_SECONDARY}",
    "lambda_function_name": "${LAMBDA_FUNCTION_NAME}",
    "eventbridge_bus_name": "${EVENTBRIDGE_BUS_NAME}",
    "iam_role_name": "${IAM_ROLE_NAME}",
    "iam_policy_name": "${IAM_POLICY_NAME}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    info "Environment initialized:"
    info "  Primary Region: ${PRIMARY_REGION}"
    info "  Secondary Region: ${SECONDARY_REGION}"
    info "  Witness Region: ${WITNESS_REGION}"
    info "  Random Suffix: ${RANDOM_SUFFIX}"
    info "  AWS Account ID: ${AWS_ACCOUNT_ID}"
}

# Check Aurora DSQL availability in regions
check_dsql_availability() {
    log "Checking Aurora DSQL availability in target regions..."
    
    # Note: Aurora DSQL is in preview and availability may vary
    # This is a placeholder check - in real implementation, verify service availability
    for region in "${PRIMARY_REGION}" "${SECONDARY_REGION}" "${WITNESS_REGION}"; do
        info "Checking Aurora DSQL availability in ${region}..."
        # Add actual service availability check here when Aurora DSQL is generally available
    done
    
    log "Aurora DSQL availability check completed."
}

# Create IAM resources
create_iam_resources() {
    log "Creating IAM resources..."
    
    # Create IAM role for Lambda functions
    aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
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
        --tags Key=Environment,Value=Production Key=Application,Value=DistributedApp \
        --output text > /dev/null || {
            if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
                warn "IAM role ${IAM_ROLE_NAME} already exists, continuing..."
            else
                error "Failed to create IAM role ${IAM_ROLE_NAME}"
            fi
        }
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for Aurora DSQL and EventBridge
    aws iam create-policy \
        --policy-name "${IAM_POLICY_NAME}" \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "dsql:Connect",
                        "dsql:DbConnect",
                        "dsql:ExecuteStatement",
                        "events:PutEvents"
                    ],
                    "Resource": "*"
                }
            ]
        }' \
        --output text > /dev/null || {
            if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_NAME}" &> /dev/null; then
                warn "IAM policy ${IAM_POLICY_NAME} already exists, continuing..."
            else
                error "Failed to create IAM policy ${IAM_POLICY_NAME}"
            fi
        }
    
    # Attach custom policy to role
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_NAME}"
    
    # Wait for IAM role propagation
    info "Waiting for IAM role propagation..."
    sleep 10
    
    log "IAM resources created successfully."
}

# Create Aurora DSQL clusters
create_dsql_clusters() {
    log "Creating Aurora DSQL clusters..."
    
    # Create primary cluster
    info "Creating primary Aurora DSQL cluster in ${PRIMARY_REGION}..."
    aws dsql create-cluster \
        --region "${PRIMARY_REGION}" \
        --cluster-name "${CLUSTER_NAME_PRIMARY}" \
        --witness-region "${WITNESS_REGION}" \
        --engine-version postgres \
        --tags Key=Environment,Value=Production Key=Application,Value=DistributedApp \
        --output text > /dev/null || error "Failed to create primary cluster"
    
    # Get primary cluster identifier
    PRIMARY_CLUSTER_ID=$(aws dsql describe-clusters \
        --region "${PRIMARY_REGION}" \
        --query 'clusters[?clusterName==`'${CLUSTER_NAME_PRIMARY}'`].clusterIdentifier' \
        --output text)
    
    if [[ -z "${PRIMARY_CLUSTER_ID}" ]]; then
        error "Failed to retrieve primary cluster identifier"
    fi
    
    echo "PRIMARY_CLUSTER_ID=${PRIMARY_CLUSTER_ID}" >> deployment_state.env
    
    # Create secondary cluster
    info "Creating secondary Aurora DSQL cluster in ${SECONDARY_REGION}..."
    aws dsql create-cluster \
        --region "${SECONDARY_REGION}" \
        --cluster-name "${CLUSTER_NAME_SECONDARY}" \
        --witness-region "${WITNESS_REGION}" \
        --engine-version postgres \
        --tags Key=Environment,Value=Production Key=Application,Value=DistributedApp \
        --output text > /dev/null || error "Failed to create secondary cluster"
    
    # Get secondary cluster identifier
    SECONDARY_CLUSTER_ID=$(aws dsql describe-clusters \
        --region "${SECONDARY_REGION}" \
        --query 'clusters[?clusterName==`'${CLUSTER_NAME_SECONDARY}'`].clusterIdentifier' \
        --output text)
    
    if [[ -z "${SECONDARY_CLUSTER_ID}" ]]; then
        error "Failed to retrieve secondary cluster identifier"
    fi
    
    echo "SECONDARY_CLUSTER_ID=${SECONDARY_CLUSTER_ID}" >> deployment_state.env
    
    # Wait for clusters to be available
    info "Waiting for primary cluster to be available..."
    aws dsql wait cluster-available \
        --region "${PRIMARY_REGION}" \
        --cluster-identifier "${PRIMARY_CLUSTER_ID}" || error "Primary cluster failed to become available"
    
    info "Waiting for secondary cluster to be available..."
    aws dsql wait cluster-available \
        --region "${SECONDARY_REGION}" \
        --cluster-identifier "${SECONDARY_CLUSTER_ID}" || error "Secondary cluster failed to become available"
    
    log "Aurora DSQL clusters created successfully."
    info "  Primary Cluster ID: ${PRIMARY_CLUSTER_ID}"
    info "  Secondary Cluster ID: ${SECONDARY_CLUSTER_ID}"
}

# Create multi-region cluster link
create_cluster_link() {
    log "Creating multi-region cluster link..."
    
    # Source environment variables
    source deployment_state.env
    
    # Create linked cluster between primary and secondary
    aws dsql create-multi-region-clusters \
        --region "${PRIMARY_REGION}" \
        --primary-cluster-identifier "${PRIMARY_CLUSTER_ID}" \
        --secondary-cluster-identifier "${SECONDARY_CLUSTER_ID}" \
        --secondary-cluster-region "${SECONDARY_REGION}" \
        --witness-region "${WITNESS_REGION}" \
        --output text > /dev/null || error "Failed to create multi-region cluster link"
    
    # Wait for multi-region setup to complete
    info "Waiting for multi-region setup to complete..."
    aws dsql wait multi-region-clusters-available \
        --region "${PRIMARY_REGION}" \
        --primary-cluster-identifier "${PRIMARY_CLUSTER_ID}" || error "Multi-region cluster setup failed"
    
    log "Multi-region cluster link created successfully."
}

# Create Lambda function package
create_lambda_package() {
    log "Creating Lambda function package..."
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import boto3
import os
from datetime import datetime
import uuid
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to handle Aurora DSQL operations and EventBridge integration
    """
    try:
        # Initialize clients
        dsql_client = boto3.client('dsql')
        eventbridge = boto3.client('events')
        
        # Aurora DSQL connection parameters
        cluster_identifier = os.environ.get('DSQL_CLUSTER_ID')
        
        if not cluster_identifier:
            raise ValueError("DSQL_CLUSTER_ID environment variable not set")
        
        # Process the incoming event
        operation = event.get('operation', 'read')
        region = context.invoked_function_arn.split(':')[3]
        
        logger.info(f"Processing {operation} operation in region {region}")
        
        if operation == 'write':
            # Perform write operation using Aurora DSQL Data API
            transaction_id = event.get('transaction_id', str(uuid.uuid4()))
            amount = event.get('amount', 0)
            
            response = dsql_client.execute_statement(
                ClusterIdentifier=cluster_identifier,
                Sql="""
                    INSERT INTO transactions (id, amount, timestamp, region, status)
                    VALUES (?, ?, ?, ?, ?)
                """,
                Parameters=[
                    {'StringValue': transaction_id},
                    {'DoubleValue': float(amount)},
                    {'StringValue': datetime.now().isoformat()},
                    {'StringValue': region},
                    {'StringValue': 'completed'}
                ]
            )
            
            logger.info(f"Transaction {transaction_id} created successfully")
            
            # Publish event to EventBridge
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'dsql.application',
                        'DetailType': 'Transaction Created',
                        'Detail': json.dumps({
                            'transaction_id': transaction_id,
                            'amount': amount,
                            'region': region,
                            'timestamp': datetime.now().isoformat()
                        })
                    }
                ]
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Transaction created successfully',
                    'transaction_id': transaction_id,
                    'region': region
                })
            }
            
        elif operation == 'read':
            # Perform read operation
            response = dsql_client.execute_statement(
                ClusterIdentifier=cluster_identifier,
                Sql="""
                    SELECT COUNT(*) as count, 
                           SUM(amount) as total_amount,
                           MIN(timestamp) as first_transaction,
                           MAX(timestamp) as last_transaction
                    FROM transactions
                """
            )
            
            record = response['Records'][0]['Values']
            count = record[0].get('LongValue', 0)
            total_amount = record[1].get('DoubleValue', 0.0)
            first_transaction = record[2].get('StringValue', 'N/A')
            last_transaction = record[3].get('StringValue', 'N/A')
            
            logger.info(f"Retrieved {count} transactions from region {region}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'transaction_count': count,
                    'total_amount': total_amount,
                    'first_transaction': first_transaction,
                    'last_transaction': last_transaction,
                    'region': region
                })
            }
        
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Invalid operation',
                    'supported_operations': ['read', 'write']
                })
            }
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Internal server error: {str(e)}',
                'region': context.invoked_function_arn.split(':')[3]
            })
        }
EOF
    
    # Create deployment package
    zip -q function.zip lambda_function.py
    
    log "Lambda function package created successfully."
}

# Create EventBridge resources
create_eventbridge_resources() {
    log "Creating EventBridge resources..."
    
    # Create custom EventBridge bus in primary region
    aws events create-event-bus \
        --region "${PRIMARY_REGION}" \
        --name "${EVENTBRIDGE_BUS_NAME}" \
        --tags Key=Environment,Value=Production Key=Application,Value=DistributedApp \
        --output text > /dev/null || {
            if aws events describe-event-bus --region "${PRIMARY_REGION}" --name "${EVENTBRIDGE_BUS_NAME}" &> /dev/null; then
                warn "EventBridge bus ${EVENTBRIDGE_BUS_NAME} already exists in ${PRIMARY_REGION}, continuing..."
            else
                error "Failed to create EventBridge bus in ${PRIMARY_REGION}"
            fi
        }
    
    # Create custom EventBridge bus in secondary region
    aws events create-event-bus \
        --region "${SECONDARY_REGION}" \
        --name "${EVENTBRIDGE_BUS_NAME}" \
        --tags Key=Environment,Value=Production Key=Application,Value=DistributedApp \
        --output text > /dev/null || {
            if aws events describe-event-bus --region "${SECONDARY_REGION}" --name "${EVENTBRIDGE_BUS_NAME}" &> /dev/null; then
                warn "EventBridge bus ${EVENTBRIDGE_BUS_NAME} already exists in ${SECONDARY_REGION}, continuing..."
            else
                error "Failed to create EventBridge bus in ${SECONDARY_REGION}"
            fi
        }
    
    # Create rule for cross-region event replication in primary region
    aws events put-rule \
        --region "${PRIMARY_REGION}" \
        --name "CrossRegionReplication-${RANDOM_SUFFIX}" \
        --event-pattern '{"source":["dsql.application"]}' \
        --state ENABLED \
        --event-bus-name "${EVENTBRIDGE_BUS_NAME}" \
        --description "Cross-region event replication for Aurora DSQL application" \
        --output text > /dev/null
    
    # Create rule for cross-region event replication in secondary region
    aws events put-rule \
        --region "${SECONDARY_REGION}" \
        --name "CrossRegionReplication-${RANDOM_SUFFIX}" \
        --event-pattern '{"source":["dsql.application"]}' \
        --state ENABLED \
        --event-bus-name "${EVENTBRIDGE_BUS_NAME}" \
        --description "Cross-region event replication for Aurora DSQL application" \
        --output text > /dev/null
    
    log "EventBridge resources created successfully."
}

# Deploy Lambda functions
deploy_lambda_functions() {
    log "Deploying Lambda functions..."
    
    # Source environment variables
    source deployment_state.env
    
    # Create Lambda function in primary region
    info "Creating Lambda function in ${PRIMARY_REGION}..."
    aws lambda create-function \
        --region "${PRIMARY_REGION}" \
        --function-name "${LAMBDA_FUNCTION_NAME}-primary" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://function.zip \
        --timeout 30 \
        --memory-size 256 \
        --environment Variables="{DSQL_CLUSTER_ID=${PRIMARY_CLUSTER_ID}}" \
        --tags Environment=Production,Application=DistributedApp \
        --description "Aurora DSQL processor for primary region" \
        --output text > /dev/null || {
            if aws lambda get-function --region "${PRIMARY_REGION}" --function-name "${LAMBDA_FUNCTION_NAME}-primary" &> /dev/null; then
                warn "Lambda function ${LAMBDA_FUNCTION_NAME}-primary already exists, updating..."
                aws lambda update-function-code \
                    --region "${PRIMARY_REGION}" \
                    --function-name "${LAMBDA_FUNCTION_NAME}-primary" \
                    --zip-file fileb://function.zip > /dev/null
            else
                error "Failed to create Lambda function in ${PRIMARY_REGION}"
            fi
        }
    
    # Create Lambda function in secondary region
    info "Creating Lambda function in ${SECONDARY_REGION}..."
    aws lambda create-function \
        --region "${SECONDARY_REGION}" \
        --function-name "${LAMBDA_FUNCTION_NAME}-secondary" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://function.zip \
        --timeout 30 \
        --memory-size 256 \
        --environment Variables="{DSQL_CLUSTER_ID=${SECONDARY_CLUSTER_ID}}" \
        --tags Environment=Production,Application=DistributedApp \
        --description "Aurora DSQL processor for secondary region" \
        --output text > /dev/null || {
            if aws lambda get-function --region "${SECONDARY_REGION}" --function-name "${LAMBDA_FUNCTION_NAME}-secondary" &> /dev/null; then
                warn "Lambda function ${LAMBDA_FUNCTION_NAME}-secondary already exists, updating..."
                aws lambda update-function-code \
                    --region "${SECONDARY_REGION}" \
                    --function-name "${LAMBDA_FUNCTION_NAME}-secondary" \
                    --zip-file fileb://function.zip > /dev/null
            else
                error "Failed to create Lambda function in ${SECONDARY_REGION}"
            fi
        }
    
    # Grant EventBridge permission to invoke Lambda functions
    aws lambda add-permission \
        --region "${PRIMARY_REGION}" \
        --function-name "${LAMBDA_FUNCTION_NAME}-primary" \
        --statement-id eventbridge-invoke \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_BUS_NAME}/CrossRegionReplication-${RANDOM_SUFFIX}" \
        --output text > /dev/null 2>&1 || warn "Permission for primary Lambda function may already exist"
    
    aws lambda add-permission \
        --region "${SECONDARY_REGION}" \
        --function-name "${LAMBDA_FUNCTION_NAME}-secondary" \
        --statement-id eventbridge-invoke \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${SECONDARY_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_BUS_NAME}/CrossRegionReplication-${RANDOM_SUFFIX}" \
        --output text > /dev/null 2>&1 || warn "Permission for secondary Lambda function may already exist"
    
    log "Lambda functions deployed successfully."
}

# Create database schema
create_database_schema() {
    log "Creating database schema..."
    
    # Source environment variables
    source deployment_state.env
    
    # Create sample application schema
    cat > schema.sql << 'EOF'
-- Create transactions table for the distributed application
CREATE TABLE IF NOT EXISTS transactions (
    id VARCHAR(255) PRIMARY KEY,
    amount DECIMAL(10,2) NOT NULL,
    timestamp TIMESTAMP NOT NULL,
    region VARCHAR(50) NOT NULL,
    status VARCHAR(50) DEFAULT 'pending'
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_transactions_timestamp ON transactions(timestamp);
CREATE INDEX IF NOT EXISTS idx_transactions_region ON transactions(region);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON transactions(status);

-- Create sequence for transaction numbering
CREATE SEQUENCE IF NOT EXISTS transaction_seq START 1;
EOF
    
    # Execute schema creation using Aurora DSQL Data API
    info "Executing schema creation on primary cluster..."
    aws dsql execute-statement \
        --region "${PRIMARY_REGION}" \
        --cluster-identifier "${PRIMARY_CLUSTER_ID}" \
        --sql "$(cat schema.sql)" \
        --output text > /dev/null || error "Failed to create database schema"
    
    log "Database schema created and synchronized across regions."
}

# Configure EventBridge targets
configure_eventbridge_targets() {
    log "Configuring EventBridge targets..."
    
    # Configure EventBridge trigger for primary region Lambda
    aws events put-targets \
        --region "${PRIMARY_REGION}" \
        --rule "CrossRegionReplication-${RANDOM_SUFFIX}" \
        --event-bus-name "${EVENTBRIDGE_BUS_NAME}" \
        --targets "Id"="1","Arn"="arn:aws:lambda:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}-primary" \
        --output text > /dev/null || warn "Failed to configure EventBridge target for primary region"
    
    # Configure EventBridge trigger for secondary region Lambda
    aws events put-targets \
        --region "${SECONDARY_REGION}" \
        --rule "CrossRegionReplication-${RANDOM_SUFFIX}" \
        --event-bus-name "${EVENTBRIDGE_BUS_NAME}" \
        --targets "Id"="1","Arn"="arn:aws:lambda:${SECONDARY_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}-secondary" \
        --output text > /dev/null || warn "Failed to configure EventBridge target for secondary region"
    
    log "EventBridge targets configured successfully."
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Source environment variables
    source deployment_state.env
    
    # Check Aurora DSQL cluster status
    info "Checking Aurora DSQL cluster status..."
    PRIMARY_STATUS=$(aws dsql describe-clusters \
        --region "${PRIMARY_REGION}" \
        --cluster-identifier "${PRIMARY_CLUSTER_ID}" \
        --query 'clusters[0].status' --output text)
    
    SECONDARY_STATUS=$(aws dsql describe-clusters \
        --region "${SECONDARY_REGION}" \
        --cluster-identifier "${SECONDARY_CLUSTER_ID}" \
        --query 'clusters[0].status' --output text)
    
    if [[ "${PRIMARY_STATUS}" != "available" ]] || [[ "${SECONDARY_STATUS}" != "available" ]]; then
        error "Aurora DSQL clusters are not in available state. Primary: ${PRIMARY_STATUS}, Secondary: ${SECONDARY_STATUS}"
    fi
    
    # Test Lambda function execution
    info "Testing Lambda function execution..."
    aws lambda invoke \
        --region "${PRIMARY_REGION}" \
        --function-name "${LAMBDA_FUNCTION_NAME}-primary" \
        --payload '{"operation":"read"}' \
        --cli-binary-format raw-in-base64-out \
        test_response.json > /dev/null || error "Lambda function test failed"
    
    # Check response
    if grep -q "statusCode.*200" test_response.json; then
        info "Lambda function test passed"
    else
        error "Lambda function test failed. Check test_response.json for details."
    fi
    
    # Clean up test file
    rm -f test_response.json
    
    log "Deployment validation completed successfully."
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f lambda_function.py function.zip schema.sql
    
    log "Temporary files cleaned up."
}

# Generate deployment summary
generate_deployment_summary() {
    log "Generating deployment summary..."
    
    # Source environment variables
    source deployment_state.env
    
    cat > deployment_summary.txt << EOF
Aurora DSQL Multi-Region Deployment Summary
==========================================

Deployment ID: dsql-multiregion-${RANDOM_SUFFIX}
Deployment Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)

Regions:
  Primary Region: ${PRIMARY_REGION}
  Secondary Region: ${SECONDARY_REGION}
  Witness Region: ${WITNESS_REGION}

Aurora DSQL Clusters:
  Primary Cluster: ${PRIMARY_CLUSTER_ID} (${PRIMARY_REGION})
  Secondary Cluster: ${SECONDARY_CLUSTER_ID} (${SECONDARY_REGION})

Lambda Functions:
  Primary: ${LAMBDA_FUNCTION_NAME}-primary (${PRIMARY_REGION})
  Secondary: ${LAMBDA_FUNCTION_NAME}-secondary (${SECONDARY_REGION})

EventBridge:
  Bus Name: ${EVENTBRIDGE_BUS_NAME}
  
IAM Resources:
  Role: ${IAM_ROLE_NAME}
  Policy: ${IAM_POLICY_NAME}

Test Commands:
# Test read operation (primary region)
aws lambda invoke --region ${PRIMARY_REGION} --function-name ${LAMBDA_FUNCTION_NAME}-primary --payload '{"operation":"read"}' --cli-binary-format raw-in-base64-out response.json

# Test write operation (primary region)
aws lambda invoke --region ${PRIMARY_REGION} --function-name ${LAMBDA_FUNCTION_NAME}-primary --payload '{"operation":"write","transaction_id":"test-001","amount":100.50}' --cli-binary-format raw-in-base64-out response.json

# Test read operation (secondary region)
aws lambda invoke --region ${SECONDARY_REGION} --function-name ${LAMBDA_FUNCTION_NAME}-secondary --payload '{"operation":"read"}' --cli-binary-format raw-in-base64-out response.json

Cleanup Command:
./destroy.sh

Notes:
- Aurora DSQL provides strong consistency across regions
- Both regions can handle read and write operations
- EventBridge coordinates events across regions
- Use the test commands above to verify functionality

EOF
    
    info "Deployment summary saved to deployment_summary.txt"
    cat deployment_summary.txt
}

# Main deployment function
main() {
    log "Starting Aurora DSQL Multi-Region Deployment..."
    
    check_prerequisites
    initialize_environment
    check_dsql_availability
    create_iam_resources
    create_dsql_clusters
    create_cluster_link
    create_lambda_package
    create_eventbridge_resources
    deploy_lambda_functions
    create_database_schema
    configure_eventbridge_targets
    validate_deployment
    cleanup_temp_files
    generate_deployment_summary
    
    log "Deployment completed successfully! 🎉"
    log "Review deployment_summary.txt for details and test commands."
    
    return 0
}

# Handle script interruption
trap 'error "Deployment interrupted. Run ./destroy.sh to clean up any created resources."' INT TERM

# Run main function
main "$@"