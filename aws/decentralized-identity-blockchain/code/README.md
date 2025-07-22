# Infrastructure as Code for Implementing Decentralized Identity Management with Blockchain

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing Decentralized Identity Management with Blockchain".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation deploys a complete decentralized identity management system including:

- AWS Managed Blockchain (Hyperledger Fabric) network
- Amazon QLDB ledger for identity state management
- AWS Lambda functions for identity operations
- Amazon API Gateway for RESTful identity services
- Amazon DynamoDB for credential indexing
- Amazon S3 for chaincode and schema storage
- IAM roles and policies for secure access

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Managed Blockchain (full access)
  - QLDB (full access)
  - Lambda (full access)
  - API Gateway (full access)
  - DynamoDB (full access)
  - S3 (full access)
  - IAM (role and policy creation)
- Node.js 18+ (for CDK implementations)
- Python 3.8+ (for CDK Python implementation)
- Terraform 1.0+ (for Terraform implementation)
- Docker Desktop (for chaincode development)
- Estimated cost: $150-250 for full deployment over 4-5 hours

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name decentralized-identity-stack \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NetworkName,ParameterValue=identity-network \
                 ParameterKey=MemberName,ParameterValue=identity-org \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# Wait for deployment to complete
aws cloudformation wait stack-create-complete \
    --stack-name decentralized-identity-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name decentralized-identity-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy DecentralizedIdentityStack

# View outputs
cdk deploy DecentralizedIdentityStack --outputs-file outputs.json
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy DecentralizedIdentityStack

# View outputs
cdk deploy DecentralizedIdentityStack --outputs-file outputs.json
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
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

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts and wait for deployment completion
```

## Configuration Options

### CloudFormation Parameters

- `NetworkName`: Name for the blockchain network (default: identity-network)
- `MemberName`: Name for the blockchain member organization (default: identity-org)
- `AdminUsername`: Administrator username for blockchain access (default: admin)
- `LedgerName`: Name for the QLDB ledger (default: identity-ledger)
- `Environment`: Deployment environment tag (default: development)

### CDK Configuration

Both TypeScript and Python CDK implementations support configuration through:

```typescript
// In cdk-typescript/app.ts
const config = {
  networkName: 'identity-network',
  memberName: 'identity-org',
  adminUsername: 'admin',
  ledgerName: 'identity-ledger',
  environment: 'development'
};
```

### Terraform Variables

Configure deployment in `terraform/terraform.tfvars`:

```hcl
# Network configuration
network_name = "identity-network"
member_name = "identity-org"
admin_username = "admin"

# QLDB configuration
ledger_name = "identity-ledger"

# Environment and tagging
environment = "development"
project_name = "decentralized-identity"

# Region settings
aws_region = "us-east-1"
```

### Bash Script Environment Variables

Set environment variables before running bash scripts:

```bash
export NETWORK_NAME="identity-network"
export MEMBER_NAME="identity-org"
export ADMIN_USERNAME="admin"
export LEDGER_NAME="identity-ledger"
export AWS_REGION="us-east-1"
```

## Post-Deployment Steps

### 1. Deploy Identity Chaincode

After infrastructure deployment, deploy the identity management chaincode:

```bash
# Package and install chaincode (run from chaincode directory)
peer lifecycle chaincode package identity-management.tar.gz \
    --path . --lang node --label identity-management_1.0

# Install on peer nodes
peer lifecycle chaincode install identity-management.tar.gz

# Approve and commit chaincode
peer lifecycle chaincode approveformyorg \
    --channelID mychannel \
    --name identity-management \
    --version 1.0 \
    --package-id [PACKAGE_ID] \
    --sequence 1

peer lifecycle chaincode commit \
    --channelID mychannel \
    --name identity-management \
    --version 1.0 \
    --sequence 1
```

### 2. Test Identity Operations

Test the deployed system:

```bash
# Test identity creation
curl -X POST \
    https://[API_GATEWAY_URL]/prod/identity \
    -H "Content-Type: application/json" \
    -d '{
        "action": "createIdentity",
        "publicKey": "[BASE64_PUBLIC_KEY]",
        "metadata": {
            "name": "Test User",
            "email": "test@example.com"
        }
    }'

# Test credential issuance
curl -X POST \
    https://[API_GATEWAY_URL]/prod/identity \
    -H "Content-Type: application/json" \
    -d '{
        "action": "issueCredential",
        "did": "[GENERATED_DID]",
        "credentialType": "UniversityDegree",
        "claims": {
            "degree": "Bachelor of Science",
            "university": "Example University"
        }
    }'
```

## Monitoring and Management

### CloudWatch Dashboards

The deployment creates CloudWatch dashboards for monitoring:

- Blockchain network health
- Lambda function performance
- API Gateway metrics
- QLDB transaction volume

### Logging

All components are configured with comprehensive logging:

- Lambda functions log to CloudWatch Logs
- API Gateway access and execution logs
- Blockchain network event logs
- QLDB query and transaction logs

### Security Monitoring

Monitor security events through:

- AWS CloudTrail for API calls
- VPC Flow Logs for network traffic
- GuardDuty for threat detection
- Security Hub for compliance monitoring

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name decentralized-identity-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name decentralized-identity-stack
```

### Using CDK

```bash
# TypeScript
cd cdk-typescript/
cdk destroy DecentralizedIdentityStack

# Python
cd cdk-python/
cdk destroy DecentralizedIdentityStack
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Customization

### Scaling Configuration

Adjust instance types and capacity:

```yaml
# CloudFormation
PeerNodeInstanceType:
  Type: String
  Default: bc.t3.small
  AllowedValues: [bc.t3.small, bc.t3.medium, bc.t3.large]

LambdaMemorySize:
  Type: Number
  Default: 256
  MinValue: 128
  MaxValue: 3008
```

### Network Configuration

Customize blockchain network settings:

```hcl
# Terraform
variable "voting_policy" {
  description = "Network voting policy configuration"
  type = object({
    threshold_percentage = number
    proposal_duration_hours = number
    threshold_comparator = string
  })
  default = {
    threshold_percentage = 50
    proposal_duration_hours = 24
    threshold_comparator = "GREATER_THAN"
  }
}
```

### Security Hardening

Additional security configurations:

- Enable encryption at rest for all storage services
- Configure VPC endpoints for private connectivity
- Implement API Gateway authentication with Cognito
- Enable AWS WAF for DDoS protection
- Configure backup strategies for QLDB and DynamoDB

## Troubleshooting

### Common Issues

1. **Blockchain Network Creation Timeout**
   - Check region availability for Managed Blockchain
   - Verify IAM permissions for blockchain operations
   - Ensure unique network and member names

2. **Lambda Function Deployment Failures**
   - Verify Node.js runtime compatibility
   - Check IAM role permissions
   - Ensure VPC configuration if applicable

3. **QLDB Access Issues**
   - Verify QLDB service availability in region
   - Check IAM permissions for QLDB operations
   - Validate session token generation

4. **API Gateway Integration Errors**
   - Check Lambda function ARN configuration
   - Verify API Gateway execution role
   - Validate request/response mapping

### Getting Help

- Review AWS service documentation for specific error codes
- Check AWS CloudFormation/CDK logs for deployment issues
- Monitor CloudWatch Logs for runtime errors
- Use AWS Support for service-specific issues

## Security Considerations

### Identity Data Protection

- All identity data is encrypted in transit and at rest
- Blockchain provides immutable audit trail
- QLDB offers cryptographic verification
- Personal data remains with credential holders

### Access Control

- IAM roles follow principle of least privilege
- API Gateway provides rate limiting and throttling
- VPC endpoints ensure private connectivity
- Multi-factor authentication recommended for admin access

### Compliance

- Architecture supports GDPR compliance through privacy by design
- Audit logs provide comprehensive compliance reporting
- Decentralized model reduces data protection obligations
- Cryptographic proofs enable regulatory compliance

## Performance Optimization

### Blockchain Performance

- Use appropriate peer node instance types
- Optimize chaincode for efficient execution
- Implement proper indexing for queries
- Monitor consensus performance

### Database Performance

- Configure QLDB with appropriate capacity
- Use DynamoDB on-demand scaling
- Implement proper query patterns
- Monitor read/write capacity utilization

### API Performance

- Enable API Gateway caching
- Optimize Lambda function memory allocation
- Use connection pooling for database connections
- Implement proper error handling and retries

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation
3. Consult provider-specific troubleshooting guides
4. Contact AWS Support for service-specific issues

## Contributing

To improve this infrastructure code:

1. Test changes thoroughly in development environment
2. Follow AWS best practices and security guidelines
3. Update documentation for any configuration changes
4. Validate compatibility across all IaC implementations