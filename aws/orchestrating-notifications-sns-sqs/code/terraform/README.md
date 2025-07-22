# Serverless Notification System - Terraform Implementation

This Terraform configuration deploys a complete serverless notification system using Amazon SNS, SQS, and Lambda functions. The architecture provides reliable, scalable message processing with automatic retry mechanisms and dead letter queue handling.

## Architecture Overview

The system consists of:

- **SNS Topic**: Central hub for message distribution with message filtering
- **SQS Queues**: Separate queues for email, SMS, and webhook notifications
- **Lambda Functions**: Process messages from each queue type
- **Dead Letter Queue**: Handles failed messages with dedicated processor
- **IAM Roles**: Secure access between services
- **CloudWatch Logs**: Comprehensive logging for monitoring and debugging

## Features

- ✅ **Message Filtering**: Route messages to appropriate queues based on notification type
- ✅ **Retry Logic**: Automatic retry with exponential backoff via SQS
- ✅ **Dead Letter Queue**: Capture and process failed messages
- ✅ **Security**: Encrypted queues and least-privilege IAM policies
- ✅ **Monitoring**: CloudWatch logs and metrics
- ✅ **Scalability**: Auto-scaling Lambda functions based on queue depth
- ✅ **Cost Optimization**: Pay-per-use serverless architecture

## Prerequisites

- AWS CLI installed and configured with appropriate credentials
- Terraform >= 1.0 installed
- AWS account with permissions to create SNS, SQS, Lambda, and IAM resources

## Quick Start

1. **Clone and Navigate**:
   ```bash
   cd terraform/
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

4. **Plan Deployment**:
   ```bash
   terraform plan
   ```

5. **Deploy Infrastructure**:
   ```bash
   terraform apply
   ```

## Configuration

### Required Variables

Create a `terraform.tfvars` file with the following variables:

```hcl
# AWS Configuration
aws_region = "us-east-1"
environment = "dev"

# Project Configuration
project_name = "my-notification-system"
test_email = "your-email@example.com"
webhook_url = "https://your-webhook-endpoint.com/webhook"

# Optional: Override default values
lambda_timeout = 300
lambda_memory_size = 256
sqs_max_receive_count = 3
```

### Optional Variables

All variables have sensible defaults. See `variables.tf` for the complete list of configurable options.

## Testing the System

After deployment, Terraform outputs provide convenient commands for testing:

### 1. Test Email Notification

```bash
# Get the command from terraform output
terraform output -raw test_sns_publish_command
```

### 2. Test Webhook Notification

```bash
# Get the command from terraform output
terraform output -raw test_webhook_publish_command
```

### 3. Test Broadcast Notification

```bash
# Get the command from terraform output
terraform output -raw test_broadcast_publish_command
```

### 4. Monitor Queue Depths

```bash
# Get the command from terraform output
terraform output -raw check_queue_depths_command
```

### 5. View Lambda Logs

```bash
# Get the commands from terraform output
terraform output -raw view_lambda_logs_command
```

## Message Format

### Email Notifications

```json
{
  "subject": "Email Subject",
  "message": "Email message content",
  "recipient": "recipient@example.com",
  "priority": "high"
}
```

### Webhook Notifications

```json
{
  "subject": "Webhook Subject",
  "message": "Webhook message content",
  "webhook_url": "https://api.example.com/webhook",
  "payload": {
    "custom": "data"
  }
}
```

### Message Attributes (for filtering)

```json
{
  "notification_type": {
    "DataType": "String",
    "StringValue": "email|sms|webhook|all"
  }
}
```

## Lambda Function Customization

### Email Handler

Located in `lambda_functions/email_handler.py.tpl`. To integrate with an email service:

1. Uncomment the SES integration code
2. Configure the `FROM_EMAIL` environment variable
3. Ensure SES permissions are added to the Lambda role

### Webhook Handler

Located in `lambda_functions/webhook_handler.py.tpl`. Features:

- HTTP timeout configuration
- Retry logic for server errors
- Request/response logging
- Error categorization

### DLQ Processor

Located in `lambda_functions/dlq_processor.py`. Features:

- Failed message logging
- CloudWatch metrics
- Optional S3 archiving
- Alert generation

## Monitoring and Alerting

### CloudWatch Metrics

The system automatically publishes metrics to CloudWatch:

- Queue depths
- Lambda function durations
- Error rates
- Failed message counts

### Log Groups

Each Lambda function has its own log group:

- `/aws/lambda/EmailNotificationHandler-{suffix}`
- `/aws/lambda/WebhookNotificationHandler-{suffix}`
- `/aws/lambda/DLQProcessor-{suffix}`

### Custom Alerting

To enable custom alerting:

1. Set the `ALERT_SNS_TOPIC_ARN` environment variable
2. Configure the `FAILED_MESSAGES_BUCKET` for S3 archiving
3. Customize the `dlq_processor.py` function

## Security Considerations

- All SQS queues use server-side encryption
- IAM roles follow least-privilege principles
- SNS topic has restricted access policies
- Lambda functions use VPC endpoints (if needed)

## Cost Optimization

- Lambda functions scale to zero when not in use
- SQS queues only charge for messages processed
- SNS charges per message published
- CloudWatch logs have 30-day retention

Estimated monthly costs for 1M notifications:
- SNS: ~$0.50
- SQS: ~$0.40
- Lambda: ~$0.20
- CloudWatch: ~$0.50
- **Total: ~$1.60/month**

## Troubleshooting

### Common Issues

1. **Messages not being processed**:
   - Check queue depths with the monitoring command
   - Verify Lambda function logs for errors
   - Ensure IAM permissions are correct

2. **Email notifications not sending**:
   - Verify SES configuration and verification
   - Check Lambda function environment variables
   - Review CloudWatch logs for errors

3. **Webhook timeouts**:
   - Increase Lambda timeout if needed
   - Verify webhook endpoint availability
   - Check network connectivity

### Debug Commands

```bash
# Check queue attributes
aws sqs get-queue-attributes --queue-url $(terraform output -raw email_queue_url) --attribute-names All

# View recent Lambda invocations
aws lambda get-function --function-name $(terraform output -raw email_lambda_function_name)

# Check SNS topic subscriptions
aws sns list-subscriptions-by-topic --topic-arn $(terraform output -raw sns_topic_arn)
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will permanently delete all resources and cannot be undone.

## Advanced Configuration

### Multi-Region Deployment

To deploy across multiple regions, use Terraform workspaces:

```bash
terraform workspace new us-west-2
terraform apply -var="aws_region=us-west-2"
```

### Custom Lambda Layers

Add Lambda layers for common dependencies:

```hcl
resource "aws_lambda_layer_version" "notification_layer" {
  filename   = "notification_layer.zip"
  layer_name = "notification-dependencies"
  compatible_runtimes = ["python3.9"]
}
```

### VPC Configuration

For private subnet deployment:

```hcl
resource "aws_lambda_function" "email_handler" {
  # ... existing configuration ...
  
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
}
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Support

For issues and questions:

1. Check the troubleshooting section
2. Review CloudWatch logs
3. Consult AWS documentation
4. Open an issue in the repository

## License

This code is provided as-is for educational and demonstration purposes.