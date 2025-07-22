# CloudFront Real-time Monitoring and Analytics Infrastructure

This Terraform configuration deploys a comprehensive real-time monitoring and analytics system for Amazon CloudFront using AWS services including Kinesis Data Streams, Lambda, OpenSearch Service, DynamoDB, and CloudWatch.

## Architecture Overview

The infrastructure creates:

- **CloudFront Distribution** with real-time logs configuration
- **Kinesis Data Streams** for real-time log ingestion and processing
- **Lambda Function** for log processing and enrichment
- **OpenSearch Service** for log analytics and visualization
- **DynamoDB Table** for metrics storage with TTL
- **Kinesis Data Firehose** for delivery to S3 and OpenSearch
- **S3 Buckets** for content and log storage
- **CloudWatch Dashboard** for monitoring visualization
- **IAM Roles and Policies** with least privilege access

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.0 installed
3. **Node.js** and **npm** (for Lambda function dependencies)
4. Appropriate AWS permissions for all services used

## Required AWS Permissions

The deploying user/role needs permissions for:
- CloudFront (distributions, real-time logs)
- Kinesis (streams, firehose)
- Lambda (functions, event source mappings)
- OpenSearch Service
- DynamoDB
- S3 (buckets, policies)
- IAM (roles, policies)
- CloudWatch (dashboards, logs, metrics)

## Quick Start

1. **Clone the repository and navigate to the terraform directory**:
   ```bash
   cd aws/cloudfront-realtime-monitoring-analytics/code/terraform
   ```

2. **Install Lambda function dependencies**:
   ```bash
   cd lambda
   npm install --production
   cd ..
   ```

3. **Copy and customize the variables file**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your preferred settings
   ```

4. **Initialize Terraform**:
   ```bash
   terraform init
   ```

5. **Plan the deployment**:
   ```bash
   terraform plan
   ```

6. **Apply the configuration**:
   ```bash
   terraform apply
   ```

7. **Upload sample content** (optional):
   ```bash
   # Get the content bucket name from outputs
   CONTENT_BUCKET=$(terraform output -raw s3_content_bucket_name)
   
   # Upload sample content
   aws s3 cp sample_content/ s3://$CONTENT_BUCKET/ --recursive --cache-control "max-age=3600"
   ```

## Configuration Options

### Key Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_name` | Name prefix for resources | `cf-monitoring` | No |
| `environment` | Environment name | `dev` | No |
| `kinesis_shard_count` | Main Kinesis stream shards | `2` | No |
| `opensearch_instance_type` | OpenSearch instance type | `t3.small.search` | No |
| `opensearch_allowed_ips` | IPs allowed to access OpenSearch | `["0.0.0.0/0"]` | No |
| `lambda_memory_size` | Lambda memory in MB | `512` | No |
| `cloudfront_price_class` | CloudFront price class | `PriceClass_100` | No |

### Security Considerations

- **OpenSearch Access**: Restrict `opensearch_allowed_ips` to your organization's IP ranges
- **S3 Buckets**: All buckets have public access blocked by default
- **IAM Roles**: Follow least privilege principle with minimal required permissions
- **Encryption**: Enabled by default for S3, OpenSearch, and data in transit

## Monitoring and Operations

### CloudWatch Dashboard

Access the dashboard via the URL provided in terraform outputs:
```bash
terraform output cloudwatch_dashboard_url
```

The dashboard includes:
- Real-time traffic volume and error rates
- Cache performance metrics
- Lambda processing performance
- Kinesis stream activity

### OpenSearch Dashboards

Access OpenSearch Dashboards via:
```bash
terraform output opensearch_dashboards_endpoint
```

### Cost Optimization

- **Traffic-based costs**: Real-time logs and Kinesis charges scale with traffic volume
- **Storage costs**: S3 lifecycle policies automatically move logs to cheaper storage classes
- **OpenSearch costs**: Start with t3.small instances, scale based on data volume
- **Retention policies**: DynamoDB TTL and CloudWatch log retention help control costs

## Testing and Validation

1. **Generate test traffic**:
   ```bash
   # Get CloudFront domain
   CF_DOMAIN=$(terraform output -raw cloudfront_domain_name)
   
   # Generate some requests
   for i in {1..10}; do
     curl -s "https://$CF_DOMAIN/" > /dev/null
     curl -s "https://$CF_DOMAIN/css/style.css" > /dev/null
     curl -s "https://$CF_DOMAIN/api/data" > /dev/null
     sleep 1
   done
   ```

2. **Check Kinesis metrics**:
   ```bash
   aws cloudwatch get-metric-statistics \
     --namespace AWS/Kinesis \
     --metric-name IncomingRecords \
     --dimensions Name=StreamName,Value=$(terraform output -raw kinesis_stream_name) \
     --start-time $(date -d '10 minutes ago' --iso-8601) \
     --end-time $(date --iso-8601) \
     --period 300 \
     --statistics Sum
   ```

3. **Verify Lambda processing**:
   ```bash
   aws logs filter-log-events \
     --log-group-name "/aws/lambda/$(terraform output -raw lambda_function_name)" \
     --start-time $(date -d '5 minutes ago' '+%s')000 \
     --filter-pattern "processedRecords"
   ```

## Troubleshooting

### Common Issues

1. **OpenSearch domain creation timeout**:
   - Domain creation can take 10-15 minutes
   - Monitor progress in AWS Console

2. **Lambda function permissions**:
   - Verify IAM roles have correct policies attached
   - Check CloudWatch logs for permission errors

3. **No data in streams**:
   - Ensure CloudFront distribution is receiving traffic
   - Verify real-time logs configuration is attached

4. **High costs**:
   - Monitor real-time logs volume
   - Adjust retention policies
   - Consider sampling for high-traffic sites

### Useful Commands

```bash
# Check resource status
terraform show

# Get all outputs
terraform output

# Refresh state
terraform refresh

# Destroy infrastructure (when done)
terraform destroy
```

## Cleanup

To avoid ongoing costs, destroy the infrastructure when no longer needed:

```bash
# This will delete all resources created by this configuration
terraform destroy
```

**Note**: This will permanently delete all data including logs and metrics. Ensure you have backups if needed.

## Estimated Costs

Costs vary significantly based on traffic volume and usage patterns:

- **Minimum**: ~$50/month (low traffic, minimal retention)
- **Typical**: ~$100/month (moderate traffic, standard retention)
- **High traffic**: $150+ (high volume sites, extended retention)

Main cost drivers:
- CloudFront real-time logs (per million log lines)
- Kinesis Data Streams (per shard hour + per million records)
- OpenSearch Service (instance hours + storage)
- Lambda invocations and execution time

## Support and Contributing

For issues related to this Terraform configuration:
1. Check the troubleshooting section above
2. Review AWS service documentation
3. Verify your AWS permissions and quotas

## License

This configuration is provided as-is for educational and reference purposes.