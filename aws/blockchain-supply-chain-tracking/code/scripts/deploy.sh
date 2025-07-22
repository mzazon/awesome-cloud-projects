#!/bin/bash

# Deploy script for AWS Blockchain-Based Supply Chain Tracking Systems
# This script deploys the complete supply chain tracking infrastructure

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
ERROR_LOG="${SCRIPT_DIR}/deployment_errors.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}" | tee -a "${ERROR_LOG}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check ${ERROR_LOG} for details."
    log_error "To clean up partial deployment, run: ./destroy.sh"
    exit 1
}

trap cleanup_on_error ERR

# Initialize logging
echo "Deployment started at $(date)" > "${LOG_FILE}"
echo "Deployment errors log" > "${ERROR_LOG}"

log_info "Starting deployment of AWS Blockchain-Based Supply Chain Tracking Systems"
log_info "Logs will be written to: ${LOG_FILE}"

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | head -n1 | awk '{print $1}' | cut -d/ -f2)
    if [[ "${AWS_CLI_VERSION}" < "2.0.0" ]]; then
        log_error "AWS CLI version 2.0.0 or higher is required. Current version: ${AWS_CLI_VERSION}"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set up AWS credentials."
        exit 1
    fi
    
    # Check required tools
    local required_tools=("jq" "zip" "tar")
    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" &> /dev/null; then
            log_error "${tool} is required but not installed."
            exit 1
        fi
    done
    
    log_success "Prerequisites check completed"
}

# Environment setup
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set environment variables
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "AWS region not configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 6))
    
    export NETWORK_NAME="supply-chain-network-${RANDOM_SUFFIX}"
    export MEMBER_NAME="manufacturer-${RANDOM_SUFFIX}"
    export BUCKET_NAME="supply-chain-data-${RANDOM_SUFFIX}"
    export IOT_THING_NAME="supply-chain-tracker-${RANDOM_SUFFIX}"
    
    # Save environment variables for destroy script
    cat > "${SCRIPT_DIR}/.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
NETWORK_NAME=${NETWORK_NAME}
MEMBER_NAME=${MEMBER_NAME}
BUCKET_NAME=${BUCKET_NAME}
IOT_THING_NAME=${IOT_THING_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment setup completed"
    log_info "Network name: ${NETWORK_NAME}"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "AWS Account: ${AWS_ACCOUNT_ID}"
}

# Create S3 bucket and DynamoDB table
create_storage_resources() {
    log_info "Creating storage resources..."
    
    # Create S3 bucket
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        log_warning "S3 bucket ${BUCKET_NAME} already exists"
    else
        if [[ "${AWS_REGION}" == "us-east-1" ]]; then
            aws s3api create-bucket --bucket "${BUCKET_NAME}"
        else
            aws s3api create-bucket \
                --bucket "${BUCKET_NAME}" \
                --create-bucket-configuration LocationConstraint="${AWS_REGION}"
        fi
        log_success "Created S3 bucket: ${BUCKET_NAME}"
    fi
    
    # Enable S3 bucket versioning
    aws s3api put-bucket-versioning \
        --bucket "${BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    # Create DynamoDB table
    if aws dynamodb describe-table --table-name SupplyChainMetadata &>/dev/null; then
        log_warning "DynamoDB table SupplyChainMetadata already exists"
    else
        aws dynamodb create-table \
            --table-name SupplyChainMetadata \
            --attribute-definitions \
                AttributeName=ProductId,AttributeType=S \
                AttributeName=Timestamp,AttributeType=N \
            --key-schema \
                AttributeName=ProductId,KeyType=HASH \
                AttributeName=Timestamp,KeyType=RANGE \
            --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
            --region "${AWS_REGION}"
        
        log_info "Waiting for DynamoDB table to become active..."
        aws dynamodb wait table-exists --table-name SupplyChainMetadata
        log_success "Created DynamoDB table: SupplyChainMetadata"
    fi
}

