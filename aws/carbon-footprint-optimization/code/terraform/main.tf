# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  project_id        = "${var.project_name}-${random_id.suffix.hex}"
  s3_bucket_name    = "${local.project_id}-data"
  lambda_function_name = "${local.project_id}-analyzer"
  dynamodb_table_name = "${local.project_id}-metrics"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Purpose     = "CarbonFootprintOptimization"
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# S3 Bucket for data storage and Cost and Usage Reports
resource "aws_s3_bucket" "carbon_data" {
  bucket        = local.s3_bucket_name
  force_destroy = var.s3_force_destroy

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "carbon_data" {
  bucket = aws_s3_bucket.carbon_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "carbon_data" {
  bucket = aws_s3_bucket.carbon_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "carbon_data" {
  bucket = aws_s3_bucket.carbon_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "carbon_data" {
  bucket = aws_s3_bucket.carbon_data.id

  rule {
    id     = "transition_to_ia"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }
  }
}

# DynamoDB table for storing carbon footprint metrics
resource "aws_dynamodb_table" "carbon_metrics" {
  name           = local.dynamodb_table_name
  billing_mode   = "PROVISIONED"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "MetricType"
  range_key      = "Timestamp"

  attribute {
    name = "MetricType"
    type = "S"
  }

  attribute {
    name = "Timestamp"
    type = "S"
  }

  attribute {
    name = "ServiceName"
    type = "S"
  }

  attribute {
    name = "CarbonIntensity"
    type = "N"
  }

  # Global Secondary Index for service-based queries
  global_secondary_index {
    name            = "ServiceCarbonIndex"
    hash_key        = "ServiceName"
    range_key       = "CarbonIntensity"
    read_capacity   = 3
    write_capacity  = 3
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = local.common_tags
}

# SNS Topic for notifications
resource "aws_sns_topic" "carbon_notifications" {
  name = "${local.project_id}-notifications"

  tags = local.common_tags
}

# SNS Topic subscription (if email is provided)
resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.carbon_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${local.project_id}-lambda-role"

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

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "CarbonOptimizationPolicy"
  role = aws_iam_role.lambda_role.id

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
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetDimensions",
          "ce:GetUsageReport",
          "ce:ListCostCategoryDefinitions",
          "cur:DescribeReportDefinitions"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.carbon_data.arn,
          "${aws_s3_bucket.carbon_data.arn}/*"
        ]
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
          aws_dynamodb_table.carbon_metrics.arn,
          "${aws_dynamodb_table.carbon_metrics.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.carbon_notifications.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter",
          "ssm:GetParameters"
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${local.project_id}/*"
      }
    ]
  })
}

# Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_code/index.py", {
      carbon_optimization_threshold = var.carbon_optimization_threshold
      high_impact_cost_threshold    = var.high_impact_cost_threshold
    })
    filename = "index.py"
  }

  source {
    content  = file("${path.module}/lambda_code/cur_processor.py")
    filename = "cur_processor.py"
  }
}

# Lambda function
resource "aws_lambda_function" "carbon_analyzer" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.carbon_metrics.name
      S3_BUCKET      = aws_s3_bucket.carbon_data.bucket
      SNS_TOPIC_ARN  = aws_sns_topic.carbon_notifications.arn
      PROJECT_NAME   = var.project_name
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 14

  tags = local.common_tags
}

# IAM role for EventBridge Scheduler
resource "aws_iam_role" "scheduler_role" {
  name = "${local.project_id}-scheduler-role"

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

  tags = local.common_tags
}

resource "aws_iam_role_policy" "scheduler_policy" {
  name = "SchedulerLambdaInvokePolicy"
  role = aws_iam_role.scheduler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.carbon_analyzer.arn
      }
    ]
  })
}

# EventBridge Scheduler for monthly analysis
resource "aws_scheduler_schedule" "monthly_analysis" {
  name       = "${local.project_id}-monthly-analysis"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = var.monthly_analysis_schedule
  description         = "Monthly carbon footprint optimization analysis"

  target {
    arn      = aws_lambda_function.carbon_analyzer.arn
    role_arn = aws_iam_role.scheduler_role.arn

    input = jsonencode({
      analysis_type = "monthly"
      detailed      = true
    })
  }
}

# EventBridge Scheduler for weekly trend analysis
resource "aws_scheduler_schedule" "weekly_trends" {
  name       = "${local.project_id}-weekly-trends"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = var.weekly_analysis_schedule
  description         = "Weekly carbon footprint trend monitoring"

  target {
    arn      = aws_lambda_function.carbon_analyzer.arn
    role_arn = aws_iam_role.scheduler_role.arn

    input = jsonencode({
      analysis_type = "weekly"
      detailed      = false
    })
  }
}

# Cost and Usage Report (if enabled)
resource "aws_cur_report_definition" "carbon_optimization" {
  count                        = var.enable_cur_integration ? 1 : 0
  report_name                  = var.cur_report_name
  time_unit                    = "DAILY"
  format                       = "Parquet"
  compression                  = "GZIP"
  additional_schema_elements   = ["RESOURCES", "SPLIT_COST_ALLOCATION_DATA"]
  s3_bucket                   = aws_s3_bucket.carbon_data.bucket
  s3_prefix                   = "cost-usage-reports/"
  s3_region                   = data.aws_region.current.name
  additional_artifacts        = ["ATHENA"]
  refresh_closed_reports      = true
  report_versioning           = "OVERWRITE_REPORT"

  tags = local.common_tags
}

# Systems Manager parameters for Sustainability Scanner configuration
resource "aws_ssm_parameter" "scanner_config" {
  count = var.enable_sustainability_scanner ? 1 : 0
  name  = "/${local.project_id}/scanner-config"
  type  = "String"
  value = jsonencode({
    rules = [
      "ec2-instance-types",
      "storage-optimization", 
      "graviton-processors",
      "regional-efficiency"
    ]
    severity = var.scanner_severity_threshold
    auto_fix = false
  })
  description = "Sustainability Scanner configuration for carbon footprint optimization"

  tags = local.common_tags
}

# S3 object for sustainable infrastructure template
resource "aws_s3_object" "sustainable_template" {
  bucket = aws_s3_bucket.carbon_data.bucket
  key    = "templates/sustainable-infrastructure-template.yaml"
  
  content = templatefile("${path.module}/templates/sustainable-infrastructure-template.yaml", {
    project_name = var.project_name
    environment  = var.environment
  })

  content_type = "application/x-yaml"

  tags = local.common_tags
}

# CloudWatch Dashboard for carbon footprint monitoring
resource "aws_cloudwatch_dashboard" "carbon_footprint" {
  dashboard_name = "${local.project_id}-carbon-footprint"

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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.carbon_analyzer.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.carbon_analyzer.function_name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.carbon_analyzer.function_name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Carbon Analysis Lambda Metrics"
          period  = 300
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
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.carbon_metrics.name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", aws_dynamodb_table.carbon_metrics.name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "DynamoDB Capacity Utilization"
          period  = 300
        }
      }
    ]
  })
}

# CloudWatch alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.project_id}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors lambda errors for carbon footprint analyzer"
  alarm_actions       = [aws_sns_topic.carbon_notifications.arn]

  dimensions = {
    FunctionName = aws_lambda_function.carbon_analyzer.function_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  alarm_name          = "${local.project_id}-dynamodb-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ThrottledRequests"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors DynamoDB throttling for carbon metrics table"
  alarm_actions       = [aws_sns_topic.carbon_notifications.arn]

  dimensions = {
    TableName = aws_dynamodb_table.carbon_metrics.name
  }

  tags = local.common_tags
}