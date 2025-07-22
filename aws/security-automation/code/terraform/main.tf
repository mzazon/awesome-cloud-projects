# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  resource_prefix = "${var.automation_prefix}-${random_string.suffix.result}"
  
  common_tags = merge(
    {
      Project     = "security-automation"
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

# =========================================================================
# IAM ROLES AND POLICIES
# =========================================================================

# Lambda execution role
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.resource_prefix}-lambda-role"

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

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for security automation
resource "aws_iam_policy" "security_automation_policy" {
  name        = "${local.resource_prefix}-policy"
  description = "Policy for security automation Lambda functions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "securityhub:BatchUpdateFindings",
          "securityhub:GetFindings",
          "securityhub:BatchGetAutomationRules",
          "securityhub:CreateAutomationRule",
          "securityhub:UpdateAutomationRule",
          "ssm:StartAutomationExecution",
          "ssm:GetAutomationExecution",
          "ec2:DescribeInstances",
          "ec2:StopInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateSnapshot",
          "ec2:DescribeSnapshots",
          "sns:Publish",
          "sqs:SendMessage",
          "events:PutEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach custom policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_security_policy" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.security_automation_policy.arn
}

# =========================================================================
# SNS TOPIC AND SQS QUEUE
# =========================================================================

# SNS topic for security notifications
resource "aws_sns_topic" "security_notifications" {
  name = "${local.resource_prefix}-notifications"

  delivery_policy = jsonencode({
    healthyRetryPolicy = {
      minDelayTarget = var.sns_delivery_policy.min_delay_target
      maxDelayTarget = var.sns_delivery_policy.max_delay_target
      numRetries     = var.sns_delivery_policy.num_retries
    }
  })

  tags = local.common_tags
}

# SQS dead letter queue
resource "aws_sqs_queue" "dlq" {
  name = "${local.resource_prefix}-dlq"

  message_retention_seconds = var.dlq_message_retention_period
  visibility_timeout_seconds = var.dlq_visibility_timeout

  tags = local.common_tags
}

# Optional email subscription to SNS topic
resource "aws_sns_topic_subscription" "email_notification" {
  count = var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.security_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# =========================================================================
# LAMBDA FUNCTIONS
# =========================================================================

# Lambda function source code for triage
data "archive_file" "triage_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/triage.zip"
  
  source {
    content = file("${path.module}/lambda_code/triage.py")
    filename = "triage.py"
  }
}

# Lambda function source code for remediation
data "archive_file" "remediation_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/remediation.zip"
  
  source {
    content = file("${path.module}/lambda_code/remediation.py")
    filename = "remediation.py"
  }
}

# Lambda function source code for notification
data "archive_file" "notification_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/notification.zip"
  
  source {
    content = file("${path.module}/lambda_code/notification.py")
    filename = "notification.py"
  }
}

# Lambda function source code for error handler
data "archive_file" "error_handler_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/error_handler.zip"
  
  source {
    content = file("${path.module}/lambda_code/error_handler.py")
    filename = "error_handler.py"
  }
}

# Triage Lambda function
resource "aws_lambda_function" "triage" {
  filename         = data.archive_file.triage_lambda_zip.output_path
  function_name    = "${local.resource_prefix}-triage"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "triage.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 60
  memory_size     = 256
  description     = "Security finding triage and response classification"

  source_code_hash = data.archive_file.triage_lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.security_notifications.arn
      DLQ_URL       = aws_sqs_queue.dlq.url
    }
  }

  tags = local.common_tags
}

# Remediation Lambda function
resource "aws_lambda_function" "remediation" {
  filename         = data.archive_file.remediation_lambda_zip.output_path
  function_name    = "${local.resource_prefix}-remediation"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "remediation.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  description     = "Automated security remediation actions"

  source_code_hash = data.archive_file.remediation_lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.security_notifications.arn
      DLQ_URL       = aws_sqs_queue.dlq.url
    }
  }

  tags = local.common_tags
}

# Notification Lambda function
resource "aws_lambda_function" "notification" {
  filename         = data.archive_file.notification_lambda_zip.output_path
  function_name    = "${local.resource_prefix}-notification"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "notification.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 60
  memory_size     = 256
  description     = "Security finding notifications"

  source_code_hash = data.archive_file.notification_lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.security_notifications.arn
    }
  }

  tags = local.common_tags
}

# Error handler Lambda function
resource "aws_lambda_function" "error_handler" {
  filename         = data.archive_file.error_handler_lambda_zip.output_path
  function_name    = "${local.resource_prefix}-error-handler"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "error_handler.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 60
  memory_size     = 256
  description     = "Handle automation errors"

  source_code_hash = data.archive_file.error_handler_lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.security_notifications.arn
    }
  }

  tags = local.common_tags
}

# =========================================================================
# EVENTBRIDGE RULES
# =========================================================================

