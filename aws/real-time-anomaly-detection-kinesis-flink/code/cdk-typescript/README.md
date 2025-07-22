# Real-time Anomaly Detection CDK TypeScript Application

This CDK TypeScript application deploys a complete real-time anomaly detection system using AWS Managed Service for Apache Flink (formerly Kinesis Data Analytics), Kinesis Data Streams, CloudWatch, SNS, and Lambda.

## Architecture Overview

The application creates the following AWS resources:

- **Kinesis Data Stream**: Ingests real-time transaction data
- **Managed Service for Apache Flink Application**: Processes streaming data and detects anomalies
- **S3 Bucket**: Stores Flink application artifacts and processed data
- **Lambda Functions**: 
  - Anomaly processor for alert handling
  - Data generator for testing
- **SNS Topic**: Sends anomaly alerts via email
- **CloudWatch**: Monitors metrics and triggers alarms
- **IAM Roles**: Secure access between services

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ installed
- AWS CDK v2 installed globally: `npm install -g aws-cdk`
- Appropriate AWS permissions for creating the required resources
- Email address for receiving anomaly alerts

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (if not done previously)

```bash
cdk bootstrap
```

### 3. Configure Context (Optional)

You can customize the deployment by setting context values in `cdk.json` or passing them via command line:

```bash
# Set notification email
cdk deploy -c notificationEmail=your-email@example.com

# Set custom shard count and parallelism
cdk deploy -c streamShardCount=4 -c flinkParallelism=4

# Set environment and stack name
cdk deploy -c environment=prod -c stackName=prod-anomaly-detection
```

### 4. Deploy the Stack

```bash
# Deploy with default settings
npm run deploy

# Or deploy with custom email notification
cdk deploy -c notificationEmail=your-email@example.com
```

### 5. Confirm Email Subscription

After deployment, check your email and confirm the SNS subscription to receive anomaly alerts.

## Testing the System

### Generate Test Data

Use the deployed data generator Lambda function to create test transaction data:

```bash
# Get the function name from stack outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
  --stack-name AnomalyDetectionStack \
  --query 'Stacks[0].Outputs[?OutputKey==`DataGeneratorName`].OutputValue' \
  --output text)

# Generate 100 test transactions
aws lambda invoke \
  --function-name $FUNCTION_NAME \
  --payload '{"records_count": 100}' \
  response.json

cat response.json
```

### Monitor Anomalies

1. **CloudWatch Metrics**: Check the `AnomalyDetection/AnomalyCount` metric in CloudWatch
2. **CloudWatch Logs**: Monitor Flink application logs for anomaly detection events
3. **Email Alerts**: Receive notifications when anomalies are detected
4. **SNS Topic**: Check SNS topic for published messages

### Manual Data Ingestion

You can also send data directly to the Kinesis stream:

```bash
# Get stream name from stack outputs
STREAM_NAME=$(aws cloudformation describe-stacks \
  --stack-name AnomalyDetectionStack \
  --query 'Stacks[0].Outputs[?OutputKey==`KinesisStreamName`].OutputValue' \
  --output text)

# Send a test transaction
aws kinesis put-record \
  --stream-name $STREAM_NAME \
  --data '{"userId":"user001","amount":25000.00,"timestamp":1672531200000,"transactionId":"txn_999999","merchantId":"merchant_1"}' \
  --partition-key user001
```

## Managing the Flink Application

### Start the Flink Application

```bash
# Get application name from stack outputs
APP_NAME=$(aws cloudformation describe-stacks \
  --stack-name AnomalyDetectionStack \
  --query 'Stacks[0].Outputs[?OutputKey==`FlinkApplicationName`].OutputValue' \
  --output text)

# Start the application
aws kinesisanalyticsv2 start-application \
  --application-name $APP_NAME \
  --run-configuration '{"FlinkRunConfiguration": {"AllowNonRestoredState": true}}'
```

### Stop the Flink Application

```bash
aws kinesisanalyticsv2 stop-application \
  --application-name $APP_NAME
```

### Check Application Status

```bash
aws kinesisanalyticsv2 describe-application \
  --application-name $APP_NAME \
  --query 'ApplicationDetail.ApplicationStatus'
```

## Customization

### Anomaly Detection Logic

The current implementation uses a simple threshold-based anomaly detection. To customize:

1. Build a custom Flink application JAR with your detection logic
2. Upload the JAR to the S3 artifacts bucket
3. Update the `s3ContentLocation` in the stack to point to your JAR

### Alert Recipients

Add additional email subscribers:

```typescript
// In lib/anomaly-detection-stack.ts
this.alertTopic.addSubscription(
  new snsSubscriptions.EmailSubscription('additional-email@example.com')
);
```

### Stream Configuration

Modify stream settings by updating the context values:

```json
{
  "streamShardCount": 4,        // Number of Kinesis shards
  "flinkParallelism": 4,        // Flink application parallelism
  "notificationEmail": "your-email@example.com"
}
```

## Cost Optimization

- **Kinesis Data Streams**: Charges per shard hour (~$0.015/hour per shard)
- **Managed Service for Apache Flink**: Charges per KPU hour (~$0.11/hour per KPU)
- **Lambda**: Pay per request and execution time
- **CloudWatch**: Standard metrics and alarm pricing
- **SNS**: Pay per message published and delivered

Estimated monthly cost for moderate usage (2 shards, 2 KPUs): $50-100

## Security Best Practices

The stack implements several security best practices:

- **IAM Least Privilege**: Each service has minimal required permissions
- **Encryption**: S3 bucket and Kinesis stream use encryption at rest
- **VPC**: Consider deploying in a private VPC for additional security
- **Secrets**: Use AWS Secrets Manager for sensitive configuration

## Monitoring and Debugging

### CloudWatch Logs

- Flink application logs: `/aws/kinesis-analytics/[ApplicationName]`
- Lambda function logs: `/aws/lambda/[FunctionName]`

### Key Metrics to Monitor

- `AnomalyDetection/AnomalyCount`: Number of detected anomalies
- `AWS/Kinesis/IncomingRecords`: Data ingestion rate
- `AWS/KinesisAnalytics/Records`: Flink processing rate
- `AWS/Lambda/Duration`: Lambda execution time

### Troubleshooting

1. **Flink Application Not Starting**:
   - Check IAM permissions for the service role
   - Verify S3 bucket permissions and JAR file location
   - Review CloudWatch logs for error messages

2. **No Anomalies Detected**:
   - Verify data is flowing to Kinesis stream
   - Check Flink application logic and thresholds
   - Review application logs for processing errors

3. **Missing Email Notifications**:
   - Confirm SNS email subscription
   - Check SNS topic permissions
   - Verify Lambda function environment variables

## Development

### Build and Test

```bash
# Compile TypeScript
npm run build

# Run tests (when available)
npm test

# Lint code
npm run lint
npm run lint:fix
```

### CDK Commands

```bash
# Show differences
npm run diff

# Synthesize CloudFormation
npm run synth

# Deploy stack
npm run deploy

# Destroy stack
npm run destroy
```

## Cleanup

To avoid ongoing charges, destroy the stack when no longer needed:

```bash
npm run destroy
```

This will remove all created resources except:
- CloudWatch logs (retained for debugging)
- S3 bucket contents (if versioning enabled)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License.

## Support

For issues with this CDK application:
1. Check the troubleshooting section above
2. Review AWS documentation for the services used
3. Open an issue in the repository

For AWS service-specific issues, refer to AWS Support or documentation.