#!/bin/bash

# -----------------------------------------------------------------------------
# User Data Script for Blockchain Client EC2 Instance
# This script installs and configures Hyperledger Fabric client tools
# -----------------------------------------------------------------------------

# Variables passed from Terraform
REGION="${region}"
NETWORK_ID="${network_id}"
MEMBER_ID="${member_id}"
NODE_ID="${node_id}"
HYPERLEDGER_VERSION="${hyperledger_version}"

# Log all output
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting blockchain client setup..."
echo "Region: $REGION"
echo "Network ID: $NETWORK_ID"
echo "Member ID: $MEMBER_ID"
echo "Node ID: $NODE_ID"
echo "Hyperledger Version: $HYPERLEDGER_VERSION"

# Update system packages
echo "Updating system packages..."
yum update -y

# Install required packages
echo "Installing required packages..."
yum install -y \
    docker \
    git \
    wget \
    curl \
    unzip \
    jq \
    tree

# Start and enable Docker
echo "Starting Docker service..."
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -a -G docker ec2-user

# Install Docker Compose
echo "Installing Docker Compose..."
DOCKER_COMPOSE_VERSION="1.29.2"
curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create symbolic link for docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Install AWS CLI v2
echo "Installing AWS CLI v2..."
cd /tmp
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Configure AWS CLI to use instance region
echo "Configuring AWS CLI..."
runuser -l ec2-user -c "aws configure set default.region $REGION"

# Install Node.js via NVM
echo "Installing Node.js..."
runuser -l ec2-user -c '
export NVM_DIR="$HOME/.nvm"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source $NVM_DIR/nvm.sh
nvm install 16
nvm use 16
nvm alias default 16
echo "export NVM_DIR=\"\$HOME/.nvm\"" >> ~/.bashrc
echo "[ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"" >> ~/.bashrc
echo "[ -s \"\$NVM_DIR/bash_completion\" ] && \\. \"\$NVM_DIR/bash_completion\"" >> ~/.bashrc
'

# Download and install Hyperledger Fabric binaries
echo "Installing Hyperledger Fabric binaries..."
runuser -l ec2-user -c "
cd /home/ec2-user
curl -sSL https://bit.ly/2ysbOFE | bash -s -- $HYPERLEDGER_VERSION 1.4.9
"

# Add Fabric binaries to PATH
echo "Configuring Fabric binaries PATH..."
runuser -l ec2-user -c '
echo "export PATH=/home/ec2-user/fabric-samples/bin:\$PATH" >> ~/.bashrc
echo "export FABRIC_CFG_PATH=/home/ec2-user/fabric-samples/config" >> ~/.bashrc
'

# Create blockchain client directory structure
echo "Creating blockchain client directory structure..."
runuser -l ec2-user -c '
mkdir -p /home/ec2-user/blockchain-client/{crypto-config,channel-artifacts,chaincode,scripts}
cd /home/ec2-user/blockchain-client
'

# Download CA certificate for Managed Blockchain
echo "Setting up certificate authority configuration..."
runuser -l ec2-user -c "
cd /home/ec2-user/blockchain-client
mkdir -p crypto-config/managedblockchain-tls
cd crypto-config/managedblockchain-tls

# Download the AWS managed blockchain TLS certificate
aws s3 cp s3://us-east-1-managedblockchain/etc/managedblockchain-tls-chain.pem managedblockchain-tls-chain.pem --region $REGION 2>/dev/null || {
    echo 'Note: TLS chain file not available via S3, will need to be configured manually'
}
"

# Create network configuration file
echo "Creating network configuration file..."
runuser -l ec2-user -c "
cat > /home/ec2-user/blockchain-client/network-config.json << EOF
{
    \"networkId\": \"$NETWORK_ID\",
    \"memberId\": \"$MEMBER_ID\",
    \"nodeId\": \"$NODE_ID\",
    \"region\": \"$REGION\",
    \"hyperledgerVersion\": \"$HYPERLEDGER_VERSION\"
}
EOF
"

