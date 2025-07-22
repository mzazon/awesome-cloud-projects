#!/bin/bash

# Deploy script for Ethereum-Compatible Smart Contracts with Managed Blockchain
# This script automates the deployment of the complete infrastructure

set -e
set -o pipefail

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
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        error "Node.js is not installed. Please install Node.js 18+ first."
    fi
    
    # Check if npm is installed
    if ! command -v npm &> /dev/null; then
        error "npm is not installed. Please install npm first."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq first."
    fi
    
    # Check if zip is installed
    if ! command -v zip &> /dev/null; then
        error "zip is not installed. Please install zip first."
    fi
    
    log "Prerequisites check completed successfully"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not configured. Please set your AWS region."
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        error "Failed to get AWS account ID"
    fi
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export NODE_ID="eth-node-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="eth-contract-manager-${RANDOM_SUFFIX}"
    export API_NAME="ethereum-api-${RANDOM_SUFFIX}"
    export BUCKET_NAME="ethereum-artifacts-${AWS_ACCOUNT_ID}-${RANDOM_SUFFIX}"
    export DEPLOYMENT_LOG_FILE="/tmp/ethereum-deployment-${RANDOM_SUFFIX}.log"
    
    info "Environment initialized:"
    info "  AWS Region: ${AWS_REGION}"
    info "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    info "  Random Suffix: ${RANDOM_SUFFIX}"
    info "  Node ID: ${NODE_ID}"
    info "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    info "  API Name: ${API_NAME}"
    info "  Bucket Name: ${BUCKET_NAME}"
    
    # Create deployment log file
    echo "Deployment started at $(date)" > "$DEPLOYMENT_LOG_FILE"
    echo "Environment variables:" >> "$DEPLOYMENT_LOG_FILE"
    echo "  AWS_REGION=${AWS_REGION}" >> "$DEPLOYMENT_LOG_FILE"
    echo "  AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}" >> "$DEPLOYMENT_LOG_FILE"
    echo "  RANDOM_SUFFIX=${RANDOM_SUFFIX}" >> "$DEPLOYMENT_LOG_FILE"
}

# Create S3 bucket for contract artifacts
create_s3_bucket() {
    log "Creating S3 bucket for contract artifacts..."
    
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        warn "S3 bucket ${BUCKET_NAME} already exists"
    else
        if [ "$AWS_REGION" == "us-east-1" ]; then
            aws s3api create-bucket --bucket "$BUCKET_NAME" || error "Failed to create S3 bucket"
        else
            aws s3api create-bucket --bucket "$BUCKET_NAME" \
                --create-bucket-configuration LocationConstraint="$AWS_REGION" || error "Failed to create S3 bucket"
        fi
        log "S3 bucket created successfully: ${BUCKET_NAME}"
    fi
    
    # Enable versioning on the bucket
    aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled || warn "Failed to enable versioning"
    
    echo "S3 bucket created: ${BUCKET_NAME}" >> "$DEPLOYMENT_LOG_FILE"
}

# Create IAM role for Lambda
create_lambda_role() {
    log "Creating IAM role for Lambda function..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${LAMBDA_FUNCTION_NAME}-role" >/dev/null 2>&1; then
        warn "IAM role ${LAMBDA_FUNCTION_NAME}-role already exists"
    else
        # Create IAM role
        aws iam create-role \
            --role-name "${LAMBDA_FUNCTION_NAME}-role" \
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
            }' || error "Failed to create IAM role"
        
        log "IAM role created successfully"
    fi
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || warn "Failed to attach basic execution policy"
    
    # Create custom policy for Managed Blockchain and S3 access
    POLICY_DOCUMENT='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "managedblockchain:*",
                    "ssm:GetParameter",
                    "ssm:GetParameters"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "s3:GetObject",
                    "s3:PutObject"
                ],
                "Resource": "arn:aws:s3:::'"${BUCKET_NAME}"'/*"
            }
        ]
    }'
    
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_FUNCTION_NAME}-blockchain-policy" >/dev/null 2>&1; then
        warn "IAM policy ${LAMBDA_FUNCTION_NAME}-blockchain-policy already exists"
    else
        aws iam create-policy \
            --policy-name "${LAMBDA_FUNCTION_NAME}-blockchain-policy" \
            --policy-document "$POLICY_DOCUMENT" || error "Failed to create blockchain policy"
        
        log "Blockchain policy created successfully"
    fi
    
    # Attach the blockchain policy to Lambda role
    aws iam attach-role-policy \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_FUNCTION_NAME}-blockchain-policy" || warn "Failed to attach blockchain policy"
    
    # Wait for role to be ready
    sleep 10
    
    echo "IAM role created: ${LAMBDA_FUNCTION_NAME}-role" >> "$DEPLOYMENT_LOG_FILE"
}

