# Intelligent Web Scraping with AgentCore Browser and Code Interpreter
# This Terraform configuration deploys a complete intelligent web scraping solution
# using AWS Bedrock AgentCore, Lambda, S3, and CloudWatch services

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  project_name = "intelligent-scraper-${random_string.suffix.result}"
  
  common_tags = {
    Project     = "IntelligentWebScraping"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "intelligent-web-scraping-browser-codeinterpreter"
  }
}

#==============================================================================
# S3 BUCKETS FOR INPUT CONFIGURATIONS AND OUTPUT DATA
#==============================================================================

# S3 bucket for storing scraping configurations and input data
resource "aws_s3_bucket" "input_bucket" {
  bucket = "${local.project_name}-input"
  tags   = local.common_tags
}

# S3 bucket for storing processed results and scraped data
resource "aws_s3_bucket" "output_bucket" {
  bucket = "${local.project_name}-output"
  tags   = local.common_tags
}

# Enable versioning on input bucket for configuration management
resource "aws_s3_bucket_versioning" "input_bucket_versioning" {
  bucket = aws_s3_bucket.input_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable versioning on output bucket for data retention
resource "aws_s3_bucket_versioning" "output_bucket_versioning" {
  bucket = aws_s3_bucket.output_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption for input bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "input_bucket_encryption" {
  bucket = aws_s3_bucket.input_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Server-side encryption for output bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "output_bucket_encryption" {
  bucket = aws_s3_bucket.output_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access for input bucket
resource "aws_s3_bucket_public_access_block" "input_bucket_pab" {
  bucket = aws_s3_bucket.input_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Block public access for output bucket
resource "aws_s3_bucket_public_access_block" "output_bucket_pab" {
  bucket = aws_s3_bucket.output_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload initial scraping configuration
resource "aws_s3_object" "scraper_config" {
  bucket = aws_s3_bucket.input_bucket.id
  key    = "scraper-config.json"
  content = jsonencode({
    scraping_scenarios = [
      {
        name        = "ecommerce_demo"
        description = "Extract product information from demo sites"
        target_url  = "https://books.toscrape.com/"
        extraction_rules = {
          product_titles = {
            selector  = "h3 a"
            attribute = "title"
            wait_for  = "h3 a"
          }
          prices = {
            selector  = ".price_color"
            attribute = "textContent"
            wait_for  = ".price_color"
          }
          availability = {
            selector  = ".availability"
            attribute = "textContent"
            wait_for  = ".availability"
          }
        }
        session_config = {
          timeout_seconds = 30
          view_port = {
            width  = 1920
            height = 1080
          }
        }
      }
    ]
  })
  content_type = "application/json"
  tags         = local.common_tags
}

# Upload data processing configuration
resource "aws_s3_object" "data_processing_config" {
  bucket = aws_s3_bucket.input_bucket.id
  key    = "data-processing-config.json"
  content = jsonencode({
    processing_rules = {
      price_cleaning = {
        remove_currency_symbols = true
        normalize_decimal_places = 2
        convert_to_numeric      = true
      }
      text_analysis = {
        extract_keywords    = true
        sentiment_analysis  = false
        language_detection  = false
      }
      data_validation = {
        required_fields             = ["product_titles", "prices"]
        min_data_points            = 1
        max_processing_time_seconds = 60
      }
      output_format = {
        include_raw_data       = true
        include_statistics     = true
        include_quality_metrics = true
      }
    }
    analysis_templates = {
      ecommerce = {
        metrics = ["price_distribution", "availability_rate", "product_count"]
        alerts = {
          low_availability        = 0.5
          price_variance_threshold = 0.3
        }
      }
    }
  })
  content_type = "application/json"
  tags         = local.common_tags
}

#==============================================================================
# IAM ROLE AND POLICIES FOR LAMBDA FUNCTION
#==============================================================================

# IAM role for Lambda function to interact with AWS services
resource "aws_iam_role" "lambda_role" {
  name = "${local.project_name}-lambda-role"

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

# IAM policy for Lambda function permissions
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.project_name}-lambda-policy"
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
          "bedrock-agentcore:StartBrowserSession",
          "bedrock-agentcore:StopBrowserSession",
          "bedrock-agentcore:GetBrowserSession",
          "bedrock-agentcore:UpdateBrowserStream",
          "bedrock-agentcore:StartCodeInterpreterSession",
          "bedrock-agentcore:StopCodeInterpreterSession",
          "bedrock-agentcore:GetCodeInterpreterSession"
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
          aws_s3_bucket.input_bucket.arn,
          "${aws_s3_bucket.input_bucket.arn}/*",
          aws_s3_bucket.output_bucket.arn,
          "${aws_s3_bucket.output_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

#==============================================================================
# SQS DEAD LETTER QUEUE FOR ERROR HANDLING
#==============================================================================

# SQS Dead Letter Queue for failed Lambda executions
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.project_name}-dlq"
  visibility_timeout_seconds = 300
  message_retention_seconds = 1209600 # 14 days
  
  tags = local.common_tags
}

#==============================================================================
# LAMBDA FUNCTION FOR WORKFLOW ORCHESTRATION
#==============================================================================

# Archive Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "lambda_function.zip"
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      s3_bucket_input  = aws_s3_bucket.input_bucket.id
      s3_bucket_output = aws_s3_bucket.output_bucket.id
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for intelligent scraping orchestration
resource "aws_lambda_function" "scraper_orchestrator" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.project_name}-orchestrator"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.11"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      S3_BUCKET_INPUT   = aws_s3_bucket.input_bucket.id
      S3_BUCKET_OUTPUT  = aws_s3_bucket.output_bucket.id
      ENVIRONMENT       = var.environment
      LOG_LEVEL         = var.log_level
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = local.common_tags
}

#==============================================================================
# CLOUDWATCH LOGGING AND MONITORING
#==============================================================================

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.project_name}-orchestrator"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# CloudWatch dashboard for monitoring scraping activities
resource "aws_cloudwatch_dashboard" "scraping_dashboard" {
  dashboard_name = "${local.project_name}-monitoring"

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
            ["IntelligentScraper/${aws_lambda_function.scraper_orchestrator.function_name}", "ScrapingJobs"],
            [".", "DataPointsExtracted"]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Scraping Activity"
          yAxis = {
            left = {
              min = 0
            }
          }
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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.scraper_orchestrator.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Lambda Performance"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          query  = "SOURCE '${aws_cloudwatch_log_group.lambda_logs.name}'\n| fields @timestamp, @message\n| filter @message like /ERROR/\n| sort @timestamp desc\n| limit 20"
          region = var.aws_region
          title  = "Recent Errors"
          view   = "table"
        }
      }
    ]
  })
}

