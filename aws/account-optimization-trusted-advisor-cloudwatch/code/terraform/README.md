# Terraform Infrastructure for AWS Trusted Advisor CloudWatch Monitoring

This Terraform configuration creates an automated monitoring system that leverages AWS Trusted Advisor's built-in optimization checks with CloudWatch alarms and SNS notifications to proactively alert teams when account optimization opportunities arise.

## Architecture Overview

The infrastructure creates:
- **SNS Topic**: Central notification hub for Trusted Advisor alerts
- **Email Subscriptions**: Automatic email notifications to specified addresses
- **CloudWatch Alarms**: Real-time monitoring of Trusted Advisor metrics
- **Security Policies**: Proper IAM permissions for alarm-to-SNS communication

## Prerequisites

1. **AWS Account Requirements**:
   - Business, Enterprise On-Ramp, or Enterprise Support plan for full Trusted Advisor access
   - Appropriate IAM permissions for CloudWatch, SNS, and Trusted Advisor operations

2. **Tool Requirements**:
   - Terraform >= 1.0
   - AWS CLI v2 configured with appropriate credentials
   - Valid email addresses for receiving optimization alerts

3. **Region Requirements**:
   - Deployment must be in `us-east-1` region (Trusted Advisor requirement)
   - All Trusted Advisor metrics are published exclusively to us-east-1

4. **Cost Considerations**:
   - Estimated cost: $0.50-$3.00/month for SNS notifications
   - First 10 CloudWatch alarms are free
   - First 1,000 SNS notifications per month are free

## Quick Start

### 1. Clone and Navigate

```bash
cd aws/account-optimization-trusted-advisor-cloudwatch/code/terraform/
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review and Customize Configuration

Create a `terraform.tfvars` file with your specific configuration:

```hcl
project_name     = "my-trusted-advisor"
environment      = "prod"
notification_emails = [
  "ops-team@company.com",
  "security@company.com"
]

# Customize thresholds as needed
cost_optimization_threshold = 1
security_threshold         = 1
service_limits_threshold   = 80

# Enable additional monitoring (optional)
enable_iam_key_rotation_alarm = true
enable_rds_security_alarm     = true
enable_s3_permissions_alarm   = true

additional_tags = {
  Owner       = "Operations Team"
  CostCenter  = "IT-Infrastructure"
  Environment = "Production"
}
```

### 4. Plan and Apply

```bash
# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### 5. Confirm Email Subscriptions

After deployment, check your email inbox for SNS subscription confirmation messages and click the confirmation links.

## Configuration Options

### Core Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_name` | Project name for resource naming | `trusted-advisor` | No |
| `environment` | Environment (dev/test/staging/prod) | `prod` | No |
| `notification_emails` | List of email addresses for alerts | `[]` | No |

### Alarm Thresholds

| Variable | Description | Default | Range |
|----------|-------------|---------|-------|
| `cost_optimization_threshold` | Resources triggering cost alerts | `1` | 1-100 |
| `security_threshold` | Resources triggering security alerts | `1` | 1-50 |
| `service_limits_threshold` | Service limit percentage for alerts | `80` | 50-95% |

### Optional Features

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_iam_key_rotation_alarm` | Monitor IAM key rotation | `false` |
| `enable_rds_security_alarm` | Monitor RDS security groups | `false` |
| `enable_s3_permissions_alarm` | Monitor S3 bucket permissions | `false` |

## Post-Deployment Validation

### 1. Verify SNS Topic Configuration

```bash
aws sns get-topic-attributes \
    --topic-arn $(terraform output -raw sns_topic_arn) \
    --query 'Attributes.[DisplayName,SubscriptionsConfirmed]' \
    --output table
```

### 2. Test Notification Delivery

```bash
aws sns publish \
    --topic-arn $(terraform output -raw sns_topic_arn) \
    --message "Test notification: Trusted Advisor monitoring is active" \
    --subject "Test Alert"
```

### 3. Check CloudWatch Alarms

```bash
aws cloudwatch describe-alarms \
    --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
    --output table
```

### 4. Verify Trusted Advisor Metrics

```bash
aws cloudwatch list-metrics \
    --namespace AWS/TrustedAdvisor \
    --region us-east-1 \
    --output table
```

## Monitoring and Operations

### View Alarm History

```bash
aws cloudwatch describe-alarm-history \
    --alarm-name $(terraform output -json cloudwatch_alarms | jq -r '.cost_optimization.name') \
    --max-records 5
```

### Check Current Trusted Advisor Status

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/TrustedAdvisor \
    --metric-name YellowResources \
    --dimensions Name=CheckName,Value="Low Utilization Amazon EC2 Instances" \
    --start-time $(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Average \
    --region us-east-1
```

## Troubleshooting

### Common Issues

1. **No Email Notifications**:
   - Check spam/junk folders for confirmation emails
   - Verify email addresses in `notification_emails` variable
   - Confirm subscriptions via AWS console

2. **Alarms Stuck in "INSUFFICIENT_DATA"**:
   - Normal behavior - Trusted Advisor metrics appear after several hours
   - Ensure Business/Enterprise support plan is active
   - Verify deployment is in us-east-1 region

3. **Permission Errors**:
   - Ensure AWS credentials have CloudWatch, SNS, and IAM permissions
   - Check that the deployment role can create resources in us-east-1

4. **Missing Trusted Advisor Checks**:
   - Verify AWS support plan includes Trusted Advisor API access
   - Some checks require specific AWS services to be in use

### Diagnostic Commands

```bash
# Check Terraform state
terraform show

# Validate configuration
terraform validate

# Refresh state
terraform refresh

# View all outputs
terraform output
```

## Security Considerations

1. **SNS Topic Encryption**: Uses AWS KMS encryption (configurable)
2. **IAM Permissions**: Minimal permissions for CloudWatch-to-SNS communication
3. **Email Security**: Subscription confirmations prevent unauthorized access
4. **Resource Tagging**: All resources tagged for identification and management

## Customization Examples

### Multi-Environment Deployment

```hcl
# dev.tfvars
project_name = "trusted-advisor-dev"
environment  = "dev"
notification_emails = ["dev-team@company.com"]
cost_optimization_threshold = 5  # Less sensitive in dev

# prod.tfvars
project_name = "trusted-advisor-prod"
environment  = "prod"
notification_emails = ["ops@company.com", "security@company.com"]
cost_optimization_threshold = 1  # Very sensitive in prod
```

### Integration with External Systems

```hcl
# For Slack integration via webhook
variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  sensitive   = true
}

resource "aws_sns_topic_subscription" "slack_webhook" {
  topic_arn = aws_sns_topic.trusted_advisor_alerts.arn
  protocol  = "https"
  endpoint  = var.slack_webhook_url
}
```

## Cleanup

To remove all created resources:

```bash
terraform destroy
```

This will remove:
- All CloudWatch alarms
- SNS topic and subscriptions
- IAM policies
- All created tags

## Cost Optimization

1. **SNS Costs**: First 1,000 notifications/month are free
2. **CloudWatch Costs**: First 10 alarms are free
3. **Monitoring**: Use CloudWatch to track SNS usage and costs
4. **Optimization**: Adjust thresholds to reduce unnecessary alerts

## Support and Contributing

- **AWS Documentation**: [Trusted Advisor User Guide](https://docs.aws.amazon.com/awssupport/latest/user/trusted-advisor.html)
- **Terraform Documentation**: [AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- **Recipe Source**: AWS Recipes Repository

## License

This infrastructure code is provided as part of the AWS Recipes project and follows the same licensing terms.