# Create Ethereum node on Managed Blockchain
create_ethereum_node() {
    log "Creating Ethereum node on Amazon Managed Blockchain..."
    
    # Create Ethereum node
    NODE_RESPONSE=$(aws managedblockchain create-node \
        --node-configuration '{
            "InstanceType":"bc.t3.xlarge",
            "AvailabilityZone":"'${AWS_REGION}a'"
        }' \
        --network-id n-ethereum-mainnet \
        --output json 2>/dev/null) || error "Failed to create Ethereum node"
    
    export NODE_ID=$(echo "$NODE_RESPONSE" | jq -r '.NodeId')
    info "Ethereum node creation initiated: ${NODE_ID}"
    
    # Wait for node to become available (this can take 30-60 minutes)
    info "Waiting for Ethereum node to become available (this may take 30-60 minutes)..."
    
    local max_attempts=120  # 2 hours maximum
    local attempt=0
    local status=""
    
    while [ $attempt -lt $max_attempts ]; do
        status=$(aws managedblockchain get-node \
            --network-id n-ethereum-mainnet \
            --node-id "$NODE_ID" \
            --query 'Node.Status' --output text 2>/dev/null || echo "UNKNOWN")
        
        if [ "$status" == "AVAILABLE" ]; then
            log "Ethereum node is now available"
            break
        elif [ "$status" == "FAILED" ]; then
            error "Ethereum node creation failed"
        else
            info "Node status: ${status}. Waiting..."
            sleep 60
        fi
        
        ((attempt++))
    done
    
    if [ "$status" != "AVAILABLE" ]; then
        error "Timeout waiting for Ethereum node to become available"
    fi
    
    echo "Ethereum node created: ${NODE_ID}" >> "$DEPLOYMENT_LOG_FILE"
}

# Configure node endpoints
configure_node_endpoints() {
    log "Configuring node endpoints..."
    
    # Get node details including endpoints
    NODE_DETAILS=$(aws managedblockchain get-node \
        --network-id n-ethereum-mainnet \
        --node-id "$NODE_ID" \
        --output json) || error "Failed to get node details"
    
    export HTTP_ENDPOINT=$(echo "$NODE_DETAILS" | jq -r '.Node.HttpEndpoint')
    export WS_ENDPOINT=$(echo "$NODE_DETAILS" | jq -r '.Node.WebsocketEndpoint')
    
    info "HTTP Endpoint: ${HTTP_ENDPOINT}"
    info "WebSocket Endpoint: ${WS_ENDPOINT}"
    
    # Store endpoints in Parameter Store
    aws ssm put-parameter \
        --name "/ethereum/${LAMBDA_FUNCTION_NAME}/http-endpoint" \
        --value "$HTTP_ENDPOINT" \
        --type "String" \
        --overwrite || error "Failed to store HTTP endpoint in Parameter Store"
    
    aws ssm put-parameter \
        --name "/ethereum/${LAMBDA_FUNCTION_NAME}/ws-endpoint" \
        --value "$WS_ENDPOINT" \
        --type "String" \
        --overwrite || error "Failed to store WebSocket endpoint in Parameter Store"
    
    log "Node endpoints configured and stored in Parameter Store"
    
    echo "Endpoints configured:" >> "$DEPLOYMENT_LOG_FILE"
    echo "  HTTP: ${HTTP_ENDPOINT}" >> "$DEPLOYMENT_LOG_FILE"
    echo "  WebSocket: ${WS_ENDPOINT}" >> "$DEPLOYMENT_LOG_FILE"
}

