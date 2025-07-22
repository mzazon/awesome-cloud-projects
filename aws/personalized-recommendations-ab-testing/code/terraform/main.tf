# Data sources for current AWS context
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Unique naming with random suffix
  name_prefix = "${var.project_name}-${random_string.suffix.result}"
  
  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Recipe      = "real-time-recommendations-personalize-ab-testing"
  }
  
  # Account and region info
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# KMS Key for encryption
resource "aws_kms_key" "personalize_key" {
  description             = "KMS key for Personalize recommendation system encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-personalize-key"
  })
}

resource "aws_kms_alias" "personalize_key" {
  name          = "alias/${local.name_prefix}-personalize"
  target_key_id = aws_kms_key.personalize_key.key_id
}

# S3 Bucket for Personalize training data
resource "aws_s3_bucket" "personalize_data" {
  bucket        = "${local.name_prefix}-personalize-data"
  force_destroy = var.s3_force_destroy
  
  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-personalize-data"
    Purpose     = "personalize-training-data"
    CostCenter  = var.enable_cost_allocation_tags ? "ml-infrastructure" : null
  })
}

resource "aws_s3_bucket_versioning" "personalize_data" {
  bucket = aws_s3_bucket.personalize_data.id
  
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "personalize_data" {
  bucket = aws_s3_bucket.personalize_data.id
  
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.personalize_key.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "personalize_data" {
  bucket = aws_s3_bucket.personalize_data.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB Tables
resource "aws_dynamodb_table" "users" {
  name           = "${local.name_prefix}-users"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "UserId"
  
  # Only set capacity if using provisioned mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  
  attribute {
    name = "UserId"
    type = "S"
  }
  
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.personalize_key.arn
  }
  
  point_in_time_recovery {
    enabled = true
  }
  
  tags = merge(local.common_tags, {
    Name       = "${local.name_prefix}-users"
    TableType  = "user-profiles"
    CostCenter = var.enable_cost_allocation_tags ? "data-storage" : null
  })
}

resource "aws_dynamodb_table" "items" {
  name           = "${local.name_prefix}-items"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "ItemId"
  
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  
  attribute {
    name = "ItemId"
    type = "S"
  }
  
  attribute {
    name = "Category"
    type = "S"
  }
  
  global_secondary_index {
    name            = "CategoryIndex"
    hash_key        = "Category"
    projection_type = "ALL"
    
    read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? 5 : null
    write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? 5 : null
  }
  
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.personalize_key.arn
  }
  
  point_in_time_recovery {
    enabled = true
  }
  
  tags = merge(local.common_tags, {
    Name       = "${local.name_prefix}-items"
    TableType  = "item-catalog"
    CostCenter = var.enable_cost_allocation_tags ? "data-storage" : null
  })
}

resource "aws_dynamodb_table" "ab_assignments" {
  name           = "${local.name_prefix}-ab-assignments"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "UserId"
  range_key      = "TestName"
  
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null
  
  attribute {
    name = "UserId"
    type = "S"
  }
  
  attribute {
    name = "TestName"
    type = "S"
  }
  
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.personalize_key.arn
  }
  
  point_in_time_recovery {
    enabled = true
  }
  
  tags = merge(local.common_tags, {
    Name       = "${local.name_prefix}-ab-assignments"
    TableType  = "ab-test-assignments"
    CostCenter = var.enable_cost_allocation_tags ? "experimentation" : null
  })
}

resource "aws_dynamodb_table" "events" {
  name           = "${local.name_prefix}-events"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "UserId"
  range_key      = "Timestamp"
  
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity * 2 : null
  
  attribute {
    name = "UserId"
    type = "S"
  }
  
  attribute {
    name = "Timestamp"
    type = "N"
  }
  
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.personalize_key.arn
  }
  
  point_in_time_recovery {
    enabled = true
  }
  
  # TTL for automatic cleanup of old events
  ttl {
    attribute_name = "ExpirationTime"
    enabled        = true
  }
  
  tags = merge(local.common_tags, {
    Name       = "${local.name_prefix}-events"
    TableType  = "event-stream"
    CostCenter = var.enable_cost_allocation_tags ? "analytics" : null
  })
}

# IAM Role for Lambda functions
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
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-role"
  })
}

# IAM Role for Personalize
resource "aws_iam_role" "personalize_role" {
  name = "${local.name_prefix}-personalize-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "personalize.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-personalize-role"
  })
}

# IAM policies for Lambda role
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.name_prefix}-lambda-policy"
  role = aws_iam_role.lambda_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.users.arn,
          aws_dynamodb_table.items.arn,
          aws_dynamodb_table.ab_assignments.arn,
          aws_dynamodb_table.events.arn,
          "${aws_dynamodb_table.items.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "personalize:GetRecommendations",
          "personalize:PutEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.personalize_key.arn
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:${local.region}:${local.account_id}:function:${local.name_prefix}-*"
      }
    ]
  })
}

# IAM policies for Personalize role
resource "aws_iam_role_policy_attachment" "personalize_full_access" {
  role       = aws_iam_role.personalize_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonPersonalizeFullAccess"
}

resource "aws_iam_role_policy" "personalize_s3_access" {
  name = "${local.name_prefix}-personalize-s3-policy"
  role = aws_iam_role.personalize_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.personalize_data.arn,
          "${aws_s3_bucket.personalize_data.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.personalize_key.arn
      }
    ]
  })
}

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "ab_test_router_logs" {
  name              = "/aws/lambda/${local.name_prefix}-ab-test-router"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.personalize_key.arn
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ab-test-router-logs"
  })
}

resource "aws_cloudwatch_log_group" "recommendation_engine_logs" {
  name              = "/aws/lambda/${local.name_prefix}-recommendation-engine"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.personalize_key.arn
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-recommendation-engine-logs"
  })
}

resource "aws_cloudwatch_log_group" "event_tracker_logs" {
  name              = "/aws/lambda/${local.name_prefix}-event-tracker"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.personalize_key.arn
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-event-tracker-logs"
  })
}

resource "aws_cloudwatch_log_group" "personalize_manager_logs" {
  name              = "/aws/lambda/${local.name_prefix}-personalize-manager"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.personalize_key.arn
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-personalize-manager-logs"
  })
}

# Lambda function source code archives
data "archive_file" "ab_test_router_zip" {
  type        = "zip"
  output_path = "${path.module}/ab_test_router.zip"
  
  source {
    content  = file("${path.module}/lambda_code/ab_test_router.py")
    filename = "ab_test_router.py"
  }
}

data "archive_file" "recommendation_engine_zip" {
  type        = "zip"
  output_path = "${path.module}/recommendation_engine.zip"
  
  source {
    content  = file("${path.module}/lambda_code/recommendation_engine.py")
    filename = "recommendation_engine.py"
  }
}

data "archive_file" "event_tracker_zip" {
  type        = "zip"
  output_path = "${path.module}/event_tracker.zip"
  
  source {
    content  = file("${path.module}/lambda_code/event_tracker.py")
    filename = "event_tracker.py"
  }
}

data "archive_file" "personalize_manager_zip" {
  type        = "zip"
  output_path = "${path.module}/personalize_manager.zip"
  
  source {
    content  = file("${path.module}/lambda_code/personalize_manager.py")
    filename = "personalize_manager.py"
  }
}

# Lambda Functions
resource "aws_lambda_function" "ab_test_router" {
  filename         = data.archive_file.ab_test_router_zip.output_path
  function_name    = "${local.name_prefix}-ab-test-router"
  role            = aws_iam_role.lambda_role.arn
  handler         = "ab_test_router.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.ab_test_router_zip.output_base64sha256
  
  environment {
    variables = {
      AB_ASSIGNMENTS_TABLE             = aws_dynamodb_table.ab_assignments.name
      RECOMMENDATION_ENGINE_FUNCTION   = "${local.name_prefix}-recommendation-engine"
    }
  }
  
  depends_on = [aws_cloudwatch_log_group.ab_test_router_logs]
  
  tags = merge(local.common_tags, {
    Name       = "${local.name_prefix}-ab-test-router"
    Function   = "ab-testing"
    CostCenter = var.enable_cost_allocation_tags ? "experimentation" : null
  })
}

resource "aws_lambda_function" "recommendation_engine" {
  filename         = data.archive_file.recommendation_engine_zip.output_path
  function_name    = "${local.name_prefix}-recommendation-engine"
  role            = aws_iam_role.lambda_role.arn
  handler         = "recommendation_engine.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.recommendation_engine_zip.output_base64sha256
  
  environment {
    variables = {
      ITEMS_TABLE  = aws_dynamodb_table.items.name
      EVENTS_TABLE = aws_dynamodb_table.events.name
      USERS_TABLE  = aws_dynamodb_table.users.name
    }
  }
  
  depends_on = [aws_cloudwatch_log_group.recommendation_engine_logs]
  
  tags = merge(local.common_tags, {
    Name       = "${local.name_prefix}-recommendation-engine"
    Function   = "recommendations"
    CostCenter = var.enable_cost_allocation_tags ? "ml-inference" : null
  })
}

resource "aws_lambda_function" "event_tracker" {
  filename         = data.archive_file.event_tracker_zip.output_path
  function_name    = "${local.name_prefix}-event-tracker"
  role            = aws_iam_role.lambda_role.arn
  handler         = "event_tracker.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.event_tracker_zip.output_base64sha256
  
  environment {
    variables = {
      EVENTS_TABLE = aws_dynamodb_table.events.name
    }
  }
  
  depends_on = [aws_cloudwatch_log_group.event_tracker_logs]
  
  tags = merge(local.common_tags, {
    Name       = "${local.name_prefix}-event-tracker"
    Function   = "event-tracking"
    CostCenter = var.enable_cost_allocation_tags ? "analytics" : null
  })
}

resource "aws_lambda_function" "personalize_manager" {
  filename         = data.archive_file.personalize_manager_zip.output_path
  function_name    = "${local.name_prefix}-personalize-manager"
  role            = aws_iam_role.lambda_role.arn
  handler         = "personalize_manager.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 60
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.personalize_manager_zip.output_base64sha256
  
  depends_on = [aws_cloudwatch_log_group.personalize_manager_logs]
  
  tags = merge(local.common_tags, {
    Name       = "${local.name_prefix}-personalize-manager"
    Function   = "personalize-management"
    CostCenter = var.enable_cost_allocation_tags ? "ml-infrastructure" : null
  })
}

# API Gateway
resource "aws_apigatewayv2_api" "recommendation_api" {
  name          = "${local.name_prefix}-recommendation-api"
  protocol_type = "HTTP"
  description   = "Real-time recommendation API with A/B testing"
  
  cors_configuration {
    allow_origins     = ["*"]
    allow_methods     = ["GET", "POST", "OPTIONS"]
    allow_headers     = ["content-type", "x-amz-date", "authorization"]
    expose_headers    = ["x-request-id"]
    max_age          = 300
    allow_credentials = false
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-recommendation-api"
  })
}

# API Gateway Stage
resource "aws_apigatewayv2_stage" "recommendation_api_stage" {
  api_id      = aws_apigatewayv2_api.recommendation_api.id
  name        = var.api_gateway_stage_name
  auto_deploy = true
  
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      error          = "$context.error.message"
      integrationError = "$context.integration.error"
    })
  }
  
  default_route_settings {
    detailed_metrics_enabled = true
    throttling_burst_limit    = 100
    throttling_rate_limit     = 50
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api-stage"
  })
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/${local.name_prefix}-recommendation-api"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.personalize_key.arn
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api-gateway-logs"
  })
}

# Lambda integrations
resource "aws_apigatewayv2_integration" "ab_test_router_integration" {
  api_id           = aws_apigatewayv2_api.recommendation_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.ab_test_router.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "event_tracker_integration" {
  api_id           = aws_apigatewayv2_api.recommendation_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.event_tracker.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

# API Gateway routes
resource "aws_apigatewayv2_route" "recommendations_route" {
  api_id    = aws_apigatewayv2_api.recommendation_api.id
  route_key = "POST /recommendations"
  target    = "integrations/${aws_apigatewayv2_integration.ab_test_router_integration.id}"
}

resource "aws_apigatewayv2_route" "events_route" {
  api_id    = aws_apigatewayv2_api.recommendation_api.id
  route_key = "POST /events"
  target    = "integrations/${aws_apigatewayv2_integration.event_tracker_integration.id}"
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "ab_test_router_api_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ab_test_router.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.recommendation_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "event_tracker_api_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.event_tracker.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.recommendation_api.execution_arn}/*/*"
}

# CloudWatch Dashboard for monitoring
resource "aws_cloudwatch_dashboard" "personalize_dashboard" {
  dashboard_name = "${local.name_prefix}-personalize-dashboard"
  
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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.ab_test_router.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "A/B Test Router Lambda Metrics"
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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.recommendation_engine.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "Recommendation Engine Lambda Metrics"
          period  = 300
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
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.users.name],
            [".", "ConsumedWriteCapacityUnits", ".", "."],
            [".", "UserErrors", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = local.region
          title   = "DynamoDB Users Table Metrics"
          period  = 300
        }
      }
    ]
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_error_rate" {
  for_each = {
    ab_test_router        = aws_lambda_function.ab_test_router.function_name
    recommendation_engine = aws_lambda_function.recommendation_engine.function_name
    event_tracker        = aws_lambda_function.event_tracker.function_name
  }
  
  alarm_name          = "${local.name_prefix}-${each.key}-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda error rate for ${each.key}"
  
  dimensions = {
    FunctionName = each.value
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${each.key}-error-alarm"
  })
}

# ElastiCache Subnet Group (for future caching implementation)
resource "aws_elasticache_subnet_group" "personalize_cache" {
  count      = var.enable_vpc_endpoints ? 1 : 0
  name       = "${local.name_prefix}-cache-subnet-group"
  subnet_ids = data.aws_subnets.default[0].ids
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cache-subnet-group"
  })
}

# Get default VPC and subnets for ElastiCache
data "aws_vpc" "default" {
  count   = var.enable_vpc_endpoints ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = var.enable_vpc_endpoints ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
}