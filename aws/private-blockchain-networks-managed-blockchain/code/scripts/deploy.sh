#!/bin/bash

#######################################
# AWS Private Blockchain Networks Deployment Script
# Recipe: Establishing Private Blockchain Networks with Amazon Managed Blockchain
# 
# This script deploys a complete blockchain infrastructure including:
# - Amazon Managed Blockchain network and member
# - VPC endpoint for secure connectivity
# - EC2 instance for blockchain client operations
# - IAM roles and security groups
# - Hyperledger Fabric client setup
#######################################

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Installing jq for JSON parsing..."
        if command -v yum &> /dev/null; then
            sudo yum install -y jq
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        else
            error "Please install jq manually for JSON parsing"
        fi
    fi
    
    # Verify required permissions
    info "Verifying AWS permissions..."
    aws managedblockchain list-networks --max-results 1 &> /dev/null || \
        error "Insufficient permissions for Amazon Managed Blockchain"
    
    aws ec2 describe-vpcs --max-items 1 &> /dev/null || \
        error "Insufficient permissions for EC2/VPC operations"
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not configured. Please set a region."
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export NETWORK_NAME="SupplyChainNetwork-${RANDOM_SUFFIX}"
    export MEMBER_NAME="OrganizationA-${RANDOM_SUFFIX}"
    export ADMIN_USER="admin"
    export ADMIN_PASSWORD="TempPassword123!"
    
    # Create deployment directory
    DEPLOYMENT_DIR="blockchain-deployment-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${DEPLOYMENT_DIR}"
    cd "${DEPLOYMENT_DIR}"
    
    log "Environment setup completed"
    info "Network Name: ${NETWORK_NAME}"
    info "Member Name: ${MEMBER_NAME}"
    info "AWS Region: ${AWS_REGION}"
    info "Deployment Directory: $(pwd)"
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for Managed Blockchain..."
    
    # Check if role already exists
    if aws iam get-role --role-name ManagedBlockchainRole &> /dev/null; then
        warn "IAM role ManagedBlockchainRole already exists, skipping creation"
        return 0
    fi
    
    # Create trust policy document
    cat > trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "managedblockchain.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name ManagedBlockchainRole \
        --assume-role-policy-document file://trust-policy.json \
        --description "IAM role for Amazon Managed Blockchain operations" \
        --tags Key=Project,Value=SupplyChain Key=Environment,Value=Production
    
    # Attach required policies
    aws iam attach-role-policy \
        --role-name ManagedBlockchainRole \
        --policy-arn arn:aws:iam::aws:policy/AmazonManagedBlockchainFullAccess
    
    # Wait for role propagation
    sleep 10
    
    log "IAM role created successfully"
}

# Function to create blockchain network
create_blockchain_network() {
    log "Creating blockchain network..."
    
    # Create network configuration file
    cat > network-config.json << EOF
{
    "Name": "${NETWORK_NAME}",
    "Description": "Private blockchain network for supply chain tracking",
    "Framework": "HYPERLEDGER_FABRIC",
    "FrameworkVersion": "2.2",
    "FrameworkConfiguration": {
        "Fabric": {
            "Edition": "STANDARD"
        }
    },
    "VotingPolicy": {
        "ApprovalThresholdPolicy": {
            "ThresholdPercentage": 50,
            "ProposalDurationInHours": 24,
            "ThresholdComparator": "GREATER_THAN"
        }
    },
    "MemberConfiguration": {
        "Name": "${MEMBER_NAME}",
        "Description": "Founding member of supply chain network",
        "MemberFrameworkConfiguration": {
            "Fabric": {
                "AdminUsername": "${ADMIN_USER}",
                "AdminPassword": "${ADMIN_PASSWORD}"
            }
        }
    },
    "Tags": {
        "Environment": "Production",
        "Project": "SupplyChain"
    }
}
EOF
    
    # Create the blockchain network
    info "Creating blockchain network (this may take 10-30 minutes)..."
    NETWORK_ID=$(aws managedblockchain create-network \
        --cli-input-json file://network-config.json \
        --query 'NetworkId' --output text)
    
    if [ -z "$NETWORK_ID" ]; then
        error "Failed to create blockchain network"
    fi
    
    export NETWORK_ID
    echo "NETWORK_ID=${NETWORK_ID}" >> ../blockchain-vars.env
    
    log "Blockchain network created with ID: ${NETWORK_ID}"
    
    # Wait for network to become available
    info "Waiting for network to become available..."
    while true; do
        STATUS=$(aws managedblockchain get-network \
            --network-id "${NETWORK_ID}" \
            --query 'Network.Status' --output text)
        
        if [ "$STATUS" = "AVAILABLE" ]; then
            log "Network is now available"
            break
        elif [ "$STATUS" = "CREATE_FAILED" ]; then
            error "Network creation failed"
        else
            info "Network status: ${STATUS}, waiting..."
            sleep 30
        fi
    done
}

