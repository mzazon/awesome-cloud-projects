# Terraform Infrastructure for AWS CloudWatch Monitoring

This directory contains Terraform Infrastructure as Code (IaC) for implementing basic monitoring using Amazon CloudWatch Alarms and SNS notifications, as described in the recipe "Basic Monitoring with CloudWatch Alarms".

## Architecture Overview

This Terraform configuration creates:

- **SNS Topic**: For alarm notifications with email subscriptions
- **CloudWatch Alarms**: 
  - High CPU Utilization (EC2 instances)
  - High Response Time (Application Load Balancers)
  - High Database Connections (RDS instances)
- **CloudWatch Dashboard**: Optional unified view of all monitored metrics
- **IAM Policies**: Proper permissions for CloudWatch to publish to SNS

## Prerequisites

1. **AWS CLI** v2 installed and configured
2. **Terraform** v1.6.0 or later
3. **AWS Account** with appropriate permissions for:
   - CloudWatch (alarms, dashboards)
   - SNS (topics, subscriptions)
   - IAM (policies)
4. **Email Address** for receiving alarm notifications

## Required AWS Permissions

Your AWS credentials need the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:*",
        "sns:*",
        "iam:GetRole",
        "iam:PassRole"
      ],
      "Resource": "*"
    }
  ]
}
```

## Quick Start

### 1. Initialize Terraform

```bash
terraform init
```

### 2. Review the Plan

```bash
terraform plan -var="notification_email=your-email@example.com"
```

### 3. Apply the Configuration

```bash
terraform apply -var="notification_email=your-email@example.com"
```

### 4. Confirm Email Subscription

After deployment, check your email and confirm the SNS subscription to receive alarm notifications.

## Configuration Options

### Required Variables

- `notification_email`: Email address for alarm notifications

### Optional Variables

You can customize the deployment by creating a `terraform.tfvars` file:

```hcl
# terraform.tfvars
notification_email = "ops-team@company.com"
sns_topic_name     = "prod-monitoring-alerts"
cpu_threshold      = 85
response_time_threshold = 2.0
db_connections_threshold = 100
create_dashboard   = true

tags = {
  Project     = "Production-Monitoring"
  Environment = "Production"
  Team        = "DevOps"
}
```

### Available Variables

| Variable | Description | Default | Type |
|----------|-------------|---------|------|
| `notification_email` | Email for notifications | *required* | string |
| `sns_topic_name` | SNS topic name | "monitoring-alerts" | string |
| `cpu_threshold` | CPU alarm threshold (%) | 80 | number |
| `response_time_threshold` | Response time threshold (seconds) | 1.0 | number |
| `db_connections_threshold` | DB connections threshold | 80 | number |
| `alarm_period` | Alarm evaluation period (seconds) | 300 | number |
| `create_dashboard` | Create CloudWatch dashboard | true | bool |
| `tags` | Resource tags | see variables.tf | map(string) |

## Deployment Examples

### Basic Deployment

```bash
terraform apply -var="notification_email=admin@example.com"
```

### Custom Configuration

```bash
terraform apply \
  -var="notification_email=ops@example.com" \
  -var="cpu_threshold=90" \
  -var="response_time_threshold=2.0" \
  -var="create_dashboard=false"
```

### Production Deployment with Variables File

Create `terraform.tfvars`:

```hcl
notification_email = "alerts@company.com"
sns_topic_name     = "prod-monitoring"
cpu_threshold      = 85
response_time_threshold = 1.5
db_connections_threshold = 120
create_dashboard   = true

tags = {
  Project     = "Production-Monitoring"
  Environment = "Production"
  Team        = "Platform"
  CostCenter  = "Engineering"
}
```

Then deploy:

```bash
terraform apply
```

## Validation

After deployment, verify the setup:

### 1. Check SNS Topic and Subscription

```bash
# List SNS topics
aws sns list-topics --query "Topics[?contains(TopicArn, 'monitoring-alerts')]"

# Check subscription status
aws sns list-subscriptions-by-topic --topic-arn $(terraform output -raw sns_topic_arn)
```

### 2. Verify CloudWatch Alarms

```bash
# List created alarms
aws cloudwatch describe-alarms --query "MetricAlarms[].{Name:AlarmName,State:StateValue,Threshold:Threshold}"
```

### 3. Test Alarm Notification

```bash
# Test CPU alarm notification
aws cloudwatch set-alarm-state \
  --alarm-name $(terraform output -raw cpu_alarm_name) \
  --state-value ALARM \
  --state-reason "Testing alarm notification"

