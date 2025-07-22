# Main Terraform configuration for automated security incident response with AWS Security Hub
#
# This file creates the complete infrastructure for automated security incident response
# including Security Hub, Lambda functions, EventBridge rules, SNS notifications, and IAM roles.

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent resource naming
locals {
  name_prefix = var.resource_name_prefix != "" ? "${var.resource_name_prefix}-" : ""
  name_suffix = var.resource_name_suffix != "" ? "-${var.resource_name_suffix}" : "-${random_id.suffix.hex}"
  
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
  }
  
  # Security finding severity levels to process
  severity_levels = compact([
    var.process_critical_findings ? "CRITICAL" : null,
    var.process_high_findings ? "HIGH" : null,
    var.process_medium_findings ? "MEDIUM" : null,
    var.process_low_findings ? "LOW" : null
  ])
}

# ===================================
# KMS Key for Encryption
# ===================================

resource "aws_kms_key" "security_response" {
  count = var.enable_kms_encryption ? 1 : 0
  
  description             = "KMS key for security incident response encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Security Hub Service"
        Effect = "Allow"
        Principal = {
          Service = "securityhub.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow Lambda Service"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}security-response-key${local.name_suffix}"
  })
}

resource "aws_kms_alias" "security_response" {
  count = var.enable_kms_encryption ? 1 : 0
  
  name          = "alias/${local.name_prefix}security-response${local.name_suffix}"
  target_key_id = aws_kms_key.security_response[0].key_id
}

# ===================================
# Security Hub Configuration
# ===================================

resource "aws_securityhub_account" "main" {
  enable_default_standards = var.enable_security_hub_standards
  
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls      = true
}

# Enable specific security standards
resource "aws_securityhub_standards_subscription" "standards" {
  count = length(var.security_standards)
  
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::ruleset/finding-format/${var.security_standards[count.index]}"
  
  depends_on = [aws_securityhub_account.main]
}

# ===================================
# SNS Topic for Notifications
# ===================================

resource "aws_sns_topic" "security_incidents" {
  name = "${local.name_prefix}security-incidents${local.name_suffix}"
  
  kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.security_response[0].arn : null
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}security-incidents${local.name_suffix}"
    Description = "SNS topic for security incident notifications"
  })
}

# Email subscription for notifications
resource "aws_sns_topic_subscription" "email" {
  count = var.enable_email_notifications ? 1 : 0
  
  topic_arn = aws_sns_topic.security_incidents.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# SNS topic policy to allow Lambda functions to publish
resource "aws_sns_topic_policy" "security_incidents" {
  arn = aws_sns_topic.security_incidents.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.incident_response.arn
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.security_incidents.arn
      }
    ]
  })
}

# ===================================
# IAM Role for Lambda Functions
# ===================================

# Trust policy for Lambda functions
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# IAM role for incident response Lambda functions
resource "aws_iam_role" "incident_response" {
  name               = "${local.name_prefix}incident-response-role${local.name_suffix}"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}incident-response-role${local.name_suffix}"
    Description = "IAM role for security incident response Lambda functions"
  })
}

# Comprehensive IAM policy for incident response
data "aws_iam_policy_document" "incident_response" {
  # CloudWatch Logs permissions
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
  
  # Security Hub permissions
  statement {
    effect = "Allow"
    actions = [
      "securityhub:GetFindings",
      "securityhub:BatchUpdateFindings",
      "securityhub:BatchImportFindings"
    ]
    resources = ["*"]
  }
  
  # SNS permissions
  statement {
    effect = "Allow"
    actions = [
      "sns:Publish"
    ]
    resources = [aws_sns_topic.security_incidents.arn]
  }
  
  # EC2 permissions for security group remediation
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeSecurityGroups",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:CreateTags"
    ]
    resources = ["*"]
  }
  
  # IAM permissions for policy remediation
  statement {
    effect = "Allow"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRole",
      "iam:GetRolePolicy"
    ]
    resources = ["*"]
  }
  
  # S3 permissions for bucket policy remediation
  statement {
    effect = "Allow"
    actions = [
      "s3:PutBucketPolicy",
      "s3:GetBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketPublicAccessBlock"
    ]
    resources = ["*"]
  }
  
  # KMS permissions if encryption is enabled
  dynamic "statement" {
    for_each = var.enable_kms_encryption ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ]
      resources = [aws_kms_key.security_response[0].arn]
    }
  }
}

resource "aws_iam_role_policy" "incident_response" {
  name   = "IncidentResponsePolicy"
  role   = aws_iam_role.incident_response.id
  policy = data.aws_iam_policy_document.incident_response.json
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.incident_response.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ===================================
# CloudWatch Log Groups
# ===================================

resource "aws_cloudwatch_log_group" "classification_function" {
  name              = "/aws/lambda/${local.name_prefix}security-classification${local.name_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  kms_key_id = var.enable_kms_encryption ? aws_kms_key.security_response[0].arn : null
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}classification-logs${local.name_suffix}"
  })
}

