# Real-time Anomaly Detection Infrastructure - Terraform

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete real-time anomaly detection system on AWS using Kinesis Data Streams, Managed Service for Apache Flink, CloudWatch, and SNS.

## Architecture Overview

The infrastructure includes:

- **Kinesis Data Streams**: High-throughput data ingestion
- **Managed Service for Apache Flink**: Real-time stream processing and anomaly detection
- **Kinesis Data Firehose**: Data archival to S3
- **S3 Bucket**: Application artifacts and processed data storage
- **Lambda Function**: Anomaly processing and alerting
- **SNS Topic**: Alert notifications with KMS encryption
- **CloudWatch**: Monitoring, logging, and alarming
- **IAM Roles**: Secure access control with least privilege

## Prerequisites

1. **AWS CLI**: Installed and configured with appropriate permissions
2. **Terraform**: Version 1.0 or later installed
3. **AWS Permissions**: The following AWS services permissions are required:
   - Kinesis Data Streams
   - Managed Service for Apache Flink (Kinesis Analytics V2)
   - Lambda
   - S3
   - SNS
   - CloudWatch
   - IAM
   - KMS

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd aws/real-time-anomaly-detection-kinesis-data-analytics/code/terraform/

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your specific configuration
vim terraform.tfvars
```

### 2. Initialize and Plan

```bash
# Initialize Terraform
terraform init

# Review the execution plan
terraform plan

# Optional: Save the plan for review
terraform plan -out=tfplan
```

### 3. Deploy

```bash
# Apply the configuration
terraform apply

# Or apply with saved plan
terraform apply tfplan
```

### 4. Start the Flink Application

After deployment, start the Flink application:

```bash
# Get the application name from Terraform outputs
FLINK_APP_NAME=$(terraform output -raw flink_application_name)

# Start the application
aws kinesisanalyticsv2 start-application \
    --application-name $FLINK_APP_NAME \
    --run-configuration '{"FlinkRunConfiguration": {"AllowNonRestoredState": true}}'
```

## Configuration Variables

### Required Variables

- `aws_region`: AWS region for deployment
- `environment`: Environment name (dev/staging/prod)
- `project_name`: Project identifier for resource naming

### Key Optional Variables

- `kinesis_stream_shard_count`: Number of Kinesis shards (default: 2)
- `flink_parallelism`: Flink application parallelism (default: 2)
- `anomaly_threshold_multiplier`: Anomaly detection sensitivity (default: 3.0)
- `notification_email`: Email for anomaly alerts (optional)
- `cloudwatch_log_retention_days`: Log retention period (default: 14)

See `terraform.tfvars.example` for complete configuration options.

## Testing the Deployment

### 1. Send Test Data

```bash
# Get stream name from outputs
STREAM_NAME=$(terraform output -raw kinesis_stream_name)

# Send a normal transaction
aws kinesis put-record \
    --stream-name $STREAM_NAME \
    --data '{"userId":"user001","amount":100.0,"timestamp":1234567890000,"transactionId":"txn-001","merchantId":"merchant-001"}' \
    --partition-key user001

# Send an anomalous transaction (high amount)
aws kinesis put-record \
    --stream-name $STREAM_NAME \
    --data '{"userId":"user001","amount":10000.0,"timestamp":1234567890000,"transactionId":"txn-002","merchantId":"merchant-001"}' \
    --partition-key user001
```

### 2. Monitor Results

```bash
# Check Flink application logs
LOG_GROUP=$(terraform output -raw cloudwatch_log_group_name)
aws logs describe-log-streams --log-group-name $LOG_GROUP

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace "AnomalyDetection" \
    --metric-name "AnomalyCount" \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum

# Subscribe to SNS notifications
SNS_TOPIC_ARN=$(terraform output -raw sns_topic_arn)
aws sns subscribe \
    --topic-arn $SNS_TOPIC_ARN \
    --protocol email \
    --notification-endpoint your-email@example.com
```

## Monitoring and Troubleshooting

### CloudWatch Dashboard

A CloudWatch dashboard is automatically created with key metrics:
- Kinesis stream throughput
- Anomaly detection counts
- Lambda function performance

### Log Groups

- Flink Application: `/aws/kinesis-analytics/[app-name]`
- Lambda Function: `/aws/lambda/[function-name]`

### Common Issues

1. **Flink Application Won't Start**
   - Check IAM permissions
   - Verify Kinesis stream is active
   - Review application logs

2. **No Anomaly Alerts**
   - Verify SNS subscription is confirmed
   - Check anomaly threshold settings
   - Review test data format

3. **High Costs**
   - Reduce Flink parallelism
   - Decrease Kinesis shard count
   - Adjust CloudWatch log retention

## Security Features

- **Encryption**: KMS encryption for S3, SNS, and CloudWatch logs
- **IAM**: Least privilege access with resource-specific policies
- **VPC**: Optional VPC deployment (uncomment in main.tf)
- **Monitoring**: Comprehensive CloudWatch monitoring and alerting

## Cost Optimization

### Estimated Monthly Costs (us-east-1)

- **Kinesis Data Streams**: ~$20-40 (2 shards)
- **Managed Service for Apache Flink**: ~$80-160 (2 KPUs)
- **Lambda**: ~$1-5 (based on invocations)
- **S3**: ~$1-10 (based on storage)
- **CloudWatch**: ~$5-15 (logs and metrics)

**Total**: ~$107-230/month for moderate throughput

### Cost Reduction Tips

1. Use fewer Kinesis shards for lower throughput
2. Reduce Flink parallelism for smaller workloads
3. Adjust log retention periods
4. Use S3 lifecycle policies for old data

## Customization

### Adding Additional Data Sources

Modify the Flink application configuration in `main.tf` to add more input streams or change processing logic.

### Enhanced Anomaly Detection

Replace the simple threshold-based detection with machine learning models by:
1. Integrating with Amazon SageMaker
2. Using more sophisticated algorithms
3. Adding feature engineering

### Multi-Region Deployment

For high availability:
1. Deploy to multiple regions
2. Use cross-region replication for S3
3. Implement failover mechanisms

## Cleanup

To avoid ongoing charges:

```bash
# Stop the Flink application first
aws kinesisanalyticsv2 stop-application --application-name $FLINK_APP_NAME

# Destroy the infrastructure
terraform destroy
```

**Note**: Ensure you want to delete all resources, as this action is irreversible.

## Support

For issues with this infrastructure:

1. Check the [AWS Managed Service for Apache Flink documentation](https://docs.aws.amazon.com/kinesisanalytics/)
2. Review [Terraform AWS Provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
3. Refer to the original recipe documentation

## Contributing

When modifying this infrastructure:

1. Follow Terraform best practices
2. Update variable descriptions and validation
3. Test in a development environment first
4. Update this README with any changes