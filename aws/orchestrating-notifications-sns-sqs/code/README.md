# Infrastructure as Code for Building Serverless Notification Systems with SNS, SQS, and Lambda

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Building Serverless Notification Systems with SNS, SQS, and Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates a serverless notification system that includes:

- **SNS Topic**: Central message hub for publishing notifications
- **SQS Queues**: Separate queues for email, SMS, webhook, and dead letter processing
- **Lambda Functions**: Serverless processors for email and webhook notifications
- **IAM Roles**: Secure access permissions for Lambda functions
- **Message Filtering**: Intelligent routing based on notification type
- **Dead Letter Queue**: Failed message handling and retry logic

## Prerequisites

- AWS CLI v2 installed and configured with appropriate credentials
- AWS account with permissions to create SNS topics, SQS queues, Lambda functions, and IAM roles
- For CDK implementations:
  - Node.js 16+ (for TypeScript)
  - Python 3.9+ (for Python)
  - AWS CDK v2 installed globally
- For Terraform:
  - Terraform v1.0+ installed
  - AWS provider configured
- Email address for testing notifications
- Basic understanding of serverless architectures and message queuing

## Estimated Costs

- **SNS**: ~$0.50 per million requests
- **SQS**: ~$0.40 per million requests  
- **Lambda**: ~$0.20 per million requests
- **CloudWatch Logs**: ~$0.50 per GB ingested

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name serverless-notification-system \
    --template-body file://cloudformation.yaml \
    --parameters ParameterKey=TestEmail,ParameterValue=your-email@example.com \
    --capabilities CAPABILITY_IAM

# Monitor deployment
aws cloudformation wait stack-create-complete \
    --stack-name serverless-notification-system

# Get outputs
aws cloudformation describe-stacks \
    --stack-name serverless-notification-system \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK directory
cd cdk-typescript/

# Install dependencies
npm install

# Set test email environment variable
export TEST_EMAIL=your-email@example.com

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

# Set test email environment variable
export TEST_EMAIL=your-email@example.com

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

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
test_email = "your-email@example.com"
aws_region = "us-east-1"
EOF

# Plan deployment
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export TEST_EMAIL=your-email@example.com
export AWS_REGION=us-east-1

# Deploy infrastructure
./scripts/deploy.sh

# The script will output resource ARNs and testing instructions
```

## Testing the Notification System

After deployment, test the system using the provided test publisher:

```bash
# Using CloudFormation outputs
SNS_TOPIC_ARN=$(aws cloudformation describe-stacks \
    --stack-name serverless-notification-system \
    --query 'Stacks[0].Outputs[?OutputKey==`SNSTopicArn`].OutputValue' \
    --output text)

# Test email notification
aws sns publish \
    --topic-arn $SNS_TOPIC_ARN \
    --message '{"subject":"Test Email","message":"Hello from serverless notifications!","recipient":"your-email@example.com"}' \
    --message-attributes 'notification_type={"DataType":"String","StringValue":"email"}'

# Test webhook notification  
aws sns publish \
    --topic-arn $SNS_TOPIC_ARN \
    --message '{"subject":"Test Webhook","message":"Hello webhook!","webhook_url":"https://httpbin.org/post","payload":{"test":true}}' \
    --message-attributes 'notification_type={"DataType":"String","StringValue":"webhook"}'

# Test broadcast notification (goes to all channels)
aws sns publish \
    --topic-arn $SNS_TOPIC_ARN \
    --message '{"subject":"Broadcast Test","message":"This goes everywhere!","recipient":"your-email@example.com","webhook_url":"https://httpbin.org/post"}' \
    --message-attributes 'notification_type={"DataType":"String","StringValue":"all"}'
```

## Monitoring and Verification

### Check Lambda Function Logs

```bash
# Email handler logs
aws logs tail /aws/lambda/EmailNotificationHandler --follow

# Webhook handler logs  
aws logs tail /aws/lambda/WebhookNotificationHandler --follow
```

### Monitor Queue Metrics

```bash
# Get queue URLs from CloudFormation
EMAIL_QUEUE_URL=$(aws cloudformation describe-stacks \
    --stack-name serverless-notification-system \
    --query 'Stacks[0].Outputs[?OutputKey==`EmailQueueUrl`].OutputValue' \
    --output text)

# Check queue depth
aws sqs get-queue-attributes \
    --queue-url $EMAIL_QUEUE_URL \
    --attribute-names ApproximateNumberOfMessages
