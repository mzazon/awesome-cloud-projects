# Simple Business Notifications - Terraform Infrastructure

This Terraform configuration creates a serverless business notification system using Amazon EventBridge Scheduler and Amazon SNS. The system automatically sends scheduled notifications for daily reports, weekly summaries, and monthly reminders.

## Architecture Overview

The infrastructure includes:

- **Amazon SNS Topic**: Central hub for message distribution
- **Email/SMS Subscriptions**: Multiple delivery channels for notifications
- **EventBridge Scheduler**: Automated scheduling with cron expressions
- **IAM Roles & Policies**: Security with least privilege access
- **SQS Integration** (optional): Queue-based message processing
- **CloudWatch Logs** (optional): Execution monitoring and debugging

## Quick Start

### Prerequisites

1. **AWS CLI** installed and configured
   ```bash
   aws configure
   # or use AWS SSO, IAM roles, or environment variables
   ```

2. **Terraform** version 1.0 or higher
   ```bash
   terraform --version
   ```

3. **Required AWS Permissions** (see [versions.tf](versions.tf) for complete list):
   - EventBridge Scheduler (create/manage schedules)
   - SNS (create topics and subscriptions)
   - IAM (create roles and policies)
   - SQS (if integration enabled)
   - CloudWatch Logs (if logging enabled)

### Basic Deployment

1. **Clone and navigate to the Terraform directory**:
   ```bash
   cd aws/simple-business-notifications-eventbridge-scheduler-sns/code/terraform/
   ```

2. **Configure variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your email addresses and preferences
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Review the deployment plan**:
   ```bash
   terraform plan
   ```

5. **Deploy the infrastructure**:
   ```bash
   terraform apply
   ```

6. **Confirm email subscriptions**:
   - Check your email inbox for SNS confirmation messages
   - Click the confirmation links to activate subscriptions

## Configuration

### Required Variables

Edit `terraform.tfvars` with your specific values:

```hcl
# Essential configuration
notification_emails = [
  "manager@company.com",
  "team@company.com"
]

# Optional but recommended
environment = "production"
schedule_timezone = "America/New_York"
```

### Schedule Configuration

Customize notification schedules using cron expressions:

```hcl
# Daily reports at 9 AM on weekdays
daily_schedule_expression = "cron(0 9 ? * MON-FRI *)"

# Weekly summary every Monday at 8 AM
weekly_schedule_expression = "cron(0 8 ? * MON *)"

# Monthly reminders on the 1st at 10 AM
monthly_schedule_expression = "cron(0 10 1 * ? *)"
```

### Message Customization

Personalize notification content:

```hcl
daily_notification_subject = "Daily Business Report - Ready"
daily_notification_message = "Your customized daily message here..."
```

## Advanced Features

### SQS Integration

Enable queue-based processing for system integrations:

```hcl
enable_sqs_integration = true
enable_dlq = true  # Dead letter queue for failed messages
```

### SMS Notifications

Add SMS delivery for urgent notifications:

```hcl
notification_phone_numbers = [
  "+15551234567",  # Include country code
  "+15559876543"
]
```

### CloudWatch Logging

Enable detailed execution logging:

```hcl
enable_cloudwatch_logs = true
log_retention_days = 30
```

### Message Filtering

Configure subscription-specific filtering:

```hcl
email_filter_policy = {
  priority = ["high", "normal"]
}
```

## Testing and Validation

### Test SNS Message Delivery

```bash
# Get the topic ARN from Terraform output
SNS_TOPIC_ARN=$(terraform output -raw sns_topic_arn)

# Send a test message
aws sns publish \
    --topic-arn "$SNS_TOPIC_ARN" \
    --subject "Test Notification" \
    --message "Testing the business notification system."
```

### Verify Schedule Configuration

```bash
# List all schedules
SCHEDULE_GROUP=$(terraform output -raw schedule_group_name)
aws scheduler list-schedules --group-name "$SCHEDULE_GROUP"

# Get specific schedule details
aws scheduler get-schedule \
    --name "daily-business-report" \
    --group-name "$SCHEDULE_GROUP"
```

### Check Subscription Status

```bash
# List topic subscriptions
aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN"
```

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor schedule executions:

```bash
# View scheduler logs
aws logs describe-log-groups --log-group-name-prefix "/aws/events/scheduler"

# Stream live logs
aws logs tail "/aws/events/scheduler/your-schedule-group" --follow
```

### Common Issues

1. **Email subscriptions not confirmed**:
   - Check spam/junk folders
   - Resend confirmation via AWS Console

2. **Schedules not executing**:
   - Verify IAM role permissions
   - Check schedule state (ENABLED vs DISABLED)
   - Review timezone settings

3. **Messages not received**:
   - Test SNS topic directly
   - Check subscription filter policies
   - Verify email addresses/phone numbers

### Cost Monitoring

Track notification costs:

```bash
# View SNS costs
aws ce get-cost-and-usage \
    --time-period Start=2024-01-01,End=2024-01-31 \
    --granularity MONTHLY \
    --metrics BlendedCost \
    --group-by Type=DIMENSION,Key=SERVICE

# EventBridge Scheduler costs
aws logs describe-metric-filters \
    --log-group-name "/aws/events/scheduler/your-group"
```

## Maintenance

### Update Notification Content

Modify messages without recreating resources:

```bash
# Update variables in terraform.tfvars
terraform plan
terraform apply
```

### Add/Remove Subscribers

Update email or SMS lists:

```hcl
notification_emails = [
  "existing@company.com",
  "new-subscriber@company.com"  # Add new emails
]
```

### Schedule Maintenance

Temporarily disable schedules:

```hcl
schedules_enabled = false
```

## Cleanup

Remove all resources to avoid ongoing costs:

```bash
# Destroy all infrastructure
terraform destroy

# Confirm deletion
# Type "yes" when prompted
```

## Security Considerations

### IAM Best Practices

- Uses least privilege IAM policies
- Scheduler role limited to specific SNS topic
- Cross-account access controls implemented

### Data Protection

- SNS messages encrypted at rest (AWS managed keys)
- CloudWatch logs retention configured
- No sensitive data in notification content

### Network Security

- All communication over HTTPS
- No VPC resources created (serverless)
- Regional isolation supported

## Cost Estimation

### Typical Monthly Costs

For standard business notifications:

| Service | Usage | Estimated Cost |
|---------|-------|---------------|
| EventBridge Scheduler | 93 invocations/month | $0.09 |
| SNS Email | 93 messages | $0.00 |
| SNS SMS (optional) | 93 messages | $9.30 |
| CloudWatch Logs | 1GB/month | $0.50 |
| **Total (Email only)** | | **< $1.00** |
| **Total (with SMS)** | | **< $10.00** |

### Cost Optimization

- Use email instead of SMS for non-urgent notifications
- Adjust log retention periods for cost management
- Leverage flexible time windows for scheduler efficiency

## Support and Documentation

- **AWS EventBridge Scheduler**: [User Guide](https://docs.aws.amazon.com/scheduler/latest/UserGuide/)
- **Amazon SNS**: [Developer Guide](https://docs.aws.amazon.com/sns/latest/dg/)
- **Terraform AWS Provider**: [Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Update variable descriptions and validation
3. Maintain backward compatibility
4. Update documentation and examples
5. Follow Terraform best practices

## License

This infrastructure code is provided as part of the AWS Recipes collection. See the main repository for license information.