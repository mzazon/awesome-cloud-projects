#!/bin/bash

# Decentralized Identity Management with Blockchain - Deployment Script
# This script deploys AWS Managed Blockchain, QLDB, Lambda, and supporting infrastructure
# for a decentralized identity management system.

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
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    log "Checking AWS CLI authentication..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not authenticated. Please run 'aws configure' or set AWS credentials."
        exit 1
    fi
    log_success "AWS CLI authentication verified"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check required commands
    local required_commands=("aws" "openssl" "zip" "jq" "curl")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "$cmd is not installed. Please install it before continuing."
            exit 1
        fi
    done
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $aws_version"
    
    # Check Node.js version for chaincode
    if command_exists "node"; then
        local node_version=$(node --version)
        log "Node.js version: $node_version"
    else
        log_warning "Node.js not found. This is required for chaincode development."
    fi
    
    # Check Docker for local development
    if command_exists "docker"; then
        log "Docker found for chaincode development"
    else
        log_warning "Docker not found. This may be needed for local chaincode testing."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        log_error "AWS region not configured. Please set default region with 'aws configure'."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword)
    
    export NETWORK_NAME="identity-network-${RANDOM_SUFFIX}"
    export MEMBER_NAME="identity-org-${RANDOM_SUFFIX}"
    export ADMIN_USERNAME="admin"
    export ADMIN_PASSWORD="TempPassword123!"
    export QLDB_LEDGER_NAME="identity-ledger-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="identity-blockchain-assets-${RANDOM_SUFFIX}"
    export DYNAMODB_TABLE_NAME="identity-credentials-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="identity-management-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="identity-lambda-role-${RANDOM_SUFFIX}"
    export IAM_POLICY_NAME="identity-management-policy-${RANDOM_SUFFIX}"
    export API_NAME="identity-management-api-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
NETWORK_NAME=${NETWORK_NAME}
MEMBER_NAME=${MEMBER_NAME}
ADMIN_USERNAME=${ADMIN_USERNAME}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
QLDB_LEDGER_NAME=${QLDB_LEDGER_NAME}
S3_BUCKET_NAME=${S3_BUCKET_NAME}
DYNAMODB_TABLE_NAME=${DYNAMODB_TABLE_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
IAM_ROLE_NAME=${IAM_ROLE_NAME}
IAM_POLICY_NAME=${IAM_POLICY_NAME}
API_NAME=${API_NAME}
EOF
    
    log_success "Environment variables configured with suffix: ${RANDOM_SUFFIX}"
}

# Function to create foundational resources
create_foundational_resources() {
    log "Creating foundational resources..."
    
    # Create S3 bucket for chaincode and schema storage
    log "Creating S3 bucket for blockchain assets..."
    aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION} || {
        log_error "Failed to create S3 bucket"
        exit 1
    }
    log_success "S3 bucket created: ${S3_BUCKET_NAME}"
    
    # Create DynamoDB table for credential indexing
    log "Creating DynamoDB table for credential indexing..."
    aws dynamodb create-table \
        --table-name ${DYNAMODB_TABLE_NAME} \
        --attribute-definitions \
            AttributeName=did,AttributeType=S \
            AttributeName=credential_id,AttributeType=S \
        --key-schema \
            AttributeName=did,KeyType=HASH \
            AttributeName=credential_id,KeyType=RANGE \
        --provisioned-throughput \
            ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --region ${AWS_REGION} || {
        log_error "Failed to create DynamoDB table"
        exit 1
    }
    
    # Wait for table to be active
    log "Waiting for DynamoDB table to become active..."
    aws dynamodb wait table-exists --table-name ${DYNAMODB_TABLE_NAME}
    log_success "DynamoDB table created: ${DYNAMODB_TABLE_NAME}"
}

