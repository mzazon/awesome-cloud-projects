# CDK Python - Basic Secret Management with Secrets Manager and Lambda

This directory contains the AWS CDK Python implementation for the "Basic Secret Management with Secrets Manager and Lambda" recipe. This CDK application creates a complete solution for secure secret management using AWS Secrets Manager and AWS Lambda with the AWS Parameters and Secrets Extension.

## Architecture Overview

The CDK application deploys:

- **AWS Secrets Manager Secret**: Stores sample database credentials in encrypted JSON format
- **AWS Lambda Function**: Retrieves secrets using the AWS Parameters and Secrets Extension for optimized performance
- **IAM Role**: Implements least privilege permissions for secret access
- **CloudWatch Log Group**: Provides monitoring and troubleshooting capabilities

## Prerequisites

1. **AWS Account**: Active AWS account with appropriate permissions
2. **AWS CLI**: Installed and configured with your credentials
3. **Python**: Python 3.8 or later installed
4. **AWS CDK**: CDK CLI installed globally
5. **Node.js**: Required for CDK CLI (version 14.x or later)

### Installation Commands

```bash
# Install Node.js (if not already installed)
# Visit https://nodejs.org/ for installation instructions

# Install AWS CDK CLI globally
npm install -g aws-cdk

# Verify CDK installation
cdk --version

# Install Python dependencies
pip install -r requirements.txt
```

## Quick Start

### 1. Bootstrap CDK (First Time Only)

If this is your first time using CDK in your AWS account/region:

```bash
# Bootstrap CDK in your AWS account/region
cdk bootstrap
```

### 2. Deploy the Stack

```bash
# Synthesize CloudFormation template (optional - for validation)
cdk synth

# Deploy the stack
cdk deploy

# Deploy with automatic approval (skip confirmation prompts)
cdk deploy --require-approval never
```

### 3. Test the Deployment

After successful deployment, the outputs will display the resource names. Test the Lambda function:

```bash
# Get the Lambda function name from CDK outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name BasicSecretManagementStack \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Invoke the Lambda function
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload '{}' \
    response.json

# View the response
cat response.json
```

Expected response format:
```json
{
  "statusCode": 200, 
  "body": "{\"message\": \"Secret retrieved successfully\", \"database_host\": \"mydb.cluster-xyz.us-east-1.rds.amazonaws.com\", \"database_name\": \"production\", \"username\": \"appuser\", \"extension_cache\": \"Enabled with 300s TTL\", \"note\": \"Password retrieved but not displayed for security\"}"
}
```

### 4. Monitor the Application

```bash
# View CloudWatch logs
LOG_GROUP_NAME=$(aws cloudformation describe-stacks \
    --stack-name BasicSecretManagementStack \
    --query 'Stacks[0].Outputs[?OutputKey==`LogGroupName`].OutputValue' \
    --output text)

# Get recent log events
aws logs describe-log-streams \
    --log-group-name ${LOG_GROUP_NAME} \
    --order-by LastEventTime \
    --descending \
    --max-items 1 \
    --query 'logStreams[0].logStreamName' \
    --output text
```

## Customization

### Environment-Specific Deployments

Deploy to different environments using CDK context:

```bash
# Deploy with custom suffix for resource names
cdk deploy -c unique_suffix=dev

# Deploy to specific environment
cdk deploy -c unique_suffix=prod --profile production
```

### Modify Secret Content

Edit the `secret_value` dictionary in `app.py` to customize the secret content:

```python
secret_value = {
    "database_host": "your-database-host.amazonaws.com",
    "database_port": "5432", 
    "database_name": "your-database",
    "username": "your-username",
    "password": "your-secure-password"
}
```

### Update Lambda Extension Version

Check for the latest AWS Parameters and Secrets Extension layer version:

```python
# Update this line in app.py with the latest version
extension_layer_arn = f"arn:aws:lambda:{self.region}:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:18"
```