# Function to get member information
get_member_info() {
    log "Retrieving member information..."
    
    # Get member ID from network
    MEMBER_ID=$(aws managedblockchain list-members \
        --network-id "${NETWORK_ID}" \
        --query 'Members[0].Id' --output text)
    
    if [ -z "$MEMBER_ID" ] || [ "$MEMBER_ID" = "None" ]; then
        error "Failed to retrieve member ID"
    fi
    
    export MEMBER_ID
    echo "MEMBER_ID=${MEMBER_ID}" >> ../blockchain-vars.env
    
    # Get certificate authority endpoint
    CA_ENDPOINT=$(aws managedblockchain get-member \
        --network-id "${NETWORK_ID}" \
        --member-id "${MEMBER_ID}" \
        --query 'Member.FrameworkAttributes.Fabric.CaEndpoint' \
        --output text)
    
    export CA_ENDPOINT
    echo "CA_ENDPOINT=${CA_ENDPOINT}" >> ../blockchain-vars.env
    
    log "Member ID: ${MEMBER_ID}"
    log "CA Endpoint: ${CA_ENDPOINT}"
}

# Function to create VPC endpoint
create_vpc_endpoint() {
    log "Creating VPC endpoint for blockchain access..."
    
    # Get default VPC ID
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
        error "No default VPC found. Please create a VPC first."
    fi
    
    export VPC_ID
    echo "VPC_ID=${VPC_ID}" >> ../blockchain-vars.env
    
    # Get subnet ID for VPC endpoint
    SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[0].SubnetId' --output text)
    
    export SUBNET_ID
    echo "SUBNET_ID=${SUBNET_ID}" >> ../blockchain-vars.env
    
    # Create security group for VPC endpoint
    info "Creating security group..."
    SG_ID=$(aws ec2 create-security-group \
        --group-name "managed-blockchain-sg-${RANDOM_SUFFIX}" \
        --description "Security group for Managed Blockchain VPC endpoint" \
        --vpc-id "${VPC_ID}" \
        --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=managed-blockchain-sg},{Key=Project,Value=SupplyChain}]' \
        --query 'GroupId' --output text)
    
    export SG_ID
    echo "SG_ID=${SG_ID}" >> ../blockchain-vars.env
    
    # Add inbound rules for Hyperledger Fabric
    aws ec2 authorize-security-group-ingress \
        --group-id "${SG_ID}" \
        --protocol tcp \
        --port 30001 \
        --cidr 10.0.0.0/8 \
        --tag-specifications 'ResourceType=security-group-rule,Tags=[{Key=Purpose,Value=BlockchainAccess}]'
    
    aws ec2 authorize-security-group-ingress \
        --group-id "${SG_ID}" \
        --protocol tcp \
        --port 30002 \
        --cidr 10.0.0.0/8
    
    # Add peer communication rules
    aws ec2 authorize-security-group-ingress \
        --group-id "${SG_ID}" \
        --protocol tcp \
        --port 7051 \
        --source-group "${SG_ID}"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "${SG_ID}" \
        --protocol tcp \
        --port 7053 \
        --source-group "${SG_ID}"
    
    # Add SSH access for EC2 management
    aws ec2 authorize-security-group-ingress \
        --group-id "${SG_ID}" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0
    
    # Create VPC endpoint
    info "Creating VPC endpoint..."
    ENDPOINT_ID=$(aws ec2 create-vpc-endpoint \
        --vpc-id "${VPC_ID}" \
        --service-name "com.amazonaws.${AWS_REGION}.managedblockchain" \
        --subnet-ids "${SUBNET_ID}" \
        --security-group-ids "${SG_ID}" \
        --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=blockchain-endpoint},{Key=Project,Value=SupplyChain}]' \
        --query 'VpcEndpoint.VpcEndpointId' --output text)
    
    export ENDPOINT_ID
    echo "ENDPOINT_ID=${ENDPOINT_ID}" >> ../blockchain-vars.env
    
    log "VPC endpoint created: ${ENDPOINT_ID}"
    log "Security group created: ${SG_ID}"
}