# EventBridge rule for Security Hub findings
resource "aws_cloudwatch_event_rule" "security_hub_findings" {
  name        = "${local.resource_prefix}-findings-rule"
  description = "Route Security Hub findings to automation"
  state       = var.event_rule_state

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = var.finding_severities
        }
        Workflow = {
          Status = ["NEW"]
        }
      }
    }
  })

  tags = local.common_tags
}

# EventBridge rule for remediation actions
resource "aws_cloudwatch_event_rule" "remediation_actions" {
  name        = "${local.resource_prefix}-remediation-rule"
  description = "Route remediation actions to Lambda"
  state       = var.event_rule_state

  event_pattern = jsonencode({
    source      = ["security.automation"]
    detail-type = ["Security Response Required"]
  })

  tags = local.common_tags
}

# EventBridge rule for custom actions
resource "aws_cloudwatch_event_rule" "custom_actions" {
  name        = "${local.resource_prefix}-custom-actions"
  description = "Handle custom Security Hub actions"
  state       = var.event_rule_state

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Custom Action"]
    detail = {
      actionName = ["TriggerAutomatedRemediation", "EscalateToSOC"]
    }
  })

  tags = local.common_tags
}

# EventBridge rule for error handling
resource "aws_cloudwatch_event_rule" "error_handling" {
  name        = "${local.resource_prefix}-error-handling"
  description = "Handle failed automation events"
  state       = var.event_rule_state

  event_pattern = jsonencode({
    source      = ["aws.events"]
    detail-type = ["EventBridge Rule Execution Failed"]
  })

  tags = local.common_tags
}

# =========================================================================
# EVENTBRIDGE TARGETS
# =========================================================================

# Target for Security Hub findings rule - triage function
resource "aws_cloudwatch_event_target" "triage_target" {
  rule      = aws_cloudwatch_event_rule.security_hub_findings.name
  target_id = "TriageTarget"
  arn       = aws_lambda_function.triage.arn
}

# Target for Security Hub findings rule - notification function
resource "aws_cloudwatch_event_target" "notification_target" {
  rule      = aws_cloudwatch_event_rule.security_hub_findings.name
  target_id = "NotificationTarget"
  arn       = aws_lambda_function.notification.arn
}

# Target for remediation actions rule
resource "aws_cloudwatch_event_target" "remediation_target" {
  rule      = aws_cloudwatch_event_rule.remediation_actions.name
  target_id = "RemediationTarget"
  arn       = aws_lambda_function.remediation.arn
}

# Target for custom actions rule
resource "aws_cloudwatch_event_target" "custom_action_target" {
  rule      = aws_cloudwatch_event_rule.custom_actions.name
  target_id = "CustomActionTarget"
  arn       = aws_lambda_function.triage.arn
}

# Target for error handling rule
resource "aws_cloudwatch_event_target" "error_handler_target" {
  rule      = aws_cloudwatch_event_rule.error_handling.name
  target_id = "ErrorHandlerTarget"
  arn       = aws_lambda_function.error_handler.arn
}

# =========================================================================
# LAMBDA PERMISSIONS
# =========================================================================

# Permission for EventBridge to invoke triage Lambda
resource "aws_lambda_permission" "allow_eventbridge_triage" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.triage.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.security_hub_findings.arn
}

# Permission for EventBridge to invoke notification Lambda
resource "aws_lambda_permission" "allow_eventbridge_notification" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notification.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.security_hub_findings.arn
}

# Permission for EventBridge to invoke remediation Lambda
resource "aws_lambda_permission" "allow_eventbridge_remediation" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.remediation_actions.arn
}

# Permission for EventBridge to invoke error handler Lambda
resource "aws_lambda_permission" "allow_eventbridge_error_handler" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.error_handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.error_handling.arn
}

# Permission for custom actions
resource "aws_lambda_permission" "allow_eventbridge_custom_actions" {
  statement_id  = "AllowExecutionFromEventBridgeCustomActions"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.triage.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.custom_actions.arn
}

# =========================================================================
# SECURITY HUB AUTOMATION RULES
# =========================================================================

# Security Hub automation rule for high severity findings
resource "aws_securityhub_automation_rule" "high_severity" {
  count = var.enable_automation_rules ? 1 : 0

  rule_name   = "Auto-Process-High-Severity"
  description = "Automatically mark high severity findings as in progress"
  rule_order  = 1
  rule_status = "ENABLED"

  criteria {
    severity_label {
      comparison = "EQUALS"
      value      = "HIGH"
    }
    workflow_status {
      comparison = "EQUALS"
      value      = "NEW"
    }
  }

  actions {
    finding_fields_update {
      note {
        text       = "High severity finding detected - automated response initiated"
        updated_by = "SecurityAutomation"
      }
      workflow {
        status = "IN_PROGRESS"
      }
    }
  }

  tags = local.common_tags
}

