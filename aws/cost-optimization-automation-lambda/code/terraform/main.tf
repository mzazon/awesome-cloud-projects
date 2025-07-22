# Data sources for current AWS account and caller identity
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Resource names with random suffix
  s3_bucket_name        = "${local.name_prefix}-reports-${random_id.suffix.hex}"
  dynamodb_table_name   = "${local.name_prefix}-tracking-${random_id.suffix.hex}"
  sns_topic_name        = "${local.name_prefix}-alerts-${random_id.suffix.hex}"
  
  # Combined tags
  common_tags = merge(var.default_tags, var.additional_tags, {
    Environment = var.environment
    Name        = local.name_prefix
  })
}

# S3 bucket for reports and Lambda deployment packages
resource "aws_s3_bucket" "cost_optimization_reports" {
  bucket        = local.s3_bucket_name
  force_destroy = var.s3_bucket_force_destroy
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-reports-bucket"
    Description = "S3 bucket for cost optimization reports and Lambda deployment packages"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "cost_optimization_reports" {
  bucket = aws_s3_bucket.cost_optimization_reports.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "cost_optimization_reports" {
  bucket = aws_s3_bucket.cost_optimization_reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "cost_optimization_reports" {
  bucket = aws_s3_bucket.cost_optimization_reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for tracking optimization actions
resource "aws_dynamodb_table" "cost_optimization_tracking" {
  name           = local.dynamodb_table_name
  billing_mode   = "PROVISIONED"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "ResourceId"
  range_key      = "CheckId"

  attribute {
    name = "ResourceId"
    type = "S"
  }

  attribute {
    name = "CheckId"
    type = "S"
  }

  # Global secondary index for querying by CheckId
  global_secondary_index {
    name            = "CheckIdIndex"
    hash_key        = "CheckId"
    read_capacity   = var.dynamodb_read_capacity
    write_capacity  = var.dynamodb_write_capacity
    projection_type = "ALL"
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-tracking-table"
    Description = "DynamoDB table for tracking cost optimization actions"
  })
}

# SNS topic for notifications
resource "aws_sns_topic" "cost_optimization_alerts" {
  name = local.sns_topic_name

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-alerts-topic"
    Description = "SNS topic for cost optimization alerts"
  })
}

# SNS topic policy
resource "aws_sns_topic_policy" "cost_optimization_alerts" {
  arn = aws_sns_topic.cost_optimization_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.cost_optimization_alerts.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Email subscription to SNS topic (if email provided)
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.cost_optimization_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Slack webhook subscription (if webhook URL provided)
resource "aws_sns_topic_subscription" "slack_alerts" {
  count     = var.slack_webhook_url != "" ? 1 : 0
  topic_arn = aws_sns_topic.cost_optimization_alerts.arn
  protocol  = "https"
  endpoint  = var.slack_webhook_url
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-role"

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
    Name        = "${local.name_prefix}-lambda-role"
    Description = "IAM role for cost optimization Lambda functions"
  })
}

# IAM policy for cost optimization Lambda functions
resource "aws_iam_policy" "lambda_cost_optimization_policy" {
  name        = "${local.name_prefix}-lambda-policy"
  description = "Policy for cost optimization Lambda functions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "support:DescribeTrustedAdvisorChecks",
          "support:DescribeTrustedAdvisorCheckResult",
          "support:RefreshTrustedAdvisorCheck"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetDimensionValues",
          "ce:GetUsageReport",
          "ce:GetReservationCoverage",
          "ce:GetReservationPurchaseRecommendation",
          "ce:GetReservationUtilization"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.cost_optimization_tracking.arn,
          "${aws_dynamodb_table.cost_optimization_tracking.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.cost_optimization_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.cost_optimization_reports.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:StopInstances",
          "ec2:TerminateInstances",
          "ec2:ModifyInstanceAttribute",
          "ec2:DescribeVolumes",
          "ec2:ModifyVolume",
          "ec2:CreateSnapshot",
          "ec2:DeleteVolume"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:ModifyDBInstance",
          "rds:StopDBInstance"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${local.name_prefix}-*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-lambda-policy"
    Description = "IAM policy for cost optimization Lambda functions"
  })
}

# Attach policy to Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_cost_optimization_policy" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_cost_optimization_policy.arn
}

# CloudWatch log groups for Lambda functions
resource "aws_cloudwatch_log_group" "cost_analysis_logs" {
  name              = "/aws/lambda/${local.name_prefix}-analysis"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-analysis-logs"
    Description = "CloudWatch log group for cost analysis Lambda function"
  })
}

resource "aws_cloudwatch_log_group" "remediation_logs" {
  name              = "/aws/lambda/${local.name_prefix}-remediation"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-remediation-logs"
    Description = "CloudWatch log group for remediation Lambda function"
  })
}

# Create Lambda deployment packages
data "archive_file" "cost_analysis_lambda" {
  type        = "zip"
  output_path = "${path.module}/cost_analysis_lambda.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/cost_analysis.py", {
      auto_remediation_checks = jsonencode(var.auto_remediation_checks)
      enable_auto_remediation = var.enable_auto_remediation
      cost_alert_threshold    = var.cost_alert_threshold
      high_savings_threshold  = var.high_savings_threshold
    })
    filename = "lambda_function.py"
  }
}

data "archive_file" "remediation_lambda" {
  type        = "zip"
  output_path = "${path.module}/remediation_lambda.zip"
  
  source {
    content  = file("${path.module}/lambda_functions/remediation.py")
    filename = "lambda_function.py"
  }
}

