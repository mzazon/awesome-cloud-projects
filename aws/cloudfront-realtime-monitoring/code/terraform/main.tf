# CloudFront Real-time Monitoring and Analytics - Main Infrastructure
# This file defines all AWS resources needed for the complete monitoring solution

# Random string for unique resource naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  name_prefix = "${var.project_name}-${random_string.suffix.result}"
  
  # Common tags for all resources
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "Terraform"
  }
}

# Data source for current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

#------------------------------------------------------------------------------
# S3 BUCKETS FOR CONTENT AND LOG STORAGE
#------------------------------------------------------------------------------

# S3 bucket for CloudFront content
resource "aws_s3_bucket" "content" {
  bucket = "${local.name_prefix}-content"

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-content"
    Purpose = "CloudFront origin content storage"
  })
}

# S3 bucket for log storage
resource "aws_s3_bucket" "logs" {
  bucket = "${local.name_prefix}-logs"

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-logs"
    Purpose = "CloudFront real-time logs storage"
  })
}

# Content bucket versioning
resource "aws_s3_bucket_versioning" "content" {
  bucket = aws_s3_bucket.content.id
  versioning_configuration {
    status = var.s3_enable_versioning ? "Enabled" : "Disabled"
  }
}

# Logs bucket versioning
resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = var.s3_enable_versioning ? "Enabled" : "Disabled"
  }
}

# Content bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "content" {
  bucket = aws_s3_bucket.content.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Logs bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Content bucket public access block
resource "aws_s3_bucket_public_access_block" "content" {
  count  = var.enable_s3_public_access_block ? 1 : 0
  bucket = aws_s3_bucket.content.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Logs bucket public access block
resource "aws_s3_bucket_public_access_block" "logs" {
  count  = var.enable_s3_public_access_block ? 1 : 0
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Content bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "content" {
  bucket = aws_s3_bucket.content.id

  rule {
    id     = "content_lifecycle"
    status = "Enabled"

    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = var.s3_lifecycle_expiration_days
    }

    noncurrent_version_transition {
      noncurrent_days = var.s3_lifecycle_transition_days
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = var.s3_lifecycle_expiration_days
    }
  }
}

# Logs bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "logs_lifecycle"
    status = "Enabled"

    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_lifecycle_expiration_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.s3_lifecycle_expiration_days * 2
    }
  }
}

