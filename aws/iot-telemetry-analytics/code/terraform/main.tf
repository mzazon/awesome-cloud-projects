# Main Terraform configuration for IoT Analytics Pipeline

# Generate random suffix for resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Use provided suffix or generate random one
  suffix = var.random_suffix != "" ? var.random_suffix : random_string.suffix.result
  
  # Resource names
  channel_name     = "${var.project_name}-channel-${local.suffix}"
  pipeline_name    = "${var.project_name}-pipeline-${local.suffix}"
  datastore_name   = "${var.project_name}-datastore-${local.suffix}"
  dataset_name     = "${var.project_name}-dataset-${local.suffix}"
  kinesis_name     = "${var.project_name}-stream-${local.suffix}"
  timestream_db    = "${var.project_name}-db-${local.suffix}"
  timestream_table = "sensor-data"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ============================================================================
# IAM ROLES AND POLICIES
# ============================================================================

# IAM role for IoT Analytics
resource "aws_iam_role" "iot_analytics_role" {
  name = "IoTAnalyticsServiceRole-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "iotanalytics.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach AWS managed policy for IoT Analytics
resource "aws_iam_role_policy_attachment" "iot_analytics_policy" {
  role       = aws_iam_role.iot_analytics_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSIoTAnalyticsServiceRole"
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "LambdaTimestreamRole-${local.suffix}"

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

# Attach basic execution policy for Lambda
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach Kinesis read policy for Lambda
resource "aws_iam_role_policy_attachment" "lambda_kinesis_read" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole"
}

# Custom policy for Lambda to write to Timestream
resource "aws_iam_role_policy" "lambda_timestream_policy" {
  name = "LambdaTimestreamPolicy-${local.suffix}"
  role = aws_iam_role.lambda_role.id

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
}

# IAM role for IoT Rule
resource "aws_iam_role" "iot_rule_role" {
  name = "IoTRuleRole-${local.suffix}"

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

  tags = local.common_tags
}

# Policy for IoT Rule to access IoT Analytics and Kinesis
resource "aws_iam_role_policy" "iot_rule_policy" {
  name = "IoTRulePolicy-${local.suffix}"
  role = aws_iam_role.iot_rule_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iotanalytics:BatchPutMessage"
        ]
        Resource = aws_iotanalytics_channel.sensor_channel.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecords"
        ]
        Resource = aws_kinesis_stream.sensor_stream.arn
      }
    ]
  })
}

# ============================================================================
# AWS IOT ANALYTICS RESOURCES (LEGACY - DEPRECATED)
# ============================================================================

# IoT Analytics Channel - collects raw IoT data
resource "aws_iotanalytics_channel" "sensor_channel" {
  name = local.channel_name

  # Configure retention period
  retention_period {
    unlimited = var.iot_analytics_channel_retention_unlimited
  }

  tags = local.common_tags
}

# IoT Analytics Datastore - stores processed data
resource "aws_iotanalytics_datastore" "sensor_datastore" {
  name = local.datastore_name

  # Configure retention period
  retention_period {
    unlimited = var.iot_analytics_datastore_retention_unlimited
  }

  tags = local.common_tags
}

# IoT Analytics Pipeline - processes data from channel to datastore
resource "aws_iotanalytics_pipeline" "sensor_pipeline" {
  name = local.pipeline_name

  # Pipeline activities define the data transformation workflow
  pipeline_activities {
    # Channel activity - input from IoT Analytics channel
    channel {
      name         = "ChannelActivity"
      channel_name = aws_iotanalytics_channel.sensor_channel.name
      next         = "FilterActivity"
    }

    # Filter activity - remove invalid temperature readings
    filter {
      name   = "FilterActivity"
      filter = "temperature > ${var.temperature_filter_min} AND temperature < ${var.temperature_filter_max}"
      next   = "MathActivity"
    }

    # Math activity - create calculated field
    math {
      name      = "MathActivity"
      attribute = "temperature_celsius"
      math      = "temperature"
      next      = "AddAttributesActivity"
    }

    # Add attributes activity - enrich data with metadata
    add_attributes {
      name = "AddAttributesActivity"
      attributes = {
        location    = var.device_location
        device_type = var.device_type
      }
      next = "DatastoreActivity"
    }

    # Datastore activity - output to IoT Analytics datastore
    datastore {
      name           = "DatastoreActivity"
      datastore_name = aws_iotanalytics_datastore.sensor_datastore.name
    }
  }

  tags = local.common_tags
}

