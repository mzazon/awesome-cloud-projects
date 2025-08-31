# Main Terraform configuration for Markdown to HTML Converter
# This file creates a serverless document processing pipeline using AWS Lambda and S3

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffixes for unique resource naming
resource "random_string" "bucket_suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming and configuration
locals {
  # Generate unique bucket names using provided suffix or random string
  input_bucket_name  = "${var.project_name}-input-${var.input_bucket_suffix != "" ? var.input_bucket_suffix : random_string.bucket_suffix.result}"
  output_bucket_name = "${var.project_name}-output-${var.output_bucket_suffix != "" ? var.output_bucket_suffix : random_string.bucket_suffix.result}"
  
  # Common tags to be applied to all resources
  common_tags = merge(
    {
      Project      = var.project_name
      Environment  = var.environment
      Function     = "markdown-to-html-conversion"
      CreatedBy    = "terraform"
      LastModified = timestamp()
    },
    var.additional_tags
  )
}

# ============================================================================
# S3 BUCKETS - INPUT AND OUTPUT STORAGE
# ============================================================================

# S3 Bucket for input Markdown files
# This bucket receives uploaded Markdown files and triggers the Lambda function
resource "aws_s3_bucket" "input_bucket" {
  bucket = local.input_bucket_name

  tags = merge(local.common_tags, {
    Name        = local.input_bucket_name
    Purpose     = "markdown-input-storage"
    BucketType  = "input"
  })
}

# S3 Bucket for output HTML files
# This bucket stores the converted HTML files with metadata
resource "aws_s3_bucket" "output_bucket" {
  bucket = local.output_bucket_name

  tags = merge(local.common_tags, {
    Name        = local.output_bucket_name
    Purpose     = "html-output-storage"
    BucketType  = "output"
  })
}

# ============================================================================
# S3 BUCKET CONFIGURATIONS - SECURITY AND VERSIONING
# ============================================================================

# Configure versioning for input bucket
resource "aws_s3_bucket_versioning" "input_bucket_versioning" {
  bucket = aws_s3_bucket.input_bucket.id
  
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# Configure versioning for output bucket
resource "aws_s3_bucket_versioning" "output_bucket_versioning" {
  bucket = aws_s3_bucket.output_bucket.id
  
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Disabled" 
  }
}

# Enable server-side encryption for input bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "input_bucket_encryption" {
  count  = var.s3_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.input_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Enable server-side encryption for output bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "output_bucket_encryption" {
  count  = var.s3_bucket_encryption ? 1 : 0
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

# ============================================================================
# IAM ROLES AND POLICIES FOR LAMBDA EXECUTION
# ============================================================================

# IAM policy document for Lambda service to assume the execution role
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# IAM execution role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name               = "${var.project_name}-lambda-execution-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "Execution role for ${var.lambda_function_name} Lambda function"

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-lambda-execution-role"
    Purpose = "lambda-execution"
  })
}

# IAM policy document for S3 bucket access permissions
data "aws_iam_policy_document" "lambda_s3_policy" {
  # Allow reading from input bucket
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion"
    ]
    resources = ["${aws_s3_bucket.input_bucket.arn}/*"]
  }
  
  # Allow writing to output bucket
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]
    resources = ["${aws_s3_bucket.output_bucket.arn}/*"]
  }
  
  # Allow listing bucket contents (for validation)
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.input_bucket.arn,
      aws_s3_bucket.output_bucket.arn
    ]
  }
}

# IAM policy for S3 access
resource "aws_iam_policy" "lambda_s3_policy" {
  name        = "${var.project_name}-lambda-s3-access"
  description = "IAM policy for Lambda function to access S3 buckets"
  policy      = data.aws_iam_policy_document.lambda_s3_policy.json

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-lambda-s3-access"
    Purpose = "lambda-permissions"
  })
}

# Attach basic Lambda execution policy (for CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach custom S3 access policy
resource "aws_iam_role_policy_attachment" "lambda_s3_access" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}

# Attach X-Ray tracing policy if tracing is enabled
resource "aws_iam_role_policy_attachment" "lambda_xray_access" {
  count      = var.enable_lambda_tracing ? 1 : 0
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ============================================================================
# CLOUDWATCH LOGS FOR LAMBDA MONITORING
# ============================================================================

# CloudWatch Log Group for Lambda function logs
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name    = "/aws/lambda/${var.lambda_function_name}"
    Purpose = "lambda-logging"
  })
}

# ============================================================================
# LAMBDA FUNCTION DEPLOYMENT PACKAGE
# ============================================================================