# Cost Analysis Lambda function
resource "aws_lambda_function" "cost_optimization_analysis" {
  filename         = data.archive_file.cost_analysis_lambda.output_path
  function_name    = "${local.name_prefix}-analysis"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.cost_analysis_lambda.output_base64sha256

  environment {
    variables = {
      COST_OPT_TABLE             = aws_dynamodb_table.cost_optimization_tracking.name
      REMEDIATION_FUNCTION_NAME  = "${local.name_prefix}-remediation"
      SNS_TOPIC_ARN             = aws_sns_topic.cost_optimization_alerts.arn
      S3_BUCKET_NAME            = aws_s3_bucket.cost_optimization_reports.bucket
      ENABLE_AUTO_REMEDIATION   = var.enable_auto_remediation
      COST_ALERT_THRESHOLD      = var.cost_alert_threshold
      HIGH_SAVINGS_THRESHOLD    = var.high_savings_threshold
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.cost_analysis_logs,
    aws_iam_role_policy_attachment.lambda_cost_optimization_policy
  ]

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-analysis-function"
    Description = "Lambda function for cost optimization analysis"
  })
}

# Remediation Lambda function
resource "aws_lambda_function" "cost_optimization_remediation" {
  filename         = data.archive_file.remediation_lambda.output_path
  function_name    = "${local.name_prefix}-remediation"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.remediation_lambda.output_base64sha256

  environment {
    variables = {
      COST_OPT_TABLE    = aws_dynamodb_table.cost_optimization_tracking.name
      SNS_TOPIC_ARN     = aws_sns_topic.cost_optimization_alerts.arn
      S3_BUCKET_NAME    = aws_s3_bucket.cost_optimization_reports.bucket
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.remediation_logs,
    aws_iam_role_policy_attachment.lambda_cost_optimization_policy
  ]

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-remediation-function"
    Description = "Lambda function for cost optimization remediation"
  })
}

# IAM role for EventBridge Scheduler
resource "aws_iam_role" "scheduler_execution_role" {
  name = "${local.name_prefix}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-scheduler-role"
    Description = "IAM role for EventBridge Scheduler"
  })
}

# IAM policy for EventBridge Scheduler
resource "aws_iam_policy" "scheduler_policy" {
  name        = "${local.name_prefix}-scheduler-policy"
  description = "Policy for EventBridge Scheduler to invoke Lambda functions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.cost_optimization_analysis.arn,
          aws_lambda_function.cost_optimization_remediation.arn
        ]
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-scheduler-policy"
    Description = "IAM policy for EventBridge Scheduler"
  })
}

# Attach policy to scheduler role
resource "aws_iam_role_policy_attachment" "scheduler_policy" {
  role       = aws_iam_role.scheduler_execution_role.name
  policy_arn = aws_iam_policy.scheduler_policy.arn
}

# EventBridge Schedule Group
resource "aws_scheduler_schedule_group" "cost_optimization" {
  name = "${local.name_prefix}-schedules"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-schedule-group"
    Description = "EventBridge schedule group for cost optimization"
  })
}

# Daily cost analysis schedule
resource "aws_scheduler_schedule" "daily_analysis" {
  name       = "${local.name_prefix}-daily-analysis"
  group_name = aws_scheduler_schedule_group.cost_optimization.name

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = var.analysis_schedule_expression

  target {
    arn      = aws_lambda_function.cost_optimization_analysis.arn
    role_arn = aws_iam_role.scheduler_execution_role.arn

    input = jsonencode({
      scheduled_analysis = true
      analysis_type     = "daily"
    })
  }
}

# Weekly comprehensive analysis schedule
resource "aws_scheduler_schedule" "weekly_analysis" {
  name       = "${local.name_prefix}-weekly-analysis"
  group_name = aws_scheduler_schedule_group.cost_optimization.name

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = var.comprehensive_analysis_schedule_expression

  target {
    arn      = aws_lambda_function.cost_optimization_analysis.arn
    role_arn = aws_iam_role.scheduler_execution_role.arn

    input = jsonencode({
      scheduled_analysis      = true
      analysis_type          = "comprehensive"
      comprehensive_analysis = true
    })
  }
}

# CloudWatch Dashboard for monitoring
resource "aws_cloudwatch_dashboard" "cost_optimization" {
  dashboard_name = "${local.name_prefix}-dashboard"

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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.cost_optimization_analysis.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.cost_optimization_analysis.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.cost_optimization_analysis.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.cost_optimization_remediation.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.cost_optimization_remediation.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.cost_optimization_remediation.function_name]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Cost Optimization Lambda Metrics"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          query = "SOURCE '${aws_cloudwatch_log_group.cost_analysis_logs.name}'\n| fields @timestamp, @message\n| filter @message like /optimization/\n| sort @timestamp desc\n| limit 100"
          region = data.aws_region.current.name
          title  = "Cost Optimization Analysis Logs"
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
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.cost_optimization_tracking.name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", aws_dynamodb_table.cost_optimization_tracking.name],
            ["AWS/SNS", "NumberOfMessagesPublished", "TopicName", aws_sns_topic.cost_optimization_alerts.name]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Storage and Notification Metrics"
        }
      }
    ]
  })
}

# Lambda permission for EventBridge Scheduler
resource "aws_lambda_permission" "allow_scheduler_analysis" {
  statement_id  = "AllowExecutionFromScheduler"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_optimization_analysis.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.daily_analysis.arn
}

resource "aws_lambda_permission" "allow_scheduler_comprehensive" {
  statement_id  = "AllowExecutionFromSchedulerComprehensive"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_optimization_analysis.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.weekly_analysis.arn
}