# DynamoDB Streams Real-time Processing Infrastructure

This Terraform configuration deploys a complete real-time database change stream processing solution using Amazon DynamoDB Streams and AWS Lambda.

## Architecture Overview

The infrastructure includes:

- **DynamoDB Table**: User activities table with streams enabled
- **Lambda Function**: Stream processor for real-time event handling
- **SNS Topic**: Notifications for alerts and events
- **S3 Bucket**: Audit log storage with lifecycle policies
- **SQS Queue**: Dead letter queue for failed processing
- **CloudWatch**: Monitoring, logging, and alerting
- **IAM Roles/Policies**: Least-privilege security configuration

## Prerequisites

1. **AWS CLI**: Installed and configured with appropriate credentials
2. **Terraform**: Version 1.0 or later
3. **AWS Permissions**: IAM permissions for:
   - DynamoDB (tables, streams)
   - Lambda (functions, event source mappings)
   - IAM (roles, policies)
   - S3 (buckets, objects)
   - SNS (topics, subscriptions)
   - SQS (queues)
   - CloudWatch (alarms, log groups)

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository>
cd aws/real-time-database-change-streams-dynamodb-streams/code/terraform
```

### 2. Configure Variables

```bash
# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit variables to match your requirements
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

### 4. Confirm Email Subscription (if enabled)

If you enabled email notifications, check your email and confirm the SNS subscription.

## Configuration Options

### Core Settings

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `environment` | Environment name | `development` | No |
| `project_name` | Project name for resources | `stream-processing` | No |
| `table_name` | DynamoDB table name | `UserActivities` | No |

### DynamoDB Settings

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `read_capacity` | DynamoDB read capacity units | `5` | No |
| `write_capacity` | DynamoDB write capacity units | `5` | No |
| `stream_view_type` | Stream view type | `NEW_AND_OLD_IMAGES` | No |

### Lambda Settings

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `lambda_runtime` | Python runtime version | `python3.9` | No |
| `lambda_memory_size` | Memory allocation (MB) | `256` | No |
| `lambda_timeout` | Function timeout (seconds) | `60` | No |

### Notification Settings

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_email_notifications` | Enable email alerts | `false` | No |
| `notification_email` | Email for notifications | `""` | Yes (if email enabled) |

## Testing the Infrastructure

### 1. Insert Test Data

```bash
# Get table name from Terraform output
TABLE_NAME=$(terraform output -raw dynamodb_table_name)

# Insert a test record
aws dynamodb put-item \
    --table-name $TABLE_NAME \
    --item '{
        "UserId": {"S": "test-user-001"},
        "ActivityId": {"S": "login-001"},
        "ActivityType": {"S": "LOGIN"},
        "Timestamp": {"N": "'$(date +%s)'"},
        "IPAddress": {"S": "192.168.1.100"},
        "UserAgent": {"S": "Mozilla/5.0"}
    }'
```

### 2. Verify Processing

```bash
# Check Lambda logs
aws logs filter-log-events \
    --log-group-name $(terraform output -raw lambda_log_group_name) \
    --start-time $(date -d '5 minutes ago' +%s)000 \
    --filter-pattern 'Processing'

# Check S3 audit logs
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/audit-logs/ --recursive

# Check for any dead letter queue messages
aws sqs receive-message --queue-url $(terraform output -raw dlq_url)
```

### 3. Test Error Handling

```bash
# Get function name
FUNCTION_NAME=$(terraform output -raw lambda_function_name)

# Temporarily break the function (invalid SNS ARN)
aws lambda update-function-configuration \
    --function-name $FUNCTION_NAME \
    --environment Variables='{"SNS_TOPIC_ARN":"invalid-arn","S3_BUCKET_NAME":"'$(terraform output -raw s3_bucket_name)'"}'

# Insert data to trigger error
aws dynamodb put-item \
    --table-name $TABLE_NAME \
    --item '{
        "UserId": {"S": "error-test"},
        "ActivityId": {"S": "error-001"},
        "ActivityType": {"S": "ERROR_TEST"},
        "Timestamp": {"N": "'$(date +%s)'"}
    }'

