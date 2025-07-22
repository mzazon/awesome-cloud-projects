# Main Terraform Configuration for Video Processing Workflow
# Creates a complete event-driven video processing pipeline using S3, Lambda, and MediaConvert

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data sources for existing AWS resources
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Get MediaConvert endpoint for the current region
data "aws_mediaconvert_endpoints" "current" {}

# Local values for resource naming and configuration
locals {
  random_suffix = random_string.suffix.result
  
  # Resource names with consistent naming convention
  source_bucket_name = "${var.s3_source_bucket_name}-${local.random_suffix}"
  output_bucket_name = "${var.s3_output_bucket_name}-${local.random_suffix}"
  
  # Common tags to apply to all resources
  common_tags = merge(
    var.tags,
    {
      Name        = var.project_name
      Environment = var.environment
      Terraform   = "true"
    }
  )
  
  # MediaConvert endpoint (first available endpoint)
  mediaconvert_endpoint = data.aws_mediaconvert_endpoints.current.endpoints[0].url
}

# ============================================================================
# S3 BUCKETS FOR VIDEO STORAGE
# ============================================================================

# S3 bucket for source video files
resource "aws_s3_bucket" "source" {
  bucket = local.source_bucket_name
  
  tags = merge(local.common_tags, {
    Purpose = "Source video files"
  })
}

# S3 bucket for processed video outputs
resource "aws_s3_bucket" "output" {
  bucket = local.output_bucket_name
  
  tags = merge(local.common_tags, {
    Purpose = "Processed video outputs"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_versioning" "output" {
  bucket = aws_s3_bucket.output.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "output" {
  bucket = aws_s3_bucket.output.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "source" {
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "output" {
  bucket = aws_s3_bucket.output.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "source" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.source.id

  rule {
    id     = "source_lifecycle"
    status = "Enabled"

    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }

    dynamic "expiration" {
      for_each = var.s3_lifecycle_expiration_days > 0 ? [1] : []
      content {
        days = var.s3_lifecycle_expiration_days
      }
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "output" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.output.id

  rule {
    id     = "output_lifecycle"
    status = "Enabled"

    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }

    dynamic "expiration" {
      for_each = var.s3_lifecycle_expiration_days > 0 ? [1] : []
      content {
        days = var.s3_lifecycle_expiration_days
      }
    }
  }
}

# ============================================================================
# IAM ROLES AND POLICIES
# ============================================================================

# IAM role for MediaConvert service
resource "aws_iam_role" "mediaconvert_role" {
  name = "MediaConvertRole-${local.random_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "mediaconvert.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Purpose = "MediaConvert service role"
  })
}

# IAM policy for MediaConvert to access S3 buckets
resource "aws_iam_policy" "mediaconvert_s3_policy" {
  name        = "MediaConvertS3Policy-${local.random_suffix}"
  description = "Policy for MediaConvert to access S3 buckets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.source.arn,
          "${aws_s3_bucket.source.arn}/*",
          aws_s3_bucket.output.arn,
          "${aws_s3_bucket.output.arn}/*"
        ]
      }
    ]
  })

  tags = local.common_tags
}

# Attach policy to MediaConvert role
resource "aws_iam_role_policy_attachment" "mediaconvert_s3_policy" {
  role       = aws_iam_role.mediaconvert_role.name
  policy_arn = aws_iam_policy.mediaconvert_s3_policy.arn
}

# IAM role for Lambda function execution
resource "aws_iam_role" "lambda_role" {
  name = "LambdaVideoProcessorRole-${local.random_suffix}"

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
    Purpose = "Lambda video processor execution role"
  })
}

# IAM policy for Lambda to access MediaConvert and S3
resource "aws_iam_policy" "lambda_policy" {
  name        = "LambdaVideoProcessorPolicy-${local.random_suffix}"
  description = "Policy for Lambda to access MediaConvert and S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "mediaconvert:*"
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
        Resource = [
          "${aws_s3_bucket.source.arn}/*",
          "${aws_s3_bucket.output.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.mediaconvert_role.arn
      }
    ]
  })

  tags = local.common_tags
}

# Attach policies to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# ============================================================================
# LAMBDA FUNCTION FOR VIDEO PROCESSING
# ============================================================================

# Create Lambda function code file
resource "local_file" "lambda_function_py" {
  content = templatefile("${path.module}/templates/lambda_function.py.tpl", {
    mediaconvert_endpoint = local.mediaconvert_endpoint
    mediaconvert_role_arn = aws_iam_role.mediaconvert_role.arn
    output_bucket_name    = local.output_bucket_name
    video_bitrate         = var.mediaconvert_bitrate
    video_framerate       = var.mediaconvert_framerate
    video_width           = var.mediaconvert_width
    video_height          = var.mediaconvert_height
  })
  filename = "${path.module}/lambda_function.py"
}

# Create Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content  = local_file.lambda_function_py.content
    filename = "lambda_function.py"
  }
  
  depends_on = [local_file.lambda_function_py]
}

