# CDK Python Implementation - Enterprise API Integration with AgentCore Gateway

This directory contains the AWS Cloud Development Kit (CDK) Python implementation for the Enterprise API Integration with AgentCore Gateway and Step Functions solution.

## Architecture Overview

This CDK application deploys a comprehensive serverless API integration system that includes:

- **Amazon API Gateway**: REST API endpoint for external access
- **AWS Lambda Functions**: Data transformation and validation services
- **AWS Step Functions**: Orchestration workflow for complex API integration
- **IAM Roles**: Least privilege security configuration
- **CloudWatch Logs**: Monitoring and observability

## Prerequisites

### System Requirements

- Python 3.8 or later
- AWS CLI v2 installed and configured
- AWS CDK v2.150.0 or later
- Node.js 18.x or later (required for CDK)

### AWS Requirements

- AWS account with appropriate permissions
- CDK bootstrapped in target region
- Required service limits for Lambda, API Gateway, and Step Functions

### Permission Requirements

The deploying user/role needs the following AWS permissions:

- IAM: Create and manage roles and policies
- Lambda: Create and manage functions
- API Gateway: Create and manage REST APIs
- Step Functions: Create and manage state machines
- CloudWatch: Create and manage log groups
- CloudFormation: Create and manage stacks

## Installation and Setup

### 1. Clone and Navigate

```bash
cd aws/api-integration-agentcore-gateway/code/cdk-python/
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
# Install production dependencies
pip install -r requirements.txt

# Install development dependencies (optional)
pip install -e .[dev,docs,typing]
```

### 4. Bootstrap CDK (if not already done)

```bash
# Bootstrap CDK in your target region
cdk bootstrap aws://ACCOUNT-ID/REGION
```

## Configuration

### Environment Variables

Set the following environment variables to customize the deployment:

```bash
export PROJECT_NAME="api-integration"          # Default: api-integration
export ENVIRONMENT="dev"                       # Default: dev
export CDK_DEFAULT_REGION="us-east-1"         # Default: us-east-1
export CDK_DEFAULT_ACCOUNT="123456789012"     # Your AWS account ID
```

### CDK Context Parameters

You can also use CDK context parameters:

```bash
# Deploy with custom context
cdk deploy --context project_name=my-api --context environment=prod
```

### Cost Estimation

Estimated monthly costs for typical usage:

- **Lambda Functions**: $5-15 (1M requests/month)
- **API Gateway**: $3-10 (1M requests/month)
- **Step Functions**: $2-8 (10K executions/month)
- **CloudWatch Logs**: $1-5 (standard retention)

**Total estimated cost**: $11-38/month

## Deployment

### 1. Validate the CDK Application

```bash
# Synthesize CloudFormation template
cdk synth

# Check for differences with deployed stack
cdk diff
```

### 2. Deploy the Stack

```bash
# Deploy with confirmation prompts
cdk deploy

# Deploy without confirmation (CI/CD)
cdk deploy --require-approval never

# Deploy to specific environment
cdk deploy --context environment=prod
```

### 3. Verify Deployment

```bash
# List deployed stacks
cdk list

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name ApiIntegrationStack-dev \
    --query 'Stacks[0].Outputs'
```

## Usage

### Testing the API

After deployment, test the API endpoint:

```bash
# Get the API endpoint from stack outputs
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name ApiIntegrationStack-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

# Test with sample data
curl -X POST $API_ENDPOINT \
    -H "Content-Type: application/json" \
    -d '{
        "id": "test-001",
        "type": "erp",
        "data": {
            "amount": 1500.00,
            "transaction_type": "purchase_order"
        },
        "validation_type": "financial"
    }'
```

### Monitoring Executions

```bash
# List Step Functions executions
aws stepfunctions list-executions \
    --state-machine-arn $(aws cloudformation describe-stacks \
        --stack-name ApiIntegrationStack-dev \
        --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
        --output text)

# View CloudWatch logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/api-integration"
```

## Development

### Code Structure

```
cdk-python/
├── app.py                 # Main CDK application
├── requirements.txt       # Python dependencies
├── setup.py              # Package configuration
├── cdk.json              # CDK configuration
├── README.md             # This file
├── .venv/                # Virtual environment
└── cdk.out/              # CDK synthesis output
```

### Adding New Features

1. **New Lambda Function**:
   ```python
   def _create_new_function(self) -> _lambda.Function:
       # Add your Lambda function code here
       pass
   ```

