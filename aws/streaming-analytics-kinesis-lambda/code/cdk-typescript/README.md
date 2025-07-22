# Serverless Real-Time Analytics Pipeline CDK TypeScript

This CDK TypeScript application deploys a complete serverless real-time analytics pipeline using Amazon Kinesis Data Streams, AWS Lambda, and Amazon DynamoDB. The pipeline processes streaming data in real-time, calculates analytics metrics, and stores results for immediate querying.

## Architecture Overview

The CDK application creates:

- **Amazon Kinesis Data Streams**: Scalable data ingestion for real-time events
- **AWS Lambda Function**: Serverless processing with automatic scaling
- **Amazon DynamoDB**: NoSQL database for storing processed analytics results
- **CloudWatch Alarms**: Monitoring and alerting for operational visibility
- **IAM Roles & Policies**: Secure cross-service communication with least privilege

## Prerequisites

- Node.js 18.x or later
- AWS CLI configured with appropriate permissions
- AWS CDK CLI installed (`npm install -g aws-cdk`)
- TypeScript knowledge for customization

## Required AWS Permissions

Your AWS user/role needs permissions for:
- CloudFormation stack operations
- IAM role and policy management
- Kinesis Data Streams operations
- Lambda function management
- DynamoDB table operations
- CloudWatch alarms and metrics

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure AWS Environment

```bash
# Set your target AWS account and region (optional)
export CDK_DEFAULT_ACCOUNT=123456789012
export CDK_DEFAULT_REGION=us-east-1
```

### 3. Bootstrap CDK (First Time Only)

```bash
npm run bootstrap
```

### 4. Deploy the Stack

```bash
npm run deploy
```

### 5. Test the Pipeline

After deployment, use the output commands to send test data:

```bash
# Example test event (use the output from CDK deployment)
aws kinesis put-record \
  --stream-name real-time-analytics-stream \
  --data '{"eventType":"page_view","userId":"user_1234","timestamp":"2024-01-01T12:00:00Z","pageUrl":"/home","loadTime":1200}' \
  --partition-key user_1234
```

### 6. Verify Results

```bash
# Query DynamoDB for processed results (use table name from CDK output)
aws dynamodb scan \
  --table-name analytics-results \
  --max-items 5
```

## Architecture Components

### Kinesis Data Stream
- **Shards**: 2 (configurable)
- **Retention**: 24 hours (configurable)
- **Encryption**: AWS managed keys
- **Capacity**: 2,000 records/second, 2 MB/second

### Lambda Function
- **Runtime**: Python 3.9
- **Memory**: 512 MB (configurable)
- **Timeout**: 5 minutes (configurable)
- **Concurrency**: Limited to 100 concurrent executions
- **Features**: X-Ray tracing, dead letter queue

### DynamoDB Table
- **Primary Key**: eventId (partition), timestamp (sort)
- **Billing**: Pay-per-request
- **Features**: Point-in-time recovery, GSI for event type queries
- **TTL**: 30 days automatic cleanup

### Event Processing
- **Batch Size**: 100 records (configurable)
- **Batching Window**: 5 seconds maximum (configurable)
- **Error Handling**: Retry with bisect on error
- **Parallelization**: 2x factor for increased throughput

## Configuration Options

Customize the deployment by providing context values:

```bash
# Deploy with custom configuration
cdk deploy \
  --context kinesisShardCount=4 \
  --context lambdaMemorySize=1024 \
  --context lambdaBatchSize=50 \
  --context environment=production
```

Available configuration options:
- `kinesisShardCount`: Number of Kinesis shards (default: 2)
- `kinesisRetentionPeriod`: Data retention in hours (default: 24)
- `lambdaMemorySize`: Lambda memory in MB (default: 512)
- `lambdaTimeout`: Lambda timeout in minutes (default: 5)
- `lambdaBatchSize`: Event batch size (default: 100)
- `lambdaMaxBatchingWindow`: Max batching window in seconds (default: 5)
- `environment`: Environment name for tagging (default: dev)

## Event Types Supported

The pipeline processes these event types with specific analytics:

### Page View Events
```json
{
  "eventType": "page_view",
  "userId": "user_1234",
  "sessionId": "session_5678",
  "pageUrl": "/home",
  "loadTime": 1200,
  "deviceType": "desktop",
  "sessionLength": 300,
  "pagesViewed": 3
}
```

