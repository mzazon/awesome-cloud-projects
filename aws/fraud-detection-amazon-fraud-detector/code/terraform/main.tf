# Generate random suffix for resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

# S3 bucket for fraud detection data and models
resource "aws_s3_bucket" "fraud_detection" {
  bucket = "${var.project_name}-platform-${random_string.suffix.result}"

  tags = merge(var.default_tags, {
    Name        = "${var.project_name}-platform-${random_string.suffix.result}"
    Description = "S3 bucket for fraud detection training data and models"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "fraud_detection" {
  bucket = aws_s3_bucket.fraud_detection.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "fraud_detection" {
  bucket = aws_s3_bucket.fraud_detection.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "fraud_detection" {
  bucket = aws_s3_bucket.fraud_detection.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Kinesis stream for real-time transaction processing
resource "aws_kinesis_stream" "fraud_transactions" {
  name             = "${var.project_name}-transaction-stream-${random_string.suffix.result}"
  shard_count      = var.kinesis_shard_count
  retention_period = 24

  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords",
  ]

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  tags = merge(var.default_tags, {
    Name        = "${var.project_name}-transaction-stream-${random_string.suffix.result}"
    Description = "Kinesis stream for real-time transaction processing"
  })
}

# DynamoDB table for fraud decisions logging
resource "aws_dynamodb_table" "fraud_decisions" {
  name           = "${var.project_name}-decisions-${random_string.suffix.result}"
  billing_mode   = "PROVISIONED"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "transaction_id"
  range_key      = "timestamp"

  attribute {
    name = "transaction_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  attribute {
    name = "customer_id"
    type = "S"
  }

  global_secondary_index {
    name            = "customer-index"
    hash_key        = "customer_id"
    projection_type = "ALL"
    read_capacity   = var.dynamodb_read_capacity / 2
    write_capacity  = var.dynamodb_write_capacity / 2
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(var.default_tags, {
    Name        = "${var.project_name}-decisions-${random_string.suffix.result}"
    Description = "DynamoDB table for fraud decisions logging"
  })
}

# SNS topic for fraud alerts
resource "aws_sns_topic" "fraud_alerts" {
  name = "${var.project_name}-alerts-${random_string.suffix.result}"

  kms_master_key_id = "alias/aws/sns"

  tags = merge(var.default_tags, {
    Name        = "${var.project_name}-alerts-${random_string.suffix.result}"
    Description = "SNS topic for fraud detection alerts"
  })
}

# SNS topic subscription for email alerts
resource "aws_sns_topic_subscription" "fraud_alerts_email" {
  topic_arn = aws_sns_topic.fraud_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# IAM role for Amazon Fraud Detector
resource "aws_iam_role" "fraud_detector_role" {
  name = "${var.project_name}-fraud-detector-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "frauddetector.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.default_tags, {
    Name        = "${var.project_name}-fraud-detector-role-${random_string.suffix.result}"
    Description = "IAM role for Amazon Fraud Detector"
  })
}

# IAM policy for Fraud Detector
resource "aws_iam_role_policy" "fraud_detector_policy" {
  name = "${var.project_name}-fraud-detector-policy"
  role = aws_iam_role.fraud_detector_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.fraud_detection.arn,
          "${aws_s3_bucket.fraud_detection.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "frauddetector:*",
          "kinesis:PutRecord",
          "kinesis:PutRecords",
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.default_tags, {
    Name        = "${var.project_name}-lambda-role-${random_string.suffix.result}"
    Description = "IAM role for Lambda functions"
  })
}

# IAM policy attachments for Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_kinesis_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole"
}

# Custom IAM policy for Lambda functions
resource "aws_iam_role_policy" "lambda_custom_policy" {
  name = "${var.project_name}-lambda-custom-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "frauddetector:GetEventPrediction",
          "frauddetector:GetDetectors",
          "frauddetector:GetModels"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.fraud_decisions.arn,
          "${aws_dynamodb_table.fraud_decisions.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.fraud_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:*"
      }
    ]
  })
}

# CloudWatch Log Group for event enrichment Lambda
resource "aws_cloudwatch_log_group" "event_enrichment_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${var.project_name}-event-enrichment-${random_string.suffix.result}"
  retention_in_days = var.log_retention_days

  tags = merge(var.default_tags, {
    Name        = "/aws/lambda/${var.project_name}-event-enrichment-${random_string.suffix.result}"
    Description = "CloudWatch logs for event enrichment Lambda function"
  })
}

# CloudWatch Log Group for fraud detection processor Lambda
resource "aws_cloudwatch_log_group" "fraud_processor_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${var.project_name}-fraud-processor-${random_string.suffix.result}"
  retention_in_days = var.log_retention_days

  tags = merge(var.default_tags, {
    Name        = "/aws/lambda/${var.project_name}-fraud-processor-${random_string.suffix.result}"
    Description = "CloudWatch logs for fraud detection processor Lambda function"
  })
}

# Lambda function code archive for event enrichment
data "archive_file" "event_enrichment_zip" {
  type        = "zip"
  output_path = "${path.module}/event_enrichment_lambda.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/event_enrichment_lambda.py", {
      project_name = var.project_name
    })
    filename = "lambda_function.py"
  }
}

