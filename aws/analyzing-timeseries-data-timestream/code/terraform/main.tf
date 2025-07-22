# Amazon Timestream Time-Series Data Solution
# This configuration creates a complete time-series data solution using Amazon Timestream
# for IoT sensor data ingestion, storage, and analytics

# === DATA SOURCES ===

# Get current AWS region
data "aws_region" "current" {}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# === RANDOM SUFFIX FOR UNIQUE NAMING ===

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# === LOCAL VALUES ===

locals {
  # Generate resource names with random suffix
  database_name       = var.database_name != null ? var.database_name : "${var.project_name}-db-${random_id.suffix.hex}"
  lambda_function_name = var.lambda_function_name != null ? var.lambda_function_name : "${var.project_name}-ingestion-${random_id.suffix.hex}"
  iot_rule_name       = var.iot_rule_name != null ? var.iot_rule_name : "${replace(var.project_name, "-", "_")}_rule_${random_id.suffix.hex}"
  rejected_data_bucket = var.rejected_data_bucket_name != null ? var.rejected_data_bucket_name : "${var.project_name}-rejected-data-${random_id.suffix.hex}"
  
  # Common tags
  common_tags = merge(var.additional_tags, {
    Name = "${var.project_name}-${var.environment}"
  })
}

# === S3 BUCKET FOR REJECTED DATA ===

# S3 bucket for storing rejected Timestream records
resource "aws_s3_bucket" "rejected_data" {
  count  = var.enable_rejected_data_location ? 1 : 0
  bucket = local.rejected_data_bucket

  tags = merge(local.common_tags, {
    Purpose = "timestream-rejected-data-storage"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "rejected_data" {
  count  = var.enable_rejected_data_location ? 1 : 0
  bucket = aws_s3_bucket.rejected_data[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "rejected_data" {
  count  = var.enable_rejected_data_location ? 1 : 0
  bucket = aws_s3_bucket.rejected_data[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "rejected_data" {
  count  = var.enable_rejected_data_location ? 1 : 0
  bucket = aws_s3_bucket.rejected_data[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# === TIMESTREAM DATABASE ===

# Timestream database for storing time-series IoT data
resource "aws_timestreamwrite_database" "iot_database" {
  database_name = local.database_name

  # KMS encryption configuration
  dynamic "kms_key_id" {
    for_each = var.enable_kms_encryption ? [1] : []
    content {
      kms_key_id = var.kms_key_id
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "iot-time-series-data-storage"
    Service = "timestream-database"
  })
}

# === TIMESTREAM TABLE ===

# Timestream table for sensor data with retention policies
resource "aws_timestreamwrite_table" "sensor_data" {
  database_name = aws_timestreamwrite_database.iot_database.database_name
  table_name    = var.table_name

  # Retention properties for memory and magnetic stores
  retention_properties {
    memory_store_retention_period_in_hours  = var.memory_store_retention_hours
    magnetic_store_retention_period_in_days = var.magnetic_store_retention_days
  }

  # Magnetic store write properties with S3 rejected data location
  dynamic "magnetic_store_write_properties" {
    for_each = var.enable_magnetic_store_writes ? [1] : []
    content {
      enable_magnetic_store_writes = var.enable_magnetic_store_writes
      
      # Configure S3 location for rejected records
      dynamic "magnetic_store_rejected_data_location" {
        for_each = var.enable_rejected_data_location ? [1] : []
        content {
          s3_configuration {
            bucket_name       = aws_s3_bucket.rejected_data[0].bucket
            object_key_prefix = var.rejected_data_prefix
            encryption_option = "SSE_S3"
          }
        }
      }
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "sensor-data-table"
    Service = "timestream-table"
  })

  depends_on = [aws_timestreamwrite_database.iot_database]
}

# === LAMBDA FUNCTION FOR DATA INGESTION ===

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      database_name = aws_timestreamwrite_database.iot_database.database_name
      table_name    = aws_timestreamwrite_table.sensor_data.table_name
    })
    filename = "index.py"
  }
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Purpose = "lambda-function-logs"
    Service = "cloudwatch-logs"
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${local.lambda_function_name}-role"

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
    Purpose = "lambda-execution-role"
    Service = "iam-role"
  })
}

# IAM policy for Lambda to access Timestream
resource "aws_iam_policy" "lambda_timestream_policy" {
  name        = "${local.lambda_function_name}-timestream-policy"
  description = "IAM policy for Lambda function to write to Timestream"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "timestream:WriteRecords",
          "timestream:DescribeEndpoints"
        ]
        Resource = [
          aws_timestreamwrite_database.iot_database.arn,
          aws_timestreamwrite_table.sensor_data.arn
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

  tags = merge(local.common_tags, {
    Purpose = "lambda-timestream-access"
    Service = "iam-policy"
  })
}

# Attach policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_timestream_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_timestream_policy.arn
}

# Lambda function for data ingestion
resource "aws_lambda_function" "data_ingestion" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DATABASE_NAME = aws_timestreamwrite_database.iot_database.database_name
      TABLE_NAME    = aws_timestreamwrite_table.sensor_data.table_name
      AWS_REGION    = data.aws_region.current.name
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "timestream-data-ingestion"
    Service = "lambda-function"
  })

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy_attachment.lambda_timestream_attachment
  ]
}

# === IOT CORE RULE ===

# IAM role for IoT Core to access Timestream
resource "aws_iam_role" "iot_timestream_role" {
  name = "${local.iot_rule_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Purpose = "iot-timestream-access-role"
    Service = "iam-role"
  })
}

