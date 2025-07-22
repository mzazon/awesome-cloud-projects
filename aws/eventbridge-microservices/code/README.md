# Infrastructure as Code for Microservices with EventBridge Routing

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Microservices with EventBridge Routing".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure deploys a complete event-driven e-commerce platform featuring:

- Custom EventBridge event bus for domain isolation
- Lambda functions for order processing and inventory management
- SQS queue for asynchronous payment processing
- EventBridge rules with intelligent pattern matching
- CloudWatch integration for monitoring and observability
- IAM roles with least privilege access

## Prerequisites

- AWS CLI v2 installed and configured with appropriate permissions
- AWS account with permissions to create:
  - EventBridge custom event buses and rules
  - Lambda functions and IAM roles
  - SQS queues and CloudWatch log groups
  - EventBridge targets and permissions
- For CDK deployments: Node.js 18+ and npm/yarn
- For Terraform: Terraform 1.0+ installed
- Basic understanding of event-driven architecture patterns

**Estimated Monthly Cost**: $5-20 USD (varies based on event volume and Lambda executions)

> **Note**: Review [EventBridge pricing](https://aws.amazon.com/eventbridge/pricing/) and [Lambda pricing](https://aws.amazon.com/lambda/pricing/) for detailed cost information.

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name eventbridge-ecommerce-demo \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=demo

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name eventbridge-ecommerce-demo \
    --query 'Stacks[0].StackStatus'

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name eventbridge-ecommerce-demo \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
npx cdk bootstrap

# Deploy the infrastructure
npx cdk deploy EventBridgeEcommerceStack

# View deployed resources
npx cdk list
```

### Using CDK Python (AWS)

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv

# Activate virtual environment
source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the infrastructure
cdk deploy EventBridgeEcommerceStack

# View deployed resources
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

# Deploy the infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/status.sh
```

## Testing the Deployment

After successful deployment, test the event-driven architecture:

### 1. Generate Test Events

```bash
# Get the event generator function name from outputs
EVENT_GENERATOR_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name eventbridge-ecommerce-demo \
    --query 'Stacks[0].Outputs[?OutputKey==`EventGeneratorFunction`].OutputValue' \
    --output text)

# Generate a test order event
aws lambda invoke \
    --function-name $EVENT_GENERATOR_FUNCTION \
    --payload '{}' \
    --cli-binary-format raw-in-base64-out \
    response.json

# View the response
cat response.json
```

### 2. Monitor Event Processing

```bash
# Check order processor logs
aws logs describe-log-streams \
    --log-group-name /aws/lambda/eventbridge-demo-order-processor \
    --order-by LastEventTime --descending --max-items 1 \
    --query 'logStreams[0].logStreamName' --output text | \
xargs -I {} aws logs get-log-events \
    --log-group-name /aws/lambda/eventbridge-demo-order-processor \
    --log-stream-name {} --limit 10

# Check inventory manager logs
aws logs describe-log-streams \
    --log-group-name /aws/lambda/eventbridge-demo-inventory-manager \
    --order-by LastEventTime --descending --max-items 1 \
    --query 'logStreams[0].logStreamName' --output text | \
xargs -I {} aws logs get-log-events \
    --log-group-name /aws/lambda/eventbridge-demo-inventory-manager \
    --log-stream-name {} --limit 10
```

### 3. Check Payment Queue

```bash
# Get payment queue URL from outputs
PAYMENT_QUEUE_URL=$(aws cloudformation describe-stacks \
    --stack-name eventbridge-ecommerce-demo \
    --query 'Stacks[0].Outputs[?OutputKey==`PaymentQueueUrl`].OutputValue' \
    --output text)

# Check for messages in payment queue
aws sqs receive-message \
    --queue-url $PAYMENT_QUEUE_URL \
    --max-number-of-messages 5
```

## Customization

### Configuration Variables

Each implementation provides variables for customization:

#### CloudFormation Parameters
- `Environment`: Deployment environment (dev, staging, prod)
- `CustomBusName`: Name for the custom EventBridge bus
- `LambdaTimeout`: Timeout for Lambda functions (default: 30 seconds)

#### CDK Configuration
- Modify `cdk.json` for deployment settings
- Update stack properties in the main application file
- Customize Lambda runtime and memory settings

#### Terraform Variables
- `aws_region`: AWS region for deployment
- `environment`: Environment tag for resources
- `lambda_timeout`: Lambda function timeout
- `custom_bus_name`: Custom EventBridge bus name

### Lambda Function Customization

To modify Lambda function behavior:

1. **Order Processing Logic**: Edit the order processor code to add business rules
2. **Inventory Management**: Customize inventory checking and reservation logic
3. **Event Schemas**: Modify event structure in the event generator
4. **Error Handling**: Enhance error handling and retry logic

### EventBridge Rule Patterns

Customize event routing by modifying rule patterns:

```json
{
    "source": ["ecommerce.api"],
    "detail-type": ["Order Created"],
    "detail": {
        "totalAmount": [{"numeric": [">", 100]}],
        "customerType": ["premium"]
    }
}
```

### Monitoring and Alerting

Add CloudWatch alarms for operational monitoring:

```bash
# Create alarm for failed Lambda invocations
aws cloudwatch put-metric-alarm \
    --alarm-name "EventBridge-Lambda-Errors" \
    --alarm-description "Alert on Lambda function errors" \
    --metric-name Errors \
    --namespace AWS/Lambda \
    --statistic Sum \
    --period 300 \
    --threshold 1 \
    --comparison-operator GreaterThanThreshold
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name eventbridge-ecommerce-demo

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name eventbridge-ecommerce-demo
```

### Using CDK (AWS)

```bash
# Destroy the stack
npx cdk destroy EventBridgeEcommerceStack

# Confirm deletion when prompted
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Architecture Components

### EventBridge Resources
- **Custom Event Bus**: Domain-specific event routing
- **Event Rules**: Pattern-based event filtering and routing
- **Event Targets**: Lambda functions, SQS queues, CloudWatch logs

### Lambda Functions
- **Order Processor**: Handles order created events and emits processing status
- **Inventory Manager**: Manages inventory checks and reservations
- **Event Generator**: Simulates API events for testing

### Supporting Services
- **SQS Queue**: Asynchronous payment processing with delayed message handling
- **CloudWatch Logs**: Centralized logging and monitoring
- **IAM Roles**: Least privilege access for all services

## Security Considerations

The infrastructure implements several security best practices:

- **IAM Least Privilege**: Each service has minimal required permissions
- **Resource-Based Policies**: EventBridge rules and SQS queues use resource-based access
- **VPC Isolation**: Lambda functions can be deployed in VPC for network isolation
- **Event Source Validation**: EventBridge rules validate event sources and patterns

### Additional Security Enhancements

Consider implementing these security improvements:

1. **Event Source Validation**: Validate event sources using custom authorizers
2. **Encryption**: Enable encryption at rest for SQS queues and CloudWatch logs
3. **Network Isolation**: Deploy Lambda functions in private VPC subnets
4. **Monitoring**: Set up AWS CloudTrail for API call auditing

## Troubleshooting

### Common Issues

1. **Events Not Routing**: Check EventBridge rule patterns and permissions
2. **Lambda Timeouts**: Increase timeout or optimize function code
3. **Permission Errors**: Verify IAM roles have necessary permissions
4. **Queue Visibility**: Check SQS visibility timeout settings

### Debugging Commands

```bash
# Check EventBridge rule matches
aws events describe-rule \
    --name your-rule-name \
    --event-bus-name your-bus-name

# View Lambda function configuration
aws lambda get-function \
    --function-name your-function-name

# Check SQS queue attributes
aws sqs get-queue-attributes \
    --queue-url your-queue-url \
    --attribute-names All
```

## Performance Optimization

### EventBridge Optimization
- Use specific event patterns to reduce rule evaluations
- Implement event deduplication for idempotency
- Consider cross-region replication for disaster recovery

### Lambda Optimization
- Optimize memory allocation based on workload
- Use provisioned concurrency for consistent performance
- Implement connection pooling for external service calls

### Cost Optimization
- Monitor EventBridge rule evaluations and optimize patterns
- Use SQS batch processing to reduce Lambda invocations
- Implement event archiving with S3 lifecycle policies

## Extension Ideas

1. **Step Functions Integration**: Add workflow orchestration for complex business processes
2. **Schema Registry**: Implement event schema validation and evolution
3. **Cross-Region Replication**: Set up disaster recovery with event replication
4. **API Destinations**: Integrate with external HTTP endpoints
5. **Event Replay**: Implement event sourcing with replay capabilities

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../event-driven-architectures-with-eventbridge.md)
2. Review [AWS EventBridge documentation](https://docs.aws.amazon.com/eventbridge/)
3. Consult [AWS Lambda best practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
4. Review [EventBridge troubleshooting guide](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-troubleshooting.html)

## Version History

- **v1.0**: Initial implementation with basic event-driven architecture
- **v1.1**: Added comprehensive monitoring and error handling
- **v1.2**: Enhanced security with least privilege IAM policies

---

**Note**: This infrastructure code implements the complete solution described in the recipe "Microservices with EventBridge Routing". All components are production-ready with proper security, monitoring, and error handling configurations.