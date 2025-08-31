# VPC Lattice Cost Analytics Platform - Main Infrastructure
# This file contains the core infrastructure components for service mesh cost analytics

# Local values for resource naming and configuration
locals {
  resource_prefix = "${var.project_name}-${random_string.suffix.result}"
  
  # Merge common tags with additional tags
  tags = merge(var.common_tags, var.additional_tags, {
    Project      = var.project_name
    Environment  = var.environment
    CostCenter   = var.cost_center
    Owner        = var.owner
    DeployedDate = timestamp()
  })
}

# S3 Bucket for Cost Analytics Data Storage
resource "aws_s3_bucket" "analytics_bucket" {
  bucket = "${local.resource_prefix}-analytics"
  
  tags = merge(local.tags, {
    Purpose = "VPC Lattice cost analytics data storage"
  })
}

# S3 Bucket Versioning Configuration
resource "aws_s3_bucket_versioning" "analytics_bucket_versioning" {
  count  = var.s3_versioning_enabled ? 1 : 0
  bucket = aws_s3_bucket.analytics_bucket.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "analytics_bucket_encryption" {
  count  = var.s3_encryption_enabled ? 1 : 0
  bucket = aws_s3_bucket.analytics_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket Public Access Block (Security Best Practice)
resource "aws_s3_bucket_public_access_block" "analytics_bucket_pab" {
  bucket = aws_s3_bucket.analytics_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Objects for folder structure organization
resource "aws_s3_object" "cost_reports_folder" {
  bucket = aws_s3_bucket.analytics_bucket.id
  key    = "cost-reports/"
  source = "/dev/null"
  
  tags = merge(local.tags, {
    Purpose = "Cost reports folder structure"
  })
}

resource "aws_s3_object" "metrics_data_folder" {
  bucket = aws_s3_bucket.analytics_bucket.id
  key    = "metrics-data/"
  source = "/dev/null"
  
  tags = merge(local.tags, {
    Purpose = "Metrics data folder structure"
  })
}

# IAM Role for Lambda Function
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.resource_prefix}-lambda-role"
  
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
  
  tags = merge(local.tags, {
    Purpose = "Lambda execution role for cost analytics"
  })
}

# IAM Policy for Cost Analytics Permissions
resource "aws_iam_policy" "cost_analytics_policy" {
  name        = "${local.resource_prefix}-cost-analytics-policy"
  description = "Permissions for VPC Lattice cost analytics Lambda function"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetUsageReport",
          "ce:ListCostCategoryDefinitions",
          "ce:GetCostCategories",
          "ce:GetRecommendations"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData",
          "cloudwatch:ListMetrics",
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "vpc-lattice:GetService",
          "vpc-lattice:GetServiceNetwork",
          "vpc-lattice:ListServices",
          "vpc-lattice:ListServiceNetworks"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.analytics_bucket.arn}/*"
      }
    ]
  })
  
  tags = local.tags
}

# Attach Custom Policy to Lambda Role
resource "aws_iam_role_policy_attachment" "lambda_cost_analytics_policy" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.cost_analytics_policy.arn
}

# Attach AWS Managed Policy for Basic Lambda Execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Function Source Code Archive
data "archive_file" "lambda_function_archive" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      bucket_name = aws_s3_bucket.analytics_bucket.id
    })
    filename = "lambda_function.py"
  }
}

# Lambda Function for Cost Analytics Processing
resource "aws_lambda_function" "cost_processor" {
  function_name = "${local.resource_prefix}-cost-processor"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size
  
  filename         = data.archive_file.lambda_function_archive.output_path
  source_code_hash = data.archive_file.lambda_function_archive.output_base64sha256
  
  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.analytics_bucket.id
    }
  }
  
  description = "VPC Lattice cost analytics processor"
  
  tags = merge(local.tags, {
    Purpose = "Cost analytics processing"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_cost_analytics_policy,
    aws_iam_role_policy_attachment.lambda_basic_execution
  ]
}

# EventBridge Rule for Scheduled Cost Analysis
resource "aws_cloudwatch_event_rule" "cost_analysis_schedule" {
  name                = "${local.resource_prefix}-cost-analysis"
  description         = "Trigger for daily VPC Lattice cost analysis"
  schedule_expression = var.cost_analysis_schedule
  state               = "ENABLED"
  
  tags = merge(local.tags, {
    Purpose = "Automated cost analysis scheduling"
  })
}

# EventBridge Target for Lambda Function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.cost_analysis_schedule.name
  target_id = "CostAnalyticsLambdaTarget"
  arn       = aws_lambda_function.cost_processor.arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_analysis_schedule.arn
}

# Demo VPC Lattice Service Network (Optional)
resource "aws_vpclattice_service_network" "demo_network" {
  count = var.enable_demo_vpc_lattice ? 1 : 0
  
  name      = "${local.resource_prefix}-demo-network"
  auth_type = "AWS_IAM"
  
  tags = merge(local.tags, {
    Purpose     = "Demo service network for cost analytics testing"
    ServiceType = "demo"
  })
}

# Demo VPC Lattice Service (Optional)
resource "aws_vpclattice_service" "demo_service" {
  count = var.enable_demo_vpc_lattice ? 1 : 0
  
  name      = "${local.resource_prefix}-demo-service"
  auth_type = "AWS_IAM"
  
  tags = merge(local.tags, {
    Purpose     = "Demo service for cost analytics testing"
    ServiceType = "demo"
  })
}

# Service Network to Service Association (Optional)
resource "aws_vpclattice_service_network_service_association" "demo_association" {
  count = var.enable_demo_vpc_lattice ? 1 : 0
  
  service_identifier         = aws_vpclattice_service.demo_service[0].id
  service_network_identifier = aws_vpclattice_service_network.demo_network[0].id
  
  tags = merge(local.tags, {
    Purpose = "Demo service network association"
  })
}

# CloudWatch Dashboard for Cost Visualization (Optional)
resource "aws_cloudwatch_dashboard" "cost_analytics_dashboard" {
  count = var.enable_cloudwatch_dashboard ? 1 : 0
  
  dashboard_name = "${local.resource_prefix}-cost-analytics"
  
  dashboard_body = templatefile("${path.module}/dashboard.json.tpl", {
    aws_region           = data.aws_region.current.name
    service_network_id   = var.enable_demo_vpc_lattice ? aws_vpclattice_service_network.demo_network[0].id : "placeholder"
    enable_demo_lattice  = var.enable_demo_vpc_lattice
  })
}

# CloudWatch Log Group for Lambda Function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.cost_processor.function_name}"
  retention_in_days = 14
  
  tags = merge(local.tags, {
    Purpose = "Lambda function logs for cost analytics"
  })
}