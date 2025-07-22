# Smart City Digital Twins with SimSpace Weaver and IoT
# This Terraform configuration deploys a comprehensive smart city digital twin solution
# combining real-time IoT sensor data ingestion with spatial simulations

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.4"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffixes for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local variables for consistent naming and tagging
locals {
  project_name = "smartcity-${random_id.suffix.hex}"
  common_tags = {
    Project     = "Smart City Digital Twins"
    Environment = var.environment
    ManagedBy   = "Terraform"
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  }
}

#########################################
# S3 Bucket for Simulation Artifacts
#########################################

# Main S3 bucket for SimSpace Weaver simulation artifacts
resource "aws_s3_bucket" "simulation_artifacts" {
  bucket        = "${local.project_name}-simulation-artifacts"
  force_destroy = var.enable_force_destroy

  tags = merge(local.common_tags, {
    Purpose = "SimSpace Weaver simulation artifacts storage"
  })
}

# Enable versioning for simulation artifacts
resource "aws_s3_bucket_versioning" "simulation_artifacts" {
  bucket = aws_s3_bucket.simulation_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "simulation_artifacts" {
  bucket = aws_s3_bucket.simulation_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "simulation_artifacts" {
  bucket = aws_s3_bucket.simulation_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "simulation_artifacts" {
  bucket = aws_s3_bucket.simulation_artifacts.id

  rule {
    id     = "cleanup_old_artifacts"
    status = "Enabled"

    expiration {
      days = var.artifact_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

#########################################
# DynamoDB Table for Sensor Data
#########################################

# DynamoDB table for storing IoT sensor data with streams enabled
resource "aws_dynamodb_table" "sensor_data" {
  name             = "${local.project_name}-sensor-data"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "sensor_id"
  range_key        = "timestamp"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  # Define key attributes
  attribute {
    name = "sensor_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "sensor_type"
    type = "S"
  }

  attribute {
    name = "location_id"
    type = "S"
  }

  # Global Secondary Index for querying by sensor type
  global_secondary_index {
    name            = "SensorTypeIndex"
    hash_key        = "sensor_type"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  # Global Secondary Index for querying by location
  global_secondary_index {
    name            = "LocationIndex"
    hash_key        = "location_id"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  # Enable point-in-time recovery for data protection
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  tags = merge(local.common_tags, {
    Purpose = "IoT sensor data storage for digital twin"
  })
}

#########################################
# Lambda Functions
#########################################

# Create Lambda deployment packages
data "archive_file" "sensor_processor_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/sensor_processor.zip"
  source {
    content = templatefile("${path.module}/lambda_functions/sensor_processor.py", {
      table_name = aws_dynamodb_table.sensor_data.name
    })
    filename = "lambda_function.py"
  }
}

data "archive_file" "stream_processor_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/stream_processor.zip"
  source {
    content = templatefile("${path.module}/lambda_functions/stream_processor.py", {
      table_name = aws_dynamodb_table.sensor_data.name
    })
    filename = "lambda_function.py"
  }
}

data "archive_file" "analytics_processor_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/analytics_processor.zip"
  source {
    content = templatefile("${path.module}/lambda_functions/analytics_processor.py", {
      table_name = aws_dynamodb_table.sensor_data.name
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for processing IoT sensor data
resource "aws_lambda_function" "sensor_processor" {
  function_name = "${local.project_name}-sensor-processor"
  role         = aws_iam_role.lambda_execution.arn
  handler      = "lambda_function.lambda_handler"
  runtime      = "python3.12"
  filename     = data.archive_file.sensor_processor_zip.output_path
  architectures = ["arm64"]

  source_code_hash = data.archive_file.sensor_processor_zip.output_base64sha256

  memory_size = 512
  timeout     = 60

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.sensor_data.name
      LOG_LEVEL          = var.lambda_log_level
    }
  }

  # Enable X-Ray tracing for observability
  tracing_config {
    mode = "Active"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.sensor_processor,
  ]

  tags = merge(local.common_tags, {
    Purpose = "IoT sensor data processing"
  })
}

# Lambda function for processing DynamoDB stream events
resource "aws_lambda_function" "stream_processor" {
  function_name = "${local.project_name}-stream-processor"
  role         = aws_iam_role.lambda_execution.arn
  handler      = "lambda_function.lambda_handler"
  runtime      = "python3.12"
  filename     = data.archive_file.stream_processor_zip.output_path
  architectures = ["arm64"]

  source_code_hash = data.archive_file.stream_processor_zip.output_base64sha256

  memory_size = 256
  timeout     = 60

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.sensor_data.name
      LOG_LEVEL          = var.lambda_log_level
    }
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.stream_processor,
  ]

  tags = merge(local.common_tags, {
    Purpose = "DynamoDB stream processing for simulation updates"
  })
}

# Lambda function for analytics processing
resource "aws_lambda_function" "analytics_processor" {
  function_name = "${local.project_name}-analytics-processor"
  role         = aws_iam_role.analytics_lambda_execution.arn
  handler      = "lambda_function.lambda_handler"
  runtime      = "python3.12"
  filename     = data.archive_file.analytics_processor_zip.output_path
  architectures = ["arm64"]

  source_code_hash = data.archive_file.analytics_processor_zip.output_base64sha256

  memory_size = 1024
  timeout     = 300

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.sensor_data.name
      LOG_LEVEL          = var.lambda_log_level
    }
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [
    aws_iam_role_policy_attachment.analytics_lambda_basic_execution,
    aws_cloudwatch_log_group.analytics_processor,
  ]

  tags = merge(local.common_tags, {
    Purpose = "Analytics processing for smart city insights"
  })
}

#########################################
# CloudWatch Log Groups
#########################################

resource "aws_cloudwatch_log_group" "sensor_processor" {
  name              = "/aws/lambda/${local.project_name}-sensor-processor"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "stream_processor" {
  name              = "/aws/lambda/${local.project_name}-stream-processor"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "analytics_processor" {
  name              = "/aws/lambda/${local.project_name}-analytics-processor"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

#########################################
# IoT Core Resources
#########################################

# IoT Thing Group for organizing smart city sensors
resource "aws_iot_thing_group" "smart_city_sensors" {
  name = "${local.project_name}-sensors"

  properties {
    description = "Smart city sensor fleet for digital twin solution"
    attribute_payload {
      attributes = {
        project = "smart-city-digital-twin"
        type    = "sensor-group"
      }
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "IoT device organization"
  })
}

# IoT Policy for sensor devices with least privilege access
resource "aws_iot_policy" "sensor_policy" {
  name = "${local.project_name}-sensor-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["iot:Connect"]
        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:client/$${iot:Connection.Thing.ThingName}"
        Condition = {
          Bool = {
            "iot:Connection.Thing.IsAttached" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = ["iot:Publish"]
        Resource = [
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/smartcity/sensors/$${iot:Connection.Thing.ThingName}/data",
          "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/smartcity/sensors/$${iot:Connection.Thing.ThingName}/status"
        ]
      }
    ]
  })

  tags = merge(local.common_tags, {
    Purpose = "IoT device permissions"
  })
}

# IoT Topic Rule for processing sensor data
resource "aws_iot_topic_rule" "sensor_data_processing" {
  name        = replace("${local.project_name}_sensor_data_processing", "-", "_")
  description = "Route smart city sensor data to Lambda processing function"
  enabled     = true
  sql         = "SELECT *, timestamp() as ingestion_timestamp FROM 'smartcity/sensors/+/data'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.sensor_processor.arn
  }

  error_action {
    cloudwatch_logs {
      log_group_name = aws_cloudwatch_log_group.iot_errors.name
      role_arn      = aws_iam_role.iot_rule_execution.arn
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "IoT data routing"
  })
}

# CloudWatch Log Group for IoT rule errors
resource "aws_cloudwatch_log_group" "iot_errors" {
  name              = "/aws/iot/rule/${local.project_name}-errors"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# Sample IoT Thing for testing
resource "aws_iot_thing" "sample_traffic_sensor" {
  name = "${local.project_name}-traffic-sensor-001"

  attributes = {
    sensor_type = "traffic"
    location    = "intersection-main-elm"
    version     = "v1.0"
  }

  tags = merge(local.common_tags, {
    Purpose = "Sample traffic sensor for testing"
  })
}

# Add sample thing to the group
resource "aws_iot_thing_group_membership" "sample_sensor" {
  thing_name       = aws_iot_thing.sample_traffic_sensor.name
  thing_group_name = aws_iot_thing_group.smart_city_sensors.name
}

#########################################
# DynamoDB Stream Event Source Mapping
#########################################

resource "aws_lambda_event_source_mapping" "dynamodb_stream" {
  event_source_arn  = aws_dynamodb_table.sensor_data.stream_arn
  function_name     = aws_lambda_function.stream_processor.arn
  starting_position = "LATEST"

  # Batch configuration for efficient processing
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  parallelization_factor            = 2

  # Error handling configuration
  maximum_retry_attempts         = 3
  bisect_batch_on_function_error = true

  # Filter for relevant events only
  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT", "MODIFY"]
      })
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_dynamodb_stream
  ]
}

#########################################
# Lambda Permission for IoT Rule
#########################################

resource "aws_lambda_permission" "iot_invoke_sensor_processor" {
  statement_id  = "AllowIoTRuleInvocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sensor_processor.function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.sensor_data_processing.arn
}

#########################################
# Simulation Schema Upload
#########################################

# Upload simulation schema to S3
resource "aws_s3_object" "simulation_schema" {
  bucket = aws_s3_bucket.simulation_artifacts.id
  key    = "schema/simulation_schema.yaml"
  content = templatefile("${path.module}/simulation_files/simulation_schema.yaml", {
    project_name = local.project_name
  })
  content_type = "application/yaml"

  tags = merge(local.common_tags, {
    Purpose = "SimSpace Weaver simulation schema"
  })
}

# Upload sample simulation application
resource "aws_s3_object" "traffic_simulation" {
  bucket = aws_s3_bucket.simulation_artifacts.id
  key    = "apps/traffic_sim.py"
  source = "${path.module}/simulation_files/traffic_sim.py"
  etag   = filemd5("${path.module}/simulation_files/traffic_sim.py")

  tags = merge(local.common_tags, {
    Purpose = "Traffic simulation application"
  })
}

#########################################
# CloudWatch Alarms for Monitoring
#########################################

# Alarm for high error rate in sensor processing
resource "aws_cloudwatch_metric_alarm" "sensor_processor_errors" {
  alarm_name          = "${local.project_name}-sensor-processor-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors sensor processor lambda errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.sensor_processor.function_name
  }

  tags = local.common_tags
}

# Alarm for DynamoDB throttling
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  alarm_name          = "${local.project_name}-dynamodb-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UserErrors"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors DynamoDB throttling"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    TableName = aws_dynamodb_table.sensor_data.name
  }

  tags = local.common_tags
}

