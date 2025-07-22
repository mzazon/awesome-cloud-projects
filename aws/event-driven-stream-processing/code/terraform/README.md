# Terraform Infrastructure for Real-Time Data Processing with Kinesis and Lambda

This Terraform configuration deploys a complete serverless real-time data processing pipeline using Amazon Kinesis Data Streams, AWS Lambda, DynamoDB, and CloudWatch.

## Architecture Overview

The infrastructure includes:

- **Amazon Kinesis Data Stream**: Ingests high-volume real-time event data
- **AWS Lambda Function**: Processes stream records and enriches data
- **Amazon DynamoDB**: Stores processed events with global secondary indexes
- **Amazon SQS**: Dead letter queue for failed event processing
- **Amazon CloudWatch**: Monitoring, logging, and alerting
- **Amazon SNS**: Optional email notifications for alerts
- **AWS IAM**: Least-privilege security roles and policies

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.5.0 installed
- Python 3.8+ (for testing the data producer)
- Appropriate AWS permissions for resource creation

## Quick Start

### 1. Clone and Navigate to Directory

```bash
cd aws/real-time-data-processing-with-kinesis-lambda/code/terraform/
```

### 2. Create Variables File

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your desired configuration
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Test the Pipeline

```bash
# Make the test producer executable
chmod +x test_data_producer.py

# Generate test events (replace stream-name with actual name from outputs)
python3 test_data_producer.py <kinesis-stream-name> 100 0.1

# Verify events in DynamoDB (replace table-name with actual name)
aws dynamodb scan --table-name <dynamodb-table-name> --limit 5
```

## Configuration Options

### Core Infrastructure Settings

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `project_name` | Project name for resource naming | `retail-events` | `my-project` |
| `environment` | Environment (dev/staging/prod) | `dev` | `prod` |
| `region` | AWS region | `us-east-1` | `us-west-2` |

### Kinesis Configuration

| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `kinesis_shard_count` | Number of stream shards | `1` | 1-1000 |
| `kinesis_retention_period` | Data retention (hours) | `24` | 24-8760 |
| `kinesis_shard_level_metrics` | Enabled metrics | `["IncomingRecords", "OutgoingRecords"]` | See AWS docs |

### Lambda Configuration

| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `lambda_memory_size` | Memory allocation (MB) | `256` | 128-10240 |
| `lambda_timeout` | Function timeout (seconds) | `120` | 1-900 |
| `lambda_batch_size` | Records per invocation | `100` | 1-10000 |
| `lambda_starting_position` | Stream reading position | `LATEST` | `LATEST`/`TRIM_HORIZON` |

### DynamoDB Configuration

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `dynamodb_billing_mode` | Billing mode | `PAY_PER_REQUEST` | `PAY_PER_REQUEST`/`PROVISIONED` |
| `dynamodb_point_in_time_recovery_enabled` | Enable PITR | `true` | `true`/`false` |
| `dynamodb_server_side_encryption_enabled` | Enable encryption | `true` | `true`/`false` |

### Monitoring Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `cloudwatch_alarm_threshold` | Failed events threshold | `10` |
| `sns_email_endpoint` | Email for notifications | `""` (optional) |

## Testing and Validation

### 1. Basic Functionality Test

```bash
# Send test events
python3 test_data_producer.py $(terraform output -raw kinesis_stream_name) 50 0.2

# Check processing results
aws dynamodb scan \
    --table-name $(terraform output -raw dynamodb_table_name) \
    --limit 5 \
    --projection-expression "userId,eventType,eventTimestamp,insight"
```

### 2. Error Handling Test

```bash
# Send invalid data to test error handling
aws kinesis put-record \
    --stream-name $(terraform output -raw kinesis_stream_name) \
    --data '{"invalid_format": true}' \
    --partition-key "test-error"

# Check dead letter queue
aws sqs receive-message \
    --queue-url $(terraform output -raw sqs_dlq_url) \
    --max-number-of-messages 5
```

### 3. Performance Test (Burst Mode)

```bash
# Generate burst traffic for auto-scaling testing
python3 test_data_producer.py $(terraform output -raw kinesis_stream_name) 0 0 --burst
```

### 4. Monitor Processing

```bash
# View Lambda logs in real-time
aws logs tail $(terraform output -raw lambda_log_group_name) --follow

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace RetailEventProcessing \
    --metric-name ProcessedEvents \
    --statistics Sum \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 300
```

## Monitoring and Troubleshooting

### CloudWatch Dashboards

