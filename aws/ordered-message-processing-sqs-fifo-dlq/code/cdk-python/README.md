# Ordered Message Processing with SQS FIFO and Dead Letter Queues - CDK Python

This CDK Python application implements a production-ready ordered message processing system using Amazon SQS FIFO queues with sophisticated deduplication, message grouping strategies, and comprehensive dead letter queue handling for financial trading systems and other mission-critical applications.

## Architecture Overview

The solution implements the following components:

- **DynamoDB Table**: Order state management with Global Secondary Index and streams
- **S3 Bucket**: Poison message archival with lifecycle policies for cost optimization
- **SNS Topic**: Operational alerting for critical system events
- **SQS FIFO Queues**: Main processing queue and dead letter queue with advanced configuration
- **Lambda Functions**: Message processor, poison handler, and message replay capabilities
- **CloudWatch Alarms**: Comprehensive monitoring for failure rates, latency, and poison messages
- **IAM Roles**: Least-privilege security with scoped permissions

## Features

### Message Processing
- **Strict Ordering**: FIFO queues ensure message order within message groups
- **Exactly-Once Processing**: Content-based deduplication and idempotency checks
- **High Throughput**: Per-message-group deduplication scope for horizontal scaling
- **Failure Isolation**: Automatic routing to dead letter queue after 3 failed attempts

### Poison Message Handling
- **Intelligent Analysis**: Categorizes failures by severity and recoverability
- **Automated Recovery**: Attempts to fix common issues (e.g., negative amounts)
- **S3 Archival**: Comprehensive metadata storage for manual investigation
- **Real-time Alerting**: SNS notifications for critical poison messages

### Operational Features
- **Message Replay**: Time-based and group-based filtering with dry-run capabilities
- **Comprehensive Monitoring**: CloudWatch metrics and alarms for proactive management
- **Cost Optimization**: S3 lifecycle policies and DynamoDB provisioned capacity
- **Security**: Least-privilege IAM roles and encryption at rest

## Prerequisites

- Python 3.8 or later
- AWS CDK v2 (latest version)
- AWS CLI configured with appropriate permissions
- Node.js 14.x or later (for CDK CLI)

## Installation

1. **Clone or download this CDK application**

2. **Create and activate a Python virtual environment**:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Install AWS CDK CLI** (if not already installed):
   ```bash
   npm install -g aws-cdk
   ```

## Configuration

You can customize the deployment by modifying the context values in `cdk.json`:

### Project Configuration
```json
{
  "projectName": "fifo-processing",
  "enableDeadLetterQueues": true,
  "enablePoisonMessageHandling": true,
  "enableMessageReplay": true
}
```

### FIFO Queue Configuration
```json
{
  "fifoQueueConfiguration": {
    "contentBasedDeduplication": false,
    "deduplicationScope": "messageGroup",
    "throughputLimit": "perMessageGroupId",
    "maxReceiveCount": 3,
    "visibilityTimeoutSeconds": 300,
    "messageRetentionPeriodDays": 14
  }
}
```

### Lambda Configuration
```json
{
  "lambdaConfiguration": {
    "runtime": "python3.9",
    "timeout": 300,
    "memorySize": 512,
    "reservedConcurrency": 10,
    "logRetentionDays": 7
  }
}
```

## Deployment

### Bootstrap CDK (first time only)
```bash
cdk bootstrap
```

### Deploy the stack
```bash
cdk deploy
```

### Deploy with custom project name
```bash
cdk deploy -c projectName=my-custom-name
```

### Deploy to specific environment
```bash
cdk deploy -c projectName=production \
  --profile production-profile \
  --region us-west-2
```

## Usage

### Sending Test Messages

After deployment, you can send test messages to the main FIFO queue:

```bash
# Get queue URL from stack outputs
MAIN_QUEUE_URL=$(aws cloudformation describe-stacks \
  --stack-name OrderedMessageProcessingStack \
  --query 'Stacks[0].Outputs[?OutputKey==`MainQueueUrl`].OutputValue' \
  --output text)

# Send a valid message
aws sqs send-message \
  --queue-url $MAIN_QUEUE_URL \
  --message-body '{
    "orderId": "order-123",
    "orderType": "BUY",
    "amount": 100.50,
    "symbol": "STOCK1",
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }' \
  --message-group-id "trading-group-1" \
  --message-deduplication-id "$(uuidgen)"
```

### Sending Poison Messages (for testing)

```bash
# Send a message with negative amount (will be handled by poison handler)
aws sqs send-message \
  --queue-url $MAIN_QUEUE_URL \
  --message-body '{
    "orderId": "poison-1",
    "orderType": "BUY", 
    "amount": -100,
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }' \
  --message-group-id "test-group" \
  --message-deduplication-id "$(uuidgen)"
```

### Message Replay

To replay archived messages, invoke the replay Lambda function:

