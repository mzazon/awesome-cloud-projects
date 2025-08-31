# Markdown to HTML Converter - CDK Python

This directory contains an AWS CDK Python implementation for the Simple Markdown to HTML Converter recipe.

## Overview

This CDK application creates a serverless document converter using AWS Lambda and S3 that automatically transforms uploaded Markdown files into formatted HTML. The solution is event-driven, cost-effective, and requires no server management.

## Architecture

The CDK application provisions:

- **Input S3 Bucket**: Receives uploaded Markdown files with encryption and versioning
- **Output S3 Bucket**: Stores converted HTML files with matching security configuration  
- **Lambda Function**: Processes Markdown files and converts them to HTML using Python
- **IAM Role**: Provides least-privilege access for Lambda to read/write S3 objects
- **S3 Event Trigger**: Automatically invokes Lambda when `.md` files are uploaded

## Prerequisites

- Python 3.8 or later
- AWS CLI configured with appropriate permissions
- AWS CDK v2 installed (`npm install -g aws-cdk`)
- Docker (for Lambda function bundling, if needed)

### Required AWS Permissions

Your AWS credentials need permissions for:
- S3 bucket creation and management
- Lambda function creation and configuration
- IAM role and policy creation
- CloudFormation stack operations

## Quick Start

### 1. Install Dependencies

```bash
# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install CDK dependencies
pip install -r requirements.txt
```

### 2. Bootstrap CDK (if first time)

```bash
cdk bootstrap
```

### 3. Deploy the Stack

```bash
# Review the resources that will be created
cdk diff

# Deploy the stack
cdk deploy
```

### 4. Test the Converter

After deployment, the output will show the S3 bucket names:

```bash
# Upload a sample Markdown file
echo "# Hello World\nThis is **bold** text." > sample.md
aws s3 cp sample.md s3://markdown-input-{account}-{region}/

# Check for converted HTML file
aws s3 ls s3://markdown-output-{account}-{region}/
aws s3 cp s3://markdown-output-{account}-{region}/sample.html ./
```

## Configuration

### Environment Variables

The Lambda function uses these environment variables:
- `OUTPUT_BUCKET_NAME`: Set automatically by CDK to the output bucket name

### Customization

You can customize the deployment by modifying `app.py`:

- **Memory and Timeout**: Adjust Lambda function memory (256MB) and timeout (60s)
- **Bucket Names**: Modify bucket naming patterns
- **Lambda Code**: Replace inline code with external file or layer
- **Tags**: Update resource tags for cost allocation and organization

### Advanced Configuration

For production deployments, consider:

```python
# In app.py, modify the Lambda function:
self.markdown_converter_function = lambda_.Function(
    # ... other parameters
    memory_size=512,  # Increase for larger files
    timeout=Duration.minutes(5),  # Increase for complex processing
    reserved_concurrent_executions=10,  # Limit concurrency
)
```

## Monitoring and Troubleshooting

### CloudWatch Logs

Lambda function logs are available in CloudWatch:

```bash
# View recent logs
aws logs tail /aws/lambda/markdown-to-html-converter --follow
```

### Common Issues

1. **Permission Errors**: Ensure the CDK execution role has necessary permissions
2. **Bucket Name Conflicts**: S3 bucket names must be globally unique
3. **Large File Processing**: Increase Lambda memory/timeout for large Markdown files
4. **Conversion Errors**: Check CloudWatch logs for detailed error messages

## Cost Optimization

This solution is designed for cost efficiency:

- **Lambda**: Pay only for execution time (typically $0.000000167 per 100ms)
- **S3**: Standard storage pricing with intelligent tiering available
- **No idle costs**: Resources scale to zero when not in use

Estimated monthly cost for 1000 conversions: < $1.00

## Security Features

- **Encryption**: All S3 buckets use server-side encryption (SSE-S3)
- **Versioning**: Enabled on both input and output buckets for data protection
- **Block Public Access**: All buckets block public access by default
- **Least Privilege**: IAM role has minimal required permissions
- **VPC**: Can be deployed in VPC for additional network isolation (optional)

## Development

### Local Testing

```bash
# Install development dependencies
pip install -r requirements.txt[dev]

# Run tests
pytest tests/

# Type checking
mypy app.py

# Code formatting
black app.py
flake8 app.py
```

### CDK Commands

```bash
# List all stacks
cdk list

# Compare deployed stack with current state
cdk diff

# Synthesize CloudFormation template
cdk synth

# Deploy specific stack
cdk deploy MarkdownHtmlConverterStack

# View stack outputs
aws cloudformation describe-stacks --stack-name MarkdownHtmlConverterStack
```

## Cleanup

To remove all resources and avoid ongoing charges:

```bash
# Delete the CDK stack
cdk destroy

# Confirm deletion when prompted
```

This will remove:
- Lambda function
- S3 buckets and all contents
- IAM roles and policies
- CloudWatch log groups

## Extension Ideas

1. **Multiple Output Formats**: Add PDF generation using WeasyPrint
2. **Batch Processing**: Handle ZIP files with multiple Markdown documents
3. **Custom Templates**: Support for custom HTML templates and CSS themes
4. **Web Interface**: Add S3 static website with upload functionality
5. **Notification System**: Add SNS notifications for conversion completion

## Support

For issues with this CDK implementation:
1. Check the original recipe documentation
2. Review CloudWatch logs for error details
3. Consult AWS CDK documentation
4. Verify AWS service limits and quotas

## License

This code is provided as-is for educational and demonstration purposes.