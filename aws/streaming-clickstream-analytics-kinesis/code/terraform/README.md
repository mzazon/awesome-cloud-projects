# Real-time Clickstream Analytics with Kinesis Data Streams and Lambda - Terraform

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete real-time clickstream analytics pipeline on AWS.

## Architecture Overview

This solution implements a serverless, real-time analytics pipeline that processes clickstream events using:

- **Amazon Kinesis Data Streams** - Real-time data ingestion with configurable shards
- **AWS Lambda** - Serverless event processing and anomaly detection
- **Amazon DynamoDB** - NoSQL storage for real-time metrics and session data
- **Amazon S3** - Long-term storage and archival of raw clickstream data
- **Amazon CloudWatch** - Monitoring, metrics, and operational dashboards
- **Amazon SNS** - Optional alerting for anomaly detection (configurable)

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform** v1.0 or later installed
3. **AWS IAM permissions** for creating the following resources:
   - Kinesis Data Streams
   - Lambda functions and IAM roles
   - DynamoDB tables
   - S3 buckets
   - CloudWatch dashboards and log groups
   - SNS topics (optional)
   - SQS queues

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd aws/real-time-clickstream-analytics-kinesis-data-analytics/code/terraform/
```

### 2. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your specific configuration
nano terraform.tfvars
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

### 4. Verify Deployment

```bash
# Check the outputs
terraform output

# Verify Kinesis stream is active
aws kinesis describe-stream --stream-name $(terraform output -raw kinesis_stream_name)
```

## Configuration

### Essential Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for deployment | `us-east-1` | No |
| `environment` | Environment name (dev/staging/prod) | `dev` | No |
| `project_name` | Project name for resource naming | `clickstream-analytics` | No |

### Kinesis Configuration

| Variable | Description | Default | Notes |
|----------|-------------|---------|-------|
| `kinesis_shard_count` | Number of Kinesis shards | `2` | Each shard: 1K records/sec write, 2MB/sec read |
| `kinesis_retention_period` | Data retention in hours | `24` | Min: 24, Max: 8760 hours |

### Lambda Configuration

| Variable | Description | Default | Notes |
|----------|-------------|---------|-------|
| `lambda_memory_size` | Memory allocation in MB | `256` | Higher memory = better performance |
| `lambda_timeout` | Function timeout in seconds | `60` | Max: 900 seconds |
| `batch_size` | Records per Lambda invocation | `100` | Balance latency vs throughput |

### Feature Toggles

| Variable | Description | Default | Notes |
|----------|-------------|---------|-------|
| `enable_anomaly_detection` | Deploy anomaly detection function | `true` | Adds second Lambda for pattern analysis |
| `enable_sns_alerts` | Create SNS topic for alerts | `false` | Requires email configuration |
| `enable_cloudwatch_dashboard` | Create monitoring dashboard | `true` | Recommended for production |

## Outputs

After successful deployment, Terraform provides these key outputs:

### Infrastructure Resources
- `kinesis_stream_name` - Name of the data stream for event ingestion
- `kinesis_stream_arn` - ARN for programmatic access
- `s3_bucket_name` - Bucket for raw data archival
- `lambda_event_processor_function_name` - Main processing function

### Database Tables
- `dynamodb_page_metrics_table_name` - Page view aggregations
- `dynamodb_session_metrics_table_name` - Session-level metrics
- `dynamodb_counters_table_name` - Real-time counters

### Monitoring
- `cloudwatch_dashboard_url` - Direct link to monitoring dashboard
- `sns_topic_arn` - Alert topic ARN (if enabled)

## Testing the Solution

### 1. Generate Test Events

Use the AWS CLI to send sample events:

```bash
# Get the stream name
STREAM_NAME=$(terraform output -raw kinesis_stream_name)

# Send a test event
aws kinesis put-record \
    --stream-name $STREAM_NAME \
    --partition-key "test-session-123" \
    --data '{
        "event_type": "page_view",
        "session_id": "test-session-123",
        "user_id": "user-456",
        "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'",
        "page_url": "/products",
        "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "ip_address": "192.168.1.100"
    }'
```

### 2. Verify Processing

```bash
# Check Lambda logs
aws logs tail /aws/lambda/$(terraform output -raw lambda_event_processor_function_name) --follow

# Query DynamoDB for processed data
aws dynamodb scan \
    --table-name $(terraform output -raw dynamodb_counters_table_name) \
    --limit 5
