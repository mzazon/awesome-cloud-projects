# Main Terraform Configuration for CodeGuru Automation
# This file creates the complete infrastructure for automated code review with CodeGuru

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique names with random suffix
  repo_name           = var.repository_name != "" ? var.repository_name : "${var.project_name}-${random_id.suffix.hex}"
  profiler_group_name = var.profiler_group_name != "" ? var.profiler_group_name : "${var.project_name}-profiler-${random_id.suffix.hex}"
  iam_role_name       = var.iam_role_name != "" ? var.iam_role_name : "CodeGuruRole-${random_id.suffix.hex}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "code-review-automation-codeguru"
  })
}

# IAM Role for CodeGuru Services
resource "aws_iam_role" "codeguru_role" {
  name = local.iam_role_name
  description = "IAM role for CodeGuru Reviewer and Profiler services"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "codeguru-reviewer.amazonaws.com",
            "codeguru-profiler.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# IAM Policy Attachment for CodeGuru Reviewer
resource "aws_iam_role_policy_attachment" "codeguru_reviewer_policy" {
  count      = var.enable_codeguru_reviewer ? 1 : 0
  role       = aws_iam_role.codeguru_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonCodeGuruReviewerServiceRolePolicy"
}

# IAM Policy Attachment for CodeGuru Profiler
resource "aws_iam_role_policy_attachment" "codeguru_profiler_policy" {
  count      = var.enable_codeguru_profiler ? 1 : 0
  role       = aws_iam_role.codeguru_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonCodeGuruProfilerAgentAccess"
}

# Additional IAM policy for enhanced CodeGuru permissions
resource "aws_iam_role_policy" "codeguru_enhanced_policy" {
  name = "${local.iam_role_name}-enhanced-policy"
  role = aws_iam_role.codeguru_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codecommit:GetRepository",
          "codecommit:DescribeRepositories",
          "codecommit:GetBranch",
          "codecommit:GetCommit",
          "codecommit:GetDifferences",
          "codecommit:ListBranches",
          "codecommit:ListRepositories"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::codeguru-reviewer-*",
          "arn:aws:s3:::codeguru-reviewer-*/*",
          "arn:aws:s3:::codeguru-profiler-*",
          "arn:aws:s3:::codeguru-profiler-*/*"
        ]
      }
    ]
  })
}

# CodeCommit Repository
resource "aws_codecommit_repository" "main" {
  repository_name   = local.repo_name
  repository_description = var.repository_description

  tags = merge(local.common_tags, {
    Name = local.repo_name
    Type = "SourceRepository"
  })
}

# CodeGuru Reviewer Association
resource "aws_codegurureviewer_association_repository" "main" {
  count = var.enable_codeguru_reviewer ? 1 : 0
  
  repository {
    codecommit {
      name = aws_codecommit_repository.main.repository_name
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.repo_name}-association"
    Type = "CodeGuruAssociation"
  })
}

# CodeGuru Profiler Group
resource "aws_codeguruprofiler_profiling_group" "main" {
  count = var.enable_codeguru_profiler ? 1 : 0
  
  name            = local.profiler_group_name
  compute_platform = var.profiler_compute_platform

  agent_permissions {
    principals = [
      aws_iam_role.codeguru_role.arn
    ]
  }

  tags = merge(local.common_tags, {
    Name = local.profiler_group_name
    Type = "ProfilerGroup"
  })
}

