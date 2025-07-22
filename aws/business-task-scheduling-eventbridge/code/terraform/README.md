# Automated Business Task Scheduling - Terraform Implementation

This Terraform configuration deploys an automated business task scheduling system using AWS EventBridge Scheduler, Lambda, S3, and SNS. The system automates recurring business tasks like report generation, data processing, and notifications.

## Architecture Overview

The solution includes:

- **EventBridge Scheduler**: Manages flexible schedules for business tasks
- **Lambda Function**: Processes different types of business tasks
- **S3 Bucket**: Stores generated reports and processed data
- **SNS Topic**: Sends notifications about task completion/failure
- **CloudWatch**: Monitors Lambda execution and provides logging
- **IAM Roles**: Secure access between services

## Prerequisites

- AWS CLI installed and configured
- Terraform >= 1.5 installed
- Appropriate AWS permissions for creating the required resources
- Email address for notifications (optional)

## Quick Start

1. **Clone and Navigate**:
   ```bash
   cd aws/automated-business-task-scheduling-eventbridge-scheduler-lambda/code/terraform/
   ```

2. **Configure Variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your preferred settings
   ```

3. **Initialize and Deploy**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Confirm Email Subscription** (if configured):
   Check your email for the SNS subscription confirmation and click the confirmation link.

## Configuration

### Required Variables

The deployment uses sensible defaults, but you may want to customize:

```hcl
# Basic configuration
environment = "dev"
notification_email = "admin@yourcompany.com"
timezone = "America/New_York"

# Feature toggles
schedules_enabled = true
enable_hourly_processing = true
enable_weekly_notifications = true
enable_monitoring = true
```

### Schedule Configuration

Customize the timing of automated tasks:

```hcl
# Daily reports at 9 AM
daily_report_schedule = "cron(0 9 * * ? *)"

# Hourly data processing
hourly_processing_schedule = "rate(1 hour)"

# Weekly notifications on Monday at 10 AM
weekly_notification_schedule = "cron(0 10 ? * MON *)"
```

### Environment-Specific Configurations

**Development**:
```hcl
environment = "dev"
schedules_enabled = false     # Disable automated execution
enable_monitoring = false     # Reduce costs
log_retention_days = 7       # Shorter retention
lambda_memory_size = 128     # Smaller instance
```

**Production**:
```hcl
environment = "prod"
schedules_enabled = true
enable_monitoring = true
log_retention_days = 90
lambda_memory_size = 512
lambda_reserved_concurrency = 10  # Concurrency limits
```

## Deployment

### Standard Deployment

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

### Targeted Deployment

Deploy specific components:

```bash
# Deploy only the Lambda function
terraform apply -target=aws_lambda_function.business_task_processor

# Deploy only the schedules
terraform apply -target=aws_scheduler_schedule_group.business_automation
```

### Environment-Specific Deployment

```bash
# Deploy to development
terraform apply -var="environment=dev" -var="schedules_enabled=false"

# Deploy to production
terraform apply -var="environment=prod" -var="enable_monitoring=true"
```

## Testing

### Test Lambda Function

```bash
# Get the function name from outputs
FUNCTION_NAME=$(terraform output -raw lambda_function_name)

# Test report generation
aws lambda invoke \
  --function-name $FUNCTION_NAME \
  --payload '{"task_type":"report"}' \
  response.json

# View the response
cat response.json
```

### Verify Schedules

```bash
# List all schedules
SCHEDULE_GROUP=$(terraform output -raw schedule_group_name)
aws scheduler list-schedules --group-name $SCHEDULE_GROUP

# Get schedule details
aws scheduler get-schedule --name "daily-report-schedule" --group-name $SCHEDULE_GROUP
```

### Check S3 Reports

```bash
# List generated reports
BUCKET_NAME=$(terraform output -raw s3_bucket_name)
aws s3 ls s3://$BUCKET_NAME/reports/

# Download a report
aws s3 cp s3://$BUCKET_NAME/reports/ ./reports/ --recursive
```

### Monitor Execution

```bash
# View Lambda logs
FUNCTION_NAME=$(terraform output -raw lambda_function_name)
aws logs tail /aws/lambda/$FUNCTION_NAME --follow

# Check CloudWatch alarms (if monitoring enabled)
aws cloudwatch describe-alarms --alarm-names $(terraform output -raw lambda_function_name)-errors
```

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor Lambda execution:
```bash
# Stream live logs
aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow

# Search for errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/$(terraform output -raw lambda_function_name) \
  --filter-pattern "ERROR"
```

### CloudWatch Alarms

If monitoring is enabled, check alarm status:
```bash
# List alarms
aws cloudwatch describe-alarms --alarm-name-prefix $(terraform output -raw lambda_function_name)