# IAM policy for IoT Core to write to Timestream
resource "aws_iam_policy" "iot_timestream_policy" {
  name        = "${local.iot_rule_name}-timestream-policy"
  description = "IAM policy for IoT Core to write to Timestream"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "timestream:WriteRecords",
          "timestream:DescribeEndpoints"
        ]
        Resource = [
          aws_timestreamwrite_database.iot_database.arn,
          aws_timestreamwrite_table.sensor_data.arn
        ]
      }
    ]
  })

  tags = merge(local.common_tags, {
    Purpose = "iot-timestream-access"
    Service = "iam-policy"
  })
}

# Attach policy to IoT role
resource "aws_iam_role_policy_attachment" "iot_timestream_attachment" {
  role       = aws_iam_role.iot_timestream_role.name
  policy_arn = aws_iam_policy.iot_timestream_policy.arn
}

# IoT Core rule for routing sensor data to Timestream
resource "aws_iot_topic_rule" "sensor_data_rule" {
  name        = local.iot_rule_name
  description = "Route IoT sensor data to Timestream database"
  enabled     = true
  sql         = "SELECT device_id, location, timestamp, temperature, humidity, pressure FROM '${var.iot_topic_pattern}'"
  sql_version = var.iot_sql_version

  # Timestream action for direct data ingestion
  timestream {
    database_name = aws_timestreamwrite_database.iot_database.database_name
    table_name    = aws_timestreamwrite_table.sensor_data.table_name
    role_arn      = aws_iam_role.iot_timestream_role.arn

    # Define dimensions (metadata) for time-series data
    dimension {
      name  = "device_id"
      value = "$${device_id}"
    }

    dimension {
      name  = "location"
      value = "$${location}"
    }

    # Optional: Add timestamp if provided in the message
    dynamic "timestamp" {
      for_each = ["timestamp"]
      content {
        value = "$${timestamp}"
        unit  = "MILLISECONDS"
      }
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "iot-sensor-data-routing"
    Service = "iot-topic-rule"
  })

  depends_on = [aws_iam_role_policy_attachment.iot_timestream_attachment]
}

# === CLOUDWATCH MONITORING ===

# CloudWatch alarm for Timestream ingestion latency
resource "aws_cloudwatch_metric_alarm" "ingestion_latency" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "Timestream-IngestionLatency-${local.database_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "SuccessfulRequestLatency"
  namespace           = "AWS/Timestream"
  period              = 300
  statistic           = "Average"
  threshold           = var.ingestion_latency_threshold_ms
  alarm_description   = "Monitor Timestream ingestion latency"
  alarm_unit          = "Milliseconds"

  dimensions = {
    DatabaseName = aws_timestreamwrite_database.iot_database.database_name
    TableName    = aws_timestreamwrite_table.sensor_data.table_name
    Operation    = "WriteRecords"
  }

  tags = merge(local.common_tags, {
    Purpose = "timestream-ingestion-monitoring"
    Service = "cloudwatch-alarm"
  })
}

# CloudWatch alarm for Timestream query latency
resource "aws_cloudwatch_metric_alarm" "query_latency" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "Timestream-QueryLatency-${local.database_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "QueryLatency"
  namespace           = "AWS/Timestream"
  period              = 300
  statistic           = "Average"
  threshold           = var.query_latency_threshold_ms
  alarm_description   = "Monitor Timestream query latency"
  alarm_unit          = "Milliseconds"

  dimensions = {
    DatabaseName = aws_timestreamwrite_database.iot_database.database_name
  }

  tags = merge(local.common_tags, {
    Purpose = "timestream-query-monitoring"
    Service = "cloudwatch-alarm"
  })
}

# CloudWatch alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "Lambda-Errors-${local.lambda_function_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Monitor Lambda function errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.data_ingestion.function_name
  }

  tags = merge(local.common_tags, {
    Purpose = "lambda-error-monitoring"
    Service = "cloudwatch-alarm"
  })
}

# CloudWatch alarm for Lambda function duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "Lambda-Duration-${local.lambda_function_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = var.lambda_timeout * 1000 * 0.8  # 80% of timeout in milliseconds
  alarm_description   = "Monitor Lambda function duration approaching timeout"
  alarm_unit          = "Milliseconds"

  dimensions = {
    FunctionName = aws_lambda_function.data_ingestion.function_name
  }

  tags = merge(local.common_tags, {
    Purpose = "lambda-duration-monitoring"
    Service = "cloudwatch-alarm"
  })
}

# === VPC ENDPOINT (OPTIONAL) ===

# VPC endpoint for Timestream (optional for private connectivity)
resource "aws_vpc_endpoint" "timestream" {
  count = var.enable_vpc_endpoint ? 1 : 0

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.timestream.ingest-cell1"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  private_dns_enabled = true

  security_group_ids = [aws_security_group.timestream_vpc_endpoint[0].id]

  tags = merge(local.common_tags, {
    Purpose = "timestream-vpc-endpoint"
    Service = "vpc-endpoint"
  })
}

# Security group for Timestream VPC endpoint
resource "aws_security_group" "timestream_vpc_endpoint" {
  count = var.enable_vpc_endpoint ? 1 : 0

  name_prefix = "${var.project_name}-timestream-endpoint-"
  vpc_id      = var.vpc_id
  description = "Security group for Timestream VPC endpoint"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]  # Adjust based on your VPC CIDR
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Purpose = "timestream-vpc-endpoint-security"
    Service = "security-group"
  })
}