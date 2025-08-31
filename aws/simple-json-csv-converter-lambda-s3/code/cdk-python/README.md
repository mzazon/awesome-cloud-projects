# JSON to CSV Converter - CDK Python Application

This AWS CDK Python application creates a serverless data processing pipeline that automatically converts JSON files to CSV format when uploaded to an S3 bucket.

## Architecture

The solution creates:

- **Input S3 Bucket**: Secure bucket for uploading JSON files with encryption and versioning
- **Output S3 Bucket**: Secure bucket for storing converted CSV files
- **Lambda Function**: Python function that handles JSON to CSV conversion
- **S3 Event Trigger**: Automatic processing when JSON files are uploaded
- **CloudWatch Logs**: Monitoring and debugging capabilities
- **IAM Roles**: Least-privilege security permissions

## Features

- **Event-Driven Processing**: Automatic conversion when files are uploaded
- **Multiple JSON Formats**: Supports arrays of objects, single objects, and arrays of values
- **Security Best Practices**: Encrypted buckets, SSL enforcement, and minimal IAM permissions
- **Cost Optimization**: Serverless architecture with lifecycle policies
- **Monitoring**: CloudWatch logs for tracking processing and errors
- **CDK Nag Integration**: Security best practices validation

## Prerequisites

Before deploying this CDK application, ensure you have:

1. **AWS CLI** installed and configured with appropriate permissions
2. **Python 3.8+** installed on your system
3. **Node.js 18+** for AWS CDK CLI
4. **AWS CDK CLI** installed globally (`npm install -g aws-cdk`)
5. **AWS Account** with permissions to create IAM roles, Lambda functions, and S3 buckets

## Installation and Setup

### 1. Clone and Navigate

```bash
cd aws/simple-json-csv-converter-lambda-s3/code/cdk-python/
```

### 2. Create Virtual Environment

```bash
# Create virtual environment
python -m venv .venv

# Activate virtual environment
# On macOS/Linux:
source .venv/bin/activate
# On Windows:
.venv\Scripts\activate
```

### 3. Install Dependencies

```bash
# Install CDK dependencies
pip install -r requirements.txt

# Verify CDK installation
cdk --version
```

### 4. Bootstrap CDK (First Time Only)

```bash
# Bootstrap your AWS account for CDK (run once per account/region)
cdk bootstrap
```

## Deployment

### Quick Deploy

Deploy with default settings:

```bash
# Synthesize CloudFormation template
cdk synth

# Deploy the stack
cdk deploy
```

### Custom Configuration

Deploy with custom settings using CDK context:

```bash
# Deploy with custom stack name and environment
cdk deploy -c stack_name=MyJsonConverter -c environment=prod

# Deploy without CDK Nag security checks
cdk deploy -c enable_cdk_nag=false

# Deploy with custom Lambda settings
cdk deploy -c lambda_timeout_seconds=120 -c lambda_memory_mb=512
```

### Available Context Options

Configure the deployment using CDK context parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `stack_name` | `JsonCsvConverterStack` | Name of the CloudFormation stack |
| `environment` | `dev` | Environment tag for resources |
| `enable_cdk_nag` | `true` | Enable CDK Nag security checks |
| `lambda_timeout_seconds` | `60` | Lambda function timeout |
| `lambda_memory_mb` | `256` | Lambda function memory allocation |
| `lambda_reserved_concurrency` | `10` | Reserved concurrency for Lambda |
| `log_retention_days` | `7` | CloudWatch logs retention period |

## Usage

### Upload JSON Files

After deployment, upload JSON files to the input bucket:

```bash
# Get bucket names from stack outputs
aws cloudformation describe-stacks --stack-name JsonCsvConverterStack \
    --query 'Stacks[0].Outputs'

# Upload a JSON file
aws s3 cp sample-data.json s3://json-input-{account-id}-{region}/
```

### Download CSV Files

Check the output bucket for converted CSV files:

```bash
# List converted files
aws s3 ls s3://csv-output-{account-id}-{region}/

# Download converted file
aws s3 cp s3://csv-output-{account-id}-{region}/sample-data.csv ./
```

### Monitor Processing

View Lambda function logs:

```bash
# View recent logs
aws logs describe-log-streams \
    --log-group-name /aws/lambda/json-csv-converter-{account-id}-{region} \
    --order-by LastEventTime --descending --max-items 1

# View log events
aws logs get-log-events \
    --log-group-name /aws/lambda/json-csv-converter-{account-id}-{region} \
    --log-stream-name {log-stream-name}
```

## Supported JSON Formats

The converter handles multiple JSON structures:

### Array of Objects
```json
[
  {"id": 1, "name": "John", "email": "john@example.com"},
  {"id": 2, "name": "Jane", "email": "jane@example.com"}
]
```

### Single Object
```json
{
  "id": 1,
  "name": "John Doe",
  "email": "john@example.com",
  "department": "Engineering"
}
```

### Array of Values
```json
["value1", "value2", "value3"]
```

## Development

### Local Development

Set up the development environment:

```bash
# Install development dependencies
pip install -e ".[dev]"

# Run code formatting
black app.py

# Run linting
flake8 app.py

# Run type checking
mypy app.py
```

### Testing

Run tests (if test files are created):

```bash
# Install test dependencies
pip install -e ".[test]"

# Run tests
pytest

# Run tests with coverage
pytest --cov=app
```

### CDK Commands

Useful CDK commands for development:

```bash
# Synthesize CloudFormation template
cdk synth

# Compare deployed stack with current state
cdk diff

# View stack resources
cdk list

# Destroy the stack
cdk destroy
```

## Security Best Practices

This application implements AWS security best practices:

- **Encryption**: All S3 buckets use SSE-S3 encryption
- **Access Control**: Buckets block all public access
- **SSL Enforcement**: HTTPS required for all S3 operations
- **IAM Least Privilege**: Lambda role has minimal required permissions
- **Versioning**: S3 buckets have versioning enabled
- **Lifecycle Policies**: Automatic cleanup of old object versions
- **CDK Nag**: Automated security best practices validation

## Cost Optimization

The solution is designed for cost efficiency:

- **Serverless Architecture**: Pay only for actual processing time
- **Lifecycle Policies**: Automatic cleanup of old file versions
- **Reserved Concurrency**: Limits on Lambda execution to control costs
- **Log Retention**: Short retention period for CloudWatch logs
- **Resource Cleanup**: Auto-delete objects when stack is destroyed

## Troubleshooting

### Common Issues

1. **Permission Errors**: Ensure your AWS credentials have necessary permissions
2. **Bucket Name Conflicts**: Bucket names must be globally unique
3. **Lambda Timeout**: Increase timeout for large files via CDK context
4. **Memory Issues**: Increase Lambda memory for complex JSON files

### Debug Steps

1. Check CloudWatch logs for detailed error messages
2. Verify S3 bucket permissions and event notifications
3. Test Lambda function independently using AWS Console
4. Validate JSON file format before upload

### Getting Help

- Check AWS CDK documentation: https://docs.aws.amazon.com/cdk/
- Review AWS Lambda best practices: https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html
- AWS S3 event notifications: https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventNotifications.html

## Cleanup

To avoid ongoing costs, destroy the stack when no longer needed:

```bash
# Destroy all resources
cdk destroy

# Confirm deletion when prompted
```

This will remove all AWS resources created by the stack, including S3 buckets and their contents.

## License

This project is licensed under the Apache License 2.0. See the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

For questions or support, please open an issue in the repository.