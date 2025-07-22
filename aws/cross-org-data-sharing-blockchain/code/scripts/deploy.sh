#!/bin/bash

# Cross-Organization Data Sharing with Amazon Managed Blockchain - Deployment Script
# This script deploys a complete cross-organization blockchain network for secure data sharing

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Wait for resource to be available with timeout
wait_for_resource() {
    local wait_command="$1"
    local resource_name="$2"
    local timeout="${3:-600}"  # Default 10 minutes
    local interval="${4:-30}"   # Default 30 seconds
    
    log_info "Waiting for $resource_name to be available (timeout: ${timeout}s)..."
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if eval "$wait_command" >/dev/null 2>&1; then
            log_success "$resource_name is now available"
            return 0
        fi
        
        log_info "Waiting for $resource_name... (${elapsed}s elapsed)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_error "Timeout waiting for $resource_name after ${timeout}s"
    return 1
}

# Cleanup function for graceful exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Deployment failed with exit code $exit_code"
        log_warning "You may need to run the destroy script to clean up partial resources"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Node.js for Lambda functions
    if ! command_exists node; then
        log_error "Node.js is not installed. Please install it first."
        exit 1
    fi
    
    # Check npm
    if ! command_exists npm; then
        log_error "npm is not installed. Please install Node.js with npm."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check for required permissions (basic check)
    if ! aws iam get-user >/dev/null 2>&1 && ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "Unable to verify AWS credentials"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "No default region set, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    
    export NETWORK_NAME="cross-org-network-${random_suffix}"
    export ORG_A_MEMBER="financial-institution-${random_suffix}"
    export ORG_B_MEMBER="healthcare-provider-${random_suffix}"
    export BUCKET_NAME="cross-org-data-${random_suffix}"
    export LAMBDA_FUNCTION_NAME="CrossOrgDataValidator-${random_suffix}"
    
    # Create state file to persist variables
    cat > deployment-state.env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
NETWORK_NAME=${NETWORK_NAME}
ORG_A_MEMBER=${ORG_A_MEMBER}
ORG_B_MEMBER=${ORG_B_MEMBER}
BUCKET_NAME=${BUCKET_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
EOF
    
    log_success "Environment variables configured"
    log_info "Network name: ${NETWORK_NAME}"
    log_info "AWS Region: ${AWS_REGION}"
}

# Create foundational resources
create_foundational_resources() {
    log_info "Creating foundational resources..."
    
    # Create S3 bucket for shared data and chaincode
    if aws s3 ls "s3://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "S3 bucket ${BUCKET_NAME} already exists"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
        log_success "Created S3 bucket: ${BUCKET_NAME}"
    fi
    
    # Create DynamoDB table for audit trail
    if aws dynamodb describe-table --table-name CrossOrgAuditTrail >/dev/null 2>&1; then
        log_warning "DynamoDB table CrossOrgAuditTrail already exists"
    else
        aws dynamodb create-table \
            --table-name CrossOrgAuditTrail \
            --attribute-definitions \
                AttributeName=TransactionId,AttributeType=S \
                AttributeName=Timestamp,AttributeType=N \
            --key-schema \
                AttributeName=TransactionId,KeyType=HASH \
                AttributeName=Timestamp,KeyType=RANGE \
            --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
            --region "${AWS_REGION}"
        log_success "Created DynamoDB table: CrossOrgAuditTrail"
    fi
    
    log_success "Foundational resources created"
}