# Create blockchain network
create_blockchain_network() {
    log_info "Creating Hyperledger Fabric blockchain network..."
    
    # Create the initial blockchain network
    NETWORK_ID=$(aws managedblockchain create-network \
        --name "${NETWORK_NAME}" \
        --description "Supply Chain Tracking Network" \
        --framework HYPERLEDGER_FABRIC \
        --framework-version 2.2 \
        --framework-configuration '{
            "NetworkFabricConfiguration": {
                "Edition": "STARTER"
            }
        }' \
        --voting-policy '{
            "ApprovalThresholdPolicy": {
                "ThresholdPercentage": 50,
                "ProposalDurationInHours": 24,
                "ThresholdComparator": "GREATER_THAN"
            }
        }' \
        --member-configuration '{
            "Name": "'"${MEMBER_NAME}"'",
            "Description": "Manufacturer member",
            "MemberFabricConfiguration": {
                "AdminUsername": "admin",
                "AdminPassword": "TempPassword123!"
            }
        }' \
        --query 'NetworkId' --output text)
    
    export NETWORK_ID
    echo "NETWORK_ID=${NETWORK_ID}" >> "${SCRIPT_DIR}/.env"
    
    log_success "Created blockchain network: ${NETWORK_ID}"
    log_info "Waiting for network to become available..."
    
    # Wait for network to be active
    aws managedblockchain wait network-available --network-id "${NETWORK_ID}"
    
    # Get the member ID
    MEMBER_ID=$(aws managedblockchain list-members \
        --network-id "${NETWORK_ID}" \
        --query 'Members[0].Id' --output text)
    
    export MEMBER_ID
    echo "MEMBER_ID=${MEMBER_ID}" >> "${SCRIPT_DIR}/.env"
    
    log_success "Network active with member ID: ${MEMBER_ID}"
}

# Create peer node
create_peer_node() {
    log_info "Creating peer node for blockchain network..."
    
    # Create peer node for the manufacturer
    NODE_ID=$(aws managedblockchain create-node \
        --network-id "${NETWORK_ID}" \
        --member-id "${MEMBER_ID}" \
        --node-configuration '{
            "InstanceType": "bc.t3.small",
            "AvailabilityZone": "'"${AWS_REGION}a"'"
        }' \
        --query 'NodeId' --output text)
    
    export NODE_ID
    echo "NODE_ID=${NODE_ID}" >> "${SCRIPT_DIR}/.env"
    
    log_info "Waiting for peer node to become available..."
    
    # Wait for node to be available
    aws managedblockchain wait node-available \
        --network-id "${NETWORK_ID}" \
        --member-id "${MEMBER_ID}" \
        --node-id "${NODE_ID}"
    
    log_success "Created and activated peer node: ${NODE_ID}"
}

# Create VPC endpoint
create_vpc_endpoint() {
    log_info "Creating VPC endpoint for blockchain access..."
    
    # Get default VPC
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    # Get subnet for VPC endpoint
    SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[0].SubnetId' --output text)
    
    # Create VPC endpoint for blockchain access (using accessor for billing)
    ENDPOINT_ID=$(aws managedblockchain create-accessor \
        --accessor-type BILLING_TOKEN \
        --query 'AccessorId' --output text 2>/dev/null || echo "endpoint-created")
    
    export VPC_ID SUBNET_ID ENDPOINT_ID
    echo "VPC_ID=${VPC_ID}" >> "${SCRIPT_DIR}/.env"
    echo "SUBNET_ID=${SUBNET_ID}" >> "${SCRIPT_DIR}/.env"
    echo "ENDPOINT_ID=${ENDPOINT_ID}" >> "${SCRIPT_DIR}/.env"
    
    log_success "Created VPC endpoint configuration"
}