```bash
# Get function name from stack outputs
REPLAY_FUNCTION=$(aws cloudformation describe-stacks \
  --stack-name OrderedMessageProcessingStack \
  --query 'Stacks[0].Outputs[?OutputKey==`MessageReplayFunctionName`].OutputValue' \
  --output text)

# Test replay in dry-run mode
aws lambda invoke \
  --function-name $REPLAY_FUNCTION \
  --payload '{
    "replay_request": {
      "start_time": "'$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)'",
      "dry_run": true
    }
  }' \
  replay_result.json

cat replay_result.json
```

### Monitoring

Access CloudWatch to monitor:

- **Custom Metrics**: Navigate to CloudWatch > Metrics > FIFO/MessageProcessing
- **Alarms**: CloudWatch > Alarms to see configured monitoring
- **Lambda Logs**: CloudWatch > Log Groups > /aws/lambda/[function-name]
- **DynamoDB**: Monitor table metrics and stream activity

## Testing

### Unit Tests
```bash
python -m pytest tests/ -v
```

### Integration Tests
```bash
python -m pytest tests/integration/ -v --integration
```

### Coverage Report
```bash
python -m pytest tests/ --cov=app --cov-report=html
```

## Development

### Code Formatting
```bash
black app.py
```

### Type Checking
```bash
mypy app.py
```

### Linting
```bash
flake8 app.py
```

### CDK Commands

- `cdk ls` - List all stacks
- `cdk synth` - Synthesize CloudFormation template
- `cdk diff` - Compare deployed stack with current state
- `cdk deploy` - Deploy the stack
- `cdk destroy` - Delete the stack
- `cdk doctor` - Check for common issues

## Stack Outputs

After deployment, the stack provides these outputs:

- **MainQueueUrl**: URL of the main FIFO queue for sending messages
- **DeadLetterQueueUrl**: URL of the dead letter queue
- **OrderTableName**: Name of the DynamoDB table storing order state
- **ArchiveBucketName**: Name of the S3 bucket for poison message archival
- **AlertTopicArn**: ARN of the SNS topic for operational alerts
- **MessageProcessorFunctionName**: Name of the message processor Lambda
- **PoisonHandlerFunctionName**: Name of the poison handler Lambda
- **MessageReplayFunctionName**: Name of the message replay Lambda

## Cost Optimization

The solution implements several cost optimization strategies:

### S3 Lifecycle Policies
- Transitions to Standard-IA after 30 days
- Transitions to Glacier after 90 days
- Automatic cleanup on stack deletion

### DynamoDB Configuration
- Provisioned capacity for predictable costs
- Point-in-time recovery enabled
- Streams for real-time processing

### Lambda Optimization
- Reserved concurrency to control costs
- Appropriate memory allocation
- Log retention policies

### Monitoring Cost Control
- CloudWatch alarms for cost anomaly detection
- Custom metrics to track processing efficiency
- Resource tagging for cost allocation

## Security

### IAM Least Privilege
- Separate roles for different Lambda functions
- Resource-specific permissions
- No wildcard permissions except where necessary

### Encryption
- SQS queues encrypted with AWS managed keys
- S3 bucket server-side encryption enabled
- DynamoDB encryption at rest

### Network Security
- All resources deployed in default VPC
- Security groups restrict access as needed
- No public endpoints exposed

## Troubleshooting

### Common Issues

1. **Permission Errors**
   - Ensure AWS credentials are properly configured
   - Verify IAM permissions for CDK deployment
   - Check CloudFormation stack events

2. **Queue Visibility**
   - Messages may be invisible due to visibility timeout
   - Check CloudWatch logs for processing errors
   - Verify message format and required fields

3. **DLQ Processing**
   - Monitor DLQ depth in CloudWatch
   - Check poison handler logs for analysis results
   - Verify S3 bucket for archived messages

4. **Lambda Timeout**
   - Increase timeout in `cdk.json` lambda configuration
   - Monitor CloudWatch metrics for duration
   - Check for infinite loops or blocking operations

### Debugging Commands

```bash
# Check stack status
cdk diff

# View CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name OrderedMessageProcessingStack

# Check Lambda function logs
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/lambda/fifo-processing"

# Monitor SQS queue attributes
aws sqs get-queue-attributes \
  --queue-url $MAIN_QUEUE_URL \
  --attribute-names All
```

## Cleanup

To avoid ongoing charges, destroy the stack when no longer needed:

```bash
cdk destroy
```

This will:
- Delete all Lambda functions and logs
- Remove SQS queues and messages
- Delete DynamoDB table and data
- Empty and delete S3 bucket
- Remove CloudWatch alarms and custom metrics
- Clean up IAM roles and policies

## Support

For issues with this CDK application:

1. Check CloudWatch logs for error messages
2. Review AWS CloudFormation stack events
3. Verify AWS service limits and quotas
4. Consult AWS CDK documentation
5. Review the original recipe documentation

## License

This sample code is made available under the MIT-0 license. See the LICENSE file.

## Contributing

Contributions are welcome! Please read the contributing guidelines and submit pull requests for any improvements.