# Terraform Infrastructure for Document Analysis with Amazon Textract

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete document analysis solution using Amazon Textract. The infrastructure supports both synchronous and asynchronous document processing with intelligent workflow orchestration.

## Architecture Overview

The solution creates:
- **S3 Buckets**: Input and output storage for documents and results
- **Lambda Functions**: Document classification, processing, and querying
- **Step Functions**: Workflow orchestration for complex processing
- **DynamoDB Table**: Metadata storage with GSI for querying
- **SNS Topic**: Notifications and async job completion handling
- **IAM Roles**: Secure access with least privilege principles
- **CloudWatch Logs**: Comprehensive logging and monitoring

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for:
  - S3 bucket creation and management
  - Lambda function deployment
  - IAM role and policy management
  - DynamoDB table creation
  - Step Functions state machine creation
  - SNS topic creation
  - CloudWatch log group creation

## Quick Start

### 1. Initialize Terraform

```bash
cd terraform/
terraform init
```

### 2. Review and Customize Variables

Copy the example variables file and customize as needed:

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values
```

### 3. Plan the Deployment

```bash
terraform plan
```

### 4. Deploy the Infrastructure

```bash
terraform apply
```

### 5. Verify the Deployment

```bash
# Check S3 buckets
aws s3 ls | grep textract-analysis

# Check Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `textract-analysis`)].FunctionName'

# Check DynamoDB table
aws dynamodb list-tables --query 'TableNames[?contains(@, `textract-analysis`)]'
```

## Configuration Variables

### Core Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_name` | Project name for resource naming | `textract-analysis` | No |
| `environment` | Environment (dev/staging/prod) | `dev` | No |
| `aws_region` | AWS region for deployment | `us-east-1` | No |

### S3 Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `input_bucket_name` | Input bucket name (auto-generated if empty) | `""` | No |
| `output_bucket_name` | Output bucket name (auto-generated if empty) | `""` | No |
| `s3_bucket_versioning` | Enable S3 versioning | `true` | No |
| `s3_lifecycle_enabled` | Enable lifecycle management | `true` | No |

### Lambda Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `lambda_runtime` | Lambda runtime version | `python3.9` | No |
| `lambda_timeout` | Function timeout (seconds) | `300` | No |
| `lambda_memory_size` | Memory allocation (MB) | `512` | No |
| `lambda_log_retention_days` | Log retention period | `14` | No |

### Security Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_s3_encryption` | Enable S3 encryption | `true` | No |
| `enable_dynamodb_encryption` | Enable DynamoDB encryption | `true` | No |
| `enable_enhanced_monitoring` | Enable CloudWatch alarms | `true` | No |

## Usage Examples

### Upload and Process Documents

```bash
# Get bucket names from Terraform output
INPUT_BUCKET=$(terraform output -raw input_bucket_name)
OUTPUT_BUCKET=$(terraform output -raw output_bucket_name)

# Upload a document for processing
aws s3 cp sample-invoice.pdf s3://${INPUT_BUCKET}/documents/

# Check processing status
aws dynamodb scan --table-name $(terraform output -raw metadata_table_name)

# Download results
aws s3 cp s3://${OUTPUT_BUCKET}/results/ ./results/ --recursive
```

### Query Document Metadata

```bash
# Get the query function name
QUERY_FUNCTION=$(terraform output -raw document_query_function_name)

# Query by document type
aws lambda invoke \
    --function-name ${QUERY_FUNCTION} \
    --payload '{"documentType": "invoice"}' \
    response.json

# Query specific document
aws lambda invoke \
    --function-name ${QUERY_FUNCTION} \
    --payload '{"documentId": "your-document-id"}' \
    response.json
```

### Monitor Processing

```bash
# Check Step Functions executions
aws stepfunctions list-executions \
    --state-machine-arn $(terraform output -raw step_functions_state_machine_arn)

# View Lambda logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/textract-analysis"
```

## Outputs

The Terraform configuration provides comprehensive outputs:

