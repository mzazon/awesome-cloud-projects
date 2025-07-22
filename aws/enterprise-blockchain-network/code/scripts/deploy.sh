#!/bin/bash

# Deploy script for Hyperledger Fabric Applications on Amazon Managed Blockchain
# Recipe: hyperledger-fabric-applications-managed-blockchain
# Description: Deploys a complete Hyperledger Fabric blockchain network with client infrastructure

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Cleanup on script exit
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Script failed with exit code $exit_code. Check logs above for details."
    fi
}

trap cleanup_on_exit EXIT

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check required permissions
    log "Checking AWS permissions..."
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    log "AWS Account ID: $account_id"
    
    # Check if jq is available (optional but helpful)
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some output formatting may be limited."
    fi
    
    # Check Node.js (for client application)
    if ! command -v node &> /dev/null; then
        warning "Node.js is not installed. Client application setup will be skipped."
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not set. Please set AWS_REGION or configure default region."
    fi
    
    # Generate unique identifiers for resources
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export NETWORK_NAME="fabric-network-${random_suffix}"
    export MEMBER_NAME="member-org-${random_suffix}"
    export VPC_ENDPOINT_NAME="blockchain-vpc-endpoint-${random_suffix}"
    export RANDOM_SUFFIX="$random_suffix"
    
    # Create state file to store resource IDs
    export STATE_FILE="/tmp/blockchain-deploy-state-${random_suffix}.env"
    
    log "Environment variables configured:"
    log "  AWS_REGION: $AWS_REGION"
    log "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
    log "  NETWORK_NAME: $NETWORK_NAME"
    log "  MEMBER_NAME: $MEMBER_NAME"
    log "  STATE_FILE: $STATE_FILE"
    
    # Save initial state
    cat > "$STATE_FILE" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
NETWORK_NAME=$NETWORK_NAME
MEMBER_NAME=$MEMBER_NAME
VPC_ENDPOINT_NAME=$VPC_ENDPOINT_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    success "Environment setup completed"
}

# Create VPC infrastructure
create_vpc_infrastructure() {
    log "Creating VPC infrastructure..."
    
    # Create VPC
    log "Creating VPC..."
    local vpc_result=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=blockchain-vpc-${RANDOM_SUFFIX}},{Key=Purpose,Value=ManagedBlockchain}]" \
        --output json)
    
    export VPC_ID=$(echo "$vpc_result" | jq -r '.Vpc.VpcId')
    log "VPC created: $VPC_ID"
    
    # Wait for VPC to be available
    aws ec2 wait vpc-available --vpc-ids "$VPC_ID"
    
    # Create subnet
    log "Creating subnet..."
    local subnet_result=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block 10.0.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=blockchain-subnet-${RANDOM_SUFFIX}},{Key=Purpose,Value=ManagedBlockchain}]" \
        --output json)
    
    export SUBNET_ID=$(echo "$subnet_result" | jq -r '.Subnet.SubnetId')
    log "Subnet created: $SUBNET_ID"
    
    # Create Internet Gateway (for client access)
    log "Creating Internet Gateway..."
    local igw_result=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=blockchain-igw-${RANDOM_SUFFIX}}]" \
        --output json)
    
    export IGW_ID=$(echo "$igw_result" | jq -r '.InternetGateway.InternetGatewayId')
    log "Internet Gateway created: $IGW_ID"
    
    # Attach Internet Gateway to VPC
    aws ec2 attach-internet-gateway \
        --internet-gateway-id "$IGW_ID" \
        --vpc-id "$VPC_ID"
    
    # Create route table and add route
    log "Configuring routing..."
    local route_table_id=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=true" \
        --query 'RouteTables[0].RouteTableId' --output text)
    
    aws ec2 create-route \
        --route-table-id "$route_table_id" \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id "$IGW_ID"
    
    # Update state file
    cat >> "$STATE_FILE" << EOF
VPC_ID=$VPC_ID
SUBNET_ID=$SUBNET_ID
IGW_ID=$IGW_ID
EOF
    
    success "VPC infrastructure created successfully"
}

