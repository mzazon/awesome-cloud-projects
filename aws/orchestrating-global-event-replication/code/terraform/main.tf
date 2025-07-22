# main.tf - Multi-region EventBridge replication infrastructure

# Data sources
data "aws_caller_identity" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  random_suffix = random_id.suffix.hex
  event_bus_name = "${var.resource_prefix}-bus-${local.random_suffix}"
  global_endpoint_name = "${var.resource_prefix}-endpoint-${local.random_suffix}"
  lambda_function_name = "${var.resource_prefix}-processor-${local.random_suffix}"
  sns_topic_name = "${var.resource_prefix}-alerts-${local.random_suffix}"
  
  common_tags = merge(
    {
      Environment = var.environment
      Project     = "multi-region-event-replication"
      Purpose     = "eventbridge-global-replication"
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

# ========================================
# SNS Topic for Notifications
# ========================================

resource "aws_sns_topic" "alerts" {
  name = local.sns_topic_name
  
  tags = local.common_tags
}

# Optional email subscription for notifications
resource "aws_sns_topic_subscription" "email_alerts" {
  count = var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ========================================
# IAM Roles and Policies
# ========================================

# EventBridge cross-region role
resource "aws_iam_role" "eventbridge_cross_region" {
  name = "eventbridge-cross-region-role-${local.random_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# EventBridge cross-region policy
resource "aws_iam_role_policy" "eventbridge_cross_region" {
  name = "EventBridgeCrossRegionPolicy"
  role = aws_iam_role.eventbridge_cross_region.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = [
          "arn:aws:events:*:${data.aws_caller_identity.current.account_id}:event-bus/*"
        ]
      }
    ]
  })
}

# Lambda execution role
resource "aws_iam_role" "lambda_execution" {
  name = "lambda-execution-role-${local.random_suffix}"
  
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
  
  tags = local.common_tags
}

# Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Additional Lambda permissions for EventBridge
resource "aws_iam_role_policy" "lambda_eventbridge" {
  name = "LambdaEventBridgePolicy"
  role = aws_iam_role.lambda_execution.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents",
          "events:DescribeRule",
          "events:ListTargetsByRule"
        ]
        Resource = [
          "arn:aws:events:*:${data.aws_caller_identity.current.account_id}:event-bus/*",
          "arn:aws:events:*:${data.aws_caller_identity.current.account_id}:rule/*"
        ]
      }
    ]
  })
}

# ========================================
# Lambda Function Code
# ========================================

# Create Lambda function deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = <<EOF
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    region = os.environ.get('AWS_REGION', 'unknown')
    
    # Log the received event
    print(f"Processing event in region {region}")
    print(f"Event: {json.dumps(event, indent=2)}")
    
    # Extract event details
    for record in event.get('Records', []):
        event_source = record.get('source', 'unknown')
        event_detail_type = record.get('detail-type', 'unknown')
        event_detail = record.get('detail', {})
        
        # Process the event (implement your business logic here)
        process_business_event(event_source, event_detail_type, event_detail, region)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Events processed successfully in {region}',
            'timestamp': datetime.utcnow().isoformat(),
            'region': region
        })
    }

def process_business_event(source, detail_type, detail, region):
    """Process business events with region-specific logic"""
    
    # Example: Handle financial transaction events
    if source == 'finance.transactions' and detail_type == 'Transaction Created':
        transaction_id = detail.get('transactionId')
        amount = detail.get('amount')
        
        print(f"Processing transaction {transaction_id} "
              f"for amount {amount} in region {region}")
        
        # Implement your business logic here
        # Examples: update databases, send notifications, etc.
        
    # Example: Handle user events
    elif source == 'user.management' and detail_type == 'User Action':
        user_id = detail.get('userId')
        action = detail.get('action')
        
        print(f"Processing user action {action} for user {user_id} "
              f"in region {region}")
    
    # Example: Handle system monitoring events
    elif source == 'system.monitoring' and detail_type == 'System Alert':
        alert_type = detail.get('alertType')
        severity = detail.get('severity')
        
        print(f"Processing system alert {alert_type} "
              f"with severity {severity} in region {region}")
EOF
    filename = "lambda_function.py"
  }
}

# ========================================
# EventBridge Event Buses
# ========================================

