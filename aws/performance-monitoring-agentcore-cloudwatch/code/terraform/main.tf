# Main Terraform configuration for AgentCore Performance Monitoring
# This file creates the complete infrastructure for monitoring AI agents with CloudWatch

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = var.random_suffix_length
  upper   = false
  special = false
}

# Local values for resource naming and configuration
locals {
  # Agent name configuration - use provided name or generate one
  agent_name = var.agent_name != "" ? var.agent_name : "ai-agent-${random_string.suffix.result}"
  
  # Common resource naming
  common_name_suffix = random_string.suffix.result
  
  # S3 bucket name (must be globally unique)
  s3_bucket_name = "${var.s3_bucket_prefix}-${local.common_name_suffix}"
  
  # Lambda function name
  lambda_function_name = "${var.lambda_function_prefix}-${local.common_name_suffix}"
  
  # CloudWatch dashboard name
  dashboard_name = "${var.dashboard_name_prefix}-${local.common_name_suffix}"
  
  # IAM role names
  agentcore_role_name = "${var.agentcore_role_prefix}-${local.common_name_suffix}"
  lambda_role_name    = "${var.lambda_role_prefix}-${local.common_name_suffix}"
  
  # Log group names
  agentcore_log_group_name         = "/aws/bedrock/agentcore/${local.agent_name}"
  lambda_log_group_name           = "/aws/lambda/${local.lambda_function_name}"
  agentcore_memory_log_group_name = "/aws/bedrock/agentcore/memory/${local.agent_name}"
  agentcore_gateway_log_group_name = "/aws/bedrock/agentcore/gateway/${local.agent_name}"
  
  # Common tags
  common_tags = merge(var.additional_tags, {
    AgentName    = local.agent_name
    Environment  = var.environment
    Project      = "AgentCore Performance Monitoring"
    ManagedBy    = "Terraform"
    Recipe       = "performance-monitoring-agentcore-cloudwatch"
    CreatedDate  = formatdate("YYYY-MM-DD", timestamp())
  })
}

# S3 Bucket for storing performance reports
resource "aws_s3_bucket" "monitoring_data" {
  bucket = local.s3_bucket_name

  tags = merge(local.common_tags, {
    Name        = local.s3_bucket_name
    Description = "Storage for AgentCore performance monitoring reports and analytics"
  })
}

# S3 Bucket versioning configuration
resource "aws_s3_bucket_versioning" "monitoring_data" {
  bucket = aws_s3_bucket.monitoring_data.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

# S3 Bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "monitoring_data" {
  bucket = aws_s3_bucket.monitoring_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "monitoring_data" {
  bucket = aws_s3_bucket.monitoring_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "monitoring_data" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.monitoring_data.id

  rule {
    id     = "performance_reports_lifecycle"
    status = "Enabled"

    # Expire objects after configured days
    expiration {
      days = var.s3_expiration_days
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    # Transition to IA after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 60 days
    transition {
      days          = 60
      storage_class = "GLACIER"
    }

    filter {
      prefix = "performance-reports/"
    }
  }
}

# IAM role for AgentCore with observability permissions
resource "aws_iam_role" "agentcore_monitoring" {
  name = local.agentcore_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = local.agentcore_role_name
    Description = "IAM role for AgentCore observability and monitoring"
  })
}

