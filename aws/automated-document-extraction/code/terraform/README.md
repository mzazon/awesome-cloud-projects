# Terraform Infrastructure for AWS Intelligent Document Processing with Amazon Textract

This Terraform configuration deploys a complete document processing pipeline using Amazon Textract, S3, and Lambda. The infrastructure automatically processes documents uploaded to S3 and extracts text, tables, and forms using machine learning.

## Architecture Overview

The solution creates:

- **S3 Bucket**: Secure storage for documents and processing results
- **Lambda Function**: Serverless document processor using Amazon Textract
- **IAM Roles & Policies**: Least-privilege security configuration
- **CloudWatch Monitoring**: Logging and alerting for operational visibility
- **Event-Driven Architecture**: Automatic processing when documents are uploaded

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- AWS account with permissions for S3, Lambda, IAM, CloudWatch, and Textract services
- Basic understanding of Terraform and AWS services

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd aws/intelligent-document-processing-amazon-textract/code/terraform/
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review and Customize Configuration

Copy the example variables file and customize as needed:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` to match your requirements:

```hcl
project_name = "my-document-processor"
environment  = "dev"
enable_monitoring = true
tags = {
  Owner = "MyTeam"
  Cost_Center = "Engineering"
}
```

### 4. Plan and Deploy

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 5. Test the Deployment

After deployment, upload a test document:

```bash
# Get the S3 bucket name from outputs
BUCKET_NAME=$(terraform output -raw s3_bucket_name)

# Upload a test document
aws s3 cp test-document.pdf s3://$BUCKET_NAME/documents/

# Check processing results after a few moments
aws s3 ls s3://$BUCKET_NAME/results/
```

## Configuration Variables

### Required Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `project_name` | Project name for resource naming | `string` | `textract-processor` |
| `environment` | Environment (dev, staging, prod) | `string` | `dev` |

### Optional Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| `lambda_timeout` | Lambda timeout in seconds | `number` | `60` |
| `lambda_memory_size` | Lambda memory in MB | `number` | `256` |
| `enable_monitoring` | Enable CloudWatch alarms | `bool` | `true` |
| `log_retention_days` | CloudWatch log retention | `number` | `14` |
| `supported_formats` | Supported document formats | `list(string)` | `["pdf", "png", "jpg", "jpeg", "tiff", "txt"]` |

See `variables.tf` for a complete list of configuration options.

## Outputs

The configuration provides comprehensive outputs for integration and monitoring:

| Output | Description |
|--------|-------------|
| `s3_bucket_name` | S3 bucket name for document storage |
| `lambda_function_name` | Lambda function name |
| `documents_upload_path` | S3 path for uploading documents |
| `results_download_path` | S3 path for downloading results |
| `useful_commands` | AWS CLI commands for common operations |

## Usage Examples

### Upload and Process Documents

```bash
# Upload documents to trigger processing
aws s3 cp my-document.pdf s3://$(terraform output -raw s3_bucket_name)/documents/

# List processing results
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/results/

# Download results
aws s3 cp s3://$(terraform output -raw s3_bucket_name)/results/my-document.pdf_results.json ./
```

### Monitor Processing

```bash
# View Lambda logs
aws logs tail $(terraform output -raw cloudwatch_log_group_name) --follow

# Check Lambda metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=$(terraform output -raw lambda_function_name) \
  --start-time 2023-01-01T00:00:00Z \
  --end-time 2023-01-02T00:00:00Z \
  --period 3600 \
  --statistics Sum
```

### Invoke Lambda Directly

```bash
# Create test event
cat > test-event.json << 'EOF'
{
  "Records": [
    {
      "s3": {
        "bucket": {
          "name": "BUCKET_NAME"
        },
        "object": {
          "key": "documents/test-document.pdf"
        }
      }
    }
  ]
}
EOF

# Replace BUCKET_NAME and invoke
sed -i "s/BUCKET_NAME/$(terraform output -raw s3_bucket_name)/" test-event.json
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload file://test-event.json \
  response.json
```

## Security Considerations

### IAM Permissions

The infrastructure follows the principle of least privilege:

- Lambda execution role has minimal permissions for S3 and Textract
- S3 bucket blocks all public access
- CloudWatch logs are encrypted

### Data Protection

- S3 server-side encryption is enabled by default
- Document versioning provides audit trails
- Processing results include confidence scores for validation

### Network Security

For enhanced security in production environments, consider:

- Deploying Lambda in a VPC (configure `vpc_id` and `subnet_ids` variables)
- Using VPC endpoints for AWS services
- Implementing additional encryption with KMS (set `enable_kms_encryption = true`)

## Cost Optimization

### Storage Costs

- S3 Intelligent Tiering is enabled by default for cost optimization
- Configure lifecycle policies via `transition_to_ia_days` and `transition_to_glacier_days`

### Compute Costs

- Lambda pricing is based on execution time and memory allocation
- Optimize `lambda_memory_size` based on document processing requirements
- Monitor duration metrics to identify optimization opportunities

### Textract Costs

- Textract charges per page analyzed (~$1.50 per 1000 pages)
- The solution intelligently chooses between DetectDocumentText (cheaper) and AnalyzeDocument (more features)
- Monitor processing costs via CloudWatch and AWS Cost Explorer

## Monitoring and Troubleshooting

### CloudWatch Alarms

When `enable_monitoring = true`, the infrastructure creates alarms for:

- Lambda function errors (threshold: 5 errors)
- Lambda function duration (threshold: 45 seconds)

### Log Analysis

Lambda function logs include:

- Processing status and timing
- Confidence scores for extracted text
- Error details with stack traces
- Document metadata and statistics

### Common Issues

| Issue | Solution |
|-------|----------|
| Document not processed | Check file format is supported, verify S3 event notifications |
| Low confidence scores | Review document quality, consider image preprocessing |
| Lambda timeouts | Increase `lambda_timeout` or `lambda_memory_size` |
| Permission errors | Verify IAM role has required Textract and S3 permissions |

## Advanced Configuration

### VPC Deployment

For private network deployment:

```hcl
vpc_id = "vpc-xxxxxxxxx"
subnet_ids = ["subnet-xxxxxxxxx", "subnet-yyyyyyyyy"]
security_group_ids = ["sg-xxxxxxxxx"]
```

### Enhanced Monitoring

Enable X-Ray tracing for detailed performance analysis:

```hcl
enable_x_ray_tracing = true
enable_enhanced_monitoring = true
```

### Custom Alarm Actions

Configure SNS notifications for alarms:

```hcl
alarm_actions = ["arn:aws:sns:us-east-1:123456789012:my-alerts-topic"]
```

## Cleanup

To destroy the infrastructure and avoid ongoing costs:

```bash
# Remove all resources
terraform destroy

# Confirm deletion
terraform show
```

**Note**: S3 bucket contents are not automatically deleted. If the bucket contains important data, back it up before running `terraform destroy`.

## Support and Contributing

### Documentation

- [Amazon Textract Documentation](https://docs.aws.amazon.com/textract/)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

### Getting Help

1. Check the troubleshooting section above
2. Review CloudWatch logs for detailed error information
3. Consult AWS service documentation for service-specific issues
4. Open an issue in the repository for infrastructure-related problems

### Best Practices

- Use Terraform workspaces for multiple environments
- Store Terraform state in a remote backend (S3 + DynamoDB)
- Tag all resources consistently for cost tracking and management
- Regularly review and update provider versions
- Test changes in non-production environments first

## License

This infrastructure code is provided under the same license as the recipe repository.