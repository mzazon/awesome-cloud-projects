# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  resource_prefix = "${var.project_name}-${random_string.suffix.result}"
  repository_name = var.repository_name != null ? var.repository_name : "${local.resource_prefix}-repo"
  
  # Combine team leads and senior developers for approval pool
  approval_pool_members = concat(var.team_lead_users, var.senior_developer_users)
  
  # Common tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
    Purpose     = "codecommit-git-workflows"
  })
}

# ==============================================================================
# CodeCommit Repository
# ==============================================================================

# Create CodeCommit repository
resource "aws_codecommit_repository" "main" {
  repository_name = local.repository_name
  description     = var.repository_description

  tags = merge(local.common_tags, {
    Name = local.repository_name
    Type = "CodeCommit Repository"
  })
}

# ==============================================================================
# SNS Topics for Notifications
# ==============================================================================

# SNS topic for pull request notifications
resource "aws_sns_topic" "pull_requests" {
  name = "${local.resource_prefix}-pull-requests"

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-pull-requests"
    Type = "SNS Topic"
    Purpose = "Pull Request Notifications"
  })
}

# SNS topic for merge notifications
resource "aws_sns_topic" "merges" {
  name = "${local.resource_prefix}-merges"

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-merges"
    Type = "SNS Topic"
    Purpose = "Merge Notifications"
  })
}

# SNS topic for quality gate notifications
resource "aws_sns_topic" "quality_gates" {
  name = "${local.resource_prefix}-quality-gates"

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-quality-gates"
    Type = "SNS Topic"
    Purpose = "Quality Gate Notifications"
  })
}

# SNS topic for security alerts
resource "aws_sns_topic" "security_alerts" {
  name = "${local.resource_prefix}-security-alerts"

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-security-alerts"
    Type = "SNS Topic"
    Purpose = "Security Alert Notifications"
  })
}

# Optional email subscriptions for SNS topics
resource "aws_sns_topic_subscription" "pull_request_emails" {
  count     = var.enable_email_notifications ? length(var.notification_emails) : 0
  topic_arn = aws_sns_topic.pull_requests.arn
  protocol  = "email"
  endpoint  = var.notification_emails[count.index]
}

resource "aws_sns_topic_subscription" "merge_emails" {
  count     = var.enable_email_notifications ? length(var.notification_emails) : 0
  topic_arn = aws_sns_topic.merges.arn
  protocol  = "email"
  endpoint  = var.notification_emails[count.index]
}

resource "aws_sns_topic_subscription" "quality_gate_emails" {
  count     = var.enable_email_notifications ? length(var.notification_emails) : 0
  topic_arn = aws_sns_topic.quality_gates.arn
  protocol  = "email"
  endpoint  = var.notification_emails[count.index]
}

resource "aws_sns_topic_subscription" "security_alert_emails" {
  count     = var.enable_email_notifications ? length(var.notification_emails) : 0
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_emails[count.index]
}

# ==============================================================================
# IAM Role for Lambda Functions
# ==============================================================================

# Trust policy document for Lambda
data "aws_iam_policy_document" "lambda_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name               = "${local.resource_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust_policy.json

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-lambda-role"
    Type = "IAM Role"
    Purpose = "Lambda Execution Role"
  })
}

# IAM policy document for Lambda permissions
data "aws_iam_policy_document" "lambda_permissions" {
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

  # CodeCommit permissions
  statement {
    effect = "Allow"
    actions = [
      "codecommit:GetRepository",
      "codecommit:GetBranch",
      "codecommit:GetCommit",
      "codecommit:GetDifferences",
      "codecommit:GetPullRequest",
      "codecommit:ListPullRequests",
      "codecommit:GetMergeCommit",
      "codecommit:GetMergeConflicts",
      "codecommit:GetMergeOptions",
      "codecommit:PostCommentForPullRequest",
      "codecommit:UpdatePullRequestTitle",
      "codecommit:UpdatePullRequestDescription",
      "codecommit:ListBranches"
    ]
    resources = [aws_codecommit_repository.main.arn]
  }

  # SNS permissions
  statement {
    effect = "Allow"
    actions = ["sns:Publish"]
    resources = [
      aws_sns_topic.pull_requests.arn,
      aws_sns_topic.merges.arn,
      aws_sns_topic.quality_gates.arn,
      aws_sns_topic.security_alerts.arn
    ]
  }

  # CloudWatch metrics permissions
  statement {
    effect = "Allow"
    actions = ["cloudwatch:PutMetricData"]
    resources = ["*"]
  }
}