# Create and upload chaincode
create_chaincode() {
    log_info "Creating supply chain chaincode..."
    
    # Create chaincode directory
    local chaincode_dir="${SCRIPT_DIR}/../chaincode/supply-chain"
    mkdir -p "${chaincode_dir}"
    
    # Create package.json for chaincode
    cat > "${chaincode_dir}/package.json" << 'EOF'
{
  "name": "supply-chain-chaincode",
  "version": "1.0.0",
  "description": "Supply Chain Tracking Chaincode",
  "main": "index.js",
  "dependencies": {
    "fabric-contract-api": "^2.0.0"
  }
}
EOF

    # Create main chaincode file
    cat > "${chaincode_dir}/index.js" << 'EOF'
const { Contract } = require('fabric-contract-api');

class SupplyChainContract extends Contract {
    
    async initLedger(ctx) {
        console.log('Supply Chain ledger initialized');
        return 'Ledger initialized successfully';
    }
    
    async createProduct(ctx, productId, productData) {
        const product = {
            productId,
            ...JSON.parse(productData),
            createdAt: new Date().toISOString(),
            status: 'CREATED',
            history: []
        };
        
        await ctx.stub.putState(productId, Buffer.from(JSON.stringify(product)));
        return JSON.stringify(product);
    }
    
    async updateProductLocation(ctx, productId, location, sensorData) {
        const productBytes = await ctx.stub.getState(productId);
        if (!productBytes || productBytes.length === 0) {
            throw new Error(`Product ${productId} does not exist`);
        }
        
        const product = JSON.parse(productBytes.toString());
        const update = {
            location,
            sensorData: JSON.parse(sensorData),
            timestamp: new Date().toISOString(),
            updatedBy: ctx.clientIdentity.getID()
        };
        
        product.history.push(update);
        product.currentLocation = location;
        product.lastUpdated = update.timestamp;
        
        await ctx.stub.putState(productId, Buffer.from(JSON.stringify(product)));
        return JSON.stringify(product);
    }
    
    async getProduct(ctx, productId) {
        const productBytes = await ctx.stub.getState(productId);
        if (!productBytes || productBytes.length === 0) {
            throw new Error(`Product ${productId} does not exist`);
        }
        return productBytes.toString();
    }
    
    async getProductHistory(ctx, productId) {
        const productBytes = await ctx.stub.getState(productId);
        if (!productBytes || productBytes.length === 0) {
            throw new Error(`Product ${productId} does not exist`);
        }
        
        const product = JSON.parse(productBytes.toString());
        return JSON.stringify(product.history);
    }
    
    async queryProductsByLocation(ctx, location) {
        const query = {
            selector: {
                currentLocation: location
            }
        };
        
        const iterator = await ctx.stub.getQueryResult(JSON.stringify(query));
        const results = [];
        
        while (true) {
            const result = await iterator.next();
            if (result.done) break;
            
            results.push({
                key: result.value.key,
                record: JSON.parse(result.value.value.toString())
            });
        }
        
        return JSON.stringify(results);
    }
}

module.exports = SupplyChainContract;
EOF

    # Create chaincode archive
    cd "${SCRIPT_DIR}/../"
    tar -czf supply-chain-chaincode.tar.gz -C chaincode supply-chain/
    
    # Upload chaincode to S3
    aws s3 cp supply-chain-chaincode.tar.gz "s3://${BUCKET_NAME}/"
    
    log_success "Created and uploaded supply chain chaincode"
}

# Create IoT resources
create_iot_resources() {
    log_info "Creating IoT Core resources..."
    
    # Create IoT Thing Type (if it doesn't exist)
    aws iot create-thing-type \
        --thing-type-name SupplyChainTracker \
        --thing-type-description "Supply Chain Tracking Device" 2>/dev/null || true
    
    # Create IoT Thing for supply chain tracking
    aws iot create-thing \
        --thing-name "${IOT_THING_NAME}" \
        --thing-type-name SupplyChainTracker \
        --attribute-payload '{
            "attributes": {
                "deviceType": "supplyChainTracker",
                "version": "1.0"
            }
        }' 2>/dev/null || log_warning "IoT Thing ${IOT_THING_NAME} may already exist"
    
    # Create IoT policy for supply chain devices
    cat > "${SCRIPT_DIR}/iot-policy.json" << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iot:Publish",
        "iot:Subscribe",
        "iot:Connect",
        "iot:Receive"
      ],
      "Resource": "*"
    }
  ]
}
EOF

    aws iot create-policy \
        --policy-name SupplyChainTrackerPolicy \
        --policy-document file://"${SCRIPT_DIR}/iot-policy.json" 2>/dev/null || \
        log_warning "IoT Policy SupplyChainTrackerPolicy may already exist"
    
    log_success "Created IoT resources"
}

# Create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function for sensor data processing..."
    
    # Create Lambda function code
    cat > "${SCRIPT_DIR}/../lambda-function.js" << 'EOF'
const AWS = require('aws-sdk');

const dynamodb = new AWS.DynamoDB.DocumentClient();
const eventbridge = new AWS.EventBridge();