# Create blockchain network
create_blockchain_network() {
    log_info "Creating blockchain network..."
    
    local network_id
    network_id=$(aws managedblockchain create-network \
        --name "${NETWORK_NAME}" \
        --description "Cross-Organization Data Sharing Network" \
        --framework HYPERLEDGER_FABRIC \
        --framework-version 2.2 \
        --framework-configuration '{
            "NetworkFabricConfiguration": {
                "Edition": "STANDARD"
            }
        }' \
        --voting-policy '{
            "ApprovalThresholdPolicy": {
                "ThresholdPercentage": 66,
                "ProposalDurationInHours": 24,
                "ThresholdComparator": "GREATER_THAN"
            }
        }' \
        --member-configuration '{
            "Name": "'"${ORG_A_MEMBER}"'",
            "Description": "Financial Institution Member",
            "MemberFabricConfiguration": {
                "AdminUsername": "admin",
                "AdminPassword": "TempPassword123!"
            }
        }' \
        --query 'NetworkId' --output text)
    
    export NETWORK_ID="$network_id"
    echo "NETWORK_ID=${NETWORK_ID}" >> deployment-state.env
    
    log_success "Created blockchain network: ${NETWORK_ID}"
    
    # Wait for network to be active
    wait_for_resource \
        "aws managedblockchain get-network --network-id ${NETWORK_ID} --query 'Network.Status' --output text | grep -q AVAILABLE" \
        "blockchain network ${NETWORK_ID}" \
        600 \
        30
}

# Setup Organization A
setup_organization_a() {
    log_info "Setting up Organization A..."
    
    # Get the first member ID (Organization A)
    local org_a_member_id
    org_a_member_id=$(aws managedblockchain list-members \
        --network-id "${NETWORK_ID}" \
        --query 'Members[0].Id' --output text)
    
    export ORG_A_MEMBER_ID="$org_a_member_id"
    echo "ORG_A_MEMBER_ID=${ORG_A_MEMBER_ID}" >> deployment-state.env
    
    log_success "Organization A Member ID: ${ORG_A_MEMBER_ID}"
    
    # Create primary peer node for Organization A
    local org_a_node_id
    org_a_node_id=$(aws managedblockchain create-node \
        --network-id "${NETWORK_ID}" \
        --member-id "${ORG_A_MEMBER_ID}" \
        --node-configuration '{
            "InstanceType": "bc.t3.medium",
            "AvailabilityZone": "'"${AWS_REGION}a"'"
        }' \
        --query 'NodeId' --output text)
    
    export ORG_A_NODE_ID="$org_a_node_id"
    echo "ORG_A_NODE_ID=${ORG_A_NODE_ID}" >> deployment-state.env
    
    log_success "Created Organization A peer node: ${ORG_A_NODE_ID}"
    
    # Wait for node to be available
    wait_for_resource \
        "aws managedblockchain get-node --network-id ${NETWORK_ID} --member-id ${ORG_A_MEMBER_ID} --node-id ${ORG_A_NODE_ID} --query 'Node.Status' --output text | grep -q AVAILABLE" \
        "Organization A peer node ${ORG_A_NODE_ID}" \
        600 \
        30
}

