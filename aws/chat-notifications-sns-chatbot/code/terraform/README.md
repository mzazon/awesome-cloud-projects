# Chat Notifications with SNS and Chatbot - Terraform Infrastructure

This Terraform configuration creates a complete chat notification system using Amazon SNS integrated with AWS Chatbot for real-time alerts to Slack or Microsoft Teams channels.

## Architecture Overview

The infrastructure includes:

- **Amazon SNS Topic**: Central messaging hub for all notifications
- **AWS Chatbot**: Integration service for chat platform delivery
- **CloudWatch Alarms**: Example monitoring alarms for testing
- **IAM Roles**: Security permissions for Chatbot operations
- **KMS Encryption**: Server-side encryption for message security

## Prerequisites

1. **AWS Account**: With appropriate permissions for SNS, Chatbot, CloudWatch, and IAM
2. **Terraform**: Version 1.0 or later
3. **AWS CLI**: Configured with valid credentials
4. **Slack/Teams Access**: Admin permissions in your chat workspace

## Quick Start

### 1. Basic Deployment (Without Chat Integration)

```bash
# Clone the repository and navigate to terraform directory
cd aws/chat-notifications-sns-chatbot/code/terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply
```

This creates the SNS topic and CloudWatch alarms, but requires manual Slack setup for full functionality.

### 2. Full Deployment (With Slack Integration)

First, set up Slack integration manually:

1. **Configure AWS Chatbot for Slack**:
   - Go to [AWS Chatbot Console](https://console.aws.amazon.com/chatbot/)
   - Choose 'Slack' as chat client
   - Click 'Configure' and authorize AWS Chatbot in your Slack workspace
   - Note down your Slack Team ID and Channel ID

2. **Deploy with Slack Configuration**:

```bash
# Create terraform.tfvars file with your Slack details
cat > terraform.tfvars << EOF
aws_region         = "us-east-1"
environment        = "dev"
slack_team_id      = "T07EA123LEP"    # Your Slack workspace ID
slack_channel_id   = "C07EZ1ABC23"    # Your Slack channel ID
project_name       = "my-alerts"
EOF

# Deploy with Slack integration
terraform apply
```

### 3. Test the Deployment

After deployment, test the notification system:

```bash
# Use the output command to send a test notification
terraform output test_notification_command
# Copy and run the command to test

# Verify SNS topic configuration
terraform output sns_topic_verification_command
# Copy and run the command to verify
```

## Configuration Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `aws_region` | AWS region for deployment | `us-east-1` |

### Slack Integration Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `slack_team_id` | Slack workspace ID | `T07EA123LEP` |
| `slack_channel_id` | Slack channel ID | `C07EZ1ABC23` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Environment name | `dev` |
| `project_name` | Project name for resources | `chat-notifications` |
| `sns_topic_display_name` | Display name for SNS topic | `Team Notifications Topic` |
| `enable_sns_encryption` | Enable SNS encryption | `true` |
| `cloudwatch_alarm_enabled` | Create demo alarms | `true` |
| `cloudwatch_alarm_threshold` | CPU threshold for demo alarm | `1.0` |
| `chatbot_logging_level` | Chatbot logging level | `INFO` |

### Advanced Configuration

#### Multiple Notification Channels

Add email or SMS notifications alongside Slack:

```hcl
additional_sns_subscriptions = {
  "team-email" = {
    protocol = "email"
    endpoint = "alerts@company.com"
  }
  "oncall-sms" = {
    protocol = "sms"
    endpoint = "+1234567890"
  }
}
```

#### Custom Tags

Apply additional tags to all resources:

```hcl
tags = {
  Owner       = "DevOps Team"
  CostCenter  = "Engineering"
  Compliance  = "SOC2"
}
```

## Terraform Files Structure

```
terraform/
├── main.tf          # Main infrastructure resources
├── variables.tf     # Input variable definitions
├── outputs.tf       # Output values and test commands
├── versions.tf      # Terraform and provider requirements
├── terraform.tfvars # Your variable values (create this)
└── README.md        # This file
```

## Resource Details

### Created Resources

1. **SNS Topic** (`aws_sns_topic.team_notifications`)
   - Encrypted with AWS managed KMS key
   - Configured for CloudWatch alarm integration

2. **SNS Topic Policy** (`aws_sns_topic_policy.team_notifications_policy`)
   - Allows CloudWatch to publish messages
   - Restricts access to current AWS account

3. **IAM Role** (`aws_iam_role.chatbot_role`)
   - Used by AWS Chatbot for permissions
   - Includes ReadOnlyAccess for security

4. **Chatbot Configuration** (`aws_chatbot_slack_channel_configuration.team_alerts`)
   - Links SNS topic to Slack channel
   - Only created if Slack IDs are provided

5. **CloudWatch Alarms** (multiple resources)
   - Demo CPU utilization alarm
   - Example memory and error rate alarms
   - All configured to notify SNS topic

### Security Features

- **Encryption**: SNS messages encrypted at rest and in transit
- **Least Privilege**: Chatbot role has minimal required permissions
- **Guardrails**: ReadOnlyAccess policy prevents destructive commands
- **Account Isolation**: Policies restrict cross-account access

## Validation and Testing

### 1. Verify Infrastructure

```bash
# Check SNS topic configuration
terraform output sns_topic_verification_command | bash

# Check CloudWatch alarm status
terraform output cloudwatch_alarm_verification_command | bash

# List SNS subscriptions
terraform output sns_subscriptions_verification_command | bash
```

### 2. Test Notifications

```bash
# Send test notification
aws sns publish \
  --topic-arn $(terraform output -raw sns_topic_arn) \
  --subject "🚨 Test Alert" \
  --message "Test notification from Terraform deployment"
```

### 3. Monitor in AWS Console

- **SNS Console**: Verify topic creation and subscriptions
- **Chatbot Console**: Check channel configuration
- **CloudWatch Console**: Monitor alarm states
- **IAM Console**: Review role permissions

## Troubleshooting

### Common Issues

1. **Chatbot Not Created**
   - Ensure `slack_team_id` and `slack_channel_id` are set
   - Verify Slack workspace is authorized in AWS Chatbot console

2. **Notifications Not Received**
   - Check SNS topic subscriptions: `aws sns list-subscriptions-by-topic --topic-arn <topic-arn>`
   - Verify Slack channel ID is correct
   - Check Chatbot configuration in AWS console

3. **Permission Errors**
   - Ensure AWS credentials have required permissions
   - Verify IAM role policies are attached correctly

4. **Terraform Errors**
   - Run `terraform validate` to check configuration syntax
   - Use `terraform plan` to preview changes before applying

### Debug Commands

```bash
# Check Terraform state
terraform state list

# Show specific resource details
terraform state show aws_sns_topic.team_notifications

# Validate configuration
terraform validate

# Format code
terraform fmt
```

## Cleanup

To remove all created resources:

```bash
# Destroy all resources
terraform destroy

# Confirm when prompted
```

**Note**: This will delete all notifications and alarm configurations. Ensure you have backups of any important configurations.

## Cost Considerations

### Estimated Monthly Costs

- **SNS Messages**: $0.50 per million messages
- **CloudWatch Alarms**: $0.10 per alarm per month
- **CloudWatch Logs**: $0.50 per GB ingested
- **AWS Chatbot**: No additional charges

### Cost Optimization Tips

1. **Disable Demo Alarms**: Set `cloudwatch_alarm_enabled = false` for production
2. **Reduce Logging**: Set `chatbot_logging_level = "ERROR"` to reduce log volume
3. **Message Filtering**: Use SNS message filtering to reduce unnecessary notifications
4. **Alarm Consolidation**: Combine related alarms to reduce costs

## Extensions and Customization

### 1. Multi-Environment Setup

```hcl
# dev.tfvars
environment = "dev"
cloudwatch_alarm_enabled = true
chatbot_logging_level = "INFO"

# prod.tfvars
environment = "prod"
cloudwatch_alarm_enabled = false
chatbot_logging_level = "ERROR"
```

### 2. Custom Alarms

Add your own CloudWatch alarms:

```hcl
resource "aws_cloudwatch_metric_alarm" "custom_alarm" {
  alarm_name          = "my-custom-alarm"
  alarm_description   = "Custom application alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MyCustomMetric"
  namespace           = "MyApp"
  period              = 300
  statistic           = "Average"
  threshold           = 100
  
  alarm_actions = [aws_sns_topic.team_notifications.arn]
}
```

### 3. Microsoft Teams Integration

Replace Slack configuration with Teams:

```hcl
resource "aws_chatbot_teams_channel_configuration" "team_alerts" {
  configuration_name   = "team-alerts"
  iam_role_arn        = aws_iam_role.chatbot_role.arn
  team_id             = "your-teams-team-id"
  tenant_id           = "your-tenant-id"
  
  sns_topic_arns = [aws_sns_topic.team_notifications.arn]
}
```

## Support and Contributing

For issues with this Terraform configuration:

1. Check the [troubleshooting section](#troubleshooting)
2. Review AWS Chatbot documentation
3. Validate your Slack workspace integration

## References

- [AWS Chatbot Documentation](https://docs.aws.amazon.com/chatbot/)
- [Amazon SNS Documentation](https://docs.aws.amazon.com/sns/)
- [CloudWatch Alarms Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)