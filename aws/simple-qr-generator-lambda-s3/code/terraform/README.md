# Terraform Infrastructure for Simple QR Code Generator

This directory contains Terraform Infrastructure as Code (IaC) for deploying a serverless QR code generator on AWS using Lambda, S3, and API Gateway.

## Architecture

The infrastructure creates:

- **S3 Bucket**: Stores generated QR code images with public read access
- **Lambda Function**: Python runtime that generates QR codes using the `qrcode` library
- **API Gateway**: REST API with `/generate` endpoint for QR code creation
- **IAM Role**: Lambda execution role with minimal S3 write permissions
- **CloudWatch Log Groups**: For Lambda and API Gateway access logging

## Prerequisites

- AWS CLI installed and configured with appropriate credentials
- Terraform >= 1.0 installed
- Appropriate AWS permissions for:
  - S3 bucket creation and policy management
  - Lambda function deployment
  - API Gateway configuration
  - IAM role and policy management
  - CloudWatch log group creation

## Required AWS Permissions

Your AWS credentials need the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:PutBucketPolicy",
        "s3:PutBucketPublicAccessBlock",
        "s3:PutBucketVersioning",
        "s3:PutBucketEncryption",
        "s3:PutBucketCors",
        "lambda:CreateFunction",
        "lambda:DeleteFunction",
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:AddPermission",
        "lambda:RemovePermission",
        "apigateway:*",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:PutRetentionPolicy"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Start

1. **Clone and Navigate**:
   ```bash
   cd aws/simple-qr-generator-lambda-s3/code/terraform/
   ```

2. **Initialize Terraform**:
   ```bash
   terraform init
   ```

3. **Review and Customize** (optional):
   ```bash
   # Edit terraform.tfvars to customize deployment
   cp terraform.tfvars.example terraform.tfvars
   ```

4. **Plan Deployment**:
   ```bash
   terraform plan
   ```

5. **Deploy Infrastructure**:
   ```bash
   terraform apply
   ```

6. **Test the API**:
   ```bash
   # Get the API endpoint from output
   API_URL=$(terraform output -raw api_gateway_generate_endpoint)
   
   # Test QR code generation
   curl -X POST $API_URL \
     -H "Content-Type: application/json" \
     -d '{"text": "Hello, World! This is my QR code."}'
   ```

## Configuration Options

### Required Variables

None - all variables have sensible defaults.

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region for deployment |
| `environment` | `dev` | Environment name (dev/staging/prod) |
| `project_name` | `qr-generator` | Project name for resource naming |
| `lambda_timeout` | `30` | Lambda timeout in seconds (1-900) |
| `lambda_memory_size` | `256` | Lambda memory in MB (128-10240) |
| `s3_bucket_force_destroy` | `true` | Allow S3 bucket force destroy |
| `enable_cors` | `true` | Enable CORS for web applications |
| `api_throttle_burst_limit` | `500` | API Gateway burst limit |
| `api_throttle_rate_limit` | `100` | API requests per second limit |
| `log_retention_in_days` | `14` | CloudWatch log retention period |
| `tags` | `{}` | Additional tags for resources |

### Example terraform.tfvars

```hcl
# AWS Configuration
aws_region  = "us-west-2"
environment = "prod"

# Resource Configuration
project_name        = "my-qr-generator"
lambda_timeout      = 60
lambda_memory_size  = 512

# API Configuration
api_throttle_rate_limit  = 200
api_throttle_burst_limit = 1000

# Logging Configuration
log_retention_in_days = 30

# Additional Tags
tags = {
  Owner       = "DevOps Team"
  CostCenter  = "Engineering"
  Application = "QR Code Generator"
}
```

## Usage Examples

### Basic QR Code Generation

```bash
# Generate a simple QR code
curl -X POST ${API_ENDPOINT}/generate \
  -H "Content-Type: application/json" \
  -d '{"text": "https://example.com"}'
```

### Using with JavaScript/Web Applications

```javascript
const generateQRCode = async (text) => {
  const response = await fetch('YOUR_API_ENDPOINT/generate', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ text: text })
  });
  
  const result = await response.json();
  if (response.ok) {
    return result.url; // URL to the generated QR code image
  } else {
    throw new Error(result.error);
  }
};
```

### Batch Processing with Scripts

```bash
#!/bin/bash
# Generate QR codes for a list of URLs

API_ENDPOINT="YOUR_API_ENDPOINT/generate"
URLS=("https://example1.com" "https://example2.com" "https://example3.com")

for url in "${URLS[@]}"; do
  response=$(curl -s -X POST $API_ENDPOINT \
    -H "Content-Type: application/json" \
    -d "{\"text\": \"$url\"}")
  
  qr_url=$(echo $response | jq -r '.url')
  echo "QR code for $url: $qr_url"
done
```