#########################################
# SNS Topic for Alerts
#########################################

resource "aws_sns_topic" "alerts" {
  name = "${local.project_name}-alerts"

  tags = merge(local.common_tags, {
    Purpose = "Smart city monitoring alerts"
  })
}

# Optional: Subscribe email to alerts (commented out to avoid requiring email input)
# resource "aws_sns_topic_subscription" "email_alerts" {
#   topic_arn = aws_sns_topic.alerts.arn
#   protocol  = "email"
#   endpoint  = var.alert_email
# }

#########################################
# IAM Roles and Policies
#########################################

# IAM assume role policy for Lambda
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

# IAM role for Lambda execution
resource "aws_iam_role" "lambda_execution" {
  name               = "${local.project_name}-lambda-execution-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = merge(local.common_tags, {
    Purpose = "Lambda execution role for IoT data processing"
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Lambda DynamoDB access
data "aws_iam_policy_document" "lambda_dynamodb_policy" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [
      aws_dynamodb_table.sensor_data.arn,
      "${aws_dynamodb_table.sensor_data.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_access" {
  name   = "${local.project_name}-lambda-dynamodb-policy"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_dynamodb_policy.json
}

# Custom policy for Lambda DynamoDB stream access
data "aws_iam_policy_document" "lambda_stream_policy" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:DescribeStream",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
      "dynamodb:ListStreams"
    ]
    resources = [aws_dynamodb_table.sensor_data.stream_arn]
  }
}