# IAM policy for AgentCore observability
resource "aws_iam_policy" "agentcore_observability" {
  name        = "AgentCoreObservabilityPolicy-${local.common_name_suffix}"
  description = "Policy for AgentCore to emit telemetry data to CloudWatch"

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
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/agentcore/*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "AWS/BedrockAgentCore"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "AgentCoreObservabilityPolicy-${local.common_name_suffix}"
    Description = "Policy for AgentCore observability permissions"
  })
}

# Attach observability policy to AgentCore role
resource "aws_iam_role_policy_attachment" "agentcore_observability" {
  role       = aws_iam_role.agentcore_monitoring.name
  policy_arn = aws_iam_policy.agentcore_observability.arn
}

# CloudWatch Log Groups for AgentCore components
resource "aws_cloudwatch_log_group" "agentcore" {
  name              = local.agentcore_log_group_name
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = local.agentcore_log_group_name
    Description = "Log group for AgentCore main operations"
    Component   = "AgentCore"
  })
}

resource "aws_cloudwatch_log_group" "agentcore_memory" {
  name              = local.agentcore_memory_log_group_name
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = local.agentcore_memory_log_group_name
    Description = "Log group for AgentCore memory operations"
    Component   = "AgentCore-Memory"
  })
}

resource "aws_cloudwatch_log_group" "agentcore_gateway" {
  name              = local.agentcore_gateway_log_group_name
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = local.agentcore_gateway_log_group_name
    Description = "Log group for AgentCore gateway operations"
    Component   = "AgentCore-Gateway"
  })
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda" {
  name              = local.lambda_log_group_name
  retention_in_days = var.lambda_log_retention_days

  tags = merge(local.common_tags, {
    Name        = local.lambda_log_group_name
    Description = "Log group for Lambda performance monitor function"
    Component   = "Lambda"
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_performance_monitor" {
  name = local.lambda_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = local.lambda_role_name
    Description = "IAM role for Lambda performance monitoring function"
  })
}

# IAM policy attachments for Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_performance_monitor.name
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
  role       = aws_iam_role.lambda_performance_monitor.name
}

# Custom IAM policy for Lambda to access S3 bucket
resource "aws_iam_policy" "lambda_s3_access" {
  name        = "LambdaS3AccessPolicy-${local.common_name_suffix}"
  description = "Policy for Lambda to access S3 monitoring bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.monitoring_data.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.monitoring_data.arn
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "LambdaS3AccessPolicy-${local.common_name_suffix}"
    Description = "S3 access policy for Lambda performance monitor"
  })
}

resource "aws_iam_role_policy_attachment" "lambda_s3_access" {
  policy_arn = aws_iam_policy.lambda_s3_access.arn
  role       = aws_iam_role.lambda_performance_monitor.name
}

# Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/performance_monitor.zip"
  
  source {
    content = <<EOF
import json
import boto3
import os
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Monitor AgentCore performance metrics and trigger optimization actions
    """
    try:
        # Handle direct CloudWatch alarm format
        if 'Records' in event:
            # SNS message format
            message = json.loads(event['Records'][0]['Sns']['Message'])
            alarm_name = message.get('AlarmName', 'Unknown')
            alarm_description = message.get('AlarmDescription', '')
            new_state = message.get('NewStateValue', 'UNKNOWN')
        else:
            # Direct invocation format
            alarm_name = event.get('AlarmName', 'TestAlarm')
            alarm_description = event.get('AlarmDescription', 'Test alarm')
            new_state = event.get('NewStateValue', 'ALARM')
        
        # Get performance metrics for the last 5 minutes
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=5)
        
        # Query AgentCore metrics
        try:
            response = cloudwatch.get_metric_statistics(
                Namespace='AWS/BedrockAgentCore',
                MetricName='Latency',
                Dimensions=[
                    {'Name': 'AgentId', 'Value': os.environ['AGENT_NAME']}
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=60,
                Statistics=['Average', 'Maximum']
            )
        except Exception as metric_error:
            print(f"Warning: Could not retrieve metrics - {str(metric_error)}")
            response = {'Datapoints': []}
        
        # Analyze performance and create report
        performance_report = {
            'timestamp': end_time.isoformat(),
            'alarm_triggered': alarm_name,
            'alarm_description': alarm_description,
            'new_state': new_state,
            'metrics': response['Datapoints'],
            'optimization_actions': []
        }
        
        # Add optimization recommendations based on metrics
        if response['Datapoints']:
            avg_latency = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
            max_latency = max((dp['Maximum'] for dp in response['Datapoints']), default=0)
            
            if avg_latency > 30000:  # 30 seconds
                performance_report['optimization_actions'].append({
                    'action': 'increase_memory_allocation',
                    'reason': f'High average latency detected: {avg_latency:.2f}ms'
                })
            
            if max_latency > 60000:  # 60 seconds
                performance_report['optimization_actions'].append({
                    'action': 'investigate_timeout_issues',
                    'reason': f'Maximum latency threshold exceeded: {max_latency:.2f}ms'
                })
        else:
            performance_report['optimization_actions'].append({
                'action': 'verify_agent_health',
                'reason': 'No metric data available for analysis'
            })
        
        # Store performance report in S3
        report_key = f"performance-reports/{datetime.now().strftime('%Y/%m/%d')}/{alarm_name}-{context.aws_request_id}.json"
        s3.put_object(
            Bucket=os.environ['S3_BUCKET_NAME'],
            Key=report_key,
            Body=json.dumps(performance_report, indent=2),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Performance analysis completed',
                'report_location': f"s3://{os.environ['S3_BUCKET_NAME']}/{report_key}",
                'optimization_actions': len(performance_report['optimization_actions'])
            })
        }
        
    except Exception as e:
        print(f"Error processing performance alert: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    filename = "performance_monitor.py"
  }
}

# Lambda function for performance monitoring
resource "aws_lambda_function" "performance_monitor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_performance_monitor.arn
  handler         = "performance_monitor.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      AGENT_NAME       = local.agent_name
      S3_BUCKET_NAME   = aws_s3_bucket.monitoring_data.id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda,
  ]

  tags = merge(local.common_tags, {
    Name        = local.lambda_function_name
    Description = "Lambda function for AgentCore performance monitoring and optimization"
  })
}

# Lambda permission for CloudWatch alarms to invoke the function
resource "aws_lambda_permission" "allow_cloudwatch_alarms" {
  statement_id  = "AllowExecutionFromCloudWatchAlarms"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.performance_monitor.function_name
  principal     = "cloudwatch.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
}

# CloudWatch Alarms for performance monitoring
resource "aws_cloudwatch_metric_alarm" "high_latency" {
  alarm_name          = "AgentCore-HighLatency-${local.common_name_suffix}"
  alarm_description   = "Alert when agent latency exceeds ${var.latency_threshold_ms / 1000} seconds"
  metric_name         = "Latency"
  namespace           = "AWS/BedrockAgentCore"
  statistic           = "Average"
  period              = var.alarm_period_seconds
  threshold           = var.latency_threshold_ms
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  alarm_actions       = [aws_lambda_function.performance_monitor.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    AgentId = local.agent_name
  }

  tags = merge(local.common_tags, {
    Name        = "AgentCore-HighLatency-${local.common_name_suffix}"
    Description = "CloudWatch alarm for high agent latency"
    Component   = "Monitoring"
  })
}

resource "aws_cloudwatch_metric_alarm" "high_system_errors" {
  alarm_name          = "AgentCore-HighSystemErrors-${local.common_name_suffix}"
  alarm_description   = "Alert when system errors exceed threshold of ${var.system_error_threshold}"
  metric_name         = "SystemErrors"
  namespace           = "AWS/BedrockAgentCore"
  statistic           = "Sum"
  period              = var.alarm_period_seconds
  threshold           = var.system_error_threshold
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  alarm_actions       = [aws_lambda_function.performance_monitor.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    AgentId = local.agent_name
  }

  tags = merge(local.common_tags, {
    Name        = "AgentCore-HighSystemErrors-${local.common_name_suffix}"
    Description = "CloudWatch alarm for high system error rates"
    Component   = "Monitoring"
  })
}

resource "aws_cloudwatch_metric_alarm" "high_throttles" {
  alarm_name          = "AgentCore-HighThrottles-${local.common_name_suffix}"
  alarm_description   = "Alert when throttling occurs frequently (threshold: ${var.throttle_threshold})"
  metric_name         = "Throttles"
  namespace           = "AWS/BedrockAgentCore"
  statistic           = "Sum"
  period              = var.alarm_period_seconds
  threshold           = var.throttle_threshold
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  alarm_actions       = [aws_lambda_function.performance_monitor.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    AgentId = local.agent_name
  }

  tags = merge(local.common_tags, {
    Name        = "AgentCore-HighThrottles-${local.common_name_suffix}"
    Description = "CloudWatch alarm for high throttle rates"
    Component   = "Monitoring"
  })
}

# CloudWatch Dashboard for agent performance visualization
resource "aws_cloudwatch_dashboard" "agentcore_performance" {
  count          = var.create_dashboard ? 1 : 0
  dashboard_name = local.dashboard_name

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
            ["AWS/BedrockAgentCore", "Latency", "AgentId", local.agent_name],
            [".", "Invocations", ".", "."],
            [".", "SessionCount", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Agent Performance Metrics"
          period  = 300
          stat    = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/BedrockAgentCore", "UserErrors", "AgentId", local.agent_name],
            [".", "SystemErrors", ".", "."],
            [".", "Throttles", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Error and Throttle Rates"
          period  = 300
          stat    = "Sum"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          query  = "SOURCE '${local.agentcore_log_group_name}' | fields @timestamp, @message\n| filter @message like /ERROR/\n| sort @timestamp desc\n| limit 20"
          region = data.aws_region.current.name
          title  = "Recent Agent Errors"
          view   = "table"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = local.dashboard_name
    Description = "CloudWatch dashboard for AgentCore performance monitoring"
    Component   = "Dashboard"
  })
}

# CloudWatch Log Metric Filters for custom metrics
resource "aws_cloudwatch_log_metric_filter" "agent_response_time" {
  name           = "AgentResponseTime"
  log_group_name = aws_cloudwatch_log_group.agentcore.name
  pattern        = "[timestamp, requestId, level=INFO, metric=\"response_time\", value]"

  metric_transformation {
    name      = "AgentResponseTime"
    namespace = "CustomAgentMetrics"
    value     = "$value"
    default_value = 0
  }
}

resource "aws_cloudwatch_log_metric_filter" "conversation_quality" {
  name           = "ConversationQualityScore"
  log_group_name = aws_cloudwatch_log_group.agentcore.name
  pattern        = "[timestamp, requestId, level=INFO, metric=\"quality_score\", score]"

  metric_transformation {
    name      = "ConversationQuality"
    namespace = "CustomAgentMetrics"
    value     = "$score"
    default_value = 0
  }
}

resource "aws_cloudwatch_log_metric_filter" "business_outcome_success" {
  name           = "BusinessOutcomeSuccess"
  log_group_name = aws_cloudwatch_log_group.agentcore.name
  pattern        = "[timestamp, requestId, level=INFO, outcome=\"SUCCESS\"]"

  metric_transformation {
    name      = "BusinessOutcomeSuccess"
    namespace = "CustomAgentMetrics"
    value     = "1"
    default_value = 0
  }
}