# Primary region event bus
resource "aws_cloudwatch_event_bus" "primary" {
  name               = local.event_bus_name
  kms_key_identifier = var.enable_encryption ? "alias/aws/events" : null
  
  tags = local.common_tags
}

# Secondary region event bus
resource "aws_cloudwatch_event_bus" "secondary" {
  provider = aws.secondary
  
  name               = local.event_bus_name
  kms_key_identifier = var.enable_encryption ? "alias/aws/events" : null
  
  tags = local.common_tags
}

# Tertiary region event bus
resource "aws_cloudwatch_event_bus" "tertiary" {
  provider = aws.tertiary
  
  name               = local.event_bus_name
  kms_key_identifier = var.enable_encryption ? "alias/aws/events" : null
  
  tags = local.common_tags
}

# ========================================
# Lambda Functions
# ========================================

# Primary region Lambda function
resource "aws_lambda_function" "primary" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  tags = merge(local.common_tags, {
    Purpose = "EventProcessing"
  })
}

# Secondary region Lambda function
resource "aws_lambda_function" "secondary" {
  provider = aws.secondary
  
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  tags = merge(local.common_tags, {
    Purpose = "EventProcessing"
  })
}

# Tertiary region Lambda function
resource "aws_lambda_function" "tertiary" {
  provider = aws.tertiary
  
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  tags = merge(local.common_tags, {
    Purpose = "EventProcessing"
  })
}

# ========================================
# EventBridge Rules
# ========================================

# Primary region cross-region replication rule
resource "aws_cloudwatch_event_rule" "cross_region_replication" {
  name           = "cross-region-replication-rule"
  event_bus_name = aws_cloudwatch_event_bus.primary.name
  state          = "ENABLED"
  
  event_pattern = jsonencode({
    source = var.high_priority_events
    detail-type = ["Transaction Created", "User Action", "System Alert"]
    detail = {
      priority = ["high", "critical"]
      amount = [{
        numeric = [">=", var.financial_amount_threshold]
      }]
    }
  })
  
  tags = local.common_tags
}

# Secondary region local processing rule
resource "aws_cloudwatch_event_rule" "secondary_local_processing" {
  provider = aws.secondary
  
  name           = "local-processing-rule"
  event_bus_name = aws_cloudwatch_event_bus.secondary.name
  state          = "ENABLED"
  
  event_pattern = jsonencode({
    source = var.high_priority_events
    detail-type = ["Transaction Created", "User Action", "System Alert"]
  })
  
  tags = local.common_tags
}

# Tertiary region local processing rule
resource "aws_cloudwatch_event_rule" "tertiary_local_processing" {
  provider = aws.tertiary
  
  name           = "local-processing-rule"
  event_bus_name = aws_cloudwatch_event_bus.tertiary.name
  state          = "ENABLED"
  
  event_pattern = jsonencode({
    source = var.high_priority_events
    detail-type = ["Transaction Created", "User Action", "System Alert"]
  })
  
  tags = local.common_tags
}

# ========================================
# EventBridge Targets
# ========================================

# Cross-region targets for primary region rule
resource "aws_cloudwatch_event_target" "cross_region_secondary" {
  rule           = aws_cloudwatch_event_rule.cross_region_replication.name
  event_bus_name = aws_cloudwatch_event_bus.primary.name
  target_id      = "secondary-region-target"
  arn            = aws_cloudwatch_event_bus.secondary.arn
  role_arn       = aws_iam_role.eventbridge_cross_region.arn
}

resource "aws_cloudwatch_event_target" "cross_region_tertiary" {
  rule           = aws_cloudwatch_event_rule.cross_region_replication.name
  event_bus_name = aws_cloudwatch_event_bus.primary.name
  target_id      = "tertiary-region-target"
  arn            = aws_cloudwatch_event_bus.tertiary.arn
  role_arn       = aws_iam_role.eventbridge_cross_region.arn
}

# Primary region Lambda target
resource "aws_cloudwatch_event_target" "primary_lambda" {
  rule           = aws_cloudwatch_event_rule.cross_region_replication.name
  event_bus_name = aws_cloudwatch_event_bus.primary.name
  target_id      = "primary-lambda-target"
  arn            = aws_lambda_function.primary.arn
}

