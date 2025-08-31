# Terraform Infrastructure - JSON to CSV Converter

This directory contains Terraform Infrastructure as Code (IaC) for deploying a serverless JSON-to-CSV converter using AWS Lambda and S3. The solution automatically converts JSON files to CSV format when they are uploaded to an S3 bucket.

## Architecture Overview

The infrastructure creates:

- **Input S3 Bucket**: Receives JSON files for conversion
- **Output S3 Bucket**: Stores converted CSV files
- **Lambda Function**: Processes JSON-to-CSV conversion
- **IAM Role**: Provides least-privilege access for Lambda
- **CloudWatch Logs**: Captures function execution logs
- **S3 Event Notification**: Triggers Lambda on file uploads
- **CloudWatch Alarms**: Monitors function performance (optional)

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- AWS account with permissions for:
  - S3 (bucket creation and management)
  - Lambda (function creation and management)
  - IAM (role and policy management)
  - CloudWatch (logs and alarms)

## Quick Start

### 1. Clone and Navigate

```bash
cd terraform/
```

### 2. Configure Variables (Optional)

```bash
# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit with your preferred settings
nano terraform.tfvars
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply
```

### 4. Test the Deployment

```bash
# Create a test JSON file
echo '[{"id":1,"name":"John","email":"john@example.com"},{"id":2,"name":"Jane","email":"jane@example.com"}]' > test.json

# Upload to input bucket (use output from terraform apply)
aws s3 cp test.json s3://$(terraform output -raw input_bucket_name)/

# Check for converted CSV file
aws s3 ls s3://$(terraform output -raw output_bucket_name)/

# Download and view the CSV
aws s3 cp s3://$(terraform output -raw output_bucket_name)/test.csv ./
cat test.csv
```

## Configuration Options

### Basic Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `input_bucket_prefix` | Prefix for input S3 bucket name | `json-input` | No |
| `output_bucket_prefix` | Prefix for output S3 bucket name | `csv-output` | No |
| `lambda_function_name` | Base name for Lambda function | `json-csv-converter` | No |
| `environment` | Environment designation | `development` | No |

### Lambda Configuration

| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `lambda_runtime` | Python runtime version | `python3.12` | python3.8-3.12 |
| `lambda_timeout` | Function timeout (seconds) | `60` | 1-900 |
| `lambda_memory_size` | Memory allocation (MB) | `256` | 128-10240 |
| `lambda_architecture` | CPU architecture | `x86_64` | x86_64, arm64 |

### Monitoring Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_monitoring` | Enable CloudWatch alarms | `true` |
| `log_retention_days` | Log retention period | `30` |
| `alarm_sns_topic_arn` | SNS topic for alarm notifications | `""` |

## Environment-Specific Configurations

### Development Environment

```hcl
# terraform.tfvars
environment = "development"
lambda_memory_size = 256
lambda_timeout = 60
log_retention_days = 7
enable_monitoring = false
max_concurrent_executions = 5
```

### Production Environment

```hcl
# terraform.tfvars
environment = "production"
lambda_memory_size = 512
lambda_timeout = 300
log_retention_days = 90
enable_monitoring = true
enable_lambda_insights = true
max_concurrent_executions = 50
alarm_sns_topic_arn = "arn:aws:sns:us-east-1:123456789012:alerts"
```

## Important Outputs

After deployment, Terraform provides useful outputs:

```bash
# View all outputs
terraform output

# Get specific values
terraform output input_bucket_name
terraform output output_bucket_name
terraform output lambda_function_name

# Get CLI commands for testing
terraform output upload_command_example
terraform output download_command_example
terraform output view_logs_command
```

## Monitoring and Troubleshooting

### View Lambda Logs

```bash
# Using Terraform output
$(terraform output -raw view_logs_command)

# Or directly with AWS CLI
aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow
```

### Monitor Function Performance

```bash
# View Lambda metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Duration \
    --dimensions Name=FunctionName,Value=$(terraform output -raw lambda_function_name) \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average
```

### Debug Failed Conversions

1. Check CloudWatch logs for error messages
2. Verify JSON file format and structure
3. Ensure sufficient Lambda memory and timeout
4. Check IAM permissions for S3 access

## Cost Optimization

### Estimated Monthly Costs

For typical usage (1000 conversions/month):

