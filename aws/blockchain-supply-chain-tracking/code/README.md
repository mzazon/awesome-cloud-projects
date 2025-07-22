# Infrastructure as Code for Blockchain Supply Chain Tracking Systems

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Blockchain Supply Chain Tracking Systems".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a decentralized blockchain-based supply chain tracking system using:

- **Amazon Managed Blockchain** with Hyperledger Fabric for immutable record-keeping
- **AWS IoT Core** for sensor data collection from supply chain assets
- **AWS Lambda** for processing sensor data and blockchain interactions
- **Amazon EventBridge** for multi-party notifications and event orchestration
- **Amazon DynamoDB** for metadata storage and fast queries
- **Amazon S3** for chaincode storage and data archiving
- **Amazon CloudWatch** for monitoring and alerting

## Prerequisites

- AWS CLI v2 installed and configured with appropriate permissions
- Administrative access to create IAM roles, policies, and managed blockchain networks
- Understanding of blockchain concepts and Hyperledger Fabric
- Node.js 18+ (for CDK implementations)
- Python 3.9+ (for CDK Python implementation)
- Terraform 1.0+ (for Terraform implementation)
- Estimated cost: $150-200 for initial setup and testing

### Required AWS Permissions

- Amazon Managed Blockchain full access
- AWS IoT Core full access
- AWS Lambda full access
- Amazon EventBridge full access
- Amazon DynamoDB full access
- Amazon S3 full access
- Amazon CloudWatch full access
- IAM role and policy management

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name blockchain-supply-chain \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=NetworkName,ParameterValue=supply-chain-network \
                 ParameterKey=MemberName,ParameterValue=manufacturer \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region us-east-1

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name blockchain-supply-chain

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name blockchain-supply-chain \
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
cdk deploy --parameters networkName=supply-chain-network \
           --parameters memberName=manufacturer

# Get outputs
cdk output
```

### Using CDK Python

```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Deploy the stack
cdk deploy --parameters networkName=supply-chain-network \
           --parameters memberName=manufacturer

# Get outputs
cdk output
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="network_name=supply-chain-network" \
               -var="member_name=manufacturer"

# Apply the configuration
terraform apply -var="network_name=supply-chain-network" \
                -var="member_name=manufacturer"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export NETWORK_NAME="supply-chain-network"
export MEMBER_NAME="manufacturer"
export AWS_REGION="us-east-1"

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/deploy.sh --status
```

## Configuration Options

### CloudFormation Parameters

- `NetworkName`: Name for the blockchain network (default: supply-chain-network)
- `MemberName`: Name for the initial member organization (default: manufacturer)
- `NodeInstanceType`: EC2 instance type for blockchain peer nodes (default: bc.t3.small)
- `IoTThingName`: Name for the IoT thing representing supply chain devices
- `LambdaMemorySize`: Memory allocation for Lambda function (default: 256 MB)
- `LambdaTimeout`: Timeout for Lambda function execution (default: 30 seconds)

### Terraform Variables

```hcl
# Example terraform.tfvars
network_name = "my-supply-chain-network"
member_name = "my-company"
node_instance_type = "bc.t3.small"
iot_thing_name = "my-supply-chain-tracker"
lambda_memory_size = 256
lambda_timeout = 30
```

### CDK Configuration

Both CDK implementations support the same parameters via CDK context:

```bash
# Example CDK deployment with custom parameters
cdk deploy -c networkName=my-supply-chain-network \
           -c memberName=my-company \
           -c nodeInstanceType=bc.t3.small
```

## Post-Deployment Setup

1. **Chaincode Deployment**: After infrastructure deployment, deploy the supply chain chaincode to the blockchain network
2. **IoT Device Registration**: Register actual IoT devices or configure simulation scripts
3. **Member Onboarding**: Invite additional organizations to join the blockchain network
4. **Monitoring Setup**: Configure CloudWatch dashboards and alarms for operational monitoring

## Testing the Deployment

```bash
# Test IoT data publication
aws iot-data publish \
    --topic supply-chain/sensor-data \
    --payload '{
        "productId": "TEST-PROD-001",
        "location": "Factory",
        "temperature": 22.5,
        "humidity": 48.2,
        "timestamp": '$(date +%s)'
    }'

# Check Lambda function logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/ProcessSupplyChainData" \
    --start-time $(date -d '5 minutes ago' +%s)000

# Query DynamoDB for test data
aws dynamodb scan \
    --table-name SupplyChainMetadata \
    --limit 5
```

## Cleanup

### Using CloudFormation

```bash
# Delete the CloudFormation stack
aws cloudformation delete-stack \
    --stack-name blockchain-supply-chain

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name blockchain-supply-chain
```

### Using CDK

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy the infrastructure
terraform destroy -var="network_name=supply-chain-network" \
                  -var="member_name=manufacturer"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Security Considerations

- **IAM Permissions**: The deployment creates IAM roles with least-privilege access
- **Network Security**: Blockchain network uses VPC endpoints for secure access
- **Data Encryption**: All data is encrypted in transit and at rest
- **Access Control**: IoT devices require proper authentication and authorization
- **Audit Logging**: All blockchain transactions are immutable and auditable

## Monitoring and Troubleshooting

### CloudWatch Dashboards

The deployment creates monitoring dashboards for:
- Lambda function performance and errors
- DynamoDB read/write metrics
- IoT Core message processing
- EventBridge event processing

### Common Issues

1. **Network Creation Delays**: Blockchain networks can take 15-30 minutes to provision
2. **IoT Permission Errors**: Ensure IoT policies are correctly attached to certificates
3. **Lambda Timeout Issues**: Increase timeout if processing complex blockchain transactions
4. **DynamoDB Throttling**: Monitor read/write capacity and adjust as needed

### Logs and Debugging

```bash
# View Lambda function logs
aws logs tail /aws/lambda/ProcessSupplyChainData --follow

# Check EventBridge rule metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Events \
    --metric-name MatchedEvents \
    --dimensions Name=RuleName,Value=SupplyChainTrackingRule \
    --start-time $(date -d '1 hour ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Sum
```

## Customization

### Adding New IoT Sensors

1. Create additional IoT things in the IoT Core console
2. Update IoT policies to include new device certificates
3. Modify Lambda function to handle additional sensor types
4. Update EventBridge rules for new event patterns

### Extending Blockchain Network

1. Invite additional AWS accounts as new members
2. Configure endorsement policies for multi-organization approval
3. Deploy chaincode to new peer nodes
4. Update application logic to handle multi-party consensus

### Scaling Considerations

- **Blockchain Network**: Upgrade from STARTER to STANDARD edition for production
- **Lambda Functions**: Configure reserved concurrency for predictable performance
- **DynamoDB**: Switch to on-demand billing for variable workloads
- **IoT Core**: Implement device shadows for offline operation capability

## Cost Optimization

- Use AWS Cost Explorer to monitor blockchain network costs
- Configure S3 lifecycle policies for long-term data archiving
- Implement Lambda provisioned concurrency only when needed
- Monitor DynamoDB read/write patterns and optimize table design

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation for implementation details
2. Check AWS service documentation for configuration options
3. Monitor CloudWatch logs for detailed error information
4. Use AWS Support for service-specific issues

## Additional Resources

- [Amazon Managed Blockchain Developer Guide](https://docs.aws.amazon.com/managed-blockchain/latest/hyperledger-fabric-dev/)
- [AWS IoT Core Developer Guide](https://docs.aws.amazon.com/iot/latest/developerguide/)
- [Hyperledger Fabric Documentation](https://hyperledger-fabric.readthedocs.io/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)