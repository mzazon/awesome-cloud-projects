# S3 Storage Cost Optimization with Terraform

This Terraform configuration creates a comprehensive S3 storage cost optimization solution that demonstrates lifecycle policies, intelligent tiering, storage analytics, and cost monitoring capabilities. The solution can achieve potential cost savings of 50-95% depending on data access patterns and storage class transitions.

## Architecture Overview

The infrastructure includes:

- **S3 Bucket** with encryption and public access blocking
- **Storage Analytics** for access pattern analysis
- **Intelligent Tiering** for automatic cost optimization
- **Lifecycle Policies** for different data types
- **CloudWatch Dashboard** for monitoring storage metrics
- **AWS Budgets** for cost alerts and monitoring
- **Optional SNS notifications** for enhanced alerting
- **Sample data objects** for testing (optional)

## Quick Start

### Prerequisites

- AWS CLI installed and configured
- Terraform >= 1.5.0 installed
- Appropriate AWS permissions for S3, CloudWatch, and Budgets

### Basic Deployment

1. **Clone and Navigate**:
   ```bash
   git clone <repository-url>
   cd aws/storage-cost-optimization-s3-storage-classes/code/terraform/
   ```

2. **Initialize Terraform**:
   ```bash
   terraform init
   ```

3. **Review and Customize Variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

4. **Plan the Deployment**:
   ```bash
   terraform plan
   ```

5. **Apply the Configuration**:
   ```bash
   terraform apply
   ```

### Custom Configuration

Create a `terraform.tfvars` file with your specific settings:

```hcl
# Basic Configuration
environment           = "production"
bucket_name_prefix   = "my-company-storage-optimization"
aws_region           = "us-west-2"

# Budget Configuration
budget_limit_amount     = "100.00"
budget_alert_threshold  = 75
budget_alert_emails     = ["admin@company.com", "finance@company.com"]

# Lifecycle Policy Customization
frequently_accessed_ia_days      = 30
frequently_accessed_glacier_days = 90
infrequently_accessed_ia_days    = 1
archive_glacier_days             = 1

# Enable Additional Features
create_sample_data              = true
enable_enhanced_notifications   = true
enable_storage_alarms          = true
enable_forecasted_alerts       = true

# Tagging
additional_tags = {
  Department = "IT"
  Application = "DataArchive"
}
cost_center = "CC-12345"
owner       = "data-team@company.com"
```

## Configuration Options

### Storage Lifecycle Policies

The solution includes three pre-configured lifecycle policies:

1. **Frequently Accessed Data** (`data/frequently-accessed/`):
   - 30 days → Standard-IA (40% cost reduction)
   - 90 days → Glacier (68% cost reduction)

2. **Infrequently Accessed Data** (`data/infrequently-accessed/`):
   - 1 day → Standard-IA
   - 30 days → Glacier
   - 180 days → Deep Archive (95% cost reduction)

3. **Archive Data** (`data/archive/`):
   - 1 day → Glacier
   - 30 days → Deep Archive

### Intelligent Tiering Configuration

- **Archive Access Tier**: 1 day (configurable)
- **Deep Archive Access Tier**: 90 days (configurable)
- Automatic optimization based on access patterns

### Cost Monitoring

- **Budget Alerts**: Configurable threshold (default: 80%)
- **CloudWatch Dashboard**: Real-time storage metrics
- **Email Notifications**: Multiple recipients supported
- **SNS Integration**: Enhanced notification options

## Important Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `bucket_name_prefix` | Prefix for bucket name | `storage-optimization-demo` | No |
| `budget_limit_amount` | Monthly budget limit (USD) | `"50.00"` | No |
| `budget_alert_emails` | Email addresses for alerts | `[]` | Yes (for alerts) |
| `environment` | Environment name | `demo` | No |
| `create_sample_data` | Create sample test data | `true` | No |

## Outputs

After deployment, Terraform provides comprehensive outputs including:

- **Bucket Information**: Name, ARN, region, endpoints
- **Configuration Details**: Analytics, lifecycle, and tiering settings
- **Monitoring Resources**: Dashboard and budget information
- **Management Links**: Direct AWS Console URLs
- **Verification Commands**: CLI commands for testing
- **Next Steps**: Recommended actions after deployment

## Cost Optimization Features

### Automatic Optimizations

1. **Intelligent Tiering**: Automatically moves objects between access tiers
2. **Lifecycle Policies**: Time-based transitions to lower-cost storage classes
3. **Storage Analytics**: Provides data-driven optimization recommendations
4. **Cleanup Policies**: Removes incomplete multipart uploads

