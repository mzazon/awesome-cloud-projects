# S3 Event Processing CDK TypeScript Application

This CDK TypeScript application implements the S3 Event Notifications and Automated Processing architecture from the AWS recipe. It creates an event-driven system for processing files uploaded to S3 with intelligent routing based on object prefixes.

## Architecture Overview

The application deploys the following AWS resources:

- **S3 Bucket**: Central storage with intelligent event routing
- **SNS Topic**: Fan-out notifications for broad awareness (`uploads/` prefix)
- **SQS Queue**: Reliable batch processing queue (`batch/` prefix) with dead letter queue
- **Lambda Function**: Immediate processing function (`immediate/` prefix)
- **CloudWatch Log Groups**: Centralized logging with configurable retention
- **IAM Roles & Policies**: Least privilege security model

## Prerequisites

- AWS CLI configured with appropriate permissions
- Node.js 18+ and npm 8+
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- CDK Bootstrap completed in your target AWS account and region

## Installation

1. **Clone and Install Dependencies**:
   ```bash
   cd aws/s3-event-notifications-automated-processing/code/cdk-typescript
   npm install
   ```

2. **Build the Application**:
   ```bash
   npm run build
   ```

3. **Bootstrap CDK (if not already done)**:
   ```bash
   cdk bootstrap
   ```

## Configuration

### Environment Variables

Set the following environment variables or CDK context parameters:

```bash
# Required for CDK
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)
```

### CDK Context Parameters

You can customize the deployment using CDK context parameters:

```bash
# Environment name (default: dev)
cdk deploy -c environment=prod

# Notification email for SNS subscriptions
cdk deploy -c notificationEmail=admin@example.com

# Custom bucket name (optional)
cdk deploy -c bucketName=my-custom-bucket-name

# Disable encryption for development
cdk deploy -c enableEncryption=false

# Set log retention days (default: 30)
cdk deploy -c logRetentionDays=7
```

## Deployment

### Quick Deploy

```bash
npm run deploy
```

### Deploy with Configuration

```bash
# Production deployment with email notifications
cdk deploy -c environment=prod -c notificationEmail=ops@company.com

# Development deployment with custom settings
cdk deploy -c environment=dev -c enableEncryption=false -c logRetentionDays=7
```

### Verify Deployment

```bash
# Check stack outputs
cdk list
aws cloudformation describe-stacks --stack-name S3EventProcessingStack --query 'Stacks[0].Outputs'
```

## Testing the Event Processing

After deployment, test the different processing workflows:

### 1. Test Immediate Processing (Lambda)

```bash
# Get bucket name from stack outputs
BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name S3EventProcessingStack --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' --output text)

# Create test file and upload to immediate/ prefix
echo "Test file for immediate processing" > test-immediate.txt
aws s3 cp test-immediate.txt s3://${BUCKET_NAME}/immediate/test-immediate.txt

# Check Lambda logs
aws logs describe-log-streams --log-group-name "/aws/lambda/file-processor-dev-*" --order-by LastEventTime --descending --limit 1
```

### 2. Test Batch Processing (SQS)

```bash
# Upload to batch/ prefix
echo "Test file for batch processing" > test-batch.txt
aws s3 cp test-batch.txt s3://${BUCKET_NAME}/batch/test-batch.txt

# Check SQS queue for messages
SQS_QUEUE_URL=$(aws cloudformation describe-stacks --stack-name S3EventProcessingStack --query 'Stacks[0].Outputs[?OutputKey==`SqsQueueUrl`].OutputValue' --output text)
aws sqs receive-message --queue-url ${SQS_QUEUE_URL}
```

### 3. Test Notifications (SNS)

```bash
# Upload to uploads/ prefix (requires email subscription)
echo "Test file for notifications" > test-upload.txt
aws s3 cp test-upload.txt s3://${BUCKET_NAME}/uploads/test-upload.txt

# Check email for notification (if email subscription was configured)
```

### 4. Verify Event Filtering