# Invite and setup Organization B
setup_organization_b() {
    log_info "Inviting and setting up Organization B..."
    
    # Create member proposal for Organization B
    local proposal_id
    proposal_id=$(aws managedblockchain create-proposal \
        --network-id "${NETWORK_ID}" \
        --member-id "${ORG_A_MEMBER_ID}" \
        --actions '{
            "Invitations": [
                {
                    "Principal": "'"${AWS_ACCOUNT_ID}"'"
                }
            ]
        }' \
        --description "Invite Healthcare Provider to cross-org network" \
        --query 'ProposalId' --output text)
    
    export PROPOSAL_ID="$proposal_id"
    echo "PROPOSAL_ID=${PROPOSAL_ID}" >> deployment-state.env
    
    log_success "Created proposal: ${PROPOSAL_ID}"
    
    # Vote YES on the proposal
    aws managedblockchain vote-on-proposal \
        --network-id "${NETWORK_ID}" \
        --proposal-id "${PROPOSAL_ID}" \
        --voter-member-id "${ORG_A_MEMBER_ID}" \
        --vote YES
    
    log_success "Voted YES on proposal: ${PROPOSAL_ID}"
    
    # Wait for proposal to be approved
    sleep 30
    
    # List invitations to get invitation ID
    local invitation_id
    invitation_id=$(aws managedblockchain list-invitations \
        --query 'Invitations[0].InvitationId' --output text)
    
    if [ "$invitation_id" = "None" ] || [ -z "$invitation_id" ]; then
        log_error "No invitation found. Proposal may not be approved yet."
        exit 1
    fi
    
    export INVITATION_ID="$invitation_id"
    echo "INVITATION_ID=${INVITATION_ID}" >> deployment-state.env
    
    log_success "Found invitation: ${INVITATION_ID}"
    
    # Create member for Organization B
    local org_b_member_id
    org_b_member_id=$(aws managedblockchain create-member \
        --invitation-id "${INVITATION_ID}" \
        --network-id "${NETWORK_ID}" \
        --member-configuration '{
            "Name": "'"${ORG_B_MEMBER}"'",
            "Description": "Healthcare Provider Member",
            "MemberFabricConfiguration": {
                "AdminUsername": "admin",
                "AdminPassword": "TempPassword123!"
            }
        }' \
        --query 'MemberId' --output text)
    
    export ORG_B_MEMBER_ID="$org_b_member_id"
    echo "ORG_B_MEMBER_ID=${ORG_B_MEMBER_ID}" >> deployment-state.env
    
    log_success "Created Organization B member: ${ORG_B_MEMBER_ID}"
    
    # Create peer node for Organization B
    local org_b_node_id
    org_b_node_id=$(aws managedblockchain create-node \
        --network-id "${NETWORK_ID}" \
        --member-id "${ORG_B_MEMBER_ID}" \
        --node-configuration '{
            "InstanceType": "bc.t3.medium",
            "AvailabilityZone": "'"${AWS_REGION}b"'"
        }' \
        --query 'NodeId' --output text)
    
    export ORG_B_NODE_ID="$org_b_node_id"
    echo "ORG_B_NODE_ID=${ORG_B_NODE_ID}" >> deployment-state.env
    
    log_success "Created Organization B peer node: ${ORG_B_NODE_ID}"
    
    # Wait for node to be available
    wait_for_resource \
        "aws managedblockchain get-node --network-id ${NETWORK_ID} --member-id ${ORG_B_MEMBER_ID} --node-id ${ORG_B_NODE_ID} --query 'Node.Status' --output text | grep -q AVAILABLE" \
        "Organization B peer node ${ORG_B_NODE_ID}" \
        600 \
        30
}

