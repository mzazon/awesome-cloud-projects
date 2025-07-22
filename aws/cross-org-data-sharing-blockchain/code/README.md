# Infrastructure as Code for Cross-Organization Data Sharing with Blockchain

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Cross-Organization Data Sharing with Blockchain".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a secure cross-organization data sharing platform using:

- **Amazon Managed Blockchain**: Hyperledger Fabric network with multiple organizations
- **AWS Lambda**: Serverless data validation and event processing
- **Amazon EventBridge**: Cross-organization event routing and notifications
- **Amazon S3**: Shared data storage and chaincode repository
- **Amazon DynamoDB**: Immutable audit trail storage
- **Amazon CloudWatch**: Comprehensive monitoring and alerting
- **AWS IAM**: Fine-grained access control and compliance

## Prerequisites

### AWS Account Setup
- AWS CLI v2 installed and configured
- AWS account with appropriate permissions for:
  - Amazon Managed Blockchain (full access)
  - AWS Lambda (create functions, execution roles)
  - Amazon EventBridge (create rules, targets)
  - Amazon S3 (create buckets, objects)
  - Amazon DynamoDB (create tables, read/write)
  - Amazon CloudWatch (create dashboards, alarms)
  - AWS IAM (create roles, policies)
  - Amazon SNS (create topics, subscriptions)

### Development Environment
- Node.js 18.x or later (for CDK TypeScript)
- Python 3.9 or later (for CDK Python)
- Terraform 1.5.0 or later (for Terraform implementation)
- Understanding of Hyperledger Fabric concepts

### Cost Considerations
- Estimated cost: $200-300 for multi-org network setup and testing
- Major cost components:
  - Managed Blockchain network and peer nodes
  - Lambda function executions
  - DynamoDB read/write capacity
  - S3 storage and requests
  - CloudWatch monitoring and logs

> **Warning**: This recipe creates enterprise-grade blockchain infrastructure. Monitor costs carefully and clean up resources promptly after testing.

## Quick Start

### Using CloudFormation

```bash
# Create the stack with default parameters
aws cloudformation create-stack \
    --stack-name cross-org-blockchain-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameters \
        ParameterKey=NetworkName,ParameterValue=cross-org-network \
        ParameterKey=OrgAMemberName,ParameterValue=financial-institution \
        ParameterKey=OrgBMemberName,ParameterValue=healthcare-provider

# Monitor stack creation progress
aws cloudformation describe-stacks \
    --stack-name cross-org-blockchain-stack \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name cross-org-blockchain-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy

# View stack outputs
npx cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# Monitor deployment progress
# (Script will provide status updates and resource identifiers)
```

## Configuration Options

### CloudFormation Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `NetworkName` | Blockchain network name | `cross-org-network` | Yes |
| `OrgAMemberName` | Organization A member name | `financial-institution` | Yes |
| `OrgBMemberName` | Organization B member name | `healthcare-provider` | Yes |
| `BucketName` | S3 bucket for shared data | Auto-generated | No |
| `NodeInstanceType` | Blockchain node instance type | `bc.t3.medium` | No |

### CDK Configuration

Edit the configuration variables in `app.ts` (TypeScript) or `app.py` (Python):

```typescript
// CDK TypeScript configuration
const config = {
  networkName: 'cross-org-network',
  orgAMemberName: 'financial-institution',
  orgBMemberName: 'healthcare-provider',
  nodeInstanceType: 'bc.t3.medium'
};
```

### Terraform Variables

Create a `terraform.tfvars` file:

```hcl
# terraform.tfvars
network_name         = "cross-org-network"
org_a_member_name   = "financial-institution"
org_b_member_name   = "healthcare-provider"
node_instance_type  = "bc.t3.medium"
enable_monitoring   = true
```

## Post-Deployment Steps

### 1. Verify Network Creation

```bash
# Get network ID from stack outputs
NETWORK_ID=$(aws cloudformation describe-stacks \
    --stack-name cross-org-blockchain-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`NetworkId`].OutputValue' \
    --output text)

# Check network status
aws managedblockchain get-network \
    --network-id $NETWORK_ID \
    --query 'Network.Status'
```

### 2. Test Cross-Organization Operations

```bash
# Set environment variables from stack outputs
export NETWORK_ID=$(aws cloudformation describe-stacks \
    --stack-name cross-org-blockchain-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`NetworkId`].OutputValue' \
    --output text)

export LAMBDA_FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name cross-org-blockchain-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Run simulation (if available)
node simulate-cross-org-operations.js
```

### 3. Monitor Operations

```bash
# View CloudWatch dashboard
aws cloudwatch get-dashboard \
    --dashboard-name CrossOrgDataSharing

# Check audit trail
aws dynamodb scan \
    --table-name CrossOrgAuditTrail \
    --limit 10
```