# Create smart contract development environment
create_contract_environment() {
    log "Creating smart contract development environment..."
    
    # Create temporary directory for contract development
    CONTRACTS_DIR="/tmp/ethereum-contracts-${RANDOM_SUFFIX}"
    mkdir -p "$CONTRACTS_DIR"
    cd "$CONTRACTS_DIR" || error "Failed to change to contracts directory"
    
    # Initialize package.json
    cat > package.json << 'EOF'
{
  "name": "ethereum-smart-contracts",
  "version": "1.0.0",
  "scripts": {
    "compile": "solc --bin --abi contracts/*.sol -o build/",
    "deploy": "node scripts/deploy.js"
  },
  "dependencies": {
    "web3": "^4.2.0",
    "solc": "^0.8.21"
  }
}
EOF
    
    # Install dependencies
    npm install || error "Failed to install Node.js dependencies"
    
    # Create directories
    mkdir -p contracts scripts build
    
    # Create sample Smart Contract
    cat > contracts/SimpleToken.sol << 'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SimpleToken {
    string public name = "AWS Managed Blockchain Token";
    string public symbol = "AMBT";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    constructor(uint256 _initialSupply) {
        totalSupply = _initialSupply * 10**decimals;
        balances[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }
    
    function balanceOf(address account) public view returns (uint256) {
        return balances[account];
    }
    
    function transfer(address to, uint256 amount) public returns (bool) {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) public returns (bool) {
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(balances[from] >= amount, "Insufficient balance");
        require(allowances[from][msg.sender] >= amount, "Insufficient allowance");
        
        balances[from] -= amount;
        balances[to] += amount;
        allowances[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
}
EOF
    
    # Compile the contract
    npx solc --bin --abi contracts/SimpleToken.sol \
        --output-dir build/ --overwrite || error "Failed to compile smart contract"
    
    # Create contract artifact JSON file
    cat > build/SimpleToken.json << EOF
{
  "abi": $(cat build/SimpleToken.abi),
  "bytecode": "0x$(cat build/SimpleToken.bin)"
}
EOF
    
    log "Smart contract development environment created and contract compiled"
    
    echo "Smart contract compiled in: ${CONTRACTS_DIR}" >> "$DEPLOYMENT_LOG_FILE"
}

# Upload contract artifacts to S3
upload_contract_artifacts() {
    log "Uploading contract artifacts to S3..."
    
    # Upload contract artifacts
    aws s3 cp build/SimpleToken.json \
        "s3://${BUCKET_NAME}/contracts/SimpleToken.json" || error "Failed to upload contract artifacts"
    
    # Upload source code for reference
    aws s3 cp contracts/SimpleToken.sol \
        "s3://${BUCKET_NAME}/contracts/SimpleToken.sol" || error "Failed to upload contract source"
    
    log "Contract artifacts uploaded to S3"
    
    echo "Contract artifacts uploaded to S3" >> "$DEPLOYMENT_LOG_FILE"
}

# Create Lambda function for contract management
create_lambda_function() {
    log "Creating Lambda function for contract management..."
    
    # Create Lambda deployment package directory
    LAMBDA_DIR="/tmp/lambda-deployment-${RANDOM_SUFFIX}"
    mkdir -p "$LAMBDA_DIR"
    cd "$LAMBDA_DIR" || error "Failed to change to Lambda directory"
    
    # Create package.json for Lambda
    cat > package.json << 'EOF'
{
  "name": "ethereum-contract-manager",
  "version": "1.0.0",
  "dependencies": {
    "web3": "^4.2.0",
    "@aws-sdk/client-ssm": "^3.0.0",
    "@aws-sdk/client-s3": "^3.0.0",
    "@aws-sdk/signature-v4": "^3.0.0"
  }
}
EOF
    
    # Install dependencies
    npm install --production || error "Failed to install Lambda dependencies"
    
    # Create Lambda function code
    cat > index.js << 'EOF'
const Web3 = require('web3');
const { SSMClient, GetParameterCommand } = require('@aws-sdk/client-ssm');
const { S3Client, GetObjectCommand, PutObjectCommand } = require('@aws-sdk/client-s3');

const ssmClient = new SSMClient({ region: process.env.AWS_REGION });
const s3Client = new S3Client({ region: process.env.AWS_REGION });

async function getParameter(name) {
    const command = new GetParameterCommand({ Name: name });
    const response = await ssmClient.send(command);
    return response.Parameter.Value;
}

async function getContractArtifacts(bucket, key) {
    const command = new GetObjectCommand({ Bucket: bucket, Key: key });
    const response = await s3Client.send(command);
    return JSON.parse(await response.Body.transformToString());
}

exports.handler = async (event) => {
    try {
        const httpEndpoint = await getParameter(`/ethereum/${process.env.FUNCTION_NAME}/http-endpoint`);
        const web3 = new Web3(httpEndpoint);
        
        const action = event.action;
        
        switch (action) {
            case 'getBlockNumber':
                const blockNumber = await web3.eth.getBlockNumber();
                return {
                    statusCode: 200,
                    body: JSON.stringify({ blockNumber: blockNumber.toString() })
                };
            
            case 'getBalance':
                const address = event.address;
                const balance = await web3.eth.getBalance(address);
                return {
                    statusCode: 200,
                    body: JSON.stringify({ 
                        address, 
                        balance: web3.utils.fromWei(balance, 'ether') + ' ETH'
                    })
                };
            
            case 'deployContract':
                const contractData = await getContractArtifacts(
                    process.env.BUCKET_NAME, 
                    'contracts/SimpleToken.json'
                );
                
                const contract = new web3.eth.Contract(contractData.abi);
                const deployTx = contract.deploy({
                    data: contractData.bytecode,
                    arguments: [event.initialSupply || 1000000]
                });
                
                return {
                    statusCode: 200,
                    body: JSON.stringify({
                        message: 'Contract deployment initiated',
                        gasEstimate: await deployTx.estimateGas(),
                        data: deployTx.encodeABI()
                    })
                };
            
            case 'callContract':
                const contractAbi = await getContractArtifacts(
                    process.env.BUCKET_NAME, 
                    'contracts/SimpleToken.json'
                );
                
                const contractInstance = new web3.eth.Contract(
                    contractAbi.abi, 
                    event.contractAddress
                );
                
                const result = await contractInstance.methods[event.method](...event.params).call();
                
                return {
                    statusCode: 200,
                    body: JSON.stringify({ result })
                };
            
            default:
                return {
                    statusCode: 400,
                    body: JSON.stringify({ error: 'Unknown action' })
                };
        }
    } catch (error) {
        console.error('Error:', error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: error.message })
        };
    }
};
EOF
    
    # Create deployment package
    zip -r ../lambda-deployment.zip . || error "Failed to create Lambda deployment package"
    cd ..
    
    # Create Lambda function
    LAMBDA_ARN=$(aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime nodejs18.x \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_FUNCTION_NAME}-role" \
        --handler index.handler \
        --zip-file fileb://lambda-deployment.zip \
        --timeout 60 \
        --memory-size 512 \
        --environment Variables="{
            BUCKET_NAME=${BUCKET_NAME},
            FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
        }" \
        --query 'FunctionArn' --output text) || error "Failed to create Lambda function"
    
    info "Lambda Function ARN: ${LAMBDA_ARN}"
    
    # Wait for function to be active
    aws lambda wait function-active --function-name "$LAMBDA_FUNCTION_NAME" || error "Lambda function failed to become active"
    
    log "Lambda function created successfully"
    
    echo "Lambda function created: ${LAMBDA_ARN}" >> "$DEPLOYMENT_LOG_FILE"
}

