# Infrastructure as Code for Basic Secret Management with Secrets Manager and Lambda

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Basic Secret Management with Secrets Manager and Lambda".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - AWS Secrets Manager (create, delete secrets)
  - AWS Lambda (create, invoke, delete functions)
  - AWS IAM (create roles, policies, attach/detach policies)
  - AWS CloudWatch Logs (for Lambda logging)
- For CDK deployments: Node.js 18+ (TypeScript) or Python 3.8+ (Python)
- For Terraform: Terraform v1.0+ installed
- Basic understanding of AWS services and Infrastructure as Code concepts

## Architecture Overview

This solution deploys:
- **AWS Secrets Manager Secret**: Encrypted storage for application credentials
- **Lambda Function**: Serverless function that retrieves secrets securely
- **IAM Role and Policies**: Least-privilege access for Lambda to Secrets Manager
- **Lambda Layer**: AWS Parameters and Secrets Extension for optimized retrieval
- **CloudWatch Log Group**: For Lambda function logging and monitoring

## Quick Start

### Using CloudFormation
```bash
# Deploy the stack
aws cloudformation create-stack \
    --stack-name basic-secret-management-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=Environment,ParameterValue=dev

# Check deployment status
aws cloudformation describe-stacks \
    --stack-name basic-secret-management-stack \
    --query 'Stacks[0].StackStatus'

# Get outputs
aws cloudformation describe-stacks \
    --stack-name basic-secret-management-stack \
    --query 'Stacks[0].Outputs'
```

### Using CDK TypeScript
```bash
cd cdk-typescript/

# Install dependencies
npm install

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using CDK Python
```bash
cd cdk-python/

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy

# View outputs
cdk list
```

### Using Terraform
```bash
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

# The script will create all resources and test the deployment
```

## Testing the Deployment

After deployment, test the Lambda function:

```bash
# Get the Lambda function name from outputs
FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name basic-secret-management-stack \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

# Invoke the function
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{}' \
    response.json

# View the response
cat response.json | jq .
```

Expected response showing successful secret retrieval without exposing sensitive values.

## Configuration Options

### CloudFormation Parameters
- `Environment`: Deployment environment (dev, staging, prod)
- `SecretName`: Custom name for the Secrets Manager secret
- `LambdaTimeout`: Lambda function timeout in seconds (default: 30)
- `LambdaMemorySize`: Lambda function memory in MB (default: 256)

### CDK Context Variables
```bash
# Set custom values during deployment
cdk deploy -c environment=production -c secretName=my-app-secrets
```

### Terraform Variables
```bash
# Create terraform.tfvars file
cat > terraform.tfvars << EOF
environment = "dev"
secret_name = "my-app-secrets"
lambda_timeout = 30
lambda_memory_size = 256
EOF

terraform apply -var-file="terraform.tfvars"
```

## Security Considerations

All implementations follow AWS security best practices:

- **Least Privilege Access**: IAM role has minimal permissions for secret access
- **Encryption**: Secrets are encrypted at rest using AWS KMS
- **Secure Retrieval**: Lambda Extension provides optimized, secure secret access
- **No Hardcoded Credentials**: All sensitive data stored in Secrets Manager
- **Resource Tagging**: All resources tagged for governance and cost tracking

## Performance Features

- **Lambda Extension Caching**: 5-minute default cache reduces API calls and improves performance
- **Optimized Memory**: Function configured with appropriate memory for secret retrieval workloads
- **Connection Reuse**: Extension maintains persistent connections to Secrets Manager
- **HTTP Interface**: Local HTTP endpoint eliminates SDK overhead

## Cost Optimization

- **On-Demand Pricing**: Lambda charges only for execution time
- **Extension Caching**: Reduces Secrets Manager API calls and associated costs
- **Right-Sized Resources**: Memory and timeout configured for optimal cost-performance
- **Resource Cleanup**: All implementations include comprehensive cleanup procedures

## Monitoring and Logging

The deployment includes:
- **CloudWatch Log Groups**: Centralized logging for Lambda execution
- **Structured Logging**: JSON-formatted logs for easy analysis
- **Error Tracking**: Comprehensive error handling with detailed logging
- **Performance Metrics**: Lambda duration and memory utilization tracking

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack \
    --stack-name basic-secret-management-stack

# Verify deletion
aws cloudformation describe-stacks \
    --stack-name basic-secret-management-stack
```

