# ==============================================================================
# DATA SOURCES
# ==============================================================================

# Get current AWS caller identity
data "aws_caller_identity" "current" {}

# Get current AWS region
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# ==============================================================================
# SNS TOPIC FOR COST ANOMALY NOTIFICATIONS
# ==============================================================================

# SNS topic for cost anomaly alerts
resource "aws_sns_topic" "cost_anomaly_alerts" {
  name         = "${var.resource_prefix}-alerts-${random_id.suffix.hex}"
  display_name = "Cost Anomaly Detection Alerts"

  tags = merge(var.cost_allocation_tags, {
    Name        = "${var.resource_prefix}-alerts-${random_id.suffix.hex}"
    Purpose     = "cost-anomaly-notifications"
    Component   = "sns"
  })
}

# SNS topic policy to allow Cost Anomaly Detection to publish
resource "aws_sns_topic_policy" "cost_anomaly_alerts_policy" {
  arn = aws_sns_topic.cost_anomaly_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCostAnomalyDetectionPublish"
        Effect = "Allow"
        Principal = {
          Service = "costalerts.amazonaws.com"
        }
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.cost_anomaly_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Email subscription to the SNS topic
resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.cost_anomaly_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ==============================================================================
# COST ANOMALY DETECTION MONITORS
# ==============================================================================

# AWS Services Monitor - detects anomalies across all AWS services
resource "aws_ce_anomaly_monitor" "aws_services_monitor" {
  name         = "AWS-Services-Monitor"
  monitor_type = "DIMENSIONAL"

  specification = jsonencode({
    Dimension     = "SERVICE"
    MatchOptions  = ["EQUALS"]
    Values        = []
  })

  tags = merge(var.cost_allocation_tags, {
    Name      = "AWS-Services-Monitor"
    Purpose   = "service-level-anomaly-detection"
    Component = "cost-anomaly-monitor"
  })
}

# Account-Based Monitor - detects anomalies in linked accounts
resource "aws_ce_anomaly_monitor" "account_based_monitor" {
  name         = "Account-Based-Monitor"
  monitor_type = "DIMENSIONAL"

  specification = jsonencode({
    Dimension     = "LINKED_ACCOUNT"
    MatchOptions  = ["EQUALS"]
    Values        = []
  })

  tags = merge(var.cost_allocation_tags, {
    Name      = "Account-Based-Monitor"
    Purpose   = "account-level-anomaly-detection"
    Component = "cost-anomaly-monitor"
  })
}

# Tag-Based Monitor - detects anomalies in resources with specific environment tags
resource "aws_ce_anomaly_monitor" "environment_tag_monitor" {
  name         = "Environment-Tag-Monitor"
  monitor_type = "CUSTOM"

  specification = jsonencode({
    Tags = {
      Key          = "Environment"
      Values       = var.environment_tags
      MatchOptions = ["EQUALS"]
    }
  })

  tags = merge(var.cost_allocation_tags, {
    Name      = "Environment-Tag-Monitor"
    Purpose   = "tag-based-anomaly-detection"
    Component = "cost-anomaly-monitor"
  })
}

# ==============================================================================
# COST ANOMALY DETECTION SUBSCRIPTIONS
# ==============================================================================

# Daily Summary Subscription - consolidated daily reports
resource "aws_ce_anomaly_subscription" "daily_summary" {
  name      = "Daily-Cost-Summary"
  frequency = "DAILY"
  
  monitor_arn_list = [
    aws_ce_anomaly_monitor.aws_services_monitor.arn,
    aws_ce_anomaly_monitor.account_based_monitor.arn
  ]

  subscriber {
    type    = "EMAIL"
    address = var.notification_email
  }

  threshold_expression {
    and {
      dimension {
        key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
        values        = [tostring(var.daily_summary_threshold)]
        match_options = ["GREATER_THAN_OR_EQUAL"]
      }
    }
  }

  tags = merge(var.cost_allocation_tags, {
    Name      = "Daily-Cost-Summary"
    Purpose   = "daily-anomaly-summary"
    Component = "cost-anomaly-subscription"
  })
}

# Individual Alerts Subscription - immediate notifications via SNS
resource "aws_ce_anomaly_subscription" "individual_alerts" {
  name      = "Individual-Cost-Alerts"
  frequency = "IMMEDIATE"
  
  monitor_arn_list = [
    aws_ce_anomaly_monitor.environment_tag_monitor.arn
  ]

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.cost_anomaly_alerts.arn
  }

  threshold_expression {
    and {
      dimension {
        key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
        values        = [tostring(var.individual_alert_threshold)]
        match_options = ["GREATER_THAN_OR_EQUAL"]
      }
    }
  }

  tags = merge(var.cost_allocation_tags, {
    Name      = "Individual-Cost-Alerts"
    Purpose   = "immediate-anomaly-alerts"
    Component = "cost-anomaly-subscription"
  })

  depends_on = [aws_sns_topic_policy.cost_anomaly_alerts_policy]
}

# ==============================================================================
# IAM ROLE FOR LAMBDA FUNCTION
# ==============================================================================

# IAM role for the cost anomaly processor Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.resource_prefix}-lambda-role-${random_id.suffix.hex}"

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

  tags = merge(var.cost_allocation_tags, {
    Name      = "${var.resource_prefix}-lambda-role-${random_id.suffix.hex}"
    Purpose   = "lambda-execution-role"
    Component = "iam"
  })
}