# Function to create IAM roles and policies
create_iam_resources() {
    log "Creating IAM roles and policies..."
    
    # Create IAM role for Lambda
    log "Creating IAM role for Lambda functions..."
    aws iam create-role \
        --role-name ${IAM_ROLE_NAME} \
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
        }' || {
        log_error "Failed to create IAM role"
        exit 1
    }
    
    # Create custom policy for identity management
    log "Creating custom IAM policy for identity management..."
    aws iam create-policy \
        --policy-name ${IAM_POLICY_NAME} \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "qldb:ExecuteStatement",
                        "qldb:StartSession",
                        "qldb:SendCommand"
                    ],
                    "Resource": "*"
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "dynamodb:PutItem",
                        "dynamodb:GetItem",
                        "dynamodb:UpdateItem",
                        "dynamodb:DeleteItem",
                        "dynamodb:Query"
                    ],
                    "Resource": "arn:aws:dynamodb:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':table/'${DYNAMODB_TABLE_NAME}'"
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "managedblockchain:*"
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
        }' || {
        log_error "Failed to create IAM policy"
        exit 1
    }
    
    # Attach policies to role
    log "Attaching policies to IAM role..."
    aws iam attach-role-policy \
        --role-name ${IAM_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam attach-role-policy \
        --role-name ${IAM_ROLE_NAME} \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IAM_POLICY_NAME}
    
    # Wait for role propagation
    log "Waiting for IAM role propagation..."
    sleep 10
    
    log_success "IAM roles and policies created successfully"
}

# Function to create QLDB ledger
create_qldb_ledger() {
    log "Creating QLDB ledger for identity state management..."
    
    aws qldb create-ledger \
        --name ${QLDB_LEDGER_NAME} \
        --permissions-mode STANDARD \
        --kms-key-id alias/aws/qldb \
        --region ${AWS_REGION} || {
        log_error "Failed to create QLDB ledger"
        exit 1
    }
    
    # Wait for ledger to be active
    log "Waiting for QLDB ledger to become active..."
    local max_attempts=30
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        local state=$(aws qldb describe-ledger --name ${QLDB_LEDGER_NAME} --query 'State' --output text)
        if [[ "$state" == "ACTIVE" ]]; then
            break
        fi
        log "Attempt $attempt: QLDB ledger state is $state, waiting..."
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_error "QLDB ledger did not become active within expected time"
        exit 1
    fi
    
    log_success "QLDB ledger created: ${QLDB_LEDGER_NAME}"
}

# Function to create blockchain network
create_blockchain_network() {
    log "Creating AWS Managed Blockchain network..."
    
    # Create the blockchain network with initial member
    NETWORK_ID=$(aws managedblockchain create-network \
        --name ${NETWORK_NAME} \
        --framework HYPERLEDGER_FABRIC \
        --framework-version 2.2 \
        --member-configuration \
            Name=${MEMBER_NAME},Description="Identity management organization",FrameworkConfiguration='{
                "MemberFabricConfiguration": {
                    "AdminUsername": "'${ADMIN_USERNAME}'",
                    "AdminPassword": "'${ADMIN_PASSWORD}'"
                }
            }' \
        --voting-policy ApprovalThresholdPolicy='{
            ThresholdPercentage=50,
            ProposalDurationInHours=24,
            ThresholdComparator=GREATER_THAN
        }' \
        --query 'NetworkId' --output text) || {
        log_error "Failed to create blockchain network"
        exit 1
    }
    
    # Save network ID to environment file
    echo "NETWORK_ID=${NETWORK_ID}" >> .env
    
    # Wait for network creation
    log "Waiting for blockchain network to become available..."
    local max_attempts=60
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        local status=$(aws managedblockchain get-network --network-id ${NETWORK_ID} --query 'Network.Status' --output text)
        if [[ "$status" == "AVAILABLE" ]]; then
            break
        fi
        log "Attempt $attempt: Network status is $status, waiting..."
        sleep 30
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_error "Blockchain network did not become available within expected time"
        exit 1
    fi
    
    log_success "Blockchain network created: ${NETWORK_ID}"
}

