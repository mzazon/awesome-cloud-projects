# Data sources for AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  name_suffix = random_id.suffix.hex
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Recipe      = "centralized-logging-with-opensearch-service"
  }
}

# S3 bucket for Firehose backup and Lambda deployment
resource "aws_s3_bucket" "backup_bucket" {
  bucket = "${var.project_name}-backup-${local.name_suffix}"
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-backup-${local.name_suffix}"
    Purpose = "Firehose backup storage"
  })
}

resource "aws_s3_bucket_versioning" "backup_bucket_versioning" {
  bucket = aws_s3_bucket.backup_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup_bucket_encryption" {
  bucket = aws_s3_bucket.backup_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backup_bucket_pab" {
  bucket = aws_s3_bucket.backup_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudWatch Log Groups for monitoring
resource "aws_cloudwatch_log_group" "firehose_log_group" {
  name              = "/aws/kinesisfirehose/${var.project_name}-delivery-${local.name_suffix}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "Firehose delivery logs"
  })
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${var.project_name}-processor-${local.name_suffix}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "Lambda processor logs"
  })
}

# Optional test log group for validation
resource "aws_cloudwatch_log_group" "test_log_group" {
  count             = var.create_test_log_group ? 1 : 0
  name              = "/aws/test/centralized-logging"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "Test log group"
    Purpose = "Testing centralized logging pipeline"
  })
}

# Kinesis Data Stream for log ingestion
resource "aws_kinesis_stream" "log_stream" {
  name             = "${var.project_name}-stream-${local.name_suffix}"
  shard_count      = var.kinesis_shard_count
  retention_period = var.kinesis_retention_period

  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  shard_level_metrics = [
    "IncomingRecords",
    "IncomingBytes",
    "OutgoingRecords",
    "OutgoingBytes",
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-stream-${local.name_suffix}"
    Purpose = "Log data ingestion stream"
  })
}

# IAM role for CloudWatch Logs to Kinesis
resource "aws_iam_role" "cloudwatch_logs_role" {
  name = "${var.project_name}-cwlogs-kinesis-role-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringLike = {
            "aws:SourceArn" = "arn:aws:logs:*:*:*"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "CloudWatch Logs to Kinesis role"
  })
}

resource "aws_iam_role_policy" "cloudwatch_logs_policy" {
  name = "${var.project_name}-cwlogs-kinesis-policy"
  role = aws_iam_role.cloudwatch_logs_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecords"
        ]
        Resource = aws_kinesis_stream.log_stream.arn
      }
    ]
  })
}