resource "aws_cloudwatch_log_group" "remediation_function" {
  name              = "/aws/lambda/${local.name_prefix}security-remediation${local.name_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  kms_key_id = var.enable_kms_encryption ? aws_kms_key.security_response[0].arn : null
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}remediation-logs${local.name_suffix}"
  })
}

resource "aws_cloudwatch_log_group" "notification_function" {
  name              = "/aws/lambda/${local.name_prefix}security-notification${local.name_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  kms_key_id = var.enable_kms_encryption ? aws_kms_key.security_response[0].arn : null
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}notification-logs${local.name_suffix}"
  })
}

# ===================================
# Lambda Functions
# ===================================

# Security Finding Classification Lambda Function
resource "aws_lambda_function" "classification" {
  filename         = "classification_function.zip"
  function_name    = "${local.name_prefix}security-classification${local.name_suffix}"
  role            = aws_iam_role.incident_response.arn
  handler         = "classification_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  kms_key_arn = var.enable_kms_encryption ? aws_kms_key.security_response[0].arn : null
  
  source_code_hash = data.archive_file.classification_zip.output_base64sha256
  
  environment {
    variables = {
      ENVIRONMENT = var.environment
      PROJECT     = var.project_name
    }
  }
  
  depends_on = [
    aws_cloudwatch_log_group.classification_function
  ]
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}security-classification${local.name_suffix}"
    Description = "Classifies security findings for automated response"
  })
}

# Security Remediation Lambda Function
resource "aws_lambda_function" "remediation" {
  filename         = "remediation_function.zip"
  function_name    = "${local.name_prefix}security-remediation${local.name_suffix}"
  role            = aws_iam_role.incident_response.arn
  handler         = "remediation_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = 512 # Higher memory for remediation tasks
  
  kms_key_arn = var.enable_kms_encryption ? aws_kms_key.security_response[0].arn : null
  
  source_code_hash = data.archive_file.remediation_zip.output_base64sha256
  
  environment {
    variables = {
      ENVIRONMENT                    = var.environment
      PROJECT                       = var.project_name
      AUTO_REMEDIATION_ENABLED      = var.auto_remediation_enabled
      SEVERITY_THRESHOLD            = var.auto_remediation_severity_threshold
    }
  }
  
  depends_on = [
    aws_cloudwatch_log_group.remediation_function
  ]
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}security-remediation${local.name_suffix}"
    Description = "Performs automated remediation of security findings"
  })
}

# Security Notification Lambda Function
resource "aws_lambda_function" "notification" {
  filename         = "notification_function.zip"
  function_name    = "${local.name_prefix}security-notification${local.name_suffix}"
  role            = aws_iam_role.incident_response.arn
  handler         = "notification_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  kms_key_arn = var.enable_kms_encryption ? aws_kms_key.security_response[0].arn : null
  
  source_code_hash = data.archive_file.notification_zip.output_base64sha256
  
  environment {
    variables = {
      SNS_TOPIC_ARN    = aws_sns_topic.security_incidents.arn
      ENVIRONMENT      = var.environment
      PROJECT          = var.project_name
      SLACK_WEBHOOK    = var.slack_webhook_url
      ENABLE_SLACK     = var.enable_slack_notifications
    }
  }
  
  depends_on = [
    aws_cloudwatch_log_group.notification_function
  ]
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}security-notification${local.name_suffix}"
    Description = "Sends notifications for security incidents"
  })
}

# ===================================
# Lambda Function Code Archives
# ===================================

# Classification function code
data "archive_file" "classification_zip" {
  type        = "zip"
  output_path = "classification_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_code/classification_function.py", {
      environment = var.environment
      project     = var.project_name
    })
    filename = "classification_function.py"
  }
}

# Remediation function code
data "archive_file" "remediation_zip" {
  type        = "zip"
  output_path = "remediation_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_code/remediation_function.py", {
      environment                = var.environment
      project                   = var.project_name
      auto_remediation_enabled  = var.auto_remediation_enabled
      severity_threshold        = var.auto_remediation_severity_threshold
    })
    filename = "remediation_function.py"
  }
}

# Notification function code
data "archive_file" "notification_zip" {
  type        = "zip"
  output_path = "notification_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_code/notification_function.py", {
      sns_topic_arn    = aws_sns_topic.security_incidents.arn
      environment      = var.environment
      project          = var.project_name
      aws_region       = data.aws_region.current.name
      aws_account_id   = data.aws_caller_identity.current.account_id
    })
    filename = "notification_function.py"
  }
}

# ===================================
# EventBridge Rules
# ===================================

# EventBridge rule for high/critical severity findings
resource "aws_cloudwatch_event_rule" "critical_findings" {
  name        = "${local.name_prefix}security-hub-critical${local.name_suffix}"
  description = "Triggers incident response for high/critical security findings"
  
  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["HIGH", "CRITICAL"]
        }
        RecordState = ["ACTIVE"]
        WorkflowState = ["NEW"]
      }
    }
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}critical-findings-rule${local.name_suffix}"
  })
}