#==============================================================================
# EVENTBRIDGE SCHEDULING FOR AUTOMATED SCRAPING
#==============================================================================

# EventBridge rule for scheduled scraping
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${local.project_name}-schedule"
  description         = "Scheduled intelligent web scraping"
  schedule_expression = var.scraping_schedule
  state               = var.enable_scheduling ? "ENABLED" : "DISABLED"
  tags                = local.common_tags
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "${local.project_name}-eventbridge-permission"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scraper_orchestrator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}

# EventBridge target to invoke Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "LambdaTarget"
  arn       = aws_lambda_function.scraper_orchestrator.arn

  input = jsonencode({
    bucket_input       = aws_s3_bucket.input_bucket.id
    bucket_output      = aws_s3_bucket.output_bucket.id
    scheduled_execution = true
  })
}

#==============================================================================
# CLOUDWATCH ALARMS FOR MONITORING AND ALERTING
#==============================================================================

# CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = var.enable_alerts ? 1 : 0
  alarm_name          = "${local.project_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.scraper_orchestrator.function_name
  }

  tags = local.common_tags
}

# CloudWatch alarm for Lambda duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  count               = var.enable_alerts ? 1 : 0
  alarm_name          = "${local.project_name}-lambda-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = var.lambda_timeout * 1000 * 0.8 # 80% of timeout
  alarm_description   = "This metric monitors lambda duration"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.scraper_orchestrator.function_name
  }

  tags = local.common_tags
}