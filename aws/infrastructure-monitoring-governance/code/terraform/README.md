# Infrastructure Monitoring with CloudTrail, Config, and Systems Manager - Terraform

This Terraform configuration implements a comprehensive infrastructure monitoring solution using AWS CloudTrail, AWS Config, and AWS Systems Manager. The solution provides continuous compliance monitoring, audit logging, and operational insights for your AWS environment.

## Architecture Overview

The infrastructure includes:

- **AWS CloudTrail**: Multi-region trail for API audit logging
- **AWS Config**: Configuration recorder with compliance rules
- **AWS Systems Manager**: Maintenance windows and OpsCenter integration
- **Amazon S3**: Centralized storage for logs and configuration data
- **Amazon SNS**: Notifications for compliance violations
- **AWS Lambda**: Automated remediation (optional)
- **CloudWatch**: Dashboard for monitoring and log analysis

## Features

- ✅ Multi-region CloudTrail with log file validation
- ✅ AWS Config with 4 essential compliance rules
- ✅ Automated compliance notifications via SNS
- ✅ CloudWatch dashboard for real-time monitoring
- ✅ Systems Manager integration for operational management
- ✅ Optional automated remediation with Lambda
- ✅ Comprehensive cost optimization settings
- ✅ Security best practices implementation

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.0 installed
3. **IAM permissions** for the following services:
   - CloudTrail
   - Config
   - Systems Manager
   - S3
   - SNS
   - IAM
   - CloudWatch
   - Lambda (if using automated remediation)
   - EventBridge (if using automated remediation)

## Quick Start

### 1. Clone and Navigate

```bash
cd terraform/
```

### 2. Configure Variables

Copy the example variables file and customize for your environment:

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your preferred settings
```

Key variables to configure:
- `aws_region`: Target AWS region
- `environment`: Environment name (dev, staging, prod)
- `notification_email`: Email for SNS notifications
- `enable_automated_remediation`: Enable Lambda-based remediation

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Plan Deployment

```bash
terraform plan
```

### 5. Deploy Infrastructure

```bash
terraform apply
```

Review the planned changes and type `yes` to confirm.

## Configuration Options

### Basic Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for resources | `null` (uses provider default) | No |
| `environment` | Environment name | `dev` | No |
| `notification_email` | Email for SNS notifications | `""` (no subscription) | No |

### Advanced Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_automated_remediation` | Enable Lambda remediation | `false` |
| `cloudtrail_enable_insights` | Enable CloudTrail Insights | `false` |
| `s3_bucket_lifecycle_enabled` | Enable S3 lifecycle rules | `true` |
| `cloudwatch_log_retention_days` | Log retention period | `14` |
| `maintenance_window_schedule` | Cron for maintenance window | `cron(0 02 ? * SUN *)` |

### Config Rules

Enable/disable specific Config rules:

```hcl
enable_config_rules = {
  s3_bucket_public_access_prohibited = true
  encrypted_volumes                  = true
  root_access_key_check             = true
  iam_password_policy               = true
}
```

## Post-Deployment Steps

After successful deployment, complete these steps:

### 1. Subscribe to SNS Notifications

If you provided an email address, check your inbox and confirm the SNS subscription. Alternatively, subscribe manually:

```bash
aws sns subscribe \
  --topic-arn $(terraform output -raw sns_topic_arn) \
  --protocol email \
  --notification-endpoint your-email@example.com
```

### 2. Access CloudWatch Dashboard

Open the dashboard URL from the Terraform output:

```bash
echo $(terraform output -raw cloudwatch_dashboard_url)
```

### 3. Review Config Rules

Monitor compliance status in the AWS Config console:

```bash
echo $(terraform output -raw config_console_url)
```

### 4. Test the Setup

Create a test S3 bucket with public access to trigger a Config rule violation:

```bash
# Create test bucket
aws s3 mb s3://test-public-bucket-$(date +%s)

# Disable public access block (will trigger Config rule)
aws s3api delete-public-access-block --bucket test-public-bucket-$(date +%s)
```

## Automated Remediation

When `enable_automated_remediation = true`, the solution includes:

- **Lambda Function**: Processes Config compliance changes
- **EventBridge Rule**: Triggers on non-compliant resources
- **Systems Manager OpsItems**: Tracks remediation actions

### Supported Remediations