# Force SSL policy for content bucket
resource "aws_s3_bucket_policy" "content_ssl" {
  count  = var.force_ssl_requests_only ? 1 : 0
  bucket = aws_s3_bucket.content.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.content.arn,
          "${aws_s3_bucket.content.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Force SSL policy for logs bucket
resource "aws_s3_bucket_policy" "logs_ssl" {
  count  = var.force_ssl_requests_only ? 1 : 0
  bucket = aws_s3_bucket.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.logs.arn,
          "${aws_s3_bucket.logs.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

#------------------------------------------------------------------------------
# SAMPLE CONTENT FOR TESTING (OPTIONAL)
#------------------------------------------------------------------------------

# Sample HTML content
resource "aws_s3_object" "sample_html" {
  count  = var.create_sample_content ? 1 : 0
  bucket = aws_s3_bucket.content.id
  key    = "index.html"
  
  content = <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>CloudFront Monitoring Demo</title>
    <link rel="stylesheet" href="/css/style.css">
    <script src="/js/app.js"></script>
</head>
<body>
    <h1>Welcome to CloudFront Monitoring Demo</h1>
    <p>This page generates traffic for monitoring analysis.</p>
    <img src="/images/demo.jpg" alt="Demo Image" width="300">
    <div id="content"></div>
</body>
</html>
EOF

  content_type = "text/html"
  cache_control = "max-age=3600"

  tags = merge(local.common_tags, {
    Name = "sample-html-content"
  })
}

# Sample CSS content
resource "aws_s3_object" "sample_css" {
  count  = var.create_sample_content ? 1 : 0
  bucket = aws_s3_bucket.content.id
  key    = "css/style.css"
  
  content      = "body { font-family: Arial, sans-serif; margin: 40px; background-color: #f5f5f5; } h1 { color: #333; } p { color: #666; }"
  content_type = "text/css"
  cache_control = "max-age=86400"

  tags = merge(local.common_tags, {
    Name = "sample-css-content"
  })
}

# Sample JavaScript content
resource "aws_s3_object" "sample_js" {
  count  = var.create_sample_content ? 1 : 0
  bucket = aws_s3_bucket.content.id
  key    = "js/app.js"
  
  content = <<EOF
console.log("Page loaded at:", new Date().toISOString());
fetch("/api/data")
  .then(response => response.json())
  .then(data => {
    document.getElementById("content").innerHTML = JSON.stringify(data, null, 2);
  })
  .catch(error => {
    console.error("Error loading data:", error);
    document.getElementById("content").innerHTML = "Error loading data";
  });
EOF

  content_type = "application/javascript"
  cache_control = "max-age=86400"

  tags = merge(local.common_tags, {
    Name = "sample-js-content"
  })
}

# Sample API data
resource "aws_s3_object" "sample_api" {
  count  = var.create_sample_content ? 1 : 0
  bucket = aws_s3_bucket.content.id
  key    = "api/data"
  
  content = jsonencode({
    message   = "Hello from CloudFront Monitoring Demo"
    timestamp = "2024-01-01T00:00:00.000Z"
    version   = "1.0"
    status    = "active"
  })

  content_type = "application/json"
  cache_control = "max-age=300"

  tags = merge(local.common_tags, {
    Name = "sample-api-content"
  })
}

#------------------------------------------------------------------------------
# KINESIS DATA STREAMS
#------------------------------------------------------------------------------

# Primary Kinesis stream for raw CloudFront logs
resource "aws_kinesis_stream" "cloudfront_logs" {
  name             = "${local.name_prefix}-realtime-logs"
  shard_count      = var.kinesis_shard_count
  retention_period = var.kinesis_retention_period

  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords",
    "WriteProvisionedThroughputExceeded",
    "ReadProvisionedThroughputExceeded",
    "IncomingBytes",
    "OutgoingBytes"
  ]

  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-realtime-logs"
    Purpose = "CloudFront real-time logs ingestion"
  })
}

# Secondary Kinesis stream for processed logs
resource "aws_kinesis_stream" "processed_logs" {
  name             = "${local.name_prefix}-processed-logs"
  shard_count      = var.kinesis_processed_shard_count
  retention_period = var.kinesis_retention_period

  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords"
  ]

  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-processed-logs"
    Purpose = "Processed CloudFront logs for storage"
  })
}

#------------------------------------------------------------------------------
# DYNAMODB TABLE FOR METRICS STORAGE
#------------------------------------------------------------------------------

resource "aws_dynamodb_table" "metrics" {
  name           = "${local.name_prefix}-metrics"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "MetricId"
  range_key      = "Timestamp"

  attribute {
    name = "MetricId"
    type = "S"
  }

  attribute {
    name = "Timestamp"
    type = "S"
  }

  ttl {
    attribute_name = "TTL"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-metrics"
    Purpose = "Real-time metrics storage"
  })
}

#------------------------------------------------------------------------------
# OPENSEARCH SERVICE DOMAIN
#------------------------------------------------------------------------------

