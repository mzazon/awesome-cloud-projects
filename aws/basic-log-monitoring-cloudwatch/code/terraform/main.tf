# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  # Resource naming with optional prefix and random suffix
  name_prefix = var.resource_prefix != "" ? "${var.resource_prefix}-" : ""
  name_suffix = "-${random_string.suffix.result}"
  
  # Resource names
  sns_topic_name        = "${local.name_prefix}log-monitoring-alerts${local.name_suffix}"
  lambda_function_name  = "${local.name_prefix}log-processor${local.name_suffix}"
  alarm_name           = "${local.name_prefix}application-errors-alarm${local.name_suffix}"
  metric_filter_name   = "${local.name_prefix}error-count-filter${local.name_suffix}"
  lambda_role_name     = "${local.name_prefix}lambda-log-processor-role${local.name_suffix}"
  
  # Metric configuration
  metric_namespace = "CustomApp/Monitoring"
  metric_name     = "ApplicationErrors"
  
  # Combined tags
  common_tags = merge(
    {
      Environment = var.environment
      Project     = "basic-log-monitoring"
      Recipe      = "basic-log-monitoring-cloudwatch-sns"
      ManagedBy   = "terraform"
    },
    var.tags
  )
}

# ====================================================================
# CloudWatch Log Group
# ====================================================================

# Create CloudWatch Log Group for application logs
resource "aws_cloudwatch_log_group" "application_logs" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = var.log_group_name
    Description = "Log group for application monitoring and error detection"
  })
}

# ====================================================================
# SNS Topic and Subscription
# ====================================================================

# Create SNS topic for alert notifications
resource "aws_sns_topic" "log_monitoring_alerts" {
  name = local.sns_topic_name
  
  tags = merge(local.common_tags, {
    Name        = local.sns_topic_name
    Description = "SNS topic for log monitoring alert notifications"
  })
}

# SNS topic policy to allow CloudWatch to publish messages
resource "aws_sns_topic_policy" "log_monitoring_alerts_policy" {
  arn = aws_sns_topic.log_monitoring_alerts.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = [
          "SNS:Publish"
        ]
        Resource = aws_sns_topic.log_monitoring_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Email subscription to SNS topic
resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.log_monitoring_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ====================================================================
# Lambda Function for Log Processing
# ====================================================================

# IAM role for Lambda function
resource "aws_iam_role" "lambda_log_processor_role" {
  name = local.lambda_role_name
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name        = local.lambda_role_name
    Description = "IAM role for Lambda log processor function"
  })
}

# Attach basic execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_log_processor_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Optional: Attach Lambda Insights policy if enabled
resource "aws_iam_role_policy_attachment" "lambda_insights" {
  count      = var.enable_lambda_insights ? 1 : 0
  role       = aws_iam_role.lambda_log_processor_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLambdaInsightsExecutionRolePolicy"
}

# Additional IAM policy for CloudWatch Logs access
resource "aws_iam_role_policy" "lambda_cloudwatch_logs_policy" {
  name = "${local.lambda_role_name}-cloudwatch-logs"
  role = aws_iam_role.lambda_log_processor_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:FilterLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
        ]
      }
    ]
  })
}