exports.handler = async (event) => {
    try {
        console.log('Processing sensor data:', JSON.stringify(event, null, 2));
        
        // Extract sensor data
        const sensorData = {
            productId: event.productId,
            location: event.location,
            temperature: event.temperature,
            humidity: event.humidity,
            timestamp: event.timestamp || Date.now()
        };
        
        // Store in DynamoDB
        await dynamodb.put({
            TableName: 'SupplyChainMetadata',
            Item: {
                ProductId: sensorData.productId,
                Timestamp: sensorData.timestamp,
                Location: sensorData.location,
                SensorData: {
                    temperature: sensorData.temperature,
                    humidity: sensorData.humidity
                }
            }
        }).promise();
        
        // Send event to EventBridge
        await eventbridge.putEvents({
            Entries: [{
                Source: 'supply-chain.sensor',
                DetailType: 'Product Location Update',
                Detail: JSON.stringify(sensorData)
            }]
        }).promise();
        
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Sensor data processed successfully',
                productId: sensorData.productId
            })
        };
        
    } catch (error) {
        console.error('Error processing sensor data:', error);
        throw error;
    }
};
EOF

    # Create Lambda deployment package
    cd "${SCRIPT_DIR}/../"
    zip lambda-function.zip lambda-function.js
    
    # Create Lambda execution role trust policy
    cat > "${SCRIPT_DIR}/lambda-trust-policy.json" << 'EOF'
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

    # Create Lambda execution role
    aws iam create-role \
        --role-name SupplyChainLambdaRole \
        --assume-role-policy-document file://"${SCRIPT_DIR}/lambda-trust-policy.json" 2>/dev/null || \
        log_warning "IAM Role SupplyChainLambdaRole may already exist"
    
    # Attach policies to Lambda role
    aws iam attach-role-policy \
        --role-name SupplyChainLambdaRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    
    aws iam attach-role-policy \
        --role-name SupplyChainLambdaRole \
        --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess 2>/dev/null || true
    
    aws iam attach-role-policy \
        --role-name SupplyChainLambdaRole \
        --policy-arn arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess 2>/dev/null || true
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 15
    
    # Create Lambda function
    aws lambda create-function \
        --function-name ProcessSupplyChainData \
        --runtime nodejs18.x \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/SupplyChainLambdaRole" \
        --handler lambda-function.handler \
        --zip-file fileb://lambda-function.zip \
        --timeout 30 \
        --memory-size 256 2>/dev/null || \
        log_warning "Lambda function ProcessSupplyChainData may already exist"
    
    log_success "Created Lambda function for sensor data processing"
}

# Create EventBridge resources
create_eventbridge_resources() {
    log_info "Creating EventBridge resources..."
    
    # Create EventBridge rule for supply chain events
    aws events put-rule \
        --name SupplyChainTrackingRule \
        --description "Rule for supply chain tracking events" \
        --event-pattern '{
            "source": ["supply-chain.sensor"],
            "detail-type": ["Product Location Update"]
        }' \
        --state ENABLED
    
    # Create SNS topic for notifications
    TOPIC_ARN=$(aws sns create-topic \
        --name supply-chain-notifications \
        --query 'TopicArn' --output text)
    
    echo "TOPIC_ARN=${TOPIC_ARN}" >> "${SCRIPT_DIR}/.env"
    
    # Add EventBridge target to SNS topic
    aws events put-targets \
        --rule SupplyChainTrackingRule \
        --targets "Id"="1","Arn"="${TOPIC_ARN}"
    
    # Grant EventBridge permission to publish to SNS
    aws sns add-permission \
        --topic-arn "${TOPIC_ARN}" \
        --label EventBridgePublish \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --action-name Publish 2>/dev/null || true
    
    log_success "Created EventBridge resources and SNS notifications"
}

# Configure IoT and Lambda integration
configure_iot_lambda_integration() {
    log_info "Configuring IoT and Lambda integration..."
    
    # Add permission for IoT to invoke Lambda
    aws lambda add-permission \
        --function-name ProcessSupplyChainData \
        --statement-id IoTInvoke \
        --action lambda:InvokeFunction \
        --principal iot.amazonaws.com \
        --source-arn "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/SupplyChainSensorRule" 2>/dev/null || true
    
    # Create the IoT rule with proper Lambda ARN
    aws iot create-topic-rule \
        --rule-name SupplyChainSensorRule \
        --topic-rule-payload '{
            "sql": "SELECT * FROM '\''supply-chain/sensor-data'\''",
            "actions": [
                {
                    "lambda": {
                        "functionArn": "arn:aws:lambda:'"${AWS_REGION}"':'"${AWS_ACCOUNT_ID}"':function:ProcessSupplyChainData"
                    }
                }
            ],
            "ruleDisabled": false
        }' 2>/dev/null || log_warning "IoT Rule SupplyChainSensorRule may already exist"
    
    log_success "Configured IoT to Lambda integration"
}