# Create Lambda function source code with embedded dependencies
resource "local_file" "lambda_source" {
  filename = "${path.module}/lambda_function.py"
  content  = <<EOF
import json
import boto3
import urllib.parse
import os
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize S3 client
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    AWS Lambda handler for converting Markdown files to HTML
    Triggered by S3 PUT events on markdown files
    """
    try:
        # Parse S3 event
        for record in event['Records']:
            # Extract bucket and object information
            input_bucket = record['s3']['bucket']['name']
            input_key = urllib.parse.unquote_plus(
                record['s3']['object']['key'], encoding='utf-8'
            )
            
            logger.info(f"Processing file: {input_key} from bucket: {input_bucket}")
            
            # Verify file is a markdown file
            markdown_extensions = ${jsonencode(var.markdown_file_extensions)}
            if not any(input_key.lower().endswith(ext) for ext in markdown_extensions):
                logger.info(f"Skipping non-markdown file: {input_key}")
                continue
            
            # Download markdown content from S3
            try:
                response = s3.get_object(Bucket=input_bucket, Key=input_key)
                markdown_content = response['Body'].read().decode('utf-8')
                logger.info(f"Successfully downloaded {input_key}, size: {len(markdown_content)} bytes")
            except Exception as e:
                logger.error(f"Error downloading {input_key}: {str(e)}")
                continue
            
            # Convert markdown to HTML using markdown2
            try:
                html_content = convert_markdown_to_html(markdown_content)
                logger.info(f"Successfully converted {input_key} to HTML")
            except Exception as e:
                logger.error(f"Error converting {input_key}: {str(e)}")
                continue
            
            # Generate output filename (replace .md with .html)
            output_key = input_key.rsplit('.', 1)[0] + '.html'
            output_bucket = os.environ['OUTPUT_BUCKET_NAME']
            
            # Upload HTML content to output bucket
            try:
                s3.put_object(
                    Bucket=output_bucket,
                    Key=output_key,
                    Body=html_content,
                    ContentType='text/html',
                    Metadata={
                        'source-file': input_key,
                        'conversion-timestamp': datetime.utcnow().isoformat(),
                        'converter': 'lambda-markdown2',
                        'function-version': context.function_version if context else 'unknown'
                    }
                )
                logger.info(f"Successfully uploaded {output_key} to {output_bucket}")
            except Exception as e:
                logger.error(f"Error uploading {output_key}: {str(e)}")
                continue
            
            logger.info(f"Conversion completed: {input_key} -> {output_key}")
            
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Markdown conversion completed successfully',
            'timestamp': datetime.utcnow().isoformat()
        })
    }

def convert_markdown_to_html(markdown_text):
    """
    Convert markdown text to HTML using markdown2 library
    Includes basic extensions for enhanced formatting
    """
    try:
        import markdown2
        
        # Configure markdown2 with useful extras
        html = markdown2.markdown(
            markdown_text,
            extras=[
                'code-friendly',      # Better code block handling
                'fenced-code-blocks', # Support for ``` code blocks
                'tables',            # Support for markdown tables
                'strike',            # Support for ~~strikethrough~~
                'task-list',         # Support for task lists
                'header-ids',        # Add IDs to headers
                'toc'               # Table of contents support
            ]
        )
        
        # Wrap in basic HTML structure with responsive design
        full_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Converted Document</title>
    <style>
        body {{ 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            max-width: 800px; 
            margin: 0 auto; 
            padding: 20px;
            line-height: 1.6;
            color: #333;
        }}
        code {{ 
            background-color: #f4f4f4; 
            padding: 2px 4px; 
            border-radius: 3px;
            font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, 'Courier New', monospace;
            font-size: 0.9em;
        }}
        pre {{ 
            background-color: #f4f4f4; 
            padding: 15px; 
            border-radius: 5px; 
            overflow-x: auto;
            border: 1px solid #e0e0e0;
        }}
        pre code {{
            background-color: transparent;
            padding: 0;
        }}
        table {{ 
            border-collapse: collapse; 
            width: 100%;
            margin: 1em 0;
        }}
        th, td {{ 
            border: 1px solid #ddd; 
            padding: 12px 8px; 
            text-align: left; 
        }}
        th {{ 
            background-color: #f2f2f2;
            font-weight: 600;
        }}
        blockquote {{
            border-left: 4px solid #ddd;
            margin: 1em 0;
            padding: 0 1em;
            color: #666;
            font-style: italic;
        }}
        h1, h2, h3, h4, h5, h6 {{
            margin-top: 1.5em;
            margin-bottom: 0.5em;
            color: #2c3e50;
        }}
        h1 {{ border-bottom: 2px solid #eee; padding-bottom: 0.3em; }}
        h2 {{ border-bottom: 1px solid #eee; padding-bottom: 0.3em; }}
        a {{ color: #3498db; text-decoration: none; }}
        a:hover {{ text-decoration: underline; }}
        .conversion-info {{
            font-size: 0.8em;
            color: #888;
            border-top: 1px solid #eee;
            padding-top: 1em;
            margin-top: 2em;
        }}
    </style>
</head>
<body>
{html}
<div class="conversion-info">
    <p><em>Document converted by AWS Lambda • {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')} UTC</em></p>
</div>
</body>
</html>"""
        
        return full_html
        
    except ImportError:
        logger.warning("markdown2 library not available, using fallback conversion")
        # Fallback if markdown2 is not available
        return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Markdown Content</title>
    <style>
        body {{ font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }}
        pre {{ background-color: #f4f4f4; padding: 10px; border-radius: 5px; white-space: pre-wrap; }}
    </style>
</head>
<body>
<h1>Markdown Content</h1>
<pre>{markdown_text}</pre>
<p><em>Note: This is a fallback display. Install markdown2 library for proper conversion.</em></p>
</body>
</html>"""
EOF

  depends_on = [aws_s3_bucket.output_bucket]
}

# Create requirements.txt for Lambda dependencies
resource "local_file" "lambda_requirements" {
  filename = "${path.module}/requirements.txt"
  content  = "markdown2==2.5.3\n"
}

# Package the Lambda function code and dependencies
data "archive_file" "lambda_package" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content  = local_file.lambda_source.content
    filename = "lambda_function.py"
  }
  
  source {
    content  = local_file.lambda_requirements.content
    filename = "requirements.txt"
  }

  depends_on = [
    local_file.lambda_source,
    local_file.lambda_requirements
  ]
}

# ============================================================================
# LAMBDA FUNCTION DEPLOYMENT
# ============================================================================

# AWS Lambda function for Markdown to HTML conversion
resource "aws_lambda_function" "markdown_converter" {
  filename         = data.archive_file.lambda_package.output_path
  function_name    = var.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  description     = "Converts Markdown files to HTML using markdown2 library"

  # Environment variables for function configuration
  environment {
    variables = {
      OUTPUT_BUCKET_NAME        = aws_s3_bucket.output_bucket.bucket
      INPUT_BUCKET_NAME         = aws_s3_bucket.input_bucket.bucket
      MARKDOWN_EXTENSIONS       = join(",", var.markdown_file_extensions)
      LOG_LEVEL                = "INFO"
      CONVERSION_TIMESTAMP      = "true"
    }
  }

  # Configure reserved concurrency if specified
  reserved_concurrent_executions = var.lambda_reserved_concurrency >= 0 ? var.lambda_reserved_concurrency : null

  # Enable X-Ray tracing if requested
  dynamic "tracing_config" {
    for_each = var.enable_lambda_tracing ? [1] : []
    content {
      mode = "Active"
    }
  }

  # Advanced logging configuration for better observability
  logging_config {
    log_format            = "JSON"
    application_log_level = "INFO"
    system_log_level      = "WARN"
  }

  tags = merge(local.common_tags, {
    Name    = var.lambda_function_name
    Purpose = "markdown-conversion"
    Runtime = var.lambda_runtime
  })

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_s3_access
  ]
}

# ============================================================================
# S3 EVENT TRIGGER CONFIGURATION
# ============================================================================

# Grant S3 permission to invoke the Lambda function
resource "aws_lambda_permission" "s3_trigger_permission" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.markdown_converter.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input_bucket.arn
}

# Configure S3 bucket notification to trigger Lambda function
resource "aws_s3_bucket_notification" "markdown_processing_trigger" {
  bucket = aws_s3_bucket.input_bucket.id

  # Create a separate lambda function configuration for each markdown extension
  dynamic "lambda_function" {
    for_each = var.markdown_file_extensions
    content {
      id                  = "markdown-processor-trigger-${replace(lambda_function.value, ".", "")}"
      lambda_function_arn = aws_lambda_function.markdown_converter.arn
      events              = ["s3:ObjectCreated:*"]
      
      filter_suffix = lambda_function.value
    }
  }

  depends_on = [aws_lambda_permission.s3_trigger_permission]
}

# ============================================================================
# ADDITIONAL MONITORING AND ALERTING (OPTIONAL)
# ============================================================================

# CloudWatch Metric Alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name          = "${var.lambda_function_name}-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = [] # Add SNS topic ARN here if you want notifications

  dimensions = {
    FunctionName = aws_lambda_function.markdown_converter.function_name
  }

  tags = merge(local.common_tags, {
    Name    = "${var.lambda_function_name}-error-alarm"
    Purpose = "monitoring"
  })
}

# CloudWatch Metric Alarm for Lambda duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration_alarm" {
  alarm_name          = "${var.lambda_function_name}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = tostring(var.lambda_timeout * 1000 * 0.8) # Alert at 80% of timeout
  alarm_description   = "This metric monitors lambda duration"
  alarm_actions       = [] # Add SNS topic ARN here if you want notifications

  dimensions = {
    FunctionName = aws_lambda_function.markdown_converter.function_name
  }

  tags = merge(local.common_tags, {
    Name    = "${var.lambda_function_name}-duration-alarm"
    Purpose = "monitoring"
  })
}