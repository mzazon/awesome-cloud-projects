# Infrastructure as Code for Establishing Private Blockchain Networks with Amazon Managed Blockchain

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Establishing Private Blockchain Networks with Amazon Managed Blockchain".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a complete private blockchain network using Amazon Managed Blockchain with:

- Hyperledger Fabric 2.2 blockchain network
- Private network member with administrative access
- Peer node for transaction processing and ledger maintenance
- VPC endpoint for secure blockchain access
- EC2 client instance with Hyperledger Fabric tools
- Security groups and IAM roles for secure operations
- CloudWatch logging and monitoring

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon Managed Blockchain (full access)
  - VPC and EC2 management
  - IAM role and policy creation
  - CloudWatch logs
- Basic understanding of blockchain concepts and Hyperledger Fabric
- For CDK deployments: Node.js 16+ or Python 3.8+
- For Terraform deployments: Terraform v1.0+
- Estimated cost: $50-100/day for network, members, and nodes during testing

> **Warning**: Amazon Managed Blockchain charges for network membership, peer nodes, and data storage. Review the [AWS Managed Blockchain pricing](https://aws.amazon.com/managed-blockchain/pricing/) documentation before creating production resources.

## Quick Start

### Using CloudFormation

```bash
# Set required parameters
export NETWORK_NAME="SupplyChainNetwork-$(date +%s)"
export MEMBER_NAME="OrganizationA-$(date +%s)"
export ADMIN_PASSWORD="TempPassword123!"

# Deploy the stack
aws cloudformation create-stack \
    --stack-name blockchain-network-stack \
    --template-body file://cloudformation.yaml \
    --parameters \
        ParameterKey=NetworkName,ParameterValue=${NETWORK_NAME} \
        ParameterKey=MemberName,ParameterValue=${MEMBER_NAME} \
        ParameterKey=AdminPassword,ParameterValue=${ADMIN_PASSWORD} \
    --capabilities CAPABILITY_IAM

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name blockchain-network-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name blockchain-network-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Set environment variables
export CDK_DEFAULT_REGION=$(aws configure get region)
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy BlockchainNetworkStack

# View outputs
cdk ls
```

### Using CDK Python

```bash
cd cdk-python/

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export CDK_DEFAULT_REGION=$(aws configure get region)
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy BlockchainNetworkStack

# View outputs
cdk ls
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Create terraform.tfvars file (optional)
cat > terraform.tfvars << EOF
network_name = "SupplyChainNetwork-$(date +%s)"
member_name = "OrganizationA-$(date +%s)"
admin_password = "TempPassword123!"
region = "$(aws configure get region)"
EOF

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export NETWORK_NAME="SupplyChainNetwork-$(date +%s)"
export MEMBER_NAME="OrganizationA-$(date +%s)"
export ADMIN_PASSWORD="TempPassword123!"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment information
cat network-info.json
```

## Post-Deployment Configuration

After successful deployment, complete these steps to fully configure your blockchain network:

### 1. Connect to EC2 Client Instance

```bash
# Get the EC2 instance public IP from outputs
EC2_PUBLIC_IP=$(aws cloudformation describe-stacks \
    --stack-name blockchain-network-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`EC2PublicIP`].OutputValue' \
    --output text)

# Connect to the instance
ssh -i blockchain-client-key.pem ec2-user@${EC2_PUBLIC_IP}
```

### 2. Set Up Hyperledger Fabric Client

```bash
# On the EC2 instance
cd /home/ec2-user

# Download Hyperledger Fabric binaries
curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.2.0 1.4.9

# Add to PATH
echo 'export PATH=/home/ec2-user/fabric-samples/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# Create directory structure
mkdir -p blockchain-client/{crypto-config,channel-artifacts}
```

### 3. Create Blockchain Channel

```bash
# Create channel configuration
export CHANNEL_NAME="supplychainchannel"

# Use peer CLI to create channel (requires proper certificate setup)
peer channel create \
    -o ${ORDERER_ENDPOINT} \
    -c ${CHANNEL_NAME} \
    -f channel-artifacts/channel.tx
```

### 4. Deploy Sample Chaincode

```bash
# Package the chaincode
peer lifecycle chaincode package sample.tar.gz \
    --path chaincode/sample/ \
    --lang golang \
    --label sample_1.0

# Install chaincode
peer lifecycle chaincode install sample.tar.gz

# Approve chaincode definition
peer lifecycle chaincode approveformyorg \
    -o ${ORDERER_ENDPOINT} \
    -channelID ${CHANNEL_NAME} \
    -name sample \
    -version 1.0 \
    -package-id ${PACKAGE_ID}
```

## Validation & Testing

### Verify Network Status

```bash
# Check network status
aws managedblockchain get-network \
    --network-id ${NETWORK_ID} \
    --query 'Network.{Status:Status,Framework:Framework,MemberCount:MemberCount}'
```

### Test VPC Endpoint Connectivity

```bash
# Test VPC endpoint
aws ec2 describe-vpc-endpoints \
    --vpc-endpoint-ids ${VPC_ENDPOINT_ID} \
    --query 'VpcEndpoints[0].State'
```

### Validate Security Configuration

```bash
# Check security group rules
aws ec2 describe-security-groups \
    --group-ids ${SECURITY_GROUP_ID} \
    --query 'SecurityGroups[0].IpPermissions[*].{Protocol:IpProtocol,FromPort:FromPort,ToPort:ToPort}'
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name blockchain-network-stack

# Wait for deletion
aws cloudformation wait stack-delete-complete \
    --stack-name blockchain-network-stack

# Clean up key pair and local files
aws ec2 delete-key-pair --key-name blockchain-client-key
rm -f blockchain-client-key.pem network-info.json
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy BlockchainNetworkStack

# Clean up local files
rm -f blockchain-client-key.pem network-info.json
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Clean up local files
rm -f terraform.tfstate* blockchain-client-key.pem network-info.json
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Clean up remaining files
rm -f blockchain-client-key.pem network-info.json
```

## Customization

### Network Configuration

Customize the blockchain network by modifying these parameters:

- **Network Name**: Unique identifier for your blockchain network
- **Member Name**: Name for your organization in the network
- **Framework Version**: Hyperledger Fabric version (2.2 recommended)
- **Instance Type**: Peer node compute capacity (bc.t3.small to bc.m5.4xlarge)
- **Edition**: STARTER or STANDARD (STANDARD recommended for production)

### Security Configuration

- **VPC Configuration**: Deploy in existing VPC or create new VPC
- **Security Groups**: Customize allowed ports and IP ranges
- **IAM Roles**: Adjust permissions based on least privilege principle
- **Encryption**: Configure encryption at rest and in transit

### Monitoring and Logging

- **CloudWatch Integration**: Enable detailed monitoring and logging
- **VPC Flow Logs**: Monitor network traffic for security analysis
- **Custom Metrics**: Add application-specific monitoring

## Troubleshooting

### Common Issues

1. **Network Creation Timeout**
   - Network creation can take 10-30 minutes
   - Check AWS service limits for Managed Blockchain
   - Verify IAM permissions are sufficient

2. **VPC Endpoint Connection Issues**
   - Ensure security groups allow required ports (30001, 30002, 7051, 7053)
   - Verify VPC endpoint is in same region as blockchain network
   - Check DNS resolution for VPC endpoint

3. **Peer Node Failed to Start**
   - Verify instance type is supported in target region
   - Check availability zone has sufficient capacity
   - Review CloudWatch logs for detailed error messages

4. **Certificate Authority Issues**
   - Ensure CA endpoint is accessible from client
   - Verify admin credentials are correct
   - Check certificate chain configuration

### Monitoring and Debugging

```bash
# View CloudWatch logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/managedblockchain"

# Check VPC Flow Logs
aws logs filter-log-events \
    --log-group-name "VPCFlowLogs" \
    --start-time $(date -d "1 hour ago" +%s)000

# Monitor network metrics
aws cloudwatch get-metric-statistics \
    --namespace "AWS/ManagedBlockchain" \
    --metric-name "TransactionCount" \
    --start-time $(date -d "1 hour ago" --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 3600 \
    --statistics Sum
```

## Security Best Practices

1. **Network Security**
   - Use VPC endpoints for private connectivity
   - Implement least privilege security groups
   - Enable VPC Flow Logs for network monitoring

2. **Identity and Access Management**
   - Use IAM roles with minimal required permissions
   - Implement certificate rotation policies
   - Enable CloudTrail for API auditing

3. **Data Protection**
   - Enable encryption at rest for blockchain data
   - Use TLS for all network communications
   - Implement proper key management practices

4. **Monitoring and Compliance**
   - Enable comprehensive logging
   - Set up alerting for security events
   - Regular security assessments and audits

## Multi-Member Network Setup

To add additional members to the network:

1. **Create Member Invitation**
   ```bash
   aws managedblockchain create-proposal \
       --network-id ${NETWORK_ID} \
       --member-id ${MEMBER_ID} \
       --actions InviteAccount={AccountId=123456789012}
   ```

2. **Invite Account Process**
   - Target account receives invitation
   - Target account creates member in network
   - Existing members vote on proposal
   - New member creates peer nodes

3. **Channel Management**
   - Create private channels for specific member groups
   - Configure channel access controls
   - Deploy channel-specific chaincode

## Performance Optimization

1. **Instance Sizing**
   - Start with bc.t3.small for development
   - Scale to bc.m5.large or larger for production
   - Monitor CPU and memory utilization

2. **Network Configuration**
   - Use multiple peer nodes for high availability
   - Implement load balancing for client applications
   - Optimize chaincode for performance

3. **Monitoring and Tuning**
   - Monitor transaction throughput
   - Optimize block size and timeout settings
   - Implement caching strategies for frequently accessed data

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation
2. Check AWS Managed Blockchain documentation
3. Review Hyperledger Fabric documentation
4. Contact AWS Support for service-specific issues

## Additional Resources

- [AWS Managed Blockchain User Guide](https://docs.aws.amazon.com/managed-blockchain/)
- [Hyperledger Fabric Documentation](https://hyperledger-fabric.readthedocs.io/)
- [AWS VPC Endpoints Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-endpoints.html)
- [Blockchain Security Best Practices](https://docs.aws.amazon.com/managed-blockchain/latest/managementguide/security-best-practices.html)