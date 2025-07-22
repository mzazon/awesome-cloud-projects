# Main Terraform Configuration for Security Incident Response with AWS Security Hub
# This configuration deploys a comprehensive security incident response system

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate unique random suffix for resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  suffix     = random_string.suffix.result

  # Resource naming
  security_hub_role_name      = "${var.resource_name_prefix}-incident-response-role-${local.suffix}"
  lambda_role_name           = "${var.resource_name_prefix}-lambda-role-${local.suffix}"
  sns_topic_name             = "${var.resource_name_prefix}-incident-alerts-${local.suffix}"
  lambda_function_name       = "${var.resource_name_prefix}-incident-processor-${local.suffix}"
  threat_intel_function_name = "${var.resource_name_prefix}-threat-intelligence-${local.suffix}"
  sqs_queue_name             = "${var.resource_name_prefix}-incident-queue-${local.suffix}"
  custom_action_name         = "${var.resource_name_prefix}-escalate-to-soc-${local.suffix}"

  # Common tags
  common_tags = merge(var.tags, {
    Recipe      = "security-incident-response-aws-security-hub"
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# ===================================
# Security Hub Configuration
# ===================================

# Enable Security Hub
resource "aws_securityhub_account" "main" {
  enable_default_standards = var.enable_security_standards

  depends_on = [aws_securityhub_standards_subscription.cis]
}

# Enable CIS AWS Foundations Benchmark (if enabled)
resource "aws_securityhub_standards_subscription" "cis" {
  count         = var.enable_cis_benchmark ? 1 : 0
  standards_arn = "arn:aws:securityhub:${local.region}::standards/cis-aws-foundations-benchmark/v/1.4.0"
  depends_on    = [aws_securityhub_account.main]
}

# Security Hub Custom Action for manual escalation
resource "aws_securityhub_action_target" "escalate_to_soc" {
  count       = var.create_custom_action ? 1 : 0
  name        = "Escalate to SOC"
  description = "Escalate this finding to the Security Operations Center"
  identifier  = local.custom_action_name

  depends_on = [aws_securityhub_account.main]
}

# ===================================
# IAM Roles and Policies
# ===================================

# IAM role for Security Hub service
resource "aws_iam_role" "security_hub_role" {
  name = local.security_hub_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "securityhub.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
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

  tags = local.common_tags
}

# Attach basic execution role to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Security Hub and SNS access
resource "aws_iam_policy" "security_hub_lambda_policy" {
  name        = "SecurityHubLambdaPolicy-${local.suffix}"
  description = "Policy for Lambda functions to access Security Hub and SNS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "securityhub:BatchUpdateFindings",
          "securityhub:GetFindings",
          "sns:Publish"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach custom policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_security_hub_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.security_hub_lambda_policy.arn
}

# ===================================
# SNS Topic and Subscriptions
# ===================================

# SNS topic for security incident notifications
resource "aws_sns_topic" "security_incidents" {
  name         = local.sns_topic_name
  display_name = "Security Incident Alerts"

  delivery_policy = jsonencode({
    http = {
      defaultHealthyRetryPolicy = {
        numRetries         = var.sns_delivery_retry_policy.num_retries
        minDelayTarget     = var.sns_delivery_retry_policy.min_delay_target
        maxDelayTarget     = var.sns_delivery_retry_policy.max_delay_target
        numMinDelayRetries = 0
        numMaxDelayRetries = 0
        numNoDelayRetries  = 0
        backoffFunction    = var.sns_delivery_retry_policy.backoff_function
      }
      disableSubscriptionOverrides = false
    }
  })

  tags = local.common_tags
}

# SNS topic policy allowing Lambda to publish
resource "aws_sns_topic_policy" "security_incidents_policy" {
  arn = aws_sns_topic.security_incidents.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.security_incidents.arn
      }
    ]
  })
}

# Email subscription (optional)
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.security_incidents.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ===================================
# SQS Queue for Incident Buffering
# ===================================

# SQS queue for buffering incident notifications
resource "aws_sqs_queue" "incident_queue" {
  name                      = local.sqs_queue_name
  message_retention_seconds = var.sqs_message_retention_period
  receive_wait_time_seconds = 20
  visibility_timeout_seconds = 300

  tags = local.common_tags
}

# SQS queue policy allowing SNS to send messages
resource "aws_sqs_queue_policy" "incident_queue_policy" {
  queue_url = aws_sqs_queue.incident_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.incident_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.security_incidents.arn
          }
        }
      }
    ]
  })
}

# SNS subscription to SQS queue
resource "aws_sns_topic_subscription" "sqs_notification" {
  topic_arn = aws_sns_topic.security_incidents.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.incident_queue.arn
}

# ===================================
# Lambda Functions
# ===================================

# Create Lambda function code for incident processing
data "archive_file" "incident_processor_zip" {
  type        = "zip"
  output_path = "/tmp/incident_processor.zip"
  source {
    content = templatefile("${path.module}/lambda_code/incident_processor.py", {
      sns_topic_arn = aws_sns_topic.security_incidents.arn
      aws_region    = local.region
    })
    filename = "incident_processor.py"
  }
}

