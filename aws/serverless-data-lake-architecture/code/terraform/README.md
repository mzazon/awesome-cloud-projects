# Terraform Infrastructure for Advanced Serverless Data Lake Architecture

This Terraform configuration deploys a comprehensive serverless data lake architecture on AWS using Lambda layers, Glue, and EventBridge for advanced data processing workflows.

## Architecture Overview

The infrastructure creates:

- **S3 Buckets**: Raw data ingestion, processed data storage, and quarantine storage
- **Lambda Layer**: Shared utilities and dependencies for data processing functions
- **Lambda Functions**: Data ingestion, validation, and quality monitoring
- **EventBridge**: Custom event bus with rules for workflow orchestration
- **Glue Components**: Data catalog database and crawler for schema discovery
- **DynamoDB**: Metadata storage for data lineage and quality tracking
- **IAM Roles**: Least-privilege access for all services
- **CloudWatch**: Logging and monitoring for all components

## Prerequisites

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform** >= 1.0 installed
3. **AWS Account** with permissions to create:
   - S3 buckets and objects
   - Lambda functions and layers
   - EventBridge custom buses and rules
   - Glue databases and crawlers
   - DynamoDB tables
   - IAM roles and policies
   - CloudWatch log groups

## Quick Start

### 1. Initialize Terraform

```bash
cd terraform/
terraform init
```

### 2. Review and Customize Variables

Create a `terraform.tfvars` file to customize the deployment:

```hcl
# terraform.tfvars
project_name    = "my-data-lake"
environment     = "dev"
aws_region      = "us-east-1"
s3_force_destroy = true  # Set to true for dev environments
```

### 3. Plan the Deployment

```bash
terraform plan
```

### 4. Deploy the Infrastructure

```bash
terraform apply
```

When prompted, type `yes` to confirm the deployment.

### 5. Verify Deployment

```bash
# Check deployed resources
terraform output

# Test data upload (use output values)
aws s3 cp test-data.json s3://$(terraform output -raw s3_bucket_raw_name)/input/test-data.json
```

## Configuration Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for deployment | `us-east-1` | No |
| `project_name` | Project name prefix for resources | `advanced-serverless-datalake` | No |
| `environment` | Environment (dev, staging, prod) | `dev` | No |
| `lambda_runtime` | Lambda runtime version | `python3.9` | No |
| `lambda_timeout` | Lambda timeout in seconds | `300` | No |
| `lambda_memory_size` | Lambda memory in MB | `512` | No |
| `s3_force_destroy` | Force destroy S3 buckets | `false` | No |
| `enable_xray_tracing` | Enable X-Ray tracing | `true` | No |
| `cloudwatch_logs_retention_days` | Log retention period | `14` | No |

## Key Outputs

After deployment, Terraform provides important resource identifiers:

```bash
# S3 bucket names for data upload
terraform output s3_bucket_raw_name
terraform output s3_bucket_processed_name
terraform output s3_bucket_quarantine_name

# Lambda function names for monitoring
terraform output lambda_data_ingestion_function_name
terraform output lambda_data_validation_function_name
terraform output lambda_quality_monitoring_function_name

# DynamoDB table for metadata queries
terraform output dynamodb_metadata_table_name

# EventBridge bus for custom events
terraform output eventbridge_custom_bus_name

# Testing commands
terraform output testing_commands
```

## Testing the Deployment

### 1. Create Test Data

```bash
# Create valid JSON test data
cat > test-data.json << 'EOF'
{
    "id": "12345",
    "timestamp": "2024-01-15T10:30:00Z",
    "data": {
        "temperature": 23.5,
        "humidity": 65.2,
        "location": "sensor-01"
    },
    "email": "test@example.com",
    "phone": "+1-555-123-4567",
    "metadata": {
        "source": "iot-device",
        "version": "1.0"
    }
}
EOF
```

### 2. Upload Test Data

```bash
# Upload to trigger the pipeline
RAW_BUCKET=$(terraform output -raw s3_bucket_raw_name)
aws s3 cp test-data.json s3://${RAW_BUCKET}/input/test-data.json
```

### 3. Monitor Processing

```bash
# Check processed data (should appear after ~30 seconds)
PROCESSED_BUCKET=$(terraform output -raw s3_bucket_processed_name)
aws s3 ls s3://${PROCESSED_BUCKET}/validated/ --recursive

# Check quarantine bucket (should be empty for valid data)
QUARANTINE_BUCKET=$(terraform output -raw s3_bucket_quarantine_name)
aws s3 ls s3://${QUARANTINE_BUCKET}/quarantine/ --recursive

# Query processing metadata
METADATA_TABLE=$(terraform output -raw dynamodb_metadata_table_name)
aws dynamodb scan --table-name ${METADATA_TABLE} --max-items 5
```

