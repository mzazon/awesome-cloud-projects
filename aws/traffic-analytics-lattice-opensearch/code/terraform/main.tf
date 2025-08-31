# Traffic Analytics with VPC Lattice and OpenSearch
# This Terraform configuration deploys a comprehensive traffic analytics solution
# using VPC Lattice access logs streamed through Kinesis Data Firehose to OpenSearch Service

terraform {
  required_version = ">= 1.0"
}

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_password" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  name_suffix    = random_password.suffix.result
  common_tags = {
    Project     = "traffic-analytics-lattice-opensearch"
    Environment = var.environment
    CreatedBy   = "terraform"
    Recipe      = "traffic-analytics-lattice-opensearch"
  }
}

# S3 bucket for backup and error records
resource "aws_s3_bucket" "backup" {
  bucket = "${var.project_name}-backup-${local.name_suffix}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# OpenSearch Service Domain for Analytics
resource "aws_opensearch_domain" "traffic_analytics" {
  domain_name    = "${var.project_name}-${local.name_suffix}"
  engine_version = var.opensearch_version

  cluster_config {
    instance_type  = var.opensearch_instance_type
    instance_count = var.opensearch_instance_count
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = var.opensearch_volume_size
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https = true
  }

  # Open access policy for demo purposes - restrict in production
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action   = "es:*"
        Resource = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${var.project_name}-${local.name_suffix}/*"
      }
    ]
  })

  tags = local.common_tags

  depends_on = [aws_iam_service_linked_role.opensearch]
}

# OpenSearch service-linked role
resource "aws_iam_service_linked_role" "opensearch" {
  aws_service_name = "opensearchserverless.amazonaws.com"
}

# IAM role for Lambda transformation function
resource "aws_iam_role" "lambda_transform" {
  name = "${var.project_name}-transform-role-${local.name_suffix}"

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

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_transform.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function for data transformation
resource "aws_lambda_function" "transform" {
  filename         = data.archive_file.lambda_transform.output_path
  function_name    = "${var.project_name}-transform-${local.name_suffix}"
  role            = aws_iam_role.lambda_transform.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_transform.output_base64sha256
  runtime         = "python3.12"
  timeout         = 60
  memory_size     = 256

  description = "Transform VPC Lattice access logs for OpenSearch analytics"

  tags = local.common_tags
}

# Package Lambda function code
data "archive_file" "lambda_transform" {
  type        = "zip"
  output_path = "${path.module}/transform_function.zip"
  source {
    content = templatefile("${path.module}/lambda_function.py", {})
    filename = "lambda_function.py"
  }
}

# IAM role for Kinesis Data Firehose
resource "aws_iam_role" "firehose" {
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

  tags = local.common_tags
}

# IAM policy for Firehose to access OpenSearch and S3
resource "aws_iam_role_policy" "firehose_opensearch" {
  name = "FirehoseOpenSearchPolicy"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "es:DescribeDomain",
          "es:DescribeDomains",
          "es:DescribeDomainConfig",
          "es:ESHttpPost",
          "es:ESHttpPut"
        ]
        Resource = "${aws_opensearch_domain.traffic_analytics.arn}/*"
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
          aws_s3_bucket.backup.arn,
          "${aws_s3_bucket.backup.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
          "lambda:GetFunctionConfiguration"
        ]
        Resource = aws_lambda_function.transform.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/*"
      }
    ]
  })
}

# CloudWatch log group for Firehose
resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${var.project_name}-stream-${local.name_suffix}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_stream" "firehose" {
  name           = "opensearch-delivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

# Kinesis Data Firehose delivery stream
resource "aws_kinesis_firehose_delivery_stream" "traffic_analytics" {
  name        = "${var.project_name}-stream-${local.name_suffix}"
  destination = "opensearch"

  opensearch_configuration {
    domain_arn = aws_opensearch_domain.traffic_analytics.arn
    role_arn   = aws_iam_role.firehose.arn
    index_name = "vpc-lattice-traffic"

    s3_configuration {
      role_arn        = aws_iam_role.firehose.arn
      bucket_arn      = aws_s3_bucket.backup.arn
      prefix          = "firehose-backup/"
      buffer_size     = 1
      buffer_interval = 60
      compression_format = "GZIP"
    }

    processing_configuration {
      enabled = true

      processors {
        type = "Lambda"

        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = aws_lambda_function.transform.arn
        }
      }
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose.name
    }
  }

  tags = local.common_tags
}

# VPC Lattice Service Network
resource "aws_vpclattice_service_network" "demo" {
  name      = "${var.project_name}-network-${local.name_suffix}"
  auth_type = "AWS_IAM"
  tags      = local.common_tags
}

# Demo VPC Lattice Service
resource "aws_vpclattice_service" "demo" {
  name      = "${var.project_name}-service-${local.name_suffix}"
  auth_type = "AWS_IAM"
  tags      = local.common_tags
}

# Associate service with service network
resource "aws_vpclattice_service_network_service_association" "demo" {
  service_identifier         = aws_vpclattice_service.demo.id
  service_network_identifier = aws_vpclattice_service_network.demo.id
  tags                       = local.common_tags
}

# Access log subscription for VPC Lattice
resource "aws_vpclattice_access_log_subscription" "traffic_analytics" {
  resource_identifier = aws_vpclattice_service_network.demo.arn
  destination_arn     = aws_kinesis_firehose_delivery_stream.traffic_analytics.arn
  tags                = local.common_tags
}

# CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "traffic_analytics" {
  dashboard_name = "${var.project_name}-dashboard-${local.name_suffix}"

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
            ["AWS/KinesisFirehose", "DeliveryToOpenSearch.Records", "DeliveryStreamName", aws_kinesis_firehose_delivery_stream.traffic_analytics.name],
            [".", "DeliveryToOpenSearch.Success", ".", "."],
            [".", "DeliveryToS3.Records", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Firehose Delivery Metrics"
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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.transform.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Lambda Transform Function Metrics"
          period  = 300
        }
      }
    ]
  })
}