# Simple Log Analysis with CloudWatch Insights and SNS - Terraform

This Terraform configuration creates an automated log monitoring solution that uses CloudWatch Logs Insights to query application logs for specific error patterns and automatically sends notifications via SNS when critical issues are detected.

## Architecture

The solution includes the following AWS resources:

- **CloudWatch Log Group**: Stores application logs with configurable retention
- **Lambda Function**: Analyzes logs using CloudWatch Logs Insights queries
- **SNS Topic**: Sends alert notifications via email
- **EventBridge Rule**: Schedules automated log analysis
- **IAM Role and Policies**: Provides least-privilege access for Lambda function

## Prerequisites

- AWS CLI installed and configured
- Terraform >= 1.0 installed
- Appropriate AWS permissions for creating CloudWatch, SNS, Lambda, IAM, and EventBridge resources
- Valid email address for receiving notifications

## Quick Start

1. **Clone and Navigate**:
   ```bash
   cd terraform/
   ```

2. **Initialize Terraform**:
   ```bash
   terraform init
   ```

3. **Configure Variables**:
   Create a `terraform.tfvars` file:
   ```hcl
   project_name      = "my-log-analysis"
   environment       = "dev"
   aws_region        = "us-east-1"
   notification_email = "your-email@example.com"
   log_group_name    = "/aws/lambda/my-app"
   ```

4. **Plan and Apply**:
   ```bash
   terraform plan
   terraform apply
   ```

5. **Confirm Email Subscription**:
   Check your email and confirm the SNS subscription.

## Configuration Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_name` | Project name prefix for resources | `log-analysis` | No |
| `environment` | Environment (dev/staging/prod) | `dev` | No |
| `aws_region` | AWS region for deployment | `us-east-1` | No |
| `notification_email` | Email for SNS notifications | `""` | Yes |
| `log_group_name` | CloudWatch Log Group name | `/aws/lambda/demo-app` | No |
| `log_retention_days` | Log retention period | `7` | No |
| `lambda_timeout` | Lambda timeout in seconds | `60` | No |
| `lambda_memory_size` | Lambda memory in MB | `256` | No |
| `analysis_schedule` | EventBridge schedule expression | `rate(5 minutes)` | No |
| `error_patterns` | List of error patterns to monitor | `["ERROR", "CRITICAL", "FATAL"]` | No |
| `query_time_range_minutes` | Query time range in minutes | `10` | No |
| `max_errors_to_display` | Max errors in notifications | `5` | No |
| `enable_sns_subscription` | Create email subscription | `true` | No |

## Example terraform.tfvars

```hcl
# Basic configuration
project_name      = "my-log-analysis"
environment       = "prod"
aws_region        = "us-east-1"
notification_email = "ops-team@company.com"

# Log monitoring configuration
log_group_name    = "/aws/lambda/production-app"
log_retention_days = 30
analysis_schedule = "rate(2 minutes)"

# Error pattern customization
error_patterns = ["ERROR", "CRITICAL", "FATAL", "EXCEPTION"]
query_time_range_minutes = 15
max_errors_to_display = 10

# Lambda configuration
lambda_timeout     = 90
lambda_memory_size = 512

# Additional tags
tags = {
  Team        = "DevOps"
  Application = "Production Monitoring"
  CostCenter  = "Engineering"
}
```

## Testing the Solution

### 1. Add Sample Log Events

```bash
# Get log group name from Terraform output
LOG_GROUP_NAME=$(terraform output -raw log_group_name)

# Add sample error logs
CURRENT_TIME=$(date +%s000)
aws logs put-log-events \
    --log-group-name ${LOG_GROUP_NAME} \
    --log-stream-name "test-stream" \
    --log-events \
    timestamp=${CURRENT_TIME},message="ERROR: Database connection failed - timeout" \
    timestamp=$((CURRENT_TIME + 1000)),message="CRITICAL: Application crash detected" \
    timestamp=$((CURRENT_TIME + 2000)),message="ERROR: Authentication service unavailable"
```

### 2. Manual Lambda Invocation

```bash
# Get Lambda function name from Terraform output
FUNCTION_NAME=$(terraform output -raw lambda_function_name)

# Manually invoke the function
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload '{}' \
    response.json

# Check the response
cat response.json
```

### 3. Monitor Lambda Logs

