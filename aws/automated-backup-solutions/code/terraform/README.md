# AWS Backup Solution - Terraform Infrastructure

This Terraform configuration deploys a comprehensive AWS Backup solution with automated backup plans, cross-region replication, monitoring, and compliance features.

## Architecture Overview

The solution creates:

- **Backup Vaults**: Primary and disaster recovery backup vaults with KMS encryption
- **Backup Plans**: Multi-schedule backup plans (daily, weekly, monthly) with lifecycle management
- **Cross-Region Replication**: Automatic backup copying to DR region for disaster recovery
- **Monitoring**: CloudWatch alarms and SNS notifications for backup job status
- **Compliance**: Optional AWS Config rules and backup reporting
- **Security**: IAM roles, KMS encryption, and vault access policies
- **Restore Testing**: Optional automated restore testing for validation

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform** >= 1.0 installed
3. **AWS IAM permissions** for:
   - AWS Backup (backup vaults, plans, selections)
   - IAM (roles and policies)
   - KMS (key creation and management)
   - SNS (topics and subscriptions)
   - CloudWatch (alarms and metrics)
   - S3 (buckets for reporting)
   - AWS Config (optional, for compliance rules)
4. **Existing AWS resources** tagged for backup (EC2, RDS, EFS, DynamoDB, etc.)
5. **Two AWS regions** accessible for primary and DR deployment

## Quick Start

### 1. Clone and Navigate

```bash
cd terraform/
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review and Customize Variables

Create a `terraform.tfvars` file to customize the deployment:

```hcl
# Basic Configuration
primary_region = "us-west-2"
dr_region      = "us-east-1"
environment    = "production"

# Notification Configuration
notification_email = "backup-admin@yourcompany.com"

# Feature Toggles
enable_backup_reporting   = true
enable_config_compliance  = true
enable_restore_testing    = false
enable_backup_vault_lock  = false

# Backup Retention (adjust based on compliance requirements)
daily_backup_retention_days   = 30
weekly_backup_retention_days  = 90
monthly_backup_retention_days = 365

# Default Tags
default_tags = {
  Project     = "Enterprise-Backup-Solution"
  Owner       = "Platform-Team"
  Environment = "production"
  CostCenter  = "IT-Infrastructure"
}
```

### 4. Plan and Apply

```bash
# Review the execution plan
terraform plan

# Apply the configuration
terraform apply
```

### 5. Verify Deployment

After successful deployment, verify the backup solution:

```bash
# List backup plans
aws backup list-backup-plans --region us-west-2

# List backup vaults
aws backup list-backup-vaults --region us-west-2

# Check cross-region replication
aws backup list-backup-vaults --region us-east-1

# Verify SNS subscriptions
aws sns list-subscriptions --region us-west-2
```

## Configuration Variables

### Core Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `primary_region` | Primary AWS region for backup resources | `us-west-2` | No |
| `dr_region` | Disaster recovery region for cross-region replication | `us-east-1` | No |
| `environment` | Environment name (production, staging, development, test) | `production` | No |

### Backup Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `daily_backup_schedule` | Cron expression for daily backups | `cron(0 2 ? * * *)` | No |
| `weekly_backup_schedule` | Cron expression for weekly backups | `cron(0 3 ? * SUN *)` | No |
| `monthly_backup_schedule` | Cron expression for monthly backups | `cron(0 4 1 * ? *)` | No |
| `daily_backup_retention_days` | Daily backup retention period | `30` | No |
| `weekly_backup_retention_days` | Weekly backup retention period | `90` | No |
| `monthly_backup_retention_days` | Monthly backup retention period | `365` | No |

### Security Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_backup_vault_lock` | Enable vault lock for immutable backups | `false` | No |
| `backup_vault_lock_min_retention_days` | Minimum retention for vault lock | `1` | No |
| `backup_vault_lock_max_retention_days` | Maximum retention for vault lock | `36500` | No |
| `kms_deletion_window_days` | KMS key deletion window | `10` | No |

### Monitoring Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `notification_email` | Email for backup notifications | `""` | No |
| `backup_storage_threshold_bytes` | Storage usage alarm threshold | `107374182400` (100GB) | No |

### Feature Toggles

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `enable_backup_reporting` | Enable backup reporting to S3 | `true` | No |
| `enable_config_compliance` | Enable AWS Config compliance rules | `false` | No |
| `enable_restore_testing` | Enable automated restore testing | `false` | No |
| `enable_continuous_backup` | Enable continuous backup for supported resources | `true` | No |

## Resource Tagging Strategy

The solution implements a comprehensive tagging strategy for backup resources:

### Required Tags for Backup Selection

Resources must be tagged appropriately to be included in backup plans:

```json
{
  "Environment": "production",
  "BackupEnabled": "true"
}
```

For critical databases, add:

```json
{
  "CriticalData": "true",
  "ResourceType": "Database"
}
```

### Example Resource Tagging

```bash
# Tag an EC2 instance for backup
aws ec2 create-tags \
    --resources i-1234567890abcdef0 \
    --tags Key=Environment,Value=production \
           Key=BackupEnabled,Value=true \
           Key=CriticalData,Value=false

# Tag an RDS database for backup
aws rds add-tags-to-resource \
    --resource-name arn:aws:rds:us-west-2:123456789012:db:mydb \
    --tags Key=Environment,Value=production \
           Key=BackupEnabled,Value=true \
           Key=CriticalData,Value=true \
           Key=ResourceType,Value=Database
```