# Lambda function code archive for fraud detection processor
data "archive_file" "fraud_processor_zip" {
  type        = "zip"
  output_path = "${path.module}/fraud_detection_processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/fraud_detection_processor.py", {
      project_name = var.project_name
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for event enrichment
resource "aws_lambda_function" "event_enrichment" {
  filename         = data.archive_file.event_enrichment_zip.output_path
  function_name    = "${var.project_name}-event-enrichment-${random_string.suffix.result}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.event_enrichment_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_enrichment_memory

  environment {
    variables = {
      DECISIONS_TABLE       = aws_dynamodb_table.fraud_decisions.name
      TARGET_LAMBDA_FUNCTION = "${var.project_name}-fraud-processor-${random_string.suffix.result}"
    }
  }

  depends_on = [
    var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.event_enrichment_logs[0] : null,
    aws_iam_role_policy_attachment.lambda_basic_execution,
  ]

  tags = merge(var.default_tags, {
    Name        = "${var.project_name}-event-enrichment-${random_string.suffix.result}"
    Description = "Lambda function for transaction event enrichment"
  })
}

# Lambda function for fraud detection processing
resource "aws_lambda_function" "fraud_processor" {
  filename         = data.archive_file.fraud_processor_zip.output_path
  function_name    = "${var.project_name}-fraud-processor-${random_string.suffix.result}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.fraud_processor_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_processor_memory

  environment {
    variables = {
      DETECTOR_NAME       = "${var.project_name}-detector-${random_string.suffix.result}"
      EVENT_TYPE_NAME     = "${var.project_name}-event-type-${random_string.suffix.result}"
      ENTITY_TYPE_NAME    = "${var.project_name}-entity-type-${random_string.suffix.result}"
      DECISIONS_TABLE     = aws_dynamodb_table.fraud_decisions.name
      SNS_TOPIC_ARN       = aws_sns_topic.fraud_alerts.arn
      HIGH_RISK_THRESHOLD = var.high_risk_score_threshold
      MEDIUM_RISK_THRESHOLD = var.medium_risk_score_threshold
      LOW_RISK_THRESHOLD  = var.low_risk_score_threshold
    }
  }

  depends_on = [
    var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.fraud_processor_logs[0] : null,
    aws_iam_role_policy_attachment.lambda_basic_execution,
  ]

  tags = merge(var.default_tags, {
    Name        = "${var.project_name}-fraud-processor-${random_string.suffix.result}"
    Description = "Lambda function for fraud detection processing"
  })
}

# Kinesis event source mapping for Lambda
resource "aws_lambda_event_source_mapping" "kinesis_lambda" {
  event_source_arn  = aws_kinesis_stream.fraud_transactions.arn
  function_name     = aws_lambda_function.event_enrichment.function_name
  starting_position = "LATEST"
  batch_size        = 10
  
  depends_on = [aws_iam_role_policy_attachment.lambda_kinesis_execution]
}

# CloudWatch Dashboard for fraud detection monitoring
resource "aws_cloudwatch_dashboard" "fraud_detection" {
  count          = var.enable_enhanced_monitoring ? 1 : 0
  dashboard_name = "${var.project_name}-platform-${random_string.suffix.result}"

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
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.fraud_processor.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.fraud_processor.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.fraud_processor.function_name]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Fraud Detection Lambda Metrics"
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
            ["AWS/Kinesis", "IncomingRecords", "StreamName", aws_kinesis_stream.fraud_transactions.name],
            ["AWS/Kinesis", "OutgoingRecords", "StreamName", aws_kinesis_stream.fraud_transactions.name]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Transaction Stream Metrics"
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
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.fraud_decisions.name],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", aws_dynamodb_table.fraud_decisions.name]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Decision Storage Metrics"
        }
      }
    ]
  })
}

# Local file to store entity and event type names for manual fraud detector setup
resource "local_file" "fraud_detector_config" {
  content = jsonencode({
    entity_type_name = "${var.project_name}-entity-type-${random_string.suffix.result}"
    event_type_name  = "${var.project_name}-event-type-${random_string.suffix.result}"
    model_name       = "${var.project_name}-model-${random_string.suffix.result}"
    detector_name    = "${var.project_name}-detector-${random_string.suffix.result}"
    s3_bucket        = aws_s3_bucket.fraud_detection.bucket
    training_data_path = var.fraud_model_training_data_path
    fraud_detector_role_arn = aws_iam_role.fraud_detector_role.arn
  })
  filename = "${path.module}/fraud_detector_config.json"
}

# Lambda function files
resource "local_file" "event_enrichment_lambda_source" {
  content = templatefile("${path.module}/lambda_functions/event_enrichment_lambda.py", {
    project_name = var.project_name
  })
  filename = "${path.module}/lambda_functions/event_enrichment_lambda.py"
}

resource "local_file" "fraud_processor_lambda_source" {
  content = templatefile("${path.module}/lambda_functions/fraud_detection_processor.py", {
    project_name = var.project_name
  })
  filename = "${path.module}/lambda_functions/fraud_detection_processor.py"
}