# Function to create peer node
create_peer_node() {
    log "Creating peer node..."
    
    # Create peer node configuration
    cat > node-config.json << EOF
{
    "NetworkId": "${NETWORK_ID}",
    "MemberId": "${MEMBER_ID}",
    "NodeConfiguration": {
        "InstanceType": "bc.t3.small",
        "AvailabilityZone": "${AWS_REGION}a"
    },
    "Tags": {
        "Environment": "Production",
        "NodeType": "Peer",
        "Project": "SupplyChain"
    }
}
EOF
    
    # Create the peer node
    info "Creating peer node (this may take 10-20 minutes)..."
    NODE_ID=$(aws managedblockchain create-node \
        --cli-input-json file://node-config.json \
        --query 'NodeId' --output text)
    
    if [ -z "$NODE_ID" ]; then
        error "Failed to create peer node"
    fi
    
    export NODE_ID
    echo "NODE_ID=${NODE_ID}" >> ../blockchain-vars.env
    
    log "Peer node created with ID: ${NODE_ID}"
    
    # Wait for node to become available
    info "Waiting for node to become available..."
    while true; do
        STATUS=$(aws managedblockchain get-node \
            --network-id "${NETWORK_ID}" \
            --member-id "${MEMBER_ID}" \
            --node-id "${NODE_ID}" \
            --query 'Node.Status' --output text)
        
        if [ "$STATUS" = "AVAILABLE" ]; then
            log "Peer node is now available"
            break
        elif [ "$STATUS" = "CREATE_FAILED" ]; then
            error "Peer node creation failed"
        else
            info "Node status: ${STATUS}, waiting..."
            sleep 30
        fi
    done
    
    # Get node endpoint
    NODE_ENDPOINT=$(aws managedblockchain get-node \
        --network-id "${NETWORK_ID}" \
        --member-id "${MEMBER_ID}" \
        --node-id "${NODE_ID}" \
        --query 'Node.FrameworkAttributes.Fabric.PeerEndpoint' \
        --output text)
    
    export NODE_ENDPOINT
    echo "NODE_ENDPOINT=${NODE_ENDPOINT}" >> ../blockchain-vars.env
    
    log "Node endpoint: ${NODE_ENDPOINT}"
}

