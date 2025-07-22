# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate unique suffix for resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  suffix      = random_string.suffix.result
  
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# S3 bucket for IoT data storage
resource "aws_s3_bucket" "iot_data" {
  bucket = "${local.name_prefix}-data-${local.suffix}"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-data-bucket"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "iot_data" {
  bucket = aws_s3_bucket.iot_data.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "iot_data" {
  bucket = aws_s3_bucket.iot_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "iot_data" {
  bucket = aws_s3_bucket.iot_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "iot_data" {
  bucket = aws_s3_bucket.iot_data.id

  rule {
    id     = "iot_data_lifecycle"
    status = "Enabled"

    transition {
      days          = var.s3_lifecycle_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_lifecycle_days * 3
      storage_class = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# Kinesis Data Stream for IoT data
resource "aws_kinesis_stream" "iot_data" {
  name        = "${local.name_prefix}-stream-${local.suffix}"
  shard_count = var.kinesis_shard_count

  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords",
  ]

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kinesis-stream"
  })
}

# IAM role for IoT Rules Engine to access Kinesis
resource "aws_iam_role" "iot_kinesis_role" {
  name = "${local.name_prefix}-iot-kinesis-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "iot.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-iot-kinesis-role"
  })
}

# IAM policy for IoT to access Kinesis
resource "aws_iam_policy" "iot_kinesis_policy" {
  name        = "${local.name_prefix}-iot-kinesis-policy-${local.suffix}"
  description = "Policy for IoT Rules Engine to access Kinesis"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecords"
        ]
        Resource = aws_kinesis_stream.iot_data.arn
      }
    ]
  })

  tags = local.common_tags
}

# Attach policy to IoT role
resource "aws_iam_role_policy_attachment" "iot_kinesis_policy" {
  role       = aws_iam_role.iot_kinesis_role.name
  policy_arn = aws_iam_policy.iot_kinesis_policy.arn
}

# IAM role for Kinesis Data Firehose
resource "aws_iam_role" "firehose_delivery_role" {
  name = "${local.name_prefix}-firehose-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-firehose-role"
  })
}

# IAM policy for Firehose to access S3
resource "aws_iam_policy" "firehose_s3_policy" {
  name        = "${local.name_prefix}-firehose-s3-policy-${local.suffix}"
  description = "Policy for Firehose to access S3"

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
          aws_s3_bucket.iot_data.arn,
          "${aws_s3_bucket.iot_data.arn}/*"
        ]
      }
    ]
  })

  tags = local.common_tags
}

# Attach S3 policy to Firehose role
resource "aws_iam_role_policy_attachment" "firehose_s3_policy" {
  role       = aws_iam_role.firehose_delivery_role.name
  policy_arn = aws_iam_policy.firehose_s3_policy.arn
}

# IAM policy for Firehose to access Kinesis
resource "aws_iam_policy" "firehose_kinesis_policy" {
  name        = "${local.name_prefix}-firehose-kinesis-policy-${local.suffix}"
  description = "Policy for Firehose to access Kinesis"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards"
        ]
        Resource = aws_kinesis_stream.iot_data.arn
      }
    ]
  })

  tags = local.common_tags
}

# Attach Kinesis policy to Firehose role
resource "aws_iam_role_policy_attachment" "firehose_kinesis_policy" {
  role       = aws_iam_role.firehose_delivery_role.name
  policy_arn = aws_iam_policy.firehose_kinesis_policy.arn
}

# Kinesis Data Firehose delivery stream
resource "aws_kinesis_firehose_delivery_stream" "iot_data" {
  name        = "${local.name_prefix}-firehose-${local.suffix}"
  destination = "s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.iot_data.arn
    role_arn           = aws_iam_role.firehose_delivery_role.arn
  }

  s3_configuration {
    role_arn           = aws_iam_role.firehose_delivery_role.arn
    bucket_arn         = aws_s3_bucket.iot_data.arn
    prefix             = "iot-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "error-data/"
    buffer_size        = var.firehose_buffer_size
    buffer_interval    = var.firehose_buffer_interval
    compression_format = "GZIP"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-firehose-stream"
  })
}

# IoT policy for device connectivity
resource "aws_iot_policy" "device_policy" {
  name = "${local.name_prefix}-device-policy-${local.suffix}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iot:Connect",
          "iot:Publish"
        ]
        Resource = "*"
      }
    ]
  })
}

# IoT thing type for sensors
resource "aws_iot_thing_type" "sensor_device" {
  name = "${local.name_prefix}-sensor-type-${local.suffix}"
  
  thing_type_properties {
    description = "IoT Thing Type for sensor devices"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sensor-thing-type"
  })
}