# Create Lambda function source code
resource "local_file" "lambda_source" {
  filename = "${path.module}/lambda_function.py"
  content = <<-EOT
import json
import boto3
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process CloudWatch alarm notifications from SNS and enrich alert data
    
    This function receives SNS notifications when CloudWatch alarms are triggered,
    processes the alarm details, and logs comprehensive information for monitoring
    and potential automated remediation.
    """
    
    try:
        # Initialize CloudWatch Logs client for potential log queries
        logs_client = boto3.client('logs')
        
        # Process each SNS record in the event
        for record in event.get('Records', []):
            if 'Sns' not in record:
                logger.warning("Record missing SNS data, skipping")
                continue
            
            # Parse SNS message containing CloudWatch alarm details
            sns_message = json.loads(record['Sns']['Message'])
            
            # Extract alarm details with safe defaults
            alarm_name = sns_message.get('AlarmName', 'Unknown')
            alarm_reason = sns_message.get('NewStateReason', 'No reason provided')
            alarm_state = sns_message.get('NewStateValue', 'Unknown')
            old_state = sns_message.get('OldStateValue', 'Unknown')
            timestamp = sns_message.get('StateChangeTime', datetime.now().isoformat())
            region = sns_message.get('Region', 'Unknown')
            
            # Log comprehensive alarm processing details
            logger.info(f"Processing CloudWatch alarm notification:")
            logger.info(f"  Alarm Name: {alarm_name}")
            logger.info(f"  State Change: {old_state} -> {alarm_state}")
            logger.info(f"  Reason: {alarm_reason}")
            logger.info(f"  Timestamp: {timestamp}")
            logger.info(f"  Region: {region}")
            
            # Extract metric information if available
            trigger = sns_message.get('Trigger', {})
            if trigger:
                metric_name = trigger.get('MetricName', 'Unknown')
                namespace = trigger.get('Namespace', 'Unknown')
                threshold = trigger.get('Threshold', 'Unknown')
                
                logger.info(f"  Metric: {namespace}/{metric_name}")
                logger.info(f"  Threshold: {threshold}")
            
            # Log the full SNS message for debugging (truncated if too long)
            message_str = json.dumps(sns_message, indent=2)
            if len(message_str) > 1000:
                message_str = message_str[:1000] + "... (truncated)"
            logger.debug(f"Full SNS message: {message_str}")
            
            # Additional processing can be implemented here:
            # 1. Query CloudWatch Logs for recent error context
            # 2. Send notifications to external systems (Slack, PagerDuty, etc.)
            # 3. Trigger automated remediation workflows
            # 4. Create support tickets or incident records
            # 5. Update operational dashboards
            
            # Example: Query recent log events for context (commented out to avoid permissions issues)
            # try:
            #     log_events = logs_client.filter_log_events(
            #         logGroupName='/aws/application/monitoring-demo',
            #         startTime=int((datetime.now().timestamp() - 300) * 1000),  # Last 5 minutes
            #         filterPattern='ERROR'
            #     )
            #     logger.info(f"Found {len(log_events.get('events', []))} recent error events")
            # except Exception as e:
            #     logger.warning(f"Could not query log events: {str(e)}")
        
        # Return success response
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Log processing completed successfully',
                'processed_records': len(event.get('Records', []))
            })
        }
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse SNS message JSON: {str(e)}")
        return {
            'statusCode': 400,
            'body': json.dumps(f'JSON parsing error: {str(e)}')
        }
    except Exception as e:
        logger.error(f"Unexpected error processing log event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Processing error: {str(e)}')
        }
EOT
}

# Create ZIP file for Lambda deployment
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_source.filename
  output_path = "${path.module}/lambda_function.zip"
  
  depends_on = [local_file.lambda_source]
}

# Create Lambda function
resource "aws_lambda_function" "log_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_log_processor_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  # Use source code hash to trigger updates when code changes
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  # Optional Lambda Insights layer for enhanced monitoring
  dynamic "layers" {
    for_each = var.enable_lambda_insights ? [1] : []
    content {
      layers = ["arn:aws:lambda:${data.aws_region.current.name}:580247275435:layer:LambdaInsightsExtension:14"]
    }
  }
  
  environment {
    variables = {
      LOG_LEVEL    = "INFO"
      ENVIRONMENT  = var.environment
    }
  }
  
  tags = merge(local.common_tags, {
    Name        = local.lambda_function_name
    Description = "Processes CloudWatch alarm notifications and enriches alert data"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name        = "/aws/lambda/${local.lambda_function_name}"
    Description = "Log group for Lambda log processor function"
  })
}

# Lambda permission for SNS to invoke the function
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.log_processor.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.log_monitoring_alerts.arn
}

# Subscribe Lambda function to SNS topic
resource "aws_sns_topic_subscription" "lambda_notification" {
  topic_arn = aws_sns_topic.log_monitoring_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.log_processor.arn
  
  depends_on = [aws_lambda_permission.allow_sns]
}

# ====================================================================
# CloudWatch Metric Filter
# ====================================================================

# Create metric filter to detect error patterns in logs
resource "aws_cloudwatch_log_metric_filter" "error_count_filter" {
  name           = local.metric_filter_name
  log_group_name = aws_cloudwatch_log_group.application_logs.name
  
  # Pattern to match JSON logs with ERROR level or messages containing error keywords
  # This pattern handles both structured JSON logs and unstructured text logs
  pattern = "{ ($.level = \"ERROR\") || ($.message = \"*ERROR*\") || ($.message = \"*FAILED*\") || ($.message = \"*EXCEPTION*\") || ($.message = \"*TIMEOUT*\") }"
  
  metric_transformation {
    name          = local.metric_name
    namespace     = local.metric_namespace
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

# ====================================================================
# CloudWatch Alarm
# ====================================================================

# Create CloudWatch alarm for error threshold monitoring
resource "aws_cloudwatch_metric_alarm" "application_errors" {
  alarm_name        = local.alarm_name
  alarm_description = "Alert when application errors exceed threshold in ${var.environment} environment"
  
  # Metric configuration
  metric_name         = local.metric_name
  namespace           = local.metric_namespace
  statistic           = "Sum"
  period              = var.alarm_period_seconds
  evaluation_periods  = var.alarm_evaluation_periods
  threshold           = var.error_threshold
  comparison_operator = "GreaterThanThreshold"
  
  # Data handling
  treat_missing_data = "notBreaching"
  datapoints_to_alarm = 1
  
  # Actions
  alarm_actions = [aws_sns_topic.log_monitoring_alerts.arn]
  ok_actions    = [aws_sns_topic.log_monitoring_alerts.arn]
  
  tags = merge(local.common_tags, {
    Name        = local.alarm_name
    Description = "CloudWatch alarm for application error monitoring"
    Severity    = "Medium"
  })
  
  depends_on = [aws_cloudwatch_log_metric_filter.error_count_filter]
}

# ====================================================================
# Optional: CloudWatch Dashboard
# ====================================================================

# Create CloudWatch dashboard for monitoring overview
resource "aws_cloudwatch_dashboard" "log_monitoring_dashboard" {
  dashboard_name = "${local.name_prefix}log-monitoring-dashboard${local.name_suffix}"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            [local.metric_namespace, local.metric_name]
          ]
          period = var.alarm_period_seconds
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Application Errors Over Time"
          view   = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 6
        height = 6
        
        properties = {
          metrics = [
            [local.metric_namespace, local.metric_name]
          ]
          period = 3600  # 1 hour
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Total Errors (Last 24h)"
          view   = "singleValue"
        }
      },
      {
        type   = "log"
        x      = 6
        y      = 6
        width  = 6
        height = 6
        
        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.application_logs.name}' | fields @timestamp, @message | filter @message like /ERROR|FAILED|EXCEPTION|TIMEOUT/ | sort @timestamp desc | limit 20"
          region  = data.aws_region.current.name
          title   = "Recent Error Messages"
        }
      }
    ]
  })
}