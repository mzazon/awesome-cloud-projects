# Infrastructure as Code for Feature Flags with AWS AppConfig

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Feature Flags with AWS AppConfig".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for creating AppConfig, Lambda, CloudWatch, and IAM resources
- For CDK implementations: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform 1.0+ installed
- Estimated cost: $5-15 per month for testing workloads

### Required AWS Permissions

Your AWS user/role needs permissions for:
- AWS AppConfig (applications, environments, configuration profiles, deployments)
- AWS Lambda (functions, layers, invoke permissions)
- AWS CloudWatch (alarms, metrics, logs)
- AWS IAM (roles, policies, service-linked roles)

## Quick Start

### Using CloudFormation

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name feature-flags-appconfig \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ApplicationName,ParameterValue=my-feature-app

# Monitor deployment progress
aws cloudformation describe-stacks \
    --stack-name feature-flags-appconfig \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name feature-flags-appconfig \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript

```bash
# Navigate to CDK TypeScript directory
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
npx cdk bootstrap

# Deploy the stack
npx cdk deploy

# View stack outputs
npx cdk ls --long
```

### Using CDK Python

```bash
# Navigate to CDK Python directory
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate.bat

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy

# View stack outputs
cdk ls --long
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will output resource information upon completion
```

## Testing the Deployment

After deployment, you can test the feature flags functionality:

### Test Lambda Function

```bash
# Get the Lambda function name from outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name feature-flags-appconfig \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Invoke the function to test feature flags
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{}' \
    response.json

# View the response
cat response.json | jq .
```

### Monitor Feature Flag Deployments

```bash
# Get AppConfig application ID from outputs
APP_ID=$(aws cloudformation describe-stacks \
    --stack-name feature-flags-appconfig \
    --query 'Stacks[0].Outputs[?OutputKey==`AppConfigApplicationId`].OutputValue' \
    --output text)

# List deployments
aws appconfig list-deployments \
    --application-id $APP_ID \
    --environment-id $(aws cloudformation describe-stacks \
        --stack-name feature-flags-appconfig \
        --query 'Stacks[0].Outputs[?OutputKey==`AppConfigEnvironmentId`].OutputValue' \
        --output text)
```

### Update Feature Flags

To update feature flags, create a new configuration version and deploy it:

```bash
# Create updated feature flags configuration
cat > updated-flags.json << 'EOF'
{
    "flags": {
        "new-checkout-flow": {
            "name": "new-checkout-flow",
            "enabled": true
        },
        "enhanced-search": {
            "name": "enhanced-search", 
            "enabled": true
        },
        "premium-features": {
            "name": "premium-features",
            "enabled": true
        }
    },
    "attributes": {
        "rollout-percentage": {
            "number": 50
        },
        "search-algorithm": {
            "string": "elasticsearch"
        },
        "feature-list": {
            "string": "advanced-analytics,priority-support"
        }
    }
}
EOF

# Deploy the updated configuration (replace with your actual IDs)
aws appconfig create-hosted-configuration-version \
    --application-id $APP_ID \
    --configuration-profile-id $PROFILE_ID \
    --content-type "application/json" \
    --content file://updated-flags.json

# Start deployment with gradual rollout
aws appconfig start-deployment \
    --application-id $APP_ID \
    --environment-id $ENV_ID \
    --deployment-strategy-id $STRATEGY_ID \
    --configuration-profile-id $PROFILE_ID \
    --configuration-version 2
```

## Cleanup

### Using CloudFormation

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name feature-flags-appconfig

# Monitor deletion progress
aws cloudformation describe-stacks \
    --stack-name feature-flags-appconfig \
    --query 'Stacks[0].StackStatus'
```

### Using CDK TypeScript

```bash
cd cdk-typescript/
npx cdk destroy
```

### Using CDK Python

```bash
cd cdk-python/
cdk destroy
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Customization

### CloudFormation Parameters