# Security Hub automation rule for critical findings
resource "aws_securityhub_automation_rule" "critical_severity" {
  count = var.enable_automation_rules ? 1 : 0

  rule_name   = "Auto-Process-Critical-Findings"
  description = "Automatically process critical findings"
  rule_order  = 2
  rule_status = "ENABLED"

  criteria {
    severity_label {
      comparison = "EQUALS"
      value      = "CRITICAL"
    }
    workflow_status {
      comparison = "EQUALS"
      value      = "NEW"
    }
  }

  actions {
    finding_fields_update {
      note {
        text       = "Critical finding detected - immediate attention required"
        updated_by = "SecurityAutomation"
      }
      workflow {
        status = "IN_PROGRESS"
      }
      severity {
        label = "CRITICAL"
      }
    }
  }

  tags = local.common_tags
}

# =========================================================================
# SECURITY HUB CUSTOM ACTIONS
# =========================================================================

# Custom action for manual remediation trigger
resource "aws_securityhub_action_target" "trigger_remediation" {
  count = var.enable_custom_actions ? 1 : 0

  identifier  = "trigger-remediation"
  name        = "TriggerAutomatedRemediation"
  description = "Trigger automated remediation for selected findings"
}

# Custom action for escalation
resource "aws_securityhub_action_target" "escalate_soc" {
  count = var.enable_custom_actions ? 1 : 0

  identifier  = "escalate-soc"
  name        = "EscalateToSOC"
  description = "Escalate finding to Security Operations Center"
}

# =========================================================================
# SYSTEMS MANAGER AUTOMATION DOCUMENT
# =========================================================================

# Systems Manager automation document for instance isolation
resource "aws_ssm_document" "isolate_instance" {
  count = var.enable_ssm_automation ? 1 : 0

  name          = "${local.resource_prefix}-isolate-instance"
  document_type = "Automation"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Isolate EC2 instance for security incident response"
    assumeRole    = "{{ AutomationAssumeRole }}"
    parameters = {
      InstanceId = {
        type        = "String"
        description = "EC2 instance ID to isolate"
      }
      AutomationAssumeRole = {
        type        = "String"
        description = "IAM role for automation execution"
      }
    }
    mainSteps = [
      {
        name   = "StopInstance"
        action = "aws:executeAwsApi"
        inputs = {
          Service     = "ec2"
          Api         = "StopInstances"
          InstanceIds = ["{{ InstanceId }}"]
        }
      },
      {
        name   = "CreateSnapshot"
        action = "aws:executeScript"
        inputs = {
          Runtime = "python3.8"
          Handler = "create_snapshot"
          Script = "def create_snapshot(events, context):\n    import boto3\n    ec2 = boto3.client('ec2')\n    instance_id = events['InstanceId']\n    \n    # Get instance volumes\n    response = ec2.describe_instances(InstanceIds=[instance_id])\n    instance = response['Reservations'][0]['Instances'][0]\n    \n    snapshots = []\n    for device in instance.get('BlockDeviceMappings', []):\n        volume_id = device['Ebs']['VolumeId']\n        snapshot = ec2.create_snapshot(\n            VolumeId=volume_id,\n            Description=f'Forensic snapshot for {instance_id}'\n        )\n        snapshots.append(snapshot['SnapshotId'])\n    \n    return {'snapshots': snapshots}"
          InputPayload = {
            InstanceId = "{{ InstanceId }}"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# =========================================================================
# CLOUDWATCH MONITORING
# =========================================================================

# CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  alarm_name          = "${local.resource_prefix}-lambda-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = var.cloudwatch_alarm_threshold
  alarm_description   = "Security automation Lambda errors"
  alarm_actions       = [aws_sns_topic.security_notifications.arn]

  dimensions = {
    FunctionName = aws_lambda_function.triage.function_name
  }

  tags = local.common_tags
}

# CloudWatch alarm for EventBridge failures
resource "aws_cloudwatch_metric_alarm" "eventbridge_failures" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  alarm_name          = "${local.resource_prefix}-eventbridge-failures"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "FailedInvocations"
  namespace           = "AWS/Events"
  period              = 300
  statistic           = "Sum"
  threshold           = var.cloudwatch_alarm_threshold
  alarm_description   = "EventBridge rule failures"
  alarm_actions       = [aws_sns_topic.security_notifications.arn]

  dimensions = {
    RuleName = aws_cloudwatch_event_rule.security_hub_findings.name
  }

  tags = local.common_tags
}

# CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "security_automation" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  dashboard_name = "${local.resource_prefix}-monitoring"

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
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.triage.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Security Automation Metrics"
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
            ["AWS/Events", "SuccessfulInvocations", "RuleName", aws_cloudwatch_event_rule.security_hub_findings.name],
            [".", "FailedInvocations", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "EventBridge Rule Metrics"
        }
      }
    ]
  })
}