resource "aws_opensearch_domain" "analytics" {
  domain_name    = "${local.name_prefix}-analytics"
  engine_version = var.opensearch_engine_version

  cluster_config {
    instance_type  = var.opensearch_instance_type
    instance_count = var.opensearch_instance_count
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = var.opensearch_ebs_volume_size
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  # Access policy for OpenSearch
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action   = "es:*"
        Resource = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${local.name_prefix}-analytics/*"
        Condition = {
          IpAddress = {
            "aws:SourceIp" = var.opensearch_access_ip_ranges
          }
        }
      }
    ]
  })

  advanced_security_options {
    enabled                        = false
    anonymous_auth_enabled         = false
    internal_user_database_enabled = false
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-analytics"
    Purpose = "CloudFront logs analytics and visualization"
  })
}

#------------------------------------------------------------------------------
# IAM ROLES AND POLICIES
#------------------------------------------------------------------------------

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
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

  tags = local.common_tags
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.name_prefix}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:ListStreams",
          "kinesis:PutRecord",
          "kinesis:PutRecords"
        ]
        Resource = [
          aws_kinesis_stream.cloudfront_logs.arn,
          aws_kinesis_stream.processed_logs.arn
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
        Resource = aws_dynamodb_table.metrics.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
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
        Resource = "*"
      }
    ]
  })
}

# Attach basic execution role to Lambda
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM role for Kinesis Data Firehose
resource "aws_iam_role" "firehose_role" {
  name = "${local.name_prefix}-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for Kinesis Data Firehose
resource "aws_iam_role_policy" "firehose_policy" {
  name = "${local.name_prefix}-firehose-policy"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.logs.arn,
          "${aws_s3_bucket.logs.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "es:DescribeElasticsearchDomain",
          "es:DescribeElasticsearchDomains",
          "es:DescribeElasticsearchDomainConfig",
          "es:ESHttpPost",
          "es:ESHttpPut"
        ]
        Resource = "${aws_opensearch_domain.analytics.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM role for CloudFront real-time logs
resource "aws_iam_role" "cloudfront_realtime_logs_role" {
  name = "${local.name_prefix}-cloudfront-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for CloudFront real-time logs
resource "aws_iam_role_policy" "cloudfront_realtime_logs_policy" {
  name = "${local.name_prefix}-cloudfront-logs-policy"
  role = aws_iam_role.cloudfront_realtime_logs_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:PutRecords",
          "kinesis:PutRecord"
        ]
        Resource = aws_kinesis_stream.cloudfront_logs.arn
      }
    ]
  })
}

#------------------------------------------------------------------------------
# LAMBDA FUNCTION FOR LOG PROCESSING
#------------------------------------------------------------------------------

# Archive Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = file("${path.module}/lambda_function.js")
    filename = "index.js"
  }
  
  source {
    content = file("${path.module}/package.json")
    filename = "package.json"
  }
}

# Lambda function for real-time log processing
resource "aws_lambda_function" "log_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-log-processor"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = var.lambda_runtime
  memory_size     = var.lambda_memory_size
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      METRICS_TABLE    = aws_dynamodb_table.metrics.name
      PROCESSED_STREAM = aws_kinesis_stream.processed_logs.name
      TTL_DAYS        = var.dynamodb_ttl_days
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda
  ]

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-log-processor"
    Purpose = "Real-time CloudFront log processing"
  })
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_prefix}-log-processor"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-logs"
  })
}

# Event source mapping for Lambda function
resource "aws_lambda_event_source_mapping" "kinesis_lambda" {
  event_source_arn                   = aws_kinesis_stream.cloudfront_logs.arn
  function_name                      = aws_lambda_function.log_processor.arn
  starting_position                  = "LATEST"
  batch_size                         = var.lambda_batch_size
  maximum_batching_window_in_seconds = var.lambda_maximum_batching_window

  depends_on = [aws_iam_role_policy.lambda_policy]
}

#------------------------------------------------------------------------------
# KINESIS DATA FIREHOSE
#------------------------------------------------------------------------------

# CloudWatch log group for Firehose
resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${local.name_prefix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-firehose-logs"
  })
}

# CloudWatch log stream for Firehose S3 delivery
resource "aws_cloudwatch_log_stream" "firehose_s3" {
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

# Kinesis Data Firehose delivery stream
resource "aws_kinesis_firehose_delivery_stream" "logs_to_s3_opensearch" {
  name        = "${local.name_prefix}-logs-to-s3-opensearch"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.processed_logs.arn
    role_arn          = aws_iam_role.firehose_role.arn
  }

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose_role.arn
    bucket_arn          = aws_s3_bucket.logs.arn
    prefix              = "cloudfront-logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "errors/"
    buffer_size         = var.firehose_buffer_size
    buffer_interval     = var.firehose_buffer_interval
    compression_format  = var.firehose_compression_format

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_s3.name
    }
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-firehose"
    Purpose = "CloudFront logs delivery to S3 and OpenSearch"
  })
}

#------------------------------------------------------------------------------
# CLOUDFRONT DISTRIBUTION
#------------------------------------------------------------------------------

# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "content" {
  name                              = "${local.name_prefix}-oac"
  description                       = "Origin Access Control for ${local.name_prefix}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront real-time log configuration
resource "aws_cloudfront_realtime_log_config" "main" {
  count = var.enable_real_time_logs ? 1 : 0
  name  = "${local.name_prefix}-realtime-logs"

  endpoint {
    stream_type = "Kinesis"

    kinesis_stream_config {
      role_arn   = aws_iam_role.cloudfront_realtime_logs_role.arn
      stream_arn = aws_kinesis_stream.cloudfront_logs.arn
    }
  }

  fields = [
    "timestamp",
    "c-ip",
    "sc-status",
    "cs-method",
    "cs-uri-stem",
    "cs-uri-query",
    "cs-referer",
    "cs-user-agent",
    "cs-cookie",
    "x-edge-location",
    "x-edge-request-id",
    "x-host-header",
    "cs-protocol",
    "cs-bytes",
    "sc-bytes",
    "time-taken",
    "x-forwarded-for",
    "ssl-protocol",
    "ssl-cipher",
    "x-edge-response-result-type",
    "cs-protocol-version",
    "fle-status",
    "fle-encrypted-fields",
    "c-port",
    "time-to-first-byte",
    "x-edge-detailed-result-type",
    "sc-content-type",
    "sc-content-len",
    "sc-range-start",
    "sc-range-end"
  ]
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "main" {
  comment             = "CloudFront distribution for real-time monitoring demo"
  enabled             = true
  is_ipv6_enabled     = var.cloudfront_enable_ipv6
  default_root_object = var.cloudfront_default_root_object
  price_class         = var.cloudfront_price_class

  origin {
    domain_name              = aws_s3_bucket.content.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.content.id
    origin_id                = "S3Origin"
  }

  default_cache_behavior {
    allowed_methods            = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "S3Origin"
    viewer_protocol_policy     = "redirect-to-https"
    compress                   = true
    cache_policy_id            = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"  # Managed-CachingOptimized
    realtime_log_config_arn    = var.enable_real_time_logs ? aws_cloudfront_realtime_log_config.main[0].arn : null
  }

  ordered_cache_behavior {
    path_pattern               = "/api/*"
    allowed_methods            = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "S3Origin"
    viewer_protocol_policy     = "https-only"
    compress                   = true
    cache_policy_id            = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"  # Managed-CachingOptimized
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = var.cloudfront_minimum_protocol_version
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-distribution"
    Purpose = "Global content delivery with real-time monitoring"
  })

  depends_on = [aws_cloudfront_realtime_log_config.main]
}

# S3 bucket policy for CloudFront access
resource "aws_s3_bucket_policy" "content_cloudfront" {
  bucket = aws_s3_bucket.content.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.content.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.content]
}

#------------------------------------------------------------------------------
# CLOUDWATCH DASHBOARD
#------------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "main" {
  count          = var.enable_dashboard ? 1 : 0
  dashboard_name = "CloudFront-RealTime-Analytics-${random_string.suffix.result}"

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
            ["CloudFront/RealTime", "RequestCount"],
            [".", "BytesDownloaded"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Real-time Traffic Volume"
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
            ["CloudFront/RealTime", "ErrorRate4xx"],
            [".", "ErrorRate5xx"]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Real-time Error Rates"
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
            ["CloudFront/RealTime", "CacheMissRate"]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Cache Performance"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.log_processor.function_name],
            [".", "Invocations", ".", "."],
            [".", "Errors", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Log Processing Performance"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Kinesis", "IncomingRecords", "StreamName", aws_kinesis_stream.cloudfront_logs.name],
            [".", "OutgoingRecords", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Kinesis Stream Activity"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/CloudFront", "Requests", "DistributionId", aws_cloudfront_distribution.main.id],
            [".", "BytesDownloaded", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = "us-east-1"  # CloudFront metrics are always in us-east-1
          title  = "CloudFront Standard Metrics"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-dashboard"
    Purpose = "Real-time monitoring and analytics dashboard"
  })
}