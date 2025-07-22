# Infrastructure as Code for Event-Driven Architecture with EventBridge

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Event-Driven Architecture with EventBridge". This solution demonstrates how to implement a comprehensive event-driven architecture using Amazon EventBridge with custom event buses, intelligent event routing rules, and multiple event processing targets.

## Architecture Overview

The infrastructure implements a complete event-driven architecture featuring:

- **Custom EventBridge Event Bus**: Isolated event routing for e-commerce domain events
- **Event Rules and Patterns**: Sophisticated event filtering and routing based on content
- **Lambda Functions**: Serverless event processing with business logic
- **SNS/SQS Integration**: Reliable message delivery for notifications and batch processing
- **IAM Security**: Least-privilege access controls for cross-service communication
- **Monitoring Setup**: CloudWatch integration for event tracking and observability

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit with TypeScript
- **CDK Python**: AWS Cloud Development Kit with Python
- **Terraform**: Multi-cloud infrastructure as code with AWS provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements

- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with permissions to create EventBridge, Lambda, SNS, SQS, and IAM resources
- Basic understanding of event-driven architecture patterns
- Python 3.9+ for Lambda functions and event simulation scripts

### Tool-Specific Requirements

#### CloudFormation
- AWS CLI with CloudFormation permissions
- `CAPABILITY_IAM` permissions for IAM role creation

#### CDK TypeScript
- Node.js 18.x or later
- AWS CDK CLI (`npm install -g aws-cdk`)
- TypeScript compiler

#### CDK Python
- Python 3.9+
- AWS CDK CLI (`pip install aws-cdk-lib`)
- Virtual environment recommended

#### Terraform
- Terraform 1.0+
- AWS provider configured

#### Bash Scripts
- Bash 4.0+
- AWS CLI configured
- Python 3.9+ for event publishing scripts

### Estimated Costs

- **EventBridge**: ~$1.00/million events (100M events/month free tier)
- **Lambda**: ~$0.20/million requests (1M requests/month free tier)
- **SNS**: ~$0.50/million notifications (1M notifications/month free tier)
- **SQS**: ~$0.40/million requests (1M requests/month free tier)

## Quick Start

### Using CloudFormation

```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name eventbridge-architecture \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment progress
aws cloudformation describe-stack-events \
    --stack-name eventbridge-architecture

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name eventbridge-architecture \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk output
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the infrastructure
cdk deploy

# View outputs
cdk output
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the infrastructure
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
# 1. Set up environment variables
# 2. Create all AWS resources
# 3. Deploy Lambda function code
# 4. Configure EventBridge rules
# 5. Set up monitoring
# 6. Provide testing commands
```

## Post-Deployment Testing

After deployment, test the event-driven architecture:

### 1. Publish Test Events

```bash
# Using the generated event publisher script
python3 scripts/event_publisher.py --type batch --count 5

# Publish specific event types
python3 scripts/event_publisher.py --type order
python3 scripts/event_publisher.py --type user
python3 scripts/event_publisher.py --type payment
```

### 2. Monitor Event Processing

```bash
# Use the monitoring script
python3 scripts/monitor_events.py

# Check Lambda function logs
aws logs tail /aws/lambda/event-processor-[suffix] --follow
```

### 3. Test High-Value Order Processing

```bash
# This should trigger SNS notification
python3 -c "
import boto3
import json
from datetime import datetime, timezone

eventbridge = boto3.client('events')
event = {
    'Source': 'ecommerce.orders',
    'DetailType': 'Order Created',
    'Detail': json.dumps({
        'orderId': 'test-high-value-order',
        'customerId': 'test-customer',
        'totalAmount': 1500.00,
        'currency': 'USD',
        'timestamp': datetime.now(timezone.utc).isoformat()
    }),
    'EventBusName': 'ecommerce-events-[suffix]'
}
eventbridge.put_events(Entries=[event])
"
```

## Resource Configuration

### Key Components

1. **EventBridge Custom Bus**: `ecommerce-events-[random-suffix]`
2. **Lambda Function**: `event-processor-[random-suffix]`
3. **SNS Topic**: `order-notifications-[random-suffix]`
4. **SQS Queue**: `event-processing-[random-suffix]`
5. **IAM Roles**: EventBridge execution role and Lambda execution role

### Event Rules

- **OrderEventsRule**: Routes order events to Lambda processor
- **HighValueOrdersRule**: Routes high-value orders (>$1000) to SNS
- **AllEventsToSQSRule**: Routes all events to SQS for batch processing
- **UserRegistrationRule**: Routes user registration events to Lambda

### Security Features

- Least-privilege IAM policies
- Service-specific execution roles
- Resource-based permissions
- Event bus isolation

## Customization

### Environment Variables

All implementations support these customizable parameters:

- `Environment`: Deployment environment (dev, staging, prod)
- `EventBusName`: Custom event bus name
- `LambdaTimeout`: Lambda function timeout (default: 30 seconds)
- `LambdaMemory`: Lambda function memory (default: 256 MB)
- `SQSVisibilityTimeout`: SQS message visibility timeout (default: 300 seconds)
- `SNSDisplayName`: SNS topic display name
- `ResourcePrefix`: Prefix for all resource names

### Terraform Variables

```hcl
# Example terraform.tfvars
environment = "production"
event_bus_name = "production-events"
lambda_timeout = 60
lambda_memory = 512
enable_xray_tracing = true
```

### CloudFormation Parameters

```yaml
# Example parameter overrides
Environment: production
LambdaTimeout: 60
LambdaMemory: 512
EnableXRayTracing: true
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name eventbridge-architecture

# Monitor deletion progress
aws cloudformation describe-stack-events \
    --stack-name eventbridge-architecture
```

### Using CDK

```bash
# From the respective CDK directory
cdk destroy

# Confirm destruction when prompted
```

### Using Terraform

```bash
# From the terraform directory
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will:
# 1. Remove all EventBridge rules and targets
# 2. Delete the custom event bus
# 3. Remove Lambda function and IAM roles
# 4. Delete SNS topics and SQS queues
# 5. Clean up local files
```

## Monitoring and Observability

### CloudWatch Metrics

The infrastructure automatically creates CloudWatch metrics for:

- EventBridge successful/failed invocations
- Lambda function duration and errors
- SNS message delivery status
- SQS queue depth and message age

### X-Ray Tracing

Optional X-Ray tracing can be enabled to track events across services:

```bash
# Enable X-Ray tracing (varies by implementation)
# CloudFormation: Set EnableXRayTracing=true
# CDK: Set tracingConfig in Lambda construct
# Terraform: Set tracing_config in Lambda resource
```

### Log Aggregation

All Lambda functions log to CloudWatch Logs with structured JSON formatting for easy searching and analysis.

## Troubleshooting

### Common Issues

1. **Events Not Processing**: Check EventBridge rule patterns and Lambda permissions
2. **Lambda Timeouts**: Increase timeout or memory allocation
3. **SNS Delivery Failures**: Verify topic permissions and subscription endpoints
4. **SQS Message Accumulation**: Check consumer processing capacity

### Debug Commands

```bash
# Check EventBridge metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Events \
    --metric-name SuccessfulInvocations \
    --start-time 2023-01-01T00:00:00Z \
    --end-time 2023-01-01T01:00:00Z \
    --period 300 \
    --statistics Sum

# Check Lambda function logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/event-processor-[suffix] \
    --filter-pattern "ERROR"

# Monitor SQS queue
aws sqs get-queue-attributes \
    --queue-url [queue-url] \
    --attribute-names All
```

## Best Practices

### Event Design

- Use consistent event schemas across your organization
- Include correlation IDs for tracing
- Design events for forward compatibility
- Include sufficient context in event payloads

### Error Handling

- Implement dead letter queues for failed messages
- Use exponential backoff for retries
- Log errors with sufficient context
- Monitor error rates and set up alerts

### Performance Optimization

- Use appropriate Lambda memory settings
- Implement batch processing for high-volume events
- Consider EventBridge archive for event replay
- Use SQS for buffering during traffic spikes

## Advanced Features

### Event Replay

The architecture supports event replay using EventBridge archive:

```bash
# Create archive (can be added to IaC)
aws events create-archive \
    --archive-name ecommerce-events-archive \
    --event-source-arn [event-bus-arn]

# Replay events
aws events start-replay \
    --replay-name recovery-replay \
    --event-source-arn [event-bus-arn] \
    --event-start-time 2023-01-01T00:00:00Z \
    --event-end-time 2023-01-01T01:00:00Z
```

### Cross-Region Replication

For global event distribution, implement cross-region replication:

```bash
# Create replication rule (varies by IaC tool)
# Route events to EventBridge in different regions
# Use EventBridge cross-region targets
```

### Schema Registry

Implement event schema management:

```bash
# Create schema registry
aws schemas create-registry \
    --registry-name ecommerce-events-registry

# Define event schemas
aws schemas create-schema \
    --registry-name ecommerce-events-registry \
    --schema-name order-created-schema \
    --type JSONSchemaDraft4
```

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for architectural guidance
2. Review AWS EventBridge documentation for service-specific issues
3. Consult the AWS Well-Architected Framework for best practices
4. Use AWS Support for production issues

## Contributing

When modifying this infrastructure:

1. Follow the established patterns and naming conventions
2. Update all implementations consistently
3. Test changes in a development environment
4. Update documentation to reflect changes
5. Consider backward compatibility

## License

This infrastructure code is provided as-is under the same license as the parent recipe repository.