# Create chaincode
create_chaincode() {
    log_info "Creating cross-organization data sharing chaincode..."
    
    # Create chaincode directory and files
    mkdir -p chaincode/cross-org-data-sharing
    
    # Create package.json for chaincode
    cat > chaincode/cross-org-data-sharing/package.json << 'EOF'
{
  "name": "cross-org-data-sharing-chaincode",
  "version": "1.0.0",
  "description": "Cross-Organization Data Sharing Chaincode",
  "main": "index.js",
  "dependencies": {
    "fabric-contract-api": "^2.0.0"
  }
}
EOF
    
    # Create main chaincode file with data sharing logic
    cat > chaincode/cross-org-data-sharing/index.js << 'EOF'
const { Contract } = require('fabric-contract-api');

class CrossOrgDataSharingContract extends Contract {
    
    async initLedger(ctx) {
        console.log('Cross-organization data sharing ledger initialized');
        return 'Ledger initialized successfully';
    }
    
    // Create a data sharing agreement between organizations
    async createDataSharingAgreement(ctx, agreementId, agreementData) {
        const agreement = {
            agreementId,
            ...JSON.parse(agreementData),
            createdAt: new Date().toISOString(),
            status: 'ACTIVE',
            participants: [],
            accessLog: []
        };
        
        // Get the organization ID of the creator
        const creatorOrg = ctx.clientIdentity.getMSPID();
        agreement.creator = creatorOrg;
        agreement.participants.push(creatorOrg);
        
        await ctx.stub.putState(agreementId, Buffer.from(JSON.stringify(agreement)));
        
        // Emit event for cross-organization notification
        ctx.stub.setEvent('DataSharingAgreementCreated', Buffer.from(JSON.stringify({
            agreementId,
            creator: creatorOrg,
            timestamp: agreement.createdAt
        })));
        
        return JSON.stringify(agreement);
    }
    
    // Join an existing data sharing agreement
    async joinDataSharingAgreement(ctx, agreementId, participantData) {
        const agreementBytes = await ctx.stub.getState(agreementId);
        if (!agreementBytes || agreementBytes.length === 0) {
            throw new Error(`Agreement ${agreementId} does not exist`);
        }
        
        const agreement = JSON.parse(agreementBytes.toString());
        const participantOrg = ctx.clientIdentity.getMSPID();
        
        // Check if organization is already a participant
        if (agreement.participants.includes(participantOrg)) {
            throw new Error(`Organization ${participantOrg} is already a participant`);
        }
        
        // Add organization to participants
        agreement.participants.push(participantOrg);
        agreement.accessLog.push({
            action: 'JOINED',
            organization: participantOrg,
            timestamp: new Date().toISOString(),
            data: JSON.parse(participantData)
        });
        
        await ctx.stub.putState(agreementId, Buffer.from(JSON.stringify(agreement)));
        
        // Emit event for cross-organization notification
        ctx.stub.setEvent('OrganizationJoinedAgreement', Buffer.from(JSON.stringify({
            agreementId,
            participant: participantOrg,
            timestamp: new Date().toISOString()
        })));
        
        return JSON.stringify(agreement);
    }
    
    // Share data with specific organizations
    async shareData(ctx, agreementId, dataId, dataPayload, authorizedOrgs) {
        const agreementBytes = await ctx.stub.getState(agreementId);
        if (!agreementBytes || agreementBytes.length === 0) {
            throw new Error(`Agreement ${agreementId} does not exist`);
        }
        
        const agreement = JSON.parse(agreementBytes.toString());
        const sharerOrg = ctx.clientIdentity.getMSPID();
        
        // Verify organization is a participant
        if (!agreement.participants.includes(sharerOrg)) {
            throw new Error(`Organization ${sharerOrg} is not a participant in this agreement`);
        }
        
        const authorizedOrgList = JSON.parse(authorizedOrgs);
        
        // Create data sharing record
        const dataRecord = {
            dataId,
            agreementId,
            payload: JSON.parse(dataPayload),
            sharedBy: sharerOrg,
            authorizedOrganizations: authorizedOrgList,
            sharedAt: new Date().toISOString(),
            accessHistory: []
        };
        
        // Store data record
        const dataKey = `DATA_${agreementId}_${dataId}`;
        await ctx.stub.putState(dataKey, Buffer.from(JSON.stringify(dataRecord)));
        
        // Update agreement access log
        agreement.accessLog.push({
            action: 'DATA_SHARED',
            organization: sharerOrg,
            dataId: dataId,
            authorizedOrgs: authorizedOrgList,
            timestamp: dataRecord.sharedAt
        });
        
        await ctx.stub.putState(agreementId, Buffer.from(JSON.stringify(agreement)));
        
        // Emit event for data sharing notification
        ctx.stub.setEvent('DataShared', Buffer.from(JSON.stringify({
            agreementId,
            dataId,
            sharedBy: sharerOrg,
            authorizedOrgs: authorizedOrgList,
            timestamp: dataRecord.sharedAt
        })));
        
        return JSON.stringify(dataRecord);
    }
    
    // Access shared data (with access logging)
    async accessSharedData(ctx, agreementId, dataId) {
        const dataKey = `DATA_${agreementId}_${dataId}`;
        const dataBytes = await ctx.stub.getState(dataKey);
        if (!dataBytes || dataBytes.length === 0) {
            throw new Error(`Data ${dataId} does not exist in agreement ${agreementId}`);
        }
        
        const dataRecord = JSON.parse(dataBytes.toString());
        const accessorOrg = ctx.clientIdentity.getMSPID();
        
        // Check if organization is authorized to access this data
        if (!dataRecord.authorizedOrganizations.includes(accessorOrg)) {
            throw new Error(`Organization ${accessorOrg} is not authorized to access this data`);
        }
        
        // Log the access
        dataRecord.accessHistory.push({
            accessedBy: accessorOrg,
            accessedAt: new Date().toISOString(),
            clientId: ctx.clientIdentity.getID()
        });
        
        await ctx.stub.putState(dataKey, Buffer.from(JSON.stringify(dataRecord)));
        
        // Emit event for access logging
        ctx.stub.setEvent('DataAccessed', Buffer.from(JSON.stringify({
            agreementId,
            dataId,
            accessedBy: accessorOrg,
            timestamp: new Date().toISOString()
        })));
        
        // Return only the payload data, not the full record
        return JSON.stringify({
            dataId: dataRecord.dataId,
            payload: dataRecord.payload,
            sharedBy: dataRecord.sharedBy,
            sharedAt: dataRecord.sharedAt
        });
    }
    
    // Query all agreements for an organization
    async queryOrganizationAgreements(ctx) {
        const queryOrg = ctx.clientIdentity.getMSPID();
        
        const query = {
            selector: {
                participants: {
                    $in: [queryOrg]
                }
            }
        };
        
        const iterator = await ctx.stub.getQueryResult(JSON.stringify(query));
        const agreements = [];
        
        while (true) {
            const result = await iterator.next();
            if (result.done) break;
            
            const agreement = JSON.parse(result.value.value.toString());
            agreements.push({
                agreementId: agreement.agreementId,
                creator: agreement.creator,
                participants: agreement.participants,
                createdAt: agreement.createdAt,
                status: agreement.status
            });
        }
        
        return JSON.stringify(agreements);
    }
    
    // Get audit trail for an agreement
    async getAgreementAuditTrail(ctx, agreementId) {
        const agreementBytes = await ctx.stub.getState(agreementId);
        if (!agreementBytes || agreementBytes.length === 0) {
            throw new Error(`Agreement ${agreementId} does not exist`);
        }
        
        const agreement = JSON.parse(agreementBytes.toString());
        const accessorOrg = ctx.clientIdentity.getMSPID();
        
        // Verify organization is a participant
        if (!agreement.participants.includes(accessorOrg)) {
            throw new Error(`Organization ${accessorOrg} is not a participant in this agreement`);
        }
        
        return JSON.stringify({
            agreementId: agreement.agreementId,
            accessLog: agreement.accessLog
        });
    }
}

module.exports = CrossOrgDataSharingContract;
EOF
    
    # Package chaincode
    cd chaincode/cross-org-data-sharing
    npm init -y >/dev/null 2>&1 || true
    npm install fabric-contract-api >/dev/null 2>&1 || log_warning "Failed to install fabric-contract-api"
    cd ../..
    
    # Create chaincode archive
    tar -czf cross-org-data-sharing-chaincode.tar.gz -C chaincode cross-org-data-sharing/
    
    # Upload chaincode to S3
    aws s3 cp cross-org-data-sharing-chaincode.tar.gz "s3://${BUCKET_NAME}/"
    
    log_success "Created and uploaded cross-organization data sharing chaincode"
}