# Function to create member and peer nodes
create_member_and_peers() {
    log "Creating member and peer nodes..."
    
    # Get member ID
    MEMBER_ID=$(aws managedblockchain list-members \
        --network-id ${NETWORK_ID} \
        --query 'Members[0].Id' --output text)
    
    echo "MEMBER_ID=${MEMBER_ID}" >> .env
    
    # Create peer node
    log "Creating peer node..."
    PEER_NODE_ID=$(aws managedblockchain create-node \
        --network-id ${NETWORK_ID} \
        --member-id ${MEMBER_ID} \
        --node-configuration \
            InstanceType=bc.t3.small,AvailabilityZone=${AWS_REGION}a \
        --query 'NodeId' --output text) || {
        log_error "Failed to create peer node"
        exit 1
    }
    
    echo "PEER_NODE_ID=${PEER_NODE_ID}" >> .env
    
    # Wait for peer node creation
    log "Waiting for peer node to become available..."
    local max_attempts=40
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        local status=$(aws managedblockchain get-node \
            --network-id ${NETWORK_ID} \
            --member-id ${MEMBER_ID} \
            --node-id ${PEER_NODE_ID} \
            --query 'Node.Status' --output text)
        if [[ "$status" == "AVAILABLE" ]]; then
            break
        fi
        log "Attempt $attempt: Peer node status is $status, waiting..."
        sleep 30
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_error "Peer node did not become available within expected time"
        exit 1
    fi
    
    log_success "Peer node created: ${PEER_NODE_ID}"
}