2. **New Step Functions Task**:
   ```python
   new_task = sfn_tasks.LambdaInvoke(
       self, "NewTask",
       lambda_function=self.new_function
   )
   ```

3. **New API Gateway Resource**:
   ```python
   new_resource = self.api_gateway.root.add_resource("new-endpoint")
   ```

### Running Tests

```bash
# Install test dependencies
pip install -e .[dev]

# Run unit tests
pytest tests/

# Run with coverage
pytest --cov=app tests/

# Run linting
flake8 app.py
black --check app.py
mypy app.py
```

### Code Quality

```bash
# Format code
black app.py

# Sort imports
isort app.py

# Security scan
bandit -r app.py

# Dependency vulnerability check
safety check
```

## Customization

### Environment-Specific Configurations

Create environment-specific configurations by modifying the CDK context or environment variables:

```python
# In app.py
if environment == "prod":
    # Production-specific settings
    memory_size = 1024
    timeout = Duration.minutes(5)
else:
    # Development settings
    memory_size = 512
    timeout = Duration.minutes(1)
```

### Adding CDK Nag Security Checks

```python
# Add to app.py
from cdk_nag import AwsSolutionsChecks

# Apply security checks
AwsSolutionsChecks().visit(stack)
```

### Custom Lambda Layers

```python
# Add Lambda layer for shared dependencies
layer = _lambda.LayerVersion(
    self, "SharedLayer",
    code=_lambda.Code.from_asset("layer"),
    compatible_runtimes=[_lambda.Runtime.PYTHON_3_12]
)

# Use in Lambda function
function = _lambda.Function(
    self, "Function",
    layers=[layer],
    # ... other properties
)
```

## Troubleshooting

### Common Issues

1. **CDK Bootstrap Required**:
   ```bash
   cdk bootstrap aws://ACCOUNT-ID/REGION
   ```

2. **Permission Errors**:
   - Verify AWS credentials: `aws sts get-caller-identity`
   - Check IAM permissions for required services

3. **Python Version Issues**:
   ```bash
   python --version  # Should be 3.8+
   pip install --upgrade pip setuptools
   ```

4. **Lambda Function Errors**:
   - Check CloudWatch logs: `/aws/lambda/function-name`
   - Verify IAM permissions for Lambda execution role

5. **API Gateway Issues**:
   - Check API Gateway CloudWatch logs
   - Verify integration configurations

### Debug Mode

Enable debug logging:

```bash
# CDK debug mode
cdk synth --debug

# Python debug logging
export PYTHONPATH=.
export AWS_LOG_LEVEL=DEBUG
python app.py
```

### Cleanup Failed Deployments

```bash
# Delete stack if deployment fails
cdk destroy

# Force delete CloudFormation stack
aws cloudformation delete-stack --stack-name ApiIntegrationStack-dev
```

## Cleanup

### Remove All Resources

```bash
# Destroy the CDK stack
cdk destroy

# Verify cleanup
aws cloudformation list-stacks \
    --stack-status-filter DELETE_COMPLETE \
    --query 'StackSummaries[?contains(StackName, `ApiIntegration`)].{Name:StackName,Status:StackStatus}'
```

### Clean Development Environment

```bash
# Deactivate virtual environment
deactivate

# Remove virtual environment
rm -rf .venv

# Remove CDK output
rm -rf cdk.out
```

## Security Considerations

### IAM Best Practices

- All roles follow least privilege principle
- No wildcard permissions in production
- Regular security reviews and updates

### Data Protection

- API Gateway rate limiting enabled
- CloudWatch logs with appropriate retention
- No sensitive data logged in Lambda functions

### Network Security

- Regional API Gateway endpoint
- VPC endpoints available for private access
- WAF integration possible for additional protection

## Support and Resources

### Documentation

- [AWS CDK Python Reference](https://docs.aws.amazon.com/cdk/api/v2/python/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon API Gateway Developer Guide](https://docs.aws.amazon.com/apigateway/latest/developerguide/)
- [AWS Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/latest/dg/)

### Community

- [AWS CDK GitHub](https://github.com/aws/aws-cdk)
- [AWS CDK Slack](https://cdk.dev/slack)
- [AWS Developer Forums](https://forums.aws.amazon.com/)

### Professional Support

- [AWS Support](https://aws.amazon.com/support/)
- [AWS Professional Services](https://aws.amazon.com/professional-services/)

## License

This sample code is made available under the MIT-0 license. See the LICENSE file.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## Changelog

### Version 1.0.0
- Initial CDK Python implementation
- Complete API integration workflow
- Comprehensive documentation
- Production-ready security configuration