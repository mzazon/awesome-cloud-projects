# Amazon Managed Blockchain CDK TypeScript Application

This CDK TypeScript application deploys a complete Amazon Managed Blockchain private network with Hyperledger Fabric framework, including network infrastructure, member configuration, peer nodes, and client environment.

## Architecture Overview

The application creates:

- **Managed Blockchain Network**: Private Hyperledger Fabric network with governance policies
- **Founding Member**: Initial organization member with admin credentials
- **Peer Node**: Computing infrastructure for transaction processing and ledger maintenance
- **VPC Infrastructure**: VPC endpoint for secure blockchain access
- **EC2 Client Instance**: Pre-configured environment with Hyperledger Fabric tools
- **Security Configuration**: Security groups, IAM roles, and access controls
- **Monitoring**: CloudWatch logging and VPC Flow Logs

## Prerequisites

- Node.js 18.x or later
- AWS CLI v2 configured with appropriate permissions
- AWS CDK v2 installed globally (`npm install -g aws-cdk`)
- Valid AWS account with Managed Blockchain service availability
- Estimated cost: $50-100/day for network, members, and nodes during testing

### Required AWS Permissions

Your AWS credentials must have permissions for:
- Amazon Managed Blockchain (create networks, members, nodes)
- EC2 (VPC endpoints, instances, security groups, key pairs)
- IAM (roles, policies)
- CloudWatch Logs
- VPC Flow Logs

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (if not done previously)

```bash
cdk bootstrap
```

### 3. Deploy the Stack

```bash
# Deploy with default configuration
cdk deploy

# Or deploy with custom configuration
cdk deploy \
  --context networkName="MySupplyChain" \
  --context memberName="MyOrganization" \
  --context environment="production"
```

### 4. Get Stack Outputs

After deployment, note the output values:

```bash
# View all stack outputs
aws cloudformation describe-stacks \
  --stack-name ManagedBlockchainStack \
  --query 'Stacks[0].Outputs'
```

Key outputs include:
- `NetworkId`: Blockchain network identifier
- `MemberId`: Member organization identifier  
- `NodeId`: Peer node identifier
- `ClientPublicIp`: EC2 client instance IP address
- `KeyPairName`: SSH key pair name for client access

## Configuration Options

You can customize the deployment using CDK context parameters:

```bash
cdk deploy \
  --context networkName="CustomNetworkName" \
  --context memberName="CustomMemberName" \
  --context adminUsername="admin" \
  --context adminPassword="SecurePassword123!" \
  --context nodeInstanceType="bc.t3.medium" \
  --context ec2InstanceType="t3.large" \
  --context environment="production"
```

### Available Context Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `networkName` | `SupplyChainNetwork` | Name of the blockchain network |
| `memberName` | `OrganizationA` | Name of the founding member |
| `adminUsername` | `admin` | Admin username for Fabric CA |
| `adminPassword` | `TempPassword123!` | Admin password for Fabric CA |
| `nodeInstanceType` | `bc.t3.small` | Instance type for peer node |
| `ec2InstanceType` | `t3.medium` | Instance type for client EC2 |
| `environment` | `development` | Environment tag for resources |

## Post-Deployment Steps

### 1. Connect to Client Instance

```bash
# Get the SSH key from AWS Systems Manager Parameter Store
aws ssm get-parameter \
  --name "/ec2/keypair/{KeyPairId}" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text > blockchain-client-key.pem

chmod 400 blockchain-client-key.pem

# Connect to the instance
ssh -i blockchain-client-key.pem ec2-user@{ClientPublicIp}
```

### 2. Verify Blockchain Network

```bash
# Check network status
aws managedblockchain get-network \
  --network-id {NetworkId} \
  --query 'Network.Status'

# Check member status
aws managedblockchain get-member \
  --network-id {NetworkId} \
  --member-id {MemberId} \
  --query 'Member.Status'

# Check node status
aws managedblockchain get-node \
  --network-id {NetworkId} \
  --member-id {MemberId} \
  --node-id {NodeId} \
  --query 'Node.Status'
```