# Create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function for data validation and event processing..."
    
    # Create Lambda function code for data validation
    cat > lambda-function.js << 'EOF'
const AWS = require('aws-sdk');

const dynamodb = new AWS.DynamoDB.DocumentClient();
const eventbridge = new AWS.EventBridge();
const s3 = new AWS.S3();

exports.handler = async (event) => {
    try {
        console.log('Processing blockchain event:', JSON.stringify(event, null, 2));
        
        // Extract blockchain event data
        const blockchainEvent = {
            eventType: event.eventType || 'UNKNOWN',
            agreementId: event.agreementId,
            organizationId: event.organizationId,
            dataId: event.dataId,
            timestamp: event.timestamp || Date.now(),
            metadata: event.metadata || {}
        };
        
        // Validate event data
        if (!blockchainEvent.agreementId) {
            throw new Error('Agreement ID is required');
        }
        
        // Store audit trail in DynamoDB
        const auditRecord = {
            TransactionId: `${blockchainEvent.agreementId}-${blockchainEvent.timestamp}`,
            Timestamp: blockchainEvent.timestamp,
            EventType: blockchainEvent.eventType,
            AgreementId: blockchainEvent.agreementId,
            OrganizationId: blockchainEvent.organizationId,
            DataId: blockchainEvent.dataId,
            Metadata: blockchainEvent.metadata
        };
        
        await dynamodb.put({
            TableName: 'CrossOrgAuditTrail',
            Item: auditRecord
        }).promise();
        
        // Process different event types
        switch (blockchainEvent.eventType) {
            case 'DataSharingAgreementCreated':
                await processAgreementCreated(blockchainEvent);
                break;
            case 'OrganizationJoinedAgreement':
                await processOrganizationJoined(blockchainEvent);
                break;
            case 'DataShared':
                await processDataShared(blockchainEvent);
                break;
            case 'DataAccessed':
                await processDataAccessed(blockchainEvent);
                break;
            default:
                console.log(`Unknown event type: ${blockchainEvent.eventType}`);
        }
        
        // Send notification via EventBridge
        await eventbridge.putEvents({
            Entries: [{
                Source: 'cross-org.blockchain',
                DetailType: blockchainEvent.eventType,
                Detail: JSON.stringify(blockchainEvent)
            }]
        }).promise();
        
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Blockchain event processed successfully',
                eventType: blockchainEvent.eventType,
                agreementId: blockchainEvent.agreementId
            })
        };
        
    } catch (error) {
        console.error('Error processing blockchain event:', error);
        throw error;
    }
};

