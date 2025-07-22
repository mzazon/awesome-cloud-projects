# Infrastructure as Code for Blockchain-Based Voting Systems

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Blockchain-Based Voting Systems".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a secure, transparent voting system using Amazon Managed Blockchain with Ethereum smart contracts. The infrastructure includes:

- **Amazon Managed Blockchain**: Ethereum network for immutable vote recording
- **AWS Lambda**: Serverless functions for voter authentication and vote monitoring
- **Amazon DynamoDB**: Voter registry and election management
- **Amazon S3**: Encrypted ballot storage and DApp hosting
- **Amazon EventBridge**: Real-time event processing
- **Amazon SNS**: Notification system for election officials
- **AWS KMS**: Encryption key management
- **Amazon CloudWatch**: Monitoring and alerting

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Managed Blockchain (Ethereum node creation)
  - Lambda (function creation and execution)
  - DynamoDB (table creation and data access)
  - S3 (bucket creation and object management)
  - EventBridge (rule creation and event routing)
  - SNS (topic creation and messaging)
  - KMS (key creation and encryption)
  - CloudWatch (monitoring and alerting)
  - IAM (role and policy management)
- Understanding of Ethereum blockchain concepts
- Basic knowledge of smart contract development
- Estimated cost: $150-250 for blockchain node, Lambda executions, and storage

## Quick Start

### Using CloudFormation
```bash
# Deploy the complete voting system
aws cloudformation create-stack \
    --stack-name blockchain-voting-system \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=VotingSystemName,ParameterValue=my-voting-system

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name blockchain-voting-system \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/
npm install

# Deploy the voting system
cdk deploy BlockchainVotingSystemStack

# View outputs
cdk output BlockchainVotingSystemStack
```

### Using CDK Python
```bash
cd cdk-python/
pip install -r requirements.txt

# Deploy the voting system
cdk deploy BlockchainVotingSystemStack

# View outputs
cdk output BlockchainVotingSystemStack
```

### Using Terraform
```bash
cd terraform/
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh

# The script will:
# 1. Create all necessary AWS resources
# 2. Deploy Lambda functions
# 3. Configure EventBridge rules
# 4. Set up monitoring and alerts
# 5. Deploy the voting DApp
```

## Post-Deployment Configuration

### 1. Smart Contract Deployment
After infrastructure deployment, you'll need to deploy the voting smart contracts:

```bash
# The smart contracts are included in the deployment
# They will be automatically uploaded to your S3 bucket
# Manual deployment to blockchain requires:
# - Ethereum node endpoint configuration
# - Gas fee estimation
# - Contract compilation and deployment
```

### 2. Voter Registration Setup
Configure the voter authentication system:

```bash
# Test voter registration
aws lambda invoke \
    --function-name VoterAuthentication-<random-suffix> \
    --payload '{"action":"registerVoter","voterId":"test-voter","electionId":"1","publicKey":"0x123...","identityDocument":{"type":"test"}}' \
    response.json

# Check registration in DynamoDB
aws dynamodb scan --table-name VoterRegistry --limit 5
```

### 3. Election Management
Create and manage elections:

```bash
# Elections are managed through smart contracts
# Use the DApp interface at:
# https://<bucket-name>.s3.<region>.amazonaws.com/dapp/index.html
```

## Testing and Validation

### Run System Tests
```bash
# Set environment variables
export AWS_REGION=$(aws configure get region)
export LAMBDA_AUTH_FUNCTION=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `VoterAuthentication`)].FunctionName' --output text)
export LAMBDA_MONITOR_FUNCTION=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `VoteMonitoring`)].FunctionName' --output text)

# Install Node.js dependencies for testing
npm install aws-sdk

# Run comprehensive tests
node test-voting-system.js
```

### Verify Infrastructure
```bash
# Check blockchain node status
aws managedblockchain list-nodes --query 'Nodes[0].Status'

# Verify Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `Voting`)].FunctionName'

# Check DynamoDB tables
aws dynamodb list-tables --query 'TableNames[?contains(@, `Voter`) || contains(@, `Election`)]'

# Verify S3 bucket and objects
aws s3 ls s3://voting-system-data-<random-suffix>/
```

## Monitoring and Alerts

### CloudWatch Dashboard
Access the monitoring dashboard:
```bash
# View dashboard
aws cloudwatch list-dashboards --query 'DashboardEntries[?contains(DashboardName, `Voting`)].DashboardName'

# The dashboard includes:
# - Voter authentication metrics
# - Vote monitoring statistics
# - Event processing rates
# - Database activity
```