# IAM policy for Lambda functions
resource "aws_iam_policy" "lambda_policy" {
  name   = "${local.resource_prefix}-lambda-policy"
  policy = data.aws_iam_policy_document.lambda_permissions.json

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-lambda-policy"
    Type = "IAM Policy"
    Purpose = "Lambda Function Permissions"
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# ==============================================================================
# Lambda Functions
# ==============================================================================

# CloudWatch log groups for Lambda functions
resource "aws_cloudwatch_log_group" "pull_request_lambda_logs" {
  name              = "/aws/lambda/${local.resource_prefix}-pull-request"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${local.resource_prefix}-pull-request"
    Type = "CloudWatch Log Group"
    Purpose = "Pull Request Lambda Logs"
  })
}

resource "aws_cloudwatch_log_group" "quality_gate_lambda_logs" {
  name              = "/aws/lambda/${local.resource_prefix}-quality-gate"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${local.resource_prefix}-quality-gate"
    Type = "CloudWatch Log Group"
    Purpose = "Quality Gate Lambda Logs"
  })
}

resource "aws_cloudwatch_log_group" "branch_protection_lambda_logs" {
  name              = "/aws/lambda/${local.resource_prefix}-branch-protection"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "/aws/lambda/${local.resource_prefix}-branch-protection"
    Type = "CloudWatch Log Group"
    Purpose = "Branch Protection Lambda Logs"
  })
}

# Archive Lambda function code
data "archive_file" "pull_request_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/pull-request-automation.zip"
  source {
    content  = file("${path.module}/lambda_functions/pull_request_automation.py")
    filename = "lambda_function.py"
  }
}

data "archive_file" "quality_gate_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/quality-gate-automation.zip"
  source {
    content  = file("${path.module}/lambda_functions/quality_gate_automation.py")
    filename = "lambda_function.py"
  }
}

data "archive_file" "branch_protection_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/branch-protection.zip"
  source {
    content  = file("${path.module}/lambda_functions/branch_protection.py")
    filename = "lambda_function.py"
  }
}

# Pull Request automation Lambda function
resource "aws_lambda_function" "pull_request_automation" {
  filename         = data.archive_file.pull_request_lambda_zip.output_path
  function_name    = "${local.resource_prefix}-pull-request"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.pull_request_lambda_zip.output_base64sha256

  environment {
    variables = {
      PULL_REQUEST_TOPIC_ARN = aws_sns_topic.pull_requests.arn
      MERGE_TOPIC_ARN        = aws_sns_topic.merges.arn
      QUALITY_GATE_TOPIC_ARN = aws_sns_topic.quality_gates.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.pull_request_lambda_logs]

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-pull-request"
    Type = "Lambda Function"
    Purpose = "Pull Request Automation"
  })
}

# Quality Gate automation Lambda function
resource "aws_lambda_function" "quality_gate_automation" {
  filename         = data.archive_file.quality_gate_lambda_zip.output_path
  function_name    = "${local.resource_prefix}-quality-gate"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = 512  # Higher memory for quality checks
  source_code_hash = data.archive_file.quality_gate_lambda_zip.output_base64sha256

  environment {
    variables = {
      QUALITY_GATE_TOPIC_ARN   = aws_sns_topic.quality_gates.arn
      SECURITY_ALERT_TOPIC_ARN = aws_sns_topic.security_alerts.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.quality_gate_lambda_logs]

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-quality-gate"
    Type = "Lambda Function"
    Purpose = "Quality Gate Automation"
  })
}

# Branch Protection automation Lambda function
resource "aws_lambda_function" "branch_protection_automation" {
  filename         = data.archive_file.branch_protection_lambda_zip.output_path
  function_name    = "${local.resource_prefix}-branch-protection"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.branch_protection_lambda_zip.output_base64sha256

  depends_on = [aws_cloudwatch_log_group.branch_protection_lambda_logs]

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-branch-protection"
    Type = "Lambda Function"
    Purpose = "Branch Protection Automation"
  })
}

# ==============================================================================
# EventBridge Rules and Triggers
# ==============================================================================

# Lambda permission for CodeCommit to invoke quality gate function
resource "aws_lambda_permission" "codecommit_invoke_quality_gate" {
  statement_id  = "AllowExecutionFromCodeCommit"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.quality_gate_automation.function_name
  principal     = "codecommit.amazonaws.com"
  source_arn    = aws_codecommit_repository.main.arn
}