async function processAgreementCreated(event) {
    console.log(`Processing agreement creation: ${event.agreementId}`);
    
    // Create metadata record in S3
    const metadata = {
        agreementId: event.agreementId,
        creator: event.organizationId,
        createdAt: new Date(event.timestamp).toISOString(),
        status: 'ACTIVE',
        participants: [event.organizationId]
    };
    
    await s3.putObject({
        Bucket: process.env.BUCKET_NAME,
        Key: `agreements/${event.agreementId}/metadata.json`,
        Body: JSON.stringify(metadata, null, 2),
        ContentType: 'application/json'
    }).promise();
}

async function processOrganizationJoined(event) {
    console.log(`Processing organization join: ${event.organizationId} to ${event.agreementId}`);
    
    // Update participant notification
    // In production, this would send targeted notifications to all participants
}

async function processDataShared(event) {
    console.log(`Processing data sharing: ${event.dataId} in ${event.agreementId}`);
    
    // Validate data integrity and compliance
    // In production, this would perform additional validation checks
}

async function processDataAccessed(event) {
    console.log(`Processing data access: ${event.dataId} by ${event.organizationId}`);
    
    // Log access for compliance and audit purposes
    // In production, this would trigger additional compliance checks
}
EOF
    
    # Create Lambda deployment package
    zip lambda-function.zip lambda-function.js >/dev/null
    
    # Create Lambda trust policy
    cat > lambda-trust-policy.json << 'EOF'
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
    if aws iam get-role --role-name CrossOrgDataSharingLambdaRole >/dev/null 2>&1; then
        log_warning "IAM role CrossOrgDataSharingLambdaRole already exists"
    else
        aws iam create-role \
            --role-name CrossOrgDataSharingLambdaRole \
            --assume-role-policy-document file://lambda-trust-policy.json
        log_success "Created IAM role: CrossOrgDataSharingLambdaRole"
    fi
    
    # Attach policies to Lambda role
    aws iam attach-role-policy \
        --role-name CrossOrgDataSharingLambdaRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true
    
    aws iam attach-role-policy \
        --role-name CrossOrgDataSharingLambdaRole \
        --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess || true
    
    aws iam attach-role-policy \
        --role-name CrossOrgDataSharingLambdaRole \
        --policy-arn arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess || true
    
    aws iam attach-role-policy \
        --role-name CrossOrgDataSharingLambdaRole \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess || true
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 20
    
    # Create Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" >/dev/null 2>&1; then
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} already exists, updating..."
        aws lambda update-function-code \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --zip-file fileb://lambda-function.zip >/dev/null
    else
        aws lambda create-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --runtime nodejs18.x \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/CrossOrgDataSharingLambdaRole" \
            --handler lambda-function.handler \
            --zip-file fileb://lambda-function.zip \
            --timeout 60 \
            --memory-size 512 \
            --environment "Variables={BUCKET_NAME=${BUCKET_NAME}}" >/dev/null
        log_success "Created Lambda function: ${LAMBDA_FUNCTION_NAME}"
    fi
}