Visit the [AWS Lambda Extensions documentation](https://docs.aws.amazon.com/secretsmanager/latest/userguide/retrieving-secrets_lambda.html) for the latest version numbers.

## Development

### Project Structure

```
cdk-python/
├── app.py              # Main CDK application
├── requirements.txt    # Python dependencies
├── setup.py           # Package configuration
├── cdk.json           # CDK configuration
└── README.md          # This file
```

### Code Quality

The CDK application follows Python and CDK best practices:

- **Type Hints**: Full type annotations for better IDE support
- **Documentation**: Comprehensive docstrings and comments
- **Security**: Implements least privilege IAM permissions
- **Resource Management**: Proper tagging and removal policies
- **Error Handling**: Robust error handling in Lambda function

### Testing (Optional)

Add unit tests for the CDK application:

```bash
# Install testing dependencies
pip install pytest pytest-cov boto3 moto

# Run tests (create test files first)
pytest tests/

# Run tests with coverage
pytest --cov=app tests/
```

## Configuration

### CDK Context Values

The application supports these context values in `cdk.json`:

- `unique_suffix`: Suffix for resource names (default: "demo")
- Environment-specific configurations can be added as needed

### Lambda Function Configuration

Environment variables configured for the Lambda function:

- `SECRET_NAME`: Name of the Secrets Manager secret
- `PARAMETERS_SECRETS_EXTENSION_CACHE_ENABLED`: Enable extension caching
- `PARAMETERS_SECRETS_EXTENSION_CACHE_SIZE`: Cache size (1000 entries)
- `PARAMETERS_SECRETS_EXTENSION_MAX_CONNECTIONS`: Max connections (3)
- `PARAMETERS_SECRETS_EXTENSION_HTTP_PORT`: Extension HTTP port (2773)

## Security Considerations

### IAM Permissions

The Lambda function's IAM role includes:

- **Basic Lambda Execution**: CloudWatch Logs access via `AWSLambdaBasicExecutionRole`
- **Secrets Manager Access**: Read-only access to the specific secret only (least privilege)

### Secret Security

- **Encryption**: Secrets are encrypted at rest using AWS KMS
- **Access Control**: IAM-based access control with least privilege
- **Audit Trail**: CloudTrail logging for secret access events
- **Caching**: Local caching with configurable TTL for performance

### Best Practices Implemented

- ✅ Least privilege IAM permissions
- ✅ Resource-specific secret access (not wildcard)
- ✅ Encrypted storage with AWS KMS
- ✅ Proper resource tagging for management
- ✅ CloudWatch logging for monitoring
- ✅ Resource cleanup via removal policies

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Error**:
   ```bash
   # Ensure CDK is bootstrapped in your account/region
   cdk bootstrap
   ```

2. **IAM Permission Denied**:
   ```bash
   # Ensure your AWS credentials have sufficient permissions
   aws sts get-caller-identity
   ```

3. **Lambda Function Timeout**:
   - The function is configured with 30-second timeout
   - Cold starts with the extension may take additional time

4. **Secret Not Found**:
   - Verify the secret name in the Lambda environment variables
   - Check CloudWatch logs for detailed error messages

### Debugging

```bash
# View CDK context and configuration
cdk context

# Show differences between deployed and local version
cdk diff

# View synthesized CloudFormation template
cdk synth > template.yaml

# Enable CDK debug logging
cdk deploy --debug
```

## Cleanup

### Remove All Resources

```bash
# Delete the CDK stack and all resources
cdk destroy

# Confirm deletion when prompted
# Type 'y' to confirm
```

### Verify Cleanup

```bash
# Verify stack deletion
aws cloudformation describe-stacks --stack-name BasicSecretManagementStack
# Should return error: Stack does not exist

# Verify secret deletion (should be in pending deletion state)
aws secretsmanager describe-secret --secret-id my-app-secrets-demo
```

## Cost Considerations

### Expected Costs

- **Secrets Manager**: ~$0.40/month per secret
- **Lambda**: Free tier covers most usage; ~$0.0000002 per request after
- **CloudWatch Logs**: ~$0.50/GB stored
- **KMS**: Default encryption at no additional cost

### Cost Optimization

- Extension caching reduces Secrets Manager API calls
- Short log retention period (7 days) minimizes storage costs
- Removal policies allow proper cleanup to avoid ongoing charges

## Additional Resources

- [AWS Secrets Manager User Guide](https://docs.aws.amazon.com/secretsmanager/latest/userguide/)
- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [AWS Parameters and Secrets Lambda Extension](https://docs.aws.amazon.com/secretsmanager/latest/userguide/retrieving-secrets_lambda.html)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/)
- [CDK Workshop](https://cdkworkshop.com/)

## Support

For issues with this CDK application:

1. Check the [troubleshooting section](#troubleshooting) above
2. Review CloudWatch logs for the Lambda function
3. Refer to the original recipe documentation
4. Consult AWS CDK and Secrets Manager documentation

## License

This CDK application is provided under the Apache License 2.0. See the LICENSE file for details.