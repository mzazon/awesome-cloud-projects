# =============================================================================
# JSON to CSV Converter with Lambda and S3 - Main Infrastructure
# =============================================================================
# This Terraform configuration creates a serverless JSON-to-CSV conversion
# pipeline using AWS Lambda and S3. When JSON files are uploaded to the input
# bucket, Lambda automatically processes and converts them to CSV format.
#
# Architecture Components:
# - Input S3 bucket for JSON files with versioning enabled
# - Output S3 bucket for CSV files with versioning enabled  
# - Lambda function with JSON-to-CSV conversion logic
# - IAM role with least privilege permissions for Lambda execution
# - S3 event notification to trigger Lambda on JSON file uploads
# - CloudWatch log group for Lambda function logging
# =============================================================================

# Get current AWS account ID and region for resource naming and ARNs
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# =============================================================================
# S3 BUCKETS
# =============================================================================

# Input S3 bucket for JSON files
# This bucket receives JSON files that need to be converted to CSV format
resource "aws_s3_bucket" "input" {
  bucket = "${var.input_bucket_prefix}-${random_id.suffix.hex}"

  tags = merge(var.common_tags, {
    Name        = "JSON Input Bucket"
    Purpose     = "Store incoming JSON files for conversion"
    DataFlow    = "input"
  })
}

# Enable versioning on input bucket for data protection
resource "aws_s3_bucket_versioning" "input" {
  bucket = aws_s3_bucket.input.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure server-side encryption for input bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "input" {
  bucket = aws_s3_bucket.input.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access to input bucket for security
resource "aws_s3_bucket_public_access_block" "input" {
  bucket = aws_s3_bucket.input.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Output S3 bucket for CSV files
# This bucket stores the converted CSV files
resource "aws_s3_bucket" "output" {
  bucket = "${var.output_bucket_prefix}-${random_id.suffix.hex}"

  tags = merge(var.common_tags, {
    Name        = "CSV Output Bucket"
    Purpose     = "Store converted CSV files"
    DataFlow    = "output"
  })
}

# Enable versioning on output bucket for data protection
resource "aws_s3_bucket_versioning" "output" {
  bucket = aws_s3_bucket.output.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure server-side encryption for output bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "output" {
  bucket = aws_s3_bucket.output.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access to output bucket for security
resource "aws_s3_bucket_public_access_block" "output" {
  bucket = aws_s3_bucket.output.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# LAMBDA FUNCTION
# =============================================================================

# CloudWatch log group for Lambda function
# This is created explicitly to set retention policy and permissions
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.lambda_function_name}-${random_id.suffix.hex}"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name    = "JSON-CSV Converter Lambda Logs"
    Purpose = "Store Lambda function execution logs"
  })
}

# IAM role for Lambda execution
# This role allows Lambda to assume permissions and access AWS services
resource "aws_iam_role" "lambda" {
  name = "${var.lambda_function_name}-role-${random_id.suffix.hex}"

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

  tags = merge(var.common_tags, {
    Name    = "JSON-CSV Converter Lambda Role"
    Purpose = "Execution role for Lambda function"
  })
}

# Attach basic Lambda execution policy for CloudWatch logging
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom IAM policy for S3 access
# Grants specific permissions to read from input bucket and write to output bucket
resource "aws_iam_role_policy" "lambda_s3" {
  name = "S3AccessPolicy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.input.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.output.arn}/*"
      }
    ]
  })
}

# Create Lambda deployment package
# This creates a ZIP file containing the Lambda function code
data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda-deployment.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      output_bucket = aws_s3_bucket.output.bucket
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for JSON to CSV conversion
# This function is triggered by S3 events and processes JSON files
resource "aws_lambda_function" "converter" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "${var.lambda_function_name}-${random_id.suffix.hex}"
  role            = aws_iam_role.lambda.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.output.bucket
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda_s3,
    aws_cloudwatch_log_group.lambda,
  ]

  tags = merge(var.common_tags, {
    Name    = "JSON-CSV Converter"
    Purpose = "Convert JSON files to CSV format"
  })
}

# =============================================================================
# S3 EVENT NOTIFICATIONS
# =============================================================================

# Lambda permission for S3 to invoke the function
# This allows S3 to trigger the Lambda function when events occur
resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.converter.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input.arn
}

# S3 bucket notification configuration
# This triggers the Lambda function when JSON files are uploaded
resource "aws_s3_bucket_notification" "input_notification" {
  bucket = aws_s3_bucket.input.id

  lambda_function {
    id                  = "json-csv-converter-trigger"
    lambda_function_arn = aws_lambda_function.converter.arn
    events              = ["s3:ObjectCreated:*"]
    
    filter_prefix = var.input_file_prefix
    filter_suffix = ".json"
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}

# =============================================================================
# OPTIONAL: CLOUDWATCH ALARMS FOR MONITORING
# =============================================================================

# CloudWatch alarm for Lambda function errors
# This monitors the function for errors and can trigger notifications
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${var.lambda_function_name}-${random_id.suffix.hex}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors lambda function errors"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.converter.function_name
  }

  tags = merge(var.common_tags, {
    Name    = "Lambda Error Alarm"
    Purpose = "Monitor Lambda function for errors"
  })
}

# CloudWatch alarm for Lambda function duration
# This monitors the function execution time for performance optimization
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${var.lambda_function_name}-${random_id.suffix.hex}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = var.lambda_timeout * 1000 * 0.8  # 80% of timeout in milliseconds
  alarm_description   = "This metric monitors lambda function duration"
  alarm_actions       = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.converter.function_name
  }

  tags = merge(var.common_tags, {
    Name    = "Lambda Duration Alarm"
    Purpose = "Monitor Lambda function execution time"
  })
}