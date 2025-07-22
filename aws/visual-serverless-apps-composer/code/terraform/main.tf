# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source to get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values for consistent resource naming and configuration
locals {
  resource_suffix = random_id.suffix.hex
  common_name     = "${var.project_name}-${var.environment}-${local.resource_suffix}"
  
  # Common tags to be applied to all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "building-visual-serverless-applications"
    },
    var.additional_tags
  )
}

# ============================================================================
# IAM ROLES AND POLICIES
# ============================================================================

# IAM Role for Lambda function execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.common_name}-lambda-role"

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

# IAM Policy for Lambda function to access DynamoDB
resource "aws_iam_role_policy" "lambda_dynamodb_policy" {
  name = "${local.common_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          aws_dynamodb_table.users_table.arn,
          "${aws_dynamodb_table.users_table.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.dead_letter_queue.arn
      }
    ]
  })
}

# IAM Policy for Lambda function X-Ray tracing
resource "aws_iam_role_policy" "lambda_xray_policy" {
  count = var.enable_xray_tracing ? 1 : 0
  name  = "${local.common_name}-lambda-xray-policy"
  role  = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach AWS managed policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# ============================================================================
# DYNAMODB TABLE
# ============================================================================

# DynamoDB table for storing user data
resource "aws_dynamodb_table" "users_table" {
  name           = "${local.common_name}-users-table"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "id"
  
  # Configure read/write capacity only for PROVISIONED billing mode
  read_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_read_capacity : null
  write_capacity = var.dynamodb_billing_mode == "PROVISIONED" ? var.dynamodb_write_capacity : null

  attribute {
    name = "id"
    type = "S"
  }

  # Enable server-side encryption
  server_side_encryption {
    enabled = true
  }

  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = var.dynamodb_point_in_time_recovery
  }

  # Deletion protection for production environments
  deletion_protection_enabled = var.environment == "prod" ? true : false

  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name}-users-table"
    }
  )
}

# ============================================================================
# SQS DEAD LETTER QUEUE
# ============================================================================

# SQS Dead Letter Queue for failed Lambda invocations
resource "aws_sqs_queue" "dead_letter_queue" {
  name                       = "${local.common_name}-users-dlq"
  message_retention_seconds  = var.sqs_message_retention_seconds
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  
  # Enable server-side encryption
  sqs_managed_sse_enabled = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name}-users-dlq"
    }
  )
}

# ============================================================================
# CLOUDWATCH LOG GROUPS
# ============================================================================

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${local.common_name}-users-function"
  retention_in_days = var.cloudwatch_log_retention_days
  
  # Enable encryption
  kms_key_id = aws_kms_key.log_encryption_key.arn

  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name}-lambda-logs"
    }
  )
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway_log_group" {
  name              = "/aws/apigateway/${local.common_name}-api"
  retention_in_days = var.cloudwatch_log_retention_days
  
  # Enable encryption
  kms_key_id = aws_kms_key.log_encryption_key.arn

  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name}-api-logs"
    }
  )
}

# ============================================================================
# KMS KEY FOR ENCRYPTION
# ============================================================================

# KMS Key for encrypting CloudWatch logs
resource "aws_kms_key" "log_encryption_key" {
  description             = "KMS key for encrypting CloudWatch logs"
  deletion_window_in_days = 7
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
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
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

  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name}-log-encryption-key"
    }
  )
}

# KMS Key Alias for easier reference
resource "aws_kms_alias" "log_encryption_key_alias" {
  name          = "alias/${local.common_name}-log-encryption"
  target_key_id = aws_kms_key.log_encryption_key.key_id
}

# ============================================================================
# LAMBDA FUNCTION
# ============================================================================