# Repository trigger for quality gates
resource "aws_codecommit_trigger" "quality_gate_trigger" {
  repository_name = aws_codecommit_repository.main.repository_name

  trigger {
    name            = "quality-gate-trigger"
    events          = ["all"]
    destination_arn = aws_lambda_function.quality_gate_automation.arn
  }

  depends_on = [aws_lambda_permission.codecommit_invoke_quality_gate]
}

# EventBridge rule for pull request events
resource "aws_cloudwatch_event_rule" "pull_request_events" {
  name        = "${local.resource_prefix}-pull-request-events"
  description = "Capture CodeCommit pull request events"

  event_pattern = jsonencode({
    source      = ["aws.codecommit"]
    detail-type = ["CodeCommit Pull Request State Change"]
    detail = {
      repositoryName = [aws_codecommit_repository.main.repository_name]
    }
  })

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-pull-request-events"
    Type = "EventBridge Rule"
    Purpose = "Pull Request Event Processing"
  })
}

# EventBridge target for pull request Lambda
resource "aws_cloudwatch_event_target" "pull_request_lambda_target" {
  rule      = aws_cloudwatch_event_rule.pull_request_events.name
  target_id = "PullRequestLambdaTarget"
  arn       = aws_lambda_function.pull_request_automation.arn
}

# Lambda permission for EventBridge to invoke pull request function
resource "aws_lambda_permission" "eventbridge_invoke_pull_request" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pull_request_automation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.pull_request_events.arn
}

# ==============================================================================
# Approval Rule Template
# ==============================================================================

# Approval rule template (only if approval pool members are provided)
resource "aws_codecommit_approval_rule_template" "enterprise_template" {
  count = length(local.approval_pool_members) > 0 ? 1 : 0

  name        = "${local.resource_prefix}-approval-template"
  description = "Standard approval rules for enterprise repositories"

  content = jsonencode({
    Version = "2018-11-08"
    DestinationReferences = [for branch in var.protected_branches : "refs/heads/${branch}"]
    Statements = [{
      Type                    = "Approvers"
      NumberOfApprovalsNeeded = var.required_approvals
      ApprovalPoolMembers     = local.approval_pool_members
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-approval-template"
    Type = "CodeCommit Approval Rule Template"
    Purpose = "Pull Request Approval Rules"
  })
}

# Associate approval rule template with repository
resource "aws_codecommit_approval_rule_template_association" "main" {
  count = length(local.approval_pool_members) > 0 ? 1 : 0

  approval_rule_template_name = aws_codecommit_approval_rule_template.enterprise_template[0].name
  repository_name            = aws_codecommit_repository.main.repository_name
}

# ==============================================================================
# CloudWatch Dashboard
# ==============================================================================

# CloudWatch dashboard for Git workflow monitoring
resource "aws_cloudwatch_dashboard" "git_workflow" {
  count          = var.enable_dashboard ? 1 : 0
  dashboard_name = "Git-Workflow-${local.repository_name}"

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
            ["CodeCommit/PullRequests", "PullRequestsCreated", "Repository", local.repository_name],
            [".", "PullRequestsMerged", ".", "."],
            [".", "PullRequestsClosed", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Pull Request Activity"
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
            ["CodeCommit/QualityGates", "QualityChecksResult", "Repository", local.repository_name]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Quality Gate Success Rate"
          yAxis = {
            left = {
              min = 0
              max = 1
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["CodeCommit/QualityGates", "QualityCheck_lint_check", "Repository", local.repository_name, "CheckType", "lint_check"],
            [".", "QualityCheck_security_scan", ".", ".", ".", "security_scan"],
            [".", "QualityCheck_test_coverage", ".", ".", ".", "test_coverage"],
            [".", "QualityCheck_dependency_check", ".", ".", ".", "dependency_check"]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Individual Quality Checks"
        }
      },
      {
        type   = "log"
        x      = 8
        y      = 6
        width  = 16
        height = 6
        properties = {
          query  = "SOURCE '${aws_cloudwatch_log_group.pull_request_lambda_logs.name}'\n| fields @timestamp, @message\n| filter @message like /Pull request/\n| sort @timestamp desc\n| limit 20"
          region = data.aws_region.current.name
          title  = "Recent Pull Request Events"
        }
      }
    ]
  })
}