- **Resource Names**: All created resource names and ARNs
- **Usage Instructions**: Commands for uploading documents and viewing results
- **Verification Commands**: Commands to verify successful deployment
- **Integration Endpoints**: ARNs and endpoints for external integrations
- **Cost Optimization Tips**: Recommendations for cost management
- **Security Features**: Summary of enabled security features

## Cost Optimization

### Estimated Monthly Costs (US East 1)

- **Lambda**: $0.20 per 1 million requests + $0.0000166667 per GB-second
- **S3**: $0.023 per GB Standard storage + request charges
- **DynamoDB**: Pay-per-request pricing (default) or provisioned capacity
- **Textract**: $1.50 per 1,000 pages (synchronous), $15.00 per 1,000 pages (asynchronous with tables/forms)
- **Step Functions**: $0.025 per 1,000 state transitions

### Cost Optimization Features

1. **S3 Lifecycle Policies**: Automatically transition old documents to cheaper storage classes
2. **DynamoDB TTL**: Automatically expire old metadata records
3. **CloudWatch Log Retention**: Configurable log retention periods
4. **Lambda Memory Optimization**: Configurable memory allocation per function

## Security Features

### Implemented Security Controls

- **IAM Least Privilege**: Roles with minimal required permissions
- **S3 Encryption**: AES-256 encryption at rest (configurable)
- **DynamoDB Encryption**: Server-side encryption (configurable)
- **SNS Encryption**: AWS managed KMS encryption
- **S3 Public Access Block**: Prevents accidental public exposure
- **VPC Endpoints**: Consider adding for enhanced security (not included)

### Security Best Practices

1. **Enable CloudTrail**: Monitor API calls and changes
2. **Use VPC Endpoints**: Reduce internet traffic for AWS service calls
3. **Implement WAF**: Protect any web interfaces (if added)
4. **Regular Security Reviews**: Audit IAM policies and access patterns
5. **Enable GuardDuty**: Monitor for malicious activity

## Monitoring and Troubleshooting

### CloudWatch Alarms

The solution includes optional CloudWatch alarms for:
- Lambda function errors
- DynamoDB throttling
- Custom application metrics

### Log Analysis

```bash
# View classifier logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/textract-analysis-dev-document-classifier" \
    --start-time $(date -d '1 hour ago' +%s)000

# View processor logs
aws logs filter-log-events \
    --log-group-name "/aws/lambda/textract-analysis-dev-textract-processor" \
    --start-time $(date -d '1 hour ago' +%s)000
```

### Common Issues

1. **Document Upload Fails**: Check S3 bucket permissions and event configuration
2. **Processing Timeout**: Increase Lambda timeout or switch to async processing
3. **High Textract Costs**: Monitor page counts and enable lifecycle policies
4. **DynamoDB Throttling**: Consider switching to provisioned capacity

## Cleanup

To destroy all created resources:

```bash
# Remove all objects from S3 buckets first
aws s3 rm s3://$(terraform output -raw input_bucket_name) --recursive
aws s3 rm s3://$(terraform output -raw output_bucket_name) --recursive

# Destroy infrastructure
terraform destroy
```

## Advanced Configuration

### Custom Lambda Layers

To add dependencies or custom libraries:

1. Create a Lambda layer with required packages
2. Modify the Lambda function configurations in `main.tf`
3. Add layer ARN to the `layers` parameter

### API Gateway Integration

To expose the query function via REST API:

1. Add API Gateway resources to `main.tf`
2. Create appropriate IAM permissions
3. Configure CORS and authentication

### Multi-Region Deployment

For high availability across regions:

1. Duplicate the Terraform configuration
2. Modify bucket names for global uniqueness
3. Implement cross-region replication
4. Use Route 53 for traffic routing

## Support and Contributing

For issues and feature requests:
1. Check the original recipe documentation
2. Review AWS service limits and quotas
3. Examine CloudWatch logs for detailed error messages
4. Consult AWS Textract documentation for service-specific guidance

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Ensure compliance with your organization's security and governance requirements before deploying to production environments.