Access monitoring dashboards via the URLs in the Terraform outputs:

```bash
# Get monitoring URLs
terraform output monitoring_urls
```

### Key Metrics to Monitor

- **ProcessedEvents**: Successfully processed events per minute
- **FailedEvents**: Failed processing events (triggers alarm)
- **ProcessingDuration**: Lambda execution time
- **SuccessRate**: Percentage of successfully processed events
- **BatchSize**: Number of records per Lambda invocation

### Log Analysis

```bash
# Search for errors in Lambda logs
aws logs filter-log-events \
    --log-group-name $(terraform output -raw lambda_log_group_name) \
    --filter-pattern "ERROR"

# Search for specific user events
aws logs filter-log-events \
    --log-group-name $(terraform output -raw lambda_log_group_name) \
    --filter-pattern "user-12345"
```

### Common Issues and Solutions

1. **High Error Rate**
   - Check Lambda function logs for error details
   - Verify IAM permissions for DynamoDB and SQS access
   - Review data format and validation logic

2. **Processing Delays**
   - Increase Lambda memory allocation
   - Reduce batch size for faster processing
   - Consider increasing shard count

3. **Cost Optimization**
   - Use reserved capacity for DynamoDB in production
   - Adjust Lambda memory size based on actual usage
   - Configure appropriate log retention periods

## Cost Estimation

The Terraform outputs include estimated monthly costs. Actual costs depend on:

- **Data Volume**: Number of events per second/minute
- **Processing Complexity**: Lambda execution time and memory usage
- **Storage Requirements**: DynamoDB item size and query patterns
- **Retention Settings**: CloudWatch logs and Kinesis data retention

### Cost Optimization Tips

1. **Use appropriate billing modes**:
   - DynamoDB: PAY_PER_REQUEST for variable workloads
   - DynamoDB: PROVISIONED with auto-scaling for predictable workloads

2. **Optimize Lambda configuration**:
   - Right-size memory allocation based on actual usage
   - Use appropriate batch sizes to reduce invocation overhead

3. **Configure retention policies**:
   - Set appropriate CloudWatch log retention (14 days default)
   - Configure Kinesis data retention based on replay requirements

## Security Considerations

### IAM Permissions

The Terraform configuration implements least-privilege access:

- Lambda can only read from the specific Kinesis stream
- Lambda can only write to the specific DynamoDB table and SQS queue
- CloudWatch access is limited to metrics and logs

### Encryption

- **Kinesis**: Server-side encryption with AWS managed KMS keys
- **DynamoDB**: Optional server-side encryption with customer managed KMS keys
- **SQS**: Server-side encryption with SQS managed keys
- **Lambda**: Environment variables and code are encrypted

### Network Security

All services use AWS's secure network infrastructure. For additional security:

- Deploy Lambda in VPC for network isolation
- Use VPC endpoints for service communication
- Implement API Gateway with authentication for external access

## Customization Examples

### High-Throughput Configuration

```hcl
# terraform.tfvars
kinesis_shard_count = 5
lambda_memory_size = 512
lambda_batch_size = 500
dynamodb_billing_mode = "PROVISIONED"
dynamodb_read_capacity = 100
dynamodb_write_capacity = 100
```

### Cost-Optimized Configuration

```hcl
# terraform.tfvars
kinesis_retention_period = 24
lambda_memory_size = 128
lambda_timeout = 60
cloudwatch_log_retention_days = 7
```

### Production Configuration

```hcl
# terraform.tfvars
environment = "prod"
kinesis_shard_count = 3
lambda_reserved_concurrency = 100
dynamodb_point_in_time_recovery_enabled = true
dynamodb_server_side_encryption_enabled = true
sns_email_endpoint = "alerts@company.com"
```

## Cleanup

To remove all resources:

```bash
# Destroy infrastructure
terraform destroy

# Clean up local files
rm -f terraform.tfstate*
rm -f .terraform.lock.hcl
rm -rf .terraform/
```

## Support and Troubleshooting

### Common Commands

```bash
# Get all outputs
terraform output

# Get specific output
terraform output kinesis_stream_name

# Refresh state
terraform refresh

# View state
terraform show

# Import existing resource (if needed)
terraform import aws_kinesis_stream.retail_events_stream stream-name
```

### Additional Resources

- [Amazon Kinesis Developer Guide](https://docs.aws.amazon.com/kinesis/latest/dev/)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Amazon DynamoDB Developer Guide](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or AWS service documentation.