### 3. Set Up Hyperledger Fabric Client

From the EC2 client instance:

```bash
# Source the environment
source ~/.bashrc

# Verify Fabric binaries are available
peer version

# Create channel configuration (customize as needed)
mkdir -p /home/ec2-user/blockchain-client/channels
cd /home/ec2-user/blockchain-client
```

## Development Commands

```bash
# Build the TypeScript code
npm run build

# Watch for changes and rebuild
npm run watch

# Run tests
npm test

# Synthesize CloudFormation template
cdk synth

# Compare deployed stack with current state
cdk diff

# View all stacks in the app
cdk list
```

## Testing

The application includes comprehensive unit tests using Jest:

```bash
# Run all tests
npm test

# Run tests with coverage
npm test -- --coverage

# Run tests in watch mode
npm test -- --watch
```

## Security Considerations

### Network Security
- VPC endpoints provide private connectivity to Managed Blockchain
- Security groups restrict access to required ports only
- EC2 instance uses IAM roles for service access

### Blockchain Security
- Hyperledger Fabric provides permissioned network access
- Certificate authorities manage cryptographic identities
- Admin credentials should be rotated regularly

### Production Recommendations
- Use AWS Secrets Manager for admin passwords
- Implement certificate rotation policies
- Enable detailed CloudTrail logging
- Use KMS for key management
- Implement backup strategies for network configuration

## Monitoring and Logging

The application configures:

- **CloudWatch Logs**: Blockchain network logs
- **VPC Flow Logs**: Network traffic monitoring  
- **EC2 Instance Monitoring**: System metrics
- **Custom Metrics**: Add application-specific metrics as needed

Access logs:

```bash
# View blockchain network logs
aws logs describe-log-streams \
  --log-group-name "/aws/managedblockchain/{NetworkName}"

# View VPC Flow Logs
aws logs describe-log-streams \
  --log-group-name "VPCFlowLogs"
```

## Cleanup

To remove all resources and avoid ongoing charges:

```bash
# Destroy the CDK stack
cdk destroy

# Confirm deletion when prompted
```

**Note**: Blockchain networks may take several minutes to delete completely.

## Troubleshooting

### Common Issues

1. **Network Creation Timeout**
   - Managed Blockchain networks can take 10-30 minutes to create
   - Check AWS Console for detailed status

2. **VPC Endpoint Connection Issues**
   - Verify security group rules allow required ports (30001, 30002)
   - Check VPC endpoint policy and route tables

3. **EC2 Instance Access Issues**
   - Ensure key pair is properly downloaded and permissions set (chmod 400)
   - Verify security group allows SSH access (port 22)

4. **Permission Errors**
   - Verify AWS credentials have required permissions
   - Check IAM roles and policies are correctly attached

### Debugging Commands

```bash
# Check CDK context and configuration
cdk context

# Validate CloudFormation template
cdk synth | cfn-lint

# Check AWS service limits
aws service-quotas get-service-quota \
  --service-code managedblockchain \
  --quota-code L-E9BF0BF8
```

## Additional Resources

- [Amazon Managed Blockchain Developer Guide](https://docs.aws.amazon.com/managed-blockchain/)
- [Hyperledger Fabric Documentation](https://hyperledger-fabric.readthedocs.io/)
- [AWS CDK TypeScript Reference](https://docs.aws.amazon.com/cdk/api/v2/typescript/)
- [Blockchain Network Best Practices](https://docs.aws.amazon.com/managed-blockchain/latest/managementguide/best-practices.html)

## Support

For issues with this CDK application:

1. Check the troubleshooting section above
2. Review AWS CloudFormation stack events in the console
3. Check CloudWatch logs for detailed error messages
4. Refer to the original recipe documentation

## License

This code is provided under the MIT License. See LICENSE file for details.