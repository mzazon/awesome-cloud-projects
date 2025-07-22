# Terraform Infrastructure for Automated Data Ingestion Pipelines

This Terraform configuration deploys a complete automated data ingestion solution on AWS using OpenSearch Ingestion, EventBridge Scheduler, and supporting services.

## Architecture Overview

The infrastructure creates:

- **Amazon S3**: Data lake for storing raw data files
- **Amazon OpenSearch Service**: Analytics platform with search capabilities
- **OpenSearch Ingestion**: Serverless data processing pipeline
- **EventBridge Scheduler**: Automated pipeline start/stop scheduling
- **IAM Roles and Policies**: Secure access control
- **CloudWatch Logs**: Comprehensive monitoring and logging

## Prerequisites

### Required Tools

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) v2 configured with appropriate credentials
- Valid AWS account with appropriate permissions

### Required AWS Permissions

Your AWS credentials must have permissions for:

- Amazon S3 (bucket creation, policy management)
- Amazon OpenSearch Service (domain creation, policy management)
- OpenSearch Ingestion (pipeline creation and management)
- EventBridge Scheduler (schedule and schedule group management)
- IAM (role and policy creation)
- CloudWatch Logs (log group creation)

### Supported AWS Regions

OpenSearch Ingestion is available in select AWS regions. Verify availability in your target region before deployment.

## Quick Start

### 1. Clone and Prepare

```bash
# Clone the repository (if not already done)
git clone <repository-url>
cd aws/automated-data-ingestion-pipelines-opensearch-eventbridge/code/terraform

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars
```

### 2. Configure Variables

Edit `terraform.tfvars` to customize your deployment:

```hcl
# Basic configuration
project_name = "my-data-ingestion"
environment  = "dev"
aws_region   = "us-east-1"

# OpenSearch configuration
opensearch_instance_type = "t3.small.search"
opensearch_ebs_volume_size = 20

# Pipeline configuration
pipeline_min_units = 1
pipeline_max_units = 4

# Security - restrict in production
allowed_cidr_blocks = ["10.0.0.0/8"]
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### 4. Verify Deployment

```bash
# Check pipeline status
aws osis get-pipeline --pipeline-name $(terraform output -raw ingestion_pipeline_name) --query 'Pipeline.Status' --output text

# List created resources
terraform state list
```

## Configuration Options

### Environment-Specific Configurations

#### Development Environment
```hcl
project_name = "analytics-dev"
environment = "dev"
opensearch_instance_type = "t3.small.search"
opensearch_instance_count = 1
pipeline_min_units = 1
pipeline_max_units = 2
delete_protection = false
```

#### Production Environment
```hcl
project_name = "analytics-prod"
environment = "prod"
opensearch_instance_type = "m6g.large.search"
opensearch_instance_count = 3
pipeline_min_units = 2
pipeline_max_units = 8
delete_protection = true
allowed_cidr_blocks = ["10.0.0.0/8"]
```

### Key Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_name` | Project name for resource naming | `"data-ingestion"` | No |
| `environment` | Environment (dev/staging/prod) | `"dev"` | No |
| `aws_region` | AWS region for deployment | `"us-east-1"` | No |
| `opensearch_instance_type` | OpenSearch instance type | `"t3.small.search"` | No |
| `pipeline_min_units` | Minimum pipeline capacity (ICUs) | `1` | No |
| `pipeline_max_units` | Maximum pipeline capacity (ICUs) | `4` | No |
| `enable_pipeline_scheduling` | Enable automated scheduling | `true` | No |
| `allowed_cidr_blocks` | CIDR blocks for OpenSearch access | `["0.0.0.0/0"]` | No |

See `variables.tf` for complete variable documentation.

## Usage Guide

### Uploading Data

After deployment, upload data to the S3 bucket:

```bash
# Get bucket name
BUCKET_NAME=$(terraform output -raw data_bucket_name)

# Upload log files
aws s3 cp my-application.log s3://${BUCKET_NAME}/logs/$(date +%Y/%m/%d)/

# Upload metrics files
aws s3 cp metrics.json s3://${BUCKET_NAME}/metrics/$(date +%Y/%m/%d)/

# Upload event data
aws s3 cp events.json s3://${BUCKET_NAME}/events/$(date +%Y/%m/%d)/
```

