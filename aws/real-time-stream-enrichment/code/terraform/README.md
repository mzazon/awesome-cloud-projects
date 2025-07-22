# Terraform Infrastructure for Real-Time Stream Enrichment

This Terraform configuration deploys a complete real-time stream enrichment pipeline using AWS Kinesis Data Firehose and EventBridge Pipes.

## Architecture Overview

The infrastructure creates a serverless data processing pipeline that:

1. **Ingests** streaming data via Kinesis Data Stream
2. **Processes** events through EventBridge Pipes
3. **Enriches** data using Lambda function with DynamoDB lookups
4. **Delivers** enriched data to S3 for analytics

## Components Deployed

### Core Services
- **Kinesis Data Stream**: Ingests raw streaming events
- **EventBridge Pipes**: Orchestrates the enrichment pipeline
- **Lambda Function**: Enriches events with reference data
- **DynamoDB Table**: Stores reference data for enrichment
- **Kinesis Data Firehose**: Delivers enriched data to S3
- **S3 Bucket**: Stores enriched data with partitioning

### Supporting Resources
- **IAM Roles & Policies**: Least-privilege access for all services
- **CloudWatch Log Groups**: Centralized logging for monitoring
- **CloudWatch Alarms**: Basic monitoring for error detection
- **S3 Lifecycle Policies**: Cost optimization for long-term storage

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0 installed
- Sufficient AWS permissions to create:
  - IAM roles and policies
  - Kinesis streams and Firehose delivery streams
  - Lambda functions
  - DynamoDB tables
  - S3 buckets
  - EventBridge Pipes
  - CloudWatch resources

## Quick Start

### 1. Initialize Terraform

```bash
cd terraform/
terraform init
```

### 2. Review and Customize Variables

Copy the example variables file and customize for your environment:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your desired configuration:

```hcl
# Core Configuration
aws_region   = "us-west-2"
project_name = "my-stream-enrichment"
environment  = "dev"

# Resource Configuration
kinesis_stream_mode = "ON_DEMAND"
lambda_memory_size  = 512
populate_sample_data = true
```

### 3. Plan and Apply

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Test the Pipeline

After deployment, use the output commands to test:

```bash
# Send a test event to Kinesis
aws kinesis put-record \
    --stream-name $(terraform output -raw kinesis_stream_name) \
    --data $(echo '{"eventId":"test-001","productId":"PROD-001","quantity":5,"timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' | base64) \
    --partition-key "PROD-001"

# Check for enriched data in S3
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/enriched-data/ --recursive

# Monitor Lambda logs
aws logs tail $(terraform output -raw lambda_log_group_name) --follow
```

## Configuration Variables

### Core Settings

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for deployment | `us-east-1` | No |
| `project_name` | Project name for resource naming | `stream-enrichment` | No |
| `environment` | Environment (dev/staging/prod) | `dev` | No |

### Kinesis Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `kinesis_stream_mode` | Stream capacity mode | `ON_DEMAND` | No |
| `kinesis_shard_count` | Number of shards (PROVISIONED mode) | `1` | No |
| `kinesis_retention_period` | Data retention in hours | `24` | No |

### Lambda Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `lambda_memory_size` | Memory allocation in MB | `256` | No |
| `lambda_timeout` | Function timeout in seconds | `60` | No |
| `lambda_runtime` | Python runtime version | `python3.11` | No |

### DynamoDB Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `dynamodb_billing_mode` | Billing mode | `PAY_PER_REQUEST` | No |
| `populate_sample_data` | Add sample reference data | `true` | No |
| `enable_point_in_time_recovery` | Enable PITR | `true` | No |

### Storage Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `s3_bucket_prefix` | S3 bucket name prefix | `stream-enrichment-data` | No |
| `firehose_buffer_size` | Buffer size in MB | `5` | No |
| `firehose_buffer_interval` | Buffer interval in seconds | `300` | No |

## Outputs

The Terraform configuration provides comprehensive outputs for integration and testing:

### Resource Identifiers
- `kinesis_stream_name`: Name of the Kinesis Data Stream
- `s3_bucket_name`: Name of the S3 bucket
- `lambda_function_name`: Name of the enrichment Lambda function
- `dynamodb_table_name`: Name of the reference data table