# IoT thing representing a sensor device
resource "aws_iot_thing" "sensor_device" {
  name           = "${local.name_prefix}-sensor-${local.suffix}"
  thing_type_name = aws_iot_thing_type.sensor_device.name

  attributes = {
    deviceType = "sensor"
    location   = "factory-floor"
  }
}

# IoT topic rule to route messages to Kinesis
resource "aws_iot_topic_rule" "route_to_kinesis" {
  name        = "${replace(local.name_prefix, "-", "_")}_route_to_kinesis_${local.suffix}"
  description = "Route IoT sensor data to Kinesis Data Streams"
  enabled     = true
  sql         = "SELECT *, timestamp() as event_time FROM '${var.iot_topic_name}'"
  sql_version = "2016-03-23"

  kinesis {
    stream_name = aws_kinesis_stream.iot_data.name
    role_arn    = aws_iam_role.iot_kinesis_role.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-iot-rule"
  })
}

# Glue database for data catalog
resource "aws_glue_catalog_database" "iot_analytics" {
  name        = "${replace(local.name_prefix, "-", "_")}_analytics_db_${local.suffix}"
  description = "Database for IoT sensor data analytics"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-glue-database"
  })
}

# Glue table for IoT sensor data
resource "aws_glue_catalog_table" "iot_sensor_data" {
  name          = "iot_sensor_data"
  database_name = aws_glue_catalog_database.iot_analytics.name
  description   = "Table for IoT sensor data"

  table_type = "EXTERNAL_TABLE"

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.iot_data.bucket}/iot-data/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "device_id"
      type = "string"
    }

    columns {
      name = "temperature"
      type = "int"
    }

    columns {
      name = "humidity"
      type = "int"
    }

    columns {
      name = "pressure"
      type = "int"
    }

    columns {
      name = "timestamp"
      type = "string"
    }

    columns {
      name = "event_time"
      type = "bigint"
    }
  }

  partition_keys {
    name = "year"
    type = "string"
  }

  partition_keys {
    name = "month"
    type = "string"
  }

  partition_keys {
    name = "day"
    type = "string"
  }

  partition_keys {
    name = "hour"
    type = "string"
  }
}

# QuickSight account subscription (if not already exists)
resource "aws_quicksight_account_subscription" "iot_analytics" {
  count             = var.quicksight_edition != "" ? 1 : 0
  edition           = var.quicksight_edition
  authentication_method = "IAM_AND_QUICKSIGHT"
  account_name      = "${local.name_prefix}-analytics-account"
  notification_email = var.quicksight_notification_email
}

# QuickSight data source for Athena
resource "aws_quicksight_data_source" "iot_athena" {
  data_source_id = "${local.name_prefix}-athena-datasource-${local.suffix}"
  name           = "IoT Analytics Data Source"
  type           = "ATHENA"

  parameters {
    athena {
      work_group = "primary"
    }
  }

  permission {
    principal = "arn:aws:quicksight:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:user/default/${local.name_prefix}-quicksight-user"
    actions = [
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:PassDataSource"
    ]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-quicksight-datasource"
  })

  depends_on = [aws_quicksight_account_subscription.iot_analytics]
}

# QuickSight dataset for IoT sensor data
resource "aws_quicksight_data_set" "iot_sensor_dataset" {
  data_set_id = "${local.name_prefix}-sensor-dataset-${local.suffix}"
  name        = "IoT Sensor Dataset"

  physical_table_map {
    physical_table_id = "iot_data"
    relational_table {
      data_source_arn = aws_quicksight_data_source.iot_athena.arn
      catalog         = "AwsDataCatalog"
      schema          = aws_glue_catalog_database.iot_analytics.name
      name            = aws_glue_catalog_table.iot_sensor_data.name
      input_columns {
        name = "device_id"
        type = "STRING"
      }
      input_columns {
        name = "temperature"
        type = "INTEGER"
      }
      input_columns {
        name = "humidity"
        type = "INTEGER"
      }
      input_columns {
        name = "pressure"
        type = "INTEGER"
      }
      input_columns {
        name = "timestamp"
        type = "STRING"
      }
      input_columns {
        name = "event_time"
        type = "INTEGER"
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-quicksight-dataset"
  })

  depends_on = [aws_quicksight_data_source.iot_athena]
}

# CloudWatch log group for IoT topic rule
resource "aws_cloudwatch_log_group" "iot_rule_logs" {
  name              = "/aws/iot/rule/${aws_iot_topic_rule.route_to_kinesis.name}"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-iot-rule-logs"
  })
}

# CloudWatch log group for Kinesis Firehose
resource "aws_cloudwatch_log_group" "firehose_logs" {
  name              = "/aws/kinesisfirehose/${aws_kinesis_firehose_delivery_stream.iot_data.name}"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-firehose-logs"
  })
}