| Config Rule | Remediation Action |
|-------------|-------------------|
| S3 Bucket Public Access | Automatically enables public access block |
| Encrypted Volumes | Creates OpsItem (manual action required) |
| Root Access Keys | Creates OpsItem (manual action required) |
| IAM Password Policy | Creates OpsItem (manual action required) |

## Cost Optimization

The solution includes several cost optimization features:

### S3 Lifecycle Management

```hcl
s3_bucket_lifecycle_enabled = true
s3_transition_to_ia_days = 30      # Move to IA after 30 days
s3_transition_to_glacier_days = 90  # Move to Glacier after 90 days
```

### CloudWatch Log Retention

```hcl
cloudwatch_log_retention_days = 14  # Retain logs for 14 days
```

### Estimated Costs

| Service | Estimated Monthly Cost |
|---------|----------------------|
| CloudTrail (first trail) | Free |
| Config Rules (4 rules) | ~$8 |
| S3 Storage | Varies by volume |
| SNS Notifications | ~$0.50 |
| Lambda (if enabled) | ~$1 |
| **Total** | **~$10-20/month** |

*Note: Actual costs depend on usage patterns and data volume.*

## Security Features

### Data Protection

- ✅ S3 bucket encryption at rest (AES-256)
- ✅ S3 public access blocked
- ✅ CloudTrail log file validation
- ✅ SNS topic access policies

### Access Control

- ✅ IAM roles with least privilege principles
- ✅ Resource-based policies for cross-service access
- ✅ Condition-based policies for enhanced security

### Compliance Monitoring

- ✅ S3 bucket public access detection
- ✅ EBS volume encryption monitoring
- ✅ Root access key detection
- ✅ IAM password policy enforcement

## Customization

### Adding New Config Rules

Add custom Config rules by extending the configuration:

```hcl
resource "aws_config_config_rule" "custom_rule" {
  name = "my-custom-rule"

  source {
    owner             = "AWS"
    source_identifier = "YOUR_RULE_IDENTIFIER"
  }

  depends_on = [aws_config_configuration_recorder.recorder]
}
```

### Custom Lambda Remediation

Extend the Lambda function by modifying:
- `lambda_functions/remediation-lambda.py`
- Add new remediation handlers in `route_remediation()`

### Additional Dashboard Widgets

Customize the CloudWatch dashboard by modifying the `dashboard_body` in `main.tf`.

## Troubleshooting

### Common Issues

1. **Config Recorder Already Exists**
   ```
   Error: ResourceConflictException: Configuration recorder already exists
   ```
   **Solution**: Import existing recorder or delete it manually

2. **S3 Bucket Name Conflicts**
   ```
   Error: BucketAlreadyExists
   ```
   **Solution**: Bucket names are globally unique; the random suffix should prevent this

3. **Lambda Deployment Package Missing**
   ```
   Error: InvalidParameterValueException: Unzipped size must be smaller than X bytes
   ```
   **Solution**: Ensure Lambda function file exists in `lambda_functions/`

### Validation Commands

```bash
# Check CloudTrail status
aws cloudtrail get-trail-status --name $(terraform output -raw cloudtrail_name)

# Check Config recorder status
aws configservice describe-configuration-recorders

# List Config rules
aws configservice describe-config-rules

# Check SNS subscriptions
aws sns list-subscriptions-by-topic --topic-arn $(terraform output -raw sns_topic_arn)
```

## Cleanup

To remove all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete all monitoring data, logs, and configurations.

## Outputs Reference

Key outputs from this Terraform configuration:

| Output | Description |
|--------|-------------|
| `monitoring_bucket_name` | S3 bucket for storing logs |
| `sns_topic_arn` | SNS topic for notifications |
| `cloudtrail_name` | Name of the CloudTrail |
| `config_rules` | Map of created Config rules |
| `cloudwatch_dashboard_url` | Direct link to dashboard |
| `next_steps` | List of post-deployment actions |

## Support and Contributing

For issues with this Terraform configuration:

1. Check the [AWS Config documentation](https://docs.aws.amazon.com/config/)
2. Review [CloudTrail best practices](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/best-practices-security.html)
3. Consult [Systems Manager documentation](https://docs.aws.amazon.com/systems-manager/)

## License

This Terraform configuration is provided as-is for educational and deployment purposes. Please review and test thoroughly before using in production environments.