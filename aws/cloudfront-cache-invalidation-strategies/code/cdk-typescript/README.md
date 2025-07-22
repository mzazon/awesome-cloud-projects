# CloudFront Cache Invalidation Strategies - CDK TypeScript

This AWS CDK TypeScript application implements an intelligent CloudFront cache invalidation system that automatically detects content changes, applies selective invalidation patterns, optimizes costs through batch processing, and provides comprehensive monitoring.

## Architecture Overview

The solution includes:

- **S3 Bucket**: Origin content storage with EventBridge notifications
- **CloudFront Distribution**: Global content delivery with Origin Access Control (OAC)
- **Lambda Function**: Intelligent invalidation processing with cost optimization
- **EventBridge Custom Bus**: Event-driven automation for content changes
- **SQS Queue**: Batch processing for cost-efficient invalidations
- **DynamoDB Table**: Audit logging and invalidation history
- **CloudWatch Dashboard**: Comprehensive monitoring and metrics

## Prerequisites

1. **AWS CLI**: Install and configure AWS CLI v2
2. **Node.js**: Version 18.x or later
3. **AWS CDK**: Version 2.100.0 or later
4. **TypeScript**: Version 5.2.x or later
5. **AWS Account**: With appropriate permissions for all services

### Required AWS Permissions

Your AWS credentials need permissions for:
- CloudFormation (stack operations)
- IAM (roles and policies)
- S3 (bucket operations)
- CloudFront (distribution management)
- Lambda (function operations)
- EventBridge (custom bus and rules)
- SQS (queue operations)
- DynamoDB (table operations)
- CloudWatch (dashboard and alarms)

## Installation

1. **Clone or download the code**:
   ```bash
   cd aws/cloudfront-cache-invalidation-strategies/code/cdk-typescript/
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Bootstrap CDK** (if first time using CDK in this account/region):
   ```bash
   cdk bootstrap
   ```

## Configuration

### Environment Variables

Set the following environment variables or CDK context:

```bash
# Required
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Optional configuration
export CDK_CONTEXT_PROJECT_NAME="my-invalidation-system"
export CDK_CONTEXT_ENVIRONMENT="development"
export CDK_CONTEXT_OWNER="platform-team"
```

### CDK Context Configuration

Alternatively, configure through CDK context in `cdk.json`:

```json
{
  "context": {
    "projectName": "my-invalidation-system",
    "environment": "development",
    "owner": "platform-team",
    "enableMonitoring": true,
    "enableBatchProcessing": true,
    "enableCostOptimization": true,
    "lambdaTimeout": 300,
    "lambdaMemory": 256,
    "batchSize": 10,
    "batchWindow": 30,
    "priceClass": "PriceClass_100",
    "enableCompression": true,
    "enableIPv6": true,
    "enforceHTTPS": true,
    "retentionPeriod": 30
  }
}
```

### Configuration Options

| Parameter | Default | Description |
|-----------|---------|-------------|
| `projectName` | `cf-invalidation` | Prefix for resource names |
| `environment` | `development` | Environment tag |
| `enableMonitoring` | `true` | Create CloudWatch dashboard |
| `enableBatchProcessing` | `true` | Enable SQS batch processing |
| `enableCostOptimization` | `true` | Enable intelligent path optimization |
| `lambdaTimeout` | `300` | Lambda timeout in seconds |
| `lambdaMemory` | `256` | Lambda memory in MB |
| `batchSize` | `10` | SQS batch size |
| `batchWindow` | `30` | SQS batch window in seconds |
| `priceClass` | `PriceClass_100` | CloudFront price class |
| `enableCompression` | `true` | Enable compression |
| `enableIPv6` | `true` | Enable IPv6 |
| `enforceHTTPS` | `true` | Enforce HTTPS |
| `retentionPeriod` | `30` | DynamoDB TTL in days |

## Deployment

### Deploy the Stack

```bash
# Review the changes
cdk diff

# Deploy the stack
cdk deploy

# Deploy with confirmation skip
cdk deploy --require-approval never
```

### Deploy with Custom Configuration

```bash
# Deploy with custom project name
cdk deploy --context projectName=my-cdn-system

# Deploy with custom environment
cdk deploy --context environment=production --context owner=devops-team

