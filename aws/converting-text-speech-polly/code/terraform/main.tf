# Amazon Polly Text-to-Speech Solutions Infrastructure
# This file contains the main infrastructure resources for implementing
# comprehensive text-to-speech capabilities using Amazon Polly

# Data sources for account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming with fallbacks
  bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.project_name}-audio-storage-${random_id.suffix.hex}"
  lambda_function_name = var.lambda_function_name != "" ? var.lambda_function_name : "${var.project_name}-batch-processor-${random_id.suffix.hex}"
  iam_role_name = var.iam_role_name != "" ? var.iam_role_name : "PollyProcessorRole-${random_id.suffix.hex}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    Recipe      = "amazon-polly-tts"
  })
}

# S3 Bucket for storing generated audio files
resource "aws_s3_bucket" "audio_storage" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, {
    Name        = local.bucket_name
    Purpose     = "Audio file storage for Polly TTS"
    ContentType = "audio/mpeg"
  })
}

# S3 Bucket versioning configuration
resource "aws_s3_bucket_versioning" "audio_storage" {
  bucket = aws_s3_bucket.audio_storage.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 Bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "audio_storage" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.audio_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "audio_storage" {
  bucket = aws_s3_bucket.audio_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "audio_storage" {
  bucket = aws_s3_bucket.audio_storage.id

  rule {
    id     = "audio_lifecycle"
    status = "Enabled"

    # Transition to cheaper storage classes over time
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete old versions if versioning is enabled
    dynamic "noncurrent_version_expiration" {
      for_each = var.enable_s3_versioning ? [1] : []
      content {
        noncurrent_days = 365
      }
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name = local.iam_role_name

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
    Name    = local.iam_role_name
    Purpose = "Lambda execution role for Polly TTS processor"
  })
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_polly_policy" {
  name = "PollyLambdaPolicy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "polly:SynthesizeSpeech",
          "polly:DescribeVoices",
          "polly:ListLexicons",
          "polly:GetLexicon",
          "polly:StartSpeechSynthesisTask",
          "polly:GetSpeechSynthesisTask",
          "polly:ListSpeechSynthesisTasks"
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
          aws_s3_bucket.audio_storage.arn,
          "${aws_s3_bucket.audio_storage.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name    = "/aws/lambda/${local.lambda_function_name}"
    Purpose = "Lambda function logs for Polly TTS processor"
  })
}

# Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      bucket_name      = local.bucket_name
      default_voice_id = var.default_voice_id
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for batch processing
resource "aws_lambda_function" "polly_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME      = aws_s3_bucket.audio_storage.bucket
      DEFAULT_VOICE_ID = var.default_voice_id
      AWS_REGION      = data.aws_region.current.name
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_polly_policy,
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name    = local.lambda_function_name
    Purpose = "Batch text-to-speech processing with Amazon Polly"
  })
}

# S3 Bucket notification to trigger Lambda on text file upload
resource "aws_s3_bucket_notification" "audio_processing_trigger" {
  bucket = aws_s3_bucket.audio_storage.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.polly_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "text/"
    filter_suffix       = ".txt"
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}

# Lambda permission for S3 to invoke the function
resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.polly_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.audio_storage.arn
}

# Custom Polly lexicons for pronunciation control
resource "aws_polly_lexicon" "custom_lexicons" {
  for_each = var.custom_lexicons
  
  name    = each.key
  content = each.value

  tags = merge(local.common_tags, {
    Name    = each.key
    Purpose = "Custom pronunciation lexicon for Polly TTS"
  })
}

# CloudFront distribution for global content delivery (optional)
resource "aws_cloudfront_distribution" "audio_cdn" {
  count = var.enable_cloudfront ? 1 : 0

  origin {
    domain_name = aws_s3_bucket.audio_storage.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.audio_storage.bucket}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.audio_oai[0].cloudfront_access_identity_path
    }
  }

  enabled = true
  comment = "CDN for Polly TTS audio files"

  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.audio_storage.bucket}"
    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # Cache behavior for audio files
  ordered_cache_behavior {
    path_pattern           = "audio/*"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.audio_storage.bucket}"
    compress               = false # Audio files are already compressed
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      headers      = ["Origin", "Access-Control-Request-Headers", "Access-Control-Request-Method"]
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 86400   # Cache audio files for 24 hours
    default_ttl = 604800  # Default 7 days
    max_ttl     = 31536000 # Max 1 year
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
    Name    = "${var.project_name}-audio-cdn"
    Purpose = "Global content delivery for Polly TTS audio files"
  })
}

# CloudFront Origin Access Identity for S3 access
resource "aws_cloudfront_origin_access_identity" "audio_oai" {
  count = var.enable_cloudfront ? 1 : 0
  
  comment = "OAI for Polly TTS audio files"
}

# S3 bucket policy for CloudFront access
resource "aws_s3_bucket_policy" "audio_storage_policy" {
  count  = var.enable_cloudfront ? 1 : 0
  bucket = aws_s3_bucket.audio_storage.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.audio_oai[0].iam_arn
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.audio_storage.arn}/*"
      }
    ]
  })
}

# API Gateway for HTTP access to Lambda function (optional)
resource "aws_api_gateway_rest_api" "polly_api" {
  count = var.enable_api_gateway ? 1 : 0
  
  name        = "${var.project_name}-polly-api"
  description = "API Gateway for Polly TTS Lambda function"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-polly-api"
    Purpose = "HTTP API for text-to-speech processing"
  })
}

# API Gateway resource
resource "aws_api_gateway_resource" "synthesize" {
  count = var.enable_api_gateway ? 1 : 0
  
  rest_api_id = aws_api_gateway_rest_api.polly_api[0].id
  parent_id   = aws_api_gateway_rest_api.polly_api[0].root_resource_id
  path_part   = "synthesize"
}

# API Gateway method
resource "aws_api_gateway_method" "synthesize_post" {
  count = var.enable_api_gateway ? 1 : 0
  
  rest_api_id   = aws_api_gateway_rest_api.polly_api[0].id
  resource_id   = aws_api_gateway_resource.synthesize[0].id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway integration with Lambda
resource "aws_api_gateway_integration" "lambda_integration" {
  count = var.enable_api_gateway ? 1 : 0
  
  rest_api_id = aws_api_gateway_rest_api.polly_api[0].id
  resource_id = aws_api_gateway_resource.synthesize[0].id
  http_method = aws_api_gateway_method.synthesize_post[0].http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.polly_processor.invoke_arn
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "polly_api_deployment" {
  count = var.enable_api_gateway ? 1 : 0
  
  rest_api_id = aws_api_gateway_rest_api.polly_api[0].id
  stage_name  = var.api_gateway_stage_name

  depends_on = [
    aws_api_gateway_method.synthesize_post,
    aws_api_gateway_integration.lambda_integration
  ]
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_invoke" {
  count = var.enable_api_gateway ? 1 : 0
  
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.polly_processor.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.polly_api[0].execution_arn}/*/*"
}