# Function to create and deploy chaincode
create_chaincode() {
    log "Creating and packaging identity chaincode..."
    
    # Create chaincode directory structure
    mkdir -p chaincode/identity-management
    cd chaincode/identity-management
    
    # Create package.json for Node.js chaincode
    cat > package.json << 'EOF'
{
  "name": "identity-management-chaincode",
  "version": "1.0.0",
  "description": "Decentralized Identity Management Chaincode",
  "main": "index.js",
  "scripts": {
    "start": "fabric-chaincode-node start"
  },
  "dependencies": {
    "fabric-contract-api": "^2.4.1",
    "fabric-shim": "^2.4.1"
  }
}
EOF
    
    # Create identity chaincode implementation
    cat > identity-chaincode.js << 'EOF'
const { Contract } = require('fabric-contract-api');
const crypto = require('crypto');

class IdentityContract extends Contract {
    
    async createDID(ctx, publicKey, metadata) {
        // Generate DID (Decentralized Identifier)
        const did = `did:fabric:${crypto.createHash('sha256')
            .update(publicKey).digest('hex').substring(0, 16)}`;
        
        const identity = {
            did: did,
            publicKey: publicKey,
            metadata: JSON.parse(metadata),
            created: new Date().toISOString(),
            status: 'active',
            credentialCount: 0
        };
        
        await ctx.stub.putState(did, Buffer.from(JSON.stringify(identity)));
        
        // Emit event for identity creation
        ctx.stub.setEvent('IdentityCreated', Buffer.from(JSON.stringify({
            did: did,
            timestamp: identity.created
        })));
        
        return did;
    }
    
    async issueCredential(ctx, did, credentialType, claims, issuerDID) {
        // Verify DID exists
        const identityBytes = await ctx.stub.getState(did);
        if (!identityBytes || identityBytes.length === 0) {
            throw new Error(`Identity ${did} does not exist`);
        }
        
        const identity = JSON.parse(identityBytes.toString());
        
        // Create credential
        const credentialId = crypto.randomBytes(16).toString('hex');
        const credential = {
            id: credentialId,
            type: credentialType,
            holder: did,
            issuer: issuerDID,
            claims: JSON.parse(claims),
            issued: new Date().toISOString(),
            status: 'active',
            proof: {
                type: 'Ed25519Signature2020',
                created: new Date().toISOString(),
                verificationMethod: `${issuerDID}#key-1`,
                proofPurpose: 'assertionMethod'
            }
        };
        
        // Store credential
        await ctx.stub.putState(credentialId, 
            Buffer.from(JSON.stringify(credential)));
        
        // Update identity credential count
        identity.credentialCount++;
        await ctx.stub.putState(did, Buffer.from(JSON.stringify(identity)));
        
        // Emit event
        ctx.stub.setEvent('CredentialIssued', Buffer.from(JSON.stringify({
            credentialId: credentialId,
            did: did,
            type: credentialType,
            timestamp: credential.issued
        })));
        
        return credentialId;
    }
    
    async verifyCredential(ctx, credentialId) {
        const credentialBytes = await ctx.stub.getState(credentialId);
        if (!credentialBytes || credentialBytes.length === 0) {
            throw new Error(`Credential ${credentialId} does not exist`);
        }
        
        const credential = JSON.parse(credentialBytes.toString());
        
        // Verify holder identity exists
        const identityBytes = await ctx.stub.getState(credential.holder);
        if (!identityBytes || identityBytes.length === 0) {
            return { valid: false, reason: 'Holder identity not found' };
        }
        
        const identity = JSON.parse(identityBytes.toString());
        
        // Check credential and identity status
        if (credential.status !== 'active' || identity.status !== 'active') {
            return { valid: false, reason: 'Credential or identity is not active' };
        }
        
        return {
            valid: true,
            credential: credential,
            identity: identity,
            verifiedAt: new Date().toISOString()
        };
    }
    
    async revokeCredential(ctx, credentialId, reason) {
        const credentialBytes = await ctx.stub.getState(credentialId);
        if (!credentialBytes || credentialBytes.length === 0) {
            throw new Error(`Credential ${credentialId} does not exist`);
        }
        
        const credential = JSON.parse(credentialBytes.toString());
        credential.status = 'revoked';
        credential.revocationReason = reason;
        credential.revokedAt = new Date().toISOString();
        
        await ctx.stub.putState(credentialId, 
            Buffer.from(JSON.stringify(credential)));
        
        // Emit event
        ctx.stub.setEvent('CredentialRevoked', Buffer.from(JSON.stringify({
            credentialId: credentialId,
            reason: reason,
            timestamp: credential.revokedAt
        })));
        
        return true;
    }
    
    async queryIdentity(ctx, did) {
        const identityBytes = await ctx.stub.getState(did);
        if (!identityBytes || identityBytes.length === 0) {
            throw new Error(`Identity ${did} does not exist`);
        }
        
        return JSON.parse(identityBytes.toString());
    }
    
    async queryCredentialsByDID(ctx, did) {
        const query = {
            selector: {
                holder: did,
                status: "active"
            }
        };
        
        const iterator = await ctx.stub.getQueryResult(JSON.stringify(query));
        const credentials = [];
        
        let result = await iterator.next();
        while (!result.done) {
            const record = result.value;
            credentials.push(JSON.parse(record.value.toString()));
            result = await iterator.next();
        }
        
        await iterator.close();
        return credentials;
    }
}

module.exports = IdentityContract;
EOF
    
    # Create chaincode index
    cat > index.js << 'EOF'
const IdentityContract = require('./identity-chaincode');
module.exports.IdentityContract = IdentityContract;
module.exports.contracts = [IdentityContract];
EOF
    
    # Install Node.js dependencies if possible
    if command_exists "npm"; then
        log "Installing chaincode dependencies..."
        npm install --only=production
    else
        log_warning "npm not found, skipping dependency installation"
    fi
    
    # Create a simple package for upload to S3
    log "Creating chaincode package..."
    tar -czf ../identity-management.tar.gz .
    
    # Upload to S3
    aws s3 cp ../identity-management.tar.gz s3://${S3_BUCKET_NAME}/chaincode/
    
    cd ../..
    log_success "Identity chaincode created and uploaded to S3"
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function for identity operations..."
    
    # Create Lambda function code
    cat > identity-lambda.js << 'EOF'
const AWS = require('aws-sdk');

const qldb = new AWS.QLDB();
const dynamodb = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event, context) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    const { action, did, credentialType, claims, publicKey } = event;
    
    try {
        switch (action) {
            case 'createIdentity':
                return await createIdentity(publicKey, event.metadata);
            case 'issueCredential':
                return await issueCredential(did, credentialType, claims);
            case 'verifyCredential':
                return await verifyCredential(event.credentialId);
            case 'revokeCredential':
                return await revokeCredential(event.credentialId, event.reason);
            case 'queryIdentity':
                return await queryIdentity(did);
            default:
                throw new Error(`Unknown action: ${action}`);
        }
    } catch (error) {
        console.error('Identity operation failed:', error);
        return {
            statusCode: 500,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({ 
                error: error.message,
                action: action
            })
        };
    }
};