# Deploy with monitoring disabled
cdk deploy --context enableMonitoring=false
```

## Usage

### Test Content Upload and Invalidation

1. **Upload content to S3**:
   ```bash
   # Get bucket name from CDK output
   BUCKET_NAME=$(aws cloudformation describe-stacks \
     --stack-name CloudFrontInvalidationStack \
     --query 'Stacks[0].Outputs[?OutputKey==`OriginBucketName`].OutputValue' \
     --output text)
   
   # Upload test content
   echo '<html><body><h1>Updated Content</h1></body></html>' > test.html
   aws s3 cp test.html s3://${BUCKET_NAME}/test.html
   ```

2. **Monitor invalidation processing**:
   ```bash
   # Check Lambda function logs
   FUNCTION_NAME=$(aws cloudformation describe-stacks \
     --stack-name CloudFrontInvalidationStack \
     --query 'Stacks[0].Outputs[?OutputKey==`InvalidationFunctionName`].OutputValue' \
     --output text)
   
   aws logs filter-log-events \
     --log-group-name /aws/lambda/${FUNCTION_NAME} \
     --start-time $(date -d '10 minutes ago' '+%s')000
   ```

3. **Check invalidation history**:
   ```bash
   # Query DynamoDB table
   TABLE_NAME=$(aws cloudformation describe-stacks \
     --stack-name CloudFrontInvalidationStack \
     --query 'Stacks[0].Outputs[?OutputKey==`TableName`].OutputValue' \
     --output text)
   
   aws dynamodb scan --table-name ${TABLE_NAME} --limit 10
   ```

### Send Custom Events

```bash
# Get EventBridge bus name
EVENT_BUS=$(aws cloudformation describe-stacks \
  --stack-name CloudFrontInvalidationStack \
  --query 'Stacks[0].Outputs[?OutputKey==`EventBusName`].OutputValue' \
  --output text)

# Send custom deployment event
aws events put-events \
  --entries '[{
    "Source": "custom.app",
    "DetailType": "Application Deployment",
    "Detail": "{\"changedFiles\": [\"index.html\", \"css/style.css\"], \"version\": \"2.0.0\"}",
    "EventBusName": "'${EVENT_BUS}'"
  }]'
```

### Monitor Performance

Access the CloudWatch dashboard:
```bash
# Get dashboard URL from CDK output
aws cloudformation describe-stacks \
  --stack-name CloudFrontInvalidationStack \
  --query 'Stacks[0].Outputs[?OutputKey==`DashboardUrl`].OutputValue' \
  --output text
```

## Monitoring and Optimization

### Key Metrics to Monitor

1. **CloudFront Cache Hit Rate**: Should be above 85%
2. **Lambda Function Errors**: Should be minimal
3. **Invalidation Frequency**: Monitor cost impact
4. **Event Processing Volume**: Track system load

### Cost Optimization

- **Batch Processing**: Enabled by default to reduce invalidation costs
- **Path Optimization**: Intelligent grouping of related paths
- **TTL Configuration**: Optimize based on content change frequency
- **Monitoring**: Track invalidation costs in DynamoDB logs

### Troubleshooting

1. **Check Lambda function logs**:
   ```bash
   aws logs filter-log-events \
     --log-group-name /aws/lambda/${FUNCTION_NAME} \
     --start-time $(date -d '1 hour ago' '+%s')000
   ```

2. **Verify EventBridge rule configuration**:
   ```bash
   aws events list-rules --event-bus-name ${EVENT_BUS}
   ```

3. **Check SQS queue for stuck messages**:
   ```bash
   aws sqs get-queue-attributes \
     --queue-url ${QUEUE_URL} \
     --attribute-names All
   ```

## Development

### Build and Test

```bash
# Compile TypeScript
npm run build

# Run tests
npm test

# Watch for changes
npm run watch
```

### Code Structure

```
├── app.ts                           # CDK application entry point
├── lib/
│   └── cloudfront-invalidation-stack.ts  # Main stack definition
├── package.json                     # Dependencies and scripts
├── tsconfig.json                    # TypeScript configuration
├── cdk.json                         # CDK configuration
└── README.md                        # This file
```

### Adding Features

1. **Custom Cache Behaviors**: Modify the `additionalBehaviors` in the stack
2. **Advanced Monitoring**: Add custom metrics and alarms
3. **Multi-Region Support**: Create multiple distributions
4. **A/B Testing**: Implement version-based invalidation

## Cleanup

### Delete the Stack

```bash
# Delete the stack
cdk destroy

# Delete with confirmation skip
cdk destroy --force
```

### Manual Cleanup (if needed)

If CDK destroy fails, manually delete:
1. CloudFront distribution (disable first, then delete)
2. S3 bucket contents
3. Lambda function
4. EventBridge rules and custom bus
5. SQS queues
6. DynamoDB table
7. CloudWatch dashboards and alarms

## Security Considerations

- **Origin Access Control**: Prevents direct S3 access
- **HTTPS Enforcement**: Redirects HTTP to HTTPS
- **IAM Least Privilege**: Minimal permissions for Lambda
- **Encryption**: S3 and DynamoDB encryption enabled
- **VPC**: Consider VPC deployment for sensitive workloads

## Cost Estimation

### Development Environment
- CloudFront: $0.085 per GB + $0.0075 per 10,000 requests
- Lambda: $0.0000166667 per GB-second
- DynamoDB: Pay-per-request pricing
- S3: $0.023 per GB storage
- EventBridge: $1.00 per million events
- SQS: $0.40 per million requests

### Production Considerations
- Monitor CloudFront invalidation costs (first 1,000 paths free/month)
- Implement cost alerts
- Optimize cache TTL policies
- Use CloudFront real-time logs for analysis

## Support

For issues with this CDK application:
1. Check CloudWatch logs for Lambda function errors
2. Review CloudFormation stack events
3. Verify IAM permissions
4. Check AWS service limits
5. Review the original recipe documentation

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.