### Accessing OpenSearch Dashboards

```bash
# Get dashboard URL
DASHBOARD_URL=$(terraform output -raw opensearch_dashboard_url)
echo "Access OpenSearch Dashboards at: ${DASHBOARD_URL}"
```

### Monitoring Pipeline Status

```bash
# Check pipeline status
PIPELINE_NAME=$(terraform output -raw ingestion_pipeline_name)
aws osis get-pipeline --pipeline-name ${PIPELINE_NAME}

# View pipeline logs
aws logs tail /aws/osis/pipelines/${PIPELINE_NAME} --follow
```

### Managing Schedules

```bash
# List schedules
SCHEDULE_GROUP=$(terraform output -raw scheduler_group_name)
aws scheduler list-schedules --group-name ${SCHEDULE_GROUP}

# Manually start pipeline
aws osis start-pipeline --pipeline-name ${PIPELINE_NAME}

# Manually stop pipeline
aws osis stop-pipeline --pipeline-name ${PIPELINE_NAME}
```

## Data Processing Pipeline

The OpenSearch Ingestion pipeline processes data through these stages:

1. **Source**: Reads from S3 bucket with configurable prefixes
2. **Processing**: 
   - Adds ingestion timestamps
   - Parses log formats (structured and unstructured)
   - Extracts JSON data
   - Adds metadata fields
3. **Destination**: Writes to OpenSearch with date-based indexing

### Supported Data Formats

- **Structured Logs**: ISO timestamp + log level + message
- **Apache Logs**: Combined Apache log format
- **JSON Data**: Automatic parsing and field extraction
- **Raw Text**: Basic timestamp and metadata addition

### Index Patterns

Data is indexed using date-based patterns:
- `application-logs-YYYY.MM.DD`
- `system-metrics-YYYY.MM.DD`
- `events-YYYY.MM.DD`

## Security Considerations

### Access Control

- OpenSearch domain uses IP-based access policies
- IAM roles follow least-privilege principle
- S3 bucket blocks public access
- Encryption enabled for data at rest and in transit

### Production Security

For production deployments:

1. **Restrict IP Access**:
   ```hcl
   allowed_cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12"]
   ```

2. **Enable Fine-Grained Access Control**:
   ```hcl
   opensearch_master_user_name = "admin"
   opensearch_master_user_password = "SecurePassword123!"
   ```

3. **Use AWS Secrets Manager** for sensitive values:
   ```bash
   # Store password in Secrets Manager
   aws secretsmanager create-secret \
     --name "opensearch-master-password" \
     --secret-string "SecurePassword123!"
   ```

4. **Enable VPC Deployment** (requires additional VPC resources):
   ```hcl
   # Add VPC configuration to OpenSearch domain
   vpc_options {
     subnet_ids         = ["subnet-12345", "subnet-67890"]
     security_group_ids = ["sg-opensearch"]
   }
   ```

## Cost Optimization

### Development/Testing
- Use `t3.small.search` instances
- Set lower pipeline capacity (1-2 ICUs)
- Enable shorter data retention
- Disable deletion protection

### Production
- Use appropriate instance sizes for workload
- Configure auto-scaling for pipeline capacity
- Implement S3 lifecycle policies
- Monitor CloudWatch metrics for optimization

### Cost Monitoring

```bash
# View cost estimation info
terraform output cost_estimation_info

# Monitor actual costs
aws ce get-cost-and-usage \
  --time-period Start=2023-01-01,End=2023-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

## Troubleshooting

### Common Issues

1. **Pipeline Creation Fails**
   ```bash
   # Check IAM role permissions
   aws iam simulate-principal-policy \
     --policy-source-arn $(terraform output -raw ingestion_role_arn) \
     --action-names s3:GetObject \
     --resource-arns "arn:aws:s3:::bucket/*"
   ```

2. **OpenSearch Domain Timeout**
   ```bash
   # Check domain status
   aws opensearch describe-domain \
     --domain-name $(terraform output -raw opensearch_domain_name) \
     --query 'DomainStatus.Processing'
   ```

3. **Scheduler Not Working**
   ```bash
   # Check schedule status
   aws scheduler get-schedule \
     --name "start-pipeline" \
     --group-name $(terraform output -raw scheduler_group_name)
   ```

### Debugging Pipeline Issues

```bash
# View pipeline configuration
PIPELINE_NAME=$(terraform output -raw ingestion_pipeline_name)
aws osis get-pipeline --pipeline-name ${PIPELINE_NAME}