# Create EventBridge rules
create_eventbridge_rules() {
    log_info "Creating EventBridge rules for cross-organization notifications..."
    
    # Create EventBridge rule for data sharing events
    if aws events describe-rule --name CrossOrgDataSharingRule >/dev/null 2>&1; then
        log_warning "EventBridge rule CrossOrgDataSharingRule already exists"
    else
        aws events put-rule \
            --name CrossOrgDataSharingRule \
            --description "Rule for cross-organization data sharing events" \
            --event-pattern '{
                "source": ["cross-org.blockchain"],
                "detail-type": [
                    "DataSharingAgreementCreated",
                    "OrganizationJoinedAgreement", 
                    "DataShared",
                    "DataAccessed"
                ]
            }' \
            --state ENABLED >/dev/null
        log_success "Created EventBridge rule: CrossOrgDataSharingRule"
    fi
    
    # Create SNS topic for cross-organization notifications
    local topic_arn
    if aws sns get-topic-attributes --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:cross-org-notifications" >/dev/null 2>&1; then
        topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:cross-org-notifications"
        log_warning "SNS topic cross-org-notifications already exists"
    else
        topic_arn=$(aws sns create-topic \
            --name cross-org-notifications \
            --query 'TopicArn' --output text)
        log_success "Created SNS topic: $topic_arn"
    fi
    
    export TOPIC_ARN="$topic_arn"
    echo "TOPIC_ARN=${TOPIC_ARN}" >> deployment-state.env
    
    # Add EventBridge target to SNS topic
    aws events put-targets \
        --rule CrossOrgDataSharingRule \
        --targets "Id"="1","Arn"="${TOPIC_ARN}" >/dev/null || true
    
    # Grant EventBridge permission to publish to SNS
    aws sns add-permission \
        --topic-arn "${TOPIC_ARN}" \
        --label EventBridgePublish \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --action-name Publish >/dev/null 2>&1 || true
    
    log_success "Created EventBridge rules for cross-organization notifications"
}