- **Lambda**: ~$0.20 (1M requests free tier)
- **S3 Storage**: ~$0.50 (varies by file size)
- **CloudWatch Logs**: ~$0.10
- **Total**: ~$0.80/month

### Cost Reduction Tips

1. **Use ARM-based Lambda** for better price-performance:
   ```hcl
   lambda_architecture = "arm64"
   ```

2. **Optimize memory allocation** based on file sizes:
   ```hcl
   lambda_memory_size = 128  # For small files
   ```

3. **Reduce log retention** for development:
   ```hcl
   log_retention_days = 3
   ```

4. **Set concurrent execution limits**:
   ```hcl
   max_concurrent_executions = 5
   ```

## Security Features

The infrastructure implements several security best practices:

- **Encryption**: S3 buckets use AES-256 server-side encryption
- **Access Control**: Public access blocked on all S3 buckets
- **IAM**: Lambda role follows least-privilege principle
- **Versioning**: S3 versioning enabled for data protection
- **Logging**: Comprehensive CloudWatch logging enabled

## Backup and Recovery

### S3 Versioning

S3 versioning is enabled by default. To restore a previous version:

```bash
# List object versions
aws s3api list-object-versions --bucket $(terraform output -raw input_bucket_name)

# Restore specific version
aws s3api copy-object \
    --copy-source "$(terraform output -raw input_bucket_name)/file.json?versionId=VERSION_ID" \
    --bucket $(terraform output -raw input_bucket_name) \
    --key file.json
```

### Lambda Function Backup

Lambda function code is stored in the Terraform state and can be redeployed:

```bash
# Force function update
terraform apply -replace=aws_lambda_function.converter
```

## Scaling Considerations

### High-Volume Processing

For processing large volumes of files:

```hcl
# terraform.tfvars
lambda_memory_size = 1024
lambda_timeout = 900
max_concurrent_executions = 100
lambda_reserved_concurrency = 50
enable_lambda_insights = true
```

### Large File Processing

For large JSON files (>10MB):

```hcl
# terraform.tfvars
lambda_memory_size = 2048
lambda_timeout = 900
max_file_size_mb = 100
```

## Supported JSON Formats

The converter handles various JSON structures:

1. **Array of Objects**:
   ```json
   [{"id": 1, "name": "John"}, {"id": 2, "name": "Jane"}]
   ```

2. **Single Object**:
   ```json
   {"id": 1, "name": "John", "email": "john@example.com"}
   ```

3. **Array of Simple Values**:
   ```json
   ["value1", "value2", "value3"]
   ```

4. **Nested Objects** (flattened with dot notation):
   ```json
   {"user": {"id": 1, "profile": {"name": "John"}}}
   ```

## Cleanup

To remove all infrastructure:

```bash
# Destroy all resources
terraform destroy

# Confirm destruction
# Type 'yes' when prompted
```

**Note**: This will permanently delete all S3 buckets and their contents. Ensure you have backups of important data.

## Advanced Configuration

### Custom Lambda Layers

To add custom Python packages:

1. Create a Lambda layer with additional packages
2. Add the layer ARN to the Lambda function configuration
3. Update the Terraform configuration accordingly

### Dead Letter Queue

To handle failed processing:

```hcl
# terraform.tfvars
lambda_dead_letter_config = {
  target_arn = "arn:aws:sqs:us-east-1:123456789012:failed-conversions"
}
```

### VPC Configuration

To deploy Lambda in a VPC:

1. Add VPC and subnet configurations to `main.tf`
2. Configure security groups for Lambda
3. Ensure NAT Gateway for internet access (if needed)

## Troubleshooting

### Common Issues

1. **Permission Denied**: Check IAM policies and roles
2. **Function Timeout**: Increase timeout or optimize code
3. **Memory Issues**: Increase memory allocation
4. **File Not Found**: Verify S3 event configuration

### Getting Help

1. Check CloudWatch logs for detailed error messages
2. Review AWS Lambda documentation
3. Verify Terraform configuration syntax
4. Test with small JSON files first

## Contributing

To contribute improvements:

1. Test changes in a development environment
2. Update documentation for new features
3. Follow Terraform best practices
4. Ensure backward compatibility

## Version History

- **v1.0.0**: Initial Terraform implementation
  - Basic JSON-to-CSV conversion
  - S3 event-driven processing
  - CloudWatch monitoring
  - Security best practices