# Create API Gateway
create_api_gateway() {
    log "Creating API Gateway for Web3 access..."
    
    # Create REST API
    API_ID=$(aws apigateway create-rest-api \
        --name "$API_NAME" \
        --description "Ethereum Smart Contract API" \
        --query 'id' --output text) || error "Failed to create REST API"
    
    # Get root resource ID
    ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id "$API_ID" \
        --query 'items[0].id' --output text) || error "Failed to get root resource ID"
    
    # Create /ethereum resource
    ETHEREUM_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "$API_ID" \
        --parent-id "$ROOT_RESOURCE_ID" \
        --path-part ethereum \
        --query 'id' --output text) || error "Failed to create ethereum resource"
    
    # Create POST method
    aws apigateway put-method \
        --rest-api-id "$API_ID" \
        --resource-id "$ETHEREUM_RESOURCE_ID" \
        --http-method POST \
        --authorization-type NONE || error "Failed to create POST method"
    
    # Get Lambda ARN for integration
    LAMBDA_ARN=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Configuration.FunctionArn' --output text)
    
    # Set up Lambda integration
    aws apigateway put-integration \
        --rest-api-id "$API_ID" \
        --resource-id "$ETHEREUM_RESOURCE_ID" \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" || error "Failed to set up Lambda integration"
    
    # Grant API Gateway permission to invoke Lambda
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id api-gateway-invoke \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*" || error "Failed to grant API Gateway permission"
    
    log "API Gateway created successfully: ${API_ID}"
    
    echo "API Gateway created: ${API_ID}" >> "$DEPLOYMENT_LOG_FILE"
}

