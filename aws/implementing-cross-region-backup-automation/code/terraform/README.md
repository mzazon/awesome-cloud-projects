# Multi-Region Backup Strategies - Terraform Implementation

This Terraform configuration implements a comprehensive multi-region backup strategy using AWS Backup with cross-region copy destinations, EventBridge for workflow automation, and lifecycle policies for cost optimization.

## Architecture Overview

The solution creates:
- **Primary backup vault** (us-east-1) for main backup operations
- **Secondary backup vault** (us-west-2) for cross-region redundancy  
- **Tertiary backup vault** (eu-west-1) for long-term archival
- **Automated backup plans** with daily and weekly schedules
- **Cross-region copy automation** for disaster recovery
- **EventBridge monitoring** with Lambda-based validation
- **SNS notifications** for operational alerts
- **CloudWatch dashboard** for monitoring and metrics

## Features

### 🔄 Multi-Region Backup Strategy
- Automated daily backups with cross-region copies
- Weekly long-term archival to tertiary region
- Intelligent lifecycle management for cost optimization
- 3-2-1 backup strategy implementation

### 🛡️ Security & Compliance
- KMS encryption for all backup data
- IAM roles with least privilege access
- Optional backup vault lock for immutable backups
- Comprehensive audit logging

### 📊 Monitoring & Alerting
- Real-time backup job monitoring via EventBridge
- Lambda-based backup validation and health checks
- CloudWatch dashboard with key metrics
- SNS notifications for failures and alerts

### 💰 Cost Optimization
- Automatic lifecycle transitions to cold storage
- Intelligent tiering for variable access patterns
- Cost allocation tags for billing transparency
- Configurable retention policies

## Prerequisites

- **AWS CLI v2** installed and configured
- **Terraform >= 1.0** installed
- **Multiple AWS regions** configured (minimum 2, recommended 3)
- **IAM permissions** for AWS Backup, EventBridge, CloudWatch, SNS, Lambda, and KMS
- **Existing AWS resources** to be backed up (tagged appropriately)

### Required IAM Permissions

Your Terraform execution role needs permissions for:
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
        "lambda:*",
        "events:*",
        "logs:*",
        "cloudwatch:*",
        "ec2:DescribeRegions"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to the terraform directory
cd aws/multi-region-backup-strategies-aws-backup/code/terraform/

# Copy the example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit the configuration file
vim terraform.tfvars
```

### 2. Initialize Terraform

```bash
# Initialize Terraform and download providers
terraform init

# Optional: Validate configuration
terraform validate

# Preview changes
terraform plan
```

### 3. Deploy Infrastructure

```bash
# Deploy the backup infrastructure
terraform apply

# Review the planned changes and type 'yes' to confirm
```

### 4. Configure Resource Tagging

Tag your AWS resources to be included in backups:

```bash
# Example: Tag an EC2 instance
aws ec2 create-tags \
    --resources i-1234567890abcdef0 \
    --tags Key=Environment,Value=production Key=BackupEnabled,Value=true

# Example: Tag an RDS database
aws rds add-tags-to-resource \
    --resource-name arn:aws:rds:us-east-1:123456789012:db:mydb \
    --tags Key=Environment,Value=production Key=BackupEnabled,Value=true
```

### 5. Verify Deployment

```bash
# Check backup plan status
aws backup get-backup-plan \
    --backup-plan-id $(terraform output -raw backup_plan_id) \
    --region us-east-1

# List protected resources
aws backup list-protected-resources --region us-east-1

