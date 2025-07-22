# Infrastructure as Code for Implementing Dynamic Configuration with Parameter Store

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing Dynamic Configuration with Parameter Store".

## Available Implementations

- **CloudFormation**: AWS native infrastructure as code (YAML)
- **CDK TypeScript**: AWS Cloud Development Kit (TypeScript)
- **CDK Python**: AWS Cloud Development Kit (Python)  
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- AWS CLI v2 installed and configured
- Appropriate AWS permissions for:
  - Systems Manager Parameter Store (read/write)
  - Lambda functions (create/invoke/delete)
  - IAM roles and policies (create/attach/delete)
  - EventBridge rules (create/delete)
  - CloudWatch alarms and dashboards (create/delete)
- Node.js 18+ (for CDK TypeScript)
- Python 3.9+ (for CDK Python)
- Terraform 1.0+ (for Terraform implementation)
- Estimated cost: $5-10 per month for moderate usage

## Architecture Overview

This solution implements a serverless configuration management system that includes:

- **Parameter Store**: Hierarchical configuration storage with encryption support
- **Lambda Function**: Configuration retrieval with intelligent caching
- **Parameters Extension**: Local caching layer for improved performance
- **EventBridge**: Automatic configuration change event handling
- **CloudWatch**: Comprehensive monitoring and alerting
- **IAM Roles**: Least-privilege security configuration

## Quick Start

### Using CloudFormation
```bash
# Deploy the infrastructure
aws cloudformation create-stack \
    --stack-name config-management-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ParameterPrefix,ParameterValue=/myapp/config

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete \
    --stack-name config-management-stack

# Get stack outputs
aws cloudformation describe-stacks \
    --stack-name config-management-stack \
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

# View deployment summary
cat deployment-summary.txt
```

## Testing the Deployment

After deployment, test the configuration management system:

```bash
# Get the Lambda function name from outputs
export FUNCTION_NAME="your-function-name"

# Test configuration retrieval
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{}' \
    response.json

# View the response
cat response.json | jq .

# Update a parameter to test dynamic updates
aws ssm put-parameter \
    --name "/myapp/config/api/timeout" \
    --value "60" \
    --type "String" \
    --overwrite

# Test the update (after cache TTL expires)
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{}' \
    response-updated.json
```

## Configuration Options

### Parameters

All implementations support these customizable parameters:

- **ParameterPrefix**: Prefix for Parameter Store parameters (default: `/myapp/config`)
- **CacheTTL**: Extension cache TTL in seconds (default: 300)
- **FunctionTimeout**: Lambda timeout in seconds (default: 30)
- **FunctionMemorySize**: Lambda memory allocation in MB (default: 256)
- **MonitoringEnabled**: Enable CloudWatch alarms and dashboard (default: true)

### Example Customization

**CloudFormation:**
```bash
aws cloudformation create-stack \
    --stack-name config-management-stack \
    --template-body file://cloudformation.yaml \
    --capabilities CAPABILITY_IAM \
    --parameters \
        ParameterKey=ParameterPrefix,ParameterValue=/production/config \
        ParameterKey=CacheTTL,ParameterValue=600 \
        ParameterKey=FunctionTimeout,ParameterValue=60
```

**Terraform:**
```bash
# Create terraform.tfvars
cat > terraform.tfvars << EOF
parameter_prefix = "/production/config"
cache_ttl = 600
function_timeout = 60
function_memory_size = 512
monitoring_enabled = true
EOF

terraform apply
```

## Monitoring and Observability

The deployment includes comprehensive monitoring:

### CloudWatch Metrics
- Lambda function invocations, errors, and duration
- Custom metrics for configuration retrieval success/failure
- Parameter Store API call patterns

### CloudWatch Alarms
- Function error rate monitoring
- Performance degradation detection  
- Configuration retrieval failure alerts

### CloudWatch Dashboard
- Real-time system health overview
- Configuration management performance metrics
- Historical trend analysis

Access the dashboard:
```bash
# Get dashboard URL
aws cloudwatch describe-dashboards \
    --dashboard-names "ConfigManager-*" \
    --query 'DashboardEntries[0].DashboardName'
```

## Security Considerations

The implementation follows AWS security best practices:

- **IAM Least Privilege**: Lambda execution role has minimal required permissions
- **Parameter Encryption**: Support for SecureString parameters with KMS encryption
- **VPC Integration**: Optional VPC deployment for network isolation
- **Resource-based Policies**: Proper EventBridge to Lambda permissions
- **Audit Logging**: CloudTrail integration for parameter access logging

## Cost Optimization

To optimize costs:

1. **Adjust Cache TTL**: Longer TTL reduces Parameter Store API calls
2. **Right-size Lambda**: Monitor memory usage and adjust allocation
3. **Parameter Organization**: Group related parameters to reduce API calls
4. **Monitoring Cleanup**: Remove unnecessary alarms and dashboards in non-production

Estimated monthly costs:
- Parameter Store: $0.05 per 10,000 requests
- Lambda: $0.20 per 1M requests + $0.0000166667 per GB-second
- CloudWatch: $0.50 per alarm + $0.30 per dashboard

## Troubleshooting

### Common Issues

**Lambda Function Errors:**
```bash
# Check function logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/your-function-name" \
    --start-time $(date -d '1 hour ago' +%s)000
```

**Parameter Store Access Issues:**
```bash
# Verify parameter exists
aws ssm get-parameter --name "/myapp/config/database/host"

# Check IAM permissions
aws iam simulate-principal-policy \
    --policy-source-arn "arn:aws:iam::account:role/config-manager-role" \
    --action-names "ssm:GetParameter" \
    --resource-arns "arn:aws:ssm:region:account:parameter/myapp/config/*"
```

**EventBridge Rule Issues:**
```bash
# Check rule status
aws events describe-rule --name "parameter-change-rule-*"

# Verify Lambda permissions
aws lambda get-policy --function-name your-function-name
```

## Cleanup

### Using CloudFormation
```bash
# Delete the stack
aws cloudformation delete-stack --stack-name config-management-stack

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
    --stack-name config-management-stack
```

### Using CDK
```bash
cd cdk-typescript/  # or cdk-python/
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

### Manual Cleanup (if needed)
```bash
# Remove any remaining parameters
aws ssm delete-parameters \
    --names $(aws ssm get-parameters-by-path \
        --path "/myapp/config" \
        --query "Parameters[].Name" \
        --output text)

# Clean up log groups
aws logs delete-log-group \
    --log-group-name "/aws/lambda/your-function-name"
```

## Extension Ideas

1. **Multi-Environment Support**: Deploy separate stacks per environment with environment-specific parameter prefixes

2. **Parameter Validation**: Add Lambda functions to validate parameter values before storage

3. **Configuration Rollback**: Implement parameter versioning with automated rollback capabilities

4. **Cross-Region Replication**: Use EventBridge cross-region rules for configuration synchronization

5. **Advanced Caching**: Implement selective cache invalidation and cache warming strategies

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../dynamic-configuration-management-parameter-store-lambda.md)
2. Review AWS service documentation:
   - [Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
   - [Lambda Extensions](https://docs.aws.amazon.com/lambda/latest/dg/lambda-extensions.html)
   - [EventBridge](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
3. Consult provider-specific documentation for IaC tools

## Version Information

- Recipe Version: 1.0
- AWS CLI Version: 2.x
- CDK Version: 2.x
- Terraform Version: 1.x
- Generated: 2025-07-12