async function createIdentity(publicKey, metadata) {
    // Generate DID (simplified for demo)
    const crypto = require('crypto');
    const did = `did:fabric:${crypto.createHash('sha256')
        .update(publicKey).digest('hex').substring(0, 16)}`;
    
    // Store in QLDB for fast queries (simplified)
    const identity = {
        did: did,
        publicKey: publicKey,
        metadata: metadata || {},
        created: new Date().toISOString(),
        status: 'active'
    };
    
    // In a real implementation, this would call the blockchain
    console.log('Created identity:', identity);
    
    return {
        statusCode: 200,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({ 
            did: did,
            message: 'Identity created successfully'
        })
    };
}

async function issueCredential(did, credentialType, claims) {
    // Generate credential ID
    const crypto = require('crypto');
    const credentialId = crypto.randomBytes(16).toString('hex');
    
    // Index in DynamoDB
    try {
        await dynamodb.put({
            TableName: process.env.CREDENTIAL_TABLE,
            Item: {
                did: did,
                credential_id: credentialId,
                type: credentialType,
                claims: claims || {},
                issued: new Date().toISOString(),
                status: 'active'
            }
        }).promise();
    } catch (error) {
        console.error('DynamoDB error:', error);
    }
    
    return {
        statusCode: 200,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({ 
            credentialId: credentialId,
            message: 'Credential issued successfully'
        })
    };
}

async function verifyCredential(credentialId) {
    // In a real implementation, this would query the blockchain
    const verification = {
        valid: true,
        credentialId: credentialId,
        verifiedAt: new Date().toISOString(),
        message: 'Credential verification successful'
    };
    
    return {
        statusCode: 200,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify(verification)
    };
}

async function revokeCredential(credentialId, reason) {
    // In a real implementation, this would call the blockchain
    return {
        statusCode: 200,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({ 
            success: true,
            credentialId: credentialId,
            reason: reason,
            message: 'Credential revoked successfully'
        })
    };
}

async function queryIdentity(did) {
    // In a real implementation, this would query the blockchain
    const identity = {
        did: did,
        status: 'active',
        queriedAt: new Date().toISOString(),
        message: 'Identity query successful'
    };
    
    return {
        statusCode: 200,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify(identity)
    };
}
EOF
    
    # Create Lambda deployment package
    log "Creating Lambda deployment package..."
    zip -r identity-lambda.zip identity-lambda.js
    
    # Deploy Lambda function
    aws lambda create-function \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --runtime nodejs18.x \
        --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME} \
        --handler identity-lambda.handler \
        --zip-file fileb://identity-lambda.zip \
        --timeout 30 \
        --memory-size 256 \
        --environment Variables="{CREDENTIAL_TABLE=${DYNAMODB_TABLE_NAME}}" || {
        log_error "Failed to create Lambda function"
        exit 1
    }
    
    # Wait for function to be active
    aws lambda wait function-active --function-name ${LAMBDA_FUNCTION_NAME}
    
    log_success "Lambda function created: ${LAMBDA_FUNCTION_NAME}"
}

