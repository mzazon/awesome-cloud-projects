# Intelligent Document Summarization CDK TypeScript Application

This CDK TypeScript application deploys an intelligent document summarization system using Amazon Bedrock and AWS Lambda. The solution automatically processes documents uploaded to S3, extracts text using Amazon Textract, generates intelligent summaries using Bedrock's Claude model, and stores results for easy access.

## Architecture Overview

The application creates:

- **S3 Input Bucket**: Receives uploaded documents for processing
- **S3 Output Bucket**: Stores generated summaries and metadata
- **Lambda Function**: Orchestrates document processing workflow
- **Amazon Textract Integration**: Extracts text from various document formats
- **Amazon Bedrock Integration**: Generates AI-powered summaries using Claude
- **SNS Notifications**: Alerts for processing completion and errors
- **CloudWatch Monitoring**: Comprehensive logging and metrics
- **IAM Roles**: Secure, least-privilege access controls

## Prerequisites

1. **AWS Account**: With appropriate permissions for:
   - S3, Lambda, IAM, SNS, CloudWatch
   - Amazon Textract
   - Amazon Bedrock (with Claude model access)

2. **AWS CDK**: Install the AWS CDK CLI
   ```bash
   npm install -g aws-cdk@2.100.0
   ```

3. **Node.js**: Version 18.x or later

4. **AWS CLI**: Configured with appropriate credentials
   ```bash
   aws configure
   ```

5. **Bedrock Model Access**: Ensure you have access to Claude models in your region
   ```bash
   aws bedrock list-foundation-models --region us-east-1
   ```

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Bootstrap CDK (First Time Only)

```bash
cdk bootstrap
```

### 3. Deploy the Stack

```bash
cdk deploy
```

The deployment will output important resource information including:
- Input S3 bucket name
- Output S3 bucket name
- Lambda function name
- SNS topic ARN
- CloudWatch dashboard URL

### 4. Test the System

Upload a document to test the processing:

```bash
# Get the input bucket name from the deployment output
INPUT_BUCKET="documents-input-xxxxxxxx"

# Upload a test document
aws s3 cp test-document.pdf s3://${INPUT_BUCKET}/documents/

# Check for the generated summary
OUTPUT_BUCKET="summaries-output-xxxxxxxx"
aws s3 ls s3://${OUTPUT_BUCKET}/summaries/
```

## Supported Document Formats

The system supports the following document formats via Amazon Textract:
- PDF files (*.pdf)
- PNG images (*.png)
- JPEG images (*.jpg, *.jpeg)
- TIFF images (*.tiff, *.tif)

## Configuration

### Environment Variables

The Lambda function uses these environment variables:
- `OUTPUT_BUCKET`: S3 bucket for storing summaries
- `NOTIFICATION_TOPIC_ARN`: SNS topic for notifications
- `LOG_LEVEL`: Logging verbosity (default: INFO)

### Cost Optimization

The application includes several cost optimization features:
- Reserved concurrent executions (limited to 10)
- Lifecycle policies for S3 objects
- Efficient text processing with size limits
- Dead letter queue for failed processing

### Security Features

- S3 buckets with encryption and public access blocked
- IAM roles with least-privilege permissions
- SSL enforcement for all S3 operations
- Secure Lambda environment variables

## Monitoring and Troubleshooting

### CloudWatch Dashboard

The deployment creates a CloudWatch dashboard with:
- Lambda function metrics (invocations, errors, duration)
- S3 bucket object counts
- Processing throughput

### CloudWatch Alarms

- Error rate alarm that triggers SNS notifications
- Configurable thresholds for monitoring

### Logs

Lambda function logs are available in CloudWatch:
```bash
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/doc-summarizer"
```

### Common Issues

1. **Bedrock Access**: Ensure you have access to Claude models in your region
2. **File Size Limits**: Textract has a 10MB limit for synchronous processing
3. **Timeout Issues**: Large documents may require longer processing times
4. **Cost Monitoring**: Monitor Bedrock usage to control costs

## Customization

### Modifying the Summary Prompt

Edit the `generate_summary` function in the Lambda code to customize:
- Summary length and detail level
- Specific analysis requirements
- Output format preferences

### Adding New Document Formats

Extend the `_is_supported_format` function to handle additional file types supported by Textract.

### Scaling Configuration

Adjust these parameters based on your needs:
- Lambda memory allocation (default: 1024MB)
- Reserved concurrent executions (default: 10)
- S3 lifecycle policies
- CloudWatch log retention

## Development Commands

```bash
# Install dependencies
npm install

# Build TypeScript
npm run build

# Watch for changes
npm run watch

# Run tests
npm test

# Deploy stack
cdk deploy

# View changes before deployment
cdk diff

# Synthesize CloudFormation template
cdk synth

# Destroy stack
cdk destroy
```

## Cleanup

To remove all resources created by this stack:

```bash
cdk destroy
```

**Note**: This will delete all data in the S3 buckets. Ensure you've backed up any important summaries before destroying the stack.

## Cost Estimation

Approximate monthly costs for moderate usage (100 documents/month):
- **S3 Storage**: $1-5 (depending on document sizes)
- **Lambda**: $2-10 (based on execution time and memory)
- **Textract**: $10-20 (based on page count)
- **Bedrock**: $20-50 (based on token usage)
- **Other Services**: $1-2 (SNS, CloudWatch)

**Total Estimated Cost**: $34-87/month

Monitor actual usage through AWS Cost Explorer and set up billing alerts.

## Security Considerations

1. **IAM Permissions**: The stack follows least-privilege principles
2. **Data Encryption**: All data is encrypted at rest and in transit
3. **Network Security**: Resources are properly isolated
4. **Access Logging**: S3 access can be logged for audit purposes

## Support and Contributing

For issues related to this CDK application:
1. Check CloudWatch logs for error details
2. Verify AWS service limits and quotas
3. Ensure proper IAM permissions
4. Review the original recipe documentation

## License

This code is provided under the MIT License. See the original recipe documentation for full terms and conditions.