# Terraform Infrastructure for Basic Secret Management with Secrets Manager and Lambda

This directory contains Terraform Infrastructure as Code (IaC) for deploying the "Basic Secret Management with Secrets Manager and Lambda" solution on AWS.

## Overview

This Terraform configuration creates a complete secret management solution that demonstrates AWS best practices for storing and retrieving sensitive information:

- **AWS Secrets Manager**: Encrypted storage for database credentials and other secrets
- **AWS Lambda**: Serverless function that retrieves secrets using the optimized extension
- **AWS Parameters and Secrets Lambda Extension**: High-performance caching layer for secret retrieval
- **IAM Roles and Policies**: Least privilege access control
- **CloudWatch Logs**: Monitoring and debugging capabilities
- **CloudWatch Alarms**: Proactive monitoring for errors and performance

## Architecture

The solution implements the following architecture:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Application   │    │  Lambda Function │    │ Secrets Manager │
│   (API/Event)   ├───▶│   + Extension    ├───▶│   (Encrypted)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │  CloudWatch     │
                       │  Logs & Alarms  │
                       └─────────────────┘
```

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
   ```bash
   aws configure
   ```

2. **Terraform** installed (version 1.0 or later)
   ```bash
   terraform --version
   ```

3. **Required AWS Permissions**:
   - IAM permissions to create and manage roles, policies
   - Lambda permissions to create functions and layers
   - Secrets Manager permissions to create and manage secrets
   - CloudWatch permissions for logs and alarms
   - KMS permissions if using custom encryption keys

4. **Network Access**: Internet connectivity for downloading Terraform providers and modules

## Quick Start

### 1. Initialize Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform (downloads providers and modules)
terraform init
```

### 2. Review and Customize Variables

Copy the example variables file and customize for your environment:

```bash
# Create a variables file (optional)
cat > terraform.tfvars << EOF
project_name = "my-secret-demo"
environment  = "dev"

# Optional: Customize Lambda settings
lambda_timeout    = 30
lambda_memory_size = 256

# Optional: Customize secret settings
secret_recovery_window = 7
enable_secret_rotation = false

# Optional: Add custom tags
additional_tags = {
  Owner       = "DevOps Team"
  CostCenter  = "Engineering"
  Application = "Secret Management Demo"
}
EOF
```

### 3. Plan the Deployment

```bash
# Review the planned changes
terraform plan
```

### 4. Deploy the Infrastructure

```bash
# Apply the configuration
terraform apply

# Type 'yes' when prompted to confirm the deployment
```

### 5. Test the Deployment

After successful deployment, test the Lambda function:

```bash
# Get the Lambda function name from outputs
FUNCTION_NAME=$(terraform output -raw lambda_function_name)

# Invoke the Lambda function
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{}' \
    response.json

# View the response
cat response.json | jq .
```

## Configuration Options

### Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_name` | Name of the project for resource naming | `secret-demo` | No |
| `environment` | Environment name (dev, staging, prod, test) | `dev` | No |
| `lambda_timeout` | Lambda function timeout in seconds (3-900) | `30` | No |
| `lambda_memory_size` | Lambda memory size in MB (128-10240) | `256` | No |
| `lambda_runtime` | Lambda runtime version | `python3.11` | No |
| `secret_recovery_window` | Days before permanent secret deletion (0 or 7-30) | `7` | No |
| `enable_secret_rotation` | Enable automatic secret rotation | `false` | No |
| `kms_key_id` | Custom KMS key for secret encryption | `null` | No |
| `extension_cache_enabled` | Enable extension caching | `true` | No |

### Advanced Configuration

For production deployments, consider these additional configurations:

```hcl
# terraform.tfvars example for production
project_name = "myapp"
environment  = "prod"

# Enhanced security
kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
secret_recovery_window = 30

# Performance optimization
lambda_memory_size = 512
extension_cache_enabled = true
extension_cache_size = 2000

# Monitoring
additional_tags = {
  Environment = "production"
  Backup      = "required"
  Monitoring  = "critical"
}
```

## Testing and Validation

### 1. Test Lambda Function

```bash
# Test the deployed function
aws lambda invoke \
    --function-name $(terraform output -raw lambda_function_name) \
    --payload '{}' \
    response.json && cat response.json | jq .
```

Expected response:
```json
{
  "statusCode": 200,
  "body": "{\"message\":\"Secret retrieved successfully\",\"database_info\":{\"host\":\"mydb.cluster-xyz.us-east-1.rds.amazonaws.com\",\"database\":\"production\",\"username\":\"appuser\"}}"
}
```

### 2. Verify Secret Storage

```bash
# Check the secret in Secrets Manager
aws secretsmanager get-secret-value \
    --secret-id $(terraform output -raw secret_name) \
    --query 'SecretString' --output text | jq .
```

### 3. Monitor CloudWatch Logs

```bash
# View recent Lambda logs
aws logs describe-log-streams \
    --log-group-name $(terraform output -raw lambda_log_group_name) \
    --order-by LastEventTime --descending --max-items 1 \
    --query 'logStreams[0].logStreamName' --output text | \
    xargs -I {} aws logs get-log-events \
    --log-group-name $(terraform output -raw lambda_log_group_name) \
    --log-stream-name {} --limit 10
```

### 4. Performance Testing

Test caching performance with multiple invocations:

```bash
# Test extension caching (first call should be slower)
for i in {1..3}; do
    echo "Invocation $i:"
    time aws lambda invoke \
        --function-name $(terraform output -raw lambda_function_name) \
        --payload '{}' \
        response-$i.json > /dev/null 2>&1
    echo "Response: $(cat response-$i.json | jq -r '.body' | jq -r '.message')"
done
```

## Monitoring and Troubleshooting

### CloudWatch Alarms

The deployment creates two CloudWatch alarms:

1. **Lambda Errors**: Triggers when the function encounters errors
2. **Lambda Duration**: Triggers when function execution approaches timeout

### Common Issues

1. **Permission Errors**:
   ```bash
   # Check IAM role permissions
   aws iam get-role --role-name $(terraform output -raw lambda_execution_role_name)
   ```

2. **Extension Issues**:
   ```bash
   # Check Lambda layers
   aws lambda get-function --function-name $(terraform output -raw lambda_function_name) \
       --query 'Configuration.Layers'
   ```

3. **Secret Access Issues**:
   ```bash
   # Test direct secret access
   aws secretsmanager get-secret-value --secret-id $(terraform output -raw secret_name)
   ```

### Debugging

Enable detailed logging by setting the Lambda function's log level:

```bash
# Update function environment variable for debug logging
aws lambda update-function-configuration \
    --function-name $(terraform output -raw lambda_function_name) \
    --environment Variables='{
        "SECRET_NAME":"'$(terraform output -raw secret_name)'",
        "PARAMETERS_SECRETS_EXTENSION_CACHE_ENABLED":"true",
        "LOG_LEVEL":"DEBUG"
    }'
```

## Security Best Practices

This implementation follows AWS security best practices:

1. **Least Privilege IAM**: Lambda role can only access the specific secret
2. **Encryption**: Secrets encrypted at rest using AWS KMS
3. **Secure Transport**: All communication uses HTTPS/TLS
4. **No Hardcoded Secrets**: All sensitive values stored in Secrets Manager
5. **Audit Logging**: CloudTrail logs all Secrets Manager API calls
6. **Network Security**: Lambda runs in managed VPC with AWS security

### Additional Security Enhancements

For enhanced security in production:

```hcl
# Use custom KMS key
kms_key_id = aws_kms_key.secrets_key.arn

# Enable rotation
enable_secret_rotation = true
rotation_days = 30

# Increase recovery window
secret_recovery_window = 30
```

## Cost Optimization

### Estimated Monthly Costs

Based on typical usage patterns:

| Service | Usage | Monthly Cost (USD) |
|---------|-------|--------------------|
| Secrets Manager | 1 secret | $0.40 |
| Lambda | 10,000 invocations | $0.002 |
| CloudWatch Logs | 1 GB | $0.50 |
| **Total** | | **~$0.90** |

### Cost Optimization Tips

1. **Extension Caching**: Reduces Secrets Manager API calls by up to 90%
2. **Log Retention**: Set appropriate log retention (14 days default)
3. **Memory Sizing**: Use smallest memory size that meets performance needs
4. **Reserved Capacity**: Consider Savings Plans for consistent workloads

## Scaling and Production Considerations

### Performance

- **Cold Starts**: First invocation includes extension initialization (~100ms)
- **Warm Starts**: Cached secrets retrieved in ~1-5ms
- **Concurrency**: Extension supports up to 1000 concurrent executions

### Production Checklist

- [ ] Use custom KMS key for encryption
- [ ] Enable secret rotation
- [ ] Set up monitoring and alerting
- [ ] Configure appropriate log retention
- [ ] Implement error handling and retry logic
- [ ] Set up cross-region secret replication for DR
- [ ] Document secret rotation procedures
- [ ] Set up automated backups

## Cleanup

To avoid ongoing charges, destroy the infrastructure when no longer needed:

```bash
# Destroy all resources
terraform destroy

# Type 'yes' when prompted to confirm the destruction
```

**Warning**: This will permanently delete all resources including secrets. Ensure you have backups if needed.

### Selective Cleanup

To remove only specific resources:

```bash
# Remove only the Lambda function
terraform destroy -target=aws_lambda_function.secret_demo

# Remove only the secret (with immediate deletion)
terraform destroy -target=module.secrets_manager
```

## Extending the Solution

### Add Secret Rotation

```hcl
# Enable automatic rotation
enable_secret_rotation = true
rotation_days = 30

# Add rotation Lambda function
resource "aws_lambda_function" "rotation_function" {
  # Rotation function implementation
}
```

### Add API Gateway Integration

```hcl
# Add REST API
resource "aws_api_gateway_rest_api" "secrets_api" {
  name = "${local.lambda_function_name}-api"
}

# Connect Lambda to API Gateway
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.secrets_api.id
  # Integration configuration
}
```

### Multi-Environment Support

```bash
# Deploy to multiple environments
terraform workspace new staging
terraform workspace new production

# Deploy with environment-specific variables
terraform apply -var-file="staging.tfvars"
```

## Support and Resources

- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [AWS Parameters and Secrets Lambda Extension](https://docs.aws.amazon.com/secretsmanager/latest/userguide/retrieving-secrets_lambda.html)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Contributing

To contribute improvements to this Terraform configuration:

1. Test changes in a development environment
2. Validate with `terraform plan` and `terraform validate`
3. Follow AWS Well-Architected Framework principles
4. Update documentation for any new variables or outputs
5. Include cost impact analysis for significant changes

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and adapt according to your organization's requirements and policies.