# Create blockchain network
create_blockchain_network() {
    log "Creating Hyperledger Fabric blockchain network..."
    
    # Create the blockchain network
    log "Initiating network creation (this may take 10-15 minutes)..."
    aws managedblockchain create-network \
        --name "$NETWORK_NAME" \
        --description "Enterprise blockchain network for secure transactions - deployed via automation" \
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
            "Name": "'"$MEMBER_NAME"'",
            "Description": "Founding member organization - deployed via automation",
            "MemberFrameworkConfiguration": {
                "MemberFabricConfiguration": {
                    "AdminUsername": "admin",
                    "AdminPassword": "TempPassword123!"
                }
            }
        }' > /dev/null
    
    success "Network creation initiated"
    
    # Wait for network to become available
    log "Waiting for network creation to complete..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local network_status=$(aws managedblockchain list-networks \
            --query "Networks[?Name=='$NETWORK_NAME'].Status" \
            --output text)
        
        case "$network_status" in
            "AVAILABLE")
                success "Network is now available"
                break
                ;;
            "CREATE_FAILED")
                error "Network creation failed"
                ;;
            "")
                log "Network not found yet, waiting... (attempt $attempt/$max_attempts)"
                ;;
            *)
                log "Network status: $network_status (attempt $attempt/$max_attempts)"
                ;;
        esac
        
        if [ $attempt -eq $max_attempts ]; then
            error "Network creation timed out after $max_attempts attempts"
        fi
        
        sleep 30
        ((attempt++))
    done
    
    # Get the network ID
    export NETWORK_ID=$(aws managedblockchain list-networks \
        --query "Networks[?Name=='$NETWORK_NAME'].Id" \
        --output text)
    
    log "Network ID: $NETWORK_ID"
    
    # Update state file
    echo "NETWORK_ID=$NETWORK_ID" >> "$STATE_FILE"
    
    success "Blockchain network created successfully"
}

# Create member and peer node
create_peer_node() {
    log "Creating peer node..."
    
    # Get the member ID
    export MEMBER_ID=$(aws managedblockchain list-members \
        --network-id "$NETWORK_ID" \
        --query "Members[?Name=='$MEMBER_NAME'].Id" \
        --output text)
    
    log "Member ID: $MEMBER_ID"
    
    # Create peer node
    log "Initiating peer node creation (this may take 5-10 minutes)..."
    aws managedblockchain create-node \
        --network-id "$NETWORK_ID" \
        --member-id "$MEMBER_ID" \
        --node-configuration '{
            "InstanceType": "bc.t3.small",
            "AvailabilityZone": "'"${AWS_REGION}a"'"
        }' > /dev/null
    
    success "Peer node creation initiated"
    
    # Wait for node to become available
    log "Waiting for peer node creation to complete..."
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local node_status=$(aws managedblockchain list-nodes \
            --network-id "$NETWORK_ID" \
            --member-id "$MEMBER_ID" \
            --query "Nodes[0].Status" \
            --output text 2>/dev/null || echo "NONE")
        
        case "$node_status" in
            "AVAILABLE")
                success "Peer node is now available"
                break
                ;;
            "CREATE_FAILED")
                error "Peer node creation failed"
                ;;
            "NONE")
                log "Node not found yet, waiting... (attempt $attempt/$max_attempts)"
                ;;
            *)
                log "Node status: $node_status (attempt $attempt/$max_attempts)"
                ;;
        esac
        
        if [ $attempt -eq $max_attempts ]; then
            error "Peer node creation timed out after $max_attempts attempts"
        fi
        
        sleep 30
        ((attempt++))
    done
    
    # Get the node ID
    export NODE_ID=$(aws managedblockchain list-nodes \
        --network-id "$NETWORK_ID" \
        --member-id "$MEMBER_ID" \
        --query "Nodes[0].Id" \
        --output text)
    
    log "Node ID: $NODE_ID"
    
    # Update state file
    cat >> "$STATE_FILE" << EOF
MEMBER_ID=$MEMBER_ID
NODE_ID=$NODE_ID
EOF
    
    success "Peer node created successfully"
}