```bash
# Upload to root (should NOT trigger any notifications)
echo "Test file for root upload" > test-root.txt
aws s3 cp test-root.txt s3://${BUCKET_NAME}/test-root.txt

# Verify no Lambda invocations, SQS messages, or SNS notifications
```

## Monitoring and Troubleshooting

### View Lambda Logs

```bash
# Get latest log stream
aws logs describe-log-streams \
  --log-group-name "/aws/lambda/file-processor-dev-*" \
  --order-by LastEventTime --descending --limit 1

# View log events
LOG_STREAM_NAME="<log-stream-name-from-above>"
aws logs get-log-events \
  --log-group-name "/aws/lambda/file-processor-dev-*" \
  --log-stream-name ${LOG_STREAM_NAME}
```

### Monitor SQS Queue

```bash
# Check queue attributes
aws sqs get-queue-attributes \
  --queue-url ${SQS_QUEUE_URL} \
  --attribute-names All
```

### Check SNS Topic

```bash
# List subscriptions
SNS_TOPIC_ARN=$(aws cloudformation describe-stacks --stack-name S3EventProcessingStack --query 'Stacks[0].Outputs[?OutputKey==`SnsTopicArn`].OutputValue' --output text)
aws sns list-subscriptions-by-topic --topic-arn ${SNS_TOPIC_ARN}
```

## Development

### Available Scripts

```bash
# Build TypeScript
npm run build

# Watch for changes
npm run watch

# Run tests
npm run test

# Lint code
npm run lint

# Format code
npm run format

# CDK commands
npm run synth    # Synthesize CloudFormation
npm run diff     # Show differences
npm run deploy   # Deploy stack
npm run destroy  # Destroy stack
```

### Adding Email Subscriptions

To add email subscriptions after deployment:

```bash
SNS_TOPIC_ARN=$(aws cloudformation describe-stacks --stack-name S3EventProcessingStack --query 'Stacks[0].Outputs[?OutputKey==`SnsTopicArn`].OutputValue' --output text)

aws sns subscribe \
  --topic-arn ${SNS_TOPIC_ARN} \
  --protocol email \
  --notification-endpoint your-email@example.com
```

### Customizing the Lambda Function

The Lambda function code is embedded in the CDK stack. To modify the processing logic:

1. Edit the `lambda.Code.fromInline()` section in `lib/s3-event-processing-stack.ts`
2. Rebuild and redeploy: `npm run build && npm run deploy`

For production workloads, consider:
- Moving Lambda code to separate files
- Using Lambda layers for dependencies
- Implementing proper error handling and retry logic
- Adding monitoring and alerting

## Cost Optimization

- **S3 Lifecycle Rules**: Automatically transition files to cheaper storage classes
- **Lambda Configuration**: Right-size memory and timeout settings
- **SQS Batching**: Use batch operations to reduce API calls
- **CloudWatch Logs**: Set appropriate retention periods

## Security Best Practices

The application implements several security best practices:

- **Least Privilege IAM**: Minimal required permissions
- **Encryption**: Optional S3 and SQS encryption
- **Private Access**: S3 bucket blocks public access
- **Source Restrictions**: Event notifications restricted to specific bucket
- **VPC Endpoints**: Consider adding for private communication

## Cleanup

To remove all resources:

```bash
npm run destroy
```

Or using CDK directly:

```bash
cdk destroy
```

**Note**: If you enabled versioning or have objects in the bucket, you may need to empty the bucket manually first.

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure your AWS credentials have necessary permissions
2. **Bucket Already Exists**: Use a custom bucket name with `-c bucketName=unique-name`
3. **Lambda Timeout**: Increase timeout in the stack configuration
4. **Missing Dependencies**: Run `npm install` to install all dependencies

### Getting Help

- Check CloudFormation events in the AWS Console
- Review CloudWatch logs for Lambda execution details
- Use `cdk diff` to see what changes will be applied
- Enable CDK debug logging: `cdk deploy --debug`

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.