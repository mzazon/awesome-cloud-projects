# Dynamic Configuration Management - CDK Python Implementation

This CDK Python application implements a serverless configuration management system using AWS Systems Manager Parameter Store, Lambda functions with the AWS Parameters and Secrets Extension for cached retrieval, EventBridge for automatic configuration invalidation, and CloudWatch for comprehensive monitoring.

## Architecture Overview

The solution creates:

- **Parameter Store Configuration**: Sample hierarchical parameters (`/myapp/config/*`)
- **Lambda Function**: Configuration retrieval with intelligent caching via Parameters Extension
- **EventBridge Integration**: Automatic configuration change detection and processing
- **CloudWatch Monitoring**: Comprehensive dashboards, alarms, and custom metrics
- **IAM Security**: Least privilege access controls with CDK Nag compliance

## Prerequisites

- Python 3.9 or later
- AWS CLI configured with appropriate permissions
- Node.js 16+ (for AWS CDK CLI)
- AWS CDK CLI installed (`npm install -g aws-cdk`)

## Installation

1. **Clone and navigate to the project directory:**
   ```bash
   cd cdk-python/
   ```

2. **Create and activate a virtual environment:**
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   ```

3. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

4. **Bootstrap CDK (if not already done):**
   ```bash
   cdk bootstrap
   ```

## Deployment

### Quick Deployment
```bash
# Synthesize CloudFormation template
cdk synth

# Deploy the stack
cdk deploy
```

### Environment-Specific Deployment
```bash
# Set environment context
cdk deploy -c environment=development

# Deploy to specific account/region
cdk deploy -c account=123456789012 -c region=us-west-2
```

### Security Validation
```bash
# Run CDK Nag security checks
cdk synth --strict
```

## Configuration

### Environment Variables
The CDK application supports these context variables:

- `environment`: Deployment environment (development/staging/production)
- `account`: AWS account ID (optional, uses default if not specified)
- `region`: AWS region (optional, uses default if not specified)

### Parameter Store Configuration
The stack creates these sample parameters:

- `/myapp/config/database/host`: Database endpoint
- `/myapp/config/database/port`: Database port
- `/myapp/config/database/password`: Encrypted password (SecureString)
- `/myapp/config/api/timeout`: API timeout setting
- `/myapp/config/features/new-ui`: Feature flag

## Usage

### Testing Configuration Retrieval
```bash
# Get function name from stack outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
  --stack-name DynamicConfigManagementStack \
  --query 'Stacks[0].Outputs[?OutputKey==`ConfigManagerFunctionName`].OutputValue' \
  --output text)

# Test configuration retrieval
aws lambda invoke \
  --function-name $FUNCTION_NAME \
  --payload '{}' \
  response.json && cat response.json
```

### Updating Configuration
```bash
# Update a parameter to trigger EventBridge event
aws ssm put-parameter \
  --name "/myapp/config/api/timeout" \
  --value "45" \
  --type "String" \
  --overwrite
```

### Monitoring
Access the CloudWatch dashboard:
```bash
# Get dashboard URL
echo "https://console.aws.amazon.com/cloudwatch/home?region=$(aws configure get region)#dashboards:name=ConfigManager-Dashboard"
```

## Architecture Benefits

### Performance Optimization
- **Local Caching**: Parameters Extension reduces API calls by up to 99%
- **Configurable TTL**: 5-minute default cache with customizable expiration
- **Intelligent Fallback**: Direct SSM calls when extension unavailable

### Operational Excellence
- **Event-Driven Updates**: Automatic cache invalidation via EventBridge
- **Comprehensive Monitoring**: Custom metrics, alarms, and dashboards
- **Structured Logging**: CloudWatch Logs with correlation IDs

### Security Best Practices
- **Least Privilege IAM**: Minimal permissions for Parameter Store access
- **Encryption Support**: SecureString parameters with KMS integration
- **CDK Nag Compliance**: Automated security validation

### Cost Optimization
- **Reduced API Calls**: Caching significantly reduces Parameter Store requests
- **Serverless Architecture**: Pay-per-use pricing model
- **Resource Tagging**: Cost allocation and management

## Monitoring and Troubleshooting

### Key Metrics
- **SuccessfulParameterRetrievals**: Configuration retrieval success rate
- **FailedParameterRetrievals**: Configuration retrieval failures
- **ConfigurationErrors**: Application-level configuration errors

### CloudWatch Alarms
- **Lambda Errors**: Triggers after 5 errors in 10 minutes
- **Lambda Duration**: Alerts on functions exceeding 10 seconds
- **Config Failures**: Monitors configuration retrieval problems

### Troubleshooting
```bash
# Check function logs
aws logs filter-log-events \
  --log-group-name "/aws/lambda/$FUNCTION_NAME" \
  --start-time $(date -d '1 hour ago' +%s)000

# Monitor EventBridge rule
aws events list-targets-by-rule \
  --rule "$(aws cloudformation describe-stack-resources \
    --stack-name DynamicConfigManagementStack \
    --logical-resource-id ParameterChangeRule \
    --query 'StackResources[0].PhysicalResourceId' \
    --output text)"
```

## Development

### Code Structure
```
dynamic_config_management/
├── __init__.py                          # Package initialization
└── dynamic_config_management_stack.py   # Main CDK stack
```

### Testing
```bash
# Install dev dependencies
pip install -r requirements.txt

# Run unit tests
python -m pytest tests/ -v

# Run type checking
mypy dynamic_config_management/

# Format code
black dynamic_config_management/
isort dynamic_config_management/
```

### Security Validation
```bash
# Run CDK Nag checks
cdk synth --strict

# Check for security issues
bandit -r dynamic_config_management/
```

## Customization

### Adding New Parameters
```python
# In dynamic_config_management_stack.py
ssm.StringParameter(
    self, "NewParameter",
    parameter_name=f"{self.parameter_prefix}/new/parameter",
    string_value="default_value",
    description="New configuration parameter",
)
```

### Custom Monitoring
```python
# Add custom CloudWatch metric
cloudwatch.Metric(
    namespace="ConfigManager",
    metric_name="CustomMetric",
    period=Duration.minutes(5),
    statistic=cloudwatch.Statistic.SUM
)
```

### Environment-Specific Configuration
```python
# In app.py, add environment-specific settings
environment = app.node.try_get_context("environment") or "development"
if environment == "production":
    # Production-specific configuration
    pass
```

## Cleanup

```bash
# Destroy the stack
cdk destroy

# Confirm deletion
cdk destroy --force
```

## Best Practices

### Parameter Organization
- Use hierarchical parameter naming (`/app/component/setting`)
- Group related parameters under common prefixes
- Use descriptive parameter names and descriptions

### Caching Strategy
- Configure appropriate TTL based on change frequency
- Use shorter TTL for feature flags, longer for stable config
- Monitor cache hit rates and adjust accordingly

### Security
- Use SecureString for sensitive values
- Implement parameter-level IAM permissions
- Regular rotation of sensitive parameters

### Monitoring
- Set up alerts for configuration retrieval failures
- Monitor Lambda function performance metrics
- Track parameter change patterns

## Support

- **AWS CDK Documentation**: [https://docs.aws.amazon.com/cdk/](https://docs.aws.amazon.com/cdk/)
- **Parameter Store Documentation**: [https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
- **Parameters Extension**: [https://docs.aws.amazon.com/systems-manager/latest/userguide/ps-integration-lambda-extensions.html](https://docs.aws.amazon.com/systems-manager/latest/userguide/ps-integration-lambda-extensions.html)