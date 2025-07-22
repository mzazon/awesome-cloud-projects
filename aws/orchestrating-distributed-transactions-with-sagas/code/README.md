# Infrastructure as Code for Orchestrating Distributed Transactions with Saga Patterns

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Orchestrating Distributed Transactions with Saga Patterns".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Step Functions (create/manage state machines)
  - Lambda (create/manage functions)
  - DynamoDB (create/manage tables)
  - SNS (create/manage topics)
  - API Gateway (create/manage APIs)
  - IAM (create/manage roles and policies)
  - CloudWatch (logging and monitoring)
- Node.js 16+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)

## Architecture Overview

This implementation creates a complete saga orchestration system with:

- **Step Functions State Machine**: Central saga orchestrator
- **Lambda Functions**: Business services (Order, Inventory, Payment, Notification)
- **Compensation Lambda Functions**: Rollback services (Cancel Order, Revert Inventory, Refund Payment)
- **DynamoDB Tables**: Data persistence for each service
- **SNS Topic**: Notification system
- **API Gateway**: REST endpoint for saga initiation
- **IAM Roles**: Proper security configuration

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name saga-pattern-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=demo

# Monitor deployment
aws cloudformation describe-stack-events \
    --stack-name saga-pattern-stack

# Get outputs
aws cloudformation describe-stacks \
    --stack-name saga-pattern-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Install dependencies
cd cdk-typescript/
npm install

# Bootstrap CDK (first time only)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy

# View outputs
npx cdk ls
```

### Using CDK Python

```bash
# Install dependencies
cd cdk-python/
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk ls
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Plan deployment
terraform plan

# Deploy infrastructure
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

# Check deployment status
./scripts/status.sh
```

## Testing the Saga Pattern

After deployment, test the saga orchestration:

### Test Successful Transaction

```bash
# Get API endpoint from outputs
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name saga-pattern-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

# Test successful order
curl -X POST ${API_ENDPOINT}/orders \
    -H "Content-Type: application/json" \
    -d '{
      "customerId": "customer-123",
      "productId": "laptop-001",
      "quantity": 2,
      "amount": 1999.98
    }'
```

### Test Failure and Compensation

```bash
# Test insufficient inventory (should trigger compensation)
curl -X POST ${API_ENDPOINT}/orders \
    -H "Content-Type: application/json" \
    -d '{
      "customerId": "customer-456",
      "productId": "laptop-001",
      "quantity": 20,
      "amount": 19999.80
    }'
```

### Monitor Executions

```bash
# Get state machine ARN
STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
    --stack-name saga-pattern-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
    --output text)

# List executions
aws stepfunctions list-executions \
    --state-machine-arn $STATE_MACHINE_ARN

# Describe specific execution
aws stepfunctions describe-execution \
    --execution-arn <execution-arn>
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name saga-pattern-stack

# Monitor deletion
aws cloudformation describe-stack-events \
    --stack-name saga-pattern-stack
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npx cdk destroy
```

### Using CDK Python

```bash
cd cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Clean up all resources
./scripts/destroy.sh
```

## Customization

### CloudFormation Parameters

- `Environment`: Environment name (default: demo)
- `RetentionInDays`: CloudWatch logs retention (default: 7)
- `PaymentFailureRate`: Simulated payment failure rate (default: 0.2)

### CDK Configuration

Modify the stack configuration in `app.ts` or `app.py`:

```typescript
// CDK TypeScript
const sagaStack = new SagaPatternStack(app, 'SagaPatternStack', {
  env: { region: 'us-east-1' },
  environment: 'production',
  retentionInDays: 30
});
```

### Terraform Variables

Configure in `terraform.tfvars`:

```hcl
environment = "production"
aws_region = "us-west-2"
retention_in_days = 14
payment_failure_rate = 0.1
```

### Bash Script Variables

Edit environment variables in `scripts/deploy.sh`:

```bash
export ENVIRONMENT="production"
export AWS_REGION="us-west-2"
export RETENTION_DAYS=14
```

## Monitoring and Observability

### CloudWatch Dashboards

All implementations create CloudWatch dashboards for monitoring:

- Step Functions execution metrics
- Lambda function performance
- DynamoDB table metrics
- API Gateway request metrics

### X-Ray Tracing

Enable X-Ray tracing for distributed transaction visibility:

```bash
# Enable tracing on the state machine
aws stepfunctions update-state-machine \
    --state-machine-arn $STATE_MACHINE_ARN \
    --tracing-configuration enabled=true
```

### Alarms and Notifications

Configure CloudWatch alarms for:

- High failure rates in saga executions
- Lambda function errors
- DynamoDB throttling
- API Gateway 5xx errors

## Security Considerations

### IAM Roles

All implementations follow least privilege principles:

- Step Functions role: Limited to invoking Lambda functions
- Lambda execution role: Access only to required DynamoDB tables and SNS topics
- API Gateway role: Limited to starting Step Functions executions

### Data Encryption

- DynamoDB tables: Encryption at rest enabled
- SNS topics: Server-side encryption enabled
- Lambda functions: Environment variables encrypted

### Network Security

- API Gateway: Configure with API keys or AWS WAF for production
- Lambda functions: Deploy in VPC for enhanced security
- DynamoDB: Enable VPC endpoints for private access

## Troubleshooting

### Common Issues

1. **IAM Permission Errors**: Ensure the deployment role has sufficient permissions
2. **State Machine Failures**: Check CloudWatch logs for Lambda function errors
3. **API Gateway 5xx Errors**: Verify IAM roles and Step Functions integration
4. **DynamoDB Throttling**: Adjust read/write capacity or enable auto-scaling

### Debug Commands

```bash
# Check Lambda function logs
aws logs tail /aws/lambda/saga-order-service --follow

# Describe Step Functions execution
aws stepfunctions get-execution-history \
    --execution-arn <execution-arn>

# Check DynamoDB table status
aws dynamodb describe-table \
    --table-name saga-orders
```

## Cost Optimization

### Estimated Costs

- Step Functions: ~$0.025 per 1,000 state transitions
- Lambda: ~$0.20 per 1M requests + compute time
- DynamoDB: ~$0.25 per GB/month (on-demand)
- API Gateway: ~$3.50 per million requests

### Cost Reduction Strategies

1. Use Step Functions Express workflows for high-volume scenarios
2. Optimize Lambda function memory allocation
3. Use DynamoDB reserved capacity for predictable workloads
4. Implement API Gateway caching

## Performance Tuning

### Lambda Optimization

- Adjust memory allocation based on usage patterns
- Enable Lambda provisioned concurrency for consistent performance
- Use Lambda layers for shared dependencies

### DynamoDB Optimization

- Design efficient partition keys
- Use DynamoDB Accelerator (DAX) for read-heavy workloads
- Enable auto-scaling for dynamic capacity management

### Step Functions Optimization

- Use parallel execution where possible
- Implement appropriate retry and backoff strategies
- Consider Express workflows for high-throughput scenarios

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review AWS service documentation
3. Consult CloudFormation/CDK/Terraform provider documentation
4. Check AWS service quotas and limits

## Contributing

When modifying this infrastructure code:

1. Follow the original recipe architecture
2. Maintain security best practices
3. Update documentation accordingly
4. Test all deployment methods
5. Validate cleanup procedures

## Version History

- v1.0: Initial implementation with CloudFormation, CDK, Terraform, and Bash scripts
- v1.1: Added comprehensive monitoring and security improvements