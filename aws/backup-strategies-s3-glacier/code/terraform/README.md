# Terraform Infrastructure for AWS Backup Strategies with S3 and Glacier

This Terraform configuration deploys a comprehensive backup strategy solution using Amazon S3 with intelligent lifecycle transitions to Glacier storage classes, automated backup scheduling with Lambda functions, and event-driven notifications through EventBridge.

## Architecture Overview

The solution implements:
- **S3 Storage Tiers**: Automated lifecycle management transitioning data through Standard, Infrequent Access, Glacier, and Deep Archive
- **Lambda Orchestration**: Serverless backup function handling validation, metrics, and notifications
- **EventBridge Scheduling**: Daily and weekly automated backup triggers
- **Cross-Region Replication**: Optional disaster recovery protection
- **CloudWatch Monitoring**: Comprehensive metrics, alarms, and dashboards
- **SNS Notifications**: Email alerts for backup status and failures

## Prerequisites

1. **AWS CLI**: Installed and configured with appropriate credentials
2. **Terraform**: Version 1.8 or later
3. **AWS Permissions**: Required permissions for S3, Lambda, EventBridge, IAM, CloudWatch, and SNS
4. **Email Access**: For SNS notification confirmations (if email notifications enabled)

## Required AWS Permissions

Your AWS credentials must have permissions for:
- S3: Bucket management, lifecycle policies, replication, intelligent tiering
- Lambda: Function creation, execution roles, permissions
- IAM: Role and policy management
- EventBridge: Rule creation and target management
- CloudWatch: Metrics, alarms, dashboards, log groups
- SNS: Topic creation and subscription management

## Quick Start

### 1. Clone and Navigate

```bash
# Navigate to the terraform directory
cd aws/backup-strategies-s3-glacier/code/terraform/
```

### 2. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your specific values
nano terraform.tfvars
```

### 3. Initialize Terraform

```bash
# Initialize Terraform and download providers
terraform init
```

### 4. Plan Deployment

```bash
# Review the planned infrastructure changes
terraform plan
```

### 5. Deploy Infrastructure

```bash
# Apply the configuration
terraform apply
```

### 6. Confirm Email Subscription

If you configured `notification_email`, check your email and confirm the SNS subscription.

## Configuration Options

### Core Settings

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | Primary AWS region | `us-east-1` | No |
| `dr_region` | Disaster recovery region | `us-west-2` | No |
| `environment` | Environment name | `demo` | No |
| `owner` | Infrastructure owner | `backup-team` | No |

### Storage Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `backup_bucket_prefix` | S3 bucket name prefix | `backup-strategy` | No |
| `enable_cross_region_replication` | Enable disaster recovery | `true` | No |
| `enable_intelligent_tiering` | Enable cost optimization | `true` | No |

### Lifecycle Policy Settings

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `lifecycle_transition_ia_days` | Days to Infrequent Access | `30` | No |
| `lifecycle_transition_glacier_days` | Days to Glacier | `90` | No |
| `lifecycle_transition_deep_archive_days` | Days to Deep Archive | `365` | No |
| `noncurrent_version_expiration_days` | Noncurrent version retention | `2555` | No |

### Backup Scheduling

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `backup_schedule_daily` | Daily backup cron expression | `cron(0 2 * * ? *)` | No |
| `backup_schedule_weekly` | Weekly backup cron expression | `cron(0 1 ? * SUN *)` | No |

### Monitoring Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `notification_email` | Email for notifications | `""` (disabled) | No |
| `cloudwatch_log_retention_days` | Log retention period | `14` | No |
| `backup_alarm_threshold_failure` | Failure alarm threshold | `1` | No |
| `backup_alarm_threshold_duration` | Duration alarm threshold (seconds) | `600` | No |

## Post-Deployment Steps

### 1. Verify Deployment

```bash
# Check key outputs
terraform output backup_bucket_name
terraform output backup_lambda_function_name
terraform output backup_notifications_topic_arn
```

### 2. Test Backup Function

```bash
# Get the Lambda function name
FUNCTION_NAME=$(terraform output -raw backup_lambda_function_name)

# Test the backup function
aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload '{"backup_type":"test","source_prefix":"test/"}' \
    response.json

# Check the response
cat response.json
```

### 3. Upload Test Data

```bash
# Get the bucket name
BUCKET_NAME=$(terraform output -raw backup_bucket_name)

# Create test data
echo "Test backup data - $(date)" > test-data.txt

# Upload to S3
aws s3 cp test-data.txt s3://$BUCKET_NAME/data/test-data.txt