# Reset alarm state
aws cloudwatch set-alarm-state \
  --alarm-name $(terraform output -raw cpu_alarm_name) \
  --state-value OK \
  --state-reason "Test completed"
```

## Outputs

After successful deployment, Terraform provides these outputs:

- `sns_topic_arn`: ARN of the SNS topic
- `cpu_alarm_name`: Name of the CPU alarm
- `response_time_alarm_name`: Name of the response time alarm
- `db_connections_alarm_name`: Name of the database connections alarm
- `dashboard_url`: URL to access the CloudWatch dashboard
- `validation_commands`: CLI commands to validate the setup
- `estimated_monthly_cost`: Cost breakdown for the monitoring infrastructure

## Monitoring Dashboard

If `create_dashboard = true`, a CloudWatch dashboard will be created showing:

- Key metrics overview (CPU, Response Time, DB Connections)
- Alarm states visualization
- Historical trend analysis

Access the dashboard using the URL provided in the `dashboard_url` output.

## Cost Estimation

The monitoring infrastructure costs approximately:

- **CloudWatch Alarms**: $0.10 per alarm per month (3 alarms = $0.30)
- **SNS Email Notifications**: Free for first 1,000 emails/month
- **CloudWatch Dashboard**: Free (up to 3 dashboards)
- **Total Base Cost**: ~$0.30 per month

## Customization

### Adding More Alarms

To add additional alarms, modify `main.tf`:

```hcl
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "LambdaErrors-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = [aws_sns_topic.monitoring_alerts.arn]
}
```

### Multiple Notification Channels

Add SMS notifications:

```hcl
resource "aws_sns_topic_subscription" "sms_alerts" {
  topic_arn = aws_sns_topic.monitoring_alerts.arn
  protocol  = "sms"
  endpoint  = var.notification_phone
}
```

### Environment-Specific Configuration

Use Terraform workspaces:

```bash
# Create and switch to production workspace
terraform workspace new production
terraform workspace select production

# Apply with environment-specific variables
terraform apply -var-file="production.tfvars"
```

## Troubleshooting

### Common Issues

1. **Email Subscription Pending**: Check your email and confirm the SNS subscription
2. **Alarm Not Triggering**: Verify resources exist and metrics are being published
3. **Permission Errors**: Ensure AWS credentials have required permissions
4. **Resource Naming Conflicts**: Random suffix should prevent conflicts

### Debug Commands

```bash
# Check Terraform state
terraform state list

# View specific resource
terraform state show aws_sns_topic.monitoring_alerts

# Validate configuration
terraform validate

# Format configuration
terraform fmt
```

## Cleanup

To remove all resources:

```bash
terraform destroy
```

Or selectively remove resources:

```bash
# Remove only the dashboard
terraform destroy -target=aws_cloudwatch_dashboard.monitoring_dashboard

# Remove specific alarm
terraform destroy -target=aws_cloudwatch_metric_alarm.high_cpu_utilization
```

## Security Considerations

1. **SNS Topic Policy**: Restricts CloudWatch access to your AWS account
2. **Email Confirmation**: Ensures only authorized recipients get notifications
3. **IAM Permissions**: Use least privilege principle
4. **State File Security**: Consider encrypting Terraform state files

## Best Practices

1. **State Management**: Use remote state backend for production
2. **Variable Management**: Use terraform.tfvars for sensitive values
3. **Tagging**: Implement consistent tagging strategy
4. **Version Control**: Pin provider versions for reproducibility
5. **Testing**: Validate alarms trigger correctly before production use

## Next Steps

1. Confirm email subscription for notifications
2. Test alarm notifications
3. Adjust thresholds based on application behavior
4. Consider adding more alarms for other AWS services
5. Implement automated remediation actions

## Support

For issues with this Terraform configuration:

1. Check the original recipe documentation
2. Review AWS CloudWatch and SNS documentation
3. Validate AWS permissions and credentials
4. Check Terraform logs for detailed error messages

## Version History

- **v1.0**: Initial Terraform configuration
- **v1.1**: Added dashboard support and advanced variables
- **v1.2**: Enhanced outputs and validation commands