# Deploy API and set up monitoring
deploy_api_and_monitoring() {
    log "Deploying API and setting up monitoring..."
    
    # Create deployment
    DEPLOYMENT_ID=$(aws apigateway create-deployment \
        --rest-api-id "$API_ID" \
        --stage-name prod \
        --query 'id' --output text) || error "Failed to create API deployment"
    
    export API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
    
    # Create CloudWatch log group for API Gateway
    aws logs create-log-group \
        --log-group-name "/aws/apigateway/${API_NAME}" \
        --retention-in-days 7 || warn "Failed to create log group (may already exist)"
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "Ethereum-Blockchain-${RANDOM_SUFFIX}" \
        --dashboard-body '{
            "widgets": [
                {
                    "type": "metric",
                    "properties": {
                        "metrics": [
                            ["AWS/Lambda", "Duration", "FunctionName", "'${LAMBDA_FUNCTION_NAME}'"],
                            [".", "Errors", ".", "."],
                            [".", "Invocations", ".", "."]
                        ],
                        "period": 300,
                        "stat": "Average",
                        "region": "'${AWS_REGION}'",
                        "title": "Lambda Performance"
                    }
                },
                {
                    "type": "metric",
                    "properties": {
                        "metrics": [
                            ["AWS/ApiGateway", "Count", "ApiName", "'${API_NAME}'"],
                            [".", "Latency", ".", "."],
                            [".", "4XXError", ".", "."],
                            [".", "5XXError", ".", "."]
                        ],
                        "period": 300,
                        "stat": "Sum",
                        "region": "'${AWS_REGION}'",
                        "title": "API Gateway Metrics"
                    }
                }
            ]
        }' || warn "Failed to create CloudWatch dashboard"
    
    # Create CloudWatch alarm for Lambda errors
    aws cloudwatch put-metric-alarm \
        --alarm-name "${LAMBDA_FUNCTION_NAME}-errors" \
        --alarm-description "Lambda function errors" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME" \
        --evaluation-periods 2 \
        --treat-missing-data notBreaching || warn "Failed to create CloudWatch alarm"
    
    info "API Endpoint: ${API_ENDPOINT}/ethereum"
    log "API deployed with monitoring enabled"
    
    echo "API deployed:" >> "$DEPLOYMENT_LOG_FILE"
    echo "  Endpoint: ${API_ENDPOINT}/ethereum" >> "$DEPLOYMENT_LOG_FILE"
    echo "  Dashboard: Ethereum-Blockchain-${RANDOM_SUFFIX}" >> "$DEPLOYMENT_LOG_FILE"
}