# EventBridge rule for medium severity findings (notification only)
resource "aws_cloudwatch_event_rule" "medium_findings" {
  count = var.process_medium_findings ? 1 : 0
  
  name        = "${local.name_prefix}security-hub-medium${local.name_suffix}"
  description = "Triggers notifications for medium severity security findings"
  
  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["MEDIUM"]
        }
        RecordState = ["ACTIVE"]
        WorkflowState = ["NEW"]
      }
    }
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}medium-findings-rule${local.name_suffix}"
  })
}

# EventBridge rule for manual escalation
resource "aws_cloudwatch_event_rule" "manual_escalation" {
  name        = "${local.name_prefix}manual-escalation${local.name_suffix}"
  description = "Handles manual escalation of security findings"
  
  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Custom Action"]
    detail = {
      actionName = ["Escalate to Security Team"]
    }
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}manual-escalation-rule${local.name_suffix}"
  })
}

# ===================================
# EventBridge Targets
# ===================================

# Targets for critical findings rule
resource "aws_cloudwatch_event_target" "critical_classification" {
  rule      = aws_cloudwatch_event_rule.critical_findings.name
  target_id = "ClassificationTarget"
  arn       = aws_lambda_function.classification.arn
}

resource "aws_cloudwatch_event_target" "critical_remediation" {
  count = var.auto_remediation_enabled ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.critical_findings.name
  target_id = "RemediationTarget"
  arn       = aws_lambda_function.remediation.arn
}

resource "aws_cloudwatch_event_target" "critical_notification" {
  rule      = aws_cloudwatch_event_rule.critical_findings.name
  target_id = "NotificationTarget"
  arn       = aws_lambda_function.notification.arn
}

# Targets for medium findings rule
resource "aws_cloudwatch_event_target" "medium_classification" {
  count = var.process_medium_findings ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.medium_findings[0].name
  target_id = "ClassificationTarget"
  arn       = aws_lambda_function.classification.arn
}

resource "aws_cloudwatch_event_target" "medium_notification" {
  count = var.process_medium_findings ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.medium_findings[0].name
  target_id = "NotificationTarget"
  arn       = aws_lambda_function.notification.arn
}

# Target for manual escalation rule
resource "aws_cloudwatch_event_target" "manual_notification" {
  rule      = aws_cloudwatch_event_rule.manual_escalation.name
  target_id = "ManualNotificationTarget"
  arn       = aws_lambda_function.notification.arn
}

# ===================================
# Lambda Permissions for EventBridge
# ===================================

resource "aws_lambda_permission" "classification_critical" {
  statement_id  = "AllowEventBridgeCritical"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.classification.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.critical_findings.arn
}

resource "aws_lambda_permission" "classification_medium" {
  count = var.process_medium_findings ? 1 : 0
  
  statement_id  = "AllowEventBridgeMedium"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.classification.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.medium_findings[0].arn
}

resource "aws_lambda_permission" "remediation_critical" {
  count = var.auto_remediation_enabled ? 1 : 0
  
  statement_id  = "AllowEventBridgeRemediation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.critical_findings.arn
}

resource "aws_lambda_permission" "notification_critical" {
  statement_id  = "AllowEventBridgeNotificationCritical"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notification.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.critical_findings.arn
}

resource "aws_lambda_permission" "notification_medium" {
  count = var.process_medium_findings ? 1 : 0
  
  statement_id  = "AllowEventBridgeNotificationMedium"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notification.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.medium_findings[0].arn
}

resource "aws_lambda_permission" "notification_manual" {
  statement_id  = "AllowEventBridgeManual"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notification.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.manual_escalation.arn
}

# ===================================
# Security Hub Custom Actions
# ===================================

resource "aws_securityhub_action_target" "escalate" {
  name        = "Escalate to Security Team"
  identifier  = "escalate-to-security-team"
  description = "Manually escalate security finding to security team"
}

# ===================================
# Security Hub Insights
# ===================================

resource "aws_securityhub_insight" "critical_incidents" {
  name      = "Critical Security Incidents"
  group_by_attribute = "ProductName"
  
  filters {
    severity_label {
      comparison = "EQUALS"
      value      = "CRITICAL"
    }
    
    record_state {
      comparison = "EQUALS"
      value      = "ACTIVE"
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}critical-incidents-insight${local.name_suffix}"
  })
}

resource "aws_securityhub_insight" "unresolved_findings" {
  name      = "Unresolved Security Findings"
  group_by_attribute = "SeverityLabel"
  
  filters {
    workflow_status {
      comparison = "EQUALS"
      value      = "NEW"
    }
    
    record_state {
      comparison = "EQUALS"
      value      = "ACTIVE"
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}unresolved-findings-insight${local.name_suffix}"
  })
}