## Outputs

After deployment, Terraform provides these outputs:

- `api_gateway_generate_endpoint`: Full URL for QR generation
- `s3_bucket_name`: Name of the S3 bucket storing QR codes
- `lambda_function_name`: Name of the Lambda function
- `sample_curl_command`: Ready-to-use curl command for testing

## Monitoring and Troubleshooting

### CloudWatch Logs

- **Lambda Logs**: `/aws/lambda/{function-name}`
- **API Gateway Logs**: `/aws/apigateway/{api-name}`

### Common Issues

1. **Permission Denied Errors**:
   - Verify AWS credentials have sufficient permissions
   - Check IAM roles are properly attached

2. **Lambda Function Errors**:
   - Check CloudWatch logs for detailed error messages
   - Verify the qrcode library is properly packaged

3. **API Gateway 502 Errors**:
   - Ensure Lambda function exists and is invokable
   - Check API Gateway integration configuration

4. **S3 Access Issues**:
   - Verify bucket policy allows public read access
   - Check bucket exists and is in the correct region

### Debug Commands

```bash
# Check Terraform state
terraform show

# View specific resource details
terraform state show aws_lambda_function.qr_generator

# Test Lambda function directly
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload '{"text": "test"}' \
  response.json && cat response.json

# Check S3 bucket contents
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/
```

## Security Considerations

### Current Security Posture

- ✅ **Lambda Execution**: Minimal IAM permissions (S3 write only)
- ✅ **S3 Encryption**: Server-side encryption enabled (AES256)
- ✅ **API Throttling**: Rate limiting configured
- ✅ **CORS**: Configurable CORS headers
- ⚠️ **Public S3 Access**: QR codes are publicly readable
- ⚠️ **No API Authentication**: API is publicly accessible

### Production Security Enhancements

For production deployments, consider:

1. **API Authentication**:
   ```hcl
   # Add to variables.tf
   variable "enable_api_key" {
     description = "Enable API key authentication"
     type        = bool
     default     = false
   }
   ```

2. **Private S3 Access**:
   - Use CloudFront with Origin Access Control
   - Generate signed URLs instead of public access

3. **VPC Deployment**:
   - Deploy Lambda in private subnets
   - Use VPC endpoints for S3 access

4. **WAF Protection**:
   - Add AWS WAF to API Gateway
   - Implement rate limiting and IP filtering

## Cost Optimization

### Estimated Costs

For typical usage (1000 requests/month):

- **Lambda**: ~$0.20/month (requests + compute)
- **API Gateway**: ~$3.50/million requests
- **S3**: ~$0.023/GB storage + $0.0004/1000 requests
- **CloudWatch**: ~$0.50/GB logs ingested

**Total**: ~$1-5/month for light usage

### Cost Optimization Tips

1. **Adjust Lambda Memory**: Lower memory reduces costs but may increase execution time
2. **Log Retention**: Reduce CloudWatch log retention period
3. **S3 Lifecycle**: Implement lifecycle policies to archive old QR codes
4. **Reserved Capacity**: Consider Lambda reserved concurrency for predictable workloads

## Cleanup

To destroy all created resources:

```bash
# Destroy all infrastructure
terraform destroy

# Or destroy specific resources
terraform destroy -target=aws_s3_bucket.qr_bucket
```

**Warning**: This will permanently delete all QR code images stored in S3.

## Advanced Configuration

### Custom Lambda Layer

For advanced use cases, you can create a Lambda layer with the QR code dependencies:

```hcl
# Add to main.tf
resource "aws_lambda_layer_version" "qr_dependencies" {
  filename                 = "qr_layer.zip"
  layer_name              = "${local.function_name}-dependencies"
  compatible_runtimes     = ["python3.12"]
  compatible_architectures = ["x86_64"]
  
  source_code_hash = data.archive_file.layer_zip.output_base64sha256
}
```

### Multiple Environments

Use Terraform workspaces for multiple environments:

```bash
# Create environments
terraform workspace new development
terraform workspace new staging
terraform workspace new production

# Deploy to specific environment
terraform workspace select production
terraform apply -var-file="production.tfvars"
```

### State Management

For team environments, use remote state:

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "qr-generator/terraform.tfstate"
    region = "us-east-1"
  }
}
```

## Contributing

When modifying this infrastructure:

1. Run `terraform fmt` to format code
2. Run `terraform validate` to validate syntax
3. Update this README if adding new variables or outputs
4. Test changes in a development environment first

## Support

For issues with this Terraform configuration:

1. Check the [AWS Terraform Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
2. Review AWS service limits and quotas
3. Consult the original recipe documentation
4. Check Terraform and AWS CLI versions for compatibility