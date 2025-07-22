# Infrastructure as Code for Message Fan-out with SNS and Multiple SQS Queues

This directory contains Infrastructure as Code (IaC) implementations for the recipe "SNS Message Fan-out with Multiple SQS Queues".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution implements a message fan-out pattern where:
- SNS topic receives order events from applications
- Multiple SQS queues subscribe to the topic with message filtering
- Each queue serves a specific business function (inventory, payment, shipping, analytics)
- Dead letter queues handle failed message processing
- CloudWatch provides monitoring and alerting

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - SNS (topics, subscriptions)
  - SQS (queues, policies)
  - IAM (roles, policies)
  - CloudWatch (alarms, dashboards)
- Tool-specific prerequisites (see individual sections below)

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name message-fanout-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Monitor deployment
aws cloudformation describe-stacks \
    --stack-name message-fanout-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name message-fanout-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk output
```

### Using CDK Python
```bash
# Navigate to CDK directory
cd cdk-python/

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time)
cdk bootstrap

# Deploy the stack
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

# Apply changes
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
./scripts/deploy.sh --status
```

## Testing the Solution

After deployment, test the message fan-out functionality:

```bash
# Get the SNS topic ARN from outputs
TOPIC_ARN=$(aws cloudformation describe-stacks \
    --stack-name message-fanout-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`TopicArn`].OutputValue' \
    --output text)

# Publish a test message
aws sns publish \
    --topic-arn $TOPIC_ARN \
    --message '{"orderId": "test-123", "amount": 99.99}' \
    --message-attributes '{
        "eventType": {"DataType": "String", "StringValue": "payment_confirmation"},
        "priority": {"DataType": "String", "StringValue": "high"}
    }'

# Check queue message counts
aws sqs get-queue-attributes \
    --queue-url $(aws cloudformation describe-stacks \
        --stack-name message-fanout-stack \
        --query 'Stacks[0].Outputs[?OutputKey==`PaymentQueueUrl`].OutputValue' \
        --output text) \
    --attribute-names ApproximateNumberOfMessages
```

## Monitoring and Observability

### CloudWatch Dashboard
Access the automatically created dashboard:
```bash
# Get dashboard URL
aws cloudformation describe-stacks \
    --stack-name message-fanout-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`DashboardUrl`].OutputValue' \
    --output text
```

### Key Metrics to Monitor
- SNS message publish rate and failures
- SQS queue depths and message age
- Dead letter queue message counts
- CloudWatch alarm states

### Alarms
The solution includes pre-configured alarms for:
- High inventory queue depth (>100 messages)
- High payment queue depth (>50 messages)
- SNS delivery failures (>5 failures)

## Configuration Options

### Environment Variables
Set these before deployment to customize the solution:

```bash
# CloudFormation parameters
export ENVIRONMENT=dev
export NOTIFICATION_EMAIL=ops@company.com

# Terraform variables
export TF_VAR_environment=dev
export TF_VAR_notification_email=ops@company.com

# CDK context
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
```

### Message Filtering
The solution includes default message filters:
- **Inventory Queue**: `eventType` = inventory_update, stock_check
- **Payment Queue**: `eventType` = payment_request, payment_confirmation
- **Shipping Queue**: `eventType` = shipping_notification, delivery_update
- **Analytics Queue**: No filter (receives all messages)

Modify the filter policies in the IaC templates to customize routing.

### Queue Configuration
Default queue settings:
- **Visibility Timeout**: 300 seconds
- **Message Retention**: 14 days
- **Dead Letter Queue**: 3 max receive attempts

## Security Considerations

### IAM Permissions
The solution follows the principle of least privilege:
- SNS topic has restricted publish permissions
- SQS queues only accept messages from the SNS topic
- CloudWatch has minimal required permissions

### Encryption
- SNS topics use server-side encryption
- SQS queues use SQS-managed encryption
- Dead letter queues inherit encryption settings

### Network Security
- All resources are deployed in the default VPC
- Consider VPC endpoints for private connectivity

## Cost Optimization

### Estimated Costs
- SNS requests: $0.50 per million requests
- SQS requests: $0.40 per million requests
- CloudWatch alarms: $0.10 per alarm per month
- CloudWatch dashboards: $3.00 per dashboard per month

### Cost Optimization Tips
1. Use SQS long polling to reduce empty receives
2. Implement message batching where possible
3. Monitor and adjust queue retention periods
4. Use SNS message filtering to reduce unnecessary deliveries

## Troubleshooting

### Common Issues

**Messages not appearing in queues:**
- Check SNS subscription filters
- Verify SQS queue policies
- Confirm message attributes format

**High DLQ message counts:**
- Review application error logs
- Check queue visibility timeout settings
- Verify consumer processing logic

**CloudWatch alarms not triggering:**
- Confirm alarm thresholds
- Check IAM permissions
- Verify metric publication

### Debugging Commands

```bash
# Check SNS topic subscriptions
aws sns list-subscriptions-by-topic --topic-arn $TOPIC_ARN

# Monitor queue attributes
aws sqs get-queue-attributes \
    --queue-url $QUEUE_URL \
    --attribute-names All

# View CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/SNS \
    --metric-name NumberOfMessagesPublished \
    --dimensions Name=TopicName,Value=$TOPIC_NAME \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name message-fanout-stack

# Monitor deletion
aws cloudformation describe-stacks \
    --stack-name message-fanout-stack \
    --query 'Stacks[0].StackStatus'
```

### Using CDK
```bash
# From the CDK directory
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform
```bash
# From the terraform directory
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm deletions when prompted
```

## Customization

### Adding New Queues
To add additional processing queues:

1. Define the new queue in your IaC template
2. Create corresponding dead letter queue
3. Add SNS subscription with appropriate filter
4. Update monitoring dashboard and alarms

### Modifying Message Filters
Edit the subscription filter policies in your chosen IaC template:

```json
{
  "eventType": ["new_event_type"],
  "priority": ["high", "medium"],
  "region": ["us-east-1", "us-west-2"]
}
```

### Scaling Configuration
For high-volume scenarios:
- Enable SQS FIFO queues for ordering guarantees
- Implement SQS batch operations
- Add auto-scaling for queue consumers
- Consider cross-region replication

## Integration Examples

### Lambda Function Consumer
```python
import json
import boto3

def lambda_handler(event, context):
    for record in event['Records']:
        # Parse SNS message
        message = json.loads(record['body'])
        sns_message = json.loads(message['Message'])
        
        # Process based on message attributes
        event_type = message['MessageAttributes']['eventType']['Value']
        
        if event_type == 'inventory_update':
            process_inventory_update(sns_message)
        elif event_type == 'payment_confirmation':
            process_payment_confirmation(sns_message)
```

### Application Publishing
```python
import boto3
import json

sns = boto3.client('sns')

def publish_order_event(order_data, event_type, priority):
    sns.publish(
        TopicArn='your-topic-arn',
        Message=json.dumps(order_data),
        MessageAttributes={
            'eventType': {
                'DataType': 'String',
                'StringValue': event_type
            },
            'priority': {
                'DataType': 'String',
                'StringValue': priority
            }
        }
    )
```

## Support

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult AWS documentation for specific services
4. Consider AWS support channels for complex issues

## Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Validate security best practices
3. Update documentation
4. Follow the established patterns and conventions