### Monitoring and Alerting

1. **CloudWatch Dashboard**: Visual monitoring of storage metrics
2. **Budget Alerts**: Proactive cost management
3. **SNS Notifications**: Enhanced alerting capabilities
4. **Storage Alarms**: Threshold-based monitoring

## Management and Operations

### Viewing Resources

Access your resources via AWS Console:
- **S3 Bucket**: Use the `management_console_links.s3_bucket` output
- **CloudWatch Dashboard**: Use the `management_console_links.cloudwatch_dashboard` output
- **Budget Console**: Use the `management_console_links.budget_console` output

### Useful Commands

```bash
# List all objects in the bucket
aws s3 ls s3://$(terraform output -raw bucket_name) --recursive

# Get storage metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/S3 \
  --metric-name BucketSizeBytes \
  --dimensions Name=BucketName,Value=$(terraform output -raw bucket_name) Name=StorageType,Value=StandardStorage \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Average

# View lifecycle configuration
aws s3api get-bucket-lifecycle-configuration \
  --bucket $(terraform output -raw bucket_name)

# Check analytics configuration
aws s3api list-bucket-analytics-configurations \
  --bucket $(terraform output -raw bucket_name)
```

## Advanced Features

### Custom Lifecycle Rules

You can define custom lifecycle rules using the `custom_lifecycle_rules` variable:

```hcl
custom_lifecycle_rules = {
  "logs" = {
    prefix = "logs/"
    transitions = [
      {
        days          = 7
        storage_class = "STANDARD_IA"
      },
      {
        days          = 30
        storage_class = "GLACIER"
      }
    ]
    expiration_days = 2555  # 7 years
  }
}
```

### Cross-Region Replication

Enable cross-region replication for disaster recovery:

```hcl
enable_cross_region_replication = true
replication_destination_bucket  = "backup-bucket-name"
replication_destination_region  = "us-east-1"
```

### Access Logging

Enable S3 access logging for audit and analysis:

```hcl
enable_logging         = true
logging_target_bucket  = "access-logs-bucket"
logging_target_prefix  = "s3-access-logs/"
```

## Security Considerations

- **Encryption**: All data is encrypted at rest using AES-256
- **Public Access**: Bucket public access is blocked by default
- **IAM Permissions**: Follows principle of least privilege
- **Versioning**: Optional versioning for data protection
- **Access Control**: Bucket policies and ACLs properly configured

## Troubleshooting

### Common Issues

1. **Budget Creation Fails**: Ensure you have proper permissions for AWS Budgets
2. **Email Alerts Not Working**: Verify email addresses in `budget_alert_emails`
3. **Analytics Not Appearing**: Wait 24-48 hours for initial analytics data
4. **Lifecycle Not Working**: Check object prefixes match lifecycle rules

### Validation Commands

```bash
# Verify bucket exists
aws s3 ls s3://$(terraform output -raw bucket_name)

# Check all configurations
terraform output verification_commands
```

## Cost Estimates

Based on AWS pricing (subject to change):

- **S3 Standard**: $0.023/GB/month
- **S3 Standard-IA**: $0.0125/GB/month (45% savings)
- **S3 Glacier**: $0.004/GB/month (83% savings)
- **S3 Deep Archive**: $0.00099/GB/month (96% savings)
- **CloudWatch Dashboard**: $3/dashboard/month
- **Budget Alerts**: Free (first 2 budgets)

## Cleanup

To remove all resources:

```bash
# Remove all objects first (if force_destroy is false)
aws s3 rm s3://$(terraform output -raw bucket_name) --recursive

# Destroy infrastructure
terraform destroy
```

## Support and Documentation

- **Recipe Documentation**: See the main recipe file for detailed implementation steps
- **AWS Documentation**: [S3 Storage Classes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-class-intro.html)
- **Terraform AWS Provider**: [Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- **Cost Optimization**: [AWS Cost Optimization Hub](https://aws.amazon.com/aws-cost-management/cost-optimization/)

## Contributing

When modifying this configuration:

1. Follow Terraform best practices
2. Update variable descriptions and validation rules
3. Add appropriate outputs for new resources
4. Test configurations in a development environment
5. Update documentation accordingly

---

**Note**: This infrastructure is designed for educational and demonstration purposes. For production deployments, consider additional security hardening, monitoring, and backup strategies based on your specific requirements.