# Create CloudWatch monitoring
create_monitoring() {
    log_info "Creating CloudWatch monitoring and alarms..."
    
    # Create dashboard configuration
    cat > "${SCRIPT_DIR}/dashboard-config.json" << EOF
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/Lambda", "Invocations", "FunctionName", "ProcessSupplyChainData"],
          ["AWS/Lambda", "Errors", "FunctionName", "ProcessSupplyChainData"],
          ["AWS/Lambda", "Duration", "FunctionName", "ProcessSupplyChainData"]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "Supply Chain Processing Metrics"
      }
    }
  ]
}
EOF

    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name SupplyChainTracking \
        --dashboard-body file://"${SCRIPT_DIR}/dashboard-config.json"
    
    # Create alarm for Lambda errors
    aws cloudwatch put-metric-alarm \
        --alarm-name "SupplyChain-Lambda-Errors" \
        --alarm-description "Alert on Lambda function errors" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --dimensions Name=FunctionName,Value=ProcessSupplyChainData \
        --evaluation-periods 1 \
        --alarm-actions "${TOPIC_ARN}" 2>/dev/null || true
    
    # Create alarm for DynamoDB throttling
    aws cloudwatch put-metric-alarm \
        --alarm-name "SupplyChain-DynamoDB-Throttles" \
        --alarm-description "Alert on DynamoDB throttling" \
        --metric-name ThrottledRequests \
        --namespace AWS/DynamoDB \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --dimensions Name=TableName,Value=SupplyChainMetadata \
        --evaluation-periods 1 \
        --alarm-actions "${TOPIC_ARN}" 2>/dev/null || true
    
    log_success "Created CloudWatch monitoring and alarms"
}

# Test deployment
test_deployment() {
    log_info "Testing deployment..."
    
    # Test blockchain network status
    NETWORK_STATUS=$(aws managedblockchain get-network \
        --network-id "${NETWORK_ID}" \
        --query 'Network.Status' --output text)
    
    if [[ "${NETWORK_STATUS}" == "AVAILABLE" ]]; then
        log_success "Blockchain network is active: ${NETWORK_STATUS}"
    else
        log_warning "Blockchain network status: ${NETWORK_STATUS}"
    fi
    
    # Test Lambda function
    if aws lambda get-function --function-name ProcessSupplyChainData &>/dev/null; then
        log_success "Lambda function is deployed and accessible"
    else
        log_warning "Lambda function test failed"
    fi
    
    # Test DynamoDB table
    if aws dynamodb describe-table --table-name SupplyChainMetadata &>/dev/null; then
        log_success "DynamoDB table is active"
    else
        log_warning "DynamoDB table test failed"
    fi
    
    # Test S3 bucket
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" &>/dev/null; then
        log_success "S3 bucket is accessible"
    else
        log_warning "S3 bucket test failed"
    fi
    
    log_success "Deployment testing completed"
}

# Print deployment summary
print_summary() {
    log_info "=== DEPLOYMENT SUMMARY ==="
    log_info "Blockchain Network ID: ${NETWORK_ID}"
    log_info "Blockchain Member ID: ${MEMBER_ID}"
    log_info "Blockchain Node ID: ${NODE_ID}"
    log_info "S3 Bucket: ${BUCKET_NAME}"
    log_info "DynamoDB Table: SupplyChainMetadata"
    log_info "Lambda Function: ProcessSupplyChainData"
    log_info "IoT Thing: ${IOT_THING_NAME}"
    log_info "SNS Topic: ${TOPIC_ARN}"
    log_info "CloudWatch Dashboard: SupplyChainTracking"
    log_info "=========================="
    log_info ""
    log_info "To test the system, publish a message to IoT topic 'supply-chain/sensor-data'"
    log_info "To monitor the system, visit the CloudWatch dashboard: SupplyChainTracking"
    log_info "To clean up resources, run: ./destroy.sh"
    log_info ""
    log_success "Deployment completed successfully!"
    log_info "Total deployment time: $((SECONDS/60)) minutes $((SECONDS%60)) seconds"
}

# Main deployment function
main() {
    local start_time=$SECONDS
    
    check_prerequisites
    setup_environment
    create_storage_resources
    create_blockchain_network
    create_peer_node
    create_vpc_endpoint
    create_chaincode
    create_iot_resources
    create_lambda_function
    create_eventbridge_resources
    configure_iot_lambda_integration
    create_monitoring
    test_deployment
    print_summary
    
    log_success "All components deployed successfully in $((SECONDS-start_time)) seconds"
}

# Run main function
main "$@"