# Wait and check DLQ
sleep 30
aws sqs receive-message --queue-url $(terraform output -raw dlq_url)

# Restore function (get SNS ARN from Terraform)
aws lambda update-function-configuration \
    --function-name $FUNCTION_NAME \
    --environment Variables='{"SNS_TOPIC_ARN":"'$(terraform output -raw sns_topic_arn)'","S3_BUCKET_NAME":"'$(terraform output -raw s3_bucket_name)'"}'
```

## Monitoring and Alerting

### CloudWatch Alarms

The infrastructure includes several CloudWatch alarms:

1. **Lambda Errors**: Triggers on function errors
2. **Dead Letter Queue Messages**: Alerts when messages accumulate
3. **Lambda Duration**: Warns when execution time is high
4. **DynamoDB Throttles**: Monitors for capacity issues

### Key Metrics to Monitor

- Lambda invocations and errors
- DynamoDB consumed capacity
- S3 storage utilization
- Dead letter queue message count

## Cost Optimization

### Cost Factors

1. **DynamoDB**: Provisioned capacity (consider on-demand for variable workloads)
2. **Lambda**: Invocations and compute time
3. **S3**: Storage and request costs
4. **CloudWatch**: Log retention and alarm costs

### Optimization Tips

1. **Right-size Lambda**: Monitor memory usage and adjust
2. **DynamoDB Auto Scaling**: Consider enabling for variable loads
3. **S3 Lifecycle**: Automatically transition to cheaper storage classes
4. **Log Retention**: Adjust based on compliance requirements

## Security Considerations

### Implemented Security Features

- **Encryption**: All services use server-side encryption
- **IAM**: Least privilege access with resource-specific policies
- **VPC**: Lambda uses AWS managed VPC (consider custom VPC for sensitive workloads)
- **S3**: Public access blocked, versioning enabled

### Additional Security Recommendations

1. **KMS**: Consider customer-managed keys for sensitive data
2. **VPC**: Deploy Lambda in private subnet for isolation
3. **Secrets**: Use AWS Secrets Manager for sensitive configuration
4. **Access Logging**: Enable CloudTrail for audit trails

## Troubleshooting

### Common Issues

1. **IAM Permissions**: Ensure sufficient permissions for all services
2. **Lambda Timeout**: Increase timeout if processing takes longer
3. **DynamoDB Throttling**: Increase provisioned capacity or enable auto-scaling
4. **Email Subscription**: Confirm SNS email subscription

### Debugging Commands

```bash
# Check event source mapping status
aws lambda list-event-source-mappings \
    --function-name $(terraform output -raw lambda_function_name)

# Get detailed table information
aws dynamodb describe-table \
    --table-name $(terraform output -raw dynamodb_table_name)

# Check Lambda function configuration
aws lambda get-function \
    --function-name $(terraform output -raw lambda_function_name)
```

## Cleanup

To destroy all resources:

```bash
# Destroy infrastructure
terraform destroy

# Confirm destruction
terraform show
```

**Warning**: This will permanently delete all resources and data. Ensure you have backups if needed.

## Advanced Configuration

### Custom VPC Deployment

To deploy Lambda in a custom VPC, uncomment and configure the VPC settings in `main.tf`:

```hcl
vpc_config {
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids
}
```

### Auto Scaling DynamoDB

Consider replacing provisioned capacity with on-demand billing:

```hcl
billing_mode = "PAY_PER_REQUEST"
```

### Multi-Region Deployment

For multi-region deployment:

1. Use DynamoDB Global Tables
2. Deploy Lambda in multiple regions
3. Configure cross-region SNS topics
4. Implement region-specific S3 buckets

## Support and Contributions

For issues or improvements:

1. Check the troubleshooting section
2. Review AWS service limits
3. Consult AWS documentation
4. Submit issues or pull requests

## License

This infrastructure code is provided under the same license as the parent project.