### SNS Notifications
Configure notifications for election officials:
```bash
# Subscribe to voting notifications
aws sns subscribe \
    --topic-arn <voting-topic-arn> \
    --protocol email \
    --notification-endpoint your-email@example.com
```

## Security Considerations

### Access Control
- All Lambda functions use least-privilege IAM roles
- DynamoDB tables have encryption at rest enabled
- S3 buckets use server-side encryption
- KMS keys provide centralized key management

### Voter Privacy
- Voter IDs are cryptographically hashed
- Personal information is encrypted using KMS
- Votes are anonymized on the blockchain
- Audit trails maintain privacy while enabling verification

### Blockchain Security
- Ethereum smart contracts enforce voting rules
- Transaction immutability prevents vote tampering
- Cryptographic signatures verify vote authenticity
- Public blockchain enables independent verification

## Customization

### Environment Variables
Key variables that can be customized:

```bash
# Blockchain configuration
BLOCKCHAIN_NETWORK="GOERLI"  # or "MAINNET" for production
NODE_INSTANCE_TYPE="bc.t3.medium"  # or larger for production

# Lambda configuration
LAMBDA_MEMORY_SIZE="512"  # MB
LAMBDA_TIMEOUT="60"  # seconds

# DynamoDB configuration
READ_CAPACITY_UNITS="5"
WRITE_CAPACITY_UNITS="5"

# Election parameters
ELECTION_DURATION="86400"  # 24 hours in seconds
CANDIDATE_REGISTRATION_DEADLINE="3600"  # 1 hour before election
```

### Smart Contract Customization
Modify the voting smart contract for specific requirements:

```solidity
// Example customizations:
// - Multi-round elections
// - Ranked choice voting
// - Weighted voting systems
// - Delegate voting mechanisms
```

## Troubleshooting

### Common Issues

1. **Blockchain Node Not Available**
   ```bash
   # Check node status
   aws managedblockchain get-node --node-id <node-id>
   
   # Nodes can take 10-15 minutes to become available
   ```

2. **Lambda Function Errors**
   ```bash
   # Check function logs
   aws logs tail /aws/lambda/VoterAuthentication-<suffix> --follow
   ```

3. **DynamoDB Access Issues**
   ```bash
   # Verify table status
   aws dynamodb describe-table --table-name VoterRegistry
   ```

4. **S3 Permission Errors**
   ```bash
   # Check bucket policy
   aws s3api get-bucket-policy --bucket <bucket-name>
   ```

### Debug Mode
Enable debug logging for troubleshooting:
```bash
# Set debug environment variables
export DEBUG_VOTING_SYSTEM=true
export LOG_LEVEL=DEBUG

# Redeploy with debug settings
```

## Cleanup

### Using CloudFormation
```bash
aws cloudformation delete-stack --stack-name blockchain-voting-system

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name blockchain-voting-system \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
cdk destroy BlockchainVotingSystemStack
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh

# The script will:
# 1. Delete all AWS resources in proper order
# 2. Handle dependencies correctly
# 3. Provide progress feedback
# 4. Confirm successful cleanup
```

### Manual Cleanup Verification
```bash
# Verify all resources are deleted
aws managedblockchain list-nodes
aws lambda list-functions --query 'Functions[?contains(FunctionName, `Voting`)]'
aws dynamodb list-tables --query 'TableNames[?contains(@, `Voter`) || contains(@, `Election`)]'
aws s3 ls | grep voting-system
```

## Cost Optimization

### Production Considerations
- Use appropriate instance types for blockchain nodes
- Configure DynamoDB with on-demand billing for variable workloads
- Implement S3 lifecycle policies for old election data
- Use Lambda provisioned concurrency for high-volume elections
- Consider Reserved Instances for predictable workloads

### Cost Monitoring
```bash
# View cost breakdown
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE
```

## Compliance and Auditing

### Audit Trail
- All voting events are logged in CloudWatch
- Blockchain provides immutable transaction history
- S3 stores encrypted audit records
- EventBridge tracks all system events

### Compliance Features
- Data encryption at rest and in transit
- Voter privacy protection mechanisms
- Audit trail preservation
- Independent result verification capabilities

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review AWS service documentation
3. Refer to the original recipe documentation
4. Contact AWS support for service-specific issues

## Additional Resources

- [Amazon Managed Blockchain Documentation](https://docs.aws.amazon.com/managed-blockchain/)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [DynamoDB Security Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/security.html)
- [Ethereum Smart Contract Development](https://docs.aws.amazon.com/managed-blockchain/latest/ethereum-dev/)
- [AWS KMS Best Practices](https://docs.aws.amazon.com/kms/latest/developerguide/best-practices.html)