# AWS Multi-Region Backup Strategy - Terraform Implementation

This Terraform configuration implements a comprehensive multi-region backup strategy using AWS Backup, with automated cross-region replication, lifecycle management, and intelligent monitoring capabilities.

## Architecture Overview

This solution creates:

- **Multi-Region Backup Vaults**: Primary, secondary, and tertiary backup vaults across three AWS regions
- **Automated Backup Plans**: Daily and weekly backup schedules with customizable retention policies
- **Cross-Region Replication**: Automated backup copying to secondary and tertiary regions
- **KMS Encryption**: Separate KMS keys in each region for backup encryption
- **Event-Driven Monitoring**: EventBridge rules for backup job state changes
- **SNS Notifications**: Email alerts for backup success/failure events
- **Lambda Validation**: Automated backup validation and enhanced monitoring
- **Tag-Based Resource Selection**: Flexible resource discovery using AWS resource tags

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured with appropriate permissions
2. **Terraform** version 1.6 or later installed
3. **AWS Account** with permissions for:
   - AWS Backup service operations
   - IAM role and policy management
   - KMS key management
   - EventBridge rule creation
   - SNS topic management
   - Lambda function deployment
4. **Multiple AWS Regions** accessible from your account
5. **Resources to backup** tagged with appropriate labels

## Required AWS Permissions

Your AWS credentials must have the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "backup:*",
        "iam:*",
        "kms:*",
        "sns:*",
        "events:*",
        "lambda:*",
        "ec2:DescribeRegions",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to the Terraform directory
cd terraform/

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your specific configuration
nano terraform.tfvars
```

### 2. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 3. Verify Deployment

```bash
# Check backup plans
aws backup list-backup-plans --region us-east-1

# Verify backup vaults
aws backup list-backup-vaults --region us-east-1
aws backup list-backup-vaults --region us-west-2
aws backup list-backup-vaults --region eu-west-1

# Check SNS topic subscription
aws sns list-subscriptions --region us-east-1
```

## Configuration Variables

### Core Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `organization_name` | Organization name for resource naming | `"example-corp"` | Yes |
| `environment` | Environment (dev/staging/prod) | `"prod"` | Yes |
| `primary_region` | Primary AWS region | `"us-east-1"` | Yes |
| `secondary_region` | Secondary AWS region | `"us-west-2"` | Yes |
| `tertiary_region` | Tertiary AWS region | `"eu-west-1"` | Yes |

### Backup Scheduling

| Variable | Description | Default |
|----------|-------------|---------|
| `daily_backup_schedule` | Daily backup cron expression | `"cron(0 2 ? * * *)"` |
| `weekly_backup_schedule` | Weekly backup cron expression | `"cron(0 3 ? * SUN *)"` |
| `backup_start_window_minutes` | Backup start window | `480` (8 hours) |
| `backup_completion_window_minutes` | Backup completion window | `10080` (7 days) |

### Retention Policies

| Variable | Description | Default |
|----------|-------------|---------|
| `daily_retention_days` | Daily backup retention | `365` days |
| `weekly_retention_days` | Weekly backup retention | `2555` days (~7 years) |
| `cold_storage_after_days` | Cold storage transition | `30` days |
| `weekly_cold_storage_after_days` | Weekly cold storage transition | `90` days |

### Resource Selection

Resources are automatically selected for backup based on tags. Configure the `backup_resource_tags` variable to specify which resources should be backed up:

```hcl
backup_resource_tags = {
  BackupEnabled = "true"
  Environment   = "Production"
}
```

## Tagging Resources for Backup

To include resources in the backup plan, tag them with the configured backup tags:

```bash
# Tag an EC2 instance
aws ec2 create-tags \
  --resources i-1234567890abcdef0 \
  --tags Key=BackupEnabled,Value=true Key=Environment,Value=Production

# Tag an RDS instance
aws rds add-tags-to-resource \
  --resource-name arn:aws:rds:region:account:db:database-name \
  --tags Key=BackupEnabled,Value=true Key=Environment,Value=Production

# Tag an EFS file system
aws efs put-backup-policy \
  --file-system-id fs-1234567890abcdef0 \
  --backup-policy Status=ENABLED
```

## Monitoring and Notifications

### SNS Notifications

The solution automatically sends email notifications for:

- Backup job completion (success/failure)
- Cross-region copy job status
- Lambda validation results
- System errors and alerts

Configure your email address in the `notification_email` variable.

### EventBridge Integration

EventBridge rules capture backup events and trigger:

- SNS notifications for immediate alerts
- Lambda functions for validation and extended monitoring
- Custom integrations (can be extended)

### Lambda Validation

The backup validator Lambda function:

- Validates backup job completion
- Verifies recovery point creation
- Performs additional quality checks
- Sends detailed notifications with backup metrics

## Cost Optimization

### Storage Classes and Lifecycle

- **Warm Storage**: Recent backups for quick recovery
- **Cold Storage**: Automated transition after 30 days (configurable)
- **Intelligent Tiering**: Automatic cost optimization based on access patterns

### Cross-Region Transfer

- Daily backups replicated to secondary region
- Weekly backups archived in tertiary region
- Lifecycle policies reduce long-term storage costs

### Monitoring Costs

Use AWS Cost Explorer to monitor backup-related charges:

```bash
# View backup service costs
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