# Get alarm history
aws cloudwatch describe-alarm-history --alarm-name $(terraform output -raw lambda_function_name)-errors
```

### Schedule Execution History

```bash
# Check schedule execution history (requires AWS Console or API calls)
aws logs describe-log-groups --log-group-name-prefix /aws/events/rule/
```

### Common Issues

1. **Email notifications not received**:
   - Check spam folder
   - Confirm SNS subscription in email
   - Verify email address in terraform.tfvars

2. **Lambda timeouts**:
   - Increase `lambda_timeout` variable
   - Check CloudWatch logs for performance issues

3. **Schedule not triggering**:
   - Verify `schedules_enabled = true`
   - Check schedule expression syntax
   - Ensure IAM roles have correct permissions

4. **S3 access denied**:
   - Verify S3 bucket policy
   - Check Lambda execution role permissions

## Cost Optimization

### Resource Costs

Typical monthly costs for moderate usage:
- **Lambda**: ~$0.20 per 1M executions + $0.0000166667 per GB-second
- **EventBridge Scheduler**: ~$1.00 per million schedule invocations
- **S3**: ~$0.023 per GB for Standard storage
- **SNS**: ~$0.50 per million notifications
- **CloudWatch**: ~$0.50 per GB ingested

### Cost Reduction Strategies

1. **Optimize Lambda**:
   ```hcl
   lambda_memory_size = 128  # Use minimum required memory
   lambda_timeout = 30       # Reduce timeout if possible
   ```

2. **Reduce Schedule Frequency**:
   ```hcl
   hourly_processing_schedule = "rate(2 hours)"  # Less frequent processing
   ```

3. **Lifecycle Policies**:
   ```hcl
   enable_s3_lifecycle = true
   s3_intelligent_tiering_days = 30
   s3_glacier_transition_days = 90
   ```

4. **Log Retention**:
   ```hcl
   log_retention_days = 7  # Shorter retention in non-prod
   ```

## Security

### Security Features

- **Encryption**: S3 and SNS encryption enabled by default
- **IAM**: Least privilege principle for all roles
- **Network**: Public subnet deployment (VPC optional)
- **Access Control**: S3 public access blocked
- **Versioning**: S3 versioning enabled for data protection

### Security Best Practices

1. **Enable VPC Deployment** (optional):
   ```hcl
   # Add VPC configuration to Lambda
   vpc_config {
     subnet_ids         = var.private_subnet_ids
     security_group_ids = var.lambda_security_group_ids
   }
   ```

2. **Use Customer-Managed KMS Keys**:
   ```hcl
   # Replace AWS managed keys with customer managed
   kms_key_id = aws_kms_key.business_automation.arn
   ```

3. **Enable CloudTrail** (separate deployment):
   ```bash
   # Monitor API calls
   aws cloudtrail create-trail --name business-automation-trail
   ```

## Cleanup

### Complete Cleanup

```bash
# Destroy all resources
terraform destroy
```

### Partial Cleanup

```bash
# Disable schedules without destroying infrastructure
terraform apply -var="schedules_enabled=false"

# Remove monitoring only
terraform apply -var="enable_monitoring=false"
```

### Manual Cleanup (if needed)

```bash
# Empty S3 bucket before destruction
BUCKET_NAME=$(terraform output -raw s3_bucket_name)
aws s3 rm s3://$BUCKET_NAME --recursive

# Delete CloudWatch log groups
aws logs delete-log-group --log-group-name /aws/lambda/$(terraform output -raw lambda_function_name)
```

## Outputs

After deployment, Terraform provides useful outputs:

```bash
# View all outputs
terraform output

# Get specific values
terraform output lambda_function_name
terraform output s3_bucket_name
terraform output sns_topic_arn
```

Key outputs include:
- Resource names and ARNs
- Schedule configuration
- Monitoring setup
- Next steps and testing commands

## Customization

### Adding New Task Types

1. **Update Lambda Function**:
   ```python
   elif task_type == 'custom_task':
       result = process_custom_task()
   ```

2. **Create New Schedule**:
   ```hcl
   resource "aws_scheduler_schedule" "custom_task" {
     name = "custom-task-schedule"
     schedule_expression = "rate(6 hours)"
     # ... configuration
   }
   ```

### Integration with Existing Systems

1. **Database Integration**:
   ```hcl
   # Add database access to Lambda role
   statement {
     effect = "Allow"
     actions = ["rds:DescribeDBInstances"]
     resources = ["*"]
   }
   ```

2. **API Gateway Integration**:
   ```hcl
   # Add API Gateway for manual triggers
   resource "aws_api_gateway_rest_api" "business_automation" {
     name = "business-automation-api"
   }
   ```

## Support

For issues with this infrastructure:

1. Check the [original recipe documentation](../../../automated-business-task-scheduling-eventbridge-scheduler-lambda.md)
2. Review AWS service documentation:
   - [EventBridge Scheduler](https://docs.aws.amazon.com/scheduler/)
   - [AWS Lambda](https://docs.aws.amazon.com/lambda/)
   - [Amazon S3](https://docs.aws.amazon.com/s3/)
   - [Amazon SNS](https://docs.aws.amazon.com/sns/)
3. Check Terraform AWS provider documentation

## Contributing

To contribute improvements:

1. Test changes in development environment
2. Ensure all variables have appropriate validation
3. Update documentation for new features
4. Follow Terraform best practices
5. Test cleanup procedures