### 4. Test Invalid Data

```bash
# Create invalid test data
cat > invalid-data.json << 'EOF'
{
    "id": "67890",
    "data": {
        "temperature": "invalid"
    },
    "email": "invalid-email",
    "phone": "invalid-phone"
}
EOF

# Upload invalid data
aws s3 cp invalid-data.json s3://${RAW_BUCKET}/input/invalid-data.json

# Check quarantine bucket after processing
sleep 30
aws s3 ls s3://${QUARANTINE_BUCKET}/quarantine/ --recursive
```

### 5. Monitor CloudWatch Metrics

```bash
# Check data quality metrics
aws cloudwatch get-metric-statistics \
    --namespace "DataLake/Quality" \
    --metric-name "ValidationSuccessRate" \
    --dimensions Name=Pipeline,Value=$(terraform output -raw deployment_info | jq -r '.project_name') \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Average
```

## Monitoring and Observability

### CloudWatch Log Groups

- `/aws/lambda/{project-name}-data-ingestion-{suffix}`
- `/aws/lambda/{project-name}-data-validation-{suffix}`
- `/aws/lambda/{project-name}-quality-monitoring-{suffix}`

### CloudWatch Metrics

Namespace: `DataLake/Quality`

- `ValidationSuccessRate` - Percentage of data passing validation
- `AverageQualityScore` - Average quality score across processed data
- `ProcessedRecords` - Total number of processed records

### X-Ray Tracing

When enabled, provides distributed tracing across Lambda functions and AWS services.

## Security Features

- **Encryption**: All S3 buckets use server-side encryption (AES256)
- **IAM**: Least-privilege access with dedicated roles for Lambda and Glue
- **Versioning**: S3 bucket versioning enabled for data protection
- **VPC**: Can be deployed in VPC for network isolation (modify configuration)

## Customization

### Adding New Lambda Functions

1. Create the function code in a new template file
2. Add the archive data source and Lambda function resource
3. Update IAM permissions as needed
4. Add EventBridge rules and targets if required

### Modifying Data Validation Rules

Edit `lambda_validation_code.py` to customize:
- Required field validation
- Data type checking
- Quality scoring algorithms
- Business rule enforcement

### Extending Monitoring

Add custom CloudWatch metrics in `lambda_quality_code.py`:
- Processing latency
- Error rates by data type
- Custom business metrics

## Cost Optimization

- **Lambda**: Pay-per-request pricing with automatic scaling
- **S3**: Intelligent tiering can be enabled for cost optimization
- **DynamoDB**: On-demand billing mode minimizes costs for variable workloads
- **EventBridge**: Pay-per-event pricing with no idle costs
- **Glue**: Crawler runs on schedule to minimize costs

## Cleanup

To remove all deployed resources:

```bash
# Destroy infrastructure
terraform destroy

# Clean up local files
rm -f test-data.json invalid-data.json
```

**Warning**: This will permanently delete all data in S3 buckets if `s3_force_destroy` is enabled.

## Troubleshooting

### Common Issues

1. **Lambda Layer Import Errors**
   - Ensure the layer includes all required dependencies
   - Check Lambda runtime compatibility

2. **EventBridge Rule Not Triggering**
   - Verify event patterns match published events
   - Check Lambda function permissions

3. **S3 Event Notifications Not Working**
   - Confirm Lambda permissions for S3 invocation
   - Verify S3 notification configuration

4. **Glue Crawler Failures**
   - Check IAM permissions for S3 and Glue catalog
   - Verify S3 path contains valid data files

### Debugging Steps

```bash
# Check Lambda function logs
aws logs describe-log-streams \
    --log-group-name "/aws/lambda/$(terraform output -raw lambda_data_ingestion_function_name)" \
    --order-by LastEventTime --descending

# Check EventBridge metrics
aws cloudwatch get-metric-statistics \
    --namespace "AWS/Events" \
    --metric-name "MatchedEvents" \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum

# Verify IAM permissions
aws iam simulate-principal-policy \
    --policy-source-arn $(terraform output -raw lambda_execution_role_arn) \
    --action-names s3:GetObject \
    --resource-arns $(terraform output -raw s3_bucket_raw_arn)/*
```

## Support

For issues with this Terraform configuration:

1. Check the [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
2. Review the original recipe documentation
3. Consult AWS service documentation for specific resource configurations
4. Use Terraform's built-in validation and planning features

## Version History

- **v1.0**: Initial Terraform implementation
- **v1.1**: Added comprehensive monitoring and testing capabilities
- **v1.2**: Enhanced security and compliance features