# Create VPC endpoint for blockchain access
create_vpc_endpoint() {
    log "Creating VPC endpoint for secure blockchain access..."
    
    # Create accessor (if needed for VPC endpoint)
    log "Creating blockchain accessor..."
    local accessor_result=$(aws managedblockchain create-accessor \
        --accessor-type BILLING_TOKEN \
        --client-request-token "$(uuidgen || date +%s)" \
        --output json 2>/dev/null || echo '{}')
    
    # Create VPC endpoint
    log "Creating VPC endpoint..."
    local vpc_endpoint_result=$(aws ec2 create-vpc-endpoint \
        --vpc-id "$VPC_ID" \
        --service-name "com.amazonaws.${AWS_REGION}.managedblockchain.${NETWORK_ID}" \
        --vpc-endpoint-type Interface \
        --subnet-ids "$SUBNET_ID" \
        --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=$VPC_ENDPOINT_NAME},{Key=Purpose,Value=ManagedBlockchain}]" \
        --output json 2>/dev/null || echo '{}')
    
    if [ "$(echo "$vpc_endpoint_result" | jq -r '.VpcEndpoint.VpcEndpointId // empty')" != "" ]; then
        export VPC_ENDPOINT_ID=$(echo "$vpc_endpoint_result" | jq -r '.VpcEndpoint.VpcEndpointId')
        log "VPC endpoint created: $VPC_ENDPOINT_ID"
        
        # Update state file
        echo "VPC_ENDPOINT_ID=$VPC_ENDPOINT_ID" >> "$STATE_FILE"
    else
        warning "VPC endpoint creation skipped or failed (may not be required for this configuration)"
    fi
    
    success "VPC endpoint configuration completed"
}

# Create client infrastructure
create_client_infrastructure() {
    log "Creating client infrastructure..."
    
    # Create security group for blockchain client
    log "Creating security group..."
    local sg_result=$(aws ec2 create-security-group \
        --group-name "blockchain-client-sg-${RANDOM_SUFFIX}" \
        --description "Security group for blockchain client instance" \
        --vpc-id "$VPC_ID" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=blockchain-client-sg-${RANDOM_SUFFIX}}]" \
        --output json)
    
    export SG_ID=$(echo "$sg_result" | jq -r '.GroupId')
    log "Security group created: $SG_ID"
    
    # Allow SSH access (restricted - modify as needed)
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 > /dev/null
    
    # Allow HTTPS for blockchain communication
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 > /dev/null
    
    # Get the latest Amazon Linux 2 AMI
    local ami_id=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    log "Using AMI: $ami_id"
    
    # Create user data script for instance setup
    local user_data=$(cat << 'EOF'
#!/bin/bash
yum update -y
yum install -y docker git

# Install Node.js via NodeSource
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

# Start Docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create application directory
mkdir -p /home/ec2-user/fabric-client-app
chown ec2-user:ec2-user /home/ec2-user/fabric-client-app

# Log completion
echo "Instance setup completed at $(date)" > /home/ec2-user/setup-complete.log
EOF
    )
    
    # Launch EC2 instance (only if we have a key pair)
    log "Checking for available key pairs..."
    local key_pairs=$(aws ec2 describe-key-pairs --query 'KeyPairs[0].KeyName' --output text 2>/dev/null || echo "None")
    
    if [ "$key_pairs" != "None" ] && [ "$key_pairs" != "" ]; then
        log "Launching EC2 instance with key pair: $key_pairs"
        local instance_result=$(aws ec2 run-instances \
            --image-id "$ami_id" \
            --count 1 \
            --instance-type t3.medium \
            --key-name "$key_pairs" \
            --security-group-ids "$SG_ID" \
            --subnet-id "$SUBNET_ID" \
            --associate-public-ip-address \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=blockchain-client-${RANDOM_SUFFIX}},{Key=Purpose,Value=ManagedBlockchain}]" \
            --user-data "$user_data" \
            --output json)
        
        export INSTANCE_ID=$(echo "$instance_result" | jq -r '.Instances[0].InstanceId')
        log "EC2 instance launched: $INSTANCE_ID"
        
        # Update state file
        echo "INSTANCE_ID=$INSTANCE_ID" >> "$STATE_FILE"
    else
        warning "No key pairs found. EC2 instance creation skipped."
        warning "Create a key pair and re-run if you need client instance access."
    fi
    
    # Update state file
    echo "SG_ID=$SG_ID" >> "$STATE_FILE"
    
    success "Client infrastructure created successfully"
}

