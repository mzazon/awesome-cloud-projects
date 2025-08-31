# Simple Log Analysis with CloudWatch Insights and SNS
# This Terraform configuration creates an automated log monitoring solution
# that uses CloudWatch Logs Insights to query application logs for error patterns
# and sends notifications via SNS when critical issues are detected.

# Data source to get current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  resource_suffix     = random_id.suffix.hex
  lambda_function_name = "${var.project_name}-log-analyzer-${local.resource_suffix}"
  sns_topic_name      = "${var.project_name}-alerts-${local.resource_suffix}"
  eventbridge_rule_name = "${var.project_name}-schedule-${local.resource_suffix}"
  
  # Build error pattern regex for CloudWatch Logs Insights query
  error_pattern = join("|", var.error_patterns)
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.environment}"
    Component   = "log-analysis"
    CreatedBy   = "terraform"
  })
}

#=====================================
# CloudWatch Log Group
#=====================================

# CloudWatch Log Group for storing application logs
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Description = "Log group for application logs monitored by log analysis solution"
  })
}

#=====================================
# SNS Topic and Subscription
#=====================================

# SNS Topic for log analysis alerts
resource "aws_sns_topic" "log_alerts" {
  name = local.sns_topic_name
  
  tags = merge(local.common_tags, {
    Description = "SNS topic for CloudWatch log analysis alerts"
  })
}

# SNS Topic Policy to allow publishing from Lambda
resource "aws_sns_topic_policy" "log_alerts_policy" {
  arn = aws_sns_topic.log_alerts.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_role.arn
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.log_alerts.arn
      }
    ]
  })
}

# Email subscription to SNS topic (conditional based on variable)
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.enable_sns_subscription && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.log_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

#=====================================
# IAM Role and Policies for Lambda
#=====================================

# IAM Role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${local.resource_suffix}"
  
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
    Description = "IAM role for log analyzer Lambda function"
  })
}

# Attach AWS managed policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom IAM policy for CloudWatch Logs Insights and SNS access
resource "aws_iam_role_policy" "lambda_permissions" {
  name = "${var.project_name}-lambda-permissions-${local.resource_suffix}"
  role = aws_iam_role.lambda_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:StartQuery",
          "logs:GetQueryResults",
          "logs:StopQuery",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.log_alerts.arn
      }
    ]
  })
}

#=====================================
# Lambda Function
#=====================================

# Lambda function source code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      log_group_name          = var.log_group_name
      sns_topic_arn          = aws_sns_topic.log_alerts.arn
      error_pattern          = local.error_pattern
      query_time_range       = var.query_time_range_minutes
      max_errors_to_display  = var.max_errors_to_display
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for log analysis
resource "aws_lambda_function" "log_analyzer" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.12"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  environment {
    variables = {
      LOG_GROUP_NAME          = var.log_group_name
      SNS_TOPIC_ARN          = aws_sns_topic.log_alerts.arn
      ERROR_PATTERN          = local.error_pattern
      QUERY_TIME_RANGE       = var.query_time_range_minutes
      MAX_ERRORS_TO_DISPLAY  = var.max_errors_to_display
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_permissions,
    aws_cloudwatch_log_group.lambda_logs
  ]
  
  tags = merge(local.common_tags, {
    Description = "Lambda function for automated log analysis using CloudWatch Logs Insights"
  })
}

# CloudWatch Log Group for Lambda function logs
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Description = "Log group for log analyzer Lambda function"
  })
}

#=====================================
# EventBridge Rule for Scheduling
#=====================================

# EventBridge Rule for scheduled Lambda execution
resource "aws_cloudwatch_event_rule" "log_analysis_schedule" {
  name                = local.eventbridge_rule_name
  description         = "Trigger log analysis Lambda function on schedule"
  schedule_expression = var.analysis_schedule
  
  tags = merge(local.common_tags, {
    Description = "EventBridge rule for scheduling log analysis"
  })
}

# EventBridge Target to invoke Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.log_analysis_schedule.name
  target_id = "LogAnalysisLambdaTarget"
  arn       = aws_lambda_function.log_analyzer.arn
}

# Lambda permission for EventBridge to invoke the function
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.log_analyzer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.log_analysis_schedule.arn
}

#=====================================
# Template file for Lambda function code
#=====================================