# Clean up local file
rm test-data.txt
```

### 4. Monitor Dashboard

Access the CloudWatch dashboard using the URL from outputs:

```bash
terraform output backup_dashboard_url
```

### 5. Verify Notifications

If email notifications are configured, trigger a test backup and verify you receive notifications.

## Cost Optimization

### Storage Cost Savings

The lifecycle policy automatically reduces storage costs:
- **Standard → IA (30 days)**: ~45% cost reduction
- **IA → Glacier (90 days)**: ~70% cost reduction  
- **Glacier → Deep Archive (365 days)**: ~95% cost reduction

### Intelligent Tiering

When enabled, S3 Intelligent Tiering automatically optimizes costs for the `intelligent-tier/` prefix by monitoring access patterns.

### Lambda Costs

Lambda costs are minimal due to:
- Event-driven execution (only runs during scheduled backups)
- Efficient Python runtime
- Configurable memory and timeout settings

## Security Features

### Data Protection
- **Encryption at Rest**: AES-256 server-side encryption
- **Versioning**: Protection against accidental deletions
- **Public Access Blocking**: Prevents unauthorized access
- **Cross-Region Replication**: Geographic redundancy

### Access Control
- **IAM Roles**: Least privilege access for Lambda functions
- **Resource-Based Policies**: Granular S3 permissions
- **Service-to-Service Authentication**: No hardcoded credentials

### Monitoring
- **CloudWatch Metrics**: Custom backup metrics
- **Alarms**: Automated failure detection
- **Notifications**: Immediate alert delivery
- **Audit Logging**: CloudWatch Logs for troubleshooting

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   # Verify AWS credentials
   aws sts get-caller-identity
   
   # Check IAM permissions
   aws iam simulate-principal-policy --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) --action-names s3:CreateBucket
   ```

2. **Lambda Function Errors**
   ```bash
   # Check CloudWatch logs
   aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/backup-orchestrator"
   
   # Get recent log events
   aws logs filter-log-events --log-group-name "/aws/lambda/backup-orchestrator-XXXXX"
   ```

3. **S3 Bucket Creation Issues**
   ```bash
   # Verify bucket name uniqueness
   aws s3api head-bucket --bucket your-bucket-name
   
   # Check region configuration
   aws configure get region
   ```

4. **Cross-Region Replication Problems**
   ```bash
   # Verify DR region bucket exists
   aws s3api head-bucket --bucket your-dr-bucket-name --region us-west-2
   
   # Check replication status
   aws s3api get-bucket-replication --bucket your-source-bucket
   ```

### Debugging Commands

```bash
# View all resources created
terraform state list

# Get detailed resource information
terraform state show aws_s3_bucket.backup_bucket

# Check Terraform logs
export TF_LOG=DEBUG
terraform plan
```

## Cleanup

### Destroy Infrastructure

```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy
```

**Warning**: This will permanently delete all backup data. Ensure you have exported any necessary data before destroying.

### Manual Cleanup (if needed)

If Terraform destroy fails due to non-empty S3 buckets:

```bash
# Empty the backup bucket
aws s3 rm s3://your-backup-bucket-name --recursive

# Empty the DR bucket (if exists)
aws s3 rm s3://your-dr-bucket-name --recursive

# Then retry terraform destroy
terraform destroy
```

## Advanced Configuration

### Custom Lambda Function

To customize the Lambda function behavior:

1. Modify `lambda_function.py`
2. Update the archive data source
3. Redeploy with `terraform apply`

### Additional Storage Classes

To add more storage classes to the lifecycle policy:

```hcl
# Add to lifecycle configuration
transition {
  days          = 180
  storage_class = "GLACIER_IR"  # Glacier Instant Retrieval
}
```

### Multi-Region Deployment

Deploy to multiple regions by:

1. Using Terraform workspaces
2. Parameterizing region-specific values
3. Managing state files separately

## Support and Documentation

- **AWS S3 Lifecycle Documentation**: https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html
- **AWS Lambda Documentation**: https://docs.aws.amazon.com/lambda/
- **EventBridge Documentation**: https://docs.aws.amazon.com/eventbridge/
- **Terraform AWS Provider**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs

## Contributing

When modifying this Terraform configuration:

1. Follow AWS Well-Architected Framework principles
2. Update variable descriptions and validation rules
3. Add appropriate resource tags
4. Update documentation for new features
5. Test in a development environment first

## License

This infrastructure code is provided under the same license as the parent recipe repository.