# Create Lambda function deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/${local.common_name}-lambda.zip"
  
  source {
    content = <<-EOF
import json
import boto3
import os
from decimal import Decimal
from botocore.exceptions import ClientError

# Initialize DynamoDB resource with error handling
try:
    dynamodb = boto3.resource('dynamodb')
    table_name = os.environ.get('TABLE_NAME', 'UsersTable')
    table = dynamodb.Table(table_name)
except Exception as e:
    print(f"Error initializing DynamoDB: {str(e)}")
    raise

def lambda_handler(event, context):
    """
    Lambda function to handle CRUD operations for users
    Supports GET (list users) and POST (create user) operations
    """
    try:
        http_method = event.get('httpMethod', '')
        
        if http_method == 'GET':
            # Retrieve all users from DynamoDB
            response = table.scan()
            items = response.get('Items', [])
            
            # Convert Decimal objects to float for JSON serialization
            for item in items:
                for key, value in item.items():
                    if isinstance(value, Decimal):
                        item[key] = float(value)
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'users': items,
                    'count': len(items)
                })
            }
        
        elif http_method == 'POST':
            # Create new user in DynamoDB
            body = json.loads(event.get('body', '{}'))
            
            # Validate required fields
            if not body.get('id') or not body.get('name'):
                return {
                    'statusCode': 400,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({
                        'error': 'Missing required fields: id and name'
                    })
                }
            
            # Store user data
            table.put_item(Item=body)
            
            return {
                'statusCode': 201,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'message': 'User created successfully',
                    'user': body
                })
            }
        
        else:
            return {
                'statusCode': 405,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'error': f'Method {http_method} not allowed'
                })
            }
            
    except ClientError as e:
        print(f"DynamoDB error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'error': 'Database operation failed'
            })
        }
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'error': 'Invalid JSON in request body'
            })
        }
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'error': 'Internal server error'
            })
        }
EOF
    filename = "users.py"
  }
}

# Lambda function for user operations
resource "aws_lambda_function" "users_function" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.common_name}-users-function"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "users.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  architectures   = [var.lambda_architecture]
  
  # Reserved concurrency to control scaling
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  # Dead letter queue configuration
  dead_letter_config {
    target_arn = aws_sqs_queue.dead_letter_queue.arn
  }

  # Environment variables
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.users_table.name
      LOG_LEVEL  = "INFO"
    }
  }

  # X-Ray tracing configuration
  tracing_config {
    mode = var.enable_xray_tracing ? "Active" : "PassThrough"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_dynamodb_policy,
    aws_cloudwatch_log_group.lambda_log_group,
  ]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name}-users-function"
    }
  )
}

# Lambda permission for API Gateway to invoke the function
resource "aws_lambda_permission" "api_gateway_lambda_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.users_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.serverless_api.execution_arn}/*/*"
}

# ============================================================================
# API GATEWAY
# ============================================================================

# REST API Gateway
resource "aws_api_gateway_rest_api" "serverless_api" {
  name        = "${local.common_name}-api"
  description = "Serverless API for ${var.environment} environment"
  
  # Enable binary media types if needed
  binary_media_types = ["application/octet-stream"]

  # API Gateway endpoint configuration
  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name}-api"
    }
  )
}

# API Gateway Resource for /users
resource "aws_api_gateway_resource" "users_resource" {
  rest_api_id = aws_api_gateway_rest_api.serverless_api.id
  parent_id   = aws_api_gateway_rest_api.serverless_api.root_resource_id
  path_part   = "users"
}

