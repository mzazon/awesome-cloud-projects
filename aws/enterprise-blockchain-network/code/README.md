# Infrastructure as Code for Enterprise Blockchain Network

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise Blockchain Network".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured (or AWS CloudShell)
- Appropriate AWS permissions for:
  - Amazon Managed Blockchain (full access)
  - VPC and EC2 management
  - IAM role creation
  - CloudWatch Logs access
- Node.js 16+ and npm for CDK implementations
- Python 3.8+ for CDK Python implementation
- Terraform 1.0+ for Terraform implementation
- Basic understanding of blockchain concepts and Hyperledger Fabric
- Estimated cost: $50-100 for 4-hour session (includes compute and blockchain network costs)

> **Note**: Amazon Managed Blockchain charges based on peer nodes, storage, and data transfer. Review [pricing details](https://aws.amazon.com/managed-blockchain/pricing/) before proceeding.

## Architecture Overview

This implementation creates:
- Amazon Managed Blockchain network with Hyperledger Fabric 2.2
- Member organization with administrative credentials
- Peer nodes for transaction processing and ledger maintenance
- VPC with private subnets for secure blockchain access
- VPC endpoints for private connectivity
- EC2 client instance with Hyperledger Fabric SDK
- Security groups with appropriate access controls
- CloudWatch logging for network monitoring

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name hyperledger-fabric-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=KeyPairName,ParameterValue=your-key-pair \
                 ParameterKey=NetworkName,ParameterValue=fabric-network \
                 ParameterKey=MemberName,ParameterValue=member-org \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name hyperledger-fabric-stack \
    --query 'Stacks[0].StackStatus'

# Get network information
aws cloudformation describe-stacks \
    --stack-name hyperledger-fabric-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Review the deployment plan
cdk diff

# Deploy the infrastructure
cdk deploy HyperledgerFabricStack

# Get deployment outputs
cdk ls --long
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Review the deployment plan
cdk diff

# Deploy the infrastructure
cdk deploy HyperledgerFabricStack

# Get deployment outputs
cdk ls --long
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="key_pair_name=your-key-pair"

# Apply the configuration
terraform apply -var="key_pair_name=your-key-pair"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for required parameters:
# - AWS region
# - EC2 key pair name
# - Network name (optional)
# - Member organization name (optional)
```

## Post-Deployment Steps

After infrastructure deployment, you'll need to:

1. **Connect to the client instance**:
   ```bash
   # Get instance IP from outputs
   INSTANCE_IP=$(aws cloudformation describe-stacks \
       --stack-name hyperledger-fabric-stack \
       --query 'Stacks[0].Outputs[?OutputKey==`ClientInstanceIP`].OutputValue' \
       --output text)
   
   # SSH to the instance
   ssh -i your-key-pair.pem ec2-user@${INSTANCE_IP}
   ```

2. **Set up Fabric SDK environment**:
   ```bash
   # On the client instance
   cd ~/fabric-client-app
   npm install
   
   # Download network certificates
   aws managedblockchain get-network \
       --network-id ${NETWORK_ID} \
       --region ${AWS_REGION}
   ```

3. **Deploy and test smart contracts**:
   ```bash
   # Install chaincode dependencies
   cd ~/fabric-client-app/chaincode
   npm init -y
   npm install fabric-contract-api
   
   # Package and deploy chaincode (follow Hyperledger Fabric documentation)
   ```

## Configuration Options

### CloudFormation Parameters
- `NetworkName`: Name for the blockchain network
- `MemberName`: Name for the member organization
- `KeyPairName`: EC2 key pair for client instance access
- `InstanceType`: EC2 instance type for client (default: t3.medium)
- `BlockchainEdition`: Managed Blockchain edition (STARTER or STANDARD)

### CDK Configuration
Modify the configuration in the stack constructor:
```typescript
// CDK TypeScript example
const networkConfig = {
  networkName: 'fabric-network',
  memberName: 'member-org',
  instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
  blockchainEdition: 'STARTER'
};
```

### Terraform Variables
```bash
# terraform.tfvars example
network_name = "fabric-network"
member_name = "member-org"
key_pair_name = "your-key-pair"
instance_type = "t3.medium"
blockchain_edition = "STARTER"
availability_zone = "us-east-1a"
```

## Validation and Testing

After deployment, validate the infrastructure:

1. **Check network status**:
   ```bash
   aws managedblockchain list-networks \
       --query 'Networks[?Name==`fabric-network`]'
   ```

2. **Verify peer node availability**:
   ```bash
   aws managedblockchain list-nodes \
       --network-id ${NETWORK_ID} \
       --member-id ${MEMBER_ID}
   ```

3. **Test VPC endpoint connectivity**:
   ```bash
   aws ec2 describe-vpc-endpoints \
       --filters Name=service-name,Values=com.amazonaws.${AWS_REGION}.managedblockchain.${NETWORK_ID}
   ```

4. **Validate client environment**:
   ```bash
   # On client instance
   node --version
   npm list fabric-network
   ```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack (this will remove all resources)
aws cloudformation delete-stack \
    --stack-name hyperledger-fabric-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name hyperledger-fabric-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy HyperledgerFabricStack

# Confirm when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy all resources
terraform destroy -var="key_pair_name=your-key-pair"

# Confirm when prompted
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

## Security Considerations

This implementation includes several security best practices:

- **Private Network**: All blockchain communication occurs within VPC using private endpoints
- **Security Groups**: Restrictive security groups limiting access to necessary ports only
- **IAM Roles**: Least privilege IAM roles for EC2 instances and blockchain access
- **Encryption**: Data encryption in transit and at rest using AWS managed keys
- **Certificate Management**: Automated certificate authority setup through Managed Blockchain

## Troubleshooting

### Common Issues

1. **Network Creation Failed**:
   - Check AWS service limits for Managed Blockchain
   - Verify account has appropriate permissions
   - Ensure region supports Managed Blockchain

2. **Peer Node Creation Failed**:
   - Verify network is in AVAILABLE status
   - Check member organization status
   - Ensure sufficient EC2 limits in region

3. **VPC Endpoint Issues**:
   - Verify VPC and subnet configuration
   - Check security group rules
   - Ensure DNS resolution is enabled in VPC

4. **Client Connection Issues**:
   - Verify EC2 instance security group allows SSH
   - Check key pair configuration
   - Ensure instance is in public subnet with internet gateway

### Monitoring and Logging

- **CloudWatch Logs**: Blockchain network logs are automatically sent to CloudWatch
- **VPC Flow Logs**: Enable for network traffic analysis
- **CloudTrail**: Monitor API calls to Managed Blockchain service
- **Instance Monitoring**: CloudWatch metrics for EC2 client instance

## Cost Optimization

- **Instance Sizing**: Use smaller instance types for development/testing
- **Network Edition**: Use STARTER edition for proof-of-concept deployments
- **Cleanup**: Always clean up resources when not in use
- **Monitoring**: Set up billing alerts for cost control

## Support and Documentation

- [Amazon Managed Blockchain Documentation](https://docs.aws.amazon.com/managed-blockchain/)
- [Hyperledger Fabric Documentation](https://hyperledger-fabric.readthedocs.io/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or the provider's documentation.

## Next Steps

After successful deployment:

1. **Develop Smart Contracts**: Create business logic specific to your use case
2. **Build Client Applications**: Develop web or mobile applications that interact with the blockchain
3. **Multi-Organization Setup**: Add additional member organizations for consortium blockchain
4. **Production Hardening**: Implement monitoring, backup, and disaster recovery strategies
5. **Integration**: Connect with existing enterprise systems and databases