```

### 3. Monitor Metrics

```bash
# View CloudWatch dashboard
echo "Dashboard URL: $(terraform output -raw cloudwatch_dashboard_url)"

# Check custom metrics
aws cloudwatch get-metric-statistics \
    --namespace "Clickstream/Events" \
    --metric-name "EventsProcessed" \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Scaling Considerations

### Performance Tuning

1. **Kinesis Shards**: Each shard handles 1,000 records/second. Scale shards based on expected throughput.

2. **Lambda Concurrency**: Default regional limit is 1,000 concurrent executions. Request increases for high-volume scenarios.

3. **DynamoDB**: Using pay-per-request billing mode auto-scales. Consider provisioned mode for predictable workloads.

### Cost Optimization

1. **S3 Lifecycle**: Automatically transitions old data to cheaper storage classes
2. **DynamoDB TTL**: Automatically expires old metrics to control storage costs
3. **CloudWatch Logs**: 14-day retention for Lambda logs reduces long-term storage costs

## Security Features

### Data Protection
- **Encryption at Rest**: All storage services use AWS-managed encryption
- **Encryption in Transit**: HTTPS/TLS for all API communications
- **Access Control**: IAM roles follow least-privilege principle

### Network Security
- **VPC**: Can be deployed in private subnets (modify main.tf)
- **Security Groups**: Lambda functions have minimal network access
- **Bucket Policies**: S3 bucket blocks all public access

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   # Check IAM role permissions
   aws iam get-role-policy --role-name $(terraform output -raw lambda_execution_role_name) --policy-name clickstream-lambda-policy
   ```

2. **Lambda Function Errors**
   ```bash
   # View detailed logs
   aws logs filter-log-events \
       --log-group-name "/aws/lambda/$(terraform output -raw lambda_event_processor_function_name)" \
       --start-time $(date -d '1 hour ago' +%s)000
   ```

3. **Kinesis Stream Issues**
   ```bash
   # Check stream status
   aws kinesis describe-stream --stream-name $(terraform output -raw kinesis_stream_name)
   ```

### Performance Issues

1. **High Latency**: Increase Lambda memory or reduce batch size
2. **Throttling**: Scale Kinesis shards or Lambda concurrency
3. **DynamoDB Errors**: Check for hot partitions or throttling

## Cleanup

To remove all resources and avoid ongoing charges:

```bash
# Destroy the infrastructure
terraform destroy

# Confirm when prompted
```

**Warning**: This will permanently delete all data in DynamoDB tables and S3 buckets.

## Cost Estimation

### Monthly Cost Breakdown (Moderate Usage: 1M events/day)

| Service | Component | Estimated Cost |
|---------|-----------|----------------|
| Kinesis Data Streams | 2 shards × 24h × 30 days | ~$22 |
| Lambda | 1M invocations + compute time | ~$8 |
| DynamoDB | Pay-per-request (1M writes) | ~$15 |
| S3 | Storage + requests | ~$3 |
| CloudWatch | Logs + metrics + dashboard | ~$5 |
| **Total** | | **~$53/month** |

*Costs vary by region and actual usage patterns. Use AWS Pricing Calculator for precise estimates.*

## Advanced Features

### Custom Metrics

Add custom CloudWatch metrics by modifying the Lambda functions:

```javascript
// In lambda_functions/event_processor.js
await cloudwatch.putMetricData({
    Namespace: 'Clickstream/Business',
    MetricData: [{
        MetricName: 'ConversionEvents',
        Value: 1,
        Unit: 'Count',
        Dimensions: [{
            Name: 'ProductCategory',
            Value: event.product_category
        }]
    }]
}).promise();
```

### Anomaly Detection Rules

Customize anomaly detection in `lambda_functions/anomaly_detector.js`:

```javascript
// Add new anomaly check
async function checkGeographicAnomalies(event) {
    // Implement IP-based geographic anomaly detection
    // Flag unusual geographic patterns
}
```

## Support and Documentation

- **AWS Kinesis Documentation**: https://docs.aws.amazon.com/kinesis/
- **AWS Lambda Documentation**: https://docs.aws.amazon.com/lambda/
- **DynamoDB Documentation**: https://docs.aws.amazon.com/dynamodb/
- **Terraform AWS Provider**: https://registry.terraform.io/providers/hashicorp/aws/

For issues with this Terraform configuration, refer to the original recipe documentation or open an issue in the project repository.