# Check pipeline logs
aws logs filter-log-events \
  --log-group-name "/aws/osis/pipelines/${PIPELINE_NAME}" \
  --start-time $(date -d "1 hour ago" +%s)000
```

### Data Processing Issues

```bash
# Check OpenSearch indices
OPENSEARCH_ENDPOINT=$(terraform output -raw opensearch_endpoint)
curl -X GET "https://${OPENSEARCH_ENDPOINT}/_cat/indices?v"

# Search for recent data
curl -X GET "https://${OPENSEARCH_ENDPOINT}/application-logs-*/_search" \
  -H "Content-Type: application/json" \
  -d '{"query": {"range": {"@timestamp": {"gte": "now-1h"}}}}'
```

## Cleanup

### Destroy Infrastructure

```bash
# Destroy all resources
terraform destroy

# Confirm destruction
terraform state list  # Should be empty
```

### Manual Cleanup (if needed)

If Terraform destroy fails:

```bash
# Empty S3 bucket first
aws s3 rm s3://$(terraform output -raw data_bucket_name) --recursive

# Delete OpenSearch domain
aws opensearch delete-domain \
  --domain-name $(terraform output -raw opensearch_domain_name)

# Then retry terraform destroy
terraform destroy
```

## Advanced Configuration

### Custom Pipeline Configuration

To modify the data processing pipeline, edit `pipeline-config.yaml`:

```yaml
# Add custom processors
processor:
  - geoip:
      source: "client_ip"
      target: "geo"
  - user_agent:
      source: "user_agent"
      target: "ua"
```

### Integration with Other Services

```hcl
# Add SNS notifications
resource "aws_sns_topic" "pipeline_alerts" {
  name = "${local.pipeline_name}-alerts"
}

# Add CloudWatch alarms
resource "aws_cloudwatch_metric_alarm" "pipeline_errors" {
  alarm_name          = "${local.pipeline_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "PipelineErrors"
  namespace           = "AWS/OSIS"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors pipeline errors"
  alarm_actions       = [aws_sns_topic.pipeline_alerts.arn]
}
```

## Support and Maintenance

### Regular Maintenance Tasks

1. **Monitor Pipeline Performance**
   ```bash
   # Check pipeline metrics
   aws cloudwatch get-metric-statistics \
     --namespace AWS/OSIS \
     --metric-name ProcessedRecords \
     --start-time $(date -d "24 hours ago" -u +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 3600 \
     --statistics Sum
   ```

2. **Review Access Logs**
   ```bash
   # Check OpenSearch access logs
   aws logs filter-log-events \
     --log-group-name "/aws/opensearch/domains/$(terraform output -raw opensearch_domain_name)/ES_APPLICATION_LOGS"
   ```

3. **Update Security Policies**
   ```bash
   # Review IAM policies regularly
   aws iam get-role-policy \
     --role-name $(terraform output -raw ingestion_role_name) \
     --policy-name opensearch-ingestion-policy
   ```

### Version Updates

When updating Terraform or AWS provider versions:

1. Update `versions.tf`
2. Run `terraform init -upgrade`
3. Test in development environment
4. Review planned changes carefully
5. Apply updates during maintenance window

## References

- [Amazon OpenSearch Service Documentation](https://docs.aws.amazon.com/opensearch-service/)
- [OpenSearch Ingestion User Guide](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/ingestion.html)
- [EventBridge Scheduler User Guide](https://docs.aws.amazon.com/scheduler/latest/UserGuide/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Data Prepper Configuration Reference](https://opensearch.org/docs/latest/data-prepper/)

---

For additional support or questions about this infrastructure configuration, refer to the original recipe documentation or AWS support resources.