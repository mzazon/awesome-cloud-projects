# Dynamic Configuration with Parameter Store - Terraform

This Terraform configuration deploys a complete serverless configuration management system using AWS Systems Manager Parameter Store, Lambda functions with the Parameters and Secrets Extension, EventBridge for real-time configuration updates, and comprehensive CloudWatch monitoring.

## Architecture Overview

The solution implements:
- **Parameter Store**: Centralized configuration storage with hierarchical organization
- **Lambda Function**: Configuration retrieval with intelligent caching via Parameters Extension
- **EventBridge**: Event-driven configuration updates and cache invalidation
- **CloudWatch**: Comprehensive monitoring, alerting, and dashboards
- **IAM**: Least privilege access control and security policies

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- AWS account with appropriate permissions for:
  - Systems Manager Parameter Store
  - Lambda functions and layers
  - IAM roles and policies
  - EventBridge rules and targets
  - CloudWatch metrics, alarms, and dashboards

## Quick Start

### 1. Clone and Navigate

```bash
cd aws/dynamic-configuration-management-parameter-store-lambda/code/terraform/
```

### 2. Configure Variables

Copy the example variables file and customize it:

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific configuration
```

Key variables to customize:
- `database_host`: Your actual database endpoint
- `database_password`: Secure password for database access
- `environment`: Environment name (dev/staging/prod)
- `tags`: Resource tagging for cost allocation and management

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Apply the configuration
terraform apply
```

### 4. Verify Deployment

```bash
# Test the Lambda function
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload '{}' \
  response.json && cat response.json

# View the CloudWatch dashboard
echo "Dashboard URL: $(terraform output -raw cloudwatch_dashboard_url)"

# Check parameter retrieval
aws ssm get-parameters-by-path --path "$(terraform output -raw parameter_prefix)" --recursive
```

## Configuration Details

### Parameter Store Structure

The solution creates a hierarchical parameter structure:

```
/myapp/config/
├── database/
│   ├── host      (String)
│   ├── port      (String)
│   └── password  (SecureString)
├── api/
│   └── timeout   (String)
└── features/
    └── new-ui    (String)
```

### Lambda Function Features

- **Intelligent Caching**: Uses AWS Parameters and Secrets Extension for local caching
- **Error Handling**: Comprehensive error handling with fallback mechanisms
- **Monitoring**: Custom CloudWatch metrics for operational visibility
- **Validation**: Parameter validation and configuration consistency checks
- **Performance**: Optimized for low latency and high throughput

### Monitoring and Alerting

The solution includes comprehensive monitoring:

- **Lambda Metrics**: Errors, duration, invocations, and throttles
- **Custom Metrics**: Configuration retrieval success/failure rates
- **CloudWatch Alarms**: Proactive alerting on error thresholds
- **Dashboard**: Visual monitoring with metrics and log insights

## Usage Examples

### Testing Configuration Retrieval

```bash
# Direct function invocation
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload '{}' \
  response.json

# View response
cat response.json | jq .
```

### Updating Configuration Parameters

```bash
# Update a parameter value
aws ssm put-parameter \
  --name "$(terraform output -raw parameter_prefix)/api/timeout" \
  --value "60" \
  --type "String" \
  --overwrite

# The EventBridge rule will automatically trigger the Lambda function
# Check logs to verify the update was processed
aws logs filter-log-events \
  --log-group-name "/aws/lambda/$(terraform output -raw lambda_function_name)" \
  --start-time $(date -d '5 minutes ago' +%s)000
```

### Monitoring and Troubleshooting

```bash
# View recent function logs
aws logs filter-log-events \
  --log-group-name "/aws/lambda/$(terraform output -raw lambda_function_name)" \
  --start-time $(date -d '10 minutes ago' +%s)000

# Check custom metrics
aws cloudwatch get-metric-statistics \
  --namespace 'ConfigManager' \
  --metric-name 'SuccessfulParameterRetrievals' \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# View alarm status
aws cloudwatch describe-alarms \
  --alarm-names $(terraform output -json cloudwatch_alarm_names | jq -r '.[]')
```

## Customization

### Environment-Specific Configuration

Create different variable files for each environment:

```bash
# Development
cp terraform.tfvars.example dev.tfvars
# Edit dev.tfvars with development-specific values

# Staging
cp terraform.tfvars.example staging.tfvars
# Edit staging.tfvars with staging-specific values

# Production
cp terraform.tfvars.example prod.tfvars
# Edit prod.tfvars with production-specific values
```

Deploy with specific variable files:

```bash
# Deploy to development
terraform apply -var-file="dev.tfvars"

# Deploy to staging
terraform apply -var-file="staging.tfvars"

# Deploy to production
terraform apply -var-file="prod.tfvars"
```

### Adding New Parameters

1. Add new parameter resources in `main.tf`:

```hcl
resource "aws_ssm_parameter" "new_config" {
  name        = "${var.parameter_prefix}/category/new-config"
  description = "Description of new configuration parameter"
  type        = "String"  # or "SecureString"
  value       = var.new_config_value
  
  tags = merge(local.common_tags, {
    ParameterType = "Configuration"
    Category      = "NewCategory"
  })
}
```

2. Add corresponding variable in `variables.tf`:

```hcl
variable "new_config_value" {
  description = "New configuration parameter value"
  type        = string
  default     = "default-value"
}
```

3. Update the Lambda function code to retrieve the new parameter.

### Customizing Monitoring

Modify monitoring thresholds in `terraform.tfvars`:

```hcl
# Adjust alarm thresholds
error_threshold = 3
duration_threshold = 8000
failure_threshold = 2

# Customize evaluation periods
alarm_evaluation_periods = 3
alarm_period = 300
```

## Security Considerations

### IAM Permissions

The solution implements least privilege access:
- Lambda execution role has minimal required permissions
- Parameter Store access scoped to specific path prefix
- KMS decrypt permissions conditioned on SSM service usage

### Parameter Encryption

- Sensitive parameters use `SecureString` type with KMS encryption
- Database passwords and other secrets are automatically encrypted
- Access to encrypted parameters requires KMS decrypt permissions

### Network Security

For enhanced security in production:
- Deploy Lambda function in VPC with private subnets
- Use VPC endpoints for Parameter Store and other AWS services
- Implement network access controls and security groups

## Cost Optimization

### Parameter Store Costs

- Standard parameters: First 10,000 free, $0.05 per 10,000 requests thereafter
- Advanced parameters: $0.05 per parameter per month + $0.05 per 10,000 requests
- Use intelligent caching to reduce API calls and costs

### Lambda Costs

- Charges based on requests and compute time
- Optimize memory allocation based on performance requirements
- Use reserved capacity for predictable workloads

### CloudWatch Costs

- Custom metrics: $0.30 per metric per month (first 10,000 metrics)
- Dashboard: $3.00 per dashboard per month
- Logs: $0.50 per GB ingested, $0.03 per GB stored

## Troubleshooting

### Common Issues

1. **Lambda function timeouts**:
   ```bash
   # Increase timeout in variables.tf
   lambda_timeout = 60
   ```

2. **Parameter Store access denied**:
   ```bash
   # Verify IAM permissions and parameter paths
   aws iam get-role-policy --role-name <role-name> --policy-name <policy-name>
   ```

3. **Extension layer not working**:
   ```bash
   # Verify correct layer ARN for region
   # Check Lambda environment variables
   ```

4. **EventBridge rule not triggering**:
   ```bash
   # Verify event pattern and rule status
   aws events describe-rule --name <rule-name>
   ```

### Debugging Commands

```bash
# Check Terraform state
terraform state list
terraform state show <resource>

# Validate configuration
terraform validate
terraform plan

# View outputs
terraform output
terraform output -json
```

## Cleanup

To remove all resources:

```bash
# Destroy all resources
terraform destroy

# Confirm destruction
# Type 'yes' when prompted
```

**Warning**: This will permanently delete all resources including parameter values and monitoring data.

## Backend Configuration

For production deployments, configure remote state:

Create `backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "config-manager/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"
  }
}
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Deploy Configuration Manager
on:
  push:
    branches: [main]
    paths: ['terraform/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2
        with:
          terraform_version: 1.5.0
      
      - name: Terraform Init
        run: terraform init
        
      - name: Terraform Plan
        run: terraform plan -var-file="prod.tfvars"
        
      - name: Terraform Apply
        run: terraform apply -auto-approve -var-file="prod.tfvars"
```

## Support and Contributing

For issues or questions:
1. Check the troubleshooting section above
2. Review AWS documentation for specific services
3. Consult Terraform AWS provider documentation
4. Check CloudWatch logs for Lambda function errors

For improvements or bug fixes, submit pull requests with:
- Clear description of changes
- Testing evidence
- Updated documentation

## References

- [AWS Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
- [AWS Lambda](https://docs.aws.amazon.com/lambda/latest/dg/)
- [AWS Parameters and Secrets Extension](https://docs.aws.amazon.com/systems-manager/latest/userguide/ps-integration-lambda-extensions.html)
- [Amazon EventBridge](https://docs.aws.amazon.com/eventbridge/latest/userguide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)