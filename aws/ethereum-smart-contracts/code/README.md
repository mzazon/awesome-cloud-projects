# Infrastructure as Code for Smart Contract Development on Ethereum

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Smart Contract Development on Ethereum".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Amazon Managed Blockchain
  - AWS Lambda
  - Amazon API Gateway
  - Amazon S3
  - AWS IAM
  - Amazon CloudWatch
  - AWS Systems Manager Parameter Store
- Node.js 18+ (for CDK TypeScript and contract development)
- Python 3.8+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Estimated cost: $50-100/month for Ethereum mainnet node (bc.t3.xlarge instance)

> **Warning**: Amazon Managed Blockchain Ethereum nodes incur ongoing costs. Consider using testnets for development to minimize expenses.

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name ethereum-blockchain-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=NodeInstanceType,ParameterValue=bc.t3.xlarge \
                ParameterKey=EthereumNetwork,ParameterValue=n-ethereum-mainnet

# Monitor deployment progress
aws cloudformation wait stack-create-complete \
    --stack-name ethereum-blockchain-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name ethereum-blockchain-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy EthereumBlockchainStack

# View outputs
cdk outputs
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy EthereumBlockchainStack

# View outputs
cdk outputs
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Plan the deployment
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

# Monitor deployment (the script will guide you)
# Note: Ethereum node provisioning takes 30-60 minutes
```

## Architecture Overview

This infrastructure deploys:

1. **Amazon Managed Blockchain Ethereum Node**: Fully managed Ethereum node on mainnet
2. **AWS Lambda Function**: Serverless Web3 API for smart contract interactions
3. **Amazon API Gateway**: RESTful API endpoint for blockchain operations
4. **Amazon S3 Bucket**: Storage for smart contract artifacts and source code
5. **CloudWatch Monitoring**: Comprehensive logging and monitoring
6. **IAM Roles and Policies**: Secure access controls

## Configuration Options

### CloudFormation Parameters
- `NodeInstanceType`: EC2 instance type for Ethereum node (default: bc.t3.xlarge)
- `EthereumNetwork`: Ethereum network ID (default: n-ethereum-mainnet)
- `LambdaTimeout`: Lambda function timeout in seconds (default: 60)
- `LambdaMemorySize`: Lambda memory allocation in MB (default: 512)

### CDK/Terraform Variables
- `nodeInstanceType`: Ethereum node instance type
- `ethereumNetwork`: Target Ethereum network
- `lambdaTimeout`: Function execution timeout
- `lambdaMemorySize`: Function memory allocation
- `retentionDays`: CloudWatch log retention period

## Post-Deployment Setup

After infrastructure deployment, you'll need to:

1. **Wait for Node Synchronization**: The Ethereum node takes 30-60 minutes to become available
2. **Upload Smart Contracts**: Deploy your contract artifacts to the S3 bucket
3. **Test API Endpoints**: Verify the API Gateway endpoints are responding
4. **Configure Monitoring**: Set up CloudWatch alarms for production use

### Testing Your Deployment

```bash
# Get API endpoint from stack outputs
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name ethereum-blockchain-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

# Test block number endpoint
curl -X POST ${API_ENDPOINT}/ethereum \
    -H "Content-Type: application/json" \
    -d '{"action":"getBlockNumber"}'

# Test balance query
curl -X POST ${API_ENDPOINT}/ethereum \
    -H "Content-Type: application/json" \
    -d '{"action":"getBalance","address":"0xde0B295669a9FD93d5F28D9Ec85E40f4cb697BAe"}'
```

## Smart Contract Development

The infrastructure supports smart contract development with:

### Contract Compilation
```bash
# Install Solidity compiler
npm install -g solc

# Compile contracts
solc --bin --abi contracts/SimpleToken.sol --output-dir build/
```

### Contract Deployment
```bash
# Deploy via API
curl -X POST ${API_ENDPOINT}/ethereum \
    -H "Content-Type: application/json" \
    -d '{"action":"deployContract","initialSupply":1000000}'