## Monitoring and Alerting

The solution includes comprehensive monitoring:

### CloudWatch Alarms

1. **Backup Job Failures**: Triggers when backup jobs fail
2. **Storage Usage**: Monitors backup vault storage consumption

### SNS Notifications

Backup vault events that trigger notifications:
- Backup job started/completed/failed
- Restore job started/completed/failed
- Copy job started/successful/failed

### Backup Reporting

When enabled, generates monthly reports in S3 with:
- Backup job success/failure statistics
- Storage utilization metrics
- Compliance status

## Security Features

### Encryption

- **KMS encryption** for all backup data using customer-managed keys
- **Key rotation** enabled automatically
- **Regional key isolation** for primary and DR regions

### Access Control

- **IAM service roles** with least privilege permissions
- **Backup vault policies** to prevent unauthorized deletion
- **Optional vault lock** for immutable backups (compliance mode)

### Cross-Region Security

- **Independent encryption keys** per region
- **Regional access controls** for disaster recovery scenarios

## Compliance and Governance

### AWS Config Integration (Optional)

When `enable_config_compliance = true`, deploys Config rules to monitor:
- Backup plan frequency compliance
- Backup retention compliance
- Resource protection coverage

### Backup Reporting (Optional)

When `enable_backup_reporting = true`, creates:
- Monthly compliance reports in S3
- Backup job statistics and metrics
- Storage utilization analysis

### Restore Testing (Optional)

When `enable_restore_testing = true`, provides:
- Automated weekly restore validation
- Recovery point verification
- Restore capability confirmation

## Cost Optimization

### Lifecycle Management

- **Automatic deletion** of expired backups
- **Regional storage optimization** through cross-region copying
- **Intelligent tiering** for long-term retention

### Storage Classes

- Daily backups: Standard storage with 30-day retention
- Weekly backups: Standard storage with 90-day retention
- Monthly backups: Standard storage with 365-day retention

### Cost Monitoring

- CloudWatch alarms for storage usage
- S3 reporting for storage costs analysis
- Lifecycle policies to prevent storage bloat

## Disaster Recovery

### Cross-Region Replication

- **Automatic copying** of all backups to DR region
- **Independent encryption** in each region
- **Regional failover** capabilities

### Recovery Procedures

1. **Same-region recovery**: Restore from primary backup vault
2. **Cross-region recovery**: Restore from DR backup vault
3. **Point-in-time recovery**: Use continuous backup (when enabled)

## Maintenance and Updates

### Regular Tasks

1. **Monitor backup job success rates** via CloudWatch dashboard
2. **Review backup reports** monthly for compliance
3. **Test restore procedures** quarterly
4. **Update retention policies** based on compliance requirements

### Scaling Considerations

- **Resource tagging** automatically includes new resources
- **Backup vault capacity** scales automatically
- **Cross-region bandwidth** may require monitoring for large datasets

## Troubleshooting

### Common Issues

1. **Backup jobs failing**:
   - Check IAM role permissions
   - Verify resource tags
   - Review CloudWatch logs

2. **Cross-region copy failures**:
   - Verify DR region KMS key permissions
   - Check cross-region connectivity
   - Review destination vault capacity

3. **High storage costs**:
   - Review retention policies
   - Check for orphaned recovery points
   - Analyze backup frequency

### Validation Commands

```bash
# Check backup job status
aws backup list-backup-jobs \
    --by-backup-vault-name $(terraform output -raw primary_backup_vault_name) \
    --region $(terraform output -raw primary_region)

# Verify cross-region replication
aws backup list-recovery-points-by-backup-vault \
    --backup-vault-name $(terraform output -raw dr_backup_vault_name) \
    --region $(terraform output -raw dr_region)

# Check CloudWatch alarms
aws cloudwatch describe-alarms \
    --alarm-names $(terraform output -raw backup_failure_alarm_name) \
    --region $(terraform output -raw primary_region)

# Verify SNS subscriptions
aws sns list-subscriptions-by-topic \
    --topic-arn $(terraform output -raw sns_topic_arn) \
    --region $(terraform output -raw primary_region)
```

## Cleanup

To remove all backup infrastructure:

```bash
# Important: Delete all recovery points first
aws backup list-recovery-points-by-backup-vault \
    --backup-vault-name $(terraform output -raw primary_backup_vault_name) \
    --query 'RecoveryPoints[].RecoveryPointArn' \
    --output text | xargs -I {} aws backup delete-recovery-point \
    --backup-vault-name $(terraform output -raw primary_backup_vault_name) \
    --recovery-point-arn {}

# Destroy Terraform infrastructure
terraform destroy
```

**Warning**: Deleting backup vaults will permanently remove all backup data. Ensure you have alternative backups or no longer need the data before proceeding.

## Support and Documentation

- [AWS Backup Documentation](https://docs.aws.amazon.com/aws-backup/)
- [AWS Backup Best Practices](https://docs.aws.amazon.com/aws-backup/latest/devguide/best-practices.html)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

For infrastructure-specific issues, review the Terraform plan output and AWS CloudTrail logs for detailed error information.