# S3 Bucket for CodeGuru artifacts (optional)
resource "aws_s3_bucket" "codeguru_artifacts" {
  count  = var.custom_detector_s3_bucket != "" ? 1 : 0
  bucket = var.custom_detector_s3_bucket

  tags = merge(local.common_tags, {
    Name = var.custom_detector_s3_bucket
    Type = "ArtifactStorage"
  })
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "codeguru_artifacts" {
  count  = var.custom_detector_s3_bucket != "" ? 1 : 0
  bucket = aws_s3_bucket.codeguru_artifacts[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "codeguru_artifacts" {
  count  = var.custom_detector_s3_bucket != "" ? 1 : 0
  bucket = aws_s3_bucket.codeguru_artifacts[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "codeguru_artifacts" {
  count  = var.custom_detector_s3_bucket != "" ? 1 : 0
  bucket = aws_s3_bucket.codeguru_artifacts[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# EventBridge Rule for CodeGuru Events (optional)
resource "aws_cloudwatch_event_rule" "codeguru_events" {
  count       = var.enable_eventbridge_integration ? 1 : 0
  name        = "${var.project_name}-codeguru-events"
  description = "Capture CodeGuru Reviewer and Profiler events"

  event_pattern = jsonencode({
    source      = ["aws.codeguru-reviewer", "aws.codeguru-profiler"]
    detail-type = [
      "CodeGuru Reviewer Association State Change",
      "CodeGuru Reviewer Code Review State Change",
      "CodeGuru Profiler Profiling Group State Change"
    ]
  })

  tags = local.common_tags
}

# SNS Topic for notifications (optional)
resource "aws_sns_topic" "codeguru_notifications" {
  count = var.notification_email != "" ? 1 : 0
  name  = "${var.project_name}-codeguru-notifications"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-notifications"
    Type = "NotificationTopic"
  })
}

# SNS Topic Subscription
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.codeguru_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# EventBridge Target for SNS (optional)
resource "aws_cloudwatch_event_target" "sns_target" {
  count     = var.enable_eventbridge_integration && var.notification_email != "" ? 1 : 0
  rule      = aws_cloudwatch_event_rule.codeguru_events[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.codeguru_notifications[0].arn
}

# IAM policy for EventBridge to publish to SNS
resource "aws_sns_topic_policy" "codeguru_notifications_policy" {
  count = var.enable_eventbridge_integration && var.notification_email != "" ? 1 : 0
  arn   = aws_sns_topic.codeguru_notifications[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.codeguru_notifications[0].arn
      }
    ]
  })
}

# Lambda function for quality gate automation (optional)
resource "aws_lambda_function" "quality_gate" {
  count = var.enable_code_quality_gates ? 1 : 0
  
  filename         = data.archive_file.lambda_zip[0].output_path
  function_name    = "${var.project_name}-quality-gate"
  role            = aws_iam_role.lambda_execution_role[0].arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 300
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256

  environment {
    variables = {
      MAX_SEVERITY_THRESHOLD = var.max_severity_threshold
      PROFILER_GROUP_NAME    = var.enable_codeguru_profiler ? aws_codeguruprofiler_profiling_group.main[0].name : ""
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-quality-gate"
    Type = "QualityGateFunction"
  })

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    data.archive_file.lambda_zip
  ]
}

# IAM role for Lambda execution (only if quality gates enabled)
resource "aws_iam_role" "lambda_execution_role" {
  count = var.enable_code_quality_gates ? 1 : 0
  name  = "${var.project_name}-lambda-execution-role"

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

# IAM policy for Lambda to access CodeGuru
resource "aws_iam_role_policy" "lambda_codeguru_policy" {
  count = var.enable_code_quality_gates ? 1 : 0
  name  = "${var.project_name}-lambda-codeguru-policy"
  role  = aws_iam_role.lambda_execution_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codeguru-reviewer:DescribeCodeReview",
          "codeguru-reviewer:ListRecommendations",
          "codeguru-reviewer:PutRecommendationFeedback",
          "codeguru-profiler:DescribeProfilingGroup",
          "codeguru-profiler:ListProfileTimes",
          "codeguru-profiler:GetProfile"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count             = var.enable_code_quality_gates ? 1 : 0
  name              = "/aws/lambda/${var.project_name}-quality-gate"
  retention_in_days = 14

  tags = local.common_tags
}

# Create a zip file for Lambda function placeholder
data "archive_file" "lambda_zip" {
  count       = var.enable_code_quality_gates ? 1 : 0
  type        = "zip"
  output_path = "quality_gate.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      max_severity_threshold = var.max_severity_threshold
    })
    filename = "index.py"
  }
}

# CloudWatch Dashboard for CodeGuru Metrics
resource "aws_cloudwatch_dashboard" "codeguru_dashboard" {
  dashboard_name = "${var.project_name}-codeguru-dashboard"

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
            ["AWS/CodeGuru-Reviewer", "RepositoryAssociations", "AssociationState", "Associated"],
            ["AWS/CodeGuru-Reviewer", "CodeReviews", "State", "Completed"],
            ["AWS/CodeGuru-Profiler", "ProfilingGroups", "ProfilingGroupName", var.enable_codeguru_profiler ? aws_codeguruprofiler_profiling_group.main[0].name : ""]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "CodeGuru Service Metrics"
        }
      }
    ]
  })

  tags = local.common_tags
}