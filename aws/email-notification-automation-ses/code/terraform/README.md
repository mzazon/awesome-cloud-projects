# Terraform Infrastructure for Automated Email Notification Systems

This directory contains Terraform Infrastructure as Code (IaC) for deploying an automated email notification system using Amazon SES, AWS Lambda, and Amazon EventBridge.

## Architecture Overview

The infrastructure creates a scalable, event-driven email automation system with the following components:

- **Amazon SES**: Email delivery service with template support
- **AWS Lambda**: Serverless function for processing email events
- **Amazon EventBridge**: Event routing and orchestration
- **Amazon CloudWatch**: Monitoring, logging, and alerting
- **Amazon S3**: Storage for Lambda deployment packages
- **AWS IAM**: Security roles and policies

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
2. **Terraform** >= 1.0 installed
3. **AWS account** with permissions to create:
   - SES identities and templates
   - Lambda functions and execution roles
   - EventBridge buses and rules
   - CloudWatch alarms and log groups
   - S3 buckets and objects
   - IAM roles and policies
4. **Verified email addresses** in Amazon SES (for sandbox accounts)
5. Estimated cost: $5-15 per month for development/testing workloads

## Quick Start

### 1. Clone and Navigate

```bash
cd aws/automated-email-notification-systems-ses-lambda-eventbridge/code/terraform/
```

### 2. Configure Variables

Copy the example variables file and customize it:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set at minimum:

```hcl
sender_email = "your-verified-email@example.com"
recipient_email = "test-recipient@example.com"
```

### 3. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply
```

### 4. Verify Deployment

After deployment, use the output commands to verify:

```bash
# Check Lambda function
terraform output -raw verification_commands | jq -r '.check_lambda_function' | bash

# Check SES statistics
terraform output -raw verification_commands | jq -r '.check_ses_statistics' | bash
```

### 5. Test the System

Send a test event using the provided sample:

```bash
# Get the test command
terraform output -raw aws_cli_test_command

# Execute the test (copy and run the output from above)
```

Check your email for the notification and view Lambda logs in CloudWatch.

## Configuration Options

### Core Settings

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `sender_email` | Verified sender email address | - | Yes |
| `recipient_email` | Default recipient for testing | "" | No |
| `project_name` | Project name for resource naming | "email-automation" | No |
| `environment` | Environment (dev/staging/prod) | "dev" | No |
| `aws_region` | AWS region for deployment | "us-east-1" | No |

### Lambda Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `lambda_timeout` | Function timeout in seconds | 30 |
| `lambda_memory_size` | Memory allocation in MB | 256 |
| `lambda_runtime` | Python runtime version | "python3.11" |

### EventBridge Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_eventbridge_custom_bus` | Create custom event bus | true |
| `eventbridge_bus_name` | Custom bus name (auto-generated if empty) | "" |

### Monitoring Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_cloudwatch_alarms` | Enable CloudWatch alarms | true |
| `lambda_error_threshold` | Lambda error alarm threshold | 1 |
| `ses_bounce_threshold` | SES bounce alarm threshold | 5 |

### Email Template Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `email_template_name` | SES template name | "NotificationTemplate" |
| `email_template_subject` | Email subject template | "{{subject}}" |
| `email_template_html` | HTML email template | (See variables.tf) |
| `email_template_text` | Text email template | (See variables.tf) |

## Usage Examples

### Basic Email Notification

```bash
aws events put-events --entries '[
  {
    "Source": "custom.application",
    "DetailType": "Email Notification Request",
    "Detail": "{\"emailConfig\":{\"recipient\":\"user@example.com\",\"subject\":\"Test Alert\"},\"title\":\"System Alert\",\"message\":\"This is a test notification.\"}",
    "EventBusName": "your-event-bus-name"
  }
]'
```

### Priority Alert

```bash
aws events put-events --entries '[
  {
    "Source": "custom.application",
    "DetailType": "Priority Alert",
    "Detail": "{\"priority\":\"high\",\"emailConfig\":{\"recipient\":\"admin@example.com\",\"subject\":\"Critical Alert\"},\"title\":\"System Failure\",\"message\":\"Immediate attention required.\"}",
    "EventBusName": "your-event-bus-name"
  }
]'
```

## Monitoring and Troubleshooting

### CloudWatch Logs

View Lambda function logs:

```bash
aws logs describe-log-streams \
  --log-group-name /aws/lambda/your-function-name \
  --order-by LastEventTime --descending
```

### CloudWatch Alarms

The infrastructure creates alarms for:

- Lambda function errors
- SES bounce rate
- Email processing errors (from logs)

### Common Issues

1. **Email not received**: Check SES email verification status
2. **Lambda errors**: Review CloudWatch logs for detailed error messages
3. **EventBridge not triggering**: Verify event pattern matching
4. **Permission denied**: Check IAM roles and policies

## Security Considerations

This infrastructure implements security best practices:

- **Least privilege IAM**: Lambda role has minimal required permissions
- **Encrypted storage**: S3 bucket uses server-side encryption
- **Private resources**: Lambda function is not publicly accessible
- **Secure communication**: All AWS service communication uses TLS
- **Access controls**: S3 bucket blocks public access

## Cost Optimization

To minimize costs:

- **Lambda**: Pay-per-invocation pricing, no fixed costs
- **SES**: First 200 emails/day are free, then $0.10 per 1,000 emails
- **EventBridge**: First 100 million events/month are free
- **CloudWatch**: Free tier covers basic monitoring
- **S3**: Minimal storage costs for deployment packages

## Cleanup

To remove all infrastructure:

```bash
terraform destroy
```

This will delete all resources created by this Terraform configuration. Note that some resources like CloudWatch logs may have a retention period.

## Advanced Configuration

### Custom Email Templates

You can customize email templates by modifying the template variables:

```hcl
email_template_html = "<html><body><h1>{{title}}</h1><p>{{message}}</p><footer>{{timestamp}}</footer></body></html>"
email_template_text = "{{title}}\n{{message}}\nSent: {{timestamp}}"
```

### Multiple Event Patterns

The infrastructure supports multiple EventBridge rules. You can extend by adding more rules in `main.tf`.

### Integration with Other Services

This infrastructure can be integrated with:

- **API Gateway**: For webhook-based email triggers
- **S3**: For file-based event triggers
- **DynamoDB**: For database change notifications
- **CloudTrail**: For audit-based notifications

## Support

For issues with this infrastructure:

1. Check the [original recipe documentation](../../automated-email-notification-systems-ses-lambda-eventbridge.md)
2. Review AWS service documentation:
   - [Amazon SES](https://docs.aws.amazon.com/ses/)
   - [AWS Lambda](https://docs.aws.amazon.com/lambda/)
   - [Amazon EventBridge](https://docs.aws.amazon.com/eventbridge/)
3. Check Terraform AWS provider documentation
4. Review CloudWatch logs for runtime errors

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update variable descriptions and validation rules
3. Add outputs for new resources
4. Update this README with new configuration options
5. Ensure security best practices are maintained