# Lambda function for log processing
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/log_processor.zip"
  source {
    content = file("${path.module}/lambda_function.py")
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "log_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-processor-${local.name_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      FIREHOSE_STREAM_NAME = aws_kinesis_firehose_delivery_stream.opensearch_delivery_stream.name
      AWS_REGION          = data.aws_region.current.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.lambda_log_group,
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-processor-${local.name_suffix}"
    Purpose = "Log processing and enrichment"
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${local.name_suffix}"

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
    Name = "Lambda execution role"
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_kinesis_policy" {
  name = "${var.project_name}-lambda-kinesis-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListStreams"
        ]
        Resource = aws_kinesis_stream.log_stream.arn
      },
      {
        Effect = "Allow"
        Action = [
          "firehose:PutRecord",
          "firehose:PutRecordBatch"
        ]
        Resource = aws_kinesis_firehose_delivery_stream.opensearch_delivery_stream.arn
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

# Lambda event source mapping
resource "aws_lambda_event_source_mapping" "kinesis_lambda_mapping" {
  event_source_arn  = aws_kinesis_stream.log_stream.arn
  function_name     = aws_lambda_function.log_processor.arn
  starting_position = "LATEST"
  batch_size        = var.lambda_batch_size
  maximum_batching_window_in_seconds = 10

  depends_on = [aws_iam_role_policy.lambda_kinesis_policy]
}

# OpenSearch Service domain
resource "aws_opensearch_domain" "logging_domain" {
  domain_name    = "${var.project_name}-domain-${local.name_suffix}"
  engine_version = var.opensearch_version

  cluster_config {
    instance_type            = var.opensearch_instance_type
    instance_count           = var.opensearch_instance_count
    dedicated_master_enabled = true
    master_instance_type     = var.opensearch_master_instance_type
    master_instance_count    = var.opensearch_master_instance_count
    zone_awareness_enabled   = var.enable_multi_az

    dynamic "zone_awareness_config" {
      for_each = var.enable_multi_az ? [1] : []
      content {
        availability_zone_count = var.availability_zone_count
      }
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_type = var.opensearch_ebs_volume_type
    volume_size = var.opensearch_ebs_volume_size
  }

  encrypt_at_rest {
    enabled = var.enable_encryption_at_rest
  }

  node_to_node_encryption {
    enabled = var.enable_node_to_node_encryption
  }

  domain_endpoint_options {
    enforce_https       = var.enforce_https
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  # Access policy allowing account root access
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "es:*"
        Resource = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.project_name}-domain-${local.name_suffix}/*"
      }
    ]
  })

  dynamic "log_publishing_options" {
    for_each = var.enable_cloudwatch_logs ? [1] : []
    content {
      cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_logs[0].arn
      log_type                 = "INDEX_SLOW_LOGS"
    }
  }

  dynamic "log_publishing_options" {
    for_each = var.enable_cloudwatch_logs ? [1] : []
    content {
      cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_logs[0].arn
      log_type                 = "SEARCH_SLOW_LOGS"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-domain-${local.name_suffix}"
    Purpose = "Centralized log analytics and search"
  })
}

# CloudWatch log group for OpenSearch
resource "aws_cloudwatch_log_group" "opensearch_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/opensearch/domains/${var.project_name}-domain-${local.name_suffix}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "OpenSearch domain logs"
  })
}

# IAM role for Kinesis Data Firehose
resource "aws_iam_role" "firehose_role" {
  name = "${var.project_name}-firehose-role-${local.name_suffix}"

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

  tags = merge(local.common_tags, {
    Name = "Firehose delivery role"
  })
}

resource "aws_iam_role_policy" "firehose_opensearch_policy" {
  name = "${var.project_name}-firehose-opensearch-policy"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "es:ESHttpPost",
          "es:ESHttpPut"
        ]
        Resource = "${aws_opensearch_domain.logging_domain.arn}/*"
      },
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
          aws_s3_bucket.backup_bucket.arn,
          "${aws_s3_bucket.backup_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.firehose_log_group.arn}:*"
      }
    ]
  })
}

# Kinesis Data Firehose delivery stream
resource "aws_kinesis_firehose_delivery_stream" "opensearch_delivery_stream" {
  name        = "${var.project_name}-delivery-${local.name_suffix}"
  destination = "opensearch"

  opensearch_configuration {
    domain_arn            = aws_opensearch_domain.logging_domain.arn
    role_arn              = aws_iam_role.firehose_role.arn
    index_name            = "logs-%Y-%m-%d"
    index_rotation_period = "OneDay"
    type_name             = "_doc"
    retry_duration        = 300
    s3_backup_mode        = "FailedDocumentsOnly"

    s3_configuration {
      role_arn           = aws_iam_role.firehose_role.arn
      bucket_arn         = aws_s3_bucket.backup_bucket.arn
      prefix             = "failed-logs/"
      error_output_prefix = "errors/"
      buffering_size     = var.firehose_buffer_size
      buffering_interval = var.firehose_buffer_interval
      compression_format = "GZIP"
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose_log_group.name
      log_stream_name = "opensearch-delivery"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-delivery-${local.name_suffix}"
    Purpose = "Log delivery to OpenSearch"
  })
}

# CloudWatch subscription filter for test log group (if enabled)
resource "aws_cloudwatch_log_subscription_filter" "test_filter" {
  count           = var.create_test_log_group ? 1 : 0
  name            = "test-filter-${local.name_suffix}"
  log_group_name  = aws_cloudwatch_log_group.test_log_group[0].name
  filter_pattern  = ""
  destination_arn = aws_kinesis_stream.log_stream.arn
  role_arn        = aws_iam_role.cloudwatch_logs_role.arn

  depends_on = [aws_iam_role_policy.cloudwatch_logs_policy]
}