# Function to create EC2 instance
create_ec2_instance() {
    log "Creating EC2 instance for blockchain client..."
    
    # Create key pair for EC2 access
    KEY_NAME="blockchain-client-key-${RANDOM_SUFFIX}"
    aws ec2 create-key-pair \
        --key-name "${KEY_NAME}" \
        --query 'KeyMaterial' --output text > "${KEY_NAME}.pem"
    
    chmod 400 "${KEY_NAME}.pem"
    export KEY_NAME
    echo "KEY_NAME=${KEY_NAME}" >> ../blockchain-vars.env
    
    # Get latest Amazon Linux 2 AMI
    AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    # Create user data script
    cat > user-data.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y docker git jq

# Start Docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install Node.js via NVM
su - ec2-user -c '
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install 16
nvm use 16
nvm alias default 16
'

# Download Hyperledger Fabric binaries
su - ec2-user -c '
cd /home/ec2-user
curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.2.0 1.4.9
echo "export PATH=/home/ec2-user/fabric-samples/bin:\$PATH" >> ~/.bashrc
mkdir -p /home/ec2-user/blockchain-client/{crypto-config,channel-artifacts}
'

# Create setup completion marker
touch /home/ec2-user/setup-complete
EOF
    
    # Launch EC2 instance
    info "Launching EC2 instance..."
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "${AMI_ID}" \
        --instance-type t3.medium \
        --key-name "${KEY_NAME}" \
        --security-group-ids "${SG_ID}" \
        --subnet-id "${SUBNET_ID}" \
        --user-data file://user-data.sh \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=blockchain-client},{Key=Project,Value=SupplyChain}]' \
        --associate-public-ip-address \
        --query 'Instances[0].InstanceId' --output text)
    
    export INSTANCE_ID
    echo "INSTANCE_ID=${INSTANCE_ID}" >> ../blockchain-vars.env
    
    log "EC2 instance launched: ${INSTANCE_ID}"
    
    # Wait for instance to be running
    info "Waiting for instance to be running..."
    aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"
    
    # Get public IP
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids "${INSTANCE_ID}" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    export PUBLIC_IP
    echo "PUBLIC_IP=${PUBLIC_IP}" >> ../blockchain-vars.env
    
    log "EC2 instance is running at: ${PUBLIC_IP}"
    
    # Wait for user data script to complete
    info "Waiting for EC2 setup to complete (this may take 5-10 minutes)..."
    for i in {1..20}; do
        if ssh -i "${KEY_NAME}.pem" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
           ec2-user@"${PUBLIC_IP}" "test -f /home/ec2-user/setup-complete" 2>/dev/null; then
            log "EC2 setup completed successfully"
            break
        fi
        info "Setup in progress... (attempt $i/20)"
        sleep 30
    done
}

# Function to create monitoring
create_monitoring() {
    log "Setting up monitoring and logging..."
    
    # Create CloudWatch log group for blockchain logs
    aws logs create-log-group \
        --log-group-name "/aws/managedblockchain/${NETWORK_NAME}" \
        --tags Project=SupplyChain,Environment=Production \
        || warn "Log group may already exist"
    
    # Check if VPC Flow Logs role exists
    if ! aws iam get-role --role-name flowlogsRole &> /dev/null; then
        warn "VPC Flow Logs role doesn't exist. Creating basic monitoring setup..."
    else
        # Enable VPC Flow Logs
        aws ec2 create-flow-logs \
            --resource-type VPC \
            --resource-ids "${VPC_ID}" \
            --traffic-type ALL \
            --log-destination-type cloud-watch-logs \
            --log-group-name VPCFlowLogs \
            --deliver-logs-permission-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/flowlogsRole" \
            || warn "Failed to create VPC Flow Logs"
    fi
    
    log "Monitoring setup completed"
}

# Function to create chaincode policy
create_chaincode_policy() {
    log "Creating IAM policy for chaincode execution..."
    
    # Create chaincode policy document
    cat > chaincode-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "managedblockchain:*",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Create the policy
    aws iam create-policy \
        --policy-name "BlockchainChaincodePolicy-${RANDOM_SUFFIX}" \
        --policy-document file://chaincode-policy.json \
        --description "Policy for blockchain chaincode execution" \
        --tags Key=Project,Value=SupplyChain \
        || warn "Policy may already exist"
    
    log "Chaincode policy created"
}