# Create sample chaincode (Go)
echo "Creating sample chaincode..."
runuser -l ec2-user -c '
cat > /home/ec2-user/blockchain-client/chaincode/asset-chaincode.go << "EOF"
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
    Value       int    `json:"value"`
}

func (s *SmartContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
    assets := []Asset{
        {ID: "asset1", Description: "Sample Asset 1", Owner: "Organization A", Timestamp: "2024-01-01", Value: 100},
        {ID: "asset2", Description: "Sample Asset 2", Owner: "Organization A", Timestamp: "2024-01-01", Value: 200},
    }

    for _, asset := range assets {
        assetJSON, err := json.Marshal(asset)
        if err != nil {
            return err
        }

        err = ctx.GetStub().PutState(asset.ID, assetJSON)
        if err != nil {
            return fmt.Errorf("failed to put to world state: %v", err)
        }
    }

    return nil
}

func (s *SmartContract) CreateAsset(ctx contractapi.TransactionContextInterface, id string, description string, owner string, timestamp string, value int) error {
    exists, err := s.AssetExists(ctx, id)
    if err != nil {
        return err
    }
    if exists {
        return fmt.Errorf("the asset %s already exists", id)
    }

    asset := Asset{
        ID:          id,
        Description: description,
        Owner:       owner,
        Timestamp:   timestamp,
        Value:       value,
    }
    
    assetJSON, err := json.Marshal(asset)
    if err != nil {
        return err
    }

    return ctx.GetStub().PutState(id, assetJSON)
}