# Create CloudWatch monitoring
create_cloudwatch_monitoring() {
    log_info "Creating CloudWatch monitoring for cross-organization operations..."
    
    # Create CloudWatch dashboard configuration
    cat > cross-org-dashboard.json << EOF
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/Lambda", "Invocations", "FunctionName", "${LAMBDA_FUNCTION_NAME}"],
          ["AWS/Lambda", "Errors", "FunctionName", "${LAMBDA_FUNCTION_NAME}"],
          ["AWS/Lambda", "Duration", "FunctionName", "${LAMBDA_FUNCTION_NAME}"]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "Cross-Organization Data Processing Metrics"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/Events", "MatchedEvents", "RuleName", "CrossOrgDataSharingRule"],
          ["AWS/Events", "InvocationsCount", "RuleName", "CrossOrgDataSharingRule"]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "Cross-Organization Event Processing"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", "CrossOrgAuditTrail"],
          ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", "CrossOrgAuditTrail"]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "Audit Trail Storage Metrics"
      }
    }
  ]
}
EOF
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name CrossOrgDataSharing \
        --dashboard-body file://cross-org-dashboard.json >/dev/null
    
    # Create alarm for Lambda errors
    aws cloudwatch put-metric-alarm \
        --alarm-name "CrossOrg-Lambda-Errors" \
        --alarm-description "Alert on cross-organization Lambda function errors" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --dimensions Name=FunctionName,Value="${LAMBDA_FUNCTION_NAME}" \
        --evaluation-periods 1 \
        --alarm-actions "${TOPIC_ARN}" >/dev/null
    
    log_success "Created CloudWatch monitoring for cross-organization operations"
}

# Create access control policies
create_access_control() {
    log_info "Creating access control and compliance monitoring..."
    
    # Create IAM policy for cross-organization access control
    cat > cross-org-access-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "managedblockchain:GetNetwork",
                "managedblockchain:GetMember",
                "managedblockchain:GetNode",
                "managedblockchain:ListMembers",
                "managedblockchain:ListNodes"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "managedblockchain:NetworkId": "${NETWORK_ID}"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/agreements/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:Query",
                "dynamodb:GetItem"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/CrossOrgAuditTrail"
        }
    ]
}
EOF
    
    # Create IAM policy
    local policy_arn
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CrossOrgDataSharingAccessPolicy" >/dev/null 2>&1; then
        log_warning "IAM policy CrossOrgDataSharingAccessPolicy already exists"
    else
        policy_arn=$(aws iam create-policy \
            --policy-name CrossOrgDataSharingAccessPolicy \
            --policy-document file://cross-org-access-policy.json \
            --query 'Policy.Arn' --output text)
        log_success "Created IAM policy: $policy_arn"
    fi
    
    log_success "Created access control and compliance monitoring"
}

# Main deployment function
main() {
    log_info "Starting Cross-Organization Data Sharing with Amazon Managed Blockchain deployment..."
    log_info "This deployment will take approximately 15-20 minutes"
    
    check_prerequisites
    setup_environment
    create_foundational_resources
    create_blockchain_network
    setup_organization_a
    setup_organization_b
    create_chaincode
    create_lambda_function
    create_eventbridge_rules
    create_cloudwatch_monitoring
    create_access_control
    
    # Clean up temporary files
    rm -f lambda-function.zip lambda-function.js lambda-trust-policy.json
    rm -f cross-org-dashboard.json cross-org-access-policy.json
    rm -f cross-org-data-sharing-chaincode.tar.gz
    rm -rf chaincode/
    
    log_success "Cross-Organization Data Sharing deployment completed successfully!"
    log_info ""
    log_info "Deployment Summary:"
    log_info "  Network ID: ${NETWORK_ID}"
    log_info "  Organization A Member ID: ${ORG_A_MEMBER_ID}"
    log_info "  Organization B Member ID: ${ORG_B_MEMBER_ID}"
    log_info "  S3 Bucket: ${BUCKET_NAME}"
    log_info "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log_info "  SNS Topic: ${TOPIC_ARN}"
    log_info ""
    log_info "State file saved to: deployment-state.env"
    log_info "To clean up resources, run: ./destroy.sh"
    log_info ""
    log_warning "Estimated cost: \$200-300 for full network setup"
    log_warning "Remember to run the destroy script when testing is complete"
}

# Run main function
main "$@"