# Secondary region Lambda target
resource "aws_cloudwatch_event_target" "secondary_lambda" {
  provider = aws.secondary
  
  rule           = aws_cloudwatch_event_rule.secondary_local_processing.name
  event_bus_name = aws_cloudwatch_event_bus.secondary.name
  target_id      = "secondary-lambda-target"
  arn            = aws_lambda_function.secondary.arn
}

# Tertiary region Lambda target
resource "aws_cloudwatch_event_target" "tertiary_lambda" {
  provider = aws.tertiary
  
  rule           = aws_cloudwatch_event_rule.tertiary_local_processing.name
  event_bus_name = aws_cloudwatch_event_bus.tertiary.name
  target_id      = "tertiary-lambda-target"
  arn            = aws_lambda_function.tertiary.arn
}

# ========================================
# Lambda Permissions
# ========================================

# Lambda permission for EventBridge in primary region
resource "aws_lambda_permission" "allow_eventbridge_primary" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.primary.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cross_region_replication.arn
}

# Lambda permission for EventBridge in secondary region
resource "aws_lambda_permission" "allow_eventbridge_secondary" {
  provider = aws.secondary
  
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secondary.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.secondary_local_processing.arn
}

# Lambda permission for EventBridge in tertiary region
resource "aws_lambda_permission" "allow_eventbridge_tertiary" {
  provider = aws.tertiary
  
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.tertiary.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.tertiary_local_processing.arn
}

# ========================================
# Route 53 Health Check
# ========================================

resource "aws_route53_health_check" "eventbridge_health" {
  fqdn                            = "events.${var.primary_region}.amazonaws.com"
  port                            = 443
  type                            = "HTTPS"
  resource_path                   = "/"
  failure_threshold               = var.health_check_failure_threshold
  request_interval                = var.health_check_interval
  cloudwatch_alarm_region         = var.primary_region
  cloudwatch_alarm_name           = "eventbridge-health-check-${local.random_suffix}"
  insufficient_data_health_status = "Failure"
  
  tags = merge(local.common_tags, {
    Name = "EventBridge Health Check"
  })
}

# ========================================
# CloudWatch Monitoring
# ========================================

# CloudWatch alarm for EventBridge failed invocations
resource "aws_cloudwatch_metric_alarm" "eventbridge_failed_invocations" {
  alarm_name          = "EventBridge-FailedInvocations-${local.random_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "FailedInvocations"
  namespace           = "AWS/Events"
  period              = 300
  statistic           = "Sum"
  threshold           = var.alarm_threshold_failures
  alarm_description   = "This metric monitors EventBridge failed invocations"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    RuleName = aws_cloudwatch_event_rule.cross_region_replication.name
  }
  
  tags = local.common_tags
}

# CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "Lambda-Errors-${local.random_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.alarm_threshold_errors
  alarm_description   = "This metric monitors Lambda function errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    FunctionName = aws_lambda_function.primary.function_name
  }
  
  tags = local.common_tags
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "eventbridge_monitoring" {
  dashboard_name = "EventBridge-MultiRegion-${local.random_suffix}"
  
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
            ["AWS/Events", "SuccessfulInvocations", "RuleName", aws_cloudwatch_event_rule.cross_region_replication.name],
            [".", "FailedInvocations", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.primary_region
          title  = "EventBridge Rule Performance"
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
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.primary.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.primary_region
          title  = "Lambda Function Performance"
        }
      }
    ]
  })
}

# ========================================
# Event Bus Permissions
# ========================================

# Event bus permissions for cross-region access
resource "aws_cloudwatch_event_permission" "primary_cross_region" {
  principal    = data.aws_caller_identity.current.account_id
  statement_id = "AllowCrossRegionAccess"
  action       = "events:PutEvents"
  event_bus_name = aws_cloudwatch_event_bus.primary.name
}

resource "aws_cloudwatch_event_permission" "secondary_cross_region" {
  provider = aws.secondary
  
  principal    = data.aws_caller_identity.current.account_id
  statement_id = "AllowCrossRegionAccess"
  action       = "events:PutEvents"
  event_bus_name = aws_cloudwatch_event_bus.secondary.name
}

resource "aws_cloudwatch_event_permission" "tertiary_cross_region" {
  provider = aws.tertiary
  
  principal    = data.aws_caller_identity.current.account_id
  statement_id = "AllowCrossRegionAccess"
  action       = "events:PutEvents"
  event_bus_name = aws_cloudwatch_event_bus.tertiary.name
}