# Test deployment
test_deployment() {
    log "Testing deployment..."
    
    # Test Lambda function directly
    info "Testing Lambda function directly..."
    aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload '{"action":"getBlockNumber"}' \
        /tmp/lambda-response.json || error "Failed to invoke Lambda function"
    
    if [ -f /tmp/lambda-response.json ]; then
        RESPONSE=$(cat /tmp/lambda-response.json)
        info "Lambda test response: ${RESPONSE}"
        rm -f /tmp/lambda-response.json
    fi
    
    # Test API Gateway endpoint
    info "Testing API Gateway endpoint..."
    if command -v curl &> /dev/null; then
        CURL_RESPONSE=$(curl -s -X POST "${API_ENDPOINT}/ethereum" \
            -H "Content-Type: application/json" \
            -d '{"action":"getBlockNumber"}' || echo "curl failed")
        info "API Gateway test response: ${CURL_RESPONSE}"
    else
        warn "curl not available, skipping API Gateway test"
    fi
    
    log "Deployment testing completed"
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    # Create deployment info file
    DEPLOYMENT_INFO_FILE="/tmp/ethereum-deployment-info-${RANDOM_SUFFIX}.json"
    
    cat > "$DEPLOYMENT_INFO_FILE" << EOF
{
    "deploymentTime": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "awsRegion": "${AWS_REGION}",
    "awsAccountId": "${AWS_ACCOUNT_ID}",
    "randomSuffix": "${RANDOM_SUFFIX}",
    "resources": {
        "ethereumNodeId": "${NODE_ID}",
        "lambdaFunctionName": "${LAMBDA_FUNCTION_NAME}",
        "apiGatewayId": "${API_ID}",
        "apiName": "${API_NAME}",
        "s3BucketName": "${BUCKET_NAME}",
        "iamRoleName": "${LAMBDA_FUNCTION_NAME}-role",
        "cloudWatchDashboard": "Ethereum-Blockchain-${RANDOM_SUFFIX}",
        "cloudWatchAlarm": "${LAMBDA_FUNCTION_NAME}-errors"
    },
    "endpoints": {
        "httpEndpoint": "${HTTP_ENDPOINT}",
        "websocketEndpoint": "${WS_ENDPOINT}",
        "apiEndpoint": "${API_ENDPOINT}/ethereum"
    }
}
EOF
    
    # Upload deployment info to S3
    aws s3 cp "$DEPLOYMENT_INFO_FILE" \
        "s3://${BUCKET_NAME}/deployment-info.json" || warn "Failed to upload deployment info to S3"
    
    info "Deployment information saved to: ${DEPLOYMENT_INFO_FILE}"
    info "Deployment information also uploaded to S3: s3://${BUCKET_NAME}/deployment-info.json"
    
    echo "Deployment completed successfully at $(date)" >> "$DEPLOYMENT_LOG_FILE"
}

# Main deployment function
main() {
    log "Starting Ethereum Smart Contract deployment..."
    
    check_prerequisites
    initialize_environment
    create_s3_bucket
    create_lambda_role
    create_ethereum_node
    configure_node_endpoints
    create_contract_environment
    upload_contract_artifacts
    create_lambda_function
    create_api_gateway
    deploy_api_and_monitoring
    test_deployment
    save_deployment_info
    
    log "Deployment completed successfully!"
    log "================================================"
    log "DEPLOYMENT SUMMARY"
    log "================================================"
    log "AWS Region: ${AWS_REGION}"
    log "Ethereum Node ID: ${NODE_ID}"
    log "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log "API Gateway ID: ${API_ID}"
    log "S3 Bucket: ${BUCKET_NAME}"
    log "API Endpoint: ${API_ENDPOINT}/ethereum"
    log "CloudWatch Dashboard: Ethereum-Blockchain-${RANDOM_SUFFIX}"
    log "Deployment Log: ${DEPLOYMENT_LOG_FILE}"
    log "================================================"
    
    warn "IMPORTANT: The Ethereum node on mainnet will incur ongoing costs (~$50-100/month)"
    warn "Remember to run destroy.sh when you're done to avoid unnecessary charges"
}

# Run main function
main "$@"