# Function to save configuration
save_configuration() {
    log "Saving network configuration..."
    
    # Create comprehensive network configuration file
    cat > ../network-info.json << EOF
{
    "NetworkId": "${NETWORK_ID}",
    "NetworkName": "${NETWORK_NAME}",
    "MemberId": "${MEMBER_ID}",
    "MemberName": "${MEMBER_NAME}",
    "NodeId": "${NODE_ID}",
    "NodeEndpoint": "${NODE_ENDPOINT}",
    "CAEndpoint": "${CA_ENDPOINT}",
    "VPCEndpoint": "${ENDPOINT_ID}",
    "VPCId": "${VPC_ID}",
    "SubnetId": "${SUBNET_ID}",
    "SecurityGroupId": "${SG_ID}",
    "EC2Instance": "${INSTANCE_ID}",
    "PublicIP": "${PUBLIC_IP}",
    "KeyName": "${KEY_NAME}",
    "Region": "${AWS_REGION}",
    "AccountId": "${AWS_ACCOUNT_ID}",
    "DeploymentDate": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    
    # Create sample chaincode file
    cat > ../sample-chaincode.go << 'EOF'
package main

import (
    "encoding/json"
    "fmt"
    "github.com/hyperledger/fabric-contract-api-go/contractapi"
)

type SmartContract struct {
    contractapi.Contract
}

type Asset struct {
    ID          string `json:"ID"`
    Description string `json:"description"`
    Owner       string `json:"owner"`
    Timestamp   string `json:"timestamp"`
}

func (s *SmartContract) CreateAsset(ctx contractapi.TransactionContextInterface, id string, description string, owner string, timestamp string) error {
    asset := Asset{
        ID:          id,
        Description: description,
        Owner:       owner,
        Timestamp:   timestamp,
    }
    
    assetJSON, err := json.Marshal(asset)
    if err != nil {
        return err
    }
    
    return ctx.GetStub().PutState(id, assetJSON)
}

func (s *SmartContract) QueryAsset(ctx contractapi.TransactionContextInterface, id string) (*Asset, error) {
    assetJSON, err := ctx.GetStub().GetState(id)
    if err != nil {
        return nil, fmt.Errorf("failed to read from world state: %v", err)
    }
    if assetJSON == nil {
        return nil, fmt.Errorf("the asset %s does not exist", id)
    }
    
    var asset Asset
    err = json.Unmarshal(assetJSON, &asset)
    if err != nil {
        return nil, err
    }
    
    return &asset, nil
}

func main() {
    assetChaincode, err := contractapi.NewChaincode(&SmartContract{})
    if err != nil {
        panic(err.Error())
    }
    
    if err := assetChaincode.Start(); err != nil {
        panic(err.Error())
    }
}
EOF
    
    # Create connection instructions
    cat > ../connection-instructions.md << EOF
# Blockchain Network Connection Instructions

## Network Information
- **Network ID**: ${NETWORK_ID}
- **Network Name**: ${NETWORK_NAME}
- **Member ID**: ${MEMBER_ID}
- **Node Endpoint**: ${NODE_ENDPOINT}
- **CA Endpoint**: ${CA_ENDPOINT}
- **EC2 Public IP**: ${PUBLIC_IP}

## Connecting to EC2 Instance

\`\`\`bash
ssh -i ${KEY_NAME}.pem ec2-user@${PUBLIC_IP}
\`\`\`

## Hyperledger Fabric Commands

Once connected to the EC2 instance, you can use these commands:

\`\`\`bash
# Check Fabric version
peer version

# Set environment variables for peer operations
export CORE_PEER_LOCALMSPID=${MEMBER_NAME}MSP
export CORE_PEER_MSPCONFIGPATH=/opt/home/managedblockchain-tls-chain.pem
export CORE_PEER_ADDRESS=${NODE_ENDPOINT}

# List channels
peer channel list

# Query chaincode (after deployment)
peer chaincode query -C mychannel -n mychaincode -c '{"Args":["QueryAsset","asset1"]}'
\`\`\`

## Next Steps

1. Download the CA certificate from the CA endpoint
2. Configure your Hyperledger Fabric client
3. Create channels for private transactions
4. Deploy and test chaincode
5. Implement business logic for your use case

For detailed instructions, refer to the original recipe documentation.
EOF
    
    log "Configuration saved successfully"
    info "Network configuration: ../network-info.json"
    info "Connection instructions: ../connection-instructions.md"
    info "Environment variables: ../blockchain-vars.env"
}

# Function to run deployment validation
validate_deployment() {
    log "Validating deployment..."
    
    # Check network status
    NETWORK_STATUS=$(aws managedblockchain get-network \
        --network-id "${NETWORK_ID}" \
        --query 'Network.Status' --output text)
    
    if [ "$NETWORK_STATUS" != "AVAILABLE" ]; then
        error "Network is not available. Status: ${NETWORK_STATUS}"
    fi
    
    # Check member status
    MEMBER_STATUS=$(aws managedblockchain get-member \
        --network-id "${NETWORK_ID}" \
        --member-id "${MEMBER_ID}" \
        --query 'Member.Status' --output text)
    
    if [ "$MEMBER_STATUS" != "AVAILABLE" ]; then
        error "Member is not available. Status: ${MEMBER_STATUS}"
    fi
    
    # Check node status
    NODE_STATUS=$(aws managedblockchain get-node \
        --network-id "${NETWORK_ID}" \
        --member-id "${MEMBER_ID}" \
        --node-id "${NODE_ID}" \
        --query 'Node.Status' --output text)
    
    if [ "$NODE_STATUS" != "AVAILABLE" ]; then
        error "Node is not available. Status: ${NODE_STATUS}"
    fi
    
    # Check VPC endpoint status
    ENDPOINT_STATUS=$(aws ec2 describe-vpc-endpoints \
        --vpc-endpoint-ids "${ENDPOINT_ID}" \
        --query 'VpcEndpoints[0].State' --output text)
    
    if [ "$ENDPOINT_STATUS" != "available" ]; then
        warn "VPC endpoint is not available. Status: ${ENDPOINT_STATUS}"
    fi
    
    # Check EC2 instance status
    INSTANCE_STATUS=$(aws ec2 describe-instances \
        --instance-ids "${INSTANCE_ID}" \
        --query 'Reservations[0].Instances[0].State.Name' --output text)
    
    if [ "$INSTANCE_STATUS" != "running" ]; then
        warn "EC2 instance is not running. Status: ${INSTANCE_STATUS}"
    fi
    
    log "Deployment validation completed successfully"
}

# Function to display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    echo
    echo "========================================"
    echo "    BLOCKCHAIN NETWORK DEPLOYMENT"
    echo "========================================"
    echo
    echo "Network Details:"
    echo "  Network ID: ${NETWORK_ID}"
    echo "  Network Name: ${NETWORK_NAME}"
    echo "  Member ID: ${MEMBER_ID}"
    echo "  Node ID: ${NODE_ID}"
    echo
    echo "Access Information:"
    echo "  EC2 Public IP: ${PUBLIC_IP}"
    echo "  SSH Key: ${KEY_NAME}.pem"
    echo "  SSH Command: ssh -i ${KEY_NAME}.pem ec2-user@${PUBLIC_IP}"
    echo
    echo "Configuration Files:"
    echo "  Network Info: ../network-info.json"
    echo "  Environment Variables: ../blockchain-vars.env"
    echo "  Connection Instructions: ../connection-instructions.md"
    echo
    echo "Next Steps:"
    echo "  1. SSH into the EC2 instance"
    echo "  2. Configure Hyperledger Fabric client"
    echo "  3. Create blockchain channels"
    echo "  4. Deploy and test chaincode"
    echo
    warn "Remember to run ./destroy.sh to clean up resources when finished"
    echo "========================================"
}

# Main execution flow
main() {
    log "Starting blockchain network deployment..."
    
    check_prerequisites
    setup_environment
    create_iam_role
    create_blockchain_network
    get_member_info
    create_vpc_endpoint
    create_peer_node
    create_ec2_instance
    create_monitoring
    create_chaincode_policy
    save_configuration
    validate_deployment
    display_summary
    
    log "Deployment script completed successfully!"
}

# Trap errors and cleanup on failure
trap 'error "Deployment failed at line $LINENO. Check the logs for details."' ERR

# Run main function
main "$@"