# Monitor backup jobs
aws backup list-backup-jobs --region us-east-1
```

## Configuration

### Key Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `organization_name` | Organization name for resource naming | `"myorg"` | ✅ |
| `environment` | Environment (production, staging, etc.) | `"production"` | ✅ |
| `primary_region` | Primary AWS region | `"us-east-1"` | ✅ |
| `secondary_region` | Secondary region for copies | `"us-west-2"` | ✅ |
| `tertiary_region` | Tertiary region for archival | `"eu-west-1"` | ✅ |
| `notification_email` | Email for backup alerts | `null` | ❌ |
| `daily_retention_days` | Daily backup retention | `365` | ❌ |
| `weekly_retention_days` | Weekly backup retention | `2555` | ❌ |

### Resource Selection

Resources are automatically selected for backup based on tags:

**Required Tags:**
- `Environment` = value from `var.environment`
- `BackupEnabled` = `"true"`

**Excluded Tags:**
- `BackupEnabled` = `"false"`
- `Environment` = `"test"`

### Backup Schedules

**Daily Backups:**
- Schedule: `cron(0 2 * * ? *)` (2:00 AM UTC daily)
- Cross-region copy to secondary region
- Lifecycle: Cold storage after 30 days, delete after 365 days

**Weekly Backups:**
- Schedule: `cron(0 3 ? * SUN *)` (3:00 AM UTC on Sundays)
- Cross-region copy to tertiary region
- Lifecycle: Cold storage after 90 days, delete after 2555 days (7 years)

## Monitoring and Alerting

### CloudWatch Dashboard

Access the monitoring dashboard:
```bash
# Get dashboard URL
terraform output cloudwatch_dashboard_url
```

The dashboard includes:
- Backup job success/failure rates
- Cross-region copy job status
- Backup storage utilization
- Lambda function execution logs

### SNS Notifications

Configure email notifications:

```bash
# The SNS topic ARN is available as output
terraform output sns_topic_arn

# Confirm email subscription in your inbox
```

### EventBridge Rules

The solution monitors these events:
- `aws.backup` - Backup Job State Change
- `aws.backup` - Copy Job State Change

## Cost Estimation

### Monthly Infrastructure Costs

| Component | Estimated Cost |
|-----------|----------------|
| KMS Key Usage | $1.00/month |
| Lambda Execution | $0.00 - $5.00/month |
| SNS Notifications | $0.00 - $2.00/month |
| CloudWatch Logs | Variable |
| **Total Fixed** | **~$3-8/month** |

### Variable Costs

| Component | Cost Factors |
|-----------|--------------|
| Backup Storage | $0.05/GB/month (Standard), $0.01/GB/month (Cold) |
| Cross-Region Transfer | $0.02/GB transferred |
| Backup Operations | $0.05 per backup job |

### Cost Optimization Tips

1. **Lifecycle Policies**: Automatically transition to cold storage
2. **Retention Tuning**: Balance compliance needs with costs
3. **Resource Selection**: Only backup critical resources
4. **Monitoring**: Use cost allocation tags for tracking

## Troubleshooting

### Common Issues

#### 1. Backup Jobs Failing

```bash
# Check backup job details
aws backup describe-backup-job \
    --backup-job-id JOB_ID \
    --region us-east-1

# Check IAM role permissions
aws iam get-role --role-name $(terraform output -raw backup_service_role_name)
```

#### 2. Cross-Region Copy Failures

```bash
# List copy jobs
aws backup list-copy-jobs \
    --region us-west-2 \
    --max-results 10

# Check copy job details  
aws backup describe-copy-job \
    --copy-job-id COPY_JOB_ID \
    --region us-west-2
```

#### 3. Lambda Function Errors

```bash
# View Lambda logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/lambda/$(terraform output -raw lambda_function_name)"

# Get recent log events
aws logs filter-log-events \
    --log-group-name "/aws/lambda/$(terraform output -raw lambda_function_name)" \
    --start-time $(date -d '1 hour ago' +%s)000
```

#### 4. No Resources Being Backed Up

```bash
# List protected resources
aws backup list-protected-resources --region us-east-1

# Check backup selection
aws backup list-backup-selections \
    --backup-plan-id $(terraform output -raw backup_plan_id) \
    --region us-east-1

# Verify resource tags
aws ec2 describe-tags \
    --filters "Name=key,Values=Environment,BackupEnabled"