resource "aws_iam_role_policy" "lambda_dynamodb_stream" {
  name   = "${local.project_name}-lambda-stream-policy"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_stream_policy.json
}

# IAM role for analytics Lambda function (with additional permissions)
resource "aws_iam_role" "analytics_lambda_execution" {
  name               = "${local.project_name}-analytics-lambda-execution-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = merge(local.common_tags, {
    Purpose = "Lambda execution role for analytics processing"
  })
}

# Attach basic Lambda execution policy to analytics role
resource "aws_iam_role_policy_attachment" "analytics_lambda_basic_execution" {
  role       = aws_iam_role.analytics_lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for analytics Lambda DynamoDB access (read-only)
data "aws_iam_policy_document" "analytics_lambda_policy" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan"
    ]
    resources = [
      aws_dynamodb_table.sensor_data.arn,
      "${aws_dynamodb_table.sensor_data.arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = [
      "${aws_s3_bucket.simulation_artifacts.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "analytics_lambda_access" {
  name   = "${local.project_name}-analytics-lambda-policy"
  role   = aws_iam_role.analytics_lambda_execution.id
  policy = data.aws_iam_policy_document.analytics_lambda_policy.json
}

# IAM assume role policy for IoT rule
data "aws_iam_policy_document" "iot_assume_role" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["iot.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# IAM role for IoT rule execution
resource "aws_iam_role" "iot_rule_execution" {
  name               = "${local.project_name}-iot-rule-execution-role"
  assume_role_policy = data.aws_iam_policy_document.iot_assume_role.json

  tags = merge(local.common_tags, {
    Purpose = "IoT rule execution role for error handling"
  })
}

# Custom policy for IoT rule CloudWatch Logs access
data "aws_iam_policy_document" "iot_rule_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.iot_errors.arn}:*"]
  }
}

resource "aws_iam_role_policy" "iot_rule_logs" {
  name   = "${local.project_name}-iot-rule-logs-policy"
  role   = aws_iam_role.iot_rule_execution.id
  policy = data.aws_iam_policy_document.iot_rule_policy.json
}