# Event-Driven Data Processing with S3 Event Notifications - CDK TypeScript

This CDK TypeScript application deploys a complete event-driven data processing pipeline using S3 event notifications, Lambda functions, SQS, SNS, and CloudWatch monitoring.

## Architecture Overview

The solution implements the following components:

- **S3 Bucket**: Data landing zone with versioning and lifecycle policies
- **Lambda Functions**: Data processing and error handling functions
- **SQS Dead Letter Queue**: Captures failed processing attempts
- **SNS Topic**: Sends alerts for processing failures
- **CloudWatch Alarms**: Monitor function errors and queue depth
- **IAM Roles**: Secure access policies following least privilege principles

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18.x or later
- TypeScript 5.x or later
- AWS CDK v2 installed globally (`npm install -g aws-cdk`)
- Appropriate AWS permissions for creating IAM roles, Lambda functions, S3 buckets, etc.

## Installation

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Bootstrap CDK (first time only)**:
   ```bash
   cdk bootstrap
   ```

3. **Build the application**:
   ```bash
   npm run build
   ```

## Configuration

Set environment variables before deployment:

```bash
# Required: Your email for SNS notifications
export NOTIFICATION_EMAIL="your-email@example.com"

# Optional: Resource suffix for unique naming
export RESOURCE_SUFFIX="dev123"

# Optional: Enable detailed monitoring and dashboard
export ENABLE_DETAILED_MONITORING="true"

# Optional: Environment and owner tags
export ENVIRONMENT="dev"
export OWNER="data-team"
```

## Deployment

1. **Review the changes**:
   ```bash
   npm run diff
   ```

2. **Deploy the stack**:
   ```bash
   npm run deploy
   ```

3. **Confirm your email subscription**:
   - Check your email for the SNS subscription confirmation
   - Click the confirmation link to receive alerts

## Testing

1. **Upload a test file to trigger processing**:
   ```bash
   # Create a test CSV file
   echo "name,age,city" > test-data.csv
   echo "John,30,New York" >> test-data.csv
   
   # Upload to trigger processing (replace bucket name from stack output)
   aws s3 cp test-data.csv s3://data-processing-${RESOURCE_SUFFIX}/data/test-data.csv
   ```

2. **Monitor the processing**:
   ```bash
   # Check Lambda function logs
   aws logs tail /aws/lambda/data-processor-${RESOURCE_SUFFIX} --follow
   
   # Check for processing reports
   aws s3 ls s3://data-processing-${RESOURCE_SUFFIX}/reports/
   ```

3. **Test error handling**:
   ```bash
   # Upload an invalid file to trigger error handling
   echo "invalid content" > invalid-test.txt
   aws s3 cp invalid-test.txt s3://data-processing-${RESOURCE_SUFFIX}/data/invalid-test.txt
   
   # Check Dead Letter Queue
   aws sqs get-queue-attributes --queue-url <DLQ_URL> --attribute-names ApproximateNumberOfMessages
   ```

## Monitoring

The stack includes comprehensive monitoring:

- **CloudWatch Alarms**: Alert on Lambda errors and DLQ message count
- **SNS Notifications**: Email alerts for processing failures
- **Custom Dashboard**: (Optional) Visual monitoring of key metrics
- **Lambda Logs**: Detailed processing logs in CloudWatch

### Key Metrics to Monitor

- Lambda function invocations and errors
- Processing duration and timeouts
- Dead Letter Queue message count
- S3 bucket object count and size

## Customization

### Modifying Data Processing Logic

Edit the Lambda function code in `lib/event-driven-data-processing-stack.ts`:

1. Update the `process_csv_file()` and `process_json_file()` functions
2. Add support for additional file types
3. Modify the processing report format
4. Add custom error handling logic

### Adding New Event Sources

To process events from additional S3 prefixes:

```typescript
// Add another event notification
dataBucket.addEventNotification(
  s3.EventType.OBJECT_CREATED,
  new s3n.LambdaDestination(dataProcessorFunction),
  {
    prefix: 'batch-data/',
    suffix: '.parquet'
  }
);
```

### Scaling Configuration

Adjust Lambda function settings for your workload:

```typescript
const dataProcessorFunction = new lambda.Function(this, 'DataProcessorFunction', {
  // ... other properties
  memorySize: 1024,  // Increase for memory-intensive processing
  timeout: cdk.Duration.seconds(900),  // Maximum 15 minutes
  reservedConcurrentExecutions: 100,  // Limit concurrent executions
});
```

## Security Considerations

The stack implements security best practices:

- **IAM Roles**: Least privilege access for Lambda functions
- **S3 Bucket**: Block public access and encryption enabled
- **VPC**: Consider deploying Lambda functions in VPC for additional security
- **Secrets**: Use AWS Secrets Manager for sensitive configuration

## Cost Optimization

- **S3 Lifecycle Rules**: Automatically transition objects to cheaper storage classes
- **Lambda Provisioned Concurrency**: Only enable for predictable workloads
- **CloudWatch Logs**: Set retention periods to control costs
- **Reserved Concurrency**: Prevent runaway costs from unexpected traffic

## Troubleshooting

### Common Issues

1. **Lambda timeout errors**: Increase timeout or optimize processing logic
2. **Permission errors**: Verify IAM role policies
3. **S3 event not triggering**: Check event notification configuration
4. **Email not received**: Confirm SNS subscription and check spam folder

### Debug Commands

```bash
# Check stack events
aws cloudformation describe-stack-events --stack-name EventDrivenDataProcessingStack

# View Lambda function configuration
aws lambda get-function --function-name data-processor-${RESOURCE_SUFFIX}

# Check S3 event notifications
aws s3api get-bucket-notification-configuration --bucket data-processing-${RESOURCE_SUFFIX}
```

## Cleanup

To remove all resources:

```bash
npm run destroy
```

This will delete all AWS resources created by the stack. Note that S3 objects are automatically deleted due to the `autoDeleteObjects` setting.

## Development

### Running Tests

```bash
# Run unit tests
npm test

# Run tests in watch mode
npm run test:watch
```

### Code Quality

```bash
# Build and check for compilation errors
npm run build

# Watch for changes during development
npm run watch
```

## Support

For issues and questions:

1. Check the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
2. Review the [AWS Lambda developer guide](https://docs.aws.amazon.com/lambda/latest/dg/)
3. Consult the [S3 event notifications documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventNotifications.html)

## License

This project is licensed under the MIT License - see the LICENSE file for details.