# Main Lambda function for video processing
resource "aws_lambda_function" "video_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.lambda_function_name}-${local.random_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      MEDIACONVERT_ENDPOINT = local.mediaconvert_endpoint
      MEDIACONVERT_ROLE_ARN = aws_iam_role.mediaconvert_role.arn
      S3_OUTPUT_BUCKET     = local.output_bucket_name
      VIDEO_BITRATE        = var.mediaconvert_bitrate
      VIDEO_FRAMERATE      = var.mediaconvert_framerate
      VIDEO_WIDTH          = var.mediaconvert_width
      VIDEO_HEIGHT         = var.mediaconvert_height
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "Video processing orchestration"
  })
}

# Lambda permission for S3 to invoke the function
resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.video_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.source.arn
}

# ============================================================================
# S3 EVENT NOTIFICATION CONFIGURATION
# ============================================================================

# S3 bucket notification configuration
resource "aws_s3_bucket_notification" "source_notification" {
  bucket = aws_s3_bucket.source.id

  dynamic "lambda_function" {
    for_each = var.video_file_extensions
    content {
      lambda_function_arn = aws_lambda_function.video_processor.arn
      events              = ["s3:ObjectCreated:*"]
      filter_prefix       = ""
      filter_suffix       = ".${lambda_function.value}"
    }
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}

# ============================================================================
# COMPLETION HANDLER (OPTIONAL)
# ============================================================================

# Create completion handler code file
resource "local_file" "completion_handler_py" {
  count = var.enable_completion_handler ? 1 : 0
  
  content  = file("${path.module}/templates/completion_handler.py.tpl")
  filename = "${path.module}/completion_handler.py"
}

# Create completion handler code archive
data "archive_file" "completion_handler_zip" {
  count = var.enable_completion_handler ? 1 : 0
  
  type        = "zip"
  output_path = "${path.module}/completion_handler.zip"
  
  source {
    content  = local_file.completion_handler_py[0].content
    filename = "completion_handler.py"
  }
  
  depends_on = [local_file.completion_handler_py]
}

# Lambda function for job completion handling
resource "aws_lambda_function" "completion_handler" {
  count = var.enable_completion_handler ? 1 : 0

  filename         = data.archive_file.completion_handler_zip[0].output_path
  function_name    = "completion-handler-${local.random_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "completion_handler.lambda_handler"
  runtime         = "python3.9"
  timeout         = 30
  source_code_hash = data.archive_file.completion_handler_zip[0].output_base64sha256

  tags = merge(local.common_tags, {
    Purpose = "MediaConvert job completion handler"
  })
}

# EventBridge rule for MediaConvert job completion
resource "aws_cloudwatch_event_rule" "mediaconvert_completion" {
  count = var.enable_completion_handler ? 1 : 0

  name        = "MediaConvert-JobComplete-${local.random_suffix}"
  description = "Capture MediaConvert job completion events"

  event_pattern = jsonencode({
    source      = ["aws.mediaconvert"]
    detail-type = ["MediaConvert Job State Change"]
    detail = {
      status = ["COMPLETE"]
    }
  })

  tags = merge(local.common_tags, {
    Purpose = "MediaConvert job completion events"
  })
}

# EventBridge target for completion handler
resource "aws_cloudwatch_event_target" "completion_handler" {
  count = var.enable_completion_handler ? 1 : 0

  rule      = aws_cloudwatch_event_rule.mediaconvert_completion[0].name
  target_id = "CompletionHandlerTarget"
  arn       = aws_lambda_function.completion_handler[0].arn
}

# Lambda permission for EventBridge to invoke completion handler
resource "aws_lambda_permission" "eventbridge_invoke" {
  count = var.enable_completion_handler ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.completion_handler[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.mediaconvert_completion[0].arn
}

# ============================================================================
# CLOUDFRONT DISTRIBUTION (OPTIONAL)
# ============================================================================

# CloudFront Origin Access Identity for S3 access
resource "aws_cloudfront_origin_access_identity" "oai" {
  count = var.cloudfront_enabled ? 1 : 0

  comment = "OAI for video streaming distribution"
}

# S3 bucket policy for CloudFront access
resource "aws_s3_bucket_policy" "output_bucket_policy" {
  count = var.cloudfront_enabled ? 1 : 0

  bucket = aws_s3_bucket.output.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.oai[0].iam_arn
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.output.arn}/*"
      }
    ]
  })
}

# CloudFront distribution for video delivery
resource "aws_cloudfront_distribution" "video_distribution" {
  count = var.cloudfront_enabled ? 1 : 0

  origin {
    domain_name = aws_s3_bucket.output.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.output.id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai[0].cloudfront_access_identity_path
    }
  }

  enabled = true
  comment = "Video streaming distribution for ${var.project_name}"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.output.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  price_class = var.cloudfront_price_class

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(local.common_tags, {
    Purpose = "Video content delivery"
  })
}

# ============================================================================
# CLOUDWATCH LOG GROUPS FOR MONITORING
# ============================================================================

# CloudWatch log group for video processor Lambda
resource "aws_cloudwatch_log_group" "video_processor_logs" {
  name              = "/aws/lambda/${aws_lambda_function.video_processor.function_name}"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Purpose = "Video processor logs"
  })
}

# CloudWatch log group for completion handler Lambda
resource "aws_cloudwatch_log_group" "completion_handler_logs" {
  count = var.enable_completion_handler ? 1 : 0

  name              = "/aws/lambda/${aws_lambda_function.completion_handler[0].function_name}"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Purpose = "Completion handler logs"
  })
}