```bash
# Get Lambda log group name from Terraform output
LAMBDA_LOG_GROUP=$(terraform output -raw lambda_log_group_name)

# View recent Lambda logs
aws logs tail ${LAMBDA_LOG_GROUP} --follow
```

### 4. Test CloudWatch Logs Insights Query

```bash
# Run manual query to verify error detection
aws logs start-query \
    --log-group-name ${LOG_GROUP_NAME} \
    --start-time $(date -d '1 hour ago' +%s) \
    --end-time $(date +%s) \
    --query-string 'fields @timestamp, @message | filter @message like /ERROR|CRITICAL|FATAL/ | sort @timestamp desc'
```

## Monitoring and Troubleshooting

### Lambda Function Logs

Monitor the Lambda function execution:

```bash
aws logs tail $(terraform output -raw lambda_log_group_name) --follow
```

### SNS Topic Monitoring

Check SNS topic metrics in CloudWatch:
- Number of messages published
- Number of messages delivered
- Failed deliveries

### EventBridge Rule Status

Verify the EventBridge rule is enabled:

```bash
aws events describe-rule --name $(terraform output -raw eventbridge_rule_name)
```

## Customization Examples

### Custom Error Patterns

```hcl
# Monitor specific application errors
error_patterns = [
  "ERROR",
  "CRITICAL", 
  "FATAL",
  "OutOfMemoryError",
  "ConnectionTimeout",
  "DatabaseException"
]
```

### Multiple Notification Endpoints

```hcl
# Create additional SNS subscriptions manually
resource "aws_sns_topic_subscription" "slack_notification" {
  topic_arn = aws_sns_topic.log_alerts.arn
  protocol  = "https"
  endpoint  = "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
}
```

### Advanced Lambda Configuration

```hcl
# Custom Lambda environment variables
resource "aws_lambda_function" "log_analyzer" {
  # ... other configuration ...
  
  environment {
    variables = {
      LOG_GROUP_NAME         = var.log_group_name
      SNS_TOPIC_ARN         = aws_sns_topic.log_alerts.arn
      ERROR_PATTERN         = local.error_pattern
      QUERY_TIME_RANGE      = var.query_time_range_minutes
      MAX_ERRORS_TO_DISPLAY = var.max_errors_to_display
      ALERT_THRESHOLD       = "3"  # Custom threshold
      ENABLE_DETAILED_LOGS  = "true"
    }
  }
}
```

## Security Best Practices

This Terraform configuration implements security best practices:

1. **Least Privilege IAM**: Lambda role has minimal required permissions
2. **Resource-Specific Access**: SNS publish permissions limited to specific topic
3. **Encryption**: All logs encrypted at rest using AWS managed keys
4. **Network Security**: Lambda function runs in AWS managed VPC
5. **Access Logging**: All API calls logged via CloudTrail

## Cost Optimization

- **Log Retention**: Configurable retention period (default 7 days)
- **Lambda Efficiency**: Optimized memory and timeout settings
- **Query Optimization**: Limited query results and time ranges
- **Scheduled Analysis**: Configurable frequency to balance monitoring vs. cost

Estimated monthly cost for typical usage:
- CloudWatch Logs Insights: ~$0.50-$2.00 (depending on log volume)
- Lambda: ~$0.10-$0.30 (depending on execution frequency)
- SNS: ~$0.01-$0.05 (depending on notification volume)

## Cleanup

To remove all resources:

```bash
terraform destroy
```

Confirm the destruction by typing `yes` when prompted.

## Outputs

After successful deployment, Terraform provides these outputs:

- `log_group_name`: CloudWatch Log Group name
- `sns_topic_arn`: SNS Topic ARN for alerts
- `lambda_function_name`: Lambda function name
- `eventbridge_rule_name`: EventBridge rule name
- `usage_instructions`: Detailed usage instructions
- `sample_insights_query`: Sample CloudWatch Logs Insights query

## Support

For issues with this Terraform configuration:

1. Check AWS CloudWatch Logs for Lambda function errors
2. Verify IAM permissions and resource configurations
3. Review Terraform state and plan output
4. Consult AWS documentation for service-specific troubleshooting

## Related Resources

- [AWS CloudWatch Logs Insights Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AnalyzingLogData.html)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [AWS SNS Documentation](https://docs.aws.amazon.com/sns/)
- [Terraform AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)