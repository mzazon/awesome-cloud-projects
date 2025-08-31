# Simple Image Metadata Extractor - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying a serverless image metadata extraction system using AWS Lambda and S3.

## Architecture Overview

The infrastructure creates:
- **S3 Bucket**: For image storage with event notifications
- **Lambda Function**: For metadata extraction using Python 3.12
- **Lambda Layer**: PIL/Pillow library for image processing
- **IAM Roles & Policies**: Least privilege access controls
- **CloudWatch Logs**: For monitoring and debugging
- **KMS Keys**: For encryption at rest (optional)
- **Dead Letter Queue**: For error handling (optional)
- **CloudWatch Alarms**: For monitoring (optional)

## Prerequisites

1. **AWS Account** with appropriate permissions for:
   - Lambda functions and layers
   - S3 buckets and notifications
   - IAM roles and policies
   - CloudWatch logs and alarms
   - KMS keys (if encryption enabled)

2. **Tools Required**:
   ```bash
   # Terraform (>= 1.6.0)
   terraform --version
   
   # AWS CLI (configured)
   aws configure list
   
   # Optional: Docker (for building Lambda layers)
   docker --version
   ```

3. **AWS Permissions**: Ensure your AWS credentials have permissions for all services used

## Quick Start

### 1. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit with your specific configuration
vi terraform.tfvars
```

### 2. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 3. Test the Deployment

```bash
# Upload a test image (use the bucket name from terraform output)
aws s3 cp test-image.jpg s3://$(terraform output -raw s3_bucket_name)/test-image.jpg

# Check the logs
aws logs tail $(terraform output -raw cloudwatch_log_group_name) --follow
```

## Configuration Options

### Basic Configuration

```hcl
# terraform.tfvars
aws_region   = "us-east-1"
project_name = "my-image-processor"
environment  = "dev"

# Lambda configuration
lambda_memory_size = 256
lambda_timeout     = 30
lambda_runtime     = "python3.12"
```

### Production Configuration

```hcl
# terraform.tfvars
environment = "prod"

# Enhanced security
enable_kms_encryption = true
enable_monitoring     = true
enable_dlq           = true

# Performance optimization
lambda_memory_size = 1024
lambda_architecture = "arm64"  # Better price-performance

# Cost optimization
enable_lifecycle_policy = true
log_retention_days     = 90
```

### Advanced Features

```hcl
# Enable VPC deployment
lambda_subnet_ids         = ["subnet-12345", "subnet-67890"]
lambda_security_group_ids = ["sg-abcdef"]

# Enable X-Ray tracing
enable_xray_tracing = true

# Configure monitoring
enable_monitoring    = true
sns_alarm_topic_arn = "arn:aws:sns:us-east-1:123456789:alerts"
```

## File Structure

```
terraform/
├── main.tf                    # Main infrastructure resources
├── variables.tf               # Variable definitions with validation
├── outputs.tf                 # Output values and usage examples
├── versions.tf                # Provider version constraints
├── terraform.tfvars.example  # Example configuration
├── lambda_function.py.tpl     # Lambda function template
└── README.md                  # This file
```

## Key Features

### Security
- **Least Privilege IAM**: Function has minimal required permissions
- **KMS Encryption**: Optional encryption for S3 and CloudWatch logs
- **S3 Security**: Public access blocked, SSL enforcement available
- **VPC Support**: Optional VPC deployment for network isolation

### Reliability
- **Dead Letter Queue**: Capture failed invocations for retry
- **CloudWatch Alarms**: Monitor errors and performance
- **S3 Versioning**: Protect against accidental deletion
- **Error Handling**: Comprehensive error handling in function code

### Performance
- **ARM64 Support**: Up to 20% better price-performance
- **Optimized Layers**: Efficient PIL/Pillow layer deployment
- **Configurable Memory**: Scale memory based on image sizes
- **Provisioned Concurrency**: Reduce cold starts (optional)

### Cost Optimization
- **Serverless**: Pay only for actual processing time
- **Lifecycle Policies**: Automatic S3 storage class transitions
- **Intelligent Tiering**: Automatic cost optimization
- **Right-sizing**: Configurable memory and timeout settings

## Usage Examples

### Upload and Process Images

```bash
# Get bucket name
BUCKET_NAME=$(terraform output -raw s3_bucket_name)

