# Simple Password Generator CDK Python Application

This directory contains the AWS CDK Python implementation for the "Simple Password Generator with Lambda and S3" recipe. The CDK application deploys a complete serverless password generation solution using AWS Lambda and Amazon S3.

## Architecture Overview

The CDK application creates:

- **AWS Lambda Function**: Generates cryptographically secure passwords using Python's `secrets` module
- **Amazon S3 Bucket**: Encrypted storage with versioning for password history
- **IAM Role**: Least privilege permissions for Lambda execution
- **CloudWatch Log Group**: Monitoring and debugging capabilities

## Security Features

- ✅ **Encryption at Rest**: S3 bucket uses AES-256 server-side encryption
- ✅ **Block Public Access**: S3 bucket blocks all public access
- ✅ **Least Privilege IAM**: IAM role with minimal required permissions
- ✅ **Secure Random Generation**: Uses Python's cryptographically secure `secrets` module
- ✅ **Versioning**: S3 versioning enabled for password history
- ✅ **Lifecycle Policies**: Automatic cost optimization with intelligent tiering

## Prerequisites

- **AWS Account**: With appropriate permissions to create Lambda, S3, and IAM resources
- **AWS CLI**: Installed and configured with your credentials
- **AWS CDK CLI**: Install with `npm install -g aws-cdk`
- **Python 3.8+**: Required for CDK v2
- **pip**: Python package manager

## Quick Start

### 1. Environment Setup

```bash
# Create virtual environment
python -m venv .venv

# Activate virtual environment
# On macOS/Linux:
source .venv/bin/activate
# On Windows:
# .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### 2. CDK Bootstrap (One-time setup)

```bash
# Bootstrap CDK in your AWS account/region (if not done before)
cdk bootstrap
```

### 3. Deploy the Stack

```bash
# Synthesize CloudFormation template (optional)
cdk synth

# Deploy the stack
cdk deploy

# Deploy with approval for security changes
cdk deploy --require-approval never
```

### 4. Test the Password Generator

After deployment, test the Lambda function:

```bash
# Get the Lambda function name from CDK outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name PasswordGeneratorStack \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Test with default parameters
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload '{"length": 16, "name": "test-password"}' \
    response.json

# View the response
cat response.json | python -m json.tool
```

### 5. Verify S3 Storage

```bash
# Get the S3 bucket name from CDK outputs
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name PasswordGeneratorStack \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
    --output text)

# List generated passwords
aws s3 ls s3://${BUCKET_NAME}/passwords/

# Download a password file (be careful with sensitive data)
aws s3 cp s3://${BUCKET_NAME}/passwords/test-password.json ./password.json
```

## CDK Commands

| Command | Description |
|---------|-------------|
| `cdk ls` | List all stacks in the app |
| `cdk synth` | Emit the synthesized CloudFormation template |
| `cdk deploy` | Deploy the stack to your AWS account |
| `cdk diff` | Compare deployed stack with current state |
| `cdk destroy` | Remove all resources (be careful!) |
| `cdk watch` | Watch for changes and redeploy automatically |

## Configuration Options

The CDK application supports customization through environment variables and context values:

### Environment Variables

```bash
# Set AWS region (default: us-east-1)
export CDK_DEFAULT_REGION=us-west-2

# Set AWS account ID (auto-detected if not set)
export CDK_DEFAULT_ACCOUNT=123456789012
```

### CDK Context

You can customize the deployment by modifying `cdk.json` or using command-line context:

```bash
# Deploy with custom stack name
cdk deploy --context stackName=MyPasswordGenerator

# Deploy with custom environment
cdk deploy --context environment=production
```

## Password Generation Parameters

The Lambda function accepts these parameters:

```json
{
  "length": 16,                    // Password length (8-128)
  "include_uppercase": true,       // Include A-Z
  "include_lowercase": true,       // Include a-z  
  "include_numbers": true,         // Include 0-9
  "include_symbols": true,         // Include special characters
  "name": "my-password"           // Custom name for the password
}
```

## Example Usage

### Generate Different Types of Passwords

```bash
# Simple alphanumeric password
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload '{"length": 12, "include_symbols": false, "name": "simple-pass"}' \
    response.json

# Complex password with all character types
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload '{"length": 24, "name": "complex-pass"}' \
    response.json

# Numbers-only PIN
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload '{"length": 8, "include_uppercase": false, "include_lowercase": false, "include_symbols": false, "name": "pin"}' \
    response.json
```

## Monitoring and Troubleshooting

### CloudWatch Logs

```bash
# View Lambda function logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/password-generator

# Tail logs in real-time
aws logs tail /aws/lambda/password-generator-passwordgeneratorstack --follow
```

### Common Issues

1. **Permission Errors**: Ensure your AWS credentials have sufficient permissions
2. **CDK Bootstrap**: Run `cdk bootstrap` if you haven't used CDK in this region before
3. **Python Version**: Ensure you're using Python 3.8 or higher
4. **Virtual Environment**: Always activate the virtual environment before running CDK commands

## Cost Considerations

This solution is designed to be cost-effective:

- **Lambda**: Pay-per-invocation, free tier includes 1M requests/month
- **S3**: Minimal storage costs, free tier includes 5GB storage
- **CloudWatch Logs**: Free tier includes 5GB ingestion/month
- **Data Transfer**: Minimal costs for intra-region transfers

### Cost Optimization Features

- S3 lifecycle policies automatically transition older passwords to cheaper storage classes
- CloudWatch log retention set to 1 week (configurable)
- Lambda function optimized for minimal memory and execution time

## Security Best Practices

This implementation follows AWS Well-Architected Framework security principles:

1. **Least Privilege**: IAM role has minimal required permissions
2. **Encryption at Rest**: S3 server-side encryption enabled
3. **Encryption in Transit**: All AWS API calls use HTTPS
4. **Access Control**: S3 bucket blocks all public access
5. **Audit Trail**: CloudWatch Logs capture all function executions
6. **Secure Random**: Uses cryptographically secure random number generation

## Cleanup

To remove all resources and avoid ongoing costs:

```bash
# Destroy the stack (will prompt for confirmation)
cdk destroy

# Force destroy without confirmation (be careful!)
cdk destroy --force
```

**⚠️ Warning**: This will permanently delete all generated passwords stored in S3!

## Development

### Project Structure

```
cdk-python/
├── app.py              # Main CDK application
├── requirements.txt    # Python dependencies
├── setup.py           # Package configuration
├── cdk.json           # CDK configuration
├── README.md          # This file
└── .venv/             # Virtual environment (created locally)
```

### Local Development

```bash
# Install development dependencies
pip install -e .[dev]

# Run tests (if implemented)
pytest

# Format code
black app.py

# Type checking
mypy app.py

# Lint code
flake8 app.py
```

## Extensions and Next Steps

Consider these enhancements for production use:

1. **API Gateway Integration**: Add HTTP endpoints for web access
2. **Authentication**: Integrate with AWS Cognito for user management
3. **Password Policies**: Add complexity validation and organizational policies
4. **Audit Logging**: Integration with AWS CloudTrail for compliance
5. **Multi-Region**: Deploy across multiple regions for high availability
6. **Monitoring**: Add CloudWatch alarms for error rates and performance
7. **Secrets Manager**: Integration for enterprise password management

## Support

For issues with this CDK implementation:

1. Check the [AWS CDK documentation](https://docs.aws.amazon.com/cdk/)
2. Review AWS CloudFormation events in the console
3. Check CloudWatch Logs for Lambda function errors
4. Refer to the original recipe documentation

## License

This code is provided under the Apache 2.0 License. See the AWS CDK project for more details.