- `ApplicationName`: Name for the AppConfig application (default: feature-demo-app)
- `EnvironmentName`: AppConfig environment name (default: production) 
- `FunctionName`: Lambda function name (default: feature-flag-demo)

### CDK Configuration

Modify the stack parameters in `app.ts` (TypeScript) or `app.py` (Python):

```typescript
// CDK TypeScript example
const stack = new FeatureFlagsStack(app, 'FeatureFlagsStack', {
  applicationName: 'my-custom-app',
  environmentName: 'staging',
  // ... other parameters
});
```

### Terraform Variables

Customize the deployment by modifying `terraform.tfvars`:

```hcl
application_name = "my-feature-app"
environment_name = "production"
function_name    = "my-feature-function"
aws_region      = "us-west-2"
```

### Feature Flag Configuration

To customize the feature flags, modify the configuration JSON in the respective implementation files. The structure includes:

- `flags`: Feature flag definitions with enabled/disabled states
- `attributes`: Configuration attributes like rollout percentages, target audiences, etc.

## Architecture Components

This implementation creates:

1. **AWS AppConfig Application**: Container for feature flag configurations
2. **AppConfig Environment**: Production environment with monitoring
3. **Configuration Profile**: Feature flag profile with validation
4. **Deployment Strategy**: Gradual rollout strategy (20 minutes, 25% growth rate)
5. **Lambda Function**: Demo application that consumes feature flags
6. **IAM Roles**: Least-privilege access for Lambda and AppConfig
7. **CloudWatch Alarm**: Monitoring for automatic rollback
8. **AppConfig Extension**: Lambda layer for efficient feature flag retrieval

## Monitoring and Troubleshooting

### CloudWatch Dashboards

Monitor your feature flags with CloudWatch:

```bash
# View Lambda function metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=$FUNCTION_NAME \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum

# View AppConfig retrieval metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/AppConfig \
    --metric-name ConfigurationRetrievals \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

### Common Issues

1. **AppConfig Extension Timeout**: Ensure Lambda timeout is adequate (30 seconds minimum)
2. **IAM Permissions**: Verify Lambda role has AppConfig data access permissions
3. **Deployment Rollback**: Check CloudWatch alarms if deployments auto-rollback
4. **Configuration Validation**: Ensure JSON structure matches expected schema

## Security Considerations

- IAM roles follow least-privilege principle
- AppConfig configurations are encrypted at rest
- Lambda function uses VPC endpoints for secure AppConfig access (if in VPC)
- CloudWatch alarms provide monitoring-based rollback protection
- Service-linked roles enable secure cross-service integration

## Best Practices

1. **Gradual Rollouts**: Use deployment strategies for safe feature releases
2. **Monitoring**: Set up CloudWatch alarms for automatic rollback
3. **Configuration Validation**: Validate JSON schemas before deployment
4. **Caching**: Leverage AppConfig extension for efficient configuration retrieval
5. **Fallback Logic**: Implement graceful degradation when AppConfig is unavailable
6. **Feature Flag Lifecycle**: Regular cleanup of obsolete feature flags

## Performance Optimization

- AppConfig extension provides local caching (reduces API calls)
- Lambda warm-up strategies can improve first-call performance
- Consider connection pooling for high-traffic applications
- Use appropriate polling intervals based on your change frequency

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation for detailed implementation guidance
2. Review AWS AppConfig documentation: https://docs.aws.amazon.com/appconfig/
3. Consult AWS Lambda documentation: https://docs.aws.amazon.com/lambda/
4. Review AWS CloudWatch documentation: https://docs.aws.amazon.com/cloudwatch/

## Additional Resources

- [AWS AppConfig User Guide](https://docs.aws.amazon.com/appconfig/latest/userguide/)
- [AWS Lambda Extensions](https://docs.aws.amazon.com/lambda/latest/dg/extensions-api.html)
- [Feature Flag Best Practices](https://docs.aws.amazon.com/wellarchitected/latest/management-and-governance-pillar/feature-flags.html)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/)