## Security Considerations

### IAM Permissions

The solution implements least privilege access with:

- **Blockchain Access**: Scoped to specific network ID
- **S3 Access**: Limited to agreement data paths
- **DynamoDB Access**: Read-only audit trail access
- **Lambda Execution**: Minimal required permissions

### Network Security

- **Private Channels**: Selective data sharing between organizations
- **Certificate Management**: Automatic PKI infrastructure
- **Access Logging**: Comprehensive audit trail for compliance

### Data Protection

- **Encryption**: Data encrypted at rest and in transit
- **Access Controls**: Role-based access to shared data
- **Audit Trail**: Immutable record of all operations

## Monitoring and Troubleshooting

### CloudWatch Dashboards

The solution creates monitoring dashboards for:

- Lambda function performance and errors
- EventBridge event processing metrics
- DynamoDB capacity utilization
- Blockchain network health

### Common Issues

1. **Network Creation Timeout**
   ```bash
   # Check network status
   aws managedblockchain get-network --network-id $NETWORK_ID
   ```

2. **Lambda Function Errors**
   ```bash
   # View function logs
   aws logs filter-log-events \
       --log-group-name "/aws/lambda/$LAMBDA_FUNCTION_NAME"
   ```

3. **Member Join Failures**
   ```bash
   # Check proposal status
   aws managedblockchain list-proposals --network-id $NETWORK_ID
   ```

### Log Locations

- **Lambda Logs**: `/aws/lambda/{function-name}`
- **Blockchain Network**: Amazon Managed Blockchain console
- **EventBridge Events**: CloudWatch Events
- **Audit Trail**: DynamoDB `CrossOrgAuditTrail` table

## Cleanup

> **Important**: Always clean up resources to avoid ongoing charges. Blockchain networks incur costs even when not actively used.

### Using CloudFormation

```bash
# Delete the stack (this will remove all resources)
aws cloudformation delete-stack \
    --stack-name cross-org-blockchain-stack

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name cross-org-blockchain-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK

```bash
# Navigate to CDK directory
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
npx cdk destroy  # or cdk destroy for Python

# Confirm destruction when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually remove resources in this order:

1. Delete blockchain peer nodes
2. Delete blockchain members
3. Delete blockchain network
4. Delete Lambda functions
5. Delete IAM roles and policies
6. Delete DynamoDB tables
7. Empty and delete S3 buckets
8. Delete CloudWatch resources

## Customization

### Adding Additional Organizations

To add more organizations to the network:

1. **CloudFormation**: Add additional member parameters and resources
2. **CDK**: Extend the member creation loop in the construct
3. **Terraform**: Add additional member modules
4. **Scripts**: Extend the deployment script with additional member creation

### Implementing Private Data Collections

Modify the chaincode to include private data collections:

```javascript
// Add to chaincode configuration
const privateDataConfig = {
  name: "orgAOrgBPrivateData",
  policy: "OR('OrgAMSP.member', 'OrgBMSP.member')",
  requiredPeerCount: 1,
  maxPeerCount: 2,
  blockToLive: 0
};
```

### Custom Compliance Rules

Extend the Lambda function to implement organization-specific compliance checks:

```javascript
// Add custom compliance validation
async function validateCompliance(eventData) {
  // Implement GDPR, HIPAA, or other regulatory checks
  return complianceResult;
}
```

## Advanced Features

### Multi-Region Deployment

For global deployment, consider:

- **Region Selection**: Choose regions closest to participating organizations
- **Data Residency**: Ensure blockchain data stays within required jurisdictions
- **Network Latency**: Minimize latency between peer nodes

### Integration Patterns

- **API Gateway**: RESTful interface for blockchain operations
- **Step Functions**: Complex workflow orchestration
- **SQS/SNS**: Asynchronous message processing
- **AppSync**: Real-time GraphQL subscriptions

## Support and Resources

### AWS Documentation

- [Amazon Managed Blockchain Developer Guide](https://docs.aws.amazon.com/managed-blockchain/latest/hyperledger-fabric-dev/)
- [Hyperledger Fabric Documentation](https://hyperledger-fabric.readthedocs.io/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)

### Community Resources

- [AWS Blockchain Samples](https://github.com/aws-samples/amazon-managed-blockchain-client-templates)
- [Hyperledger Fabric Samples](https://github.com/hyperledger/fabric-samples)

### Getting Help

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service status and limits
3. Consult AWS support for service-specific issues
4. Review CloudWatch logs for error details

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment
2. Update documentation for any new parameters
3. Ensure security best practices are maintained
4. Validate cost implications of changes

---

**Note**: This implementation creates enterprise-grade blockchain infrastructure. Ensure you understand the cost implications and security requirements before deploying to production environments.