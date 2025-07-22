# Intelligent Document Processing with Amazon Textract - CDK Python

This directory contains the AWS CDK Python implementation for the "Automated Document Extraction with Textract" recipe. The application creates a complete serverless document processing pipeline using Amazon Textract, S3, and Lambda.

## Architecture Overview

The CDK application deploys the following infrastructure:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Documents     │    │   S3 Bucket     │    │ Lambda Function │
│   (PDF, Images) │───▶│   (Storage)     │───▶│  (Processing)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
                       ┌─────────────────┐    ┌─────────────────┐
                       │   S3 Results    │    │ Amazon Textract │
                       │   (JSON)        │◀───│  (ML Service)   │
                       └─────────────────┘    └─────────────────┘
```

## Components

### 1. S3 Bucket (`DocumentBucket`)
- **Purpose**: Stores uploaded documents and processing results
- **Features**:
  - Versioning enabled for document history
  - Server-side encryption (SSE-S3)
  - Lifecycle policies for cost optimization
  - Public access blocked for security
  - Event notifications for automatic processing

### 2. Lambda Function (`TextractProcessor`)
- **Purpose**: Orchestrates document processing with Amazon Textract
- **Runtime**: Python 3.9
- **Memory**: 256 MB
- **Timeout**: 60 seconds
- **Triggers**: S3 ObjectCreated events (documents/ prefix)
- **Functionality**:
  - Extracts text from documents using Textract
  - Calculates confidence scores and statistics
  - Saves structured results to S3 in JSON format
  - Comprehensive error handling and logging

### 3. IAM Role (`TextractProcessorRole`)
- **Purpose**: Provides least-privilege access for Lambda function
- **Permissions**:
  - Basic Lambda execution (CloudWatch Logs)
  - S3 read/write access to document bucket
  - Amazon Textract API access (DetectDocumentText, AnalyzeDocument)

### 4. CloudWatch Log Group (`ProcessingLogs`)
- **Purpose**: Centralized logging for monitoring and debugging
- **Retention**: 14 days (configurable)
- **Features**: Structured logging with different log levels

## Prerequisites

1. **AWS Account**: Active AWS account with appropriate permissions
2. **AWS CLI**: Version 2.x installed and configured
3. **Python**: Version 3.8 or higher
4. **Node.js**: Version 18.x or higher (for CDK CLI)
5. **CDK CLI**: Latest version installed globally

```bash
# Install CDK CLI
npm install -g aws-cdk

# Verify installation
cdk --version
```

## Quick Start

### 1. Environment Setup

```bash
# Clone or navigate to the project directory
cd /path/to/intelligent-document-processing-amazon-textract/code/cdk-python

# Create virtual environment
python -m venv .venv

# Activate virtual environment
# On macOS/Linux:
source .venv/bin/activate
# On Windows:
.venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Bootstrap CDK (First-time only)

```bash
# Bootstrap CDK in your AWS account/region
cdk bootstrap

# Verify bootstrap
cdk ls
```

### 3. Deploy the Stack

```bash
# Review the changes (optional)
cdk diff

# Deploy the infrastructure
cdk deploy

# Deploy with auto-approval (for CI/CD)
cdk deploy --require-approval never
```

### 4. Test the Deployment

```bash
# Get the bucket name from stack outputs
export BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name TextractDocumentProcessingStack \
    --query 'Stacks[0].Outputs[?OutputKey==`DocumentBucketName`].OutputValue' \
    --output text)

# Upload a test document
echo "This is a test document for processing." > test-document.txt
aws s3 cp test-document.txt s3://${BUCKET_NAME}/documents/

# Check processing results (after a few seconds)
aws s3 ls s3://${BUCKET_NAME}/results/

# Download and view results
aws s3 cp s3://${BUCKET_NAME}/results/test-document.txt_results.json ./
cat test-document.txt_results.json
```

## Configuration

### Environment Variables

The Lambda function uses the following environment variables:

- `BUCKET_NAME`: S3 bucket name for document storage
- `LOG_LEVEL`: Logging level (DEBUG, INFO, WARNING, ERROR)

### Customization Options

You can customize the deployment by modifying the following parameters in `app.py`:

```python
# Lambda function configuration
timeout=Duration.seconds(60),        # Processing timeout
memory_size=256,                     # Memory allocation
runtime=lambda_.Runtime.PYTHON_3_9,  # Python runtime version

# S3 bucket configuration
versioned=True,                      # Enable versioning
encryption=s3.BucketEncryption.S3_MANAGED,  # Encryption type

# Log retention
retention=logs.RetentionDays.TWO_WEEKS,  # CloudWatch log retention
```

## Supported Document Formats

Amazon Textract supports the following document formats:

- **Images**: JPEG, PNG, TIFF, PDF
- **Maximum file size**: 10 MB (synchronous), 500 MB (asynchronous)
- **Maximum pages**: 3000 pages per document
- **Languages**: English, Spanish, German, Italian, French, Portuguese

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor Lambda function execution:

```bash
# View recent logs
aws logs tail /aws/lambda/textract-processor-* --follow

# View logs for specific time range
aws logs filter-log-events \
    --log-group-name /aws/lambda/textract-processor-* \
    --start-time $(date -d '1 hour ago' +%s)000
```

### CloudWatch Metrics

Key metrics to monitor:

- **Lambda Duration**: Processing time per document
- **Lambda Errors**: Failed processing attempts
- **Lambda Invocations**: Total processing requests
- **S3 Requests**: Bucket access patterns

### Common Issues

1. **Lambda Timeout**: Increase timeout for large documents
2. **Memory Issues**: Increase memory allocation for complex documents
3. **Permission Errors**: Verify IAM role permissions
4. **Textract Limits**: Check service quotas and rate limits

## Cost Optimization

### Pricing Components

- **Amazon Textract**: $0.0015 per page (DetectDocumentText)
- **AWS Lambda**: $0.0000166667 per GB-second
- **Amazon S3**: $0.023 per GB (Standard storage)
- **CloudWatch Logs**: $0.50 per GB ingested

### Cost Optimization Tips

1. **Use S3 Lifecycle Policies**: Automatically transition to cheaper storage classes
2. **Optimize Lambda Memory**: Right-size memory allocation
3. **Batch Processing**: Process multiple documents in single invocation
4. **Use Intelligent Tiering**: Let S3 automatically optimize storage costs

## Security Best Practices

### Implemented Security Features

1. **IAM Least Privilege**: Minimal permissions for Lambda function
2. **S3 Encryption**: Server-side encryption enabled
3. **VPC Isolation**: Optional VPC deployment (modify stack for VPC)
4. **Access Logging**: CloudWatch Logs for audit trails
5. **Public Access Block**: S3 bucket blocks all public access

### Additional Security Recommendations

1. **KMS Encryption**: Use customer-managed KMS keys
2. **VPC Endpoints**: Use VPC endpoints for AWS services
3. **Resource Tags**: Tag all resources for governance
4. **Monitoring**: Set up CloudWatch alarms for anomalies

## Advanced Features

### Asynchronous Processing

For large documents, consider using Textract's asynchronous APIs:

```python
# Modify Lambda function to use async processing
response = textract_client.start_document_text_detection(
    DocumentLocation={
        'S3Object': {
            'Bucket': bucket_name,
            'Name': object_key
        }
    },
    NotificationChannel={
        'SNSTopic': sns_topic_arn,
        'RoleArn': textract_role_arn
    }
)
```

### Form and Table Extraction

Enhance the function to extract forms and tables:

```python
# Use AnalyzeDocument for structured data
response = textract_client.analyze_document(
    Document={
        'S3Object': {
            'Bucket': bucket_name,
            'Name': object_key
        }
    },
    FeatureTypes=['TABLES', 'FORMS']
)
```

### Multi-Page Processing

Handle multi-page documents efficiently:

```python
# Process pages in batches
for page_num in range(1, total_pages + 1):
    # Process individual pages
    pass
```

## Cleanup

### Remove All Resources

```bash
# Destroy the stack
cdk destroy

# Confirm deletion
# Type 'y' when prompted

# Verify cleanup
aws cloudformation list-stacks \
    --stack-status-filter DELETE_COMPLETE \
    --query 'StackSummaries[?StackName==`TextractDocumentProcessingStack`]'
```

### Manual Cleanup (if needed)

If automatic cleanup fails:

```bash
# List remaining resources
aws cloudformation describe-stack-resources \
    --stack-name TextractDocumentProcessingStack

# Manually delete S3 bucket contents
aws s3 rm s3://${BUCKET_NAME} --recursive

# Delete the bucket
aws s3 rb s3://${BUCKET_NAME}
```

## Development

### Local Development

```bash
# Install development dependencies
pip install -r requirements.txt[dev]

# Run tests
pytest tests/

# Code formatting
black app.py

# Type checking
mypy app.py

# Linting
flake8 app.py
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the test suite
6. Submit a pull request

## Support

For issues and questions:

1. **AWS Documentation**: [Amazon Textract Documentation](https://docs.aws.amazon.com/textract/)
2. **CDK Documentation**: [AWS CDK Python Documentation](https://docs.aws.amazon.com/cdk/api/v2/python/)
3. **AWS Support**: Create a support case in the AWS Console
4. **Community**: AWS Developer Forums and Stack Overflow

## License

This project is licensed under the MIT License. See the LICENSE file for details.