# IAM policy for Lambda CloudWatch Logs access
resource "aws_iam_role_policy" "lambda_logging_policy" {
  name = "lambda-logging-policy"
  role = aws_iam_role.lambda_execution_role.id

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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# ==============================================================================
# LAMBDA FUNCTION FOR COST ANOMALY PROCESSING
# ==============================================================================

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/anomaly-processor.zip"
  source {
    content = <<EOF
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Process cost anomaly detection events and take automated actions"""
    
    try:
        # Log the incoming event
        logger.info(f"Received cost anomaly event: {json.dumps(event)}")
        
        # Extract anomaly details
        detail = event.get('detail', {})
        anomaly_score = detail.get('anomalyScore', 0)
        impact = detail.get('impact', {})
        total_impact = impact.get('totalImpact', 0)
        
        # Determine severity level
        if total_impact > 500:
            severity = "HIGH"
        elif total_impact > 100:
            severity = "MEDIUM"
        else:
            severity = "LOW"
        
        # Log anomaly details
        logger.info(f"Anomaly detected - Score: {anomaly_score}, Impact: ${total_impact}, Severity: {severity}")
        
        # Send to CloudWatch Logs for further analysis
        cloudwatch = boto3.client('logs')
        log_group = '/aws/lambda/cost-anomaly-processor'
        log_stream = f"anomaly-{datetime.now().strftime('%Y-%m-%d')}"
        
        try:
            cloudwatch.create_log_group(logGroupName=log_group)
        except cloudwatch.exceptions.ResourceAlreadyExistsException:
            pass
        
        try:
            cloudwatch.create_log_stream(
                logGroupName=log_group,
                logStreamName=log_stream
            )
        except cloudwatch.exceptions.ResourceAlreadyExistsException:
            pass
        
        # Log structured anomaly data
        structured_log = {
            "timestamp": datetime.now().isoformat(),
            "anomaly_score": anomaly_score,
            "total_impact": total_impact,
            "severity": severity,
            "event_detail": detail
        }
        
        cloudwatch.put_log_events(
            logGroupName=log_group,
            logStreamName=log_stream,
            logEvents=[
                {
                    'timestamp': int(datetime.now().timestamp() * 1000),
                    'message': json.dumps(structured_log)
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost anomaly processed successfully',
                'severity': severity,
                'impact': total_impact
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing cost anomaly: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error processing cost anomaly',
                'error': str(e)
            })
        }
EOF
    filename = "anomaly-processor.py"
  }
}

# Lambda function for processing cost anomaly events
resource "aws_lambda_function" "cost_anomaly_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.resource_prefix}-processor-${random_id.suffix.hex}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "anomaly-processor.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  description = "Process cost anomaly detection events with intelligent categorization"

  environment {
    variables = {
      LOG_LEVEL = "INFO"
      ENVIRONMENT = var.environment
    }
  }

  tags = merge(var.cost_allocation_tags, {
    Name      = "${var.resource_prefix}-processor-${random_id.suffix.hex}"
    Purpose   = "cost-anomaly-processing"
    Component = "lambda"
  })

  depends_on = [aws_iam_role_policy.lambda_logging_policy]
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.cost_anomaly_processor.function_name}"
  retention_in_days = 14

  tags = merge(var.cost_allocation_tags, {
    Name      = "/aws/lambda/${aws_lambda_function.cost_anomaly_processor.function_name}"
    Purpose   = "lambda-logs"
    Component = "cloudwatch"
  })
}

# ==============================================================================
# EVENTBRIDGE INTEGRATION
# ==============================================================================

# EventBridge rule to capture cost anomaly detection events
resource "aws_cloudwatch_event_rule" "cost_anomaly_events" {
  name        = "${var.resource_prefix}-detection-rule-${random_id.suffix.hex}"
  description = "Capture AWS Cost Anomaly Detection events"

  event_pattern = jsonencode({
    source      = ["aws.ce"]
    detail-type = ["Cost Anomaly Detection"]
  })

  tags = merge(var.cost_allocation_tags, {
    Name      = "${var.resource_prefix}-detection-rule-${random_id.suffix.hex}"
    Purpose   = "cost-anomaly-event-capture"
    Component = "eventbridge"
  })
}

# EventBridge target to invoke Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.cost_anomaly_events.name
  target_id = "CostAnomalyLambdaTarget"
  arn       = aws_lambda_function.cost_anomaly_processor.arn
}

# Lambda permission for EventBridge to invoke the function
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_anomaly_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_anomaly_events.arn
}

# ==============================================================================
# CLOUDWATCH DASHBOARD (OPTIONAL)
# ==============================================================================

# CloudWatch dashboard for cost anomaly monitoring
resource "aws_cloudwatch_dashboard" "cost_anomaly_dashboard" {
  count          = var.create_dashboard ? 1 : 0
  dashboard_name = "${var.resource_prefix}-detection-dashboard-${random_id.suffix.hex}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "log"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          query  = "SOURCE \"/aws/lambda/${aws_lambda_function.cost_anomaly_processor.function_name}\"\n| fields @timestamp, severity, total_impact, anomaly_score\n| filter severity = \"HIGH\"\n| sort @timestamp desc\n| limit 20"
          region = data.aws_region.current.name
          title  = "High Impact Cost Anomalies"
          view   = "table"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          query  = "SOURCE \"/aws/lambda/${aws_lambda_function.cost_anomaly_processor.function_name}\"\n| fields @timestamp, severity, total_impact\n| stats count() by severity\n| sort severity desc"
          region = data.aws_region.current.name
          title  = "Anomaly Count by Severity"
          view   = "table"
        }
      }
    ]
  })
}