```

### View CloudWatch Metrics

```bash
# Lambda invocations
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=EmailNotificationHandler \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-01T23:59:59Z \
    --period 300 \
    --statistics Sum

# SQS message counts
aws cloudwatch get-metric-statistics \
    --namespace AWS/SQS \
    --metric-name NumberOfMessagesSent \
    --dimensions Name=QueueName,Value=email-notifications-* \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-01T23:59:59Z \
    --period 300 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name serverless-notification-system

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name serverless-notification-system
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
cdk destroy
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
# Run cleanup script
./scripts/destroy.sh
```

## Customization

### Environment Variables

All implementations support these customization options:

- `TEST_EMAIL`: Email address for testing notifications
- `AWS_REGION`: AWS region for resource deployment
- `NOTIFICATION_SYSTEM_NAME`: Prefix for resource names
- `ENABLE_SMS_QUEUE`: Whether to create SMS processing queue (true/false)
- `DLQ_MAX_RECEIVE_COUNT`: Maximum retry attempts before dead letter queue (default: 3)
- `LAMBDA_TIMEOUT`: Lambda function timeout in seconds (default: 300)
- `LAMBDA_MEMORY_SIZE`: Lambda function memory allocation in MB (default: 128)

### Advanced Configuration

#### Message Filtering

Customize message routing by modifying filter policies:

```json
{
  "notification_type": ["email", "urgent"],
  "priority": ["high", "critical"],
  "region": ["us-east-1", "us-west-2"]
}
```

#### Dead Letter Queue Settings

Adjust retry behavior in queue configurations:

```json
{
  "maxReceiveCount": 5,
  "deadLetterTargetArn": "arn:aws:sqs:region:account:dlq-name"
}
```

#### Lambda Function Environment Variables

Configure notification handlers with custom settings:

```json
{
  "EMAIL_PROVIDER": "ses",
  "WEBHOOK_TIMEOUT": "30",
  "RETRY_ATTEMPTS": "3",
  "LOG_LEVEL": "INFO"
}
```

## Production Considerations

### Security Hardening

1. **Encryption**: Enable encryption at rest for SQS queues using AWS KMS
2. **Access Control**: Implement least privilege IAM policies
3. **VPC Integration**: Deploy Lambda functions in private subnets
4. **Secrets Management**: Use AWS Secrets Manager for API keys

### Performance Optimization

1. **Batching**: Configure optimal batch sizes for Lambda event source mappings
2. **Concurrency**: Set reserved concurrency limits for Lambda functions
3. **Memory Allocation**: Optimize Lambda memory settings based on workload
4. **Connection Pooling**: Implement connection reuse for webhook handlers

### Monitoring and Alerting

1. **CloudWatch Alarms**: Set up alarms for failed invocations and queue depth
2. **X-Ray Tracing**: Enable distributed tracing for debugging
3. **Custom Metrics**: Implement business-specific metrics
4. **Dashboard**: Create CloudWatch dashboards for operational visibility

### Cost Optimization

1. **Right-sizing**: Adjust Lambda memory and timeout settings
2. **Queue Optimization**: Configure appropriate message retention periods
3. **Monitoring**: Set up billing alerts for unexpected costs
4. **Cleanup**: Implement automated cleanup for old log groups

## Troubleshooting

### Common Issues

1. **Lambda Timeout**: Increase timeout or optimize function code
2. **Permission Errors**: Verify IAM roles have required permissions
3. **Queue Visibility**: Check SQS visibility timeout settings
4. **Message Format**: Ensure message payloads match expected schema

### Debug Commands

```bash
# Check Lambda function configuration
aws lambda get-function --function-name EmailNotificationHandler

# Inspect SQS queue attributes
aws sqs get-queue-attributes --queue-url $QUEUE_URL --attribute-names All

# View SNS topic subscriptions
aws sns list-subscriptions-by-topic --topic-arn $TOPIC_ARN

# Check IAM role permissions
aws iam get-role-policy --role-name NotificationLambdaRole --policy-name SQSAccessPolicy
```

### Support Resources

- [AWS SNS Documentation](https://docs.aws.amazon.com/sns/)
- [AWS SQS Documentation](https://docs.aws.amazon.com/sqs/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)

## Contributing

To extend this solution:

1. Fork the repository
2. Create a feature branch
3. Implement your changes
4. Test thoroughly
5. Submit a pull request

## License

This code is provided under the MIT License. See LICENSE file for details.