# Upload various image formats
aws s3 cp image1.jpg s3://$BUCKET_NAME/images/
aws s3 cp image2.png s3://$BUCKET_NAME/photos/
aws s3 cp image3.gif s3://$BUCKET_NAME/graphics/

# Check processing logs
aws logs tail $(terraform output -raw cloudwatch_log_group_name) --follow
```

### Monitor Performance

```bash
# Get Lambda function metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=$(terraform output -raw lambda_function_name) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum

# View error metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=$(terraform output -raw lambda_function_name) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### Test Function Directly

```bash
# Invoke function with test payload
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload '{"Records":[{"s3":{"bucket":{"name":"'$BUCKET_NAME'"},"object":{"key":"test-image.jpg"}}}]}' \
  response.json

# View response
cat response.json
```

## Troubleshooting

### Common Issues

1. **Permission Denied**:
   ```bash
   # Check IAM role permissions
   aws lambda get-policy --function-name $(terraform output -raw lambda_function_name)
   ```

2. **Layer Build Failures**:
   ```bash
   # Manually build layer (if automated build fails)
   mkdir -p layer/python
   pip install Pillow -t layer/python/
   cd layer && zip -r ../pillow_layer.zip python/
   ```

3. **S3 Notification Issues**:
   ```bash
   # Check notification configuration
   aws s3api get-bucket-notification-configuration \
     --bucket $(terraform output -raw s3_bucket_name)
   ```

### Debug Commands

```bash
# Check recent executions
aws logs filter-log-events \
  --log-group-name $(terraform output -raw cloudwatch_log_group_name) \
  --start-time $(date -d '1 hour ago' +%s)000

# Validate S3 permissions
aws s3api head-object \
  --bucket $(terraform output -raw s3_bucket_name) \
  --key test-image.jpg

# Check Lambda configuration
aws lambda get-function-configuration \
  --function-name $(terraform output -raw lambda_function_name)
```

## Cost Estimation

### AWS Free Tier Eligible
- **Lambda**: 1M free requests/month, 400,000 GB-seconds compute time
- **S3**: 5GB free storage, 20,000 GET requests, 2,000 PUT requests
- **CloudWatch**: 5GB free log ingestion, 10 custom metrics

### Estimated Monthly Costs (beyond free tier)
- **Light Usage** (100 images/month): ~$0.01-$0.05
- **Medium Usage** (10,000 images/month): ~$1-$5
- **Heavy Usage** (100,000 images/month): ~$10-$50

*Costs depend on image sizes, memory allocation, and enabled features*

## Security Considerations

### Production Checklist
- [ ] Enable KMS encryption (`enable_kms_encryption = true`)
- [ ] Review IAM policies for least privilege
- [ ] Enable CloudTrail logging for audit trails
- [ ] Configure VPC if network isolation required
- [ ] Set up monitoring and alerting
- [ ] Enable S3 versioning and lifecycle policies
- [ ] Review security groups and NACLs
- [ ] Configure backup and disaster recovery

### Compliance Features
- **Data Classification**: Configurable classification levels
- **Encryption**: At rest and in transit
- **Audit Logging**: CloudTrail integration available
- **Access Controls**: IAM-based with least privilege
- **Data Retention**: Configurable log retention periods

## Cleanup

To remove all resources:

```bash
# Destroy infrastructure
terraform destroy

# Clean up local files (optional)
rm -f terraform.tfstate*
rm -f .terraform.lock.hcl
rm -rf .terraform/
```

**Warning**: This will permanently delete all resources including stored images and logs.

## Contributing

1. Follow Terraform best practices
2. Update documentation for any changes
3. Test in development environment first
4. Use consistent naming conventions
5. Add appropriate variable validation

## Support

For issues and questions:
1. Check the troubleshooting section above
2. Review AWS service documentation
3. Check Terraform provider documentation
4. Refer to the original recipe documentation

## License

This infrastructure code is provided as part of the AWS recipe collection. Use according to your organization's policies and AWS terms of service.