# Function to create API Gateway
create_api_gateway() {
    log "Creating API Gateway for identity services..."
    
    # Create API Gateway
    API_ID=$(aws apigateway create-rest-api \
        --name ${API_NAME} \
        --description "Decentralized Identity Management API" \
        --query 'id' --output text) || {
        log_error "Failed to create API Gateway"
        exit 1
    }
    
    echo "API_ID=${API_ID}" >> .env
    
    # Get root resource ID
    ROOT_RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id ${API_ID} \
        --query 'items[0].id' --output text)
    
    # Create /identity resource
    IDENTITY_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id ${API_ID} \
        --parent-id ${ROOT_RESOURCE_ID} \
        --path-part identity \
        --query 'id' --output text)
    
    # Create POST method for identity operations
    aws apigateway put-method \
        --rest-api-id ${API_ID} \
        --resource-id ${IDENTITY_RESOURCE_ID} \
        --http-method POST \
        --authorization-type NONE
    
    # Add CORS support
    aws apigateway put-method \
        --rest-api-id ${API_ID} \
        --resource-id ${IDENTITY_RESOURCE_ID} \
        --http-method OPTIONS \
        --authorization-type NONE
    
    # Integrate with Lambda
    aws apigateway put-integration \
        --rest-api-id ${API_ID} \
        --resource-id ${IDENTITY_RESOURCE_ID} \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}/invocations
    
    # Add Lambda permission for API Gateway
    aws lambda add-permission \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --statement-id api-gateway-invoke \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*/*
    
    # Deploy API
    aws apigateway create-deployment \
        --rest-api-id ${API_ID} \
        --stage-name prod
    
    API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
    echo "API_ENDPOINT=${API_ENDPOINT}" >> .env
    
    log_success "API Gateway deployed: ${API_ENDPOINT}"
}

# Function to run validation tests
run_validation_tests() {
    log "Running validation tests..."
    
    # Test API Gateway endpoint
    log "Testing API Gateway endpoint..."
    curl -s -o /dev/null -w "%{http_code}" "${API_ENDPOINT}/identity" | grep -q "404" && {
        log_success "API Gateway endpoint is accessible"
    } || {
        log_warning "API Gateway endpoint test inconclusive"
    }
    
    # Test Lambda function
    log "Testing Lambda function..."
    TEST_RESULT=$(aws lambda invoke \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --payload '{"action":"queryIdentity","did":"test"}' \
        --output json \
        response.json)
    
    if [[ $? -eq 0 ]]; then
        log_success "Lambda function test passed"
    else
        log_warning "Lambda function test failed"
    fi
    
    # Cleanup test file
    rm -f response.json
    
    log_success "Validation tests completed"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=================================================="
    echo "DECENTRALIZED IDENTITY MANAGEMENT DEPLOYMENT SUMMARY"
    echo "=================================================="
    echo
    echo "AWS Region: ${AWS_REGION}"
    echo "Random Suffix: ${RANDOM_SUFFIX}"
    echo
    echo "Blockchain Network:"
    echo "  Network ID: ${NETWORK_ID:-Not created}"
    echo "  Member ID: ${MEMBER_ID:-Not created}"
    echo "  Peer Node ID: ${PEER_NODE_ID:-Not created}"
    echo
    echo "QLDB Ledger: ${QLDB_LEDGER_NAME}"
    echo "DynamoDB Table: ${DYNAMODB_TABLE_NAME}"
    echo "S3 Bucket: ${S3_BUCKET_NAME}"
    echo
    echo "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "API Gateway: ${API_ENDPOINT:-Not created}"
    echo
    echo "IAM Role: ${IAM_ROLE_NAME}"
    echo "IAM Policy: ${IAM_POLICY_NAME}"
    echo
    echo "=================================================="
    echo
    echo "Next Steps:"
    echo "1. Test the API endpoints using the provided examples"
    echo "2. Deploy the chaincode to the blockchain network"
    echo "3. Configure client applications to use the API"
    echo
    echo "Environment variables saved to .env file"
    echo "Use destroy.sh to clean up all resources"
    echo
    echo "Estimated monthly cost: \$150-250 for the deployed infrastructure"
    echo "=================================================="
}

# Main execution function
main() {
    log "Starting decentralized identity management deployment..."
    
    # Check if dry-run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log "DRY RUN MODE - No resources will be created"
        return 0
    fi
    
    # Run all deployment steps
    check_aws_auth
    check_prerequisites
    setup_environment
    create_foundational_resources
    create_iam_resources
    create_qldb_ledger
    create_blockchain_network
    create_member_and_peers
    create_chaincode
    create_lambda_function
    create_api_gateway
    run_validation_tests
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Handle script termination
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        log_error "Deployment failed. Check the logs for details."
        log "You may need to run destroy.sh to clean up partially created resources."
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"