## Security Features

### Encryption

- **KMS Encryption**: Separate customer-managed keys in each region
- **Key Rotation**: Automatic annual key rotation enabled
- **Cross-Region Access**: Keys configured for backup service access

### Access Control

- **Least Privilege IAM**: Service roles with minimal required permissions
- **Cross-Account Support**: Can be extended for multi-account scenarios
- **Audit Trail**: All backup operations logged in CloudTrail

### Compliance

- **Backup Vault Lock**: Optional immutable backup retention
- **Tag-Based Governance**: Consistent tagging for compliance reporting
- **Audit Reports**: EventBridge events for compliance monitoring

## Disaster Recovery Testing

### Validation Commands

```bash
# List recovery points in primary region
aws backup list-recovery-points \
  --backup-vault-name primary-backup-vault \
  --region us-east-1

# List recovery points in secondary region
aws backup list-recovery-points \
  --backup-vault-name secondary-backup-vault \
  --region us-west-2

# Test restore operation (replace with actual recovery point ARN)
aws backup start-restore-job \
  --recovery-point-arn "arn:aws:backup:us-east-1:123456789012:recovery-point:primary-backup-vault/recovery-point-id" \
  --iam-role-arn "arn:aws:iam::123456789012:role/backup-service-role" \
  --metadata InstanceType=t3.micro,SubnetId=subnet-12345678 \
  --region us-east-1
```

### Automated Testing

The Lambda validator function can be extended to perform periodic restore tests:

1. Create test restore jobs
2. Validate restored resources
3. Clean up test resources
4. Report on restore capabilities

## Troubleshooting

### Common Issues

1. **Permission Errors**: Verify IAM roles have required policies attached
2. **Cross-Region Issues**: Check KMS key policies allow backup service access
3. **Notification Failures**: Confirm SNS topic subscription and email verification
4. **Tag Selection**: Verify resources have correct backup tags applied

### Debug Commands

```bash
# Check backup job status
aws backup list-backup-jobs --region us-east-1

# Describe specific backup job
aws backup describe-backup-job \
  --backup-job-id "backup-job-id" \
  --region us-east-1

# Check cross-region copy jobs
aws backup list-copy-jobs --region us-west-2

# View EventBridge rule targets
aws events list-targets-by-rule \
  --rule "backup-job-state-change" \
  --region us-east-1
```

### Logs and Monitoring

- **CloudWatch Logs**: Lambda function logs for validation results
- **EventBridge Events**: Real-time backup event monitoring
- **SNS Delivery**: Notification delivery status and failures
- **AWS Backup Console**: Comprehensive backup job monitoring

## Customization and Extensions

### Adding More Regions

To add additional backup destinations:

1. Add provider configuration for new region
2. Create KMS key and backup vault resources
3. Update backup plan copy actions
4. Extend monitoring and notification rules

### Custom Validation Logic

Extend the Lambda validator function to:

- Perform application-specific backup validation
- Integrate with external monitoring systems
- Generate custom compliance reports
- Implement automated remediation workflows

### Integration Patterns

- **ServiceNow**: Automatic ticket creation for backup failures
- **Slack/Teams**: Real-time notifications to team channels
- **Datadog/New Relic**: Custom metrics and dashboards
- **AWS Config**: Compliance rule evaluation

## Cleanup

To remove all backup infrastructure:

```bash
# Destroy Terraform-managed resources
terraform destroy

# Manually clean up any remaining recovery points
aws backup list-recovery-points \
  --backup-vault-name primary-backup-vault \
  --region us-east-1 \
  --query 'RecoveryPoints[].RecoveryPointArn' \
  --output text | xargs -I {} aws backup delete-recovery-point \
  --backup-vault-name primary-backup-vault \
  --recovery-point-arn {} \
  --region us-east-1
```

**Warning**: This will permanently delete all backup infrastructure and recovery points. Ensure you have alternative backup strategies in place before cleanup.

## Support and Contributing

For issues or questions:

1. Review AWS Backup documentation
2. Check Terraform AWS provider documentation
3. Review CloudWatch logs for specific error details
4. Consult AWS Support for service-specific issues

## License

This Terraform configuration is provided as-is for educational and implementation purposes. Customize according to your organization's requirements and security policies.