func (s *SmartContract) ReadAsset(ctx contractapi.TransactionContextInterface, id string) (*Asset, error) {
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

func (s *SmartContract) UpdateAsset(ctx contractapi.TransactionContextInterface, id string, description string, owner string, timestamp string, value int) error {
    exists, err := s.AssetExists(ctx, id)
    if err != nil {
        return err
    }
    if !exists {
        return fmt.Errorf("the asset %s does not exist", id)
    }

    asset := Asset{
        ID:          id,
        Description: description,
        Owner:       owner,
        Timestamp:   timestamp,
        Value:       value,
    }
    
    assetJSON, err := json.Marshal(asset)
    if err != nil {
        return err
    }

    return ctx.GetStub().PutState(id, assetJSON)
}

func (s *SmartContract) DeleteAsset(ctx contractapi.TransactionContextInterface, id string) error {
    exists, err := s.AssetExists(ctx, id)
    if err != nil {
        return err
    }
    if !exists {
        return fmt.Errorf("the asset %s does not exist", id)
    }

    return ctx.GetStub().DelState(id)
}

func (s *SmartContract) AssetExists(ctx contractapi.TransactionContextInterface, id string) (bool, error) {
    assetJSON, err := ctx.GetStub().GetState(id)
    if err != nil {
        return false, fmt.Errorf("failed to read from world state: %v", err)
    }

    return assetJSON != nil, nil
}

func (s *SmartContract) TransferAsset(ctx contractapi.TransactionContextInterface, id string, newOwner string) error {
    asset, err := s.ReadAsset(ctx, id)
    if err != nil {
        return err
    }

    asset.Owner = newOwner
    assetJSON, err := json.Marshal(asset)
    if err != nil {
        return err
    }

    return ctx.GetStub().PutState(id, assetJSON)
}

func (s *SmartContract) GetAllAssets(ctx contractapi.TransactionContextInterface) ([]*Asset, error) {
    resultsIterator, err := ctx.GetStub().GetStateByRange("", "")
    if err != nil {
        return nil, err
    }
    defer resultsIterator.Close()

    var assets []*Asset
    for resultsIterator.HasNext() {
        queryResponse, err := resultsIterator.Next()
        if err != nil {
            return nil, err
        }

        var asset Asset
        err = json.Unmarshal(queryResponse.Value, &asset)
        if err != nil {
            return nil, err
        }
        assets = append(assets, &asset)
    }

    return assets, nil
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
'

# Create chaincode package.json for Node.js version
runuser -l ec2-user -c '
cat > /home/ec2-user/blockchain-client/chaincode/package.json << EOF
{
    "name": "asset-chaincode",
    "version": "1.0.0",
    "description": "Asset management chaincode for supply chain",
    "main": "index.js",
    "scripts": {
        "start": "fabric-chaincode-node start"
    },
    "dependencies": {
        "fabric-contract-api": "^2.2.0",
        "fabric-shim": "^2.2.0"
    }
}
EOF
'

# Create helper scripts
echo "Creating helper scripts..."
runuser -l ec2-user -c '
cat > /home/ec2-user/blockchain-client/scripts/setup-peer-connection.sh << "EOF"
#!/bin/bash

# This script helps set up peer connection for Hyperledger Fabric operations
# It retrieves necessary endpoints and certificates from AWS Managed Blockchain

NETWORK_CONFIG="/home/ec2-user/blockchain-client/network-config.json"

if [ ! -f "$NETWORK_CONFIG" ]; then
    echo "Error: Network configuration file not found at $NETWORK_CONFIG"
    exit 1
fi

NETWORK_ID=$(jq -r .networkId "$NETWORK_CONFIG")
MEMBER_ID=$(jq -r .memberId "$NETWORK_CONFIG")
NODE_ID=$(jq -r .nodeId "$NETWORK_CONFIG")
REGION=$(jq -r .region "$NETWORK_CONFIG")

echo "Retrieving blockchain network information..."
echo "Network ID: $NETWORK_ID"
echo "Member ID: $MEMBER_ID"
echo "Node ID: $NODE_ID"
echo "Region: $REGION"

# Get member information
echo "Getting member information..."
aws managedblockchain get-member \
    --network-id "$NETWORK_ID" \
    --member-id "$MEMBER_ID" \
    --region "$REGION" \
    --output json > /tmp/member-info.json

CA_ENDPOINT=$(jq -r .Member.FrameworkAttributes.Fabric.CaEndpoint /tmp/member-info.json)
echo "CA Endpoint: $CA_ENDPOINT"

# Get node information
echo "Getting node information..."
aws managedblockchain get-node \
    --network-id "$NETWORK_ID" \
    --member-id "$MEMBER_ID" \
    --node-id "$NODE_ID" \
    --region "$REGION" \
    --output json > /tmp/node-info.json

PEER_ENDPOINT=$(jq -r .Node.FrameworkAttributes.Fabric.PeerEndpoint /tmp/node-info.json)
echo "Peer Endpoint: $PEER_ENDPOINT"

# Save endpoints to environment file
cat > /home/ec2-user/blockchain-client/network-endpoints.env << EOL
export NETWORK_ID="$NETWORK_ID"
export MEMBER_ID="$MEMBER_ID"
export NODE_ID="$NODE_ID"
export CA_ENDPOINT="$CA_ENDPOINT"
export PEER_ENDPOINT="$PEER_ENDPOINT"
export REGION="$REGION"
EOL

echo "Network endpoints saved to network-endpoints.env"
echo "Source this file with: source /home/ec2-user/blockchain-client/network-endpoints.env"

# Clean up temporary files
rm -f /tmp/member-info.json /tmp/node-info.json
EOF

chmod +x /home/ec2-user/blockchain-client/scripts/setup-peer-connection.sh
'

# Create status check script
runuser -l ec2-user -c '
cat > /home/ec2-user/blockchain-client/scripts/check-blockchain-status.sh << "EOF"
#!/bin/bash

NETWORK_CONFIG="/home/ec2-user/blockchain-client/network-config.json"

if [ ! -f "$NETWORK_CONFIG" ]; then
    echo "Error: Network configuration file not found"
    exit 1
fi

NETWORK_ID=$(jq -r .networkId "$NETWORK_CONFIG")
MEMBER_ID=$(jq -r .memberId "$NETWORK_CONFIG")
NODE_ID=$(jq -r .nodeId "$NETWORK_CONFIG")
REGION=$(jq -r .region "$NETWORK_CONFIG")

echo "Checking blockchain network status..."
echo "=================================="

# Check network status
echo "Network Status:"
aws managedblockchain get-network \
    --network-id "$NETWORK_ID" \
    --region "$REGION" \
    --query "Network.{Status:Status,Framework:Framework}" \
    --output table

# Check member status
echo -e "\nMember Status:"
aws managedblockchain get-member \
    --network-id "$NETWORK_ID" \
    --member-id "$MEMBER_ID" \
    --region "$REGION" \
    --query "Member.{Status:Status,Name:Name}" \
    --output table

# Check node status
echo -e "\nNode Status:"
aws managedblockchain get-node \
    --network-id "$NETWORK_ID" \
    --member-id "$MEMBER_ID" \
    --node-id "$NODE_ID" \
    --region "$REGION" \
    --query "Node.{Status:Status,InstanceType:InstanceType}" \
    --output table

echo -e "\nBlockchain infrastructure is ready when all components show 'AVAILABLE' status."
EOF

chmod +x /home/ec2-user/blockchain-client/scripts/check-blockchain-status.sh
'

# Create README for the client
runuser -l ec2-user -c '
cat > /home/ec2-user/blockchain-client/README.md << "EOF"
# Blockchain Client Setup

This EC2 instance has been configured as a Hyperledger Fabric client for AWS Managed Blockchain.

## Available Tools

- **Hyperledger Fabric CLI tools**: `peer`, `configtxgen`, `cryptogen`
- **Docker and Docker Compose**: For chaincode development and testing
- **Node.js and npm**: For JavaScript chaincode development
- **AWS CLI v2**: For managing blockchain resources
- **Go compiler**: For Go chaincode development

## Getting Started

1. **Check blockchain status**:
   ```bash
   cd ~/blockchain-client
   ./scripts/check-blockchain-status.sh
   ```

2. **Set up peer connection**:
   ```bash
   ./scripts/setup-peer-connection.sh
   source network-endpoints.env
   ```

3. **Explore the sample chaincode**:
   ```bash
   cd chaincode
   cat asset-chaincode.go
   ```

## Network Configuration

The network configuration is stored in `network-config.json` and contains:
- Network ID
- Member ID  
- Node ID
- AWS Region
- Hyperledger Fabric version

## Directory Structure

```
blockchain-client/
├── crypto-config/          # Certificate and key storage
├── channel-artifacts/       # Channel configuration files
├── chaincode/              # Smart contract source code
├── scripts/                # Helper scripts
├── network-config.json     # Network configuration
└── README.md              # This file
```

## Next Steps

1. Configure certificates for peer operations
2. Create channels for private transactions
3. Deploy and test chaincode
4. Develop blockchain applications

For more information, refer to the Hyperledger Fabric documentation and AWS Managed Blockchain user guide.
EOF
'

# Set proper ownership for all created files
echo "Setting file ownership..."
chown -R ec2-user:ec2-user /home/ec2-user/blockchain-client
chown -R ec2-user:ec2-user /home/ec2-user/fabric-samples 2>/dev/null || true

# Create completion marker
echo "Creating completion marker..."
runuser -l ec2-user -c 'touch /home/ec2-user/blockchain-client/.setup-complete'

# Final status
echo "====================================="
echo "Blockchain client setup completed!"
echo "====================================="
echo "Available tools:"
echo "- Hyperledger Fabric CLI tools"
echo "- Docker and Docker Compose"
echo "- Node.js and npm"
echo "- AWS CLI v2"
echo "- Sample chaincode and scripts"
echo ""
echo "To get started:"
echo "1. SSH to this instance as ec2-user"
echo "2. cd ~/blockchain-client"
echo "3. Run ./scripts/check-blockchain-status.sh"
echo "4. Run ./scripts/setup-peer-connection.sh"
echo ""
echo "Setup log available at: /var/log/user-data.log"
echo "====================================="