# Setup client application
setup_client_application() {
    log "Setting up client application structure..."
    
    # Create local application directory
    local app_dir="./fabric-client-app"
    mkdir -p "$app_dir/chaincode"
    
    # Create package.json
    cat > "$app_dir/package.json" << 'EOF'
{
  "name": "fabric-blockchain-client",
  "version": "1.0.0",
  "description": "Sample Hyperledger Fabric client for Amazon Managed Blockchain",
  "main": "app.js",
  "dependencies": {
    "fabric-network": "^2.2.20",
    "fabric-client": "^1.4.22",
    "fabric-ca-client": "^2.2.20",
    "dotenv": "^16.0.0"
  },
  "scripts": {
    "start": "node app.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "keywords": ["blockchain", "hyperledger-fabric", "aws"],
  "author": "AWS Recipe Generator",
  "license": "MIT"
}
EOF
    
    # Create sample chaincode
    cat > "$app_dir/chaincode/asset-contract.js" << 'EOF'
'use strict';

const { Contract } = require('fabric-contract-api');

class AssetContract extends Contract {

    async initLedger(ctx) {
        console.info('============= START : Initialize Ledger ===========');
        const assets = [
            {
                ID: 'asset1',
                Owner: 'Alice',
                Value: 100,
                Timestamp: new Date().toISOString()
            },
            {
                ID: 'asset2',
                Owner: 'Bob',
                Value: 200,
                Timestamp: new Date().toISOString()
            }
        ];

        for (const asset of assets) {
            await ctx.stub.putState(asset.ID, Buffer.from(JSON.stringify(asset)));
            console.info(`Asset ${asset.ID} initialized`);
        }
        console.info('============= END : Initialize Ledger ===========');
    }

    async createAsset(ctx, id, owner, value) {
        console.info('============= START : Create Asset ===========');
        
        const exists = await this.assetExists(ctx, id);
        if (exists) {
            throw new Error(`The asset ${id} already exists`);
        }

        const asset = {
            ID: id,
            Owner: owner,
            Value: parseInt(value),
            Timestamp: new Date().toISOString()
        };
        
        await ctx.stub.putState(id, Buffer.from(JSON.stringify(asset)));
        console.info('============= END : Create Asset ===========');
        return JSON.stringify(asset);
    }

    async readAsset(ctx, id) {
        const assetJSON = await ctx.stub.getState(id);
        if (!assetJSON || assetJSON.length === 0) {
            throw new Error(`The asset ${id} does not exist`);
        }
        return assetJSON.toString();
    }

    async assetExists(ctx, id) {
        const assetJSON = await ctx.stub.getState(id);
        return assetJSON && assetJSON.length > 0;
    }

    async transferAsset(ctx, id, newOwner) {
        console.info('============= START : Transfer Asset ===========');
        
        const assetString = await this.readAsset(ctx, id);
        const asset = JSON.parse(assetString);
        
        asset.Owner = newOwner;
        asset.Timestamp = new Date().toISOString();
        
        await ctx.stub.putState(id, Buffer.from(JSON.stringify(asset)));
        console.info('============= END : Transfer Asset ===========');
        return JSON.stringify(asset);
    }

    async getAllAssets(ctx) {
        const allResults = [];
        const iterator = await ctx.stub.getStateByRange('', '');
        let result = await iterator.next();
        
        while (!result.done) {
            const strValue = Buffer.from(result.value.value).toString('utf8');
            let record;
            try {
                record = JSON.parse(strValue);
            } catch (err) {
                console.log(err);
                record = strValue;
            }
            allResults.push({ Key: result.value.key, Record: record });
            result = await iterator.next();
        }
        
        return JSON.stringify(allResults);
    }
}

module.exports = AssetContract;
EOF
    
    # Create environment file template
    cat > "$app_dir/.env.example" << EOF
# Blockchain Network Configuration
NETWORK_ID=$NETWORK_ID
MEMBER_ID=${MEMBER_ID:-your-member-id}
NODE_ID=${NODE_ID:-your-node-id}
AWS_REGION=$AWS_REGION

# Certificate and Key Paths (to be configured after certificate generation)
CERT_PATH=./certs/admin-cert.pem
KEY_PATH=./certs/admin-key.pem
CA_CERT_PATH=./certs/ca-cert.pem

# Connection Profile
CONNECTION_PROFILE_PATH=./connection-profile.json
EOF
    
    # Create basic README for the client application
    cat > "$app_dir/README.md" << 'EOF'
# Hyperledger Fabric Client Application

This directory contains a sample client application for interacting with the Amazon Managed Blockchain network.

## Setup

1. Install dependencies:
   ```bash
   npm install
   ```

2. Configure environment:
   ```bash
   cp .env.example .env
   # Edit .env with your network details
   ```

3. Download certificates from AWS Managed Blockchain console

4. Update connection profile with your network endpoints

## Usage

The asset contract provides basic CRUD operations for blockchain assets:

- Create assets
- Read asset details
- Transfer asset ownership
- Query all assets

See the chaincode in `chaincode/asset-contract.js` for implementation details.

## Next Steps

1. Install and instantiate the chaincode on your blockchain network
2. Configure connection profiles with peer and orderer endpoints
3. Implement client applications using the Fabric SDK

For detailed instructions, refer to the AWS Managed Blockchain documentation.
EOF
    
    log "Client application directory: $app_dir"
    success "Client application structure created successfully"
}

# Display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    echo
    echo "🔗 Blockchain Network:"
    echo "  Network Name: $NETWORK_NAME"
    echo "  Network ID: $NETWORK_ID"
    echo "  Member Name: $MEMBER_NAME"
    echo "  Member ID: $MEMBER_ID"
    echo "  Node ID: $NODE_ID"
    echo
    echo "🌐 Network Infrastructure:"
    echo "  VPC ID: $VPC_ID"
    echo "  Subnet ID: $SUBNET_ID"
    echo "  Security Group: $SG_ID"
    if [ -n "${INSTANCE_ID:-}" ]; then
        echo "  EC2 Instance: $INSTANCE_ID"
    fi
    if [ -n "${VPC_ENDPOINT_ID:-}" ]; then
        echo "  VPC Endpoint: $VPC_ENDPOINT_ID"
    fi
    echo
    echo "📁 Application:"
    echo "  Client App Directory: ./fabric-client-app"
    echo "  State File: $STATE_FILE"
    echo
    echo "⚠️  Important Next Steps:"
    echo "1. Download member certificates from AWS Console"
    echo "2. Configure connection profiles for client applications"
    echo "3. Deploy and instantiate chaincode"
    echo "4. Test blockchain transactions"
    echo
    echo "💰 Cost Management:"
    echo "  - Monitor blockchain network charges in AWS Billing"
    echo "  - Use destroy.sh script to clean up resources when done"
    echo
    echo "📖 Documentation:"
    echo "  - AWS Managed Blockchain: https://docs.aws.amazon.com/managed-blockchain/"
    echo "  - Hyperledger Fabric: https://hyperledger-fabric.readthedocs.io/"
    echo
    success "Deployment completed successfully!"
    echo "State saved to: $STATE_FILE"
}

# Main deployment function
main() {
    echo "🚀 Starting Hyperledger Fabric Blockchain Deployment"
    echo "====================================================="
    echo
    
    check_prerequisites
    setup_environment
    create_vpc_infrastructure
    create_blockchain_network
    create_peer_node
    create_vpc_endpoint
    create_client_infrastructure
    setup_client_application
    display_summary
    
    echo
    success "All deployment steps completed successfully!"
    echo "Use ./destroy.sh to clean up resources when finished."
}

# Run main function
main "$@"