### Purchase Events
```json
{
  "eventType": "purchase",
  "userId": "user_1234",
  "amount": 99.99,
  "currency": "USD",
  "itemsCount": 2,
  "paymentMethod": "credit_card"
}
```

### User Signup Events
```json
{
  "eventType": "user_signup",
  "userId": "user_1234",
  "signupMethod": "email",
  "campaignSource": "google",
  "marketingConsent": true
}
```

### Click Events
```json
{
  "eventType": "click",
  "userId": "user_1234",
  "elementId": "cta-button",
  "elementType": "button",
  "pageUrl": "/product"
}
```

### Error Events
```json
{
  "eventType": "error",
  "userId": "user_1234",
  "errorType": "javascript",
  "errorMessage": "Cannot read property of undefined",
  "pageUrl": "/checkout"
}
```

## Monitoring and Alarms

The stack includes CloudWatch alarms for:

1. **Lambda Errors**: Triggers when processing errors occur
2. **Lambda Duration**: Alerts on functions approaching timeout
3. **DynamoDB Throttling**: Monitors write capacity issues
4. **Kinesis Incoming Records**: Detects when no data is flowing

### Custom Metrics

The Lambda function publishes custom metrics to CloudWatch:

- `RealTimeAnalytics/EventsProcessed`: Count by event type and device
- `RealTimeAnalytics/PurchaseAmount`: Purchase values by currency
- `RealTimeAnalytics/PageLoadTime`: Page performance metrics
- `RealTimeAnalytics/Batch/*`: Batch processing statistics

## Development

### Build and Test

```bash
# Compile TypeScript
npm run build

# Run tests
npm test

# Watch mode for development
npm run watch

# Lint and format code
npm run lint
npm run format
```

### CDK Commands

```bash
# View differences before deployment
npm run diff

# Generate CloudFormation template
npm run synth

# Deploy with approval required
cdk deploy --require-approval=broadening

# Destroy the stack
npm run destroy
```

## Cost Optimization

### Development/Testing
- Use single shard Kinesis stream
- Reduce Lambda memory to 256 MB
- Set DynamoDB to on-demand pricing
- Use short data retention periods

### Production
- Monitor and adjust shard count based on throughput
- Use reserved capacity for predictable DynamoDB workloads
- Implement data lifecycle policies
- Enable detailed monitoring for optimization insights

## Security Best Practices

The CDK application implements:

- **Least Privilege IAM**: Minimal required permissions
- **Encryption**: At-rest and in-transit encryption
- **VPC Isolation**: Consider VPC deployment for sensitive workloads
- **Resource Tagging**: Comprehensive tagging for governance
- **Access Logging**: CloudWatch logging for all components

## Troubleshooting

### Common Issues

1. **No data in DynamoDB**
   - Check Lambda function logs
   - Verify Kinesis stream is receiving data
   - Confirm event source mapping is active

2. **Lambda timeouts**
   - Increase function timeout
   - Reduce batch size
   - Check DynamoDB write capacity

3. **DynamoDB throttling**
   - Switch to on-demand billing
   - Increase provisioned capacity
   - Implement exponential backoff

### Debugging Commands

```bash
# Check Lambda logs
aws logs tail /aws/lambda/kinesis-stream-processor --follow

# Monitor Kinesis metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Kinesis \
  --metric-name IncomingRecords \
  --dimensions Name=StreamName,Value=real-time-analytics-stream \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T01:00:00Z \
  --period 300 \
  --statistics Sum

# Check DynamoDB metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedReadCapacityUnits \
  --dimensions Name=TableName,Value=analytics-results \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T01:00:00Z \
  --period 300 \
  --statistics Average
```

## Extending the Pipeline

### Add New Event Types
1. Update the Lambda function's `validate_event_data()` function
2. Add processing logic in `process_analytics_data()`
3. Update custom metrics in `send_custom_metrics()`

### Add Data Transformations
1. Implement transformation functions in the Lambda code
2. Add new derived metrics calculations
3. Update DynamoDB schema if needed

### Add Real-Time Dashboards
1. Connect Amazon QuickSight to DynamoDB
2. Use DynamoDB Streams with Lambda for real-time updates
3. Implement Kinesis Data Analytics for streaming aggregations

## Support and Resources

- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Amazon Kinesis Data Streams Guide](https://docs.aws.amazon.com/kinesis/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/)
- [Amazon DynamoDB Developer Guide](https://docs.aws.amazon.com/dynamodb/)

## License

This project is licensed under the MIT License - see the LICENSE file for details.