# IoT Analytics Dataset - provides SQL interface for querying data
resource "aws_iotanalytics_dataset" "sensor_dataset" {
  name = local.dataset_name

  # SQL query action to analyze high temperature readings
  actions {
    action_name = "SqlAction"
    query_action {
      sql_query = "SELECT * FROM ${aws_iotanalytics_datastore.sensor_datastore.name} WHERE temperature_celsius > 25 ORDER BY timestamp DESC LIMIT 100"
    }
  }

  # Schedule dataset to run hourly
  triggers {
    schedule {
      expression = var.iot_analytics_dataset_schedule
    }
  }

  tags = local.common_tags
}

# ============================================================================
# MODERN ALTERNATIVE: KINESIS + LAMBDA + TIMESTREAM
# ============================================================================

# Kinesis Data Stream - real-time data ingestion
resource "aws_kinesis_stream" "sensor_stream" {
  name             = local.kinesis_name
  shard_count      = var.kinesis_shard_count
  retention_period = var.kinesis_retention_period

  # Enable encryption
  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  tags = local.common_tags
}

# Timestream Database - time-series data storage
resource "aws_timestreamwrite_database" "iot_database" {
  database_name = local.timestream_db

  tags = local.common_tags
}

# Timestream Table - sensor data table
resource "aws_timestreamwrite_table" "sensor_data" {
  database_name = aws_timestreamwrite_database.iot_database.database_name
  table_name    = local.timestream_table

  retention_properties {
    memory_store_retention_period_in_hours  = var.timestream_memory_retention_hours
    magnetic_store_retention_period_in_days = var.timestream_magnetic_retention_days
  }

  tags = local.common_tags
}

# Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      timestream_database = aws_timestreamwrite_database.iot_database.database_name
      timestream_table    = aws_timestreamwrite_table.sensor_data.table_name
      device_location     = var.device_location
    })
    filename = "lambda_function.py"
  }
}

# Lambda function - processes Kinesis data and writes to Timestream
resource "aws_lambda_function" "process_iot_data" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "ProcessIoTData-${local.suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TIMESTREAM_DATABASE = aws_timestreamwrite_database.iot_database.database_name
      TIMESTREAM_TABLE    = aws_timestreamwrite_table.sensor_data.table_name
      DEVICE_LOCATION     = var.device_location
    }
  }

  tags = local.common_tags
}

# Event source mapping - connects Kinesis to Lambda
resource "aws_lambda_event_source_mapping" "kinesis_trigger" {
  event_source_arn  = aws_kinesis_stream.sensor_stream.arn
  function_name     = aws_lambda_function.process_iot_data.arn
  starting_position = "LATEST"
  batch_size        = 100
  
  depends_on = [aws_iam_role_policy_attachment.lambda_kinesis_read]
}

# ============================================================================
# IOT RULES ENGINE
# ============================================================================

# IoT Topic Rule - routes sensor data to both IoT Analytics and Kinesis
resource "aws_iot_topic_rule" "sensor_data_rule" {
  name        = "IoTAnalyticsRule${replace(local.suffix, "-", "")}"
  description = var.iot_rule_description
  enabled     = true
  sql         = "SELECT * FROM '${var.iot_topic_name}'"
  sql_version = "2016-03-23"

  # Route to IoT Analytics Channel (Legacy)
  iot_analytics {
    channel_name = aws_iotanalytics_channel.sensor_channel.name
    role_arn     = aws_iam_role.iot_rule_role.arn
  }

  # Route to Kinesis Data Stream (Modern Alternative)
  kinesis {
    stream_name   = aws_kinesis_stream.sensor_stream.name
    partition_key = "$${deviceId}"
    role_arn      = aws_iam_role.iot_rule_role.arn
  }

  tags = local.common_tags
}