### ARNs for Integration
- `kinesis_stream_arn`: Full ARN of the Kinesis stream
- `lambda_function_arn`: Full ARN of the Lambda function
- `eventbridge_pipe_arn`: Full ARN of the EventBridge Pipe

### Test Commands
- `test_commands`: Ready-to-use CLI commands for testing

## Security Features

### Data Protection
- **Encryption at rest**: S3, DynamoDB, and Kinesis encryption enabled
- **Encryption in transit**: All service communications use TLS
- **S3 public access blocking**: Prevents accidental public exposure

### Access Control
- **Least privilege IAM**: Each service has minimal required permissions
- **Role-based access**: Separate roles for each service component
- **Resource-specific policies**: Permissions scoped to exact resources

### Monitoring
- **CloudWatch alarms**: Monitor Lambda errors and stream activity
- **Centralized logging**: All logs collected in CloudWatch
- **Audit trail**: All API calls logged via CloudTrail (if enabled)

## Cost Optimization

### Included Optimizations
- **S3 lifecycle policies**: Automatic transition to cheaper storage classes
- **On-demand pricing**: Kinesis and DynamoDB scale with usage
- **Right-sized Lambda**: Configurable memory allocation
- **Efficient buffering**: Optimized Firehose delivery settings

### Cost Factors
- **Kinesis Data Stream**: Based on shard hours or on-demand usage
- **Lambda**: Pay per invocation and execution time
- **DynamoDB**: Based on read/write requests (on-demand)
- **S3**: Storage, requests, and data transfer costs
- **Firehose**: Data delivery volume

## Monitoring and Troubleshooting

### CloudWatch Metrics
- **Lambda**: Duration, errors, invocations, concurrent executions
- **Kinesis**: Incoming records, iterator age, write throughput
- **DynamoDB**: Consumed read/write capacity, throttles
- **Firehose**: Delivery success/failure, record processing

### Log Analysis
```bash
# Lambda execution logs
aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow

# EventBridge Pipes logs
aws logs tail /aws/events/pipes/$(terraform output -raw eventbridge_pipe_name) --follow

# Firehose delivery logs  
aws logs tail /aws/kinesisfirehose/$(terraform output -raw project_name)-s3-delivery --follow
```

### Common Issues

#### Lambda Timeout Errors
- Increase `lambda_timeout` variable
- Check DynamoDB performance and capacity
- Review Lambda memory allocation

#### Firehose Delivery Failures
- Verify S3 bucket permissions
- Check IAM role policies
- Review buffer size and interval settings

#### Missing Reference Data
- Verify DynamoDB table has sample data
- Check Lambda function logs for lookup errors
- Ensure IAM permissions for DynamoDB access

## Customization

### Adding More Reference Data
```bash
# Add items to DynamoDB table
aws dynamodb put-item \
    --table-name $(terraform output -raw dynamodb_table_name) \
    --item '{
        "productId": {"S": "PROD-004"},
        "productName": {"S": "Custom Device"},
        "category": {"S": "Custom Category"},
        "price": {"N": "99.99"}
    }'
```

### Modifying Lambda Function
1. Edit `lambda_function.py.tpl`
2. Run `terraform apply` to update the function
3. Test with new event structure

### Adding Data Format Conversion
Enable Parquet conversion in Firehose for better analytics performance:
```hcl
# In main.tf, modify the firehose configuration
data_format_conversion_configuration {
  enabled = true
  output_format_configuration {
    serializer {
      parquet_ser_de {}
    }
  }
  schema_configuration {
    database_name = "your_glue_database"
    table_name    = "your_glue_table"
  }
}
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete all data in S3 and DynamoDB. Ensure you have backups if needed.

## Support

For issues with this Terraform configuration:
1. Check the [AWS documentation](https://docs.aws.amazon.com/) for service-specific guidance
2. Review CloudWatch logs for error details
3. Validate IAM permissions are correctly configured
4. Ensure all prerequisites are met

## Contributing

To contribute improvements:
1. Test changes in a development environment
2. Validate with `terraform plan` and `terraform validate`
3. Update documentation for any new variables or outputs
4. Follow Terraform best practices for resource organization