# Main incident processing Lambda function
resource "aws_lambda_function" "incident_processor" {
  filename         = data.archive_file.incident_processor_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "incident_processor.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.incident_processor_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.security_incidents.arn
      AWS_REGION    = local.region
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_security_hub_policy,
    aws_cloudwatch_log_group.incident_processor_logs
  ]
}

# CloudWatch log group for incident processor
resource "aws_cloudwatch_log_group" "incident_processor_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  tags              = local.common_tags
}

# Threat Intelligence Lambda function (if enabled)
data "archive_file" "threat_intelligence_zip" {
  count       = var.enable_threat_intelligence ? 1 : 0
  type        = "zip"
  output_path = "/tmp/threat_intelligence.zip"
  source {
    content  = file("${path.module}/lambda_code/threat_intelligence.py")
    filename = "threat_intelligence.py"
  }
}

resource "aws_lambda_function" "threat_intelligence" {
  count            = var.enable_threat_intelligence ? 1 : 0
  filename         = data.archive_file.threat_intelligence_zip[0].output_path
  function_name    = local.threat_intel_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "threat_intelligence.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.threat_intelligence_zip[0].output_base64sha256

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_security_hub_policy,
    aws_cloudwatch_log_group.threat_intelligence_logs[0]
  ]
}

# CloudWatch log group for threat intelligence function
resource "aws_cloudwatch_log_group" "threat_intelligence_logs" {
  count             = var.enable_threat_intelligence ? 1 : 0
  name              = "/aws/lambda/${local.threat_intel_function_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  tags              = local.common_tags
}

# ===================================
# EventBridge Rules and Targets
# ===================================

# EventBridge rule for high severity findings
resource "aws_cloudwatch_event_rule" "security_hub_high_severity" {
  name        = "security-hub-high-severity"
  description = "Process high and critical severity Security Hub findings"
  state       = "ENABLED"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = var.severity_filter
        }
        Workflow = {
          Status = ["NEW"]
        }
      }
    }
  })

  tags = local.common_tags
}

# EventBridge target for high severity rule
resource "aws_cloudwatch_event_target" "high_severity_lambda" {
  rule      = aws_cloudwatch_event_rule.security_hub_high_severity.name
  target_id = "SecurityHubHighSeverityTarget"
  arn       = aws_lambda_function.incident_processor.arn
}

# Lambda permission for EventBridge to invoke function
resource "aws_lambda_permission" "allow_eventbridge_high_severity" {
  statement_id  = "AllowExecutionFromEventBridgeHighSeverity"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.incident_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.security_hub_high_severity.arn
}

# EventBridge rule for custom action escalation
resource "aws_cloudwatch_event_rule" "security_hub_custom_escalation" {
  count       = var.create_custom_action ? 1 : 0
  name        = "security-hub-custom-escalation"
  description = "Process manual escalation from Security Hub"
  state       = "ENABLED"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Custom Action"]
    detail = {
      actionName        = ["Escalate to SOC"]
      actionDescription = ["Escalate this finding to the Security Operations Center"]
    }
  })

  tags = local.common_tags
}

# EventBridge target for custom action rule
resource "aws_cloudwatch_event_target" "custom_escalation_lambda" {
  count     = var.create_custom_action ? 1 : 0
  rule      = aws_cloudwatch_event_rule.security_hub_custom_escalation[0].name
  target_id = "SecurityHubCustomEscalationTarget"
  arn       = aws_lambda_function.incident_processor.arn
}

# Lambda permission for custom action EventBridge rule
resource "aws_lambda_permission" "allow_eventbridge_custom_escalation" {
  count         = var.create_custom_action ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridgeCustomEscalation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.incident_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.security_hub_custom_escalation[0].arn
}

# ===================================
# CloudWatch Dashboard and Alarms
# ===================================

# CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "security_hub_incident_response" {
  count          = var.enable_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "SecurityHubIncidentResponse"

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
            ["AWS/Lambda", "Invocations", "FunctionName", local.lambda_function_name],
            ["AWS/Lambda", "Errors", "FunctionName", local.lambda_function_name],
            ["AWS/Lambda", "Duration", "FunctionName", local.lambda_function_name]
          ]
          period = 300
          stat   = "Sum"
          region = local.region
          title  = "Security Incident Processing Metrics"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/SNS", "NumberOfMessagesPublished", "TopicName", local.sns_topic_name],
            ["AWS/SNS", "NumberOfNotificationsFailed", "TopicName", local.sns_topic_name]
          ]
          period = 300
          stat   = "Sum"
          region = local.region
          title  = "Notification Delivery Metrics"
        }
      }
    ]
  })
}

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "SecurityHubIncidentProcessingFailures"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when Security Hub incident processing fails"
  alarm_actions       = [aws_sns_topic.security_incidents.arn]

  dimensions = {
    FunctionName = local.lambda_function_name
  }

  tags = local.common_tags
}

# CloudWatch alarm for SNS notification failures
resource "aws_cloudwatch_metric_alarm" "sns_failures" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "SecurityHubNotificationFailures"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "NumberOfNotificationsFailed"
  namespace           = "AWS/SNS"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when SNS notifications fail to deliver"
  alarm_actions       = [aws_sns_topic.security_incidents.arn]

  dimensions = {
    TopicName = local.sns_topic_name
  }

  tags = local.common_tags
}