# Create the Lambda function template file
resource "local_file" "lambda_template" {
  content = <<-EOT
import json
import boto3
import time
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    """
    Lambda function to analyze CloudWatch logs for error patterns
    and send SNS notifications when errors are detected.
    """
    logs_client = boto3.client('logs')
    sns_client = boto3.client('sns')
    
    # Get configuration from environment variables
    log_group = os.environ.get('LOG_GROUP_NAME', '${log_group_name}')
    sns_topic = os.environ.get('SNS_TOPIC_ARN', '${sns_topic_arn}')
    error_pattern = os.environ.get('ERROR_PATTERN', '${error_pattern}')
    query_time_range = int(os.environ.get('QUERY_TIME_RANGE', '${query_time_range}'))
    max_errors = int(os.environ.get('MAX_ERRORS_TO_DISPLAY', '${max_errors_to_display}'))
    
    # Define time range for log analysis
    end_time = datetime.now()
    start_time = end_time - timedelta(minutes=query_time_range)
    
    # CloudWatch Logs Insights query for error patterns
    query = f"""
    fields @timestamp, @message
    | filter @message like /{error_pattern}/
    | sort @timestamp desc
    | limit 100
    """
    
    try:
        print(f"Starting log analysis for log group: {log_group}")
        print(f"Time range: {start_time} to {end_time}")
        print(f"Error pattern: {error_pattern}")
        
        # Start the CloudWatch Logs Insights query
        response = logs_client.start_query(
            logGroupName=log_group,
            startTime=int(start_time.timestamp()),
            endTime=int(end_time.timestamp()),
            queryString=query
        )
        
        query_id = response['queryId']
        print(f"Started query with ID: {query_id}")
        
        # Wait for query completion with timeout protection
        max_wait_time = 60  # Maximum wait time in seconds
        wait_start = time.time()
        
        while True:
            if time.time() - wait_start > max_wait_time:
                raise Exception(f'Query timeout after {max_wait_time} seconds')
                
            time.sleep(2)
            result = logs_client.get_query_results(queryId=query_id)
            
            if result['status'] == 'Complete':
                break
            elif result['status'] == 'Failed':
                raise Exception(f"Query failed: {result.get('statusMessage', 'Unknown error')}")
            elif result['status'] in ['Cancelled', 'Timeout']:
                raise Exception(f"Query {result['status'].lower()}")
        
        # Process query results
        error_count = len(result['results'])
        print(f"Query completed. Found {error_count} error(s)")
        
        if error_count > 0:
            # Format alert message
            alert_message = f"""🚨 CloudWatch Log Analysis Alert

Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}
Log Group: {log_group}
Error Pattern: {error_pattern}
Error Count: {error_count} error(s) found in the last {query_time_range} minutes

Recent Errors:"""
            
            # Add up to max_errors recent errors to the message
            for i, log_entry in enumerate(result['results'][:max_errors]):
                try:
                    timestamp = next(field['value'] for field in log_entry if field['field'] == '@timestamp')
                    message = next(field['value'] for field in log_entry if field['field'] == '@message')
                    alert_message += f"\n{i+1}. {timestamp}: {message}"
                except (StopIteration, KeyError) as e:
                    print(f"Error parsing log entry {i}: {e}")
                    continue
            
            if error_count > max_errors:
                alert_message += f"\n... and {error_count - max_errors} more error(s)"
            
            # Send SNS notification
            sns_response = sns_client.publish(
                TopicArn=sns_topic,
                Subject=f'CloudWatch Log Analysis Alert - {error_count} Error(s) Detected',
                Message=alert_message
            )
            
            print(f"Alert sent successfully. SNS Message ID: {sns_response.get('MessageId')}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Alert sent successfully',
                    'error_count': error_count,
                    'query_id': query_id,
                    'sns_message_id': sns_response.get('MessageId'),
                    'status': 'success'
                })
            }
        else:
            print("No errors detected in recent logs")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'No errors detected',
                    'error_count': 0,
                    'query_id': query_id,
                    'status': 'success'
                })
            }
            
    except Exception as e:
        error_message = f"Error analyzing logs: {str(e)}"
        print(error_message)
        
        # Send error notification to SNS
        try:
            sns_client.publish(
                TopicArn=sns_topic,
                Subject='CloudWatch Log Analysis Error',
                Message=f"""❌ Log Analysis Function Error

Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}
Log Group: {log_group}
Error: {error_message}

The log analysis function encountered an error and may need attention."""
            )
        except Exception as sns_error:
            print(f"Failed to send error notification: {sns_error}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message,
                'status': 'error'
            })
        }
EOT

  filename = "${path.module}/lambda_function.py.tpl"
}