```

### Log Analysis

Access Lambda function logs for backup validation:

```bash
# Stream logs in real-time
aws logs tail "/aws/lambda/$(terraform output -raw lambda_function_name)" --follow

# Filter for errors
aws logs filter-log-events \
    --log-group-name "/aws/lambda/$(terraform output -raw lambda_function_name)" \
    --filter-pattern "ERROR"
```

## Security Considerations

### Encryption

- All backups encrypted with KMS keys
- Multi-region KMS key for primary region
- AWS managed keys for secondary/tertiary regions
- Automatic key rotation enabled

### Access Control

- Dedicated service role for AWS Backup
- Least privilege IAM policies
- Lambda execution role with minimal permissions
- Cross-region access controls

### Compliance Features

- Backup vault lock support for immutable backups
- Comprehensive audit logging via CloudTrail
- Cost allocation tags for compliance reporting
- Configurable retention periods

## Disaster Recovery

### Testing Restore Operations

```bash
# List available recovery points
aws backup list-recovery-points \
    --backup-vault-name $(terraform output -json backup_vault_names | jq -r '.primary') \
    --region us-east-1

# Start a restore job (example)
aws backup start-restore-job \
    --recovery-point-arn RECOVERY_POINT_ARN \
    --metadata '{"InstanceType":"t3.micro","SubnetId":"subnet-12345"}' \
    --iam-role-arn $(terraform output -raw backup_service_role_arn) \
    --region us-east-1
```

### Recovery Scenarios

1. **Single Resource Recovery**: Restore individual resources from recovery points
2. **Regional Failure**: Use cross-region copies in secondary region
3. **Long-term Recovery**: Access archived backups in tertiary region

## Customization

### Adding Custom Validation

Modify `lambda_functions/backup_validator.py` to add custom business logic:

```python
def custom_validation(backup_job):
    # Add your custom validation logic
    # Example: Check database consistency
    # Example: Verify application-specific requirements
    pass
```

### Extending Notifications

Add Slack integration by modifying the Lambda function:

```python
def send_slack_notification(message):
    webhook_url = os.environ.get('SLACK_WEBHOOK_URL')
    # Implement Slack webhook logic
```

### Custom Metrics

Add application-specific metrics:

```python
def send_custom_metrics(backup_job):
    cloudwatch_client.put_metric_data(
        Namespace='MyApp/Backup',
        MetricData=[{
            'MetricName': 'CustomBackupMetric',
            'Value': calculate_custom_value(backup_job),
            'Unit': 'Count'
        }]
    )
```

## Maintenance

### Regular Tasks

1. **Monthly**: Review backup costs and storage utilization
2. **Quarterly**: Test disaster recovery procedures
3. **Semi-annually**: Review and update retention policies
4. **Annually**: Audit IAM permissions and access patterns

### Upgrades

```bash
# Update Terraform providers
terraform init -upgrade

# Plan and apply updates
terraform plan
terraform apply
```

### Cleanup

To remove all backup infrastructure:

```bash
# Destroy all resources (WARNING: This will delete backup vaults and recovery points)
terraform destroy

# Type 'yes' to confirm destruction
```

⚠️ **Warning**: This will permanently delete all backup vaults and recovery points. Ensure you have alternative backups before proceeding.

## Support

### AWS Backup Limits

Be aware of AWS Backup service limits:
- 100 backup plans per region
- 1000 backup selections per backup plan
- 10000 recovery points per backup vault

### Getting Help

1. **AWS Documentation**: [AWS Backup User Guide](https://docs.aws.amazon.com/aws-backup/latest/devguide/)
2. **Terraform Documentation**: [AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
3. **AWS Support**: Open a support case for service-specific issues
4. **Community**: AWS forums and Stack Overflow

### Contributing

To contribute improvements:
1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request with detailed description

## License

This Terraform configuration is provided as-is for educational and operational use. Please review and adapt according to your organization's requirements and compliance needs.