### Using CDK
```bash
# Destroy the stack
cdk destroy

# Confirm when prompted
```

### Using Terraform
```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm when prompted for destructive actions
```

## Customization

### Extending the Solution

1. **Add Secret Rotation**:
   - Modify the secret configuration to include rotation settings
   - Add a rotation Lambda function to the infrastructure
   - Update IAM permissions for rotation operations

2. **Multi-Environment Support**:
   - Use environment-specific parameter files
   - Implement environment-based resource naming
   - Add environment-specific secret configurations

3. **Cross-Region Deployment**:
   - Configure secret replication to multiple regions
   - Deploy Lambda functions in multiple regions
   - Implement failover logic for regional outages

4. **Enhanced Monitoring**:
   - Add CloudWatch alarms for failed secret retrievals
   - Implement X-Ray tracing for performance analysis
   - Create custom metrics for secret access patterns

### Common Modifications

```bash
# Update Lambda function code
aws lambda update-function-code \
    --function-name $FUNCTION_NAME \
    --zip-file fileb://new-function.zip

# Modify secret value
aws secretsmanager update-secret \
    --secret-id $SECRET_NAME \
    --secret-string '{"new_key": "new_value"}'

# Update extension configuration
aws lambda update-function-configuration \
    --function-name $FUNCTION_NAME \
    --environment Variables="{
        SECRET_NAME=$SECRET_NAME,
        PARAMETERS_SECRETS_EXTENSION_CACHE_ENABLED=true,
        PARAMETERS_SECRETS_EXTENSION_CACHE_SIZE=2000
    }"
```

## Troubleshooting

### Common Issues

1. **Lambda Timeout Errors**:
   ```bash
   # Increase timeout for cold start scenarios
   aws lambda update-function-configuration \
       --function-name $FUNCTION_NAME \
       --timeout 60
   ```

2. **Permission Denied Errors**:
   ```bash
   # Verify IAM role has proper permissions
   aws iam simulate-principal-policy \
       --policy-source-arn $LAMBDA_ROLE_ARN \
       --action-names secretsmanager:GetSecretValue \
       --resource-arns $SECRET_ARN
   ```

3. **Extension Not Loading**:
   ```bash
   # Verify layer ARN for your region
   aws lambda get-layer-version \
       --layer-name AWS-Parameters-and-Secrets-Lambda-Extension \
       --version-number 18
   ```

### Debugging Commands

```bash
# View Lambda logs
aws logs tail /aws/lambda/$FUNCTION_NAME --follow

# Check secret accessibility
aws secretsmanager get-secret-value --secret-id $SECRET_NAME

# Verify Lambda configuration
aws lambda get-function-configuration --function-name $FUNCTION_NAME
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for step-by-step implementation details
2. **AWS Documentation**: Consult the [AWS Secrets Manager User Guide](https://docs.aws.amazon.com/secretsmanager/latest/userguide/)
3. **Lambda Extension**: Review the [AWS Parameters and Secrets Lambda Extension](https://docs.aws.amazon.com/systems-manager/latest/userguide/ps-integration-lambda-extensions.html) documentation
4. **Best Practices**: Follow the [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/) security pillar guidance

## Version History

- **v1.0**: Initial implementation with basic secret management
- **v1.1**: Added Lambda Extension support and performance optimizations

---

**Note**: This infrastructure implements the solution described in the "Basic Secret Management with Secrets Manager and Lambda" recipe. For detailed implementation guidance and best practices, refer to the complete recipe documentation.