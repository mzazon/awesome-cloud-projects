# Infrastructure as Code for Building Distributed Transaction Processing with SQS

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Building Distributed Transaction Processing with SQS".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements the Saga pattern for distributed transaction processing using:

- **Amazon SQS FIFO Queues**: For ordered message processing and transaction coordination
- **Amazon DynamoDB**: For transaction state management and business data storage
- **AWS Lambda**: For microservice implementation and transaction orchestration
- **Amazon API Gateway**: For HTTP API endpoints to initiate transactions
- **Amazon CloudWatch**: For monitoring, logging, and alerting

## Prerequisites

- AWS CLI v2 installed and configured
- AWS account with permissions for DynamoDB, SQS, Lambda, IAM, API Gateway, and CloudWatch
- For CDK: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Basic understanding of distributed systems and transaction patterns
- Estimated cost: $15-25 per day for testing

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name distributed-transaction-processing \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=EnvironmentName,ParameterValue=dev

# Monitor deployment progress
aws cloudformation describe-stack-events \
    --stack-name distributed-transaction-processing

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name distributed-transaction-processing \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# Get deployment outputs
cdk list
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if not already done)
cdk bootstrap

# Deploy the stack
cdk deploy

# Get deployment outputs
cdk list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
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

# The script will:
# 1. Create all required AWS resources
# 2. Deploy Lambda functions
# 3. Configure API Gateway
# 4. Set up monitoring
# 5. Initialize sample data
```

## Testing the Solution

After deployment, test the distributed transaction system:

### Test Successful Transaction

```bash
# Get API endpoint from outputs
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name distributed-transaction-processing \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

# Send test transaction
curl -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "customerId": "CUST-001",
        "productId": "PROD-001",
        "quantity": 2,
        "amount": 2599.98
    }' \
    "${API_ENDPOINT}/transactions"
```

### Test Failed Transaction (Inventory Constraint)

```bash
# Test with high quantity to trigger inventory failure
curl -X POST \
    -H "Content-Type: application/json" \
    -d '{
        "customerId": "CUST-002",
        "productId": "PROD-003",
        "quantity": 100,
        "amount": 79999.00
    }' \
    "${API_ENDPOINT}/transactions"
```

### Monitor Transaction Status

```bash
# Check CloudWatch dashboard
aws cloudwatch get-dashboard \
    --dashboard-name "distributed-transaction-processing-transactions"

# View Lambda function logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/distributed-transaction-processing"
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name distributed-transaction-processing

# Monitor deletion progress
aws cloudformation describe-stack-events \
    --stack-name distributed-transaction-processing
```

### Using CDK

```bash
# Navigate to CDK directory (TypeScript or Python)
cd cdk-typescript/  # or cd cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Remove all created resources
# 2. Delete Lambda functions
# 3. Clean up IAM roles
# 4. Remove local files
```

## Customization

### Environment Variables

Each implementation supports customization through variables:

- **Environment Name**: Prefix for all resources (default: "distributed-tx")
- **AWS Region**: Deployment region (default: current CLI region)
- **Lambda Timeout**: Function timeout in seconds (default: 300)
- **SQS Message Retention**: Message retention period (default: 14 days)
- **DynamoDB Billing Mode**: PAY_PER_REQUEST or PROVISIONED

### CloudFormation Parameters

```yaml
Parameters:
  EnvironmentName:
    Type: String
    Default: distributed-tx
    Description: Environment name prefix for resources
  
  LambdaTimeout:
    Type: Number
    Default: 300
    Description: Lambda function timeout in seconds
```

### CDK Configuration

```typescript
// cdk-typescript/app.ts
const app = new cdk.App();

const config = {
  environmentName: app.node.tryGetContext('environmentName') || 'distributed-tx',
  region: app.node.tryGetContext('region') || 'us-east-1',
  lambdaTimeout: app.node.tryGetContext('lambdaTimeout') || 300
};
```

### Terraform Variables

```hcl
# terraform/variables.tf
variable "environment_name" {
  description = "Environment name prefix for resources"
  type        = string
  default     = "distributed-tx"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
}
```

## Architecture Components

### Lambda Functions

1. **Transaction Orchestrator**: Coordinates saga transactions and manages state
2. **Order Service**: Handles order creation and validation
3. **Payment Service**: Processes payments with failure simulation
4. **Inventory Service**: Manages inventory updates with atomic operations
5. **Compensation Handler**: Manages transaction rollbacks

### DynamoDB Tables

1. **Saga State Table**: Tracks transaction progress and state
2. **Orders Table**: Stores order information
3. **Payments Table**: Records payment transactions
4. **Inventory Table**: Manages product inventory levels

### SQS Queues

1. **Order Processing Queue**: FIFO queue for order processing
2. **Payment Processing Queue**: FIFO queue for payment processing
3. **Inventory Update Queue**: FIFO queue for inventory updates
4. **Compensation Queue**: FIFO queue for rollback operations
5. **Dead Letter Queue**: Handles failed messages

### Monitoring

1. **CloudWatch Alarms**: Monitor transaction failures and queue age
2. **CloudWatch Dashboard**: Real-time metrics visualization
3. **Lambda Logs**: Detailed execution logs for debugging

## Security Considerations

- **IAM Roles**: Least privilege access for Lambda functions
- **VPC**: Optional VPC deployment for enhanced security
- **Encryption**: DynamoDB encryption at rest enabled
- **API Gateway**: Rate limiting and request validation
- **CloudTrail**: API call logging for audit trails

## Troubleshooting

### Common Issues

1. **Lambda Timeout**: Increase timeout values in configuration
2. **DynamoDB Throttling**: Monitor read/write capacity metrics
3. **SQS Message Delays**: Check queue visibility timeout settings
4. **API Gateway Errors**: Verify Lambda permissions and integration

### Debug Steps

1. Check CloudWatch logs for Lambda function errors
2. Monitor SQS queue metrics for message processing
3. Verify DynamoDB table status and capacity
4. Review API Gateway access logs

### Log Locations

- Lambda logs: `/aws/lambda/{function-name}`
- API Gateway logs: `/aws/apigateway/{api-id}`
- CloudTrail logs: CloudTrail console

## Performance Optimization

### Scaling Considerations

- **Lambda Concurrency**: Configure reserved concurrency for critical functions
- **DynamoDB**: Use on-demand billing or configure auto-scaling
- **SQS**: Monitor queue depth and adjust batch sizes
- **API Gateway**: Implement caching for frequently accessed endpoints

### Cost Optimization

- **DynamoDB**: Use on-demand billing for variable workloads
- **Lambda**: Optimize memory allocation and execution time
- **SQS**: Configure message retention based on requirements
- **CloudWatch**: Set appropriate log retention periods

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation for specific resources
3. Consult the CloudFormation/CDK/Terraform documentation
4. Monitor AWS service health dashboard for outages

## Additional Resources

- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Saga Pattern Documentation](https://docs.aws.amazon.com/prescriptive-guidance/latest/modernization-data-persistence/saga-pattern.html)
- [DynamoDB Transactions](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/transaction-apis.html)
- [SQS FIFO Queues](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-fifo-queues.html)
- [Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)