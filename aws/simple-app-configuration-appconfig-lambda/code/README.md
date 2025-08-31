# Infrastructure as Code for Simple Application Configuration with AppConfig and Lambda

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Application Configuration with AppConfig and Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI installed and configured
- Appropriate AWS permissions for AppConfig, Lambda, IAM, and CloudWatch
- For CDK implementations: Node.js 18+ and AWS CDK CLI installed
- For Terraform: Terraform 1.0+ installed
- Basic understanding of serverless functions and configuration management

## Quick Start

### Using CloudFormation (AWS)

```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name simple-appconfig-lambda-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ApplicationName,ParameterValue=my-config-app \
                 ParameterKey=LambdaFunctionName,ParameterValue=my-config-function

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name simple-appconfig-lambda-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name simple-appconfig-lambda-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript (AWS)

```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters applicationName=my-config-app \
           --parameters lambdaFunctionName=my-config-function

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using CDK Python (AWS)

```bash
cd cdk-python/

# Create virtual environment (recommended)
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (if first time using CDK in this account/region)
cdk bootstrap

# Deploy the stack
cdk deploy --parameters applicationName=my-config-app \
           --parameters lambdaFunctionName=my-config-function

# View outputs
cdk deploy --outputs-file outputs.json
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan -var="application_name=my-config-app" \
               -var="lambda_function_name=my-config-function"

# Apply the configuration
terraform apply -var="application_name=my-config-app" \
                -var="lambda_function_name=my-config-function"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables (optional customization)
export APPLICATION_NAME="my-config-app"
export LAMBDA_FUNCTION_NAME="my-config-function"

# Deploy infrastructure
./scripts/deploy.sh

# View deployment outputs
cat deployment_outputs.json
```

## Configuration Parameters

### CloudFormation Parameters

- `ApplicationName`: Name for the AppConfig application (default: simple-config-app)
- `LambdaFunctionName`: Name for the Lambda function (default: config-demo-function)
- `Environment`: Environment name for AppConfig (default: development)

### CDK Parameters

- `applicationName`: Name for the AppConfig application
- `lambdaFunctionName`: Name for the Lambda function
- `environment`: Environment name for AppConfig

### Terraform Variables

- `application_name`: Name for the AppConfig application
- `lambda_function_name`: Name for the Lambda function
- `environment_name`: Environment name for AppConfig
- `aws_region`: AWS region for deployment (defaults to current region)

### Bash Script Environment Variables

- `APPLICATION_NAME`: Name for the AppConfig application
- `LAMBDA_FUNCTION_NAME`: Name for the Lambda function
- `ENVIRONMENT_NAME`: Environment name for AppConfig
- `AWS_REGION`: AWS region for deployment

## Testing the Deployment

After successful deployment, test the Lambda function:

```bash
# Get the Lambda function name from outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name simple-appconfig-lambda-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Invoke the function
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload '{}' \
    response.json

# View the response
cat response.json | jq '.'
```

## Updating Configuration

To update the application configuration after deployment:

```bash
# Create new configuration version
cat > updated-config.json << 'EOF'
{
  "database": {
    "max_connections": 200,
    "timeout_seconds": 45,
    "retry_attempts": 5
  },
  "features": {
    "enable_logging": true,
    "enable_metrics": true,
    "debug_mode": true
  },
  "api": {
    "rate_limit": 2000,
    "cache_ttl": 600
  }
}
EOF

# Get AppConfig details from stack outputs
APP_ID=$(aws cloudformation describe-stacks \
    --stack-name simple-appconfig-lambda-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`AppConfigApplicationId`].OutputValue' \
    --output text)

CONFIG_PROFILE_ID=$(aws cloudformation describe-stacks \
    --stack-name simple-appconfig-lambda-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`ConfigurationProfileId`].OutputValue' \
    --output text)

# Create new configuration version
aws appconfig create-hosted-configuration-version \
    --application-id ${APP_ID} \
    --configuration-profile-id ${CONFIG_PROFILE_ID} \
    --content-type "application/json" \
    --content fileb://updated-config.json

# Deploy the updated configuration (deployment strategy from outputs)
DEPLOYMENT_STRATEGY_ID=$(aws cloudformation describe-stacks \
    --stack-name simple-appconfig-lambda-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`DeploymentStrategyId`].OutputValue' \
    --output text)

ENV_ID=$(aws cloudformation describe-stacks \
    --stack-name simple-appconfig-lambda-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`EnvironmentId`].OutputValue' \
    --output text)

NEW_VERSION=$(aws appconfig list-hosted-configuration-versions \
    --application-id ${APP_ID} \
    --configuration-profile-id ${CONFIG_PROFILE_ID} \
    --query "Items[0].VersionNumber" --output text)

aws appconfig start-deployment \
    --application-id ${APP_ID} \
    --environment-id ${ENV_ID} \
    --deployment-strategy-id ${DEPLOYMENT_STRATEGY_ID} \
    --configuration-profile-id ${CONFIG_PROFILE_ID} \
    --configuration-version ${NEW_VERSION} \
    --description "Updated configuration deployment"
```

## Monitoring and Troubleshooting

### CloudWatch Logs

```bash
# View Lambda function logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
    --start-time $(date -d '10 minutes ago' +%s)000
```

### AppConfig Deployment Status

```bash
# Check deployment status
aws appconfig list-deployments \
    --application-id ${APP_ID} \
    --environment-id ${ENV_ID}
```

### Lambda Function Metrics

```bash
# Get Lambda function metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Invocations \
    --dimensions Name=FunctionName,Value=${FUNCTION_NAME} \
    --start-time $(date -d '1 hour ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Sum
```

## Cleanup

### Using CloudFormation (AWS)

```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name simple-appconfig-lambda-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name simple-appconfig-lambda-stack
```

### Using CDK (AWS)

```bash
cd cdk-typescript/  # or cdk-python/

# Destroy the stack
cdk destroy

# Confirm deletion when prompted
```

### Using Terraform

```bash
cd terraform/

# Destroy the infrastructure
terraform destroy

# Confirm deletion when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion when prompted
```

## Cost Optimization

This solution uses several AWS services with different pricing models:

- **AWS AppConfig**: Pay-per-request pricing ($0.50 per 1M requests)
- **AWS Lambda**: Pay-per-invocation and compute time
- **CloudWatch Logs**: Pay for log ingestion and storage
- **IAM**: No additional charges

To minimize costs:
- Use appropriate Lambda memory settings for your workload
- Set CloudWatch log retention policies
- Monitor AppConfig request patterns to optimize caching

## Security Considerations

The deployed infrastructure follows AWS security best practices:

- **IAM Roles**: Least privilege access for Lambda execution
- **Encryption**: Configuration data encrypted at rest and in transit
- **Network Security**: No public endpoints exposed
- **Access Control**: Proper IAM policies for AppConfig access

## Customization

### Adding Validation

To add JSON Schema validation to your configuration:

1. Create a JSON Schema file
2. Update the configuration profile to include validation
3. Modify the deployment process to include validation

### Multiple Environments

To deploy multiple environments (dev, staging, prod):

1. Duplicate the stack with different parameter values
2. Use different AppConfig applications or environments
3. Implement environment-specific configuration values

### Advanced Deployment Strategies

AppConfig supports various deployment strategies:

- **Canary**: Gradually roll out to a percentage of targets
- **Linear**: Deploy to targets in equal increments over time
- **All-at-once**: Deploy to all targets immediately

Modify the deployment strategy in the IaC templates to use these patterns.

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check AWS service documentation for AppConfig and Lambda
3. Verify IAM permissions and resource configurations
4. Review CloudWatch logs for error details

## Additional Resources

- [AWS AppConfig User Guide](https://docs.aws.amazon.com/appconfig/latest/userguide/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [AWS CDK Developer Guide](https://docs.aws.amazon.com/cdk/v2/guide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)