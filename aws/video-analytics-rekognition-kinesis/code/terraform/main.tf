# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Use provided suffix or generate one
  name_suffix = var.resource_name_suffix != "" ? var.resource_name_suffix : random_string.suffix.result
  
  # Resource names
  video_stream_name   = var.video_stream_name != "" ? var.video_stream_name : "${var.project_name}-stream-${local.name_suffix}"
  face_collection_name = var.face_collection_name != "" ? var.face_collection_name : "${var.project_name}-faces-${local.name_suffix}"
  
  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    CreatedBy   = "Terraform"
    Timestamp   = timestamp()
  }
}

# KMS Key for encryption (if enabled)
resource "aws_kms_key" "video_analytics" {
  count = var.enable_encryption ? 1 : 0
  
  description             = "KMS key for video analytics encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow video analytics services"
        Effect = "Allow"
        Principal = {
          Service = [
            "kinesisvideo.amazonaws.com",
            "kinesis.amazonaws.com",
            "lambda.amazonaws.com",
            "rekognition.amazonaws.com",
            "dynamodb.amazonaws.com",
            "sns.amazonaws.com"
          ]
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-kms-key-${local.name_suffix}"
  })
}

resource "aws_kms_alias" "video_analytics" {
  count = var.enable_encryption ? 1 : 0
  
  name          = "alias/${var.project_name}-video-analytics-${local.name_suffix}"
  target_key_id = aws_kms_key.video_analytics[0].key_id
}

# IAM Role for video analytics services
resource "aws_iam_role" "video_analytics_role" {
  name = "${var.project_name}-video-analytics-role-${local.name_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "rekognition.amazonaws.com",
            "apigateway.amazonaws.com"
          ]
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM policies for video analytics role
resource "aws_iam_role_policy" "video_analytics_policy" {
  name = "${var.project_name}-video-analytics-policy-${local.name_suffix}"
  role = aws_iam_role.video_analytics_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rekognition:*",
          "kinesisvideo:*",
          "kinesis:*",
          "dynamodb:*",
          "sns:Publish",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      var.enable_encryption ? {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.video_analytics[0].arn
      } : null
    ]
  })
}

# Attach AWS managed policies
resource "aws_iam_role_policy_attachment" "rekognition_full_access" {
  role       = aws_iam_role.video_analytics_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRekognitionFullAccess"
}

resource "aws_iam_role_policy_attachment" "kinesis_video_full_access" {
  role       = aws_iam_role.video_analytics_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonKinesisVideoStreamsFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.video_analytics_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Kinesis Video Stream for video ingestion
resource "aws_kinesisvideo_stream" "video_stream" {
  name                    = local.video_stream_name
  data_retention_in_hours = var.video_retention_hours
  media_type              = var.video_media_type
  
  dynamic "kms_key_id" {
    for_each = var.enable_encryption ? [1] : []
    content {
      kms_key_id = aws_kms_key.video_analytics[0].arn
    }
  }
  
  tags = merge(local.common_tags, {
    Name = local.video_stream_name
    Type = "VideoIngestion"
  })
}

# Rekognition Face Collection
resource "aws_rekognition_collection" "face_collection" {
  collection_id = local.face_collection_name
  
  tags = merge(local.common_tags, {
    Name = local.face_collection_name
    Type = "FaceRecognition"
  })
}

# Kinesis Data Stream for analytics results
resource "aws_kinesis_stream" "analytics_stream" {
  name             = "${var.project_name}-analytics-${local.name_suffix}"
  shard_count      = var.kinesis_shard_count
  retention_period = 24
  
  dynamic "encryption_type" {
    for_each = var.enable_encryption ? [1] : []
    content {
      encryption_type = "KMS"
      key_id          = aws_kms_key.video_analytics[0].arn
    }
  }
  
  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords",
  ]
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-analytics-stream-${local.name_suffix}"
    Type = "AnalyticsStream"
  })
}

# DynamoDB table for detection events
resource "aws_dynamodb_table" "detections" {
  name           = "${var.project_name}-detections-${local.name_suffix}"
  billing_mode   = "PROVISIONED"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "StreamName"
  range_key      = "Timestamp"
  
  attribute {
    name = "StreamName"
    type = "S"
  }
  
  attribute {
    name = "Timestamp"
    type = "N"
  }
  
  # Global Secondary Index for querying by detection type
  global_secondary_index {
    name            = "DetectionTypeIndex"
    hash_key        = "DetectionType"
    range_key       = "Timestamp"
    read_capacity   = var.dynamodb_read_capacity
    write_capacity  = var.dynamodb_write_capacity
    projection_type = "ALL"
  }
  
  attribute {
    name = "DetectionType"
    type = "S"
  }
  
  dynamic "server_side_encryption" {
    for_each = var.enable_encryption ? [1] : []
    content {
      enabled     = true
      kms_key_arn = aws_kms_key.video_analytics[0].arn
    }
  }
  
  point_in_time_recovery {
    enabled = true
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-detections-${local.name_suffix}"
    Type = "DetectionEvents"
  })
}

# DynamoDB table for face metadata
resource "aws_dynamodb_table" "faces" {
  name           = "${var.project_name}-faces-${local.name_suffix}"
  billing_mode   = "PROVISIONED"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "FaceId"
  range_key      = "Timestamp"
  
  attribute {
    name = "FaceId"
    type = "S"
  }
  
  attribute {
    name = "Timestamp"
    type = "N"
  }
  
  # Global Secondary Index for querying by stream name
  global_secondary_index {
    name            = "StreamNameIndex"
    hash_key        = "StreamName"
    range_key       = "Timestamp"
    read_capacity   = var.dynamodb_read_capacity
    write_capacity  = var.dynamodb_write_capacity
    projection_type = "ALL"
  }
  
  attribute {
    name = "StreamName"
    type = "S"
  }
  
  dynamic "server_side_encryption" {
    for_each = var.enable_encryption ? [1] : []
    content {
      enabled     = true
      kms_key_arn = aws_kms_key.video_analytics[0].arn
    }
  }
  
  point_in_time_recovery {
    enabled = true
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-faces-${local.name_suffix}"
    Type = "FaceMetadata"
  })
}

# SNS Topic for security alerts
resource "aws_sns_topic" "security_alerts" {
  name = "${var.project_name}-security-alerts-${local.name_suffix}"
  
  dynamic "kms_master_key_id" {
    for_each = var.enable_encryption ? [1] : []
    content {
      kms_master_key_id = aws_kms_key.video_analytics[0].arn
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-security-alerts-${local.name_suffix}"
    Type = "SecurityAlerts"
  })
}

# SNS subscription for email alerts (if email provided)
resource "aws_sns_topic_subscription" "email_alerts" {
  count = var.alert_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Lambda function code for analytics processing
data "archive_file" "analytics_processor_zip" {
  type        = "zip"
  output_path = "${path.module}/analytics_processor.zip"
  
  source {
    content = templatefile("${path.module}/analytics_processor.py", {
      detections_table = aws_dynamodb_table.detections.name
      faces_table      = aws_dynamodb_table.faces.name
      sns_topic_arn    = aws_sns_topic.security_alerts.arn
    })
    filename = "analytics_processor.py"
  }
}

# CloudWatch Log Group for analytics processor
resource "aws_cloudwatch_log_group" "analytics_processor" {
  name              = "/aws/lambda/${var.project_name}-analytics-processor-${local.name_suffix}"
  retention_in_days = var.log_retention_days
  
  dynamic "kms_key_id" {
    for_each = var.enable_encryption ? [1] : []
    content {
      kms_key_id = aws_kms_key.video_analytics[0].arn
    }
  }
  
  tags = local.common_tags
}

# Lambda function for analytics processing
resource "aws_lambda_function" "analytics_processor" {
  filename         = data.archive_file.analytics_processor_zip.output_path
  function_name    = "${var.project_name}-analytics-processor-${local.name_suffix}"
  role            = aws_iam_role.video_analytics_role.arn
  handler         = "analytics_processor.lambda_handler"
  source_code_hash = data.archive_file.analytics_processor_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  
  environment {
    variables = {
      DETECTIONS_TABLE = aws_dynamodb_table.detections.name
      FACES_TABLE      = aws_dynamodb_table.faces.name
      SNS_TOPIC_ARN    = aws_sns_topic.security_alerts.arn
    }
  }
  
  dynamic "kms_key_arn" {
    for_each = var.enable_encryption ? [1] : []
    content {
      kms_key_arn = aws_kms_key.video_analytics[0].arn
    }
  }
  
  depends_on = [
    aws_cloudwatch_log_group.analytics_processor,
    aws_iam_role_policy_attachment.lambda_basic_execution,
  ]
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-analytics-processor-${local.name_suffix}"
    Type = "AnalyticsProcessor"
  })
}

# Event source mapping for Kinesis to Lambda
resource "aws_lambda_event_source_mapping" "kinesis_lambda" {
  event_source_arn  = aws_kinesis_stream.analytics_stream.arn
  function_name     = aws_lambda_function.analytics_processor.arn
  starting_position = "LATEST"
  batch_size        = var.lambda_batch_size
  
  depends_on = [aws_iam_role_policy_attachment.lambda_basic_execution]
}

# Lambda function code for query API
data "archive_file" "query_api_zip" {
  type        = "zip"
  output_path = "${path.module}/query_api.zip"
  
  source {
    content = templatefile("${path.module}/query_api.py", {
      detections_table = aws_dynamodb_table.detections.name
      faces_table      = aws_dynamodb_table.faces.name
      project_name     = var.project_name
    })
    filename = "query_api.py"
  }
}

# CloudWatch Log Group for query API
resource "aws_cloudwatch_log_group" "query_api" {
  count = var.enable_api_gateway ? 1 : 0
  
  name              = "/aws/lambda/${var.project_name}-query-api-${local.name_suffix}"
  retention_in_days = var.log_retention_days
  
  dynamic "kms_key_id" {
    for_each = var.enable_encryption ? [1] : []
    content {
      kms_key_id = aws_kms_key.video_analytics[0].arn
    }
  }
  
  tags = local.common_tags
}

# Lambda function for query API
resource "aws_lambda_function" "query_api" {
  count = var.enable_api_gateway ? 1 : 0
  
  filename         = data.archive_file.query_api_zip.output_path
  function_name    = "${var.project_name}-query-api-${local.name_suffix}"
  role            = aws_iam_role.video_analytics_role.arn
  handler         = "query_api.lambda_handler"
  source_code_hash = data.archive_file.query_api_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = 30
  
  environment {
    variables = {
      DETECTIONS_TABLE = aws_dynamodb_table.detections.name
      FACES_TABLE      = aws_dynamodb_table.faces.name
      PROJECT_NAME     = var.project_name
    }
  }
  
  dynamic "kms_key_arn" {
    for_each = var.enable_encryption ? [1] : []
    content {
      kms_key_arn = aws_kms_key.video_analytics[0].arn
    }
  }
  
  depends_on = [
    aws_cloudwatch_log_group.query_api[0],
    aws_iam_role_policy_attachment.lambda_basic_execution,
  ]
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-query-api-${local.name_suffix}"
    Type = "QueryAPI"
  })
}

# API Gateway for video analytics queries
resource "aws_apigatewayv2_api" "video_analytics_api" {
  count = var.enable_api_gateway ? 1 : 0
  
  name          = "${var.project_name}-api-${local.name_suffix}"
  protocol_type = "HTTP"
  description   = "Video Analytics Query API"
  
  cors_configuration {
    allow_credentials = false
    allow_headers     = ["content-type"]
    allow_methods     = ["GET", "POST", "OPTIONS"]
    allow_origins     = ["*"]
    max_age           = 300
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-api-${local.name_suffix}"
    Type = "QueryAPI"
  })
}

# API Gateway integration with Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
  count = var.enable_api_gateway ? 1 : 0
  
  api_id           = aws_apigatewayv2_api.video_analytics_api[0].id
  integration_type = "AWS_PROXY"
  
  connection_type    = "INTERNET"
  description        = "Lambda integration for video analytics API"
  integration_method = "POST"
  integration_uri    = aws_lambda_function.query_api[0].invoke_arn
}

# API Gateway routes
resource "aws_apigatewayv2_route" "detections_route" {
  count = var.enable_api_gateway ? 1 : 0
  
  api_id    = aws_apigatewayv2_api.video_analytics_api[0].id
  route_key = "GET /detections"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration[0].id}"
}

resource "aws_apigatewayv2_route" "faces_route" {
  count = var.enable_api_gateway ? 1 : 0
  
  api_id    = aws_apigatewayv2_api.video_analytics_api[0].id
  route_key = "GET /faces"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration[0].id}"
}

resource "aws_apigatewayv2_route" "stats_route" {
  count = var.enable_api_gateway ? 1 : 0
  
  api_id    = aws_apigatewayv2_api.video_analytics_api[0].id
  route_key = "GET /stats"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration[0].id}"
}

# API Gateway stage
resource "aws_apigatewayv2_stage" "default" {
  count = var.enable_api_gateway ? 1 : 0
  
  api_id      = aws_apigatewayv2_api.video_analytics_api[0].id
  name        = "$default"
  auto_deploy = true
  
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway[0].arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }
  
  tags = local.common_tags
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway" {
  count = var.enable_api_gateway ? 1 : 0
  
  name              = "/aws/apigateway/${var.project_name}-api-${local.name_suffix}"
  retention_in_days = var.log_retention_days
  
  dynamic "kms_key_id" {
    for_each = var.enable_encryption ? [1] : []
    content {
      kms_key_id = aws_kms_key.video_analytics[0].arn
    }
  }
  
  tags = local.common_tags
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway_lambda" {
  count = var.enable_api_gateway ? 1 : 0
  
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.query_api[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.video_analytics_api[0].execution_arn}/*/*"
}