# Amazon Comprehend NLP Pipeline - CDK TypeScript

This CDK TypeScript application deploys a complete natural language processing pipeline using Amazon Comprehend for text analysis.

## Architecture

The solution creates:

- **S3 Input Bucket**: Stores customer feedback, reviews, and support tickets for processing
- **S3 Output Bucket**: Stores structured analysis results with sentiment, entities, and key phrases
- **Lambda Function**: Processes text in real-time using Amazon Comprehend APIs
- **IAM Roles**: Secure access policies following least privilege principles
- **CloudWatch Logs**: Monitoring and debugging capabilities
- **S3 Event Notifications**: Automatic processing when new files are uploaded

## Features

- **Real-time Processing**: Immediate analysis via Lambda function invocation
- **Batch Processing**: Support for Comprehend batch jobs for large document sets
- **Multi-language Support**: Automatic language detection and analysis
- **Comprehensive Analysis**: Sentiment, entities, key phrases, and syntax analysis
- **Security**: Encrypted S3 buckets and least privilege IAM policies
- **Monitoring**: CloudWatch logs and metrics for operational visibility

## Prerequisites

- AWS CLI v2 installed and configured
- Node.js 18+ and npm
- AWS CDK v2 installed globally (`npm install -g aws-cdk`)
- Appropriate AWS permissions for resource creation

## Installation

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Build the TypeScript code**:
   ```bash
   npm run build
   ```

3. **Bootstrap CDK (first time only)**:
   ```bash
   cdk bootstrap
   ```

## Deployment

1. **Preview the changes**:
   ```bash
   cdk diff
   ```

2. **Deploy the stack**:
   ```bash
   cdk deploy
   ```

3. **Confirm deployment** when prompted.

## Usage Examples

### Real-time Text Processing

Invoke the Lambda function directly for immediate analysis:

```bash
# Get function name from stack outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name ComprehendNlpPipelineStack \
    --query 'Stacks[0].Outputs[?OutputKey==`ProcessingFunctionName`].OutputValue' \
    --output text)

# Process text directly
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{
        "text": "I love this product! The quality is amazing and customer service was helpful.",
        "output_bucket": "true"
    }' \
    --cli-binary-format raw-in-base64-out \
    response.json

# View results
cat response.json | jq '.body | fromjson'
```

### Batch Processing via S3

Upload text files to trigger automatic processing:

```bash
# Get bucket names from stack outputs
INPUT_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name ComprehendNlpPipelineStack \
    --query 'Stacks[0].Outputs[?OutputKey==`InputBucketName`].OutputValue' \
    --output text)

OUTPUT_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name ComprehendNlpPipelineStack \
    --query 'Stacks[0].Outputs[?OutputKey==`OutputBucketName`].OutputValue' \
    --output text)

# Create sample text file
echo "The customer service was terrible and I want a refund!" > review.txt

# Upload to input bucket (triggers automatic processing)
aws s3 cp review.txt s3://$INPUT_BUCKET/input/

# Check processing results
aws s3 ls s3://$OUTPUT_BUCKET/processed/ --recursive
```

### Starting Comprehend Batch Jobs

For large document collections, use Comprehend batch processing:

```python
import boto3

comprehend = boto3.client('comprehend')

# Start sentiment detection job
response = comprehend.start_sentiment_detection_job(
    InputDataConfig={
        'S3Uri': f's3://{INPUT_BUCKET}/batch-input/',
        'InputFormat': 'ONE_DOC_PER_LINE'
    },
    OutputDataConfig={
        'S3Uri': f's3://{OUTPUT_BUCKET}/batch-output/'
    },
    DataAccessRoleArn='arn:aws:iam::ACCOUNT:role/ComprehendServiceRole-SUFFIX',
    JobName='sentiment-analysis-batch',
    LanguageCode='en'
)

print(f"Job ID: {response['JobId']}")
```

## Configuration

### Environment Variables

The Lambda function uses these environment variables (automatically set by CDK):

- `INPUT_BUCKET`: S3 bucket for input text files
- `OUTPUT_BUCKET`: S3 bucket for processed results
- `COMPREHEND_ROLE_ARN`: IAM role for batch processing
- `LOG_LEVEL`: Logging level (INFO, DEBUG, etc.)

### Customization

Modify the stack parameters in `lib/comprehend-nlp-pipeline-stack.ts`:

```typescript
// Adjust Lambda function configuration
memorySize: 1024,              // Increase for larger texts
timeout: cdk.Duration.minutes(10),  // Increase for batch operations
reservedConcurrentExecutions: 50,   // Scale based on traffic

// Modify S3 lifecycle policies
lifecycleRules: [{
    expiration: cdk.Duration.days(90),  // Adjust retention period
    noncurrentVersionExpiration: cdk.Duration.days(30)
}]
```

## Monitoring

### CloudWatch Logs

View Lambda function logs:

```bash
aws logs tail /aws/lambda/comprehend-processor-SUFFIX --follow
```

### CloudWatch Metrics

Monitor key metrics:
- Lambda invocations and errors
- S3 bucket object counts
- Comprehend API calls and throttling

### Cost Monitoring

Set up billing alerts for:
- Comprehend API usage
- Lambda execution time
- S3 storage and requests

## Security Features

- **Encryption**: All S3 buckets use server-side encryption
- **Access Control**: IAM roles follow least privilege principle
- **Network Security**: Private VPC deployment option available
- **SSL Enforcement**: All S3 access requires SSL/TLS

## Development

### Local Testing

```bash
# Run type checking
npm run build

# Watch for changes
npm run watch

# Run tests (if available)
npm test
```

### Adding Features

1. **Custom Classification**: Train domain-specific models
2. **Multi-language**: Add translation before analysis
3. **Real-time Alerts**: Integrate with SNS for notifications
4. **Dashboards**: Connect to QuickSight for visualization

## Troubleshooting

### Common Issues

1. **Lambda Timeout**: Increase timeout or reduce text size
2. **IAM Permissions**: Check CloudWatch logs for access denied errors
3. **S3 Events**: Verify event notification configuration
4. **Comprehend Limits**: Monitor API throttling and quotas

### Debug Commands

```bash
# Check stack status
cdk diff

# View CloudFormation events
aws cloudformation describe-stack-events --stack-name ComprehendNlpPipelineStack

# Test Lambda function
aws lambda invoke --function-name FUNCTION_NAME --payload '{}' output.json
```

## Cleanup

Remove all resources to avoid ongoing charges:

```bash
cdk destroy
```

Confirm deletion when prompted. This will remove:
- All S3 buckets and their contents
- Lambda function and logs
- IAM roles and policies
- CloudWatch log groups

## Cost Optimization

- **Comprehend Free Tier**: 50K units (5M characters) per month for 12 months
- **Lambda Free Tier**: 1M requests and 400K GB-seconds per month
- **S3 Lifecycle**: Automatic deletion of old files reduces storage costs
- **Reserved Capacity**: Consider for high-volume production workloads

## Support

For issues with this CDK application:
1. Check CloudWatch logs for detailed error messages
2. Verify IAM permissions and service limits
3. Consult AWS Comprehend documentation
4. Review the original recipe for additional guidance

## License

This code is provided under the MIT License. See LICENSE file for details.