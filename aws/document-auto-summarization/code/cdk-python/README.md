# Document Summarization CDK Python Application

This AWS CDK Python application deploys a complete serverless document summarization system using Amazon Bedrock, Lambda, S3, DynamoDB, and other AWS services.

## Architecture

The application creates the following AWS resources:

- **S3 Buckets**: Input bucket for document uploads and output bucket for generated summaries
- **Lambda Function**: Processes documents, extracts text with Textract, and generates summaries with Bedrock
- **DynamoDB Table**: Stores document metadata and processing status
- **SNS Topic**: Sends notifications about processing completion
- **CloudWatch Dashboard**: Monitors system performance and usage
- **IAM Roles**: Least-privilege permissions for secure service access

## Prerequisites

Before deploying this application, ensure you have:

1. **AWS CLI v2** installed and configured
2. **Python 3.8+** installed
3. **AWS CDK v2** installed (`npm install -g aws-cdk`)
4. **AWS account** with appropriate permissions
5. **Amazon Bedrock access** enabled for Claude models
6. **Virtual environment** (recommended)

### Required AWS Permissions

Your AWS account/user needs permissions for:
- CloudFormation (full access)
- S3 (bucket creation and management)
- Lambda (function creation and management)
- IAM (role and policy creation)
- DynamoDB (table creation and management)
- SNS (topic creation and management)
- CloudWatch (dashboard creation)
- Bedrock (model access)
- Textract (document text detection)

## Installation and Deployment

### 1. Set Up Environment

```bash
# Clone or navigate to the project directory
cd aws/intelligent-document-summarization-with-bedrock-lambda/code/cdk-python

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\\Scripts\\activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Configure AWS Environment

```bash
# Configure AWS CLI (if not already done)
aws configure

# Set environment variables for CDK
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export CDK_DEFAULT_REGION=$(aws configure get region)

# Bootstrap CDK (if not already done in this region)
cdk bootstrap
```

### 3. Deploy the Stack

```bash
# Verify the deployment plan
cdk diff

# Deploy the stack
cdk deploy

# Optional: Deploy with custom stack name
cdk deploy --context stackName=MyDocumentSummarizer
```

### 4. Verify Deployment

After successful deployment, the output will show:

- Input S3 bucket name
- Output S3 bucket name
- Lambda function name
- DynamoDB table name
- SNS topic ARN
- CloudWatch dashboard URL

## Usage

### Upload Documents for Processing

1. **Using AWS CLI**:
   ```bash
   # Upload a document to trigger processing
   aws s3 cp your-document.pdf s3://[INPUT-BUCKET-NAME]/documents/
   ```

2. **Using AWS Console**:
   - Navigate to the input S3 bucket
   - Upload files to the `documents/` prefix

### Monitor Processing

1. **Check CloudWatch Logs**:
   ```bash
   # View Lambda function logs
   aws logs tail /aws/lambda/[FUNCTION-NAME] --follow
   ```

2. **View Dashboard**:
   - Open the CloudWatch dashboard URL from deployment outputs
   - Monitor Lambda invocations, errors, and duration
   - Check S3 storage metrics and DynamoDB usage

3. **Check DynamoDB**:
   ```bash
   # Query processing status
   aws dynamodb scan --table-name [METADATA-TABLE-NAME]
   ```

### Retrieve Summaries

1. **List generated summaries**:
   ```bash
   aws s3 ls s3://[OUTPUT-BUCKET-NAME]/summaries/
   ```

2. **Download a summary**:
   ```bash
   aws s3 cp s3://[OUTPUT-BUCKET-NAME]/summaries/documents/your-document.pdf.summary.txt ./
   ```

## Configuration

### Environment Variables

The application supports customization through CDK context:

```bash
# Deploy with custom configuration
cdk deploy --context stackName=ProductionSummarizer --context environment=production
```

### Bedrock Model Configuration

To use a different Bedrock model, modify the `bedrock_model_id` parameter in `app.py`:

```python
self.bedrock_model_id = "anthropic.claude-3-haiku-20240307-v1:0"  # Faster, cheaper option
```

### Lambda Configuration

Adjust Lambda settings in `app.py`:

```python
self.lambda_timeout_minutes = 10  # Increase for larger documents
self.lambda_memory_mb = 1024      # Increase for better performance
```

## Cost Optimization

- **Bedrock Usage**: Monitor token consumption as this is the primary cost driver
- **Lambda Concurrency**: Limited to 10 concurrent executions by default
- **S3 Lifecycle**: Automatic transition to cheaper storage classes after 30/90 days
- **DynamoDB**: Uses on-demand billing with 30-day TTL for automatic cleanup

## Security Features

- **Encryption**: All data encrypted at rest (S3, DynamoDB) and in transit
- **IAM**: Least-privilege permissions for all services
- **VPC**: Optional VPC deployment (modify code to add VPC configuration)
- **Access Logging**: S3 access logging enabled for audit trails

## Troubleshooting

### Common Issues

1. **Bedrock Access Denied**:
   - Ensure Bedrock model access is enabled in your AWS account
   - Check the correct model ID is specified

2. **Lambda Timeout**:
   - Increase timeout duration for large documents
   - Consider using Step Functions for complex workflows

3. **S3 Permission Errors**:
   - Verify bucket names in outputs match your uploads
   - Ensure documents are uploaded to the `documents/` prefix

4. **High Costs**:
   - Monitor Bedrock token usage in CloudWatch
   - Implement additional cost controls if needed

### Debugging

Enable debug logging:

```bash
# Deploy with debug logging
cdk deploy --context logLevel=DEBUG
```

View detailed logs:

```bash
# Filter logs by severity
aws logs filter-log-events --log-group-name /aws/lambda/[FUNCTION-NAME] --filter-pattern "ERROR"
```

## Cleanup

To avoid ongoing charges, destroy the stack when no longer needed:

```bash
# Delete all resources
cdk destroy

# Confirm deletion when prompted
```

**Note**: S3 buckets with objects will not be deleted. Empty them manually if needed:

```bash
# Empty buckets before destruction
aws s3 rm s3://[INPUT-BUCKET-NAME] --recursive
aws s3 rm s3://[OUTPUT-BUCKET-NAME] --recursive
```

## Development

### Testing Locally

```bash
# Run tests (if implemented)
pytest tests/

# Code formatting
black app.py

# Type checking
mypy app.py

# Linting
flake8 app.py
```

### Customization

The CDK application is designed to be modular and extensible:

- Add custom document types in Lambda code
- Integrate with additional AI services
- Add web interface using API Gateway + React
- Implement batch processing with SQS
- Add data lake integration with Glue/Athena

## Support

For issues with this implementation:

1. Check AWS service quotas and limits
2. Review CloudWatch logs for specific errors
3. Consult AWS documentation for service-specific guidance
4. Consider AWS Support if needed for production deployments

## License

This sample code is provided under the MIT License. See LICENSE file for details.