```

### Gas Optimization
The Lambda function includes gas optimization utilities:
- Dynamic gas price estimation
- Network congestion monitoring
- Optimal transaction timing
- Cost calculation and reporting

## Monitoring and Observability

### CloudWatch Dashboards
- Lambda function performance metrics
- API Gateway request/response metrics
- Ethereum node health indicators
- Gas usage and cost tracking

### Alarms and Notifications
- Lambda function error rates
- API Gateway 4xx/5xx errors
- Ethereum node connectivity issues
- Unusually high gas costs

### Log Analysis
```bash
# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/eth-contract-manager

# View API Gateway logs
aws logs describe-log-groups --log-group-name-prefix /aws/apigateway/ethereum-api
```

## Security Considerations

### IAM Policies
- Lambda functions use least-privilege access
- API Gateway has no authentication (configure as needed)
- S3 bucket access is restricted to Lambda function
- Managed Blockchain node uses AWS-managed security

### Network Security
- Ethereum node endpoints are AWS-managed and secured
- API Gateway supports authentication and authorization
- Lambda functions run in AWS VPC by default
- All communications use HTTPS/TLS

### Best Practices
- Store sensitive data in AWS Secrets Manager
- Use API Gateway API keys for rate limiting
- Implement request validation and input sanitization
- Monitor for suspicious blockchain activity

## Cost Optimization

### Pricing Components
- **Managed Blockchain Node**: ~$400-500/month (bc.t3.xlarge on mainnet)
- **Lambda Functions**: Pay per invocation and duration
- **API Gateway**: Pay per API call
- **S3 Storage**: Minimal cost for contract artifacts
- **CloudWatch**: Log storage and monitoring costs

### Cost Reduction Strategies
- Use testnets for development (free node access)
- Implement API Gateway caching for read operations
- Optimize Lambda function memory allocation
- Set up S3 lifecycle policies for log archiving
- Use CloudWatch log retention policies

## Troubleshooting

### Common Issues

1. **Node Not Available**: Ethereum nodes take 30-60 minutes to sync
2. **Lambda Timeout**: Increase timeout for complex contract operations
3. **API Gateway 502 Errors**: Check Lambda function logs for errors
4. **High Gas Costs**: Implement gas price monitoring and optimization

### Debug Commands
```bash
# Check Ethereum node status
aws managedblockchain get-node \
    --network-id n-ethereum-mainnet \
    --node-id NODE_ID

# Test Lambda function directly
aws lambda invoke \
    --function-name eth-contract-manager \
    --payload '{"action":"getBlockNumber"}' \
    response.json

# Check API Gateway configuration
aws apigateway get-rest-apis
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name ethereum-blockchain-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name ethereum-blockchain-stack
```

### Using CDK
```bash
# From CDK directory
cdk destroy EthereumBlockchainStack
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
```

### Manual Cleanup Verification
```bash
# Verify Managed Blockchain node deletion
aws managedblockchain list-nodes --network-id n-ethereum-mainnet

# Check for remaining S3 buckets
aws s3 ls | grep ethereum-artifacts

# Verify Lambda function deletion
aws lambda list-functions | grep eth-contract-manager
```

## Advanced Usage

### Multi-Network Deployment
Modify the infrastructure to support multiple Ethereum networks:
- Add parameters for testnet deployment
- Configure environment-specific settings
- Implement network switching logic

### Contract Factory Pattern
Extend the Lambda function to support:
- Dynamic contract deployment
- Contract instance management
- Version control and upgrades

### Event-Driven Architecture
Integrate with other AWS services:
- Amazon EventBridge for blockchain events
- Amazon Kinesis for real-time analytics
- Amazon SQS for transaction queuing

## Support

For issues with this infrastructure code:
1. Check the original recipe documentation
2. Review AWS service documentation
3. Verify IAM permissions and resource limits
4. Check CloudWatch logs for detailed error messages

## Additional Resources

- [Amazon Managed Blockchain Documentation](https://docs.aws.amazon.com/managed-blockchain/)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [Amazon API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/)
- [Ethereum Development Documentation](https://ethereum.org/en/developers/docs/)
- [Web3.js Documentation](https://web3js.readthedocs.io/)

## License

This infrastructure code is provided as-is for educational and development purposes. Ensure compliance with your organization's policies and AWS terms of service.