# API Gateway Method for GET /users
resource "aws_api_gateway_method" "users_get_method" {
  rest_api_id   = aws_api_gateway_rest_api.serverless_api.id
  resource_id   = aws_api_gateway_resource.users_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# API Gateway Method for POST /users
resource "aws_api_gateway_method" "users_post_method" {
  rest_api_id   = aws_api_gateway_rest_api.serverless_api.id
  resource_id   = aws_api_gateway_resource.users_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# API Gateway Integration for GET /users
resource "aws_api_gateway_integration" "users_get_integration" {
  rest_api_id = aws_api_gateway_rest_api.serverless_api.id
  resource_id = aws_api_gateway_resource.users_resource.id
  http_method = aws_api_gateway_method.users_get_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.users_function.invoke_arn
}

# API Gateway Integration for POST /users
resource "aws_api_gateway_integration" "users_post_integration" {
  rest_api_id = aws_api_gateway_rest_api.serverless_api.id
  resource_id = aws_api_gateway_resource.users_resource.id
  http_method = aws_api_gateway_method.users_post_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.users_function.invoke_arn
}

# API Gateway CORS Configuration for OPTIONS method
resource "aws_api_gateway_method" "users_options_method" {
  rest_api_id   = aws_api_gateway_rest_api.serverless_api.id
  resource_id   = aws_api_gateway_resource.users_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# API Gateway Integration for OPTIONS method (CORS)
resource "aws_api_gateway_integration" "users_options_integration" {
  rest_api_id = aws_api_gateway_rest_api.serverless_api.id
  resource_id = aws_api_gateway_resource.users_resource.id
  http_method = aws_api_gateway_method.users_options_method.http_method

  type = "MOCK"
  
  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

# API Gateway Method Response for OPTIONS (CORS)
resource "aws_api_gateway_method_response" "users_options_response" {
  rest_api_id = aws_api_gateway_rest_api.serverless_api.id
  resource_id = aws_api_gateway_resource.users_resource.id
  http_method = aws_api_gateway_method.users_options_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

# API Gateway Integration Response for OPTIONS (CORS)
resource "aws_api_gateway_integration_response" "users_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.serverless_api.id
  resource_id = aws_api_gateway_resource.users_resource.id
  http_method = aws_api_gateway_method.users_options_method.http_method
  status_code = aws_api_gateway_method_response.users_options_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'${join(",", var.cors_allow_headers)}'"
    "method.response.header.Access-Control-Allow-Methods" = "'${join(",", var.cors_allow_methods)}'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${join(",", var.cors_allow_origins)}'"
  }
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_integration.users_get_integration,
    aws_api_gateway_integration.users_post_integration,
    aws_api_gateway_integration.users_options_integration,
  ]

  rest_api_id = aws_api_gateway_rest_api.serverless_api.id
  
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.users_resource.id,
      aws_api_gateway_method.users_get_method.id,
      aws_api_gateway_method.users_post_method.id,
      aws_api_gateway_method.users_options_method.id,
      aws_api_gateway_integration.users_get_integration.id,
      aws_api_gateway_integration.users_post_integration.id,
      aws_api_gateway_integration.users_options_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API Gateway Stage
resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.serverless_api.id
  stage_name    = var.api_gateway_stage_name

  # Enable X-Ray tracing
  xray_tracing_enabled = var.enable_xray_tracing

  # Configure access logging
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_log_group.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name}-api-stage"
    }
  )
}

# API Gateway Method Settings for detailed monitoring
resource "aws_api_gateway_method_settings" "api_settings" {
  rest_api_id = aws_api_gateway_rest_api.serverless_api.id
  stage_name  = aws_api_gateway_stage.api_stage.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled        = var.enable_detailed_monitoring
    logging_level         = "INFO"
    data_trace_enabled    = true
    throttling_rate_limit = var.api_gateway_throttle_rate_limit
    throttling_burst_limit = var.api_gateway_throttle_burst_limit
  }
}

# ============================================================================
# CLOUDWATCH ALARMS
# ============================================================================

# CloudWatch Alarm for Lambda function errors
resource "aws_cloudwatch_metric_alarm" "lambda_error_alarm" {
  alarm_name          = "${local.common_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = [] # Add SNS topic ARN here for notifications

  dimensions = {
    FunctionName = aws_lambda_function.users_function.function_name
  }

  tags = local.common_tags
}

# CloudWatch Alarm for Lambda function duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration_alarm" {
  alarm_name          = "${local.common_name}-lambda-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = "25000"  # 25 seconds
  alarm_description   = "This metric monitors lambda duration"
  alarm_actions       = [] # Add SNS topic ARN here for notifications

  dimensions = {
    FunctionName = aws_lambda_function.users_function.function_name
  }

  tags = local.common_tags
}

# CloudWatch Alarm for API Gateway 4XX errors
resource "aws_cloudwatch_metric_alarm" "api_gateway_4xx_alarm" {
  alarm_name          = "${local.common_name}-api-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors API Gateway 4XX errors"
  alarm_actions       = [] # Add SNS topic ARN here for notifications

  dimensions = {
    ApiName   = aws_api_gateway_rest_api.serverless_api.name
    Stage     = aws_api_gateway_stage.api_stage.stage_name
  }

  tags = local.common_tags
}

# CloudWatch Alarm for API Gateway 5XX errors
resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx_alarm" {
  alarm_name          = "${local.common_name}-api-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors API Gateway 5XX errors"
  alarm_actions       = [] # Add SNS topic ARN here for notifications

  dimensions = {
    ApiName   = aws_api_gateway_rest_api.